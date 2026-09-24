public with sharing class ConduitPlanController {

    // ── Migration plan ──────────────────────────────────────────────────────────
    @AuraEnabled
    public static String getMigrationPlan(String assessmentId) {
        return callConduit('POST', '/api/sf/migration-plan', buildAssessmentContext(assessmentId));
    }

    // ── Migration runbook (deterministic tactical view + Markdown download) ─────
    // Same data source as the plan, but per-step describeStep() text and a
    // fully-rendered Markdown document the LWC downloads directly. Not agentic.
    // Persists to Migration_Runbook__c so it survives page reloads (same
    // pattern as Gap Detail / Rationalization / Wave Notes / Scope Estimate).
    @AuraEnabled
    public static String getMigrationRunbook(String assessmentId) {
        String result = callConduit('POST', '/api/sf/migration-runbook', buildAssessmentContext(assessmentId));
        upsertAuditField(assessmentId, 'Migration_Runbook__c', result);
        return result;
    }

    // ── AI Scope Estimate (agentic — Claude call, ~30s) ─────────────────────────
    @AuraEnabled
    public static String runScopeEstimate(String assessmentId) {
        String result = callConduit('POST', '/api/sf/scope-estimate', buildAssessmentContext(assessmentId));
        upsertAuditField(assessmentId, 'Scope_Estimate__c', result);
        upsertAuditField(assessmentId, 'Scope_Estimate_Run_At__c', String.valueOf(DateTime.now()));
        return result;
    }

    // ── Assets ──────────────────────────────────────────────────────────────────
    // Converted to POST so the request body can include the uploaded CMM (via
    // buildAssessmentContext, which now embeds cmm alongside clientContext).
    @AuraEnabled
    public static String getAssets(String assessmentId) {
        return callConduit('POST', '/api/sf/assets', buildAssessmentContext(assessmentId));
    }

    // ── Audiences ───────────────────────────────────────────────────────────────
    @AuraEnabled
    public static String getAudiences(String assessmentId) {
        return callConduit('POST', '/api/sf/audiences', buildAssessmentContext(assessmentId));
    }

    // ── Gap detail (agentic — Claude call, ~15s) ────────────────────────────────
    @AuraEnabled
    public static String getGapDetail(String assessmentId) {
        String result = callConduit('POST', '/api/sf/gap-detail', buildAssessmentContext(assessmentId));
        upsertAuditField(assessmentId, 'Gap_Detail__c', result);
        return result;
    }

    // ── Rationalization (agentic — Claude call, ~20s) ───────────────────────────
    @AuraEnabled
    public static String getRationalization(String assessmentId) {
        String result = callConduit('POST', '/api/sf/rationalization', buildAssessmentContext(assessmentId));
        upsertAuditField(assessmentId, 'Rationalization_Items__c', result);
        return result;
    }

    // ── AI Wave Notes (agentic — Claude call, ~20s) ─────────────────────────────
    @AuraEnabled
    public static String runWaveNotes(String assessmentId) {
        String result = callConduit('POST', '/api/sf/wave-notes', buildAssessmentContext(assessmentId));
        upsertAuditField(assessmentId, 'Wave_Notes__c', result);
        upsertAuditField(assessmentId, 'Wave_Notes_Run_At__c', String.valueOf(DateTime.now()));
        return result;
    }

    // ── Stored plan data ─────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static Conduit_Audit__c getStoredPlanData(String assessmentId) {
        List<Conduit_Audit__c> rows = [
            SELECT Id, Scope_Estimate__c, Scope_Estimate_Run_At__c,
                   Rationalization_Items__c,
                   Wave_Notes__c, Wave_Notes_Run_At__c,
                   Gap_Detail__c,
                   Migration_Runbook__c
            FROM Conduit_Audit__c
            WHERE Assessment_Request__c = :assessmentId
            ORDER BY Run_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    // ── Audit history ────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Conduit_Audit__c> getAuditHistory(String assessmentId) {
        return [
            SELECT Id, Health_Score__c, Run_At__c, Source_Platform__c,
                   Total_Assets__c, Total_Audiences__c, Total_Data_Objects__c,
                   Migration_Steps__c, Migration_Confidence__c, Status__c
            FROM Conduit_Audit__c
            WHERE Assessment_Request__c = :assessmentId
            ORDER BY Run_At__c DESC
            LIMIT 10
        ];
    }

    // ── Private helpers ──────────────────────────────────────────────────────────

    public static String buildAssessmentContext(String assessmentId) {
        if (String.isBlank(assessmentId)) return '{}';
        Map<String, Object> body = new Map<String, Object>();

        try {
            List<GTM_Assessment_Request__c> rows = [
                SELECT Current_Platform__c, Target_Platform__c, Company__c,
                       Assessment_Score__c, Assessment_Tier__c, Timeline__c,
                       Urgency_Driver__c, Environment_Size__c, Contact_Count__c,
                       Monthly_Send_Volume__c, Migration_Goals__c, Pain_Points__c,
                       Key_Integrations__c, Success_Criteria__c, Context__c,
                       Internal_Team_Size__c, Estate_Complexity_Score__c,
                       Estate_Complexity_Band__c
                FROM GTM_Assessment_Request__c
                WHERE Id = :assessmentId
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                GTM_Assessment_Request__c r = rows[0];
                Map<String, Object> ctx = new Map<String, Object>();
                if (r.Company__c != null)                 ctx.put('company', r.Company__c);
                if (r.Current_Platform__c != null)        ctx.put('currentPlatform', r.Current_Platform__c);
                if (r.Target_Platform__c != null)         ctx.put('targetPlatform', r.Target_Platform__c);
                if (r.Assessment_Score__c != null)        ctx.put('assessmentScore', r.Assessment_Score__c);
                if (r.Assessment_Tier__c != null)         ctx.put('assessmentTier', r.Assessment_Tier__c);
                if (r.Timeline__c != null)                ctx.put('timeline', r.Timeline__c);
                if (r.Urgency_Driver__c != null)          ctx.put('urgencyDriver', r.Urgency_Driver__c);
                if (r.Environment_Size__c != null)        ctx.put('environmentSize', r.Environment_Size__c);
                if (r.Contact_Count__c != null)           ctx.put('contactCount', r.Contact_Count__c);
                if (r.Monthly_Send_Volume__c != null)     ctx.put('monthlySendVolume', r.Monthly_Send_Volume__c);
                if (r.Migration_Goals__c != null)         ctx.put('migrationGoals', r.Migration_Goals__c);
                if (r.Pain_Points__c != null)             ctx.put('painPoints', r.Pain_Points__c);
                if (r.Key_Integrations__c != null)        ctx.put('keyIntegrations', r.Key_Integrations__c);
                if (r.Success_Criteria__c != null)        ctx.put('successCriteria', r.Success_Criteria__c);
                if (r.Context__c != null)                 ctx.put('context', r.Context__c);
                if (r.Internal_Team_Size__c != null)      ctx.put('internalTeamSize', r.Internal_Team_Size__c);
                if (r.Estate_Complexity_Score__c != null) ctx.put('estateComplexityScore', r.Estate_Complexity_Score__c);
                if (r.Estate_Complexity_Band__c != null)  ctx.put('estateComplexityBand', r.Estate_Complexity_Band__c);
                if (!ctx.isEmpty()) body.put('clientContext', ctx);
            }
        } catch (Exception e) {
            System.debug('ConduitPlanController.buildAssessmentContext (context) failed: ' + e.getMessage());
        }

        // Attach the currently-active CMM for this assessment, if any. When absent
        // the Next.js route falls back to the CONDUIT_CMM_<PLATFORM> env-var fixture.
        try {
            String cmmJson = ConduitCmmController.getActiveCmmContent(assessmentId);
            if (String.isNotBlank(cmmJson)) {
                // Deserialize so the CMM is embedded as a nested object, not a
                // double-encoded JSON string.
                body.put('cmm', JSON.deserializeUntyped(cmmJson));
            }
        } catch (Exception e) {
            System.debug('ConduitPlanController.buildAssessmentContext (cmm) failed: ' + e.getMessage());
        }

        return JSON.serialize(body);
    }

    private static String callConduit(String method, String path) {
        return callConduit(method, path, '{}');
    }

    private static String callConduit(String method, String path, String body) {
        Conduit_Settings__c cfg = Conduit_Settings__c.getInstance();
        if (cfg == null || String.isBlank(cfg.API_URL__c)) {
            throw new AuraHandledException(
                'Conduit is not configured. Go to Setup → Custom Settings → Conduit Settings and enter the API URL.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.API_URL__c + path);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        if (String.isNotBlank(cfg.API_Key__c)) {
            req.setHeader('X-Conduit-Key', cfg.API_Key__c);
        }
        if (method == 'POST') {
            req.setBody(String.isBlank(body) ? '{}' : body);
        }
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Conduit returned HTTP ' + res.getStatusCode() + ' for ' + path +
                '. Check that the API URL is correct and Conduit is running.'
            );
        }
        return res.getBody();
    }

    private static void upsertAuditField(String assessmentId, String fieldName, String value) {
        try {
            List<Conduit_Audit__c> existing = [
                SELECT Id FROM Conduit_Audit__c
                WHERE Assessment_Request__c = :assessmentId
                ORDER BY Run_At__c DESC
                LIMIT 1
            ];
            if (existing.isEmpty()) return;
            Conduit_Audit__c rec = new Conduit_Audit__c(Id = existing[0].Id);
            rec.put(fieldName, value);
            update rec;
        } catch (Exception e) {
            System.debug('ConduitPlanController.upsertAuditField failed for ' + fieldName + ': ' + e.getMessage());
        }
    }
}