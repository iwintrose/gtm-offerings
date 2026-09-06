/**
 * Guest-accessible controller for logging prospect activity on shared
 * engagement links.
 *
 * Runs `without sharing` so unauthenticated Experience Cloud visitors
 * can insert GTM_Link_Event__c records without needing a Salesforce login.
 * No data is read back to the caller — insert only.
 */
public without sharing class GtmLinkEventController {

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

        GTM_Link_Event__c evt = new GTM_Link_Event__c(
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


    /** One event in a batch, as the page reports it. */
    public class EventInput {
        @AuraEnabled public String  eventType   { get; set; }
        @AuraEnabled public String  step        { get; set; }
        @AuraEnabled public String  target      { get; set; }
        @AuraEnabled public Decimal dwellSeconds{ get; set; }
        @AuraEnabled public Integer sequence    { get; set; }
    }

    // A visit that produces more than this is either a bot or a bug, and either
    // way the tail is not worth the rows.
    private static final Integer MAX_EVENTS_PER_CALL = 60;

    /**
     * A visit's events, in one call.
     *
     * Section dwell fires an event every time a chapter leaves the screen, so a
     * reader who scrolls the configurator once produces a dozen or more. One
     * @AuraEnabled round trip each would put a dozen requests on the prospect's
     * connection while they read, which is both slow and the sort of thing that
     * makes a page feel instrumented. The page batches instead and flushes on a
     * timer and on leaving; this takes the batch.
     */
    @AuraEnabled(cacheable=false)
    public static void logEvents(String configId, String sessionId, List<EventInput> events) {
        if (String.isBlank(configId) || !isValidConfigId(configId)) return;
        if (events == null || events.isEmpty()) return;

        List<GTM_Link_Event__c> rows = new List<GTM_Link_Event__c>();
        for (EventInput e : events) {
            if (e == null || String.isBlank(e.eventType)) continue;
            if (rows.size() >= MAX_EVENTS_PER_CALL) break;
            rows.add(new GTM_Link_Event__c(
                Saved_Configuration__c = configId,
                Event_Type__c   = e.eventType,
                Session_Id__c   = String.isNotBlank(sessionId) ? sessionId.left(80) : null,
                Step__c         = String.isNotBlank(e.step)   ? e.step.left(100)   : null,
                Target__c       = String.isNotBlank(e.target) ? e.target.left(120) : null,
                // Rounded on the way in: tenths of a second is the most a dwell
                // measurement means, and storing more invites reading it as
                // precision it does not have.
                Dwell_Seconds__c = e.dwellSeconds == null ? null : e.dwellSeconds.setScale(1),
                Sequence__c      = e.sequence
            ));
        }
        if (rows.isEmpty()) return;

        try {
            insert rows;
        } catch (Exception ex) {
            // Best-effort, like the single-event path: a prospect's page never
            // fails over analytics.
        }
    }

    /**
     * Names the visitor behind a session, once they say who they are.
     *
     * Everything before a form submission is anonymous, which makes the reading
     * that led to a request unattributable to the person who did it. On
     * submission the whole session is stamped, so the trail becomes theirs
     * retroactively -- the same identity stitching Marketing Cloud
     * Personalization does when an anonymous profile resolves to a known one.
     *
     * Guest-callable, and deliberately narrow: it writes one lookup on events
     * that already belong to the session doing the calling, and reads nothing
     * back.
     */
    @AuraEnabled(cacheable=false)
    public static void identifySession(String configId, String sessionId, String contactId) {
        if (String.isBlank(sessionId) || String.isBlank(configId)) return;
        if (!isValidConfigId(configId) || !isValidContactId(contactId)) return;

        try {
            List<GTM_Link_Event__c> mine = [
                SELECT Id FROM GTM_Link_Event__c
                WHERE  Session_Id__c = :sessionId
                AND    Saved_Configuration__c = :configId
                AND    Contact__c = null
                LIMIT  200
            ];
            if (mine.isEmpty()) return;
            for (GTM_Link_Event__c e : mine) e.Contact__c = (Id) contactId;
            update mine;
        } catch (Exception ex) {
            // The request itself already succeeded; attribution is a bonus.
        }
    }

    private static Boolean isValidContactId(String value) {
        if (String.isBlank(value)) return false;
        try {
            Id candidate = (Id) value;
            return candidate.getSObjectType() == Contact.SObjectType;
        } catch (Exception e) {
            return false;
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
            return candidate.getSObjectType() == GTM_Assessment_Request__c.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }
}
