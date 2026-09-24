/**
 * SECURITY-SENSITIVE -- this is the guest-accessible surface for published
 * assessment readouts. Any change here needs security-review before merge.
 *
 * Exposes exactly one method, and that method is the ONLY query path onto
 * GTM_Readout__c reachable by an unauthenticated caller. The filter for
 * "is this token allowed to see this record" is enforced IN THE SOQL WHERE
 * clause (Status__c = 'Published' AND Public_Link_Token__c = :token) --
 * never by fetching a row first and checking its status in Apex afterward.
 * That ordering matters: a filter-after-fetch would still touch the record
 * (timing, debug logs, a later refactor that forgets the check) even for a
 * Draft/Approved readout's token.
 *
 * A Draft or Approved readout's token, an unpublished token, and a token that
 * was never issued at all are all indistinguishable to the caller -- every
 * one of them returns null. This is deliberate: telling an attacker "that
 * token exists but isn't published yet" is itself information leakage (it
 * confirms a readout is being prepared for a given deal), so the response
 * carries no signal at all about which of those three cases occurred.
 *
 * `without sharing`: the guest user has no read access to GTM_Readout__c on
 * its own, and this class is the entire reason that's safe -- the WHERE
 * clause above is the access control, not org sharing rules.
 */
public without sharing class GtmReadoutPublicController {

    /**
     * Returns the published content for a valid, currently-published token,
     * or null for anything else -- a Draft/Approved readout's token, a token
     * that was published and then unpublished (Public_Link_Token__c is
     * cleared immediately by GtmReadoutController.unpublishReadout), or a
     * token that never existed. Callers must treat null as a generic "not
     * found" and must not distinguish these cases in any user-facing message.
     */
    @AuraEnabled(cacheable=true)
    public static PublishedReadout getPublishedReadout(String token) {
        if (String.isBlank(token)) {
            return null;
        }

        // Approved_Data__c, never Readout_Data__c: what a guest is served is
        // the copy taken at approval, on both halves. The WHERE clause is
        // unchanged and stays the access control -- Status__c = 'Published'
        // first, token second, filtered in SOQL and never in Apex afterwards.
        List<GTM_Readout__c> rows = [
            SELECT Id, Offering_Key__c, Approved_Content__c, Approved_Data__c,
                   Published_Date__c, OwnerId
            FROM GTM_Readout__c
            WHERE Status__c = 'Published'
            AND Public_Link_Token__c = :token
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }

        GTM_Readout__c readout = rows[0];
        PublishedReadout out = new PublishedReadout();
        out.offeringKey   = readout.Offering_Key__c;
        out.content       = readout.Approved_Content__c;
        // The measurement half of the readout, as JSON. gtmReadoutView renders
        // the designed panels from it and the approved prose into their slots.
        // It carries no field the prose does not already carry -- it is the
        // same assessment, structured -- so it widens no disclosure: a token
        // that could not read the content cannot read this either, because
        // neither is returned at all.
        out.dataJson      = readout.Approved_Data__c;
        out.publishedDate = readout.Published_Date__c;
        applyRepContact(out, readout.OwnerId);
        return out;
    }

    /**
     * Best-effort rep contact info from the readout's owning User. OwnerId
     * on a custom object is polymorphic (User or Queue), so a separate
     * User query -- guarded by the key prefix -- is used instead of a SOQL
     * relationship dot-walk, which cannot select User-only fields like
     * Email/Phone through a polymorphic Owner relationship. Never lets a
     * lookup quirk (queue ownership, a deactivated user) take down an
     * otherwise-valid published response.
     *
     * OwnerId (rather than Approved_By__c) is the source on purpose: the owner
     * is the rep working the deal and the person the prospect should contact,
     * whereas the approver may be a manager or a peer reviewer who has no
     * relationship with them. Since GtmReadoutController.Generator now assigns
     * that owner explicitly to a validated, active, non-Guest User, it is also
     * the field that is guaranteed to be a real rep.
     *
     * The UserType filter below is belt-and-braces for readouts created before
     * that fix landed, which may still be owned by the site guest / guest
     * default user: this is a public, unauthenticated page, and it must never
     * print an internal service account's name and email to a prospect. Such a
     * readout returns its content with no contact block rather than the wrong
     * contact block.
     */
    private static void applyRepContact(PublishedReadout out, Id ownerId) {
        if (ownerId == null || ownerId.getSObjectType() != User.SObjectType) {
            return;
        }
        try {
            List<User> owners = [
                SELECT Name, Email, Phone
                FROM User
                WHERE Id = :ownerId AND UserType != 'Guest'
                LIMIT 1
            ];
            if (!owners.isEmpty()) {
                out.repName  = owners[0].Name;
                out.repEmail = owners[0].Email;
                out.repPhone = owners[0].Phone;
            }
        } catch (Exception e) {
            // No access, or some other lookup hiccup -- content still returns.
        }
    }

    public class PublishedReadout {
        @AuraEnabled public String offeringKey     { get; set; }
        @AuraEnabled public String content         { get; set; }
        @AuraEnabled public String dataJson        { get; set; }
        @AuraEnabled public Datetime publishedDate { get; set; }
        @AuraEnabled public String repName         { get; set; }
        @AuraEnabled public String repEmail        { get; set; }
        @AuraEnabled public String repPhone        { get; set; }
    }
}
