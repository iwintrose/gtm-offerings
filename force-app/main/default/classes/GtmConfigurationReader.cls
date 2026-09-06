/**
 * What a prospect's browser needs to draw their own page.
 *
 * The configurator used to be rebuilt entirely from query parameters: the
 * company, the industry, the brand colour and every proof number rode in the
 * URL in plain text. That put client details in browser history, in referrer
 * headers, and in every chat message the link was ever forwarded through, and
 * it froze the page at the moment the link was generated -- an edit the rep
 * made afterwards was invisible until they sent a new link.
 *
 * So the link carries one value, the record id, and the page asks for the
 * rest. The id is the bearer token, exactly as it was before; the difference
 * is that the details are no longer travelling next to it.
 *
 * `without sharing` because the guest user has no object access at all --
 * the same pattern as GtmConfigurationStatusController, which reads this
 * object for guests today.
 *
 * This deliberately widens what a guest may read, and GtmConfigurationStatus-
 * Controller's comment warns against exactly that. The warning is about scope
 * creep on a class whose job is one boolean, and it is right. This is a
 * separate class with a stated job, and the trade it makes is a considered
 * one: the alternative is not secrecy, it is the same fields in the URL where
 * anybody can read them without asking Salesforce at all.
 *
 * Two rules keep it honest:
 *   - Link_Password__c is never selected. Whether a link is protected is
 *     GtmLinkAuthController's answer; the value itself is nobody's.
 *   - A link switched off returns its status and nothing else. A disabled
 *     link should stop being a way to read client details, not just stop
 *     rendering.
 */
public without sharing class GtmConfigurationReader {

    @AuraEnabled(cacheable=false)
    public static PublicConfig getPublicConfiguration(String recordId) {
        Id parsedId = GtmLegacyConfigId.resolve(recordId);
        if (parsedId == null) return null;

        List<GTM_Saved_Configuration__c> rows = [
            SELECT Id, Company__c, Industry__c, Industry_Label__c, Offering__c,
                   Config_Payload__c, Active__c
            FROM   GTM_Saved_Configuration__c
            WHERE  Id = :parsedId
            LIMIT  1
        ];
        if (rows.isEmpty()) return null;

        GTM_Saved_Configuration__c r = rows[0];
        PublicConfig c = new PublicConfig();
        c.isActive = r.Active__c;
        if (!c.isActive) {
            // Off means off: the page shows its expired state, and the details
            // stop being readable through this link at all.
            return c;
        }
        c.company       = r.Company__c;
        c.industry      = r.Industry__c;
        c.industryLabel = r.Industry_Label__c;
        c.offering      = r.Offering__c;
        c.configPayload = r.Config_Payload__c;
        return c;
    }

    public class PublicConfig {
        @AuraEnabled public String  company       { get; set; }
        @AuraEnabled public String  industry      { get; set; }
        @AuraEnabled public String  industryLabel { get; set; }
        @AuraEnabled public String  offering      { get; set; }
        @AuraEnabled public String  configPayload { get; set; }
        @AuraEnabled public Boolean isActive      { get; set; }
    }
}
