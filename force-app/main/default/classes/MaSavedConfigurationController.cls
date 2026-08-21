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
    }

    @AuraEnabled
    public static Id saveConfiguration(SaveInput input) {
        if (input == null || String.isBlank(input.generatedUrl)) {
            throw new AuraHandledException('A generated link is required to save a configuration.');
        }
        if (String.isBlank(input.offering)) {
            throw new AuraHandledException('An offering is required to save a configuration.');
        }

        // Found-or-created here, not looked up by the rep: the Company
        // field they already type is enough to stand up the Account (and
        // client-contact name/email, when given, the Contact) the first
        // time this link is saved, so Sales Cloud has something to attach
        // an Opportunity to later without a separate setup step.
        Id accountId = resolveAccount(trimTo(input.company, MAX_COMPANY));
        Id contactId = resolveContact(input.clientContactName, input.clientContactEmail, accountId);

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
        Decimal estimatedValue = parseDecimal(input.estimatedValue);
        if (estimatedValue != null) {
            record.Estimated_Value__c = estimatedValue;
        }

        try {
            if (String.isNotBlank(input.recordId)) {
                record.Id = input.recordId;
                update record;
            } else {
                insert record;
            }
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not save this link. Please try again, or check that the record still exists.'
            );
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

    private static String trimTo(String value, Integer maxLen) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.length() > maxLen ? trimmed.substring(0, maxLen) : trimmed;
    }

    /**
     * Exact-name match, not fuzzy: good enough to stop the same rep from
     * creating a second Account every time they resave the same client's
     * link, without guessing at a dedupe strategy more sophisticated than
     * this feature actually needs. A rep who wants to attach to an
     * existing Account under a different name can still just retype the
     * Company field to match it exactly, or fix the link later in Sales
     * Cloud.
     */
    private static Id resolveAccount(String company) {
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
        insert acc;
        return acc.Id;
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
