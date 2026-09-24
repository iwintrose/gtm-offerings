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
        /** So a rep can copy the exact link to send by email or text
         *  without opening the record. */
        @AuraEnabled public String generatedUrl;
        /** Whether a password is set, never the password itself -- same
         *  boundary GtmSavedConfigurationController.hasPassword() already
         *  draws for the Customize panel. */
        @AuraEnabled public Boolean hasPassword;
        /** The most recent Assessment Request booked off this link, if any --
         *  so a rep drilling into a link can jump straight to the submission
         *  rather than dead-ending on link metadata alone. Null when the
         *  prospect never started an assessment from this link. */
        @AuraEnabled public Id requestId;
        /** The most recent Readout generated from that request, if any.
         *  Null whenever requestId is null, and also null when a request
         *  exists but no readout has been generated for it yet -- both are
         *  valid, unremarkable states, not errors. */
        @AuraEnabled public Id readoutId;
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

        // Explicit OwnerId backstop (defense-in-depth, issue
        // rep-data-scoping-owd-2): this used to filter only by Account__c,
        // relying entirely on implicit `with sharing` + Private OWD to keep
        // a rep from seeing another rep's links on a shared Account -- same
        // root-cause pattern as GtmSavedConfigurationController.
        // getMyConfigurations(). A user holding viewAllRecords on this
        // object still sees everything, same as before. The two follow-up
        // queries below (requestIdByConfig, readoutIdByRequest) only look
        // up descendants of the Ids already scoped here, so they inherit
        // this filter transitively and don't need their own.
        Id currentUserId = UserInfo.getUserId();
        String ownerFilter = hasViewAllRecords('GTM_Saved_Configuration__c')
            ? ''
            : ' AND OwnerId = :currentUserId';
        List<GTM_Saved_Configuration__c> configs = (List<GTM_Saved_Configuration__c>) Database.query(
            'SELECT Id, Company__c, Offering__c, Industry_Label__c, Active__c, CreatedDate, ' +
            '       Contact__c, Contact__r.Name, Generated_URL__c, Link_Password__c, ' +
            '       Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName ' +
            'FROM   GTM_Saved_Configuration__c ' +
            'WHERE  Account__c = :accountId AND Contact__c != null' + ownerFilter + ' ' +
            'ORDER BY Contact__r.Name ASC, CreatedDate DESC'
        );

        Set<Id> configIds = new Map<Id, GTM_Saved_Configuration__c>(configs).keySet();

        // SOQL can't nest an aggregate relationship two levels below the root
        // (Saved Configuration -> Assessment Request -> Readout), so the most
        // recent Request per link, and the most recent Readout per Request,
        // are resolved as two flat follow-up queries instead of one nested
        // subquery -- same read-only, no-DML shape, just SOQL's own limit.
        Map<Id, Id> requestIdByConfig = new Map<Id, Id>();
        for (GTM_Assessment_Request__c req : [
            SELECT Id, Saved_Configuration__c
            FROM   GTM_Assessment_Request__c
            WHERE  Saved_Configuration__c IN :configIds
            ORDER BY Saved_Configuration__c ASC, CreatedDate DESC
        ]) {
            // First one seen per config, given the ORDER BY above, is the
            // most recent -- later ones for the same config are ignored.
            if (!requestIdByConfig.containsKey(req.Saved_Configuration__c)) {
                requestIdByConfig.put(req.Saved_Configuration__c, req.Id);
            }
        }

        Map<Id, Id> readoutIdByRequest = new Map<Id, Id>();
        if (!requestIdByConfig.isEmpty()) {
            for (GTM_Readout__c readout : [
                SELECT Id, Assessment_Request__c
                FROM   GTM_Readout__c
                WHERE  Assessment_Request__c IN :requestIdByConfig.values()
                ORDER BY Assessment_Request__c ASC, CreatedDate DESC
            ]) {
                if (!readoutIdByRequest.containsKey(readout.Assessment_Request__c)) {
                    readoutIdByRequest.put(readout.Assessment_Request__c, readout.Id);
                }
            }
        }

        Map<Id, ContactLinks> byContact = new Map<Id, ContactLinks>();
        for (GTM_Saved_Configuration__c rec : configs) {
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
            link.generatedUrl = rec.Generated_URL__c;
            link.hasPassword = String.isNotBlank(rec.Link_Password__c);
            Id requestId = requestIdByConfig.get(rec.Id);
            if (requestId != null) {
                link.requestId = requestId;
                link.readoutId = readoutIdByRequest.get(requestId);
            }
            grp.links.add(link);
        }
        return out;
    }

    /**
     * Minimal, local admin-bypass check: does the running user hold
     * viewAllRecords on the given object via ANY assigned Permission Set
     * (not a hardcoded permission-set-name check, which is the anti-pattern
     * being phased out org-wide -- see sub-issue
     * rep-data-scoping-owd-3-analytics-permcheck for the canonical,
     * generalized version of this same check). Kept small and private to
     * this class on purpose; not shared infrastructure.
     */
    private static Boolean hasViewAllRecords(String sobjectApiName) {
        List<ObjectPermissions> perms = [
            SELECT PermissionsViewAllRecords
            FROM ObjectPermissions
            WHERE SobjectType = :sobjectApiName
              AND ParentId IN (
                  SELECT PermissionSetId FROM PermissionSetAssignment
                  WHERE AssigneeId = :UserInfo.getUserId()
              )
              AND PermissionsViewAllRecords = true
            LIMIT 1
        ];
        return !perms.isEmpty();
    }
}
