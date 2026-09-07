/**
 * A part-finished configurator booking form, so a prospect who leaves can
 * come back to it.
 *
 * SHARES A TABLE WITH ANOTHER GUEST POPULATION. GTM_Form_Draft__c also holds
 * the branching readiness-questionnaire draft (Draft_Type__c = 'Assessment',
 * owned by GtmAssessmentDraftController, guest permission set
 * GTM_Assessment_Guest). Every query and insert in THIS class filters/sets
 * Draft_Type__c = 'Booking' so the two populations never cross -- see
 * docs/handoff/port-map-ma-to-gtm.md section E for the full security posture
 * this depends on. GTM_Story_Guest's field grants on this object must never
 * be widened to include the Assessment-only fields (Resume_Token__c,
 * Expires_At__c, Status__c beyond its default, Submitted_Request__c,
 * Pair_Key__c, Last_Saved_At__c).
 *
 * WHAT THIS EXPOSES, deliberately and in full — this is the one class on a
 * public page that lets an unauthenticated visitor WRITE:
 *
 *   - A draft is addressed by <engagement link id>::<visitor key>. The visitor
 *     key is 32 random characters the browser generates and keeps in its own
 *     storage; it is never derived from anything guessable and never leaves
 *     that browser. Reading a draft therefore requires holding the key that
 *     wrote it, which is a bearer-token model: right for resuming your own
 *     half-typed form, and the reason a draft cannot be enumerated.
 *   - Writes are refused unless the engagement link exists and is active, so a
 *     disabled or deleted link is not a writable endpoint.
 *   - A draft holds only what the visitor typed into the form themselves.
 *     Nothing about the account, the deal, the rep or the configuration is ever
 *     written into it or read back out of it.
 *   - getDraft returns the draft's own content and nothing else. There is no
 *     method here that returns anything about the link, and no way to learn
 *     whether a link id is real: an unknown link and a wrong key are the same
 *     empty answer.
 *   - Size is capped and one visitor holds exactly one draft per link (upsert
 *     on the external id), so the surface cannot be used as storage.
 *
 * without sharing because the rows are owned by the automated process user and
 * a guest running with sharing would resolve none of them.
 */
