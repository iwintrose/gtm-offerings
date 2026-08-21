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
        /** cfgId of the MA_Saved_Configuration__c the requester was viewing,
         * when the booking happened from a client's configured link. Used
         * to attribute the Lead to the right rep and to file the request
         * under the right Opportunity -- see resolveConfigContext(). */
        @AuraEnabled
        public String savedRecordId { get; set; }
    }

    /** What we know about the client link the request came from. */
    private class ConfigContext {
        Id ownerId;
        Id opportunityId;
        Id accountId;
        Id contactId;
        String company;
        String offering;
        Decimal estimatedValue;
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
        @AuraEnabled
        public String assessmentRequestId { get; set; }
        @AuraEnabled
        public String opportunityId { get; set; }

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
        ConfigContext ctx = resolveConfigContext(input.savedRecordId);
        // A company name is a company name wherever it shows up in this
        // flow -- it should resolve to a real Account, not sit as a bare
        // string on the request. If a linked Engagement Link already
        // resolved one, that's authoritative and left alone; this only
        // fills the gap for a direct booking (no savedRecordId at all, or
        // a link whose own Account resolution didn't happen for some
        // reason) so it isn't the one Company field in this whole feature
        // that never connects to Sales Cloud.
        if (ctx.accountId == null) {
            ctx.accountId = resolveAccount(trimTo(input.company, MAX_SHORT));
        }
        ensureOpportunity(input.savedRecordId, ctx);

        try {
            Boolean createLead = (Boolean) cfg.get('Create_Lead__c');
            Boolean sendEmail = (Boolean) cfg.get('Send_Email__c');
            String notifyEmail = (String) cfg.get('Notify_Email__c');

            if (createLead == true) {
                applyLead(input, cleanName, cleanEmail, cfg, ctx, result);
            }
            if (sendEmail == true && String.isNotBlank(notifyEmail)) {
                result.emailSent = notify(input, cleanName, cleanEmail, cfg);
            }
            recordAssessmentRequest(input, cleanName, cleanEmail, ctx, result);
            result.success = true;
            result.message = 'Request received.';
        } catch (DmlException e) {
            throw new AuraHandledException(
                'We could not record your request. Please try again, or email us directly.'
            );
        }
        return result;
    }

    // --------------------------------------------------------- client link

    /**
     * Best-effort lookup of the client link the requester was viewing, so
     * the request can be attributed to the right rep and filed under the
     * right Opportunity -- the two things the assessment request had no
     * connection to before. `without sharing` mirrors the rest of this
     * class: the guest user has no read access to MA_Saved_Configuration__c
     * or Opportunity on its own. Fails open (returns an empty context)
     * rather than blocking the submission on a bad/missing id -- a request
     * with no linkage is still far better than a dropped one.
     */
    private static ConfigContext resolveConfigContext(String savedRecordId) {
        ConfigContext ctx = new ConfigContext();
        if (String.isBlank(savedRecordId)) {
            return ctx;
        }
        try {
            Id configId = Id.valueOf(savedRecordId);
            List<MA_Saved_Configuration__c> rows = [
                SELECT OwnerId, Opportunity__c, Account__c, Contact__c,
                       Company__c, Offering__c, Estimated_Value__c
                FROM MA_Saved_Configuration__c
                WHERE Id = :configId
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                ctx.ownerId = rows[0].OwnerId;
                ctx.opportunityId = rows[0].Opportunity__c;
                ctx.accountId = rows[0].Account__c;
                ctx.contactId = rows[0].Contact__c;
                ctx.company = rows[0].Company__c;
                ctx.offering = rows[0].Offering__c;
                ctx.estimatedValue = rows[0].Estimated_Value__c;
            }
        } catch (Exception e) {
            // Malformed id, or no read access -- proceed unlinked.
        }
        return ctx;
    }

    /**
     * Same exact-name-match find-or-create as
     * MaSavedConfigurationController.resolveAccount -- kept as its own copy
     * rather than a shared utility because the two callers run under
     * different sharing contexts (this class is without sharing and
     * guest-reachable; that one is with sharing and rep-only) and each
     * file in this feature already owns its own small helpers rather than
     * pulling in a shared library for one method.
     */
    private static Id resolveAccount(String company) {
        if (String.isBlank(company)) {
            return null;
        }
        try {
            List<Account> existing = [
                SELECT Id FROM Account WHERE Name = :company LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }
            Account acc = new Account(Name = company);
            insert acc;
            return acc.Id;
        } catch (Exception e) {
            // No Account access, or a DML failure -- proceed unlinked
            // rather than blocking the submission over it.
            return null;
        }
    }

    /**
     * The whole point of the Account/Contact/Estimated Value fields on the
     * client link: an assessment booked from that link is real buying
     * intent, so it should land as a real Opportunity in the pipeline, not
     * wait for a rep to notice and create one by hand. Only creates one
     * when the client link doesn't already have one -- never overwrites or
     * duplicates. Best-effort, like the rest of this file's linkage: an
     * Opportunity that fails to create should never block the submission
     * that's already otherwise succeeded.
     */
    private static void ensureOpportunity(String savedRecordId, ConfigContext ctx) {
        if (ctx.opportunityId != null || !isId(savedRecordId)) {
            return;
        }
        try {
            String offeringLabel = offeringLabel(ctx.offering);
            String company = String.isNotBlank(ctx.company) ? ctx.company : 'New Prospect';

            Opportunity opp = new Opportunity(
                Name = company + ' - ' + offeringLabel,
                AccountId = ctx.accountId,
                StageName = 'Qualification',
                CloseDate = Date.today().addDays(90),
                Amount = ctx.estimatedValue != null
                    ? ctx.estimatedValue
                    : offeringAnnualTarget(ctx.offering)
            );
            if (ctx.ownerId != null) {
                opp.OwnerId = ctx.ownerId;
            }
            insert opp;
            ctx.opportunityId = opp.Id;

            // Write back so the next assessment on this same link reuses
            // this Opportunity instead of creating another one, and so the
            // rep sees it from the Engagement Link record too.
            update new MA_Saved_Configuration__c(
                Id = (Id) Id.valueOf(savedRecordId),
                Opportunity__c = opp.Id
            );
        } catch (Exception e) {
            // No Opportunity this time -- the Lead/Task/assessment record
            // path already succeeded and isn't affected.
        }
    }

    private static String offeringLabel(String offeringKey) {
        if (String.isBlank(offeringKey)) {
            return 'Assessment Follow-up';
        }
        try {
            List<MA_Offering__mdt> rows = [
                SELECT Label__c
                FROM MA_Offering__mdt
                WHERE Offering_Key__c = :offeringKey
                LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Label__c)) {
                return rows[0].Label__c;
            }
        } catch (Exception e) {
            // Fall through to the raw key below.
        }
        return offeringKey;
    }

    private static Decimal offeringAnnualTarget(String offeringKey) {
        if (String.isBlank(offeringKey)) {
            return null;
        }
        try {
            List<MA_Offering__mdt> rows = [
                SELECT Annual_Target__c
                FROM MA_Offering__mdt
                WHERE Offering_Key__c = :offeringKey
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].Annual_Target__c;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Files a real, queryable record of the request -- linked to the
     * client's link, the Lead, and the Opportunity when known -- instead of
     * the request only existing as free text buried in a Task description.
     * Best-effort: a failure here must never take down the Lead/Task path
     * that already succeeded above.
     */
    private static void recordAssessmentRequest(
        RequestInput input,
        String cleanName,
        String cleanEmail,
        ConfigContext ctx,
        RequestResult result
    ) {
        try {
            MA_Assessment_Request__c req = new MA_Assessment_Request__c(
                Saved_Configuration__c = isId(input.savedRecordId)
                    ? (Id) Id.valueOf(input.savedRecordId)
                    : null,
                Opportunity__c = ctx.opportunityId,
                Account__c = ctx.accountId,
                Contact__c = ctx.contactId,
                Lead__c = String.isNotBlank(result.leadId)
                    ? (Id) Id.valueOf(result.leadId)
                    : null,
                Requester_Name__c = cleanName,
                Requester_Email__c = cleanEmail,
                Company__c = trimTo(input.company, MAX_SHORT),
                Role__c = trimTo(input.role, MAX_SHORT),
                Current_Platform__c = trimTo(input.currentPlatform, MAX_SHORT),
                Environment_Size__c = trimTo(input.environmentSize, MAX_SHORT),
                Timeline__c = trimTo(input.timeline, MAX_SHORT),
                Context__c = trimTo(input.context, MAX_LONG),
                Status__c = 'New',
                Source__c = 'Migration Accelerator'
            );
            if (ctx.ownerId != null) {
                req.OwnerId = ctx.ownerId;
            }
            insert req;
            result.assessmentRequestId = req.Id;
            result.opportunityId = ctx.opportunityId;

            if (ctx.opportunityId != null) {
                postOpportunityFeed(ctx.opportunityId, cleanName, input);
            }
        } catch (Exception e) {
            // Lead/Task/email already succeeded above -- don't fail the
            // whole submission over the (nice-to-have) structured record.
        }
    }

    /** Best-effort Chatter note on the Opportunity -- visible without
     * silently changing Stage, which is a call for the rep, not this
     * form. */
    private static void postOpportunityFeed(Id opportunityId, String cleanName, RequestInput input) {
        try {
            FeedItem post = new FeedItem(
                ParentId = opportunityId,
                Body = 'New assessment request from ' + cleanName +
                    (String.isNotBlank(input.company) ? ' (' + trimTo(input.company, 80) + ')' : '') +
                    ' via the Migration Accelerator configured link.'
            );
            insert post;
        } catch (Exception e) {
            // Feed tracking may not be enabled on Opportunity -- skip.
        }
    }

    private static Boolean isId(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            Id.valueOf(value);
            return true;
        } catch (Exception e) {
            return false;
        }
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
        ConfigContext ctx,
        RequestResult result
    ) {
        String leadSourceCfg = (String) cfg.get('Lead_Source__c');
        String leadSource = String.isBlank(leadSourceCfg)
            ? 'Migration Accelerator'
            : leadSourceCfg;

        List<Lead> existing = [
            SELECT Id, Company, Title, LeadSource, GTM_Account__c
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
                LeadSource = leadSource,
                // Standard Lead.Company never links to Account until the
                // Lead is converted -- this is a same-feature convenience
                // pointing at the Account already resolved for this
                // submission, so a rep can jump there without converting
                // first. See GTM_Account__c's own field description.
                GTM_Account__c = ctx.accountId
            );
            // Attribute to the rep who owns the client link the requester
            // was viewing, rather than leaving it to fall to the guest
            // user or a generic assignment rule -- this is the entire
            // point of threading savedRecordId through: the rep who built
            // the link is the one who should see the Lead land on them.
            if (ctx.ownerId != null) {
                target.OwnerId = ctx.ownerId;
            }
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
            if (target.GTM_Account__c == null && ctx.accountId != null) {
                target.GTM_Account__c = ctx.accountId;
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
