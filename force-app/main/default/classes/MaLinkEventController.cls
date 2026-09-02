/**
 * Guest-accessible controller for logging prospect activity on shared
 * engagement links.
 *
 * Runs `without sharing` so unauthenticated Experience Cloud visitors
 * can insert MA_Link_Event__c records without needing a Salesforce login.
 * No data is read back to the caller — insert only.
 */
public without sharing class MaLinkEventController {

    @AuraEnabled(cacheable=false)
    public static void logEvent(
        String configId,
        String eventType,
        String sessionId,
        String step,
        String assessmentRequestId
    ) {
        if (String.isBlank(configId) || !isValidConfigId(configId)) return;
        if (String.isBlank(eventType)) return;

        MA_Link_Event__c evt = new MA_Link_Event__c(
            Event_Type__c           = eventType,
            Session_Id__c           = String.isNotBlank(sessionId)  ? sessionId.left(80)  : null,
            Step__c                 = String.isNotBlank(step)        ? step.left(100)      : null,
            Saved_Configuration__c  = configId
        );

        if (String.isNotBlank(assessmentRequestId) && isValidArId(assessmentRequestId)) {
            evt.Assessment_Request__c = assessmentRequestId;
        }

        try {
            insert evt;
        } catch (Exception e) {
            // Best-effort; never fail the prospect-facing page over a logging error.
        }
    }

    private static Boolean isValidConfigId(String value) {
        try {
            Id candidate = (Id) value;
            return candidate.getSObjectType() == MA_Saved_Configuration__c.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isValidArId(String value) {
        try {
            Id candidate = (Id) value;
            return candidate.getSObjectType() == MA_Assessment_Request__c.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }
}