public without sharing class GtmFormDraftController {

    // Comfortably more than the assessment form holds, and far less than the
    // field allows: a cap is what stops a write surface becoming a bucket.
    private static final Integer MAX_DRAFT_CHARS = 8000;

    /** What a spent draft holds. Written on submission, read as "nothing". */
    private static final String EMPTY_DRAFT = '{}';

    public class DraftView {
        @AuraEnabled public String   draftJson     { get; set; }
        @AuraEnabled public String   furthestField { get; set; }
        @AuraEnabled public Datetime savedAt       { get; set; }
    }

    /**
     * The draft this browser left on this link, or null.
     *
     * Null covers every failure identically -- no draft, wrong key, unknown
     * link, malformed id -- so nothing here tells a caller which of those it
     * was.
     */
    @AuraEnabled(cacheable=false)
    public static DraftView getDraft(String configId, String visitorKey) {
        Id resolvedConfigId = GtmLegacyConfigId.resolve(configId);
        String key = draftKey(resolvedConfigId, visitorKey);
        if (key == null) return null;

        List<GTM_Form_Draft__c> found = [
            SELECT Draft_JSON__c, Furthest_Field__c, CreatedDate
            FROM   GTM_Form_Draft__c
            WHERE  Draft_Type__c = 'Booking'
            AND    Draft_Key__c = :key
            // Id breaks the tie, and it has to: CreatedDate is second-resolution,
            // two saves 1.5 seconds apart routinely share one, and on a tie the
            // database is free to hand back the older row. That is exactly what
            // it did -- a resume served the draft from before the visitor's last
            // edit, and a submitted form went on offering its own answers back
            // because the emptying row lost to the one it was meant to replace.
            // Ids are assigned in insert order, so the newest row is the
            // greatest.
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT  1
        ];
        if (found.isEmpty()) return null;
        // A submitted form leaves its row behind with the content taken out.
        if (String.isBlank(found[0].Draft_JSON__c)
            || found[0].Draft_JSON__c == EMPTY_DRAFT) return null;

        DraftView v = new DraftView();
        v.draftJson     = found[0].Draft_JSON__c;
        v.furthestField = found[0].Furthest_Field__c;
        v.savedAt       = found[0].CreatedDate;
        return v;
    }

    /**
     * Replace this browser's draft on this link.
     *
     * An append, because a guest cannot update: the newest row for the key is
     * the draft. The page only calls this when the answers have actually
     * changed and only after typing has paused, so a form filled in one sitting
     * leaves a handful of rows rather than one per keystroke. Returns nothing:
     * a write path on a public page should not double as a read path.
     */
    @AuraEnabled(cacheable=false)
    public static void saveDraft(String configId, String visitorKey, String draftJson,
                                 String furthestField, String sessionId) {
        Id resolvedConfigId = GtmLegacyConfigId.resolve(configId);
        String key = draftKey(resolvedConfigId, visitorKey);
        if (key == null || String.isBlank(draftJson)) return;
        if (draftJson.length() > MAX_DRAFT_CHARS) return;
        if (!isLinkWritable(resolvedConfigId)) return;

        try {
            SObject draft = Schema.getGlobalDescribe().get('GTM_Form_Draft__c').newSObject();
            draft.put('Draft_Type__c', 'Booking');
            draft.put('Draft_Key__c', key);
            draft.put('Saved_Configuration__c', resolvedConfigId);
            draft.put('Draft_JSON__c', draftJson);
            draft.put('Furthest_Field__c', String.isNotBlank(furthestField) ? furthestField.left(80) : null);
            draft.put('Session_Id__c', String.isNotBlank(sessionId) ? sessionId.left(80) : null);
            insert draft;
        } catch (Exception e) {
            // A draft that will not save must never stop someone finishing the
            // form by typing it out in one go.
        }
    }

    /**
     * Empty the draft once the form has actually been submitted.
     *
     * A kept draft would offer a finished applicant their own answers back on
     * the next visit, which reads as "we lost your submission".
     *
     * A guest can neither update nor delete, so this appends an empty draft
     * instead. The newest row wins and getDraft reads an empty one as nothing,
     * which has the same effect and leaves the trail of how the form was
     * filled in intact. Sweeping spent drafts is an internal job, not a guest's.
     */
    @AuraEnabled(cacheable=false)
    public static void clearDraft(String configId, String visitorKey) {
        Id resolvedConfigId = GtmLegacyConfigId.resolve(configId);
        String key = draftKey(resolvedConfigId, visitorKey);
        if (key == null || !isLinkWritable(resolvedConfigId)) return;
        try {
            SObject draft = Schema.getGlobalDescribe().get('GTM_Form_Draft__c').newSObject();
            draft.put('Draft_Type__c', 'Booking');
            draft.put('Draft_Key__c', key);
            draft.put('Saved_Configuration__c', resolvedConfigId);
            draft.put('Draft_JSON__c', EMPTY_DRAFT);
            insert draft;
        } catch (Exception e) {
            // Nothing to do: the submission has already succeeded.
        }
    }

    /**
     * The address, or null when either half is unusable.
     *
     * The key is length-checked as well as present: a one-character visitor key
     * would make drafts guessable, and the browser has no reason to send one.
     * Built off the already-resolved (canonical, current-format) id, not
     * whatever raw format the browser's URL happened to carry -- otherwise
     * the same visitor could end up with two differently-keyed drafts on the
     * same link depending on whether they arrived via a legacy or current
     * URL.
     */
    private static String draftKey(Id configId, String visitorKey) {
        if (configId == null || String.isBlank(visitorKey)) return null;
        String vk = visitorKey.trim();
        if (vk.length() < 16 || vk.length() > 64) return null;
        if (!Pattern.matches('^[A-Za-z0-9_-]+$', vk)) return null;
        return configId + '::' + vk;
    }

    /** A draft may only be written against a link that is real and still live. */
    private static Boolean isLinkWritable(Id configId) {
        if (configId == null) return false;
        return [
            SELECT COUNT() FROM GTM_Saved_Configuration__c
            WHERE Id = :configId AND Active__c = true
        ] > 0;
    }
}
