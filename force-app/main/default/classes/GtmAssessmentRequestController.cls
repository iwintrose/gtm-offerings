/**
 * Handles environment-assessment requests submitted from the Migration
 * Accelerator configurator (LWC: maConfigBooking).
 *
 * Runs `without sharing` deliberately: the request form is reachable by the
 * Experience Cloud guest user, which has no read access to Contact. Finding an
 * existing Contact by email requires elevated context. The blast radius is kept
 * small on purpose — this class exposes exactly one entry point, writes only
 * to Account / Contact / Task / Event, never reflects caller input into SOQL,
 * and takes the notification destination from custom metadata rather than from
 * the caller so the endpoint cannot be used as an open mail relay.
 */
public without sharing class GtmAssessmentRequestController {
    private static final String DEFAULT_CONFIG = 'Default';
    private static final Integer MAX_SHORT = 255;
    private static final Integer MAX_LONG = 4000;

    /** Test seam: lets the test class supply config without inserting CMDT. */
    @TestVisible
    private static GTM_Assessment_Config__mdt configOverride;

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
        // Rich assessment fields (added with v2 form)
        @AuraEnabled public String targetPlatform      { get; set; }
        @AuraEnabled public String budgetRange         { get; set; }
        @AuraEnabled public String contactCount        { get; set; }
        @AuraEnabled public String monthlySendVolume   { get; set; }
        @AuraEnabled public String painPoints          { get; set; }
        @AuraEnabled public String migrationGoals      { get; set; }
        @AuraEnabled public String keyIntegrations     { get; set; }
        @AuraEnabled public String successCriteria     { get; set; }
        @AuraEnabled public String internalTeamSize    { get; set; }
        @AuraEnabled public String executiveSponsorship{ get; set; }
        @AuraEnabled public String decisionMakers      { get; set; }
        @AuraEnabled public String urgencyDriver       { get; set; }
        /** cfgId of the MA_Saved_Configuration__c the requester was viewing,
         * when the booking happened from a client's configured link. Used
         * to attribute the Contact to the right rep and to file the request
         * under the right Opportunity -- see resolveConfigContext(). */
        @AuraEnabled
        public String savedRecordId { get; set; }
        /**
         * HMAC token issued by GtmLinkAuthController.verifyAndIssueToken().
         * Required when the engagement link has a password set; ignored
         * (not checked) for direct bookings and unprotected links.
         */
        @AuraEnabled
        public String submissionToken { get; set; }
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
        /** Populated when the link has Link_Password__c set; used by
         * validateTokenIfRequired() to re-derive the expected HMAC. */
        String linkPassword;
    }

    public class RequestResult {
        @AuraEnabled
        public Boolean success { get; set; }
        @AuraEnabled
        public String contactId { get; set; }
        @AuraEnabled
        public Boolean contactCreated { get; set; }
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
            this.contactCreated = false;
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

        GTM_Assessment_Config__mdt cfg = loadConfig();
        ConfigContext ctx = resolveConfigContext(input.savedRecordId);
        validateTokenIfRequired(input.savedRecordId, input.submissionToken, ctx);
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
            ctx.company = trimTo(input.company, MAX_SHORT);
        }

        try {
            Boolean createContact = (Boolean) cfg.get('Create_Lead__c');
            Boolean sendEmail = (Boolean) cfg.get('Send_Email__c');
            String notifyEmail = (String) cfg.get('Notify_Email__c');

            if (createContact == true) {
                applyContact(input, cleanName, cleanEmail, cfg, ctx, result);
            }
            // Runs after applyContact so the OpportunityContactRole below
            // can attach the requester, not just the Account.
            ensureOpportunity(input.savedRecordId, ctx, cleanName);
            // Runs after both, so the activity lands on the Opportunity
            // (WhatId) as well as the Contact (WhoId) -- the rep working
            // the Opportunity sees what happened and when without having
            // to go find the Contact's own timeline.
            logActivity(ctx.contactId, ctx.opportunityId, input, cleanName, cleanEmail, cfg);
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
                       Company__c, Offering__c, Estimated_Value__c, Link_Password__c
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
                ctx.linkPassword = rows[0].Link_Password__c;
            }
        } catch (Exception e) {
            // Malformed id, or no read access -- proceed unlinked.
        }
        return ctx;
    }

    /**
     * Same exact-name-match find-or-create as
     * GtmSavedConfigurationController.resolveAccount -- kept as its own copy
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
     * One Opportunity per Engagement Link, not one per submission. Every
     * distinct person who touches that link -- the rep's own pick when
     * setting it up, and every requester who later submits an assessment
     * through it -- lands as an additional OpportunityContactRole on the
     * same Opportunity, rather than spawning a new one each time. A
     * different link for the same Account (a different rep, a restarted
     * cycle) still gets its own Opportunity, since reuse is keyed off the
     * link's own stored Opportunity__c, never a name/Account match.
     * Best-effort, like the rest of this file's linkage: a failure here
     * should never block the submission that's already otherwise
     * succeeded.
     */
    private static void ensureOpportunity(String savedRecordId, ConfigContext ctx, String requesterName) {
        if (ctx.accountId == null) {
            return;
        }
        try {
            Id opportunityId = ctx.opportunityId;
            Boolean linkedToEngagementLink = isId(savedRecordId);
            if (opportunityId == null) {
                // One naming authority, shared with the link-saving path --
                // see GtmDealNaming. This used to build its own name with a
                // different word order and a different dash.
                Opportunity opp = new Opportunity(
                    Name = GtmDealNaming.nameFor(ctx.company, ctx.offering, ctx.accountId),
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
                if (linkedToEngagementLink) {
                    opp.Engagement_Link__c = (Id) Id.valueOf(savedRecordId);
                }
                insert opp;
                opportunityId = opp.Id;

                if (linkedToEngagementLink) {
                    update new MA_Saved_Configuration__c(
                        Id = (Id) Id.valueOf(savedRecordId),
                        Opportunity__c = opportunityId
                    );
                }
            }
            ctx.opportunityId = opportunityId;
            ensureOpportunityContactRole(opportunityId, ctx.contactId);
        } catch (Exception e) {
            // No Opportunity this time -- the Contact/Task/assessment
            // record path already succeeded and isn't affected.
        }
    }

    /**
     * Adds the Contact to the Opportunity if it isn't already there.
     * Claims primary only when the Opportunity has no primary Contact
     * yet, so a second (or third) distinct person submitting through the
     * same link adds a role instead of erroring on a duplicate primary.
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


    private static Decimal offeringAnnualTarget(String offeringKey) {
        if (String.isBlank(offeringKey)) {
            return null;
        }
        try {
            List<GTM_Offering__mdt> rows = [
                SELECT Annual_Target__c
                FROM GTM_Offering__mdt
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
     * client's link, the Contact, and the Opportunity when known -- instead of
     * the request only existing as free text buried in a Task description.
     * Best-effort: a failure here must never take down the Contact/Task path
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
            Id cfgId = isId(input.savedRecordId) ? (Id) Id.valueOf(input.savedRecordId) : null;

            GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
                Saved_Configuration__c  = cfgId,
                Opportunity__c          = ctx.opportunityId,
                Account__c              = ctx.accountId,
                Contact__c              = ctx.contactId,
                Requester_Name__c       = cleanName,
                Requester_Email__c      = cleanEmail,
                Company__c              = trimTo(input.company, MAX_SHORT),
                Role__c                 = trimTo(input.role, MAX_SHORT),
                Current_Platform__c     = trimTo(input.currentPlatform, MAX_SHORT),
                Environment_Size__c     = trimTo(input.environmentSize, MAX_SHORT),
                Timeline__c             = trimTo(input.timeline, MAX_SHORT),
                Context__c              = trimTo(input.context, MAX_LONG),
                // Rich v2 fields
                Target_Platform__c      = trimTo(input.targetPlatform, MAX_SHORT),
                Budget_Range__c         = trimTo(input.budgetRange, MAX_SHORT),
                Contact_Count__c        = parseIntOrNull(input.contactCount),
                Monthly_Send_Volume__c  = parseIntOrNull(input.monthlySendVolume),
                Pain_Points__c          = trimTo(input.painPoints, MAX_LONG),
                Migration_Goals__c      = trimTo(input.migrationGoals, MAX_LONG),
                Key_Integrations__c     = trimTo(input.keyIntegrations, MAX_LONG),
                Success_Criteria__c     = trimTo(input.successCriteria, MAX_LONG),
                Internal_Team_Size__c   = trimTo(input.internalTeamSize, MAX_SHORT),
                Executive_Sponsorship__c= trimTo(input.executiveSponsorship, MAX_SHORT),
                Decision_Makers__c      = trimTo(input.decisionMakers, MAX_SHORT),
                Urgency_Driver__c       = trimTo(input.urgencyDriver, MAX_SHORT),
                Submitted_At__c         = DateTime.now(),
                Status__c               = 'New',
                Source__c               = 'Migration Accelerator'
            );
            if (ctx.ownerId != null) {
                req.OwnerId = ctx.ownerId;
            }
            insert req;

            // Advance the linked config to Assessment stage
            if (cfgId != null) {
                try {
                    update new MA_Saved_Configuration__c(
                        Id = cfgId,
                        Presentation_Stage__c = 'Assessment'
                    );
                } catch (Exception ex) {
                    System.debug('Could not set Assessment stage: ' + ex.getMessage());
                }
            }
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

    private static GTM_Assessment_Config__mdt loadConfig() {
        if (configOverride != null) {
            return configOverride;
        }
        List<GTM_Assessment_Config__mdt> rows = [
            SELECT Notify_Email__c, Create_Lead__c, Send_Email__c, Activity_Type__c
            FROM GTM_Assessment_Config__mdt
            WHERE DeveloperName = :DEFAULT_CONFIG
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            return rows[0];
        }
        // No config deployed yet — create contact, stay quiet otherwise.
        return new GTM_Assessment_Config__mdt(
            Create_Lead__c = true,
            Send_Email__c = false,
            Activity_Type__c = 'Task'
        );
    }

    // --------------------------------------------------------------- contact

    /**
     * Finds or creates a Contact scoped to the resolved Account.
     * Fills blank Title from the submitted role; never overwrites existing data.
     */
    private static void applyContact(
        RequestInput input,
        String cleanName,
        String cleanEmail,
        GTM_Assessment_Config__mdt cfg,
        ConfigContext ctx,
        RequestResult result
    ) {
        List<Contact> existing = [
            SELECT Id, AccountId, Title
            FROM Contact
            WHERE Email = :cleanEmail AND AccountId = :ctx.accountId
            LIMIT 1
        ];

        Contact target;
        if (existing.isEmpty()) {
            target = new Contact(
                FirstName = firstNameOf(cleanName),
                LastName = lastNameOf(cleanName),
                Email = cleanEmail,
                AccountId = ctx.accountId,
                Title = trimTo(input.role, MAX_SHORT)
            );
            if (ctx.ownerId != null) {
                target.OwnerId = ctx.ownerId;
            }
            insert target;
            result.contactCreated = true;
        } else {
            target = existing[0];
            Boolean dirty = false;
            if (String.isBlank(target.Title) && String.isNotBlank(input.role)) {
                target.Title = trimTo(input.role, MAX_SHORT);
                dirty = true;
            }
            if (dirty) {
                update target;
            }
        }

        result.contactId = target.Id;
        ctx.contactId = target.Id;
    }

    /**
     * Logs the submission as a Task or Event (per config) against both the
     * Contact (WhoId) and the Opportunity (WhatId) when known, so the
     * timeline of what happened and when shows up on the Opportunity a rep
     * is actually working, not just buried on the Contact. Called once,
     * after both the Contact and the Opportunity have been resolved --
     * never from inside applyContact, which runs before the Opportunity
     * exists.
     */
    private static void logActivity(
        Id contactId,
        Id opportunityId,
        RequestInput input,
        String cleanName,
        String cleanEmail,
        GTM_Assessment_Config__mdt cfg
    ) {
        if (contactId == null) {
            return;
        }
        String subject = 'Environment assessment request';
        String body = buildSummary(input, cleanName, cleanEmail);
        String activityType = (String) cfg.get('Activity_Type__c');

        if ('Event'.equalsIgnoreCase(activityType)) {
            Event e = new Event(
                WhoId = contactId,
                Subject = subject,
                Description = body,
                StartDateTime = System.now(),
                DurationInMinutes = 30
            );
            if (opportunityId != null) {
                e.WhatId = opportunityId;
            }
            insert e;
        } else {
            Task t = new Task(
                WhoId = contactId,
                Subject = subject,
                Description = body,
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = System.today()
            );
            if (opportunityId != null) {
                t.WhatId = opportunityId;
            }
            insert t;
        }
    }

    // ------------------------------------------------------------------ email

    private static Boolean notify(
        RequestInput input,
        String cleanName,
        String cleanEmail,
        GTM_Assessment_Config__mdt cfg
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

    // ------------------------------------------------------------ token gate

    /**
     * Enforces the submission token when the linked engagement link has a
     * password set. Throws AuraHandledException (visible to the LWC) on
     * any failure — missing token, wrong format, expired, wrong record, or
     * invalid HMAC.
     *
     * The HMAC is verified with a constant-time comparison to prevent
     * timing side-channels. Secret is the stored Link_Password__c, which
     * is never returned to the caller.
     *
     * Skips validation entirely when:
     *   - No savedRecordId was supplied (direct booking, no link)
     *   - The linked config has no Link_Password__c (unprotected link)
     */
    private static void validateTokenIfRequired(
        String savedRecordId,
        String token,
        ConfigContext ctx
    ) {
        if (!isId(savedRecordId) || String.isBlank(ctx.linkPassword)) {
            return; // Not a password-protected link — nothing to enforce.
        }

        if (String.isBlank(token)) {
            throw new AuraHandledException(
                'A submission token is required. Please enter the access password again.'
            );
        }

        // Expected format: "<recordId>:<epochSeconds>:<hmacHex>"
        List<String> parts = token.split(':');
        if (parts.size() != 3) {
            throw new AuraHandledException('Invalid submission token. Please refresh and try again.');
        }

        String tokenRecordId = parts[0];
        Long tokenEpoch;
        try {
            tokenEpoch = Long.valueOf(parts[1]);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid submission token. Please refresh and try again.');
        }
        String tokenHmac = parts[2];

        // Must be for the same record this request references.
        if (tokenRecordId != savedRecordId) {
            throw new AuraHandledException('Submission token does not match this link. Please refresh and try again.');
        }

        // Must be within the valid window (30 min, matching GtmLinkAuthController).
        Long nowEpoch = System.now().getTime() / 1000L;
        if (nowEpoch - tokenEpoch > 1800L) {
            throw new AuraHandledException(
                'Your session has expired. Please re-enter the access password.'
            );
        }

        // Verify the HMAC (constant-time comparison prevents timing attacks).
        String payload = tokenRecordId + ':' + parts[1];
        Blob expected = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(ctx.linkPassword));
        String expectedHex = EncodingUtil.convertToHex(expected);
        if (!constantTimeEqual(expectedHex, tokenHmac)) {
            throw new AuraHandledException('Invalid submission token. Please refresh and try again.');
        }
    }

    /** Compares two hex strings in O(n) time to prevent HMAC timing attacks. */
    private static Boolean constantTimeEqual(String a, String b) {
        if (a == null || b == null || a.length() != b.length()) return false;
        Integer diff = 0;
        for (Integer i = 0; i < a.length(); i++) {
            diff |= a.charAt(i) ^ b.charAt(i);
        }
        return diff == 0;
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

    private static Decimal parseIntOrNull(String value) {
        if (String.isBlank(value)) return null;
        try {
            return Decimal.valueOf(value.trim().replaceAll('[^0-9]', ''));
        } catch (Exception e) {
            return null;
        }
    }
}
