public with sharing class ConduitAuditController {

    @AuraEnabled
    public static Map<String, Object> runAudit(String assessmentId) {
        Conduit_Settings__c cfg = Conduit_Settings__c.getInstance();
        if (cfg == null || String.isBlank(cfg.API_URL__c)) {
            throw new AuraHandledException(
                'Conduit is not configured. Go to Setup → Custom Settings → Conduit Settings and enter the API URL.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.API_URL__c + '/api/sf/audit');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        if (String.isNotBlank(cfg.API_Key__c)) {
            req.setHeader('X-Conduit-Key', cfg.API_Key__c);
        }
        req.setBody(ConduitPlanController.buildAssessmentContext(assessmentId));
        req.setTimeout(60000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Conduit returned HTTP ' + res.getStatusCode() + '. Check that the API URL is correct and Conduit is running.'
            );
        }

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        upsertAuditRecord(assessmentId, result);
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Conduit_Audit__c getLastAudit(String assessmentId) {
        List<Conduit_Audit__c> rows = [
            SELECT Id, Health_Score__c, Status__c, Run_At__c,
                   Source_Platform__c, Target_Platform__c,
                   Freshness_Active__c, Freshness_Recent__c, Freshness_Stale__c,
                   Freshness_Abandoned__c, Total_Assets__c, Total_Audiences__c,
                   Total_Data_Objects__c, Findings_Summary__c,
                   Migration_Steps__c, Migration_Gaps__c, Migration_Confidence__c,
                   Gap_Analysis_Summary__c, Gap_Analysis_Items__c
            FROM Conduit_Audit__c
            WHERE Assessment_Request__c = :assessmentId
            ORDER BY Run_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    // Always inserts a new Conduit_Audit__c row per run so history builds up.
    // Ancillary AI results (Scope_Estimate__c, Wave_Notes__c, Gap_Detail__c,
    // Rationalization_Items__c) are attached to the newest row by upsertAuditField
    // in ConduitPlanController — those effectively "reset" when a fresh audit
    // runs, but the previous row keeps its AI results for the historical record.
    private static void upsertAuditRecord(String assessmentId, Map<String, Object> result) {
        Map<String, Object> freshness = (Map<String, Object>) result.get('freshness');
        Map<String, Object> plan      = (Map<String, Object>) result.get('migrationPlan');
        Map<String, Object> gaps      = (Map<String, Object>) result.get('gapAnalysis');

        Conduit_Audit__c rec = new Conduit_Audit__c(
            Assessment_Request__c = assessmentId,
            Health_Score__c       = (Decimal) result.get('healthScore'),
            Status__c             = 'Complete',
            Run_At__c             = DateTime.now(),
            Source_Platform__c    = (String) result.get('sourcePlatform'),
            Target_Platform__c    = (String) result.get('targetPlatform'),
            Total_Assets__c       = toDecimal(result.get('totalAssets')),
            Total_Audiences__c    = toDecimal(result.get('totalAudiences')),
            Total_Data_Objects__c = toDecimal(result.get('totalDataObjects')),
            Findings_Summary__c   = JSON.serialize(result.get('summary'))
        );

        if (freshness != null) {
            rec.Freshness_Active__c    = toDecimal(freshness.get('active'));
            rec.Freshness_Recent__c    = toDecimal(freshness.get('recent'));
            rec.Freshness_Stale__c     = toDecimal(freshness.get('stale'));
            rec.Freshness_Abandoned__c = toDecimal(freshness.get('abandoned'));
        }

        if (plan != null) {
            rec.Migration_Steps__c      = toDecimal(plan.get('totalSteps'));
            rec.Migration_Gaps__c       = toDecimal(plan.get('totalGaps'));
            rec.Migration_Confidence__c = toDecimal(plan.get('averageConfidence'));
        }

        if (gaps != null) {
            rec.Gap_Analysis_Summary__c = (String) gaps.get('summary');
            Object items = gaps.get('items');
            if (items != null) {
                rec.Gap_Analysis_Items__c = JSON.serialize(items);
            }
        }

        insert rec;
    }

    private static Decimal toDecimal(Object val) {
        if (val == null) return null;
        if (val instanceof Decimal) return (Decimal) val;
        if (val instanceof Integer) return (Decimal)(Integer) val;
        return Decimal.valueOf(String.valueOf(val));
    }
}