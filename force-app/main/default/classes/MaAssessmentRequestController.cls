/**
 * Handles environment-assessment requests submitted from the Migration
 * Accelerator configurator (LWC: maConfigBooking).
 *
 * Runs `without sharing` deliberately: the request form is reachable by the
 * Experience Cloud guest user, which has no read access to Lead. Finding an
 * existing Lead by email requires elevated context. The blast radius is kept
 * small on purpose — this class exposes exactly one entry point, writes only
 * to Lead / Task / Event, never reflects caller input into SOQL, and takes the
 * notification destination from custom metadata rather than from the caller so
 * the endpoint cannot be used as an open mail relay.
 */
public without sharing class MaAssessmentRequestController {
    private static final String DEFAULT_CONFIG = 'Default';
    private static final Integer MAX_SHORT = 255;
    private static final Integer MAX_LONG = 4000;

    /** Test seam: lets the test class supply config without inserting CMDT. */
    @TestVisible
    private static MA_Assessment_Config__mdt configOverride;

    // ---------------------------------------------------------------- types

    public class RequestInput {
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String email { get; set; }
        @AuraEnabled
        public String company { get; set; }
        @AuraEnabled
        public String role { get; set; }
        @AuraEnabled
        public String currentPlatform { get; set; }
        @AuraEnabled
        public String environmentSize { get; set; }
        @AuraEnabled
        public String timeline { get; set; }
        @AuraEnabled
        public String context { get; set; }
        @AuraEnabled
        public String prospect { get; set; }
        @AuraEnabled
        public String industry { get; set; }
    }

    public class RequestResult {
        @AuraEnabled
        public Boolean success { get; set; }
        @AuraEnabled
        public String leadId { get; set; }
        @AuraEnabled
        public Boolean leadCreated { get; set; }
        @AuraEnabled
        public Boolean emailSent { get; set; }
        @AuraEnabled
        public String message { get; set; }

        public RequestResult() {
            this.success = false;
            this.leadCreated = false;
            this.emailSent = false;
        }
    }

    // ------------------------------------------------------------ entry point

    /**
     * Records an assessment request. Any combination of lead capture and email
     * notification can be switched on in the MA_Assessment_Config custom
     * metadata record; both switched off simply validates and returns.
     */
    @AuraEnabled
    public static RequestResult submitRequest(RequestInput input) {
        RequestResult result = new RequestResult();

        if (input == null) {
            throw new AuraHandledException('No request data was supplied.');
        }
        String cleanName = trimTo(input.name, MAX_SHORT);
        String cleanEmail = trimTo(input.email, MAX_SHORT);

        if (String.isBlank(cleanName)) {
            throw new AuraHandledException('Please enter your name.');
        }
        if (!isValidEmail(cleanEmail)) {
            throw new AuraHandledException('Please enter a valid work email.');
        }

        MA_Assessment_Config__mdt cfg = loadConfig();

        try {
            Boolean createLead = (Boolean) cfg.get('Create_Lead__c');
            Boolean sendEmail = (Boolean) cfg.get('Send_Email__c');
            String notifyEmail = (String) cfg.get('Notify_Email__c');

            if (createLead == true) {
                applyLead(input, cleanName, cleanEmail, cfg, result);
            }
            if (sendEmail == true && String.isNotBlank(notifyEmail)) {
                result.emailSent = notify(input, cleanName, cleanEmail, cfg);
            }
            result.success = true;
            result.message = 'Request received.';
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not record your request. Please try again, or email us directly.'
            );
        }
        return result;
    }

    // ----------------------------------------------------------------- config

    private static MA_Assessment_Config__mdt loadConfig() {
        if (configOverride != null) {
            return configOverride;
        }
        List<MA_Assessment_Config__mdt> rows = [
            SELECT Notify_Email__c, Create_Lead__c, Send_Email__c,
                   Lead_Source__c, Activity_Type__c
            FROM MA_Assessment_Config__mdt
            WHERE DeveloperName = :DEFAULT_CONFIG
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            return rows[0];
        }
        // No config deployed yet — capture the lead, stay quiet otherwise.
        return new MA_Assessment_Config__mdt(
            Create_Lead__c = true,
            Send_Email__c = false,
            Lead_Source__c = 'Migration Accelerator',
            Activity_Type__c = 'Task'
        );
    }

    // ------------------------------------------------------------------- lead

    private static void applyLead(
        RequestInput input,
        String cleanName,
        String cleanEmail,
        MA_Assessment_Config__mdt cfg,
        RequestResult result
    ) {
        String leadSourceCfg = (String) cfg.get('Lead_Source__c');
        String leadSource = String.isBlank(leadSourceCfg)
            ? 'Migration Accelerator'
            : leadSourceCfg;

        List<Lead> existing = [
            SELECT Id, Company, Title, LeadSource
            FROM Lead
            WHERE Email = :cleanEmail AND IsConverted = FALSE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Lead target;
        if (existing.isEmpty()) {
            target = new Lead(
                FirstName = firstNameOf(cleanName),
                LastName = lastNameOf(cleanName),
                Email = cleanEmail,
                Company = companyOrFallback(input),
                Title = trimTo(input.role, MAX_SHORT),
                LeadSource = leadSource
            );
            insert target;
            result.leadCreated = true;
        } else {
            // Existing lead: fill blanks only, never overwrite owned data.
            target = existing[0];
            Boolean dirty = false;
            String company = trimTo(input.company, MAX_SHORT);
            if (String.isBlank(target.Company) && String.isNotBlank(company)) {
                target.Company = company;
                dirty = true;
            }
            String role = trimTo(input.role, MAX_SHORT);
            if (String.isBlank(target.Title) && String.isNotBlank(role)) {
                target.Title = role;
                dirty = true;
            }
            if (String.isBlank(target.LeadSource)) {
                target.LeadSource = leadSource;
                dirty = true;
            }
            if (dirty) {
                update target;
            }
        }

        result.leadId = target.Id;
        logActivity(target.Id, input, cleanName, cleanEmail, cfg);
    }

    private static void logActivity(
        Id leadId,
        RequestInput input,
        String cleanName,
        String cleanEmail,
        MA_Assessment_Config__mdt cfg
    ) {
        String subject = 'Environment assessment request';
        String body = buildSummary(input, cleanName, cleanEmail);
        String activityType = (String) cfg.get('Activity_Type__c');

        if ('Event'.equalsIgnoreCase(activityType)) {
            insert new Event(
                WhoId = leadId,
                Subject = subject,
                Description = body,
                StartDateTime = System.now(),
                DurationInMinutes = 30
            );
        } else {
            insert new Task(
                WhoId = leadId,
                Subject = subject,
                Description = body,
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = System.today()
            );
        }
    }

    // ------------------------------------------------------------------ email

    private static Boolean notify(
        RequestInput input,
        String cleanName,
        String cleanEmail,
        MA_Assessment_Config__mdt cfg
    ) {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        String notifyEmail = (String) cfg.get('Notify_Email__c');
        msg.setToAddresses(new List<String>{ notifyEmail });
        msg.setSubject(
            'Assessment request — ' +
            (String.isBlank(input.company) ? cleanName : trimTo(input.company, 80))
        );
        msg.setPlainTextBody(buildSummary(input, cleanName, cleanEmail));
        msg.setSaveAsActivity(false);

        List<Messaging.SendEmailResult> sent = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ msg },
            false
        );
        return !sent.isEmpty() && sent[0].isSuccess();
    }

    private static String buildSummary(
        RequestInput input,
        String cleanName,
        String cleanEmail
    ) {
        List<String> lines = new List<String>{
            'New environment-assessment request',
            '',
            'Name: ' + cleanName,
            'Work email: ' + cleanEmail,
            'Company: ' + dash(input.company),
            'Role: ' + dash(input.role),
            'Current platform: ' + dash(input.currentPlatform),
            'Environment size: ' + dash(input.environmentSize),
            'Timeline: ' + dash(input.timeline),
            'What is prompting the move: ' + dash(input.context),
            '',
            'Prospect page: ' + dash(input.prospect),
            'Industry: ' + dash(input.industry),
            'Submitted: ' + System.now().format(),
            'Source: Migration Accelerator configurator'
        };
        return trimTo(String.join(lines, '\n'), MAX_LONG);
    }

    // ----------------------------------------------------------------- helpers

    private static Boolean isValidEmail(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        return Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', value);
    }

    private static String firstNameOf(String fullName) {
        List<String> parts = fullName.trim().split('\\s+');
        return parts.size() > 1 ? trimTo(parts[0], 40) : null;
    }

    private static String lastNameOf(String fullName) {
        List<String> parts = fullName.trim().split('\\s+');
        if (parts.size() > 1) {
            List<String> lastParts = new List<String>();
            for (Integer i = 1; i < parts.size(); i++) {
                lastParts.add(parts[i]);
            }
            return trimTo(String.join(lastParts, ' '), 80);
        }
        return trimTo(fullName, 80);
    }

    private static String companyOrFallback(RequestInput input) {
        String company = trimTo(input.company, MAX_SHORT);
        if (String.isNotBlank(company)) {
            return company;
        }
        String prospect = trimTo(input.prospect, MAX_SHORT);
        return String.isNotBlank(prospect) ? prospect : 'Unknown';
    }

    private static String dash(String value) {
        return String.isBlank(value) ? '—' : trimTo(value, MAX_SHORT);
    }

    private static String trimTo(String value, Integer max) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() > max ? trimmed.substring(0, max) : trimmed;
    }
}
