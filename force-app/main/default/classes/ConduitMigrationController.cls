public with sharing class ConduitMigrationController {

    // Custom Metadata Type name that holds the SFMC target credentials.
    // SA populates one record (DeveloperName is the picker) via Setup →
    // Custom Metadata Types → Conduit Target SFMC → Manage Records.
    private static final String TARGET_MDT = 'Conduit_Target_SFMC__mdt';

    // ── Load the runbook for the LWC's step picker ──────────────────────────
    // Convenience wrapper — returns the same JSON the Runbook tab uses so the
    // Execute panel can reuse it without a second callout.
    @AuraEnabled
    public static String getRunbookForExecute(String assessmentId) {
        return ConduitPlanController.getMigrationRunbook(assessmentId);
    }

    // ── List available target configs ───────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> listTargetConfigs() {
        List<Conduit_Target_SFMC__mdt> rows = [
            SELECT DeveloperName, MasterLabel, Description__c, Auth_Base_URI__c
            FROM Conduit_Target_SFMC__mdt
            ORDER BY MasterLabel
        ];
        List<Map<String, String>> out = new List<Map<String, String>>();
        for (Conduit_Target_SFMC__mdt r : rows) {
            out.add(new Map<String, String>{
                'developerName' => r.DeveloperName,
                'label'         => r.MasterLabel,
                'description'   => r.Description__c,
                'authBaseUri'   => r.Auth_Base_URI__c
            });
        }
        return out;
    }

    // ── Execute a migration run ─────────────────────────────────────────────
    // Creates the Conduit_Migration_Run__c parent + Conduit_Migration_Run_Step__c
    // children based on what the Next.js /api/sf/migration-execute route
    // returned. Fires ONE callout to Next.js — which does the multi-step SFMC
    // work — so we stay under the Apex callout limit for moderate step counts.
    //
    // For very large runs (many hundreds of steps), we would batch this into
    // multiple Next.js calls chained by a Queueable — deferred to Phase A.5.
    @AuraEnabled
    public static Id executeRun(
        String assessmentId,
        List<Integer> stepOrders,
        Boolean rollbackEnabled,
        String targetConfigName
    ) {
        if (String.isBlank(assessmentId)) {
            throw new AuraHandledException('assessmentId is required.');
        }
        if (String.isBlank(targetConfigName)) {
            throw new AuraHandledException('targetConfigName is required — pick a Conduit Target SFMC record configured in Setup.');
        }

        // ── Phase 1: SOQL only (no DML). Apex forbids callouts after DML. ──
        Conduit_Target_SFMC__mdt target = getTargetConfig(targetConfigName);
        if (target == null) {
            throw new AuraHandledException('No Conduit Target SFMC record found with DeveloperName = ' + targetConfigName);
        }
        if (String.isBlank(target.Client_Id__c) || String.isBlank(target.Client_Secret__c) || String.isBlank(target.Auth_Base_URI__c)) {
            throw new AuraHandledException('Target config "' + targetConfigName + '" is missing Client_Id, Client_Secret, or Auth_Base_URI.');
        }

        // Lookup the active CMM version (for the CMM_Version__c pointer).
        Id activeCmmId = null;
        List<Conduit_CMM__c> activeCmms = [
            SELECT Id FROM Conduit_CMM__c
            WHERE Assessment_Request__c = :assessmentId AND Is_Active__c = true LIMIT 1
        ];
        if (!activeCmms.isEmpty()) activeCmmId = activeCmms[0].Id;

        // ── Phase 2: callout to Next.js /api/sf/migration-execute ──────────
        String body = buildExecuteRequestBody(assessmentId, stepOrders, target);
        ExecuteResponse res = callConduitExecute(body);

        // ── Phase 3: DML — persist the run + steps ──────────────────────────
        Conduit_Migration_Run__c run = new Conduit_Migration_Run__c(
            Assessment_Request__c = assessmentId,
            CMM_Version__c        = activeCmmId,
            Status__c             = res.failed > 0 ? 'Failed' : 'Complete',
            Started_At__c         = res.runStartedAt,
            Completed_At__c       = res.runCompletedAt,
            Started_By__c         = UserInfo.getUserId(),
            Total_Steps__c        = res.total,
            Steps_Succeeded__c    = res.applied,
            Steps_Failed__c       = res.failed,
            Steps_Skipped__c      = res.skipped,
            Rollback_Enabled__c   = rollbackEnabled == true,
            Target_Config__c      = targetConfigName,
            Error_Summary__c      = res.errorSummary,
            Skip_Summary__c       = res.skipSummary
        );
        insert run;

        if (!res.stepResults.isEmpty()) {
            List<Conduit_Migration_Run_Step__c> childRows = new List<Conduit_Migration_Run_Step__c>();
            for (StepResult s : res.stepResults) {
                childRows.add(new Conduit_Migration_Run_Step__c(
                    Migration_Run__c        = run.Id,
                    Order__c                = s.order,
                    Group__c                = s.groupName,
                    Entity_Type__c          = s.entityType,
                    Entity_Name__c          = s.entityName,
                    Action__c               = s.action,
                    Status__c               = statusPicklistValue(s.status),
                    Source_Canonical_Id__c  = s.sourceCanonicalId,
                    External_Id__c          = s.externalId,
                    Preview_Text__c         = s.previewText,
                    Error_Message__c        = String.isNotBlank(s.error) ? s.error : s.detail
                ));
            }
            insert childRows;
        }

        return run.Id;
    }

    // ── List runs for the assessment (for the LWC's history panel) ───────
    @AuraEnabled(cacheable=true)
    public static List<Conduit_Migration_Run__c> listRuns(String assessmentId) {
        return [
            SELECT Id, Name, Status__c, Started_At__c, Completed_At__c,
                   Total_Steps__c, Steps_Succeeded__c, Steps_Failed__c, Steps_Skipped__c,
                   Rollback_Enabled__c, Target_Config__c, Started_By__r.Name,
                   Error_Summary__c, Skip_Summary__c
            FROM Conduit_Migration_Run__c
            WHERE Assessment_Request__c = :assessmentId
            ORDER BY Started_At__c DESC
            LIMIT 20
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Conduit_Migration_Run_Step__c> listRunSteps(Id runId) {
        return [
            SELECT Id, Name, Order__c, Group__c, Entity_Type__c, Entity_Name__c,
                   Action__c, Status__c, Source_Canonical_Id__c, External_Id__c,
                   Preview_Text__c, Error_Message__c
            FROM Conduit_Migration_Run_Step__c
            WHERE Migration_Run__c = :runId
            ORDER BY Order__c ASC
        ];
    }

    // ── Most-recent outcome per canonical entity, across ALL runs ──────────
    // Powers the "already migrated / failed / not yet" badges on the runbook.
    // Returns every step, ordered so the FIRST occurrence of each
    // Source_Canonical_Id__c is the most recent one — the JS side just
    // reduces to a Map<canonicalId, firstSeen>.
    @AuraEnabled(cacheable=true)
    public static List<StepOutcome> listStepOutcomes(String assessmentId) {
        List<Conduit_Migration_Run_Step__c> rows = [
            SELECT Source_Canonical_Id__c,
                   Status__c,
                   Error_Message__c,
                   External_Id__c,
                   Migration_Run__c,
                   Migration_Run__r.Name,
                   Migration_Run__r.Started_At__c
            FROM Conduit_Migration_Run_Step__c
            WHERE Migration_Run__r.Assessment_Request__c = :assessmentId
              AND Source_Canonical_Id__c != null
            ORDER BY Migration_Run__r.Started_At__c DESC, Order__c ASC
            LIMIT 5000
        ];
        List<StepOutcome> out = new List<StepOutcome>();
        for (Conduit_Migration_Run_Step__c r : rows) {
            StepOutcome o = new StepOutcome();
            o.sourceCanonicalId = r.Source_Canonical_Id__c;
            o.status            = r.Status__c;
            o.errorMessage      = r.Error_Message__c;
            o.externalId        = r.External_Id__c;
            o.runId             = r.Migration_Run__c;
            o.runName           = r.Migration_Run__r.Name;
            o.runStartedAt      = r.Migration_Run__r.Started_At__c;
            out.add(o);
        }
        return out;
    }

    public class StepOutcome {
        @AuraEnabled public String sourceCanonicalId;
        @AuraEnabled public String status;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String externalId;
        @AuraEnabled public Id     runId;
        @AuraEnabled public String runName;
        @AuraEnabled public DateTime runStartedAt;
    }

    // ── Private helpers ────────────────────────────────────────────────────

    private static Conduit_Target_SFMC__mdt getTargetConfig(String developerName) {
        List<Conduit_Target_SFMC__mdt> rows = [
            SELECT DeveloperName, MasterLabel, Client_Id__c, Client_Secret__c,
                   Auth_Base_URI__c, Description__c
            FROM Conduit_Target_SFMC__mdt
            WHERE DeveloperName = :developerName LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String buildExecuteRequestBody(
        String assessmentId,
        List<Integer> stepOrders,
        Conduit_Target_SFMC__mdt target
    ) {
        // Reuse ConduitPlanController's assessment-context builder for
        // clientContext + cmm, then merge in stepOrders + targetCreds.
        String baseJson = ConduitPlanController.buildAssessmentContext(assessmentId);
        Map<String, Object> baseMap = (Map<String, Object>) JSON.deserializeUntyped(baseJson);
        baseMap.put('stepOrders', stepOrders == null ? new List<Integer>() : stepOrders);
        baseMap.put('targetCreds', new Map<String, String>{
            'clientId'     => target.Client_Id__c,
            'clientSecret' => target.Client_Secret__c,
            'authBaseUri'  => target.Auth_Base_URI__c
        });
        return JSON.serialize(baseMap);
    }

    private static ExecuteResponse callConduitExecute(String bodyJson) {
        Conduit_Settings__c cfg = Conduit_Settings__c.getInstance();
        if (cfg == null || String.isBlank(cfg.API_URL__c)) {
            throw new AuraHandledException(
                'Conduit is not configured. Go to Setup → Custom Settings → Conduit Settings and enter the API URL.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.API_URL__c + '/api/sf/migration-execute');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        if (String.isNotBlank(cfg.API_Key__c)) req.setHeader('X-Conduit-Key', cfg.API_Key__c);
        req.setTimeout(120000);
        req.setBody(bodyJson);

        HttpResponse http = new Http().send(req);
        if (http.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Conduit returned HTTP ' + http.getStatusCode() + ' — ' + http.getBody().left(400)
            );
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(http.getBody());

        ExecuteResponse r = new ExecuteResponse();
        r.runStartedAt   = parseDateTime((String) parsed.get('runStartedAt'));
        r.runCompletedAt = parseDateTime((String) parsed.get('runCompletedAt'));
        Map<String, Object> sum = (Map<String, Object>) parsed.get('summary');
        r.total   = toInt(sum.get('total'));
        r.applied = toInt(sum.get('applied'));
        r.skipped = toInt(sum.get('skipped'));
        r.failed  = toInt(sum.get('failed'));

        // Persist the machine-readable skip breakdown + halt cause verbatim
        // so the LWC can render a chip row without re-parsing individual
        // step Error_Message__c fields. Format:
        //   { "byCategory": { "halted": 2, "already_exists": 4, ... },
        //     "haltCause":  { "order": 8, "entityName": "..." } | null }
        Map<String, Object> skipSummary = new Map<String, Object>{
            'byCategory' => sum.get('skipBreakdown'),
            'haltCause'  => sum.get('haltCause')
        };
        r.skipSummary = JSON.serialize(skipSummary);

        List<Object> stepsRaw = (List<Object>) parsed.get('stepResults');
        List<StepResult> steps = new List<StepResult>();
        List<String> errorLines = new List<String>();
        if (stepsRaw != null) {
            for (Object sr : stepsRaw) {
                Map<String, Object> m = (Map<String, Object>) sr;
                StepResult s = new StepResult();
                s.order             = toInt(m.get('order'));
                s.groupName         = (String) m.get('group');
                s.entityType        = (String) m.get('entityType');
                s.entityName        = (String) m.get('entityName');
                s.action            = (String) m.get('action');
                s.status            = (String) m.get('status');
                s.externalId        = (String) m.get('externalId');
                s.detail            = (String) m.get('detail');
                s.error             = (String) m.get('error');
                s.previewText       = (String) m.get('previewText');
                s.sourceCanonicalId = (String) m.get('sourceCanonicalId');
                steps.add(s);
                if (s.status == 'failed' && String.isNotBlank(s.error)) {
                    errorLines.add('Step ' + s.order + ' (' + s.entityName + '): ' + s.error);
                }
            }
        }
        r.stepResults  = steps;
        r.errorSummary = errorLines.isEmpty() ? null : String.join(errorLines, '\n');
        return r;
    }

    private static DateTime parseDateTime(String iso) {
        if (String.isBlank(iso)) return null;
        try { return (DateTime) JSON.deserialize('"' + iso + '"', DateTime.class); }
        catch (Exception e) { return null; }
    }

    private static Integer toInt(Object v) {
        if (v == null) return 0;
        if (v instanceof Integer) return (Integer) v;
        if (v instanceof Decimal) return ((Decimal) v).intValue();
        try { return Integer.valueOf(String.valueOf(v)); }
        catch (Exception e) { return 0; }
    }

    private static String statusPicklistValue(String apiStatus) {
        // Route returns lowercase: applied / skipped / failed.
        // Picklist values are Title Case + "Rolled Back".
        if (apiStatus == 'applied') return 'Applied';
        if (apiStatus == 'skipped') return 'Skipped';
        if (apiStatus == 'failed')  return 'Failed';
        return 'Pending';
    }

    // ── Response DTOs ──────────────────────────────────────────────────────
    private class ExecuteResponse {
        DateTime runStartedAt;
        DateTime runCompletedAt;
        Integer total;
        Integer applied;
        Integer skipped;
        Integer failed;
        List<StepResult> stepResults = new List<StepResult>();
        String errorSummary;
        String skipSummary;   // JSON blob persisted to Skip_Summary__c
    }

    private class StepResult {
        Integer order;
        String groupName;         // avoid Apex reserved word "group"
        String entityType;
        String entityName;
        String action;
        String status;
        String externalId;
        String detail;
        String error;
        String previewText;
        String sourceCanonicalId;
    }
}