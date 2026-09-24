public with sharing class ConduitCmmController {

    // 5MB cap on the raw zip because Apex heap tops out around 6MB per callout;
    // we need headroom for base64 encoding (~+33%) + JSON envelope.
    private static final Integer MAX_ZIP_BYTES = 5 * 1024 * 1024;

    /**
     * Orchestrates a new CMM version:
     *   1. Fetch the uploaded zip bytes from ContentVersion
     *   2. POST them (base64) to the Next.js /api/sf/cmm/ingest route
     *   3. On success: store the assembled CMM JSON as a new ContentVersion, create
     *      a Conduit_CMM__c row with the next version number, mark it active, and
     *      deactivate any previous active row for the same assessment.
     *   4. On failure: record Status=Failed + Error_Message so the LWC can display.
     */
    @AuraEnabled
    public static Conduit_CMM__c uploadAndIngest(String assessmentId, String zipContentDocId) {
        if (String.isBlank(assessmentId) || String.isBlank(zipContentDocId)) {
            throw new AuraHandledException('assessmentId and zipContentDocId are required.');
        }

        // ── Phase 1: SOQL only (no DML). Apex forbids callouts after DML in the
        // same transaction, so we gather everything we need first, do the HTTP
        // round-trip, and only then touch the database.
        String sourcePlatform = getSourcePlatformFromAssessment(assessmentId);
        if (String.isBlank(sourcePlatform)) {
            throw new AuraHandledException(
                'Set Current_Platform__c on the assessment record before uploading — the ingester needs it to pick the right adapter.'
            );
        }

        Blob zipBlob = getContentVersionData(zipContentDocId);
        if (zipBlob.size() > MAX_ZIP_BYTES) {
            throw new AuraHandledException(
                'Zip is ' + (zipBlob.size() / 1024 / 1024) + 'MB — over the 5MB Apex heap limit. ' +
                'Reduce the export or contact engineering about S3-backed uploads.'
            );
        }

        Decimal nextVersion = getNextVersion(assessmentId);

        // ── Phase 2: callout. Wrapped so exceptions still land as a Failed row.
        IngestResponse res = null;
        String calloutError = null;
        try {
            res = callIngest(sourcePlatform, zipBlob);
        } catch (Exception e) {
            calloutError = 'Callout failed: ' + e.getMessage();
        }

        // ── Phase 3: DML. All callouts are done; safe to write now.
        Conduit_CMM__c rec = new Conduit_CMM__c(
            Assessment_Request__c     = assessmentId,
            Source_Platform__c        = sourcePlatform,
            Uploaded_At__c            = DateTime.now(),
            Uploaded_By__c            = UserInfo.getUserId(),
            Version__c                = nextVersion,
            Raw_Zip_Content_Doc_Id__c = zipContentDocId,
            Is_Active__c              = false
        );

        // Failure paths: persist with Status=Failed and return.
        if (calloutError != null) {
            rec.Status__c        = 'Failed';
            rec.Error_Message__c = calloutError;
            insert rec;
            return rec;
        }
        if (!res.success) {
            rec.Status__c        = 'Failed';
            rec.Error_Message__c = String.isBlank(res.errorMessage) ? 'Unknown ingest failure' : res.errorMessage;
            insert rec;
            return rec;
        }

        // Success. Insert first so rec.Id can parent the ContentVersion.
        rec.Status__c        = 'Ready';
        rec.Is_Active__c     = true;
        rec.Object_Counts__c = res.summary;
        insert rec;

        rec.Cmm_Content_Doc_Id__c = saveAssembledCmm(rec.Id, rec.Version__c, res.cmmJson);

        List<Conduit_CMM__c> priorActive = [
            SELECT Id FROM Conduit_CMM__c
            WHERE Assessment_Request__c = :assessmentId AND Is_Active__c = true AND Id != :rec.Id
        ];
        for (Conduit_CMM__c a : priorActive) a.Is_Active__c = false;
        if (!priorActive.isEmpty()) update priorActive;

        update rec;
        return rec;
    }

    /** List all CMM versions for an assessment, newest first. */
    @AuraEnabled(cacheable=true)
    public static List<Conduit_CMM__c> listVersions(String assessmentId) {
        return [
            SELECT Id, Name, Version__c, Source_Platform__c, Status__c, Is_Active__c,
                   Uploaded_At__c, Uploaded_By__r.Name, Object_Counts__c, Error_Message__c,
                   Raw_Zip_Content_Doc_Id__c, Cmm_Content_Doc_Id__c
            FROM Conduit_CMM__c
            WHERE Assessment_Request__c = :assessmentId
            ORDER BY Version__c DESC
            LIMIT 25
        ];
    }

    /** Manually set a specific version as active (rollback / switch). */
    @AuraEnabled
    public static void activateVersion(String cmmId) {
        Conduit_CMM__c target = [
            SELECT Id, Assessment_Request__c FROM Conduit_CMM__c WHERE Id = :cmmId LIMIT 1
        ];
        List<Conduit_CMM__c> others = [
            SELECT Id FROM Conduit_CMM__c
            WHERE Assessment_Request__c = :target.Assessment_Request__c
              AND Is_Active__c = true AND Id != :cmmId
        ];
        for (Conduit_CMM__c a : others) a.Is_Active__c = false;
        target.Is_Active__c = true;
        if (!others.isEmpty()) update others;
        update target;
    }

    /**
     * Returns the raw JSON string of the currently-active CMM for an assessment,
     * or null if none. Used by the other Conduit controllers when building the
     * POST body sent to /api/sf/* routes.
     */
    public static String getActiveCmmContent(String assessmentId) {
        if (String.isBlank(assessmentId)) return null;
        try {
            List<Conduit_CMM__c> active = [
                SELECT Cmm_Content_Doc_Id__c FROM Conduit_CMM__c
                WHERE Assessment_Request__c = :assessmentId AND Is_Active__c = true
                LIMIT 1
            ];
            if (active.isEmpty() || String.isBlank(active[0].Cmm_Content_Doc_Id__c)) return null;
            Blob b = getContentVersionData(active[0].Cmm_Content_Doc_Id__c);
            return b.toString();
        } catch (Exception e) {
            System.debug('ConduitCmmController.getActiveCmmContent failed: ' + e.getMessage());
            return null;
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────────

    private static String getSourcePlatformFromAssessment(String assessmentId) {
        List<GTM_Assessment_Request__c> rows = [
            SELECT Current_Platform__c FROM GTM_Assessment_Request__c
            WHERE Id = :assessmentId LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Current_Platform__c;
    }

    private static Decimal getNextVersion(String assessmentId) {
        List<Conduit_CMM__c> latest = [
            SELECT Version__c FROM Conduit_CMM__c
            WHERE Assessment_Request__c = :assessmentId
            ORDER BY Version__c DESC LIMIT 1
        ];
        return latest.isEmpty() ? 1 : (latest[0].Version__c + 1);
    }

    private static Blob getContentVersionData(String contentDocId) {
        List<ContentVersion> versions = [
            SELECT VersionData FROM ContentVersion
            WHERE ContentDocumentId = :contentDocId AND IsLatest = true
            LIMIT 1
        ];
        if (versions.isEmpty()) throw new AuraHandledException('File not found (ContentDocumentId: ' + contentDocId + ')');
        return versions[0].VersionData;
    }

    private static String saveAssembledCmm(Id cmmRecordId, Decimal version, String cmmJson) {
        ContentVersion cv = new ContentVersion(
            Title            = 'cmm-v' + Integer.valueOf(version) + '.json',
            PathOnClient     = 'cmm-v' + Integer.valueOf(version) + '.json',
            VersionData      = Blob.valueOf(cmmJson),
            FirstPublishLocationId = cmmRecordId
        );
        insert cv;
        // The ContentDocumentId isn't populated on the ContentVersion until after insert.
        ContentVersion inserted = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        return inserted.ContentDocumentId;
    }

    // ── HTTP callout ─────────────────────────────────────────────────────────────

    private class IngestResponse {
        Boolean success;
        String  cmmJson;      // stringified CMM (what we store back into ContentVersion)
        String  summary;      // small human-readable summary for Object_Counts__c
        String  errorMessage;
    }

    private static IngestResponse callIngest(String sourcePlatform, Blob zipBlob) {
        Conduit_Settings__c cfg = Conduit_Settings__c.getInstance();
        if (cfg == null || String.isBlank(cfg.API_URL__c)) {
            throw new AuraHandledException(
                'Conduit is not configured. Go to Setup → Custom Settings → Conduit Settings and enter the API URL.'
            );
        }

        String bodyJson = JSON.serialize(new Map<String, Object>{
            'platform'  => sourcePlatform,
            'zipBase64' => EncodingUtil.base64Encode(zipBlob)
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.API_URL__c + '/api/sf/cmm/ingest');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        if (String.isNotBlank(cfg.API_Key__c)) req.setHeader('X-Conduit-Key', cfg.API_Key__c);
        req.setTimeout(120000);
        req.setBody(bodyJson);

        HttpResponse http = new Http().send(req);
        Integer code = http.getStatusCode();
        String responseBody = http.getBody();

        IngestResponse r = new IngestResponse();
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            r.success = code == 200 && (Boolean) parsed.get('success') == true;
            if (r.success) {
                // Re-serialize the cmm object to a JSON string for storage.
                r.cmmJson = JSON.serialize(parsed.get('cmm'));
                Map<String, Object> s = (Map<String, Object>) parsed.get('summary');
                r.summary = s != null
                    ? String.valueOf(s.get('dataObjects')) + ' data obj (' + String.valueOf(s.get('fields')) + ' fields) · ' +
                      String.valueOf(s.get('audiences')) + ' audiences · ' +
                      String.valueOf(s.get('contentAssets')) + ' assets'
                    : null;
            } else {
                r.errorMessage = String.valueOf(parsed.get('error'));
                if (String.isBlank(r.errorMessage)) r.errorMessage = 'HTTP ' + code;
            }
        } catch (Exception e) {
            r.success = false;
            r.errorMessage = 'HTTP ' + code + ' — could not parse response: ' + responseBody.left(300);
        }
        return r;
    }
}