/**
 * Handles environment-assessment requests submitted from the Migration
 * Accelerator configurator (LWC: maConfigBooking) and from the branching
 * readiness questionnaire (LWC: gtmAssessmentQuestionnaire).
 *
 * Runs `without sharing` deliberately: the request form is reachable by the
 * Experience Cloud guest user, which has no read access to Contact. Finding an
 * existing Contact by email requires elevated context. The blast radius is kept
 * small on purpose — this class exposes exactly one entry point, writes only
 * to Account / Contact / Task / Event / GTM_Assessment_Request__c, never
 * reflects caller input into SOQL, and takes the notification destination
 * from custom metadata rather than from the caller so the endpoint cannot be
 * used as an open mail relay.
 *
 * Scoring is the other thing that follows from being guest-reachable: the
 * migration-readiness score and tier are computed here, by GtmAssessmentScoring,
 * from the raw answers, and the estate-complexity score by GtmEstateComplexity.
 * They are never taken from the request body. See the notes on
 * RequestInput.assessmentScore.
 *
 * Two override rules sit on top of the readiness band, and both are applied
 * server-side for the same reason the score is: a client must not be able to
 * talk its way past either.
 *   - the ACCESS GATE caps the tier at Discovery First when the source-access
 *     answer is at the floor. No extract, no offering;
 *   - the UNSUPPORTED-PAIR GATE suppresses the tier entirely when the routing
 *     answer names a source or target the accelerator cannot process. Which
 *     pairs those are is configuration (GTM_Migration_Pair__mdt, read by
 *     GtmMigrationPairs), not code -- see resolvePairEligibility below.
 */
