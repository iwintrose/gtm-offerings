/**
 * Backs the rep's "find a link I already sent" flow (gtmRepLinkFinder / D7).
 *
 * A rep no longer browses every offering x every template from a blank
 * picker (that was the wrong shape -- see gtmPageBrowser). What they
 * actually need is to walk the CRM relationship they already know: pick the
 * Account, see which of its Contacts a Configurator link was ever saved
 * against, then pick the link. This class answers exactly that, scoped to
 * one Account at a time.
 *
 * `with sharing`, like GtmSavedConfigurationController: this is not
 * guest-reachable (the guest permission sets are never granted class access
 * to it), so a prospect calling it fails on class access before any sharing
 * check even runs, and a rep only ever sees Accounts/Contacts/links their
 * own sharing rules already grant them.
 */
public with sharing class GtmRepLinkFinderController {

    /** One Contact under the requested Account, and every link saved
     *  against it. Only Contacts with at least one link are returned --
     *  a rep here is looking for a link they already sent, not browsing
     *  the Account's full Contact roster. */
    public class ContactLinks {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public List<LinkSummary> links;
    }

    public class LinkSummary {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String company;
        @AuraEnabled public String offering;
        @AuraEnabled public String industryLabel;
        @AuraEnabled public String dealName;
        @AuraEnabled public String dealStage;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Datetime createdDate;
    }

    /**
     * Every Contact on the given Account that has at least one saved
     * Configurator link, each carrying its own links (newest first).
     *
     * Grouped server-side rather than handed back as a flat list and grouped
     * in the component: the component's only job is to render what it's
     * given, and "which links belong to which Contact" is a query concern,
     * not a display one.
     */
    @AuraEnabled(cacheable=true)
    public static List<ContactLinks> getContactsWithLinks(Id accountId) {
        List<ContactLinks> out = new List<ContactLinks>();
        if (accountId == null) {
            return out;
        }

        Map<Id, ContactLinks> byContact = new Map<Id, ContactLinks>();
        for (MA_Saved_Configuration__c rec : [
            SELECT Id, Company__c, Offering__c, Industry_Label__c, Active__c, CreatedDate,
                   Contact__c, Contact__r.Name,
                   Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName
            FROM   MA_Saved_Configuration__c
            WHERE  Account__c = :accountId AND Contact__c != null
            ORDER BY Contact__r.Name ASC, CreatedDate DESC
        ]) {
            ContactLinks grp = byContact.get(rec.Contact__c);
            if (grp == null) {
                grp = new ContactLinks();
                grp.contactId = rec.Contact__c;
                grp.contactName = rec.Contact__r.Name;
                grp.links = new List<LinkSummary>();
                byContact.put(rec.Contact__c, grp);
                out.add(grp);
            }

            LinkSummary link = new LinkSummary();
            link.recordId = rec.Id;
            link.company = rec.Company__c;
            link.offering = rec.Offering__c;
            link.industryLabel = rec.Industry_Label__c;
            link.dealName = rec.Opportunity__c != null ? rec.Opportunity__r.Name : null;
            link.dealStage = rec.Opportunity__c != null ? rec.Opportunity__r.StageName : null;
            link.active = rec.Active__c;
            link.createdDate = rec.CreatedDate;
            grp.links.add(link);
        }
        return out;
    }
}
