/**
 * Persists and lists configurator links for internal, authenticated reps.
 *
 * Runs `with sharing` deliberately, unlike MaAssessmentRequestController:
 * this is not guest-reachable, and every visibility rule (a rep sees only
 * their own saved configs; a manager granted "View All" on the object sees
 * everyone's) should come from standard object sharing, not from anything
 * hand-rolled here. The guest permission set is never granted access to
 * this class, so a guest calling it fails on class access before any
 * sharing check even runs.
 */
public with sharing class MaSavedConfigurationController {
    private static final Integer MAX_COMPANY = 255;
    private static final Integer MAX_OFFERING = 100;
    private static final Integer MAX_INDUSTRY = 50;

    public class SaveInput {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String offering { get; set; }
        @AuraEnabled
        public String industry { get; set; }
        @AuraEnabled
        public String company { get; set; }
        @AuraEnabled
        public String generatedUrl { get; set; }
        @AuraEnabled
        public String configPayload { get; set; }
        @AuraEnabled
        public String clientContactName { get; set; }
        @AuraEnabled
        public String clientContactEmail { get; set; }
        @AuraEnabled
        public String estimatedValue { get; set; }
        /** Set when the rep picked an existing Contact from searchContacts()
         * rather than typing a name/email freehand -- takes priority over
         * resolveContact's fuzzy by-email match below, since this is exact. */
        @AuraEnabled
        public String contactId { get; set; }
        /** The selected Contact's own Account, when it has one -- takes
         * priority over resolveAccount's by-name match against the typed
         * Company field, so the Contact is attached to the Account it
         * already actually belongs to rather than whatever Account the
         * Company text happens to resolve/create. */
        @AuraEnabled
        public String accountId { get; set; }
        /** When non-blank, sets Link_Password__c to this value (guests must
         * enter it before viewing the shared link). Omit or leave blank to
         * leave the existing password untouched -- set clearLinkPassword to
         * true instead to explicitly remove it. */
        @AuraEnabled
        public String linkPassword { get; set; }
        /** When true and linkPassword is blank, clears Link_Password__c on
         * the record. Ignored when linkPassword is non-blank. */
        @AuraEnabled
        public Boolean clearLinkPassword { get; set; }
        /** Brand / marketing website for the prospect's company -- used to
         * set Account.Website when the Account is newly created. */
        @AuraEnabled
        public String website { get; set; }
        /** Engagement-link industry key (e.g. 'fintech', 'transport') mapped
         * to the closest Salesforce standard Account.Industry picklist value
         * and set on a newly created Account. */
        @AuraEnabled
        public String accountIndustry { get; set; }
    }

    /** Returned by getConfigurationCrmData -- carries the Salesforce records
     * associated with a saved config so the Customize panel can pre-fill
     * Contact, Estimated Value, and Opportunity without a localStorage round
     * trip (Sales Cloud is the source of truth for this data). */
    public class CrmData {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String estimatedValue;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
    }

    public class ContactSearchResult {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
    }

    /** Backs the Customize panel's contact search -- typing 2+ characters
     * matches against Contact Name, Contact Email, OR the parent Account's
     * Name, so a rep who thinks in terms of "which company" and not yet
     * "which person there" can search the Account name and get every
     * Contact under it to choose from, not just a Contact whose own name
     * happens to match. `with sharing`, so results are already scoped to
     * what the calling rep can see. */
    @AuraEnabled(cacheable=true)
    public static List<ContactSearchResult> searchContacts(String searchTerm) {
        String term = String.isBlank(searchTerm) ? '' : searchTerm.trim();
        if (term.length() < 2) {
            return new List<ContactSearchResult>();
        }
        String likeTerm = '%' + term + '%';
        List<ContactSearchResult> results = new List<ContactSearchResult>();
        for (Contact c : [
            SELECT Id, Name, Email, AccountId, Account.Name
            FROM Contact
            WHERE Name LIKE :likeTerm
               OR Email LIKE :likeTerm
               OR Account.Name LIKE :likeTerm
            ORDER BY Account.Name NULLS LAST, Name
            LIMIT 15
        ]) {
            ContactSearchResult r = new ContactSearchResult();
            r.contactId = c.Id;
            r.name = c.Name;
            r.email = c.Email;
            r.accountId = c.AccountId;
            r.accountName = c.Account != null ? c.Account.Name : null;
            results.add(r);
        }
        return results;
    }

    @AuraEnabled
    public static Id saveConfiguration(SaveInput input) {
        if (input == null || String.isBlank(input.generatedUrl)) {
            throw new AuraHandledException('A generated link is required to save a configuration.');
        }
        if (String.isBlank(input.offering)) {
            throw new AuraHandledException('An offering is required to save a configuration.');
        }

        // A rep who searched and picked an existing Contact/Account in the
        // panel already gave us the exact real record -- use it directly
        // rather than re-deriving one by fuzzy-matching typed text, which
        // is only the fallback for a rep who typed a brand-new contact by
        // hand (the same found-or-created-from-what-was-typed behavior
        // this always had).
        Id accountId = isValidId(input.accountId, Account.SObjectType)
            ? (Id) input.accountId
            : resolveAccount(
                trimTo(input.company, MAX_COMPANY),
                trimTo(input.website, 255),
                input.accountIndustry
            );
        Id contactId = isValidId(input.contactId, Contact.SObjectType)
            ? (Id) input.contactId
            : resolveContact(input.clientContactName, input.clientContactEmail, accountId);
        Id opportunityId = resolveOpportunity(
            input.recordId,
            accountId,
            trimTo(input.company, MAX_COMPANY),
            parseDecimal(input.estimatedValue)
        );
        // Same rule as the client-submission flow: an Opportunity never
        // sits without the Contact it's known to belong to.
        ensureOpportunityContactRole(opportunityId, contactId);

        MA_Saved_Configuration__c record = new MA_Saved_Configuration__c(
            Offering__c = trimTo(input.offering, MAX_OFFERING),
            Industry__c = trimTo(input.industry, MAX_INDUSTRY),
            Company__c = trimTo(input.company, MAX_COMPANY),
            Generated_URL__c = input.generatedUrl,
            Config_Payload__c = input.configPayload
        );
        // Set only when resolved to something real: the Customize panel
        // doesn't reload an existing record's Account/Contact/value on
        // reopen (they're not in the URL, unlike company/industry), so
        // every resave sends these blank unless the rep retypes them.
        // Unconditionally assigning null here would silently wipe out
        // whatever was already resolved on a prior save.
        if (accountId != null) {
            record.Account__c = accountId;
        }
        if (contactId != null) {
            record.Contact__c = contactId;
        }
        if (opportunityId != null) {
            record.Opportunity__c = opportunityId;
        }
        Decimal estimatedValue = parseDecimal(input.estimatedValue);
        if (estimatedValue != null) {
            record.Estimated_Value__c = estimatedValue;
        }
        if (String.isNotBlank(input.linkPassword)) {
            record.Link_Password__c = input.linkPassword.trim();
        } else if (input.clearLinkPassword == true) {
            record.Link_Password__c = null;
        }

        try {
            if (String.isNotBlank(input.recordId)) {
                record.Id = input.recordId;
                update record;
            } else {
                insert record;
            }
        } catch (DmlException e) {
            // The generic message this used to always throw (regardless of
            // cause) is exactly what hid a real STRING_TOO_LONG on
            // Generated_URL__c for weeks -- surfacing the actual DML
            // message is what made that root cause findable at all.
            throw new AuraHandledException(
                'We could not save this link: ' + e.getDmlMessage(0)
            );
        }

        // The Opportunity needs this link's own Id, which only exists once
        // the insert/update above has run -- and Amount should track
        // whatever the rep just set here, not just whatever it happened to
        // be the first time this Opportunity was created. Best-effort: the
        // link itself already saved successfully above.
        if (opportunityId != null) {
            try {
                Opportunity oppUpdate = new Opportunity(
                    Id = opportunityId,
                    Engagement_Link__c = record.Id
                );
                if (estimatedValue != null) {
                    oppUpdate.Amount = estimatedValue;
                }
                update oppUpdate;
            } catch (Exception e) {
                // Link save already succeeded -- don't fail the whole
                // request over the Opportunity sync.
            }
        }

        return record.Id;
    }

    /**
     * Deliberately NOT cacheable: this is an Aura site (Digital
     * Experience), and Aura's own action-transport layer caches any
     * cacheable=true method's results regardless of whether the caller
     * uses @wire or a plain imperative call -- switching maSavedLinksBar
     * to an imperative call fixed staleness across page navigations, but
     * not a same-session reload (e.g. right after toggling active/
     * inactive), because that caching happens below the LWC wire layer.
     */
    @AuraEnabled
    public static List<MA_Saved_Configuration__c> getMyConfigurations() {
        return [
            SELECT Id, Name, Offering__c, Industry__c, Company__c,
                   Generated_URL__c, Active__c, CreatedDate, OwnerId, Owner.Name
            FROM MA_Saved_Configuration__c
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    /**
     * Toggling this does not delete or hide the record from the rep's own
     * Saved Links list -- it only gates what a client sees when visiting
     * the shared link (see MaConfigurationStatusController, the small
     * guest-safe class that reads this one field).
     */
    @AuraEnabled
    public static void setActive(String recordId, Boolean active) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No record specified.');
        }
        try {
            update new MA_Saved_Configuration__c(Id = recordId, Active__c = active);
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not update this link\'s status. Please try again.'
            );
        }
    }

    /**
     * Lets the Saved Links bar (running inside an Experience Cloud site,
     * a different domain from Salesforce's own Lightning UI) build a
     * "View in Salesforce" link. There's no reliable client-side way to
     * know the org's internal My Domain from inside a site page.
     */
    @AuraEnabled(cacheable=true)
    public static String getOrgBaseUrl() {
        return URL.getOrgDomainUrl().toExternalForm();
    }

    /**
     * Four approaches tried before this one, in order, each disproven live:
     *   1. The site's own public siteUrl (*.my.site.com) -- no session on
     *      that domain at all. Landed as a guest.
     *   2. my.salesforce.com + /servlet/networks/switch -- redirected to
     *      the org's generic default tab, not the site. (In hindsight this
     *      wasn't a session problem -- the request clearly got processed
     *      by an authenticated domain, just not by the right endpoint.)
     *   3. my.salesforce.com + frontdoor.jsp + UserInfo.getSessionId() --
     *      that session ID isn't valid for frontdoor.jsp from a
     *      Lightning/LWC context. Rejected outright, real login form.
     *   4. window.location.origin (*.lightning.force.com) + the site's
     *      relative path -- session WAS valid this time (no login prompt),
     *      but that domain doesn't serve site/community paths at all:
     *      "Page doesn't exist".
     * #4 actually solved the auth question -- both my.salesforce.com and
     * *.lightning.force.com carry a valid session for an already-logged-in
     * rep. The remaining problem was always routing, not identity: the
     * site's own url path prefix, served from the org's own My Domain
     * (my.salesforce.com) with no wrapper of any kind -- the standard,
     * documented way an internal member accesses a Digital Experience site
     * -- which, after four detours, is what this actually is.
     *
     * Returns null if the "GTM Accelerator" site isn't found rather than
     * throwing, since a missing site here should degrade gracefully (the
     * standalone launcher just won't be able to build a link) rather than
     * break anything else on the page.
     */
    @AuraEnabled(cacheable=true)
    public static String getConfiguratorPageUrl() {
        return getSiteMyDomainUrl('/s/configurator');
    }

    /**
     * The site's own home page -- "Choose your industry" (see chooseIndustry
     * LWC), not the configurator. Used by the standalone launcher (the
     * Overview tab's "+ New Prospect Page" button) to send a rep through the
     * same industry-first flow a client-shared link would start from,
     * instead of dropping them straight onto an unpersonalized configurator.
     * Same contract as getConfiguratorPageUrl() above.
     */
    @AuraEnabled(cacheable=true)
    public static String getSiteHomePageUrl() {
        return getSiteMyDomainUrl('/s/');
    }

    private static String getSiteMyDomainUrl(String suffix) {
        try {
            List<Network> nets = [SELECT UrlPathPrefix FROM Network WHERE Name = 'GTM Accelerator' LIMIT 1];
            if (nets.isEmpty() || String.isBlank(nets[0].UrlPathPrefix)) return null;
            return URL.getOrgDomainUrl().toExternalForm() + '/' + nets[0].UrlPathPrefix + suffix;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Lets a component gate rep-only UI (the Customize panel, the saved
     * links bar) on real authentication rather than guessing from URL
     * params. Guests -- and anyone without this permission -- can't even
     * call it, since the guest permission set is never granted class
     * access here; that failure is what a caller should treat as "false".
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isConfigManager() {
        return true;
    }

    /** Returns true when the saved record currently has a password set.
     *  Used by the Customize panel to show the rep whether password
     *  protection is active without exposing the password value itself. */
    @AuraEnabled(cacheable=false)
    public static Boolean hasLinkPassword(String recordId) {
        if (String.isBlank(recordId)) return false;
        List<MA_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        return !rows.isEmpty() && String.isNotBlank(rows[0].Link_Password__c);
    }

    /** Returns the Sales Cloud records linked to a saved config so the
     * Customize panel can pre-fill Contact, Estimated Value, and Opportunity
     * without relying on localStorage (Sales Cloud is the source of truth). */
    @AuraEnabled
    public static CrmData getConfigurationCrmData(String recordId) {
        if (String.isBlank(recordId)) return null;
        List<MA_Saved_Configuration__c> rows = [
            SELECT Contact__c, Contact__r.Name, Contact__r.Email,
                   Account__c, Account__r.Name,
                   Estimated_Value__c,
                   Opportunity__c, Opportunity__r.Name
            FROM MA_Saved_Configuration__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;
        MA_Saved_Configuration__c r = rows[0];
        CrmData d = new CrmData();
        d.contactId    = r.Contact__c;
        d.contactName  = r.Contact__c  != null ? r.Contact__r.Name  : null;
        d.contactEmail = r.Contact__c  != null ? r.Contact__r.Email : null;
        d.accountId    = r.Account__c;
        d.accountName  = r.Account__c  != null ? r.Account__r.Name  : null;
        if (r.Estimated_Value__c != null) {
            Long lv = r.Estimated_Value__c.longValue();
            d.estimatedValue = (r.Estimated_Value__c == lv)
                ? String.valueOf(lv)
                : String.valueOf(r.Estimated_Value__c);
        }
        d.opportunityId   = r.Opportunity__c;
        d.opportunityName = r.Opportunity__c != null ? r.Opportunity__r.Name : null;
        return d;
    }

    @AuraEnabled
    public static void deleteConfiguration(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No record specified.');
        }
        try {
            delete new MA_Saved_Configuration__c(Id = recordId);
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not delete this link. It may already be gone, or you may not have access to it.'
            );
        }
    }

    /** Client-supplied Ids get validated, not trusted blind: a bad cast on
     * garbage input throws an opaque system error rather than a message a
     * rep could act on, and checking the SObjectType also stops an Id for
     * the wrong object type from ever reaching the DML below. */
    private static Boolean isValidId(String value, SObjectType expectedType) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            Id candidate = (Id) value;
            return candidate.getSObjectType() == expectedType;
        } catch (Exception e) {
            return false;
        }
    }

    private static String trimTo(String value, Integer maxLen) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.length() > maxLen ? trimmed.substring(0, maxLen) : trimmed;
    }

    /**
     * Exact-name match, not fuzzy: good enough to stop the same rep from
     * creating a second Account every time they resave the same client's
     * link. Website and industry are set on newly created Accounts (not
     * on existing ones, to avoid overwriting data already managed in
     * Sales Cloud). The industry key is mapped to the closest standard
     * Salesforce Account.Industry picklist value.
     */
    private static Id resolveAccount(String company, String website, String industryKey) {
        if (String.isBlank(company)) {
            return null;
        }
        List<Account> existing = [
            SELECT Id FROM Account WHERE Name = :company LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        Account acc = new Account(Name = company);
        if (String.isNotBlank(website)) {
            acc.Website = website.startsWith('http') ? website : 'https://' + website;
        }
        if (String.isNotBlank(industryKey)) {
            acc.Industry = mapIndustry(industryKey);
        }
        insert acc;
        return acc.Id;
    }

    private static String mapIndustry(String key) {
        if (key == 'fintech')    return 'Finance';
        if (key == 'medtech')    return 'Healthcare';
        if (key == 'lifesci')    return 'Biotechnology';
        if (key == 'media')      return 'Media';
        if (key == 'transport')  return 'Transportation';
        if (key == 'government') return 'Government';
        return null;
    }

    /**
     * Reuses THIS link's own Opportunity if it already has one -- never a
     * different Opportunity just because it happens to match on Account,
     * which would wrongly glom two different links (different reps,
     * different sales cycles) for the same Account onto one record. A
     * brand-new link, or an existing one that never got an Opportunity,
     * gets a fresh one. Only runs when an Account is resolved -- no
     * Account, no Opportunity.
     */
    private static Id resolveOpportunity(String recordId, Id accountId, String company, Decimal amount) {
        if (accountId == null) return null;
        if (isValidId(recordId, MA_Saved_Configuration__c.SObjectType)) {
            List<MA_Saved_Configuration__c> existingLink = [
                SELECT Opportunity__c
                FROM MA_Saved_Configuration__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (!existingLink.isEmpty() && existingLink[0].Opportunity__c != null) {
                return existingLink[0].Opportunity__c;
            }
        }
        Opportunity opp = new Opportunity(
            Name = 'Migration Accelerator — ' + (String.isNotBlank(company) ? company.trim() : 'Assessment'),
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(90)
        );
        if (amount != null) opp.Amount = amount;
        insert opp;
        return opp.Id;
    }

    /**
     * A rep saving the Customize panel resolves a Contact and an
     * Opportunity independently -- neither knew about the other, so an
     * Opportunity could sit with a known Contact right next to it and no
     * OpportunityContactRole tying them together. Same rule as the
     * assessment-submission flow: an Opportunity with a known Contact is
     * never left contact-less. Idempotent on resave (skips if the role
     * already exists); only marks primary when the Opportunity doesn't
     * already have another primary Contact, so a later resave with a
     * different Contact adds a role instead of erroring on a duplicate
     * primary.
     */
    private static void ensureOpportunityContactRole(Id opportunityId, Id contactId) {
        if (opportunityId == null || contactId == null) {
            return;
        }
        List<OpportunityContactRole> existing = [
            SELECT Id FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId AND ContactId = :contactId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }
        Boolean hasAnyRole = ![
            SELECT Id FROM OpportunityContactRole WHERE OpportunityId = :opportunityId LIMIT 1
        ].isEmpty();
        insert new OpportunityContactRole(
            OpportunityId = opportunityId,
            ContactId = contactId,
            Role = 'Decision Maker',
            IsPrimary = !hasAnyRole
        );
    }

    /** Matches by email (Salesforce doesn't enforce Contact email
     * uniqueness, so this takes the first match) rather than by name --
     * more reliable as a dedupe key, and it's the field the rep is most
     * likely to have typed correctly. No email, no Contact: a name alone
     * isn't enough to safely dedupe or usefully route to. */
    private static Id resolveContact(String name, String email, Id accountId) {
        String cleanEmail = String.isNotBlank(email) ? email.trim() : null;
        if (String.isBlank(cleanEmail)) {
            return null;
        }
        List<Contact> existing = [
            SELECT Id FROM Contact WHERE Email = :cleanEmail LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        String cleanName = String.isNotBlank(name) ? name.trim() : '';
        List<String> parts = String.isBlank(cleanName) ? new List<String>() : cleanName.split('\\s+');
        String lastName = parts.isEmpty() ? cleanEmail : parts[parts.size() - 1];
        String firstName = null;
        if (parts.size() > 1) {
            List<String> firstParts = new List<String>();
            for (Integer i = 0; i < parts.size() - 1; i++) {
                firstParts.add(parts[i]);
            }
            firstName = String.join(firstParts, ' ');
        }

        Contact c = new Contact(
            FirstName = trimTo(firstName, 40),
            LastName = trimTo(lastName, 80),
            Email = cleanEmail,
            AccountId = accountId
        );
        insert c;
        return c.Id;
    }

    private static Decimal parseDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            String cleaned = value.replaceAll('[^0-9.\\-]', '');
            return String.isBlank(cleaned) ? null : Decimal.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }
}
