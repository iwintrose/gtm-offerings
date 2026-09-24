/**
 * Guest-accessible controller for logging prospect activity on shared
 * engagement links.
 *
 * Runs `without sharing` so unauthenticated Experience Cloud visitors
 * can insert GTM_Link_Event__c records without needing a Salesforce login.
 * No data is read back to the caller — insert only.
 *
 * Saved_Configuration__c is accessed dynamically (SObject.put/get, dynamic
 * SOQL) rather than through typed dot-notation. That isn't the freshly-
 * deployed-field workaround used elsewhere in this migration -- it's
 * permanent here, because a static reference to this exact field is what
 * blocks Salesforce from letting the field be deleted and recreated, which
 * is the only way to repoint an existing Lookup's referenceTo (there is no
 * in-place "change referenceTo" deploy). Every configId is resolved through
 * GtmLegacyConfigId.resolve() first, so both current- and legacy-format ids
 * from the URL keep working.
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
        Id resolvedConfigId = GtmLegacyConfigId.resolve(configId);
        if (resolvedConfigId == null) return;
        if (String.isBlank(eventType)) return;

        SObject evt = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        evt.put('Event_Type__c', eventType);
        evt.put('Session_Id__c', String.isNotBlank(sessionId) ? sessionId.left(80) : null);
        evt.put('Step__c', String.isNotBlank(step) ? step.left(100) : null);
        evt.put('Saved_Configuration__c', resolvedConfigId);

        if (String.isNotBlank(assessmentRequestId) && isValidArId(assessmentRequestId)) {
            evt.put('Assessment_Request__c', assessmentRequestId);
        }

        try {
            GtmLinkOwnerStamp.stamp(new List<SObject>{ evt }, GtmLinkOwnerStamp.ownerForLink(resolvedConfigId));
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
        Id resolvedConfigId = GtmLegacyConfigId.resolve(configId);
        if (resolvedConfigId == null) return;
        if (events == null || events.isEmpty()) return;

        List<SObject> rows = new List<SObject>();
        for (EventInput e : events) {
            if (e == null || String.isBlank(e.eventType)) continue;
            if (rows.size() >= MAX_EVENTS_PER_CALL) break;
            SObject row = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
            row.put('Saved_Configuration__c', resolvedConfigId);
            row.put('Event_Type__c', e.eventType);
            row.put('Session_Id__c', String.isNotBlank(sessionId) ? sessionId.left(80) : null);
            row.put('Step__c', String.isNotBlank(e.step) ? e.step.left(100) : null);
            row.put('Target__c', String.isNotBlank(e.target) ? e.target.left(120) : null);
            // Rounded on the way in: tenths of a second is the most a dwell
            // measurement means, and storing more invites reading it as
            // precision it does not have.
            row.put('Dwell_Seconds__c', e.dwellSeconds == null ? null : e.dwellSeconds.setScale(1));
            row.put('Sequence__c', e.sequence);
            rows.add(row);
        }
        if (rows.isEmpty()) return;

        try {
            GtmLinkOwnerStamp.stamp(rows, GtmLinkOwnerStamp.ownerForLink(resolvedConfigId));
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
        if (String.isBlank(sessionId)) return;
        Id resolvedConfigId = GtmLegacyConfigId.resolve(configId);
        if (resolvedConfigId == null || !isValidContactId(contactId)) return;

        try {
            List<SObject> mine = Database.query(
                'SELECT Id FROM GTM_Link_Event__c ' +
                'WHERE Session_Id__c = :sessionId ' +
                'AND Saved_Configuration__c = :resolvedConfigId ' +
                'AND Contact__c = null ' +
                'LIMIT 200'
            );
            if (mine.isEmpty()) return;
            for (SObject e : mine) e.put('Contact__c', (Id) contactId);
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

    private static Boolean isValidArId(String value) {
        try {
            Id candidate = (Id) value;
            return candidate.getSObjectType() == GTM_Assessment_Request__c.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }
}