public without sharing class GtmAssessmentRequestController {
    /**
     * DeveloperName of the shared fallback config record. No longer how the
     * fallback is FOUND -- loadConfig() now finds it by a blank Offering_Key__c,
     * per ADR-0007 -- kept only so the record still has a name in this file for
     * anyone tracing it back to Setup.
     */
    private static final String DEFAULT_CONFIG = 'Default';
    private static final Integer MAX_SHORT = 255;
    private static final Integer MAX_LONG = 4000;

    /**
     * The one message every submission-token failure throws -- blank, malformed,
     * wrong record, expired, or a bad HMAC. These used to throw five different
     * sentences; a respondent who ran out the 30-minute window while still
     * mid-form (very plausible on a resumed draft link) saw "a submission token
     * is required", which reads as a bug, not a timeout. They are now the SAME
     * string on purpose: gtmAssessmentQuestionnaire.js matches this exact
     * message to trigger its re-auth overlay, and every one of these cases has
     * the same correct recovery -- re-enter the password, get a fresh token,
     * retry the same submit. This string must stay byte-identical to
     * TOKEN_REAUTH_MESSAGE in gtmAssessmentQuestionnaire.js; there is no shared
     * error-code convention elsewhere in this codebase to hang it on instead.
     */
    private static final String TOKEN_REAUTH_MESSAGE =
        'Your session has expired. Please re-enter the access password to send your assessment.';
    /** Capacity of Section_Scores__c (see its field metadata). */
    private static final Integer MAX_SECTION_SCORES = 32768;

    /** Test seam: lets the test class supply config without inserting CMDT. */
    @TestVisible
    private static GTM_Assessment_Config__mdt configOverride;

    /**
     * Test seam: forces the GTM_Assessment_Request__c insert to fail so a test
     * can prove the submit is atomic (Contact/Opportunity/Task rolled back).
     * Always false in production.
     */
    @TestVisible
    private static Boolean failAssessmentRequestInsert = false;

    private static final String SUBMIT_FAILED_MESSAGE =
        'We could not record your assessment, and nothing was saved. ' +
        'Your answers are still here, so please try sending again in a moment.';

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
        /**
         * The raw scored answers, one entry per dimension. This is the only
         * scoring input Apex trusts: GtmAssessmentScoring turns it into the
         * total, the tier and the per-section breakdown that actually get
         * stored. See recordAssessmentRequest.
         */
        @AuraEnabled public List<AnswerInput> answers  { get; set; }
        /**
         * The raw estate-complexity answers, one entry per dimension of the
         * SECOND axis (GtmEstateComplexity, 6-18). Kept as its own list rather
         * than merged into `answers` because the two instruments are
         * deliberately never summed: readiness says whether the work can be
         * scoped, complexity says how big it is. Merging them here would be the
         * first step towards a single blended number, which is the thing the
         * two-axis design exists to prevent.
         */
        @AuraEnabled public List<AnswerInput> complexityAnswers { get; set; }
        /**
         * Layer-4 supplement answers -- the extra questions a pair's pack adds
         * OUTSIDE the eight. Its own list for the same reason complexityAnswers
         * is its own list: these produce their own named index and must never be
         * summable into the 32. Scored entries carry `value` (1-3); unscored
         * verbatim probes carry `text` and are recorded, never computed on.
         */
        @AuraEnabled public List<AnswerInput> supplementAnswers { get; set; }
        /**
         * "Self-Estimated" (the prospect's pre-scan guess, which is all a
         * questionnaire can ever be) or "Measured" (recomputed post-scan from a
         * real extract). Anything else is stored as null rather than as a
         * guess: presenting a self-estimate as a measurement is the one
         * mistake this field exists to make impossible.
         */
        @AuraEnabled public String complexityBasis { get; set; }
        /**
         * IGNORED — kept only so an older client that still sends these does
         * not fail deserialization on an unknown property.
         *
         * These used to be stored verbatim: the browser computed the score and
         * the tier, and Apex wrote down whatever arrived. That made a prospect
         * the author of their own readiness score, and that score is what drives
         * the readout a rep then sends them. Both values are now recomputed
         * from `answers` on the server and whatever is passed here is discarded
         * -- discarded rather than validated, because validating a
         * client-supplied score still means the client picked which of the
         * acceptable values to claim.
         */
        @AuraEnabled public Decimal assessmentScore    { get; set; }
        /** IGNORED — recomputed from `answers`. See assessmentScore. */
        @AuraEnabled public String assessmentTier      { get; set; }
        /**
         * Legacy JSON string, e.g. {"estate_scale":3,"source_access":2}.
         * Used only when no `answers` were supplied at all, so submissions from
         * a client predating the answer contract keep the breakdown they
         * already had. When `answers` are present this is ignored and the
         * breakdown is rebuilt from them.
         */
        @AuraEnabled public String sectionScores       { get; set; }
        /** Q0 routing answer: MCE, MCAE, Both, Non-Salesforce, or None. */
        @AuraEnabled public String branchPlatform      { get; set; }
        /** cfgId of the GTM_Saved_Configuration__c the requester was viewing,
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
        /**
         * The resume token of the GTM_Form_Draft__c (Draft_Type__c =
         * 'Assessment') session this submission was finished from, when the
         * respondent had saved their place. Optional -- a form filled in one
         * sitting has none.
         *
         * It is used for exactly one thing: closing the draft in this same
         * transaction (see closeDraft). It is never read for answers. The
         * answers scored here are the ones in this payload, from the browser
         * that pressed send, exactly as they were before drafts existed --
         * because a submit path that could pull answers from a token would be a
         * second way to get answers into a scored record, and one of the two
         * would eventually diverge.
         */
        @AuraEnabled
        public String draftToken { get; set; }
        /**
         * GENERIC PATH (docs/architecture/gtm-instrument-schema.md). Per-question
         * answers for a submission scored against the new, offering-agnostic
         * GTM_Instrument_Definition__c / _Question_Definition__c schema -- a
         * single flat JSON object keyed by each question's Question_Key__c,
         * e.g. {"q1":"yes","q2":["a","b"]}. Stored verbatim (after a shape
         * check) into Answers_JSON__c.
         *
         * PRESENCE OF THIS FIELD SELECTS THE PATH. When it is supplied,
         * recordAssessmentRequest takes the generic path: it stores this blob
         * and the Offering__c lookup and does NOT run GtmAssessmentInstrument /
         * GtmAssessmentScoring / GtmEstateComplexity, and does NOT populate any
         * Migration-Accelerator-only field (Estate_Complexity_*__c,
         * Instrument_Pair__c, Instrument_Branch_Path__c) -- those stay null on
         * a generic-path request. When it is blank, the legacy `answers`-driven
         * Migration Accelerator path below runs exactly as before.
         */
        @AuraEnabled
        public String answersJson { get; set; }
    }

    /**
     * One scored questionnaire answer. `dimension` is one of
     * GtmAssessmentScoring.DIMENSIONS; anything else is ignored rather than
     * rejected, so a client that ships a new question before the server knows
     * about it degrades to a lower score instead of a failed submission.
     * `value` is 1-4; out-of-range values are dropped, not clamped.
     */
    public class AnswerInput {
        @AuraEnabled public String dimension { get; set; }
        @AuraEnabled public Integer value    { get; set; }
        /**
         * Free text, used only by the unscored verbatim probes in a supplement
         * set. Ignored entirely on the scored lists: nothing a prospect types
         * into a text box can move a number, which is the same reason
         * assessmentScore is discarded.
         */
        @AuraEnabled public String text      { get; set; }
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
        /** Per-link notification override (GTM_Saved_Configuration__c.
         * Notify_Email__c). Preferred over the org-wide CMDT Notify_Email__c
         * -- see the notifyEmail resolution in submitRequest() below. Blank
         * only for a direct booking with no link, or a link saved before
         * this field existed and never resaved since. */
        String notifyEmail;
        /** GTM_Saved_Configuration__c.Presentation_Stage__c as it stood
         * before this submission. Used by postInsertBestEffort() to decide
         * whether to advance the stage to 'Assessment' -- a Rep_Direct
         * config is permanent/pageless for its entire life (see
         * GtmSavedConfigurationController.generateRepDirectShareLink()'s
         * doc comment) and must never be moved out of that stage by a real
         * submission. Null whenever resolveConfigContext() could not read
         * the row (bad/missing id, no access, or an exception) -- treated
         * the same as "not Rep_Direct" so the fail-open behavior of this
         * whole method is unchanged.
         */
        String presentationStage;
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
     * notification can be switched on in the GTM_Assessment_Config custom
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

        ConfigContext ctx = resolveConfigContext(input.savedRecordId);
        // Resolved ONCE, here, and threaded everywhere below. Which offering
        // this submission belongs to decides which instrument scores it, which
        // config governs it, and what is stamped on the request -- so it is one
        // decision made in one place rather than three independent derivations
        // of "probably the same thing" (ADR-0007 section 3).
        String offeringKey = resolveOfferingKey(ctx);
        GTM_Assessment_Config__mdt cfg = loadConfig(offeringKey);
        validateTokenIfRequired(input.savedRecordId, input.submissionToken, ctx);

        // ONE SUBMITTED ASSESSMENT PER ENGAGEMENT LINK (ADR-0008 section 4).
        //
        // Placed AFTER resolveConfigContext and validateTokenIfRequired and
        // BEFORE any DML, so a refused duplicate writes nothing at all -- not a
        // Contact, not an Opportunity, not an activity -- and so a caller who
        // has not passed the password gate is told about the gate rather than
        // about somebody else's submission.
        //
        // The client mirrors this (gtmConfigurator.hasSubmittedAssessment, and
        // the durable GtmConfigurationStatusController.hasSubmittedAssessment
        // check behind it) so a respondent is not invited to re-answer fifteen
        // minutes of questions. The client is a COURTESY; this is where the
        // invariant is true.
        //
        // SCOPED TO LINKS ONLY. A direct booking with no savedRecordId has
        // nothing to be a duplicate of, and refusing those would silently close
        // the one path that has no link at all.
        //
        // EXISTENCE, NOT SCORE. Gated on a request existing, not on
        // Assessment_Score__c being populated. Every pre-fix booking in this org
        // is scoreless (that is the D11 bug), so gating on a score would leave
        // exactly those links permanently re-submittable -- the bug wearing a
        // hat.
        //
        // FAILS CLOSED, unlike resolveConfigContext which fails open by design.
        // A failure to determine duplicate-ness must not admit a second scored
        // request. GtmLegacyConfigId.resolve returning null is not a bypass: it
        // means the id was unusable, the submission proceeds UNLINKED, and an
        // unlinked request has no link to be a duplicate against.
        if (String.isNotBlank(input.savedRecordId)) {
            Id linkId = GtmLegacyConfigId.resolve(input.savedRecordId);
            if (linkId != null) {
                List<GTM_Assessment_Request__c> already = [
                    SELECT Id
                    FROM   GTM_Assessment_Request__c
                    WHERE  Saved_Configuration__c = :linkId
                    LIMIT  1
                ];
                if (!already.isEmpty()) {
                    // AuraHandledException, not a silent success: the client has
                    // to be able to tell this apart from a network failure so it
                    // can render the "already submitted" state rather than
                    // inviting a retry. The message names the recovery, so a
                    // prospect who genuinely needs to redo it has a route rather
                    // than a dead end.
                    throw new AuraHandledException(
                        'An assessment has already been submitted for this link. ' +
                        'Your rep can send a new one if you need to start again.'
                    );
                }
            }
        }

        // A company name is a company name wherever it shows up in this
        // flow -- it should resolve to a real Account, not sit as a bare
        // string on the request. If a linked Engagement Link already
        // resolved one, that's authoritative and left alone; this only
        // fills the gap for a direct booking (no savedRecordId at all, or
        // a link whose own Account resolution didn't happen for some
        // reason) so it isn't the one Company field in this whole feature
        // that never connects to Sales Cloud.
        // ATOMIC WRITE SECTION. Everything from here to the assessment request
        // insert (Account, Contact, Opportunity, Task/Event, the request) is one
        // unit: if the request cannot be written, all of it is rolled back so a
        // retry cannot leave orphaned Contacts/Opportunities/Tasks or duplicates.
        // https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/langCon_apex_transaction_control.htm
        // https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_methods_system_database.htm
        Savepoint sp = Database.setSavepoint();
        if (ctx.accountId == null) {
            ctx.accountId = resolveAccount(trimTo(input.company, MAX_SHORT));
            ctx.company = trimTo(input.company, MAX_SHORT);
        }

        try {
            Boolean createContact = (Boolean) cfg.get('Create_Lead__c');
            Boolean sendEmail = (Boolean) cfg.get('Send_Email__c');
            // The link's own field wins when it has one -- which, going
            // forward, is every link (GtmSavedConfigurationController
            // resolves and stores it at creation time, defaulting to the
            // creating rep). The org-wide CMDT value is only still consulted
            // as a fallback for a direct booking (no engagement link at all)
            // or a link saved before this field existed and never resaved.
            // Send_Email__c on the CMDT record stays the one global
            // kill-switch either way.
            String notifyEmail = String.isNotBlank(ctx.notifyEmail)
                ? ctx.notifyEmail
                : (String) cfg.get('Notify_Email__c');

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
            // The request insert is the commit point: it throws on failure
            // (no longer swallowed) so the catch below rolls everything back.
            recordAssessmentRequest(input, cleanName, cleanEmail, ctx, offeringKey, result);
            // After the request, so a rolled-back submission never notifies
            // anyone about something that was not saved.
            if (sendEmail == true && String.isNotBlank(notifyEmail)) {
                result.emailSent = notify(input, cleanName, cleanEmail, notifyEmail);
            }
            // INVALIDATION ON SUBMIT. In the same transaction as the request,
            // so a submitted assessment and a live resume link cannot coexist:
            // if this rolls back, so does the request. See closeDraft's own
            // comment for why this is an append, not an update.
            closeDraft(input.draftToken, result.assessmentRequestId);
            result.success = true;
            result.message = 'Request received.';
        } catch (Exception e) {
            // Roll back Account/Contact/Opportunity/Task and the request itself.
            // Never swallowed: the client gets a clear, retryable error, and
            // nothing prospect-supplied is echoed in it.
            Database.rollback(sp);
            AuraHandledException ahe = new AuraHandledException(SUBMIT_FAILED_MESSAGE);
            ahe.setMessage(SUBMIT_FAILED_MESSAGE);
            throw ahe;
        }
        return result;
    }

    // --------------------------------------------------------- client link

    /**
     * Best-effort lookup of the client link the requester was viewing, so
     * the request can be attributed to the right rep and filed under the
     * right Opportunity -- the two things the assessment request had no
     * connection to before. `without sharing` mirrors the rest of this
     * class: the guest user has no read access to GTM_Saved_Configuration__c
     * or Opportunity on its own. Fails open (returns an empty context)
     * rather than blocking the submission on a bad/missing id -- a request
     * with no linkage is still far better than a dropped one.
     */
    private static ConfigContext resolveConfigContext(String savedRecordId) {
        ConfigContext ctx = new ConfigContext();
        Id configId = GtmLegacyConfigId.resolve(savedRecordId);
        if (configId == null) {
            return ctx;
        }
        try {
            List<GTM_Saved_Configuration__c> rows = [
                SELECT OwnerId, Opportunity__c, Account__c, Contact__c,
                       Company__c, Offering__c, Estimated_Value__c, Link_Password__c,
                       Notify_Email__c, Presentation_Stage__c
                FROM GTM_Saved_Configuration__c
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
                ctx.notifyEmail = rows[0].Notify_Email__c;
                ctx.presentationStage = rows[0].Presentation_Stage__c;
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
            Id resolvedConfigId = GtmLegacyConfigId.resolve(savedRecordId);
            Boolean linkedToEngagementLink = resolvedConfigId != null;
            if (opportunityId == null) {
                // One naming authority, shared with the link-saving path --
                // see GtmDealNaming. This used to build its own name with a
                // different word order and a different dash.
                // No open-duplicate block on this path (issue #32): reuse is
                // already keyed off the link's own stored Opportunity__c
                // above, not by an Account/Contact/Offering match, and this
                // is a guest-reachable, best-effort submission flow with no
                // UI able to show the wizard's two-choice prompt.
                // Offering_Key__c is still populated so this Opportunity is
                // visible to (and, for later links, matchable by) the
                // wizard-side check.
                Opportunity opp = new Opportunity(
                    Name = GtmDealNaming.nameFor(ctx.company, ctx.offering, ctx.accountId),
                    AccountId = ctx.accountId,
                    StageName = 'Qualification',
                    CloseDate = Date.today().addDays(90),
                    Amount = ctx.estimatedValue != null
                        ? ctx.estimatedValue
                        : offeringAnnualTarget(ctx.offering),
                    Offering_Key__c = ctx.offering
                );
                if (ctx.ownerId != null) {
                    opp.OwnerId = ctx.ownerId;
                }
                // Engagement_Link__c set dynamically, not through dot-notation
                // -- a static reference to this exact field is what blocks
                // Salesforce from letting it be deleted and recreated, which
                // is the only way to repoint an existing Lookup's referenceTo.
                if (linkedToEngagementLink) {
                    opp.put('Engagement_Link__c', resolvedConfigId);
                }
                insert opp;
                opportunityId = opp.Id;

                if (linkedToEngagementLink) {
                    SObject cfgUpdate = Schema.getGlobalDescribe().get('GTM_Saved_Configuration__c').newSObject();
                    cfgUpdate.put('Id', resolvedConfigId);
                    cfgUpdate.put('Opportunity__c', opportunityId);
                    update cfgUpdate;
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


    /**
     * The Source__c display label for a request.
     *
     * A JUDGEMENT CALL flagged by ADR-0007's plan (2.5) rather than pre-decided
     * there. Source__c is a display label saying where a request came from, and
     * it was the hardcoded literal 'Migration Accelerator'. Left as that
     * literal it would silently mislabel every future offering's submissions as
     * Migration Accelerator's -- and Source__c is what a rep filters a list
     * view by, so a wrong value there is not cosmetic, it hides work.
     *
     * Resolved in the SAME three tiers, in the same order, that
     * GtmPageContentController.getOfferings() already resolves an offering's
     * display name in -- deliberately mirroring it rather than inventing a
     * fourth lookup strategy, because an offering that shows one name in the
     * offering picker and a different one on the request it produced is its
     * own bug:
     *
     *   1. GTM_Offering__mdt.Label__c -- the same table offeringAnnualTarget()
     *      below reads. Migration Accelerator has such a row, and its label is
     *      byte-identical to LEGACY_SOURCE_LABEL, so its rows keep the exact
     *      string they have always had and no existing row's value changes.
     *   2. The name on the offering's own offerings-listing tile
     *      (GTM_Page_Content__c). Custom metadata deploys asynchronously and an
     *      offering created through the Content Manager has page content long
     *      before it has a CMDT row -- today BOTH of gtm-dev's non-Migration-
     *      Accelerator offerings are in exactly that state, so without this
     *      tier they are stamped 'Migration Accelerator', which is the
     *      mislabelling this method exists to prevent.
     *   3. A GTM_Page_Section__c row proves the offering is REAL even when
     *      nobody has authored a name for it anywhere. It then gets its own raw
     *      key -- the same label = key convention getOfferings() and
     *      getHomeSummary() both fall back to. A real offering showing its key
     *      is honest; showing another offering's name is not.
     *
     * LEGACY_SOURCE_LABEL is the terminal fallback ONLY: a blank key, or a key
     * that resolves to nothing in all three tables (a typo, a synthetic test
     * key -- a genuinely unknown offering). Such a key is NOT given a truthful
     * name by this method, because none exists to give; it keeps the historical
     * literal. That is a deliberate limit of this fix, not an oversight.
     *
     * This is copy, not schema, so the risk either way is low -- but only one
     * of the options is still correct after a second offering exists.
     */
    private static String sourceLabelFor(String offeringKey) {
        if (String.isBlank(offeringKey)) {
            return LEGACY_SOURCE_LABEL;
        }
        try {
            List<GTM_Offering__mdt> rows = [
                SELECT Label__c
                FROM GTM_Offering__mdt
                WHERE Offering_Key__c = :offeringKey
                LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Label__c)) {
                return rows[0].Label__c;
            }
        } catch (Exception e) {
            // A missing or unreadable offering table must not cost the whole
            // submission a label it can still supply from a later tier.
        }
        try {
            List<GTM_Page_Content__c> named = [
                SELECT Text_Value__c
                FROM   GTM_Page_Content__c
                WHERE  Template_Type__c = 'offerings-listing'
                AND    Field_Key__c     = 'name'
                AND    Offering_Key__c  = :offeringKey
                AND    Active__c        = true
                LIMIT  1
            ];
            if (!named.isEmpty() && String.isNotBlank(named[0].Text_Value__c)) {
                return named[0].Text_Value__c;
            }
        } catch (Exception e) {
            // Same reasoning as above: an unreadable content table costs the
            // label a tier, never the submission.
        }
        try {
            List<GTM_Page_Section__c> real = [
                SELECT Id
                FROM   GTM_Page_Section__c
                WHERE  Offering_Key__c = :offeringKey
                AND    Active__c       = true
                LIMIT  1
            ];
            if (!real.isEmpty()) {
                return offeringKey;
            }
        } catch (Exception e) {
            // Ditto.
        }
        return LEGACY_SOURCE_LABEL;
    }

    private static final String LEGACY_SOURCE_LABEL = 'Migration Accelerator';

    /**
     * Best-effort resolution of the Offering__c native lookup: the Active
     * GTM_Instrument_Definition__c row for this offering (docs/architecture/
     * gtm-instrument-schema.md section 2.1), or null when the offering has
     * not been authored on the new schema yet -- expected for every offering
     * at launch (schema.md section 7: "no migration/seed... all four new
     * ... objects start empty"). Never blocks the submission: an unreadable
     * table or a missing row degrades to null, exactly like offeringAnnualTarget
     * and sourceLabelFor above.
     */
    private static Id resolveOfferingDefinitionId(String offeringKey) {
        if (String.isBlank(offeringKey)) {
            return null;
        }
        try {
            List<GTM_Instrument_Definition__c> rows = [
                SELECT Id
                FROM   GTM_Instrument_Definition__c
                WHERE  Offering_Key__c = :offeringKey
                AND    Status__c = 'Active'
                LIMIT  1
            ];
            return rows.isEmpty() ? null : rows[0].Id;
        } catch (Exception e) {
            return null;
        }
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
     * The request insert is NOT best-effort: it throws so submitRequest rolls
     * back the whole transaction. Only the steps after the insert (stage
     * advance, feed post, draft readout) are best-effort.
     */
    private static void recordAssessmentRequest(
        RequestInput input,
        String cleanName,
        String cleanEmail,
        ConfigContext ctx,
        String offeringKey,
        RequestResult result
    ) {
        {
            Id cfgId = GtmLegacyConfigId.resolve(input.savedRecordId);

            // GENERIC PATH SELECTOR (docs/architecture/gtm-instrument-schema.md).
            // A submission scored against the new, offering-agnostic
            // GTM_Instrument_Definition__c schema carries input.answersJson and
            // nothing else scoring-related; it never runs the Migration-
            // Accelerator-only pipeline below (GtmAssessmentInstrument /
            // GtmAssessmentScoring / GtmEstateComplexity) and never populates
            // Estate_Complexity_*__c, Instrument_Pair__c or
            // Instrument_Branch_Path__c. See RequestInput.answersJson.
            Boolean isGenericPath = String.isNotBlank(input.answersJson);

            // Score on the server, from the raw answers, every time.
            // input.assessmentScore / input.assessmentTier are not read at all
            // -- see their comments on RequestInput. A submission with no
            // answers scores to nulls, which is the same record shape an
            // unscored submission has always produced.
            // WHICH eight questions were asked is a property of the pair, so
            // it is resolved before scoring and recorded alongside the result.
            // Fails open to the base pack -- see GtmAssessmentInstrument.resolve.
            GtmAssessmentInstrument.Pack pack;
            GtmAssessmentScoring.Score scored;
            GtmAssessmentReadout.SupplementResult supplements;
            GtmEstateComplexity.Complexity complexity;

            if (isGenericPath) {
                // Nothing on the Migration-Accelerator scoring pipeline runs
                // for a generic-schema submission -- see isGenericPath above.
                pack = null;
                scored = new GtmAssessmentScoring.Score();
                supplements = new GtmAssessmentReadout.SupplementResult();
                complexity = new GtmEstateComplexity.Complexity();
            } else {
                pack = resolveInstrumentPack(offeringKey, input);

                // ANSWER-DRIVEN BRANCHING, resolved on the server from the submitted
                // answers. The questionnaire resolved the same branches as the
                // respondent moved through it, so that it could show the right next
                // question -- but that resolution is a rendering decision and this
                // one is the scoring decision. If a client branched differently, its
                // answers arrive under keys this pack did not resolve, and the
                // scorer never reads a key it did not ask for. Same allowlist,
                // reached from a new direction. See GtmAssessmentInstrument.applyBranches.
                Map<String, Integer> readinessAnswers = answerMap(input.answers);
                pack = GtmAssessmentInstrument.applyBranches(pack, readinessAnswers);

                scored = GtmAssessmentScoring.score(
                    offeringKey,
                    readinessAnswers,
                    resolvePairEligibility(offeringKey, input),
                    pack
                );

                // Layer 4, scored into its own named index and stored in its own
                // field. It cannot reach Assessment_Score__c from here, and that is
                // structural rather than a matter of remembering.
                supplements =
                    GtmAssessmentReadout.scoreSupplements(
                        pack,
                        answerMap(input.supplementAnswers),
                        noteMap(input.supplementAnswers)
                    );

                // The second axis, scored the same way and stored beside the first
                // -- never added into it. See GtmEstateComplexity's header.
                // Scored against the dimensions THIS PACK resolved, for the same
                // reason the readiness half is scored against its resolved slots:
                // a HubSpot respondent is asked about workflows and properties, not
                // about journeys and 30-100 tables, and the answer has to land under
                // the key they were actually asked. Answers under keys the pack did
                // not resolve are never read.
                complexity =
                    GtmEstateComplexity.score(
                        offeringKey,
                        answerMap(input.complexityAnswers),
                        pack == null ? null : pack.complexityKeys()
                    );
            }

            GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
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
                // Assessment_Score__c / Assessment_Tier__c and every field below
                // through Instrument_Branch_Path__c are the Migration-Accelerator
                // scoring pipeline's OUTPUT -- null on the generic path (isGenericPath),
                // exactly as `scored`/`complexity`/`supplements` were default-
                // constructed with no answers above.
                Assessment_Score__c     = scored.total,
                // Null whenever the pair gate fired -- a scored record with no
                // band is the shape that says "deliberately not banded".
                Assessment_Tier__c      = scored.tier,
                Assessment_Advisory__c  = scored.advisory,
                Advisory_Reason__c      = trimTo(scored.advisoryReason, MAX_SHORT),
                Assessment_Flags__c     = scored.annotationsJson,
                // MIGRATION-ACCELERATOR-ONLY FIELDS. Stripped out of the generic
                // path per docs/agent-artifacts/task-scope-assessment-instrument-
                // rebuild-02-submission.md -- left entirely null (not populated,
                // not defaulted) for a generic-schema submission.
                Estate_Complexity_Score__c = isGenericPath ? null : complexity.total,
                Estate_Complexity_Band__c  = isGenericPath ? null : complexity.band,
                // A basis with no score behind it is noise, so it is written
                // only when there is actually a number to label.
                Estate_Complexity_Basis__c = (!isGenericPath && complexity.hasAnswers)
                    ? defaultBasis(input.complexityBasis)
                    : null,
                Estate_Complexity_Dimensions__c = isGenericPath ? null : sanitizeSectionScores(
                    complexity.dimensionScoresJson
                ),
                // Server-derived whenever there are answers to derive it from;
                // the legacy client blob only survives when there are none. Not
                // populated at all on the generic path -- see Answers_JSON__c.
                Section_Scores__c       = isGenericPath ? null : sanitizeSectionScores(
                    scored.hasAnswers ? scored.sectionScoresJson : input.sectionScores
                ),
                // Which pack scored this, and which edition of it. Without the
                // pair key a stored Section_Scores__c blob stops being readable
                // the moment a pack is edited -- a 2 against a key nobody can
                // look up. See the field's own description. Null on the generic
                // path -- there is no GtmAssessmentInstrument.Pack there at all.
                Instrument_Pair__c      = isGenericPath ? null : trimTo(pack.pairKey, 80),
                Instrument_Version__c   = isGenericPath ? null : trimTo(pack.version, 40),
                // What it was scored OUT OF, and WHICH questions filled the
                // eight slots. Both derived here and never read from the
                // client, for the same reason the score is: option points and
                // branch predicates are author-editable, so a readout reopened
                // after an edit needs the frame it was actually measured
                // against rather than today's.
                Instrument_Max_Score__c = isGenericPath ? null : scored.maxTotal,
                Instrument_Branch_Path__c = isGenericPath ? null : trimTo(scored.branchPathJson, 4096),
                Supplement_Scores__c    = isGenericPath ? null : sanitizeSectionScores(supplements.json),
                Branch_Platform__c      = trimTo(input.branchPlatform, MAX_SHORT),
                // GENERIC PATH ONLY (docs/architecture/gtm-instrument-schema.md):
                // one flat JSON object keyed by Question_Key__c. Never populated
                // on the legacy Migration-Accelerator path -- see
                // RequestInput.answersJson.
                Answers_JSON__c         = isGenericPath
                    ? sanitizeSectionScores(input.answersJson)
                    : null,
                Submitted_At__c         = DateTime.now(),
                Status__c               = 'New',
                // Which offering's instrument actually scored this. Set once,
                // server-side, never client-supplied (ADR-0007 section 3).
                Offering_Key__c         = trimTo(offeringKey, 80),
                // Native lookup counterpart to Offering_Key__c -- the
                // GTM_Instrument_Definition__c row for this offering, when one
                // has been authored on the new schema (docs/architecture/
                // gtm-instrument-schema.md section 2.1). Best-effort, resolved
                // server-side, never client-supplied; null for any offering
                // that has not yet been migrated onto the new schema.
                Offering__c              = resolveOfferingDefinitionId(offeringKey),
                Source__c               = sourceLabelFor(offeringKey)
            );
            if (ctx.ownerId != null) {
                req.OwnerId = ctx.ownerId;
            }
            // Saved_Configuration__c set dynamically -- see the comment on
            // the same pattern in ensureOpportunity() above.
            req.put('Saved_Configuration__c', cfgId);
            if (failAssessmentRequestInsert == true) {
                throw new DmlException('Forced assessment request insert failure (test seam).');
            }
            insert req;
            result.assessmentRequestId = req.Id;
            result.opportunityId = ctx.opportunityId;
            postInsertBestEffort(req, cfgId, ctx, cleanName, input);
        }
    }

    private static void postInsertBestEffort(
        GTM_Assessment_Request__c req, Id cfgId, ConfigContext ctx,
        String cleanName, RequestInput input
    ) {
        try {
            // Advance the linked config to Assessment stage -- but never for
            // a Rep_Direct config. Rep_Direct is permanent/pageless for its
            // entire life (GtmSavedConfigurationController.
            // generateRepDirectShareLink()'s doc comment: "never changes
            // that value"); flipping it here would silently break the
            // gtmConfigurator.js isRepDirect gate (line ~816) and fall the
            // record through to branded-chapter rendering it was never
            // meant to have. ctx.presentationStage is null whenever
            // resolveConfigContext() could not resolve the row, which
            // compares unequal to 'Rep_Direct' and so preserves today's
            // fail-open behavior (advance the stage) on that path.
            if (cfgId != null && ctx.presentationStage != 'Rep_Direct') {
                try {
                    SObject cfgUpdate = Schema.getGlobalDescribe().get('GTM_Saved_Configuration__c').newSObject();
                    cfgUpdate.put('Id', cfgId);
                    cfgUpdate.put('Presentation_Stage__c', 'Assessment');
                    update cfgUpdate;
                } catch (Exception ex) {
                    System.debug('Could not set Assessment stage: ' + ex.getMessage());
                }
            }
            if (ctx.opportunityId != null) {
                postOpportunityFeed(ctx.opportunityId, cleanName, input);
            }

            // The server-computed score and tier are already on req at this
            // point -- generate the Draft readout now so a rep has one
            // waiting the moment the request lands. Best-effort: a failure
            // here must never take down a submission that already succeeded;
            // the readout can always be generated later from the request.
            generateDraftReadout(req.Id);

            // Notification wiring point 7 (ADR-0010, Unit 3b; corrected
            // location -- see docs/agent-artifacts/task-scope-
            // notifications-unit-3b-lifecycle-wiring.md §1a). This class is
            // `without sharing` and guest-reachable (Experience Cloud
            // prospect submission), so the Task owner must be req.OwnerId
            // (already resolved server-side above), never the running --
            // possibly guest -- user.
            GtmNotificationSettingsController.NotificationSettingsDto settings =
                GtmNotificationSettingsController.getOrgDefaults();
            if (settings.notifyOnNewAssessmentRequest && req.OwnerId != null) {
                GtmLifecycleNotificationService.fireTask(req.Id, req.OwnerId,
                    GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST,
                    'A new assessment request came in and needs review.');
                GtmLifecycleNotificationService.fireBell(req.OwnerId, req.Id,
                    'New assessment request', 'A new assessment request came in and needs review.');
            }

            // Issue #31 engagement-state Task, distinct from the
            // notification-settings-gated SUBJECT_NEW_REQUEST Task just
            // above: that one targets req.Id (the request record itself,
            // "go review this"), always owned by req.OwnerId, and is
            // switchable off by an org-wide setting. This one targets the
            // prospect's own Contact (preferred) or Account -- coalesce
            // applied here, Contact preferred, same as every other
            // engagement-state call site -- so it lands on that record's
            // Activity timeline, and always fires: it is not a
            // "notify someone" preference, it is the same-shape replacement
            // for the retired Engagement Links tab's own always-on
            // submitted_draft row. ctx.contactId reflects applyContact's
            // already-run resolution (a Contact is created/found before
            // this request is even inserted -- see applyContact and its own
            // `ctx.contactId = target.Id`), so this is almost always
            // non-null for a real submission; ctx.accountId is the fallback
            // for the rare case a Contact could not be resolved at all.
            Id engagementWhatId = ctx.contactId != null ? ctx.contactId : ctx.accountId;
            if (engagementWhatId != null && req.OwnerId != null) {
                GtmLifecycleNotificationService.syncEngagementStateTask(
                    engagementWhatId, req.OwnerId, GtmEngagementStateClassifier.STATE_SUBMITTED_DRAFT
                );
            }
        } catch (Exception e) {
            // The request is already saved; don't fail the submission over the
            // nice-to-have follow-ups (feed post, readout).
        }
    }

    /**
     * Best-effort call into GtmReadoutController.generateDraftReadout.
     * Isolated in its own try/catch (rather than relying on the outer one in
     * recordAssessmentRequest) so a readout-generation failure is visibly
     * distinct in debug logs from an assessment-record failure, without
     * changing recordAssessmentRequest's own fail-open behavior.
     */
    private static void generateDraftReadout(Id assessmentRequestId) {
        try {
            GtmReadoutController.generateDraftReadout(assessmentRequestId);
        } catch (Exception e) {
            // Deliberately not e.getMessage(): a DML exception quotes the
            // offending field values back, and on this path those values are
            // prospect-submitted content (company, pain points, success
            // criteria) -- which would then sit in the debug log of a guest
            // transaction. The exception type, its line, and the request Id
            // are enough to find the failure; the record itself holds the
            // detail, under the access controls it is supposed to be under.
            System.debug(
                LoggingLevel.WARN,
                'Could not generate draft readout for assessment request ' +
                assessmentRequestId + ' -- ' + e.getTypeName() +
                ' at line ' + e.getLineNumber() + '.'
            );
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

    /**
     * This offering's config row, or the shared default.
     *
     * PRECEDENCE, mirroring GtmPageContentController.getPageContent's
     * industry-then-default chain exactly, including the NULLS LAST idiom: a
     * row naming this offering wins, and a row with a BLANK Offering_Key__c is
     * the fallback for every offering that has none of its own. The fallback is
     * now found by that blankness rather than by DeveloperName -- the existing
     * `Default` record becomes the shared row purely by staying blank, and
     * nothing about it had to be edited (ADR-0007 section 1).
     */
    private static GTM_Assessment_Config__mdt loadConfig(String offeringKey) {
        if (configOverride != null) {
            return configOverride;
        }
        List<GTM_Assessment_Config__mdt> rows = [
            SELECT Notify_Email__c, Create_Lead__c, Send_Email__c, Activity_Type__c
            FROM GTM_Assessment_Config__mdt
            WHERE Offering_Key__c = :offeringKey OR Offering_Key__c = null
            ORDER BY Offering_Key__c NULLS LAST
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
        String notifyEmail
    ) {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
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
            throw new AuraHandledException(TOKEN_REAUTH_MESSAGE);
        }

        // Expected format: "<recordId>:<epochSeconds>:<hmacHex>"
        List<String> parts = token.split(':');
        if (parts.size() != 3) {
            throw new AuraHandledException(TOKEN_REAUTH_MESSAGE);
        }

        String tokenRecordId = parts[0];
        Long tokenEpoch;
        try {
            tokenEpoch = Long.valueOf(parts[1]);
        } catch (Exception e) {
            throw new AuraHandledException(TOKEN_REAUTH_MESSAGE);
        }
        String tokenHmac = parts[2];

        // Must be for the same record this request references.
        if (tokenRecordId != savedRecordId) {
            throw new AuraHandledException(TOKEN_REAUTH_MESSAGE);
        }

        // Must be within the valid window (30 min, matching GtmLinkAuthController).
        Long nowEpoch = System.now().getTime() / 1000L;
        if (nowEpoch - tokenEpoch > 1800L) {
            throw new AuraHandledException(TOKEN_REAUTH_MESSAGE);
        }

        // Verify the HMAC (constant-time comparison prevents timing attacks).
        String payload = tokenRecordId + ':' + parts[1];
        Blob expected = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(ctx.linkPassword));
        String expectedHex = EncodingUtil.convertToHex(expected);
        if (!constantTimeEqual(expectedHex, tokenHmac)) {
            throw new AuraHandledException(TOKEN_REAUTH_MESSAGE);
        }
    }

    /**
     * Closes the questionnaire draft (if any) this submission was finished
     * from, so a submitted assessment and a live resume link cannot coexist.
     *
     * APPENDS, NEVER UPDATES. An empirical probe against this org (see
     * docs/handoff/port-map-ma-to-gtm.md section F) confirmed a guest cannot
     * update a GTM_Form_Draft__c row, including one it created itself, in
     * this org -- INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY both times.
     * So this method appends one final row carrying Submitted_Request__c;
     * because that row becomes the newest for the token,
     * GtmAssessmentDraftController.resumeDraft's own "most recent row" lookup
     * finds it and stops resolving the token, without this class updating
     * anything.
     *
     * Failures are swallowed. A submission that succeeded must not be reported
     * as failed because a draft row would not insert -- the draft is already
     * unreachable to a client that has just been told its assessment was
     * received, and the purge job removes it either way. Nothing about the
     * draft, including its token, is logged.
     */
    private static void closeDraft(String draftToken, String assessmentRequestId) {
        if (String.isBlank(draftToken) || draftToken.length() > 64) {
            return;
        }
        try {
            // Only close a token that actually resolves to an open Assessment
            // draft right now -- an unknown or already-closed token gets a
            // silent no-op, exactly like every other failure mode here.
            List<GTM_Form_Draft__c> rows = [
                SELECT Expires_At__c, Pair_Key__c, Saved_Configuration__c
                FROM GTM_Form_Draft__c
                WHERE Draft_Type__c = 'Assessment'
                AND Resume_Token__c = :draftToken
                ORDER BY CreatedDate DESC, Id DESC
                LIMIT 1
            ];
            if (rows.isEmpty() || rows[0].Expires_At__c == null || rows[0].Expires_At__c < System.now()) {
                return;
            }
            GTM_Form_Draft__c closingRow = new GTM_Form_Draft__c(
                Draft_Type__c    = 'Assessment',
                Resume_Token__c  = draftToken,
                Draft_JSON__c    = '{}',
                Pair_Key__c      = rows[0].Pair_Key__c,
                Status__c        = 'Submitted',
                Saved_Configuration__c = rows[0].Saved_Configuration__c,
                Expires_At__c    = rows[0].Expires_At__c,
                Last_Saved_At__c = System.now()
            );
            if (String.isNotBlank(assessmentRequestId) && isId(assessmentRequestId)) {
                closingRow.Submitted_Request__c = (Id) assessmentRequestId;
            }
            GtmLinkOwnerStamp.stamp(new List<SObject>{ closingRow }, GtmLinkOwnerStamp.ownerForLink(closingRow.Saved_Configuration__c));
            insert closingRow;
        } catch (Exception e) {
            // See above. Deliberately silent, and deliberately message-free.
        }
    }

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

    /**
     * The guard for Section_Scores__c -- the one prospect-supplied field that
     * carries a *structured* value rather than free text, which is why it does
     * not simply get the trimTo(...) treatment its siblings get.
     *
     * Unguarded it was the only input that could throw STRING_TOO_LONG, and
     * recordAssessmentRequest's outer catch would then have swallowed the whole
     * GTM_Assessment_Request__c insert -- losing the submission over one field.
     *
     * But truncating is the wrong repair here. GtmReadoutController parses this
     * blob as JSON to build the readout's section breakdown
     * (sectionScoreLines), and a JSON document cut at character 32768 is
     * syntactically broken: it parses as nothing, so the breakdown silently
     * vanishes from the readout while the record still *looks* like it holds
     * section scores. Corrupt-but-plausible is the one outcome worth ruling
     * out, since the readout is what a rep sends a prospect.
     *
     * So an oversize value is dropped, not truncated: null is honest, the
     * readout template already handles a blank value by omitting the section
     * breakdown entirely, and everything else about the submission survives. A
     * legitimate per-section score map is a few hundred characters -- 32KB of
     * it is not data we are losing.
     */
    private static String sanitizeSectionScores(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.length() > MAX_SECTION_SCORES) {
            // No prospect content in the log line -- see the note on
            // generateDraftReadout's catch.
            System.debug(
                LoggingLevel.WARN,
                'Section scores dropped: ' + trimmed.length() +
                ' characters exceeds the ' + MAX_SECTION_SCORES +
                '-character field. Storing null rather than a truncated, unparseable blob.'
            );
            return null;
        }
        return trimmed;
    }

    /**
     * Asks GtmMigrationPairs whether the accelerator can process what the
     * requester says they are moving from and to.
     *
     * Best-effort by construction: any failure reading the pair metadata
     * returns an un-evaluated verdict, which leaves the gate inert and the
     * assessment scored as normal. A config-read problem must not be able to
     * silently downgrade a prospect's result -- and it must certainly not be
     * able to take down the submission, which is what an uncaught exception
     * here would do (the caller's catch would lose the whole record).
     *
     * The pair is read from the platform fields rather than from
     * Branch_Platform__c because those are what actually name a source and a
     * target; the Q0 routing answer only says which question variant was shown.
     */
    private static GtmAssessmentScoring.PairEligibility resolvePairEligibility(
        String offeringKey, RequestInput input
    ) {
        // MIGRATION ACCELERATOR ONLY, per ADR-0007 section 5. "Can the
        // accelerator process this source-to-target platform move at all" is a
        // migration business rule with no equivalent in an offering that is not
        // a migration -- GTM_Migration_Platform__mdt / GTM_Migration_Pair__mdt
        // are deliberately left unscoped rather than generalised into something
        // nothing needs yet. Every other offering gets the same inert,
        // never-evaluated verdict the whole system already fails open to when
        // pair metadata is absent, so the gate simply does not apply.
        if (!GtmAssessmentFrames.MIGRATION_ACCELERATOR.equalsIgnoreCase(
                String.isBlank(offeringKey) ? '' : offeringKey.trim())) {
            return new GtmAssessmentScoring.PairEligibility();
        }
        try {
            return GtmMigrationPairs.evaluate(input.currentPlatform, input.targetPlatform);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Migration pair could not be evaluated; the pair gate stays inert: ' +
                e.getTypeName()
            );
            return new GtmAssessmentScoring.PairEligibility();
        }
    }

    /**
     * The instrument pack for this submission's source/target combination.
     * Best-effort in exactly the way the pair gate is: a resolution failure
     * yields the base pack, so a half-deployed or missing pack table costs the
     * pair-specific wording and nothing else. An assessment that refuses to
     * score because a pack is missing would be strictly worse than one scored
     * against the base eight.
     */
    private static GtmAssessmentInstrument.Pack resolveInstrumentPack(
        String offeringKey, RequestInput input
    ) {
        try {
            return GtmAssessmentInstrument.getPack(
                offeringKey, input.currentPlatform, input.targetPlatform
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Instrument pack could not be resolved; falling back to base: ' + e.getTypeName()
            );
            return GtmAssessmentInstrument.basePack(offeringKey);
        }
    }

    /**
     * Which offering this submission belongs to.
     *
     * The engagement link's own GTM_Saved_Configuration__c.Offering__c when
     * there is one, and migration-accelerator for a direct booking with no
     * linked configuration -- which is the only offering that has ever been
     * assessed, so it is the honest answer rather than a guess. Factored out of
     * the expression GtmReadoutController.generateDraftReadout used to compute
     * independently; that method now READS the stored key instead, so the
     * derivation happens once, at the point the assessment was actually scored.
     */
    @TestVisible
    private static String resolveOfferingKey(ConfigContext ctx) {
        return ctx != null && String.isNotBlank(ctx.offering)
            ? ctx.offering.trim()
            : GtmAssessmentFrames.MIGRATION_ACCELERATOR;
    }

    /**
     * The basis to store for a complexity score that actually has answers.
     * A questionnaire answer is a pre-scan self-estimate and nothing else --
     * ALWAYS Self-Estimated, regardless of what the client sends, including a
     * well-formed "Measured". `supplied` is deliberately not trusted at all:
     * this submission path (submitRequest) is the guest-reachable
     * questionnaire, which cannot produce a measured value by construction --
     * a prospect cannot have already run a real scan through this form.
     * "Measured" can only ever be set some other way (e.g. a rep editing the
     * record after a real extract), never through this path. Fixed a bug
     * here: the previous implementation called GtmEstateComplexity.acceptedBasis
     * (a format validator, not a trust boundary) and accepted "Measured" when
     * it was well-formed, contradicting this method's own original intent and
     * its own test, aClientCannotLabelItsOwnEstimateAsMeasured.
     */
    private static String defaultBasis(String supplied) {
        return GtmEstateComplexity.BASIS_SELF_ESTIMATED;
    }

    /**
     * The verbatim half of a supplement submission: dimension -> text, for the
     * probes that are deliberately unscored. Trimmed to the same short-field
     * ceiling as any other prospect-supplied string, because it is one.
     */
    private static Map<String, String> noteMap(List<AnswerInput> answers) {
        Map<String, String> out = new Map<String, String>();
        if (answers == null) {
            return out;
        }
        for (AnswerInput a : answers) {
            if (a == null || String.isBlank(a.dimension) || String.isBlank(a.text)) {
                continue;
            }
            out.put(a.dimension.trim(), trimTo(a.text, MAX_SHORT));
        }
        return out;
    }

    /**
     * Flattens the wire shape into the dimension -> value map GtmAssessmentScoring
     * works on. A Map is the point, not an implementation detail: a repeated
     * dimension collapses to one entry, so a payload that answers
     * "estate_scale" fifty times contributes once. Blank dimension names are
     * skipped; unknown ones are left for the scorer to ignore, since it is the
     * place that knows which dimensions exist.
     */
    private static Map<String, Integer> answerMap(List<AnswerInput> answers) {
        Map<String, Integer> out = new Map<String, Integer>();
        if (answers == null) {
            return out;
        }
        for (AnswerInput a : answers) {
            if (a == null || String.isBlank(a.dimension)) {
                continue;
            }
            out.put(a.dimension.trim(), a.value);
        }
        return out;
    }

    private static Decimal parseIntOrNull(String value) {
        if (String.isBlank(value)) return null;
        try {
            return Decimal.valueOf(value.trim().replaceAll('[^0-9]', ''));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Whether the offering behind a given Assessment Request has a Conduit
     * (migration-planning) dashboard available -- used by
     * gtmReadoutWorkspace to gate its Conduit tab. Resolved off
     * GTM_Offering__mdt.Has_Conduit__c (issue-gtm-readout-workspace) rather
     * than a hardcoded Offering_Key__c === 'migration-accelerator' check, per
     * docs/backlog.md B15's direction against hardcoding Migration
     * Accelerator anywhere. Same two-query, best-effort shape as
     * sourceLabelFor()/offeringAnnualTarget() above: a missing/unreadable
     * request or offering row degrades to "no conduit" rather than an error,
     * since the caller's own Conduit tab is optional UI, not a blocking one.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean getOfferingHasConduit(Id assessmentRequestId) {
        if (assessmentRequestId == null) {
            return false;
        }
        try {
            List<GTM_Assessment_Request__c> requests = [
                SELECT Offering_Key__c
                FROM GTM_Assessment_Request__c
                WHERE Id = :assessmentRequestId
                LIMIT 1
            ];
            if (requests.isEmpty() || String.isBlank(requests[0].Offering_Key__c)) {
                return false;
            }
            List<GTM_Offering__mdt> rows = [
                SELECT Has_Conduit__c
                FROM GTM_Offering__mdt
                WHERE Offering_Key__c = :requests[0].Offering_Key__c
                LIMIT 1
            ];
            return !rows.isEmpty() && rows[0].Has_Conduit__c == true;
        } catch (Exception e) {
            return false;
        }
    }
}
