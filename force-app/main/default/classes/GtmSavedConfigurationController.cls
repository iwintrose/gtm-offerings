/**
 * Persists and lists configurator links for internal, authenticated reps.
 *
 * Runs `with sharing` deliberately, unlike GtmAssessmentRequestController:
 * this is not guest-reachable, and every visibility rule (a rep sees only
 * their own saved configs; a manager granted "View All" on the object sees
 * everyone's) should come from standard object sharing, not from anything
 * hand-rolled here. The guest permission set is never granted access to
 * this class, so a guest calling it fails on class access before any
 * sharing check even runs.
 */
public with sharing class GtmSavedConfigurationController {
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
        /** The deal this link is for, when the rep picked one of the account's
         * existing opportunities. Blank means "a new deal", which is what the
         * wizard used to do every single time without asking. */
        @AuraEnabled
        public String opportunityId { get; set; }
        /** True when the rep has already been shown the open-duplicate
         * prompt (see GtmOpenOpportunityDuplicateCheck) and explicitly chose
         * "Create new anyway" -- skips the check on this retry so a second
         * new Opportunity gets created for real, disambiguated purely by
         * GtmDealNaming's existing same-Account/same-Name date-append, never
         * by a new prompted label field. Ignored (treated as false) unless
         * the caller is deliberately re-submitting after that prompt. */
        @AuraEnabled
        public Boolean forceNewOpportunity { get; set; }
        /** The selected Contact's own Account, when it has one -- takes
         * priority over resolveAccount's by-name match against the typed
         * Company field, so the Contact is attached to the Account it
         * already actually belongs to rather than whatever Account the
         * Company text happens to resolve/create. */
        @AuraEnabled
        public String accountId { get; set; }
        /** Sets Link_Password__c to this value (guests must enter it before
         * viewing the shared link). Every link requires a password -- the
         * wizard always sends one, generated or custom, with no way to
         * turn protection off. Omit or leave blank only from a caller that
         * predates this and hasn't resaved yet; the existing password is
         * left untouched in that case, never cleared. */
        @AuraEnabled
        public String linkPassword { get; set; }
        /** Where assessment-request alerts for THIS link should go. Optional --
         * a rep who leaves it blank gets it defaulted to their own email at
         * creation time (see resolveNotifyEmail()). Set here, an existing value
         * is only ever replaced by a new explicit override, never blanked out
         * by an unrelated resave -- same "don't wipe what's already resolved"
         * rule the rest of this method follows for accountId/contactId/value. */
        @AuraEnabled
        public String notifyEmail { get; set; }
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

    /**
     * The open deals on an account, and whether each already has a link.
     *
     * A client can legitimately have several deals at once -- different parts
     * of the business, or one that closed and restarted months later -- so the
     * rep is asked which deal a link is for rather than the system guessing
     * and creating a new one every time.
     */
    @AuraEnabled(cacheable=false)
    public static List<DealOption> getAccountDeals(String accountId) {
        List<DealOption> out = new List<DealOption>();
        if (!isValidId(accountId, Account.SObjectType)) return out;
        Id acct = (Id) accountId;

        Map<Id, Integer> linkCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Opportunity__c oppId, COUNT(Id) c
            FROM   GTM_Saved_Configuration__c
            WHERE  Account__c = :acct AND Opportunity__c != null
            GROUP BY Opportunity__c
        ]) {
            linkCount.put((Id) ar.get('oppId'), (Integer) ar.get('c'));
        }

        for (Opportunity o : [
            SELECT Id, Name, StageName, CloseDate, Amount, IsClosed
            FROM   Opportunity
            WHERE  AccountId = :acct
            ORDER BY IsClosed ASC, CloseDate DESC
            LIMIT  50
        ]) {
            DealOption d = new DealOption();
            d.opportunityId = o.Id;
            d.name          = o.Name;
            d.stage         = o.StageName;
            d.closeDate     = o.CloseDate;
            d.isClosed      = o.IsClosed;
            d.linkCount     = linkCount.containsKey(o.Id) ? linkCount.get(o.Id) : 0;
            out.add(d);
        }
        return out;
    }

    /**
     * The account behind a typed company name, so the deal picker works for a
     * rep who types the client instead of picking a contact.
     *
     * Without this the picker only appeared once a contact was selected --
     * that was what supplied the account -- so a rep who typed the name got
     * the old behaviour and a new deal created without being asked. Matching
     * is the same rule saving uses: exact name first, so the account the link
     * will actually be attached to is the one whose deals are offered.
     */
    @AuraEnabled(cacheable=false)
    public static AccountMatch findAccountByName(String company) {
        if (String.isBlank(company)) return null;
        String name = company.trim();

        List<Account> exact = [SELECT Id, Name FROM Account WHERE Name = :name LIMIT 1];
        List<Account> hits = exact;
        if (hits.isEmpty()) {
            // A near match is offered but flagged, because saving on an
            // inexact name creates a new account rather than using this one.
            String pattern = '%' + name + '%';
            hits = [SELECT Id, Name FROM Account WHERE Name LIKE :pattern ORDER BY Name LIMIT 2];
            if (hits.size() != 1) return null;
        }

        AccountMatch m = new AccountMatch();
        m.accountId = hits[0].Id;
        m.name      = hits[0].Name;
        m.isExact   = !exact.isEmpty();
        return m;
    }

    public class AccountMatch {
        @AuraEnabled public Id      accountId { get; set; }
        @AuraEnabled public String  name      { get; set; }
        @AuraEnabled public Boolean isExact   { get; set; }
    }

    public class DealOption {
        @AuraEnabled public Id      opportunityId { get; set; }
        @AuraEnabled public String  name          { get; set; }
        @AuraEnabled public String  stage         { get; set; }
        @AuraEnabled public Date    closeDate     { get; set; }
        @AuraEnabled public Boolean isClosed      { get; set; }
        // How many links already point at this deal. One is normal -- it is
        // this deal's link. More than one is usually an accident.
        @AuraEnabled public Integer linkCount     { get; set; }
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

    /**
     * Returned by saveConfiguration() -- the record Id plus, when this save
     * set a password, a short-lived preview bypass token so the creating
     * rep's own "Preview the page" click doesn't hit the same password gate
     * a cold prospect would see. Minted HERE, not on GtmLinkAuthController,
     * because this class is `with sharing` and never guest-granted -- the
     * only caller who can ever reach this method is an authenticated rep
     * saving their own record, which is exactly the trust boundary a preview
     * bypass token needs. The token uses the same HMAC format/secret as the
     * password-entry token (GtmLinkAuthController.issueToken), so it is
     * validated by the same code path, but it is never returned as, or
     * derived from, the plaintext password itself.
     */
    public class SaveResult {
        @AuraEnabled public Id     recordId      { get; set; }
        @AuraEnabled public String previewToken  { get; set; }
    }

    /** Input for createRepDirectAssessment() -- deliberately narrow, unlike
     * SaveInput: this path never generates a branded page, so it carries
     * none of SaveInput's offering/company/URL/payload fields, only the
     * picked-from-search Contact/Account. */
    public class RepDirectInput {
        /** Required -- must be a real Contact Id returned by searchContacts(),
         * never a typed name/email. This is the whole point of this path:
         * no fuzzy resolveContact() fallback, ever. */
        @AuraEnabled
        public String contactId { get; set; }
        /** Optional -- the picked Contact's own Account, when it has one. */
        @AuraEnabled
        public String accountId { get; set; }
        /** Required -- Offering__c is a required field on
         * GTM_Saved_Configuration__c schema-wide (not a rule specific to
         * this path), so the caller supplies the same offering key the
         * "New engagement link" launcher already resolves before opening
         * (see gtmOverview.handleNewEngagementLink's single-offering gate). */
        @AuraEnabled
        public String offering { get; set; }
    }

    /**
     * Creates a pageless, rep-initiated assessment record for a specific,
     * already-selected Contact/Account (see searchContacts()) -- the
     * supported replacement for the accidental bare-URL "direct booking"
     * path that used to silently create duplicate Accounts/Contacts from
     * typed text (gtmConfigurator's accessBlocked exemption for internal
     * users, now closed).
     *
     * Deliberately does NOT reuse saveConfiguration(): that method requires
     * a generatedUrl and an offering, and resolves Account/Contact/
     * Opportunity for a branded page this flow never creates. This inserts
     * a bare GTM_Saved_Configuration__c stamped Presentation_Stage__c =
     * 'Rep_Direct' so it is automatically excluded from getMyConfigurations()'s
     * "All Pages" list -- it never had a page to begin with.
     *
     * Only ever takes a real, picked Contact Id -- never typed text -- so no
     * duplicate Account/Contact is ever created by this path.
     */
    @AuraEnabled
    public static Id createRepDirectAssessment(RepDirectInput input) {
        if (input == null || !isValidId(input.contactId, Contact.SObjectType)) {
            throw new AuraHandledException(
                'A contact must be selected (search and pick one) before starting an assessment.'
            );
        }
        if (input == null || String.isBlank(input.offering)) {
            throw new AuraHandledException('An offering is required to start an assessment.');
        }
        Id contactId = (Id) input.contactId;
        Id accountId = isValidId(input.accountId, Account.SObjectType) ? (Id) input.accountId : null;

        GTM_Saved_Configuration__c record = new GTM_Saved_Configuration__c(
            Contact__c = contactId,
            Offering__c = trimTo(input.offering, MAX_OFFERING),
            Presentation_Stage__c = 'Rep_Direct'
        );
        if (accountId != null) {
            record.Account__c = accountId;
        }
        try {
            insert record;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not start this assessment: ' + e.getDmlMessage(0)
            );
        }
        return record.Id;
    }

    /** Returned by generateRepDirectShareLink(). */
    public class ShareLinkResult {
        @AuraEnabled public String generatedUrl { get; set; }
        @AuraEnabled public String password     { get; set; }
    }

    /**
     * Turns an existing, pageless Rep_Direct record (see
     * createRepDirectAssessment()) into a real, password-protected link a
     * rep can hand a prospect -- the "Share with prospect" action (sub-issue
     * rep-initiated-assessment-no-page-2-share-and-continue).
     *
     * Deliberately NOT routed through saveConfiguration(): that method
     * requires an offering/company/payload this pageless flow never carries,
     * and resolves Account/Contact/Opportunity this record already has from
     * createRepDirectAssessment(). This only ever touches Generated_URL__c
     * and Link_Password__c on an EXISTING Rep_Direct record.
     *
     * Only works on a record whose Presentation_Stage__c is already
     * 'Rep_Direct' -- never changes that value, so this record still never
     * reappears in getMyConfigurations()'s "All Pages" list (that filter is
     * keyed on Presentation_Stage__c, not on whether a URL/password exist).
     *
     * The URL points at /configurator?cfgId=<id>, optionally with
     * &resume=<resumeToken> when the rep pre-filled some answers via
     * GtmAssessmentDraftController.saveDraft() first -- gtmConfigurator's
     * Rep_Direct branch (GtmConfigurationReader.PublicConfig.
     * presentationStage) renders the questionnaire directly rather than any
     * branded chapter content, since this record was never given one.
     */
    @AuraEnabled
    public static ShareLinkResult generateRepDirectShareLink(String recordId, String resumeToken) {
        if (!isValidId(recordId, GTM_Saved_Configuration__c.SObjectType)) {
            throw new AuraHandledException('No record specified.');
        }
        List<GTM_Saved_Configuration__c> rows = [
            SELECT Id, Presentation_Stage__c, Link_Password__c
            FROM   GTM_Saved_Configuration__c
            WHERE  Id = :recordId
            LIMIT  1
        ];
        if (rows.isEmpty() || rows[0].Presentation_Stage__c != 'Rep_Direct') {
            throw new AuraHandledException(
                'This action is only available for a pageless, rep-initiated assessment.'
            );
        }
        GTM_Saved_Configuration__c rec = rows[0];

        String base = getConfiguratorPageUrl();
        if (String.isBlank(base)) {
            throw new AuraHandledException(
                'We could not resolve the public site URL. Please try again shortly.'
            );
        }
        String url = base + '?cfgId=' + rec.Id;
        if (String.isNotBlank(resumeToken)) {
            url += '&resume=' + EncodingUtil.urlEncode(resumeToken.trim(), 'UTF-8');
        }

        // D10: every real link requires a password, no exceptions -- reuse
        // one already set on this record (e.g. a retry) rather than
        // rotating it out from under a rep who already relayed it.
        String password = String.isNotBlank(rec.Link_Password__c)
            ? rec.Link_Password__c
            : randomPassword();

        try {
            update new GTM_Saved_Configuration__c(
                Id = rec.Id,
                Generated_URL__c = url,
                Link_Password__c = password
            );
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not generate a share link: ' + e.getDmlMessage(0)
            );
        }

        ShareLinkResult result = new ShareLinkResult();
        result.generatedUrl = url;
        result.password     = password;
        return result;
    }

    @AuraEnabled
    public static SaveResult saveConfiguration(SaveInput input) {
        if (input == null || String.isBlank(input.generatedUrl)) {
            throw new AuraHandledException('A generated link is required to save a configuration.');
        }
        if (String.isBlank(input.offering)) {
            throw new AuraHandledException('An offering is required to save a configuration.');
        }
        // Server-side backstop for the visible-confirm-or-create requirement
        // (issue account-contact-confirm): the LWC gates Generate on the rep
        // having seen/confirmed an Account and Contact, but a UI-only gate is
        // bypassable by a direct Apex caller or a stale client bundle. Only
        // enforced on a brand-new record -- an existing record already has
        // its own Account__c/Contact__c on file, and a resave that doesn't
        // retype them (the Customize panel doesn't reload Contact/value from
        // the record) must not be blocked retroactively for that.
        Boolean isBrandNew = String.isBlank(input.recordId);
        Boolean hasAccountSignal = isValidId(input.accountId, Account.SObjectType)
            || String.isNotBlank(input.company);
        Boolean hasContactSignal = isValidId(input.contactId, Contact.SObjectType)
            || String.isNotBlank(input.clientContactEmail);
        if (isBrandNew && !hasAccountSignal && !hasContactSignal) {
            throw new AuraHandledException(
                'An Account or Contact must be resolvable (company name, contact email, '
                + 'or an existing record) before this link can be saved.'
            );
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
            contactId,
            trimTo(input.company, MAX_COMPANY),
            parseDecimal(input.estimatedValue),
            input.opportunityId,
            input.offering,
            input.forceNewOpportunity == true
        );
        // Same rule as the client-submission flow: an Opportunity never
        // sits without the Contact it's known to belong to.
        ensureOpportunityContactRole(opportunityId, contactId);

        GTM_Saved_Configuration__c record = new GTM_Saved_Configuration__c(
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
        String newPasswordForToken = null;
        if (String.isNotBlank(input.linkPassword)) {
            newPasswordForToken = input.linkPassword.trim();
            record.Link_Password__c = newPasswordForToken;
        }
        // Resolved once, here, rather than left blank and resolved lazily by
        // the notification path later -- "who created this link" is a fact
        // about the moment of creation, and the creating user is not
        // necessarily who happens to be viewing/sending the notification
        // later. isNewRecord is exactly "no recordId supplied": the same
        // signal insert-vs-update already branches on below.
        Boolean isNewRecord = String.isBlank(input.recordId);
        String resolvedNotifyEmail = resolveNotifyEmail(input.notifyEmail, isNewRecord);
        if (String.isNotBlank(resolvedNotifyEmail)) {
            record.Notify_Email__c = resolvedNotifyEmail;
        }

        try {
            if (String.isNotBlank(input.recordId)) {
                record.Id = input.recordId;
                update record;
            } else {
                // A brand-new record starts life as Draft -- it is not yet a
                // finished, sent, or otherwise "real" page until a later save
                // moves it forward. getMyConfigurations()'s completeness
                // filter relies on this: a link abandoned mid-wizard (no
                // further save ever comes) stays Draft forever and is
                // excluded from "All Pages" rather than cluttering it.
                record.Presentation_Stage__c = 'Draft';
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
                // Engagement_Link__c set dynamically, not through
                // dot-notation -- a static reference to this exact field is
                // what blocks Salesforce from letting it be deleted and
                // recreated, which is the only way to repoint an existing
                // Lookup's referenceTo.
                Opportunity oppUpdate = new Opportunity(Id = opportunityId);
                oppUpdate.put('Engagement_Link__c', record.Id);
                if (estimatedValue != null) {
                    oppUpdate.Amount = estimatedValue;
                }
                update oppUpdate;
            } catch (Exception e) {
                // Link save already succeeded -- don't fail the whole
                // request over the Opportunity sync.
            }
        }

        SaveResult result = new SaveResult();
        result.recordId = record.Id;
        // Minted as a side effect of setting Link_Password__c on THIS save,
        // immediately after it lands -- never issued from a stale/unrelated
        // password, and never issued when this save didn't touch the
        // password (an edit that left it untouched returns no token; the
        // wizard already has one from the create, or falls back to the
        // password gate like any other visit).
        if (newPasswordForToken != null) {
            result.previewToken = GtmLinkAuthController.issueToken(String.valueOf(record.Id), newPasswordForToken);
        }
        return result;
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
    public static List<GTM_Saved_Configuration__c> getMyConfigurations() {
        // The account and the opportunity both come back, because they answer
        // different questions. One client having several links is normal --
        // different deals, different parts of the business, a deal that closed
        // and restarted months later. Salesforce already models that as one
        // account with many opportunities, and the link carries the
        // opportunity, so the deal is what tells two links apart. Two links on
        // the SAME opportunity is the case worth flagging.
        //
        // Explicit OwnerId backstop (defense-in-depth, issue
        // rep-data-scoping-owd-2): this used to rely entirely on implicit
        // `with sharing` + Private OWD to scope results to "my"
        // configurations -- correct today, but silently wrong the moment OWD
        // on this object ever changes. A user holding viewAllRecords on this
        // object (e.g. GTM_Offering_Admin) still sees everyone's, same as
        // before.
        // No row LIMIT (issue stage-filter-pages-tab): the Pages grid must equal
        // GtmLinkStageService's universe, so a silent 200-row cap would break
        // "stage count == list length". Bounded only by the SOQL row governor.
        // Completeness filter: a Draft was never finished, a null-stage row
        // predates this field entirely, and a Rep_Direct row is a pageless
        // assessment (see createRepDirectAssessment()) with no generated
        // page at all -- none of the three belong in "All Pages". This is
        // the base clause every caller gets; owner-scoping (or its absence,
        // for a viewAllRecords holder) is appended with AND, never used as
        // the sole/optional clause, so the completeness filter can never be
        // accidentally dropped by the owner-scoping branch below.
        Id currentUserId = UserInfo.getUserId();
        String whereClause = ' WHERE Presentation_Stage__c != null'
            + ' AND Presentation_Stage__c != \'Draft\''
            + ' AND Presentation_Stage__c != \'Rep_Direct\'';
        if (!hasViewAllRecords('GTM_Saved_Configuration__c')) {
            whereClause += ' AND OwnerId = :currentUserId';
        }
        return Database.query(
            'SELECT Id, Name, Offering__c, Industry__c, Company__c, ' +
            '       Account__c, Account__r.Name, Contact__c, Contact__r.Name, Contact__r.Email, ' +
            '       Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName, ' +
            '       Generated_URL__c, Active__c, CreatedDate, OwnerId, Owner.Name, ' +
            '       Presentation_Stage__c ' +
            'FROM GTM_Saved_Configuration__c' + whereClause + ' ' +
            'ORDER BY CreatedDate DESC'
        );
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

    /**
     * Toggling this does not delete or hide the record from the rep's own
     * Saved Links list -- it only gates what a client sees when visiting
     * the shared link (see GtmConfigurationStatusController, the small
     * guest-safe class that reads this one field).
     */
    @AuraEnabled
    public static void setActive(String recordId, Boolean active) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No record specified.');
        }
        try {
            update new GTM_Saved_Configuration__c(Id = recordId, Active__c = active);
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not update this link\'s status. Please try again.'
            );
        }
    }

    /**
     * A new password for a link a client says they've lost, generated
     * server-side and handed back once so the rep can relay it -- not a
     * guest-facing "email me my password" flow (that one enumerates and
     * needs its own security pass, see D5 in docs/backlog.md). The rep is
     * already authenticated and already looking at this specific link;
     * this only ever changes Link_Password__c, nothing else on the record.
     */
    @AuraEnabled
    public static String regeneratePassword(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No record specified.');
        }
        String newPassword = randomPassword();
        try {
            update new GTM_Saved_Configuration__c(Id = recordId, Link_Password__c = newPassword);
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not set a new password for this link. Please try again.'
            );
        }
        return newPassword;
    }

    /** Six characters, no ambiguous 0/O/1/I/l -- read over the phone or
     *  typed off a sticky note without a guessing game either way. */
    private static String randomPassword() {
        String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
        String out = '';
        for (Integer i = 0; i < 6; i++) {
            // Widen to Long before abs() -- Integer.MIN_VALUE has no positive
            // Integer counterpart, so abs() on the raw Integer can overflow.
            Long raw = Math.abs((Long) Crypto.getRandomInteger());
            Integer idx = Math.mod(raw, alphabet.length()).intValue();
            out += alphabet.substring(idx, idx + 1);
        }
        return out;
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
     * Public Experience Cloud site URL for the configurator page -- needed
     * only by a caller running OUTSIDE the site itself (e.g. the wizard
     * launched from the internal GTM Offerings Overview Lightning tab,
     * where window.location is a *.lightning.force.com URL, not the site's).
     * A caller already on the live page builds its own link from
     * window.location instead and never needs this.
     *
     * ConnectApi.Communities is a native platform API, not an HTTP callout --
     * safe to call from the same transaction as a DML save. Read-only,
     * returns null if the /gtm site isn't found rather than
     * throwing, since a missing site here should degrade gracefully (the
     * standalone launcher just won't be able to build a link) rather than
     * break anything else on the page.
     */
    @AuraEnabled(cacheable=true)
    public static String getConfiguratorPageUrl() {
        String base = getSiteBaseUrl();
        return base == null ? null : base + '/configurator';
    }

    /**
     * The "Choose your industry" page (see chooseIndustry LWC) -- not the
     * site's bare home route, which is a separate page/view in Experience
     * Builder and does not render chooseIndustry itself. Used by the
     * standalone launcher (the Home page's "New engagement link" button)
     * to send a rep through the same industry-first flow a client-shared
     * link would start from, instead of dropping them straight onto an
     * unpersonalized configurator.
     */
    @AuraEnabled(cacheable=true)
    public static String getSiteHomePageUrl() {
        String base = getSiteBaseUrl();
        return base == null ? null : base + '/choose-offering';
    }

    /**
     * The bare site base (`<site.siteUrl>/s`), unmodified -- for callers
     * that append their own page path, such as gtmReadoutReview's public
     * readout link (`<base>/readout?token=...`). Unlike
     * getSiteHomePageUrl(), this does not append `/choose-offering`; do
     * not change getSiteHomePageUrl() to use this method's behavior, its
     * existing callers (the standalone launcher / "New engagement link")
     * depend on the `/choose-offering` suffix staying exactly as-is.
     */
    @AuraEnabled(cacheable=true)
    public static String getReadoutBaseUrl() {
        return getSiteBaseUrl();
    }

    private static String getSiteBaseUrl() {
        try {
            for (ConnectApi.Community c : ConnectApi.Communities.getCommunities().communities) {
                // Matched on the URL path prefix, not the display name: the
                // prefix is what a saved link actually depends on, and it
                // stays put across a site rename (the label a rep sees is
                // free to change -- "GTM - not live yet" becomes "GTM" at
                // go-live -- without silently breaking every link already
                // sent out).
                if (c.urlPathPrefix == 'gtm' && String.isNotBlank(c.siteUrl)) {
                    return c.siteUrl + '/s';
                }
            }
        } catch (Exception e) {
            // Degrade gracefully -- see comment above.
        }
        return null;
    }

    /**
     * Whether the current user is a rep, and so may see rep-only UI: Gus,
     * the saved links bar, the wizard.
     *
     * This used to return true unconditionally and rely on guests being
     * unable to call it at all -- the guest permission set granted no access,
     * the wire errored, and the caller read that failure as false. That works
     * until you want the site to tell a rep from a prospect, at which point
     * the only signal is an exception, and an exception is indistinguishable
     * from any other reason a call might fail. A rep on the public site was
     * therefore shown the prospect's view.
     *
     * So the answer is computed rather than implied. Guests are the site's
     * own guest user; a prospect who has somehow authenticated is a portal
     * user, not a rep. Only an internal Salesforce user -- someone with a
     * seat in this org -- is a rep.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isConfigManager() {
        return UserInfo.getUserType() == 'Standard';
    }

    /**
     * The whole saved configuration, for a rep reopening their own link.
     *
     * The record already holds everything -- Config_Payload__c is the same
     * JSON the wizard writes -- but nothing read it back, so a rep opening a
     * link they built got an empty wizard and had to retype what was already
     * stored. The URL parameters were the only thing repopulating the page,
     * which is why they had to carry every value in the first place.
     *
     * This lives on the rep-only controller on purpose: it is `with sharing`
     * and the guest permission set is never granted this class, so the payload
     * cannot leak to a prospect through it. The password is deliberately not
     * returned -- knowing a link is protected is GtmLinkAuthController's job,
     * and reading the value is nobody's.
     */
    @AuraEnabled(cacheable=false)
    public static SavedConfigView getConfiguration(String recordId) {
        Id parsedId = GtmLegacyConfigId.resolve(recordId);
        if (parsedId == null) return null;

        List<GTM_Saved_Configuration__c> rows = [
            SELECT Id, Company__c, Industry__c, Industry_Label__c, Offering__c,
                   Config_Payload__c, Generated_URL__c, Active__c, Notify_Email__c,
                   Presentation_Stage__c
            FROM   GTM_Saved_Configuration__c
            WHERE  Id = :parsedId
            LIMIT  1
        ];
        if (rows.isEmpty()) return null;

        GTM_Saved_Configuration__c r = rows[0];
        SavedConfigView v = new SavedConfigView();
        v.recordId      = String.valueOf(r.Id);
        v.company       = r.Company__c;
        v.industry      = r.Industry__c;
        v.industryLabel = r.Industry_Label__c;
        v.offering      = r.Offering__c;
        v.configPayload = r.Config_Payload__c;
        v.generatedUrl  = r.Generated_URL__c;
        v.isActive      = r.Active__c;
        // The wizard's "Notify me at" field re-reads this on reopen so an
        // override a rep already set sticks -- without it, reopening the
        // wizard would have nothing to seed from and would fall back to
        // whichever rep happens to be looking at it right now.
        v.notifyEmail   = r.Notify_Email__c;
        // Lets a rep previewing their own Rep_Direct record (isConfigManager
        // reads through THIS method, not the public one) get routed to the
        // same "skip the branded chapters, render the questionnaire
        // directly" path a prospect gets on the public read -- see
        // GtmConfigurationReader.PublicConfig.presentationStage.
        v.presentationStage = r.Presentation_Stage__c;
        return v;
    }

    public class SavedConfigView {
        @AuraEnabled public String  recordId      { get; set; }
        @AuraEnabled public String  company       { get; set; }
        @AuraEnabled public String  industry      { get; set; }
        @AuraEnabled public String  industryLabel { get; set; }
        @AuraEnabled public String  offering      { get; set; }
        @AuraEnabled public String  configPayload { get; set; }
        @AuraEnabled public String  generatedUrl  { get; set; }
        @AuraEnabled public Boolean isActive      { get; set; }
        @AuraEnabled public String  notifyEmail   { get; set; }
        @AuraEnabled public String  presentationStage { get; set; }
    }

    /** Returns true when the saved record currently has a password set.
     *  Used by the Customize panel to show the rep whether password
     *  protection is active without exposing the password value itself. */
    @AuraEnabled(cacheable=false)
    public static Boolean hasLinkPassword(String recordId) {
        Id resolvedId = GtmLegacyConfigId.resolve(recordId);
        if (resolvedId == null) return false;
        List<GTM_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];
        return !rows.isEmpty() && String.isNotBlank(rows[0].Link_Password__c);
    }

    /**
     * Returns the current plaintext Link_Password__c for a saved link, on
     * explicit demand only -- the rep-facing "view" step's password field
     * is masked by default and calls this exactly once, when the rep
     * clicks "Show" (see gtmRepLinkFinder.js handleRevealPassword). Never
     * prefetched alongside the rest of the page's load data.
     *
     * This class is `with sharing` and never guest-granted (same reasoning
     * as hasLinkPassword/getConfigurationCrmData above), so this inherits
     * record-level access from the calling rep's own sharing rules. Narrow
     * on purpose: selects Link_Password__c by Id only, no other query
     * parameter, matching regeneratePassword's shape.
     */
    @AuraEnabled(cacheable=false)
    public static String getPassword(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No record specified.');
        }
        Id resolvedId = GtmLegacyConfigId.resolve(recordId);
        if (resolvedId == null) {
            throw new AuraHandledException('No record found.');
        }
        List<GTM_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('No record found.');
        }
        return rows[0].Link_Password__c;
    }

    /** Returns the Sales Cloud records linked to a saved config so the
     * Customize panel can pre-fill Contact, Estimated Value, and Opportunity
     * without relying on localStorage (Sales Cloud is the source of truth). */
    @AuraEnabled
    public static CrmData getConfigurationCrmData(String recordId) {
        Id resolvedId = GtmLegacyConfigId.resolve(recordId);
        if (resolvedId == null) return null;
        List<GTM_Saved_Configuration__c> rows = [
            SELECT Contact__c, Contact__r.Name, Contact__r.Email,
                   Account__c, Account__r.Name,
                   Estimated_Value__c,
                   Opportunity__c, Opportunity__r.Name
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;
        GTM_Saved_Configuration__c r = rows[0];
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

    /**
     * Resends the stored magic link URL to the prospect's email address on
     * the linked Contact. This is a repeat-send of the already-saved
     * Generated_URL__c — it does not regenerate the URL or alter any record.
     *
     * Uses setToAddresses (NOT setTargetObjectId) to avoid Salesforce
     * creating an activity log entry on the Contact for an internal
     * re-send the rep initiated. setSaveAsActivity(false) is set for the
     * same reason.
     */
    @AuraEnabled
    public static void resendEngagementLink(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('No record specified.');
        }
        List<GTM_Saved_Configuration__c> rows = [
            SELECT Generated_URL__c, Contact__r.Email, Contact__r.Name, Company__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('No record found.');
        }
        GTM_Saved_Configuration__c rec = rows[0];
        if (String.isBlank(rec.Generated_URL__c)) {
            throw new AuraHandledException('This link has no generated URL to send.');
        }
        String contactEmail = rec.Contact__c != null ? rec.Contact__r.Email : null;
        if (String.isBlank(contactEmail)) {
            throw new AuraHandledException('No contact email address is set on this link. Add a contact with an email before resending.');
        }
        String contactName = rec.Contact__c != null && String.isNotBlank(rec.Contact__r.Name)
            ? rec.Contact__r.Name : 'there';
        String company = String.isNotBlank(rec.Company__c) ? rec.Company__c : 'Publicis Sapient';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ contactEmail });
        mail.setSaveAsActivity(false);
        mail.setSubject('Your engagement link from Publicis Sapient');
        mail.setPlainTextBody(
            'Hi ' + contactName + ',\n\n' +
            'Here is your engagement link from the Publicis Sapient ' + company + ' team:\n\n' +
            rec.Generated_URL__c + '\n\n' +
            'If you have any questions, please reach out directly to your contact at Publicis Sapient.\n\n' +
            'Best regards,\n' +
            'Publicis Sapient'
        );
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    @AuraEnabled
    public static void deleteConfiguration(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No record specified.');
        }
        try {
            delete new GTM_Saved_Configuration__c(Id = recordId);
        } catch (DmlException e) {
            // DELETE_FAILED is what a Restrict lookup (a link with assessment
            // requests) raises, but not only that, and a with-sharing count
            // cannot see guest-owned requests. So the wording stays neutral.
            if (e.getDmlType(0) == StatusCode.DELETE_FAILED) {
                throw new AuraHandledException(
                    'This link cannot be deleted; it may have submitted assessments or other records attached. Deactivate it instead.'
                );
            }
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
     * The per-link notification override, or a sensible default.
     *
     * An explicit override (rep typed a real-looking email) always wins, on
     * both create and edit -- the wizard validates the format client-side,
     * but this is what actually stops a bad value from landing on the
     * record regardless of caller.
     *
     * A brand-new record with no override gets the CREATING user's own
     * email, captured right now rather than resolved later by whoever
     * happens to open the notification path -- "who created this" is a fact
     * about this moment, not a lookup to make lazily at send time. A resave
     * of an EXISTING record with no override supplied returns null, which
     * the caller already treats as "leave whatever is already stored
     * alone" -- the same rule this method's caller applies to
     * accountId/contactId/estimatedValue just above it.
     */
    private static String resolveNotifyEmail(String overrideEmail, Boolean isNewRecord) {
        String trimmed = String.isNotBlank(overrideEmail) ? overrideEmail.trim() : null;
        if (trimmed != null && isValidEmailFormat(trimmed)) {
            return trimmed;
        }
        if (isNewRecord) {
            String creatorEmail = UserInfo.getUserEmail();
            return String.isNotBlank(creatorEmail) ? creatorEmail : null;
        }
        return null;
    }

    /** Loose but real format check -- same intent as the one in
     *  GtmAssessmentRequestController, kept as its own copy rather than a
     *  shared utility for the same reason the account-resolve helpers are:
     *  each file in this feature already owns its own small helpers rather
     *  than pulling in a shared library for one method. */
    private static Boolean isValidEmailFormat(String value) {
        return Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', value);
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
        if (key == 'energy-commodities') return 'Energy';
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
     *
     * Before minting a genuinely new Opportunity (neither the rep's own
     * chosen deal nor this link's existing one applies), checks for an
     * already-open Opportunity on this exact Account + Contact + Offering
     * (see GtmOpenOpportunityDuplicateCheck, issue #32) and blocks with a
     * structured AuraHandledException rather than silently creating a
     * second deal -- unless the caller has already been shown that prompt
     * and explicitly chose to proceed (forceNewOpportunity=true), in which
     * case this falls through to the existing insert, disambiguated only by
     * GtmDealNaming's pre-existing same-Name date-append.
     */
    private static Id resolveOpportunity(String recordId, Id accountId, Id contactId, String company,
                                         Decimal amount, String chosenOpportunityId,
                                         String offeringKey, Boolean forceNewOpportunity) {
        if (accountId == null) return null;

        // The rep's own choice wins. Without this the wizard could only ever
        // mint a new opportunity, so a rep building a second link for a client
        // who already had a live deal got a competing one created underneath
        // them -- which is how one account ended up with two deals nobody had
        // asked for. It is checked against the account so a stray id cannot
        // attach a link to another client's deal.
        if (isValidId(chosenOpportunityId, Opportunity.SObjectType)) {
            List<Opportunity> chosen = [
                SELECT Id FROM Opportunity
                WHERE Id = :(Id) chosenOpportunityId AND AccountId = :accountId
                LIMIT 1
            ];
            if (!chosen.isEmpty()) return chosen[0].Id;
        }

        if (isValidId(recordId, GTM_Saved_Configuration__c.SObjectType)) {
            List<GTM_Saved_Configuration__c> existingLink = [
                SELECT Opportunity__c
                FROM GTM_Saved_Configuration__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (!existingLink.isEmpty() && existingLink[0].Opportunity__c != null) {
                return existingLink[0].Opportunity__c;
            }
        }
        if (forceNewOpportunity != true && String.isNotBlank(offeringKey)) {
            GtmOpenOpportunityDuplicateCheck.Match dup =
                GtmOpenOpportunityDuplicateCheck.findOpenDuplicate(accountId, contactId, offeringKey);
            if (dup != null) {
                throw GtmOpenOpportunityDuplicateCheck.forMatch(dup);
            }
        }

        // One naming authority, shared with the assessment-request path --
        // see GtmDealNaming for why this is not two conventions any more. The
        // offering was hardcoded here, which would have been wrong the day a
        // second offering existed.
        Opportunity opp = new Opportunity(
            Name = GtmDealNaming.nameFor(company, offeringKey, accountId),
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(90),
            Offering_Key__c = trimTo(offeringKey, MAX_OFFERING)
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
