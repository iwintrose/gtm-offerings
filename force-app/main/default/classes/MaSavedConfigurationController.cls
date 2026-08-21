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
    }

    @AuraEnabled
    public static Id saveConfiguration(SaveInput input) {
        if (input == null || String.isBlank(input.generatedUrl)) {
            throw new AuraHandledException('A generated link is required to save a configuration.');
        }
        if (String.isBlank(input.offering)) {
            throw new AuraHandledException('An offering is required to save a configuration.');
        }

        MA_Saved_Configuration__c record = new MA_Saved_Configuration__c(
            Offering__c = trimTo(input.offering, MAX_OFFERING),
            Industry__c = trimTo(input.industry, MAX_INDUSTRY),
            Company__c = trimTo(input.company, MAX_COMPANY),
            Generated_URL__c = input.generatedUrl,
            Config_Payload__c = input.configPayload
        );

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
}
