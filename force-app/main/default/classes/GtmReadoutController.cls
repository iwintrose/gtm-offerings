/**
 * Rep-facing controller for the assessment readout workflow (GTM_Readout__c).
 *
 * State machine. Half of it is the platform's now, and the split is the point:
 *
 *   Draft     -> Pending Approval  Approval.process (submitForApproval)
 *   Pending   -> Approved          GTM_Readout_Approval final-approval action
 *   Pending   -> Draft             rejection, or recall (recallApproval)
 *   Approved  -> Published         publishReadout        <- stays here
 *   Published -> Approved          unpublishReadout; clears the public token
 *   Approved  -> Draft             returnToDraft; snapshots the approval first
 *
 * The approve step is a real Approval Process
 * (approvalProcesses/GTM_Readout__c.GTM_Readout_Approval), so submitting,
 * approving, rejecting and recalling are platform operations and
 * ProcessInstance / ProcessInstanceStep are the audit trail. The old custom
 * approveReadout() is gone: it let an author approve their own work and left no
 * trail beyond two fields. The Draft -> Approved transition does not exist in
 * this class for the default (manager) routing mode, and the trigger that
 * reacts to Pending -> Approved (GtmReadoutApprovalSync) is what copies the
 * draft into Approved_Content__c and writes the
 * GTM_Readout_Version__c snapshot -- a workflow field update cannot write a rich
 * text field, so that copy needs Apex.
 *
 * SELF-APPROVAL. When GTM_Readout_Approval_Settings__c.Self_Approval_Enabled__c
 * is true (org-wide, admin toggle), selfApproveReadout offers a direct
 * Draft -> Approved transition for the record's own owner, entirely bypassing
 * Approval.process(). It relies on the same Status__c-transition-keyed
 * GtmReadoutApprovalHandler for stamping/snapshotting, and additionally
 * inserts a GTM_Readout_Approval_Log__c row as its own audit trail, since
 * there is no ProcessInstance in this path. Manager mode (the default) is
 * completely unaffected by this toggle.
 *
 * APPROVE AND PUBLISH STAY SEPARATE. Approval marks a readout approved and
 * stops there. publishReadout is what mints Public_Link_Token__c, and it is
 * still a deliberate rep action, because a manager approving must never, by
 * itself, put a live link in a prospect's inbox. Nothing in the approval
 * process publishes; do not add it.
 *
 * The two transitions this class still owns throw AuraHandledException on a bad
 * state rather than silently no-op'ing, so a rep sees why a click did nothing.
 * The one transition that is deliberately absent is Published -> Draft: a
 * published readout has a live token sitting in a prospect's inbox, so it has
 * to be unpublished (which revokes the token) before it can be reopened for
 * editing. See returnToDraft for the full reasoning.
 *
 * `with sharing` throughout -- this is an internal, rep-facing surface only,
 * and now that GTM_Readout__c is Private, that declaration is what limits a rep
 * to the readouts they own. The guest-accessible read path lives in
 * GtmReadoutPublicController and the guest comment write in
 * GtmReadoutCommentController. The one deliberate exception is the Generator
 * inner class below -- see its comment.
 */
public with sharing class GtmReadoutController {

    /** Developer name of the singleton GTM_Assessment_Config__mdt row. */
    private static final String DEFAULT_CONFIG = 'Default';

    /**
     * DeveloperName of the triage Queue that owns readouts no rep can be
     * resolved for -- force-app/main/default/queues/GTM_Readout_Triage.queue-meta.xml.
     */
    private static final String TRIAGE_QUEUE = 'GTM_Readout_Triage';

    /** Test seam: lets the test class supply config without deploying CMDT. */
    @TestVisible
    private static GTM_Assessment_Config__mdt configOverride;

    /**
     * Test seam. resolveOwnerId's first three candidates include
     * UserInfo.getUserId(), and every Apex test runs as an active, non-Guest
     * user -- so in a test the User branch always resolves and the CMDT and
     * queue branches below it are unreachable. Setting this to true skips the
     * three derived User candidates (Opportunity owner, request owner, running
     * user) so those later branches can be exercised for what they are: the
     * production path for a direct booking submitted by the Experience Cloud
     * guest user, where none of the three resolves.
     *
     * It suppresses only the *derived* candidates. The configured
     * Default_Readout_Owner__c lookup still runs, which is what lets a test
     * prove a named human still beats the queue.
     */
    @TestVisible
    private static Boolean suppressDerivedOwnerCandidates = false;

    // ------------------------------------------------------------- generate

    /**
     * Auto-creates a Draft GTM_Readout__c from a scored GTM_Assessment_Request__c.
     * See Generator.run() for the body -- this is a thin entry point so the
     * elevation below stays scoped to exactly the creation path.
     */
    public static Id generateDraftReadout(Id assessmentRequestId) {
        return new Generator().run(assessmentRequestId);
    }

    /**
     * Rep-facing entry point for generateDraftReadout, for the case where the
     * guest-submit transaction (GtmAssessmentRequestController.recordAssessmentRequest,
     * the only other caller of generateDraftReadout) either no-op'd or the rep
     * needs a readout kicked off for a request that predates it. Called from
     * gtmRepLinkFinder's "Generate Readout" button.
     *
     * generateDraftReadout itself can't be exposed directly: its only other
     * caller is the without-sharing Generator path, whose elevation is
     * justified there only because that caller takes no caller-supplied
     * filter. Here the caller-supplied assessmentRequestId IS exactly that
     * kind of filter, so this method runs the lookup under the running rep's
     * own sharing first (this class is `with sharing`) and requires both the
     * request record itself and at least one of its Account/Contact/
     * Opportunity relationships to be visible before delegating. A rep with
     * no sharing access to the record -- or whose visible request has no
     * visible Account/Contact/Opportunity -- gets the same non-disclosing
     * "not found or not accessible" AuraHandledException a 404 or a 403 both
     * look like from the outside; this deliberately does not distinguish the
     * two so the error can't be used to probe for the record's existence.
     *
     * GTM_Assessment_Request__c itself has a public-ReadWrite org-wide
     * default (see the object's own sharingModel), so the row is visible to
     * any rep regardless of sharing -- the query below being "under the
     * running user's own sharing" isn't what gates access here. The actual
     * gate is the Account__r/Contact__r/Opportunity__r *relationship* field
     * traversal: querying a parent-relationship field for a specific parent
     * record the running user has no sharing access to (Account/Contact/
     * Opportunity are all Private-OWD elsewhere in this org) resolves to
     * null rather than throwing, exactly like an outer join silently
     * dropping a row it can't see -- it does NOT fall back to just reading
     * the flat Account__c/Contact__c/Opportunity__c Id fields, which would
     * always be readable off an already-visible ReadWrite row and would
     * defeat the check entirely.
     *
     * Idempotent, same as generateDraftReadout/Generator.run(): a second call
     * for a request that already has a readout returns the existing Id and
     * creates nothing.
     */
    @AuraEnabled
    public static Id generateReadoutForRequest(Id assessmentRequestId) {
        if (assessmentRequestId == null) {
            throw new AuraHandledException('Assessment request not found or not accessible.');
        }

        List<GTM_Assessment_Request__c> visible = [
            SELECT Id, Account__r.Id, Contact__r.Id, Opportunity__r.Id
            FROM GTM_Assessment_Request__c
            WHERE Id = :assessmentRequestId
            LIMIT 1
        ];
        if (visible.isEmpty()) {
            throw new AuraHandledException('Assessment request not found or not accessible.');
        }
        GTM_Assessment_Request__c req = visible[0];
        if (req.Account__r == null && req.Contact__r == null && req.Opportunity__r == null) {
            throw new AuraHandledException('Assessment request not found or not accessible.');
        }

        return generateDraftReadout(assessmentRequestId);
    }

    /**
     * The draft-generation path, and the ONLY `without sharing` code in this
     * class. It has to be: generateDraftReadout() is called from
     * GtmAssessmentRequestController.recordAssessmentRequest() inside the
     * Experience Cloud **guest** submit transaction, and Apex sharing follows
     * the declaring class -- so under the enclosing `with sharing` every query
     * here ran with guest record visibility. The GTM_Assessment_Request__c it
     * looks up is owned by a rep, the guest can see no such record, so the
     * lookup came back empty, threw "Assessment request not found", and the
     * caller's best-effort catch swallowed it: no readout was ever created in
     * production. Every Apex test runs as an admin, which is why that passed.
     * Same reasoning as GtmAssessmentRequestController's own header comment
     * about needing elevated context for the guest surface.
     *
     * Elevating here is safe because this path takes no caller-supplied filter
     * -- it reads exactly one record by Id and writes records derived from it.
     * The access decision it makes is explicit and outbound: it assigns
     * OwnerId to a resolved rep (see resolveOwnerId), which is what grants
     * access under the Private model rather than what bypasses it.
     */
    private without sharing class Generator {

        /**
         * Templates Draft_Content__c from the score/tier/section breakdown and
         * the qualitative fields, assigns the readout to the owning rep, and
         * files the rep a review Case. Idempotent: if a readout already
         * exists for this assessment, its Id is returned and nothing is
         * created.
         */
        public Id run(Id assessmentRequestId) {
            if (assessmentRequestId == null) {
                return null;
            }

            List<GTM_Readout__c> existing = [
                SELECT Id
                FROM GTM_Readout__c
                WHERE Assessment_Request__c = :assessmentRequestId
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }

            // Context__c through Key_Integrations__c are read by
            // GtmReadoutModel for the estate panel and by buildNarrative for
            // its framing lines. A field the snapshot needs and this query
            // does not select is a panel that silently never renders.
            List<GTM_Assessment_Request__c> reqs = [
                SELECT Id, OwnerId, Opportunity__c, Opportunity__r.OwnerId,
                       Company__c, Requester_Name__c, Requester_Email__c,
                       Contact__c, Account__c,
                       Current_Platform__c, Target_Platform__c, Assessment_Score__c,
                       Assessment_Tier__c, Section_Scores__c, Branch_Platform__c,
                       Assessment_Advisory__c, Advisory_Reason__c, Assessment_Flags__c,
                       Instrument_Pair__c, Instrument_Version__c, Supplement_Scores__c,
                       Estate_Complexity_Score__c, Estate_Complexity_Band__c,
                       Estate_Complexity_Basis__c, Estate_Complexity_Dimensions__c,
                       Pain_Points__c, Migration_Goals__c, Success_Criteria__c,
                       Context__c, Urgency_Driver__c, Timeline__c,
                       Contact_Count__c, Monthly_Send_Volume__c,
                       Environment_Size__c, Internal_Team_Size__c,
                       Key_Integrations__c, Offering_Key__c,
                       Saved_Configuration__r.Offering__c,
                       Submitted_At__c
                FROM GTM_Assessment_Request__c
                WHERE Id = :assessmentRequestId
                LIMIT 1
            ];
            if (reqs.isEmpty()) {
                throw new AuraHandledException('Assessment request not found.');
            }
            GTM_Assessment_Request__c req = reqs[0];

            // Under the Private sharing model OwnerId *is* the access grant, so
            // a readout with no owner at all would be invisible to everyone --
            // and a guest-owned one would publish the guest user's name and
            // email to the prospect as their "contact" (see
            // GtmReadoutPublicController.applyRepContact).
            //
            // resolveOwnerId now ends at the GTM_Readout_Triage queue, so this
            // returns null only when that queue is missing from the org
            // entirely (it is source metadata, so that means it was never
            // deployed). Refusing to create the readout is still the right
            // answer in that case -- an ownerless Private record helps nobody
            // -- but it is now a deployment fault to fix, not the routine
            // outcome of a direct booking, which is what it used to be.
            Id ownerId = resolveOwnerId(req);
            if (ownerId == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'No owner could be resolved for assessment request ' + req.Id +
                    ' -- skipping draft readout generation. The ' + TRIAGE_QUEUE +
                    ' queue is missing: deploy force-app/main/default/queues, or set ' +
                    'GTM_Assessment_Config.Default.Default_Readout_Owner__c to a fallback username.'
                );
                return null;
            }

            // READ, no longer re-derived. The offering key is resolved once,
            // server-side, at the point the assessment was actually scored
            // (GtmAssessmentRequestController.recordAssessmentRequest) and
            // stored on the request. Re-deriving it here from the linked
            // configuration would be a second, independent answer to the same
            // question -- and the two could genuinely disagree if a link's
            // Offering__c were edited between submission and readout
            // generation, which would render a readout against an instrument
            // the assessment was never scored with. ADR-0007 section 3.
            //
            // The blank fallback is for rows submitted before Offering_Key__c
            // existed. scripts/data/backfill-assessment-offering-key.apex fills
            // those in, so this should never fire in gtm-dev -- it is the guard
            // that keeps a pre-backfill or hand-created row rendering rather
            // than failing.
            String offeringKey = String.isNotBlank(req.Offering_Key__c)
                ? req.Offering_Key__c
                : GtmAssessmentFrames.MIGRATION_ACCELERATOR;

            // The two halves of a readout, written together and exactly once.
            // The snapshot is built FIRST because the prose template asks it
            // whether it exists: when the snapshot could not be built the
            // designed panels have nothing to render, so the prose falls back
            // to carrying the numbers itself. See buildReadoutHtml.
            String dataJson = GtmReadoutModel.buildJson(req);

            GTM_Readout__c readout = new GTM_Readout__c(
                OwnerId               = ownerId,
                Assessment_Request__c = req.Id,
                Opportunity__c        = req.Opportunity__c,
                Offering_Key__c       = offeringKey,
                Status__c             = 'Draft',
                Readout_Data__c       = dataJson,
                Draft_Content__c      = buildReadoutHtml(req, String.isNotBlank(dataJson))
            );
            insert readout;

            fileReviewCase(readout.Id, ownerId, req);
            fileFollowUpTask(req.Id, ownerId, req.Submitted_At__c);
            return readout.Id;
        }

        /**
         * Who should own the readout, in descending order of how directly the
         * source names the person working the deal:
         *
         *   1. the related Opportunity's owner -- the deal owner of record;
         *   2. the assessment request's own owner, which
         *      GtmAssessmentRequestController stamps from the Engagement Link's
         *      owner when the submission came through a rep's link;
         *   3. the running user, which covers a rep (or an admin, or a test)
         *      generating a readout from an internal context;
         *   4. a fallback username named in GTM_Assessment_Config__mdt;
         *   5. the GTM_Readout_Triage queue.
         *
         * Steps 1-4 are validated to be an active, non-Guest **User** before
         * they are used. That filter is the whole point of them: in guest
         * context candidates 2 and 3 can resolve to the site guest / guest
         * default user, which is exactly the owner we must never end up with.
         *
         * Step 5 is the deliberate exception, and the only place this class
         * ever hands a readout to something that is not a person. A direct
         * booking -- no Engagement Link, no Opportunity, submitted by the guest
         * user -- genuinely has no rep to name, and the previous behaviour
         * (create nothing) meant those assessments produced no readout and no
         * task, so nobody knew they had happened. A queue-owned readout is
         * visible to every queue member, and a rep claiming it becomes its
         * owner, which is what turns the prospect-facing contact block on.
         *
         * A named human at step 4 still wins over the queue: a configured
         * fallback owner is an explicit statement about who handles orphans,
         * and it should not be overridden by a queue that exists by default.
         *
         * Returns null only when the queue is missing from the org too.
         */
        private Id resolveOwnerId(GTM_Assessment_Request__c req) {
            if (suppressDerivedOwnerCandidates != true) {
                List<Id> candidates = new List<Id>();
                addCandidate(candidates, req.Opportunity__r == null ? null : req.Opportunity__r.OwnerId);
                addCandidate(candidates, req.OwnerId);
                addCandidate(candidates, UserInfo.getUserId());

                Id resolved = firstUsable(candidates);
                if (resolved != null) {
                    return resolved;
                }
            }
            // Only now -- so the configured fallback costs nothing on the
            // normal path where a real rep was already found.
            List<Id> fallback = new List<Id>();
            addCandidate(fallback, configuredFallbackOwnerId());
            Id configured = firstUsable(fallback);
            if (configured != null) {
                return configured;
            }
            return triageQueueId();
        }

        /**
         * The GTM_Readout_Triage queue's Id, or null if it is not deployed.
         *
         * `Type = 'Queue'` is part of the filter, not decoration: Group holds
         * queues, role groups, territory groups and public groups in one table,
         * and DeveloperName is only unique per type. Without it a public group
         * that happened to share the name could end up owning client readouts.
         *
         * Never throws -- a lookup failure returns null and the caller skips
         * generation, same as every other candidate step.
         */
        private Id triageQueueId() {
            try {
                List<Group> queues = [
                    SELECT Id FROM Group
                    WHERE DeveloperName = :TRIAGE_QUEUE AND Type = 'Queue'
                    LIMIT 1
                ];
                return queues.isEmpty() ? null : queues[0].Id;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Triage queue lookup failed: ' + e.getMessage());
                return null;
            }
        }

        /**
         * The first candidate, in order, that is an active non-Guest User.
         * Returns null if none is -- including if the lookup itself fails: a
         * User-query hiccup must never end with the record silently left to
         * whoever the platform would have defaulted it to.
         */
        private Id firstUsable(List<Id> candidates) {
            if (candidates.isEmpty()) {
                return null;
            }
            Set<Id> usable = new Set<Id>();
            try {
                for (User u : [
                    SELECT Id FROM User
                    WHERE Id IN :candidates AND IsActive = true AND UserType != 'Guest'
                ]) {
                    usable.add(u.Id);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Owner validation failed: ' + e.getMessage());
                return null;
            }
            for (Id candidate : candidates) {
                if (usable.contains(candidate)) {
                    return candidate;
                }
            }
            return null;
        }

        /** Adds a non-null, User-typed, not-already-listed candidate. */
        private void addCandidate(List<Id> candidates, Id candidate) {
            if (candidate == null || candidate.getSObjectType() != User.SObjectType) {
                return;
            }
            for (Id existing : candidates) {
                if (existing == candidate) {
                    return;
                }
            }
            candidates.add(candidate);
        }

        /**
         * Last-resort owner, named by username in custom metadata rather than
         * hard-coded here, so a direct booking with no Engagement Link and no
         * Opportunity still lands on a real person. Null (the shipped default)
         * means "no fallback configured" and generation is skipped.
         */
        private Id configuredFallbackOwnerId() {
            String username = (String) config().get('Default_Readout_Owner__c');
            if (String.isBlank(username)) {
                return null;
            }
            try {
                List<User> rows = [SELECT Id FROM User WHERE Username = :username LIMIT 1];
                return rows.isEmpty() ? null : rows[0].Id;
            } catch (Exception e) {
                return null;
            }
        }

        /**
         * The visible half of the assignment, and the conversation.
         *
         * This replaces the open Task that used to be filed here. A Case does
         * everything the Task did -- it lands in the owner's work list and
         * points one click back at the readout -- and three things the Task
         * could not:
         *
         *   1. It is queue-ownable with no org preference. A queue-owned Task
         *      additionally needs Setup -> Activity Settings -> "Let users
         *      assign tasks to queues", which is org state this repo cannot
         *      deploy, so the old Task silently failed to be created in exactly
         *      the case (nobody assigned) where somebody most needed telling.
         *   2. It holds a conversation natively. CaseComment is where the
         *      recipient's comments land (GtmReadoutCommentController) and where
         *      the rep replies, with no custom UI on either side.
         *   3. It has status, ownership, reporting and notification behaviour a
         *      rep and their manager already know how to use.
         *
         * There is deliberately no Task any more. Two work items against one
         * readout means two things to mark done and two places to look.
         *
         * WHAT IS DELIBERATELY LEFT UNSET. Origin, Status, Priority, Type and
         * RecordTypeId all take the org's own defaults. Writing a value that is
         * not in a given org's picklist throws on insert, and this runs inside
         * a guest submit transaction where the readout has already been
         * created -- so the least portable thing this could do is assert what
         * an org's Case picklists contain. Adding a "GTM Readout" Origin value
         * is a supported follow-up; see the runbook.
         *
         * ContactId / AccountId / SuppliedName / SuppliedEmail are set when the
         * assessment carried them, because that is what makes the Case native:
         * it appears on the Contact and the Account, and the rep can reply to
         * the prospect by email from the Case without leaving it.
         *
         * Gated by GTM_Assessment_Config.Default.Create_Readout_Case__c, same
         * toggle convention as Create_Lead__c / Send_Email__c. Best-effort: the
         * readout is already inserted and must not be rolled back over its
         * work item. Note the consequence, since it is not obvious -- a readout
         * generated with the toggle off has no Case, so it also has no thread,
         * and recipient comments on it are refused.
         *
         * Assignment rules do not run: Apex insert only applies them when
         * Database.DMLOptions.assignmentRuleHeader is set, which it is not. The
         * owner this resolves is the owner the Case keeps.
         */
        private void fileReviewCase(Id readoutId, Id ownerId, GTM_Assessment_Request__c req) {
            Boolean createCase = (Boolean) config().get('Create_Readout_Case__c');
            if (createCase == false) {
                return;
            }
            Boolean queueOwned = ownerId != null && ownerId.getSObjectType() == Group.SObjectType;
            try {
                String subject = 'Review and approve readout' +
                    (String.isBlank(req.Company__c) ? '' : ' — ' + req.Company__c);
                if (subject.length() > 255) {
                    subject = subject.substring(0, 255);
                }
                Case reviewCase = new Case(
                    OwnerId     = ownerId,
                    Readout__c  = readoutId,
                    Subject     = subject,
                    Description = 'A migration assessment was submitted' +
                        (String.isBlank(req.Requester_Name__c) ? '' : ' by ' + req.Requester_Name__c) +
                        '. A Draft readout has been generated for ' +
                        (queueOwned
                            ? 'review. No rep could be resolved from the submission, so it is ' +
                              'unassigned — claim the readout and this case to take it on.'
                            : 'your review, editing and approval.') +
                        '\n\nComments the recipient leaves on the published readout arrive on ' +
                        'this case as case comments, prefixed with the section they are about. ' +
                        'Reply here to keep the thread in one place — the recipient does not ' +
                        'see this thread, so send them anything they need to read.'
                );
                if (req.Contact__c != null) {
                    reviewCase.ContactId = req.Contact__c;
                }
                if (req.Account__c != null) {
                    reviewCase.AccountId = req.Account__c;
                }
                if (String.isNotBlank(req.Requester_Name__c)) {
                    reviewCase.SuppliedName = req.Requester_Name__c;
                }
                if (String.isNotBlank(req.Requester_Email__c)) {
                    reviewCase.SuppliedEmail = req.Requester_Email__c;
                }
                insert reviewCase;
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'Could not file the readout review case: ' + e.getTypeName() + ' -- ' +
                    e.getMessage() +
                    (queueOwned
                        ? ' -- the owner is the ' + TRIAGE_QUEUE + ' queue, which must list Case ' +
                          'as a supported object (it does in source; redeploy ' +
                          'force-app/main/default/queues). The readout itself is unaffected and is ' +
                          'already visible in the queue.'
                        : '') +
                    ' The readout has no comment thread until a Case exists for it.'
                );
            }
        }

        /**
         * Creates an open follow-up Task on the Assessment Request for the
         * owning rep. Due date = Submitted_At__c + 3 calendar days.
         * Idempotent: skips insertion if an open 'Follow up:' Task already
         * exists for this AR, so re-running generateDraftReadout (idempotent
         * path returns early before this) or any unexpected double-call never
         * creates a duplicate. Failure is logged and swallowed -- the readout
         * is already committed and must not be rolled back over a Task insert
         * failure.
         */
        private void fileFollowUpTask(Id arId, Id ownerId, DateTime submittedAt) {
            try {
                List<Task> existing = [
                    SELECT Id FROM Task
                    WHERE WhatId = :arId
                      AND Subject LIKE 'Follow up:%'
                      AND Status != 'Completed'
                    LIMIT 1
                ];
                if (!existing.isEmpty()) {
                    return;
                }

                Date dueDate = submittedAt != null
                    ? submittedAt.date().addDays(3)
                    : Date.today().addDays(3);

                insert new Task(
                    Subject      = 'Follow up: assessment response received',
                    WhatId       = arId,
                    OwnerId      = ownerId,
                    ActivityDate = dueDate,
                    Status       = 'Not Started',
                    Priority     = 'Normal'
                );
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'Could not file the follow-up Task for assessment request ' + arId +
                    ': ' + e.getTypeName() + ' -- ' + e.getMessage() +
                    ' The readout is unaffected.'
                );
            }
        }
    }

    /**
     * The singleton assessment config row, or an all-defaults stand-in when it
     * has not been deployed yet -- mirrors GtmAssessmentRequestController.loadConfig().
     * Kept as this file's own small helper rather than a shared utility, same
     * as the rest of this feature.
     */
    private static GTM_Assessment_Config__mdt cachedConfig;

    private static GTM_Assessment_Config__mdt config() {
        if (configOverride != null) {
            return configOverride;
        }
        if (cachedConfig != null) {
            return cachedConfig;
        }
        List<GTM_Assessment_Config__mdt> rows = [
            SELECT Create_Readout_Case__c, Default_Readout_Owner__c
            FROM GTM_Assessment_Config__mdt
            WHERE DeveloperName = :DEFAULT_CONFIG
            LIMIT 1
        ];
        cachedConfig = rows.isEmpty()
            ? new GTM_Assessment_Config__mdt(Create_Readout_Case__c = true)
            : rows[0];
        return cachedConfig;
    }

    /**
     * The prose half of a readout: a starting draft a rep is expected to edit.
     *
     * ── The seven-heading contract ────────────────────────────────────────
     * Every <h2> is one of GtmReadoutModel.SECTIONS, and that is load-bearing
     * in four places at once. GUS targets these headings by name
     * (GtmReadoutAgentEdit.replace_section); the recipient's comment picker
     * offers the same seven (GtmReadoutCommentController.SECTIONS); gtmReadoutView
     * routes each heading's body into its designed panel; and the rep sees the
     * same seven words in the editor. One vocabulary, four surfaces. Renaming a
     * heading here without renaming it in those three is how a section quietly
     * stops being editable, commentable or renderable.
     *
     * ── Why the numbers are (usually) not in here ─────────────────────────
     * When the frozen snapshot exists, the numbers live THERE and this template
     * writes argument only. That is not a tidiness preference:
     *
     *   - "21 out of 32" typed into a rich-text field is a number a rep can
     *     edit by hand into "24 out of 32". Moving it to Readout_Data__c, which
     *     nothing edits, closes that hole rather than documenting it.
     *   - lightning-input-rich-text normalises what it saves, so any class or
     *     data attribute this template used to mark up a score would be gone
     *     the first time a rep touched the draft. Structure cannot survive the
     *     editor; the editor is for words.
     *
     * `hasData = false` is the honest degradation, not a legacy branch. If the
     * snapshot could not be built there are no designed panels to render the
     * numbers, so the prose has to carry them, and it carries them in exactly
     * the order and wording it always did: advisory first with the tier
     * suppressed, posture above the score, score as "n out of MAX" with MAX
     * from GtmAssessmentScoring, tier and qualifier as one phrase, complexity on
     * its own line, callouts hedged from the flag.
     */
    @TestVisible
    private static String buildReadoutHtml(GTM_Assessment_Request__c req) {
        return buildReadoutHtml(req, false);
    }

    @TestVisible
    private static String buildReadoutHtml(GTM_Assessment_Request__c req, Boolean hasData) {
        GtmAssessmentReadout.Readout adaptive = GtmReadoutModel.adaptiveReadout(req);
        return hasData == true
            ? buildNarrative(req, adaptive)
            : buildFullProse(req, adaptive);
    }

    // ------------------------------------------------- prose: the narrative

    /**
     * The seven sections, argument only, for a readout whose measurements are
     * already frozen in Readout_Data__c and rendered by gtmReadoutView.
     *
     * Everything seeded here is derived from the assessment and phrased as a
     * first draft. Nothing is invented: where there is no answer there is no
     * sentence, because a placeholder a rep forgets to replace is worse than a
     * gap they can see.
     */
    private static String buildNarrative(
        GTM_Assessment_Request__c req, GtmAssessmentReadout.Readout adaptive
    ) {
        List<String> parts = new List<String>();

        // 01 VERDICT ------------------------------------------------------
        parts.add('<h2>Verdict</h2>');
        parts.add('<p>' + escape(verdictSentence(req, adaptive)) + '</p>');
        if (String.isNotBlank(req.Pain_Points__c)) {
            parts.add('<p>' + escape(req.Pain_Points__c) + '</p>');
        }

        // 02 FINDINGS -----------------------------------------------------
        // Seeded from the weakest dimensions, because that is the order of the
        // work and it is the finding a reader most needs first.
        parts.add('<h2>Findings</h2>');
        List<String> weakest = weakestDimensionLabels(adaptive, 3);
        if (weakest.isEmpty()) {
            parts.add('<p>Write the two or three things worth acting on here.</p>');
        } else {
            Integer n = 1;
            for (String label : weakest) {
                parts.add('<h3>' + String.valueOf(n) + '. ' + escape(label) + '</h3>');
                parts.add('<p>This scored lowest of the eight dimensions. Say what that means ' +
                    'for this client in a sentence, and what it costs if it is left alone.</p>');
                n++;
            }
        }

        // 03 THE PATH -----------------------------------------------------
        parts.add('<h2>The path</h2>');
        parts.add('<p>Foundation and data lead. Audience follows them. Journeys wait on both.</p>');
        if (adaptive != null && String.isNotBlank(adaptive.horizon)) {
            parts.add('<p>' + escape(adaptive.horizon) + '</p>');
        }
        if (String.isNotBlank(req.Migration_Goals__c)) {
            parts.add('<h3>Goals</h3><p>' + escape(req.Migration_Goals__c) + '</p>');
        }
        if (String.isNotBlank(req.Success_Criteria__c)) {
            parts.add('<h3>Success criteria</h3><p>' + escape(req.Success_Criteria__c) + '</p>');
        }

        // 04 CAPABILITY GAPS ----------------------------------------------
        parts.add('<h2>Capability gaps</h2>');
        parts.add('<p>' + escape(gapsLead(adaptive)) + '</p>');

        // 05 CONTEXT ------------------------------------------------------
        parts.add('<h2>Context</h2>');
        parts.add('<p>' + escape(contextLead(req)) + '</p>');
        if (String.isNotBlank(req.Context__c)) {
            parts.add('<p>' + escape(req.Context__c) + '</p>');
        }
        if (adaptive != null && !adaptive.notes.isEmpty()) {
            parts.add('<h3>Recorded verbatim</h3><ul>');
            for (String key : adaptive.notes.keySet()) {
                parts.add('<li>' + escape(key) + ': ' + escape(adaptive.notes.get(key)) + '</li>');
            }
            parts.add('</ul>');
        }

        // 06 SCORECARD ----------------------------------------------------
        parts.add('<h2>Scorecard</h2>');
        parts.add('<p>Eight dimensions predict how this goes. They are shown weakest first, ' +
            'because that is the order of the work.</p>');

        // 07 NEXT STEPS ---------------------------------------------------
        parts.add('<h2>Next steps</h2>');
        parts.add('<ul>');
        parts.add('<li>A read-only user on the target' +
            targetSuffix(req) + ', so the next pass can measure rather than ask.</li>');
        parts.add('<li>The domain list for the external form scan — every site posting into ' +
            sourceName(req) + ' today.</li>');
        parts.add('<li>A named decision owner for disposition: what gets ported, refactored ' +
            'or retired.</li>');
        parts.add('<li>Two hours for the Assess workshop, where we walk the estate inventory ' +
            'with your team.</li>');
        parts.add('</ul>');

        return String.join(parts, '\n');
    }

    /**
     * The opening line of the verdict, from the two axes. Both halves or
     * neither: "Accelerator-Ready" on its own says nothing about the size of
     * the job, and the size of the job on its own says nothing about whether it
     * can be sold.
     */
    private static String verdictSentence(
        GTM_Assessment_Request__c req, GtmAssessmentReadout.Readout adaptive
    ) {
        if (req.Assessment_Advisory__c == true) {
            return 'This pair is not one the accelerator can process today, so the readout ' +
                   'below is advisory. Say what you would do about that here.';
        }
        String tier = (adaptive != null && String.isNotBlank(adaptive.tierPhrase))
            ? adaptive.tierPhrase
            : req.Assessment_Tier__c;
        String band = req.Estate_Complexity_Band__c;
        if (String.isBlank(tier) && String.isBlank(band)) {
            return 'Write the one-sentence verdict here.';
        }
        if (String.isBlank(band)) {
            return tier + ' is the shape of this engagement. Say why in a sentence.';
        }
        if (String.isBlank(tier)) {
            return band + ' complexity is the shape of this engagement. Say why in a sentence.';
        }
        return tier + ' with a ' + band.toLowerCase() + ' estate is a known engagement shape. ' +
               'Say in one sentence what makes this one that shape. Complexity is not a grade — ' +
               'a heavier estate is a longer engagement, not a worse client.';
    }

    private static String gapsLead(GtmAssessmentReadout.Readout adaptive) {
        Integer count = adaptive == null ? 0 : adaptive.callouts.size();
        if (count == 0) {
            return 'Nothing in the resolved capability set has no target equivalent. ' +
                   'Say what that means for scope.';
        }
        return 'The constructs below have no like-for-like equivalent on the target. ' +
               'They are the part of the estimate that is rebuild rather than move.';
    }

    private static String contextLead(GTM_Assessment_Request__c req) {
        if (String.isNotBlank(req.Urgency_Driver__c)) {
            return 'What is driving this: ' + req.Urgency_Driver__c +
                   '. Say what that means for sequencing.';
        }
        return 'Say what the estate is for, and what is driving the move.';
    }

    private static String sourceName(GTM_Assessment_Request__c req) {
        return String.isBlank(req.Current_Platform__c)
            ? 'the source system'
            : req.Current_Platform__c;
    }

    private static String targetSuffix(GTM_Assessment_Request__c req) {
        return String.isBlank(req.Target_Platform__c) ? '' : ' (' + req.Target_Platform__c + ')';
    }

    /** The labels of the n lowest-scoring dimensions, weakest first. */
    private static List<String> weakestDimensionLabels(
        GtmAssessmentReadout.Readout adaptive, Integer wanted
    ) {
        List<String> labels = new List<String>();
        if (adaptive == null || adaptive.perDimension.isEmpty()) {
            return labels;
        }
        List<GtmAssessmentReadout.DimensionResult> rows = adaptive.perDimension.clone();
        for (Integer i = 0; i < rows.size(); i++) {
            for (Integer j = 0; j < rows.size() - 1 - i; j++) {
                Integer a = rows[j].value == null ? 99 : rows[j].value;
                Integer b = rows[j + 1].value == null ? 99 : rows[j + 1].value;
                if (a > b) {
                    GtmAssessmentReadout.DimensionResult tmp = rows[j];
                    rows[j] = rows[j + 1];
                    rows[j + 1] = tmp;
                }
            }
        }
        for (GtmAssessmentReadout.DimensionResult d : rows) {
            if (d.value == null || labels.size() >= wanted) {
                continue;
            }
            labels.add(String.isBlank(d.label) ? d.key : d.label);
        }
        return labels;
    }

    // ----------------------------------------------- prose: the full form

    /**
     * The whole readout as prose, for when there is no frozen snapshot to
     * render designed panels from.
     *
     * This is the original template, unchanged in every content decision it
     * makes, re-homed under the seven-heading contract so the same GUS splice,
     * the same comment sections and the same renderer work on it. Read the
     * inline comments as the specification: each one is a decision that was
     * argued once and must not be quietly reversed.
     */
    private static String buildFullProse(
        GTM_Assessment_Request__c req, GtmAssessmentReadout.Readout adaptive
    ) {
        List<String> parts = new List<String>();
        parts.add('<h2>Verdict</h2>');

        // The advisory banner goes FIRST and the tier is absent below it: when
        // the accelerator cannot process the pair, the honest readout leads
        // with that rather than burying it under a band that implies a scoped
        // migration is on the table.
        if (req.Assessment_Advisory__c == true) {
            parts.add('<p><strong>Advisory only.</strong> ' +
                (String.isBlank(req.Advisory_Reason__c)
                    ? 'The selected source/target combination is not one the accelerator can process.'
                    : escape(req.Advisory_Reason__c)) +
                ' No readiness tier is shown, because banding this pair would promise a ' +
                'delivery path that does not exist yet. The scores below are still useful ' +
                'input for the conversation.</p>');
        }

        // POSTURE, above the fold and above the number. Which of "we measured
        // this" and "this is what you told us" a readout is depends entirely on
        // whether an adapter exists for the pair, and a reader who does not know
        // which one they are holding will treat both the same way. It goes
        // BEFORE the score for the same reason the advisory banner does: a
        // caveat printed under a number is a footnote, and footnotes are not
        // read out loud.
        if (adaptive != null && String.isNotBlank(adaptive.postureStatement)) {
            parts.add('<p><strong>What this is based on.</strong> ' +
                escape(adaptive.postureStatement) + '</p>');
        }

        // "18 out of 32", never a bare number: the maximum comes from
        // GtmAssessmentScoring so the readout can never disagree with the
        // scoring that produced it (there are 8 scored dimensions worth 4
        // points each -- not the 10/40 an earlier fixture assumed).
        parts.add('<p><strong>Migration readiness:</strong> ' +
            (req.Assessment_Score__c == null
                ? '—'
                : String.valueOf(req.Assessment_Score__c) + ' out of ' +
                  String.valueOf(GtmAssessmentScoring.MAX_TOTAL_SCORE)) +
            ' <em>(a higher score means a smaller, simpler, lower-risk estate)</em></p>');
        // Suppressed rather than dashed when advisory: printing "Tier: —" next
        // to a real score invites someone to fill the dash back in.
        if (req.Assessment_Advisory__c != true) {
            // Tier AND qualifier in one phrase. "Fast-Track, foundation-gated"
            // is a real and common result -- a small, clean estate that still
            // cannot start for four months -- and a readout that prints only
            // one half of it is wrong whichever half it picks.
            String tierPhrase = (adaptive != null && String.isNotBlank(adaptive.tierPhrase))
                ? adaptive.tierPhrase
                : req.Assessment_Tier__c;
            parts.add('<p><strong>Engagement tier:</strong> ' +
                (String.isBlank(tierPhrase) ? '—' : escape(tierPhrase)) +
                '</p>');
        }

        // The second axis. Printed on its own line, never blended with the
        // first: a heavy estate is a bigger engagement, not a worse client.
        parts.add('<p><strong>Estate complexity:</strong> ' +
            (req.Estate_Complexity_Score__c == null
                ? '—'
                : String.valueOf(req.Estate_Complexity_Score__c) + ' out of ' +
                  String.valueOf(GtmEstateComplexity.MAX_TOTAL_SCORE) +
                  (String.isBlank(req.Estate_Complexity_Band__c)
                      ? ''
                      : ' — ' + escape(req.Estate_Complexity_Band__c)) +
                  (String.isBlank(req.Estate_Complexity_Basis__c)
                      ? ''
                      : ' (' + escape(req.Estate_Complexity_Basis__c) + ')')) +
            '</p>');

        if (String.isNotBlank(req.Branch_Platform__c)) {
            parts.add('<p><strong>Platform track:</strong> ' + escape(req.Branch_Platform__c) + '</p>');
        }

        for (String note : annotationLines(req.Assessment_Flags__c)) {
            parts.add('<p><strong>Note:</strong> ' + note + '</p>');
        }

        if (adaptive != null) {
            if (adaptive.estateFiguresIllustrative == true) {
                parts.add('<p><em>Estate figures in this readout are illustrative — ' +
                    'they are the client\'s account of the estate, not a measurement ' +
                    'taken from it.</em></p>');
            }
            for (GtmAssessmentReadout.GateResult g : adaptive.gates) {
                parts.add('<h3>' +
                    escape(String.isBlank(g.qualifier) ? g.key : g.qualifier) +
                    '</h3><p>' + escape(g.block) + '</p>');
            }
        }

        parts.add('<h2>Findings</h2>');
        if (String.isNotBlank(req.Pain_Points__c)) {
            parts.add('<h3>Pain points</h3><p>' + escape(req.Pain_Points__c) + '</p>');
        } else {
            parts.add('<p>Write the two or three things worth acting on here.</p>');
        }

        parts.add('<h2>The path</h2>');
        if (adaptive != null && String.isNotBlank(adaptive.horizon)) {
            parts.add('<p><strong>Foundation horizon:</strong> ' +
                escape(adaptive.horizon) + '</p>');
        }
        if (String.isNotBlank(req.Migration_Goals__c)) {
            parts.add('<h3>Migration goals</h3><p>' + escape(req.Migration_Goals__c) + '</p>');
        }
        if (String.isNotBlank(req.Success_Criteria__c)) {
            parts.add('<h3>Success criteria</h3><p>' + escape(req.Success_Criteria__c) + '</p>');
        }

        parts.add('<h2>Capability gaps</h2>');
        if (adaptive != null && !adaptive.callouts.isEmpty()) {
            parts.add('<ul>');
            for (GtmAssessmentInstrument.Callout c : adaptive.callouts) {
                // The hedge is attached here, from the flag, rather than
                // left to whoever edits the draft. A GA-pending capability
                // asserted flatly is the kind of sentence that gets quoted
                // back at you in a steering meeting.
                parts.add('<li><strong>' +
                    escape(String.isBlank(c.severity) ? 'gap' : c.severity) + ':</strong> ' +
                    escape(String.isBlank(c.issue) ? c.pattern : c.issue) +
                    (String.isBlank(c.gloss) ? '' : ' — ' + escape(c.gloss)) +
                    (String.isBlank(c.workaround) ? '' : '<br/><em>Workaround:</em> ' +
                        escape(c.workaround)) +
                    (c.verificationRequired == true
                        ? '<br/><em>Unverified against a live tenant — state this as our ' +
                          'working model, not as a platform guarantee.</em>'
                        : '') +
                    '</li>');
            }
            parts.add('</ul>');
        } else {
            parts.add('<p>No named capability gaps were resolved for this pair.</p>');
        }

        parts.add('<h2>Context</h2>');
        if (adaptive != null && !adaptive.notes.isEmpty()) {
            parts.add('<h3>Recorded verbatim</h3><ul>');
            for (String key : adaptive.notes.keySet()) {
                parts.add('<li>' + escape(key) + ': ' + escape(adaptive.notes.get(key)) + '</li>');
            }
            parts.add('</ul>');
        }
        if (adaptive != null && String.isNotBlank(adaptive.resolutionNote)) {
            parts.add('<p><em>' + escape(adaptive.resolutionNote) + '</em></p>');
        }
        if (String.isNotBlank(req.Context__c)) {
            parts.add('<p>' + escape(req.Context__c) + '</p>');
        }

        parts.add('<h2>Scorecard</h2>');
        if (String.isNotBlank(req.Section_Scores__c)) {
            parts.add('<h3>Readiness breakdown</h3><ul>');
            for (String line : sectionScoreLines(req.Section_Scores__c)) {
                parts.add('<li>' + line + '</li>');
            }
            parts.add('</ul>');
        }
        if (String.isNotBlank(req.Estate_Complexity_Dimensions__c)) {
            parts.add('<h3>Complexity breakdown</h3><ul>');
            for (String line : sectionScoreLines(req.Estate_Complexity_Dimensions__c)) {
                parts.add('<li>' + line + '</li>');
            }
            parts.add('</ul>');
        }

        parts.add('<h2>Next steps</h2>');
        parts.add('<p>Write what you need from the client to start.</p>');

        return String.join(parts, '\n');
    }

    /**
     * Parses the Section_Scores__c JSON blob into "key: value" display lines.
     * Falls back to an empty list (never throws) on malformed JSON -- a
     * templating hiccup should never block draft generation.
     */
    private static List<String> sectionScoreLines(String sectionScoresJson) {
        List<String> lines = new List<String>();
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(sectionScoresJson);
            // Machine keys are what is stored; the wording a prospect reads
            // lives in GTM_Assessment_Question__mdt. A key with no configured
            // name still prints -- as the key -- because a missing label must
            // not be able to delete a line from the breakdown.
            Map<String, String> names = dimensionNamesSafely();
            for (String key : parsed.keySet()) {
                String label = names.get(key);
                lines.add(
                    escape(String.isBlank(label) ? key : label) +
                    ': ' + escape(String.valueOf(parsed.get(key)))
                );
            }
        } catch (Exception e) {
            // Malformed JSON -- skip the breakdown, keep the rest of the draft.
        }
        return lines;
    }

    /**
     * Dimension wording, or an empty map if the metadata cannot be read. The
     * breakdown degrades to raw keys rather than disappearing.
     */
    private static Map<String, String> dimensionNamesSafely() {
        try {
            return GtmAssessmentQuestions.dimensionNames();
        } catch (Exception e) {
            return new Map<String, String>();
        }
    }

    /**
     * The non-blocking annotations GtmAssessmentScoring raised, as display
     * lines. These are the things that are true even when the headline number
     * looks good -- the high-rebuild-ratio note being the reason the mechanism
     * exists -- so they are printed above the breakdown rather than inside it.
     */
    private static List<String> annotationLines(String flagsJson) {
        List<String> lines = new List<String>();
        if (String.isBlank(flagsJson)) {
            return lines;
        }
        try {
            for (Object raw : (List<Object>) JSON.deserializeUntyped(flagsJson)) {
                Map<String, Object> flag = (Map<String, Object>) raw;
                Object message = flag.get('message');
                if (message != null) {
                    lines.add(escape(String.valueOf(message)));
                }
            }
        } catch (Exception e) {
            // Malformed -- the rest of the draft is still worth producing.
        }
        return lines;
    }


    private static String escape(String value) {
        return value == null ? '' : value.escapeHtml4();
    }

    // ------------------------------------------------------------------ list

    /**
     * Returns ALL readouts regardless of status (Draft, Pending Approval,
     * Approved, Published) for the list-first navigation view in
     * gtmAssessmentSubmissionView. Cacheable because this is a pure read used
     * only for initial list population; the list view does not perform DML.
     */
    @AuraEnabled(cacheable=true)
    public static List<ReadoutSummary> getAllReadouts() {
        List<ReadoutSummary> out = new List<ReadoutSummary>();
        for (GTM_Readout__c r : [
            SELECT Id, Name, Status__c,
                   Assessment_Request__c, Assessment_Request__r.Name,
                   Assessment_Request__r.Company__c
            FROM GTM_Readout__c
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            ReadoutSummary s = new ReadoutSummary();
            s.id                    = r.Id;
            s.name                  = r.Name;
            s.status                = r.Status__c;
            s.assessmentRequestId   = r.Assessment_Request__c;
            s.assessmentRequestName = r.Assessment_Request__r != null ? r.Assessment_Request__r.Name : null;
            s.company               = r.Assessment_Request__r != null ? r.Assessment_Request__r.Company__c : null;
            out.add(s);
        }
        return out;
    }

    public class ReadoutSummary {
        @AuraEnabled public String   id;
        @AuraEnabled public String   name;
        @AuraEnabled public String   status;
        @AuraEnabled public String   assessmentRequestId;
        @AuraEnabled public String   assessmentRequestName;
        @AuraEnabled public String   company;
        @AuraEnabled public String   requesterName;
        @AuraEnabled public String   offeringKey;
        @AuraEnabled public Datetime lastModifiedDate;
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

    // ------------------------------------------------------- account trail
    //
    // Backs gtmReadoutAccountFinder (issue-gtm-assessments-account-contact-
    // trail): the Assessments tab's Account -> Contact -> Assessment Request
    // Miller-columns browsing mode, replicating gtmRepLinkFinder's existing
    // Account -> Contact -> Link pattern
    // (GtmRepLinkFinderController.getContactsWithLinks) but walking
    // GTM_Assessment_Request__c's own direct Account__c/Contact__c lookups
    // instead of GTM_Saved_Configuration__c's -- a rep can reach an
    // assessment this way even when it was never routed through a saved
    // Configurator link at all.

    /** One Contact under the requested Account, and every Assessment Request
     *  filed against it. Only Contacts with at least one request are
     *  returned -- same shape/reasoning as
     *  GtmRepLinkFinderController.ContactLinks. */
    public class ContactRequests {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public List<RequestSummary> requests;
    }

    public class RequestSummary {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String offeringKey;
        @AuraEnabled public String status;
        @AuraEnabled public String requesterName;
        @AuraEnabled public Datetime createdDate;
        /** Most recent Readout generated for this request, if any -- null is
         *  the normal, common case for a request with no readout generated
         *  yet, not an error (same contract as
         *  GtmRepLinkFinderController.LinkSummary.readoutId). */
        @AuraEnabled public Id readoutId;
    }

    /**
     * Every Contact on the given Account that has at least one Assessment
     * Request, each carrying its own requests (newest first). Read-only, no
     * DML, `with sharing` enforced by this class already -- a rep only ever
     * sees Accounts/Contacts/requests their own sharing rules grant them.
     *
     * Cacheable: this is the Miller-columns trail's own account-search step,
     * called once per Account picked, mirroring
     * GtmRepLinkFinderController.getContactsWithLinks's own cacheable
     * contract for the same reason (a pure read, no in-page DML that would
     * make a stale cached response wrong).
     */
    @AuraEnabled(cacheable=true)
    public static List<ContactRequests> getContactsWithRequests(Id accountId) {
        List<ContactRequests> out = new List<ContactRequests>();
        if (accountId == null) {
            return out;
        }

        // Explicit OwnerId backstop (defense-in-depth, issue
        // rep-data-scoping-owd-2): this used to filter only by Account__c,
        // which leaks other reps' requests to any rep who shares visibility
        // into the same Account (e.g. via an Account-level sharing rule).
        // A user holding viewAllRecords on this object still sees
        // everything, same as before.
        Id currentUserId = UserInfo.getUserId();
        String ownerFilter = hasViewAllRecords('GTM_Assessment_Request__c')
            ? ''
            : ' AND OwnerId = :currentUserId';
        List<GTM_Assessment_Request__c> requests = (List<GTM_Assessment_Request__c>) Database.query(
            'SELECT Id, Name, Company__c, Offering_Key__c, Status__c, Requester_Name__c, ' +
            '       CreatedDate, Contact__c, Contact__r.Name ' +
            'FROM   GTM_Assessment_Request__c ' +
            'WHERE  Account__c = :accountId AND Contact__c != null' + ownerFilter + ' ' +
            'ORDER BY Contact__r.Name ASC, CreatedDate DESC'
        );

        Set<Id> requestIds = new Map<Id, GTM_Assessment_Request__c>(requests).keySet();

        Map<Id, Id> readoutIdByRequest = new Map<Id, Id>();
        if (!requestIds.isEmpty()) {
            for (GTM_Readout__c readout : [
                SELECT Id, Assessment_Request__c
                FROM   GTM_Readout__c
                WHERE  Assessment_Request__c IN :requestIds
                ORDER BY Assessment_Request__c ASC, CreatedDate DESC
            ]) {
                // First one seen per request, given the ORDER BY above, is
                // the most recent -- later ones for the same request are
                // ignored (same pattern as
                // GtmRepLinkFinderController.getContactsWithLinks).
                if (!readoutIdByRequest.containsKey(readout.Assessment_Request__c)) {
                    readoutIdByRequest.put(readout.Assessment_Request__c, readout.Id);
                }
            }
        }

        Map<Id, ContactRequests> byContact = new Map<Id, ContactRequests>();
        for (GTM_Assessment_Request__c rec : requests) {
            ContactRequests grp = byContact.get(rec.Contact__c);
            if (grp == null) {
                grp = new ContactRequests();
                grp.contactId = rec.Contact__c;
                grp.contactName = rec.Contact__r.Name;
                grp.requests = new List<RequestSummary>();
                byContact.put(rec.Contact__c, grp);
                out.add(grp);
            }

            RequestSummary s = new RequestSummary();
            s.recordId       = rec.Id;
            s.name           = rec.Name;
            s.company        = rec.Company__c;
            s.offeringKey    = rec.Offering_Key__c;
            s.status         = rec.Status__c;
            s.requesterName  = rec.Requester_Name__c;
            s.createdDate    = rec.CreatedDate;
            s.readoutId      = readoutIdByRequest.get(rec.Id);
            grp.requests.add(s);
        }
        return out;
    }

    /**
     * A single readout's full detail for the review/edit surface
     * (gtmReadoutReview). Contract: { id, status, draftContent,
     * approvedContent, publicLinkToken, assessmentRequestId,
     * assessmentRequestName, company, caseId, caseNumber, approvalState,
     * pendingApprover, approverName, approvalDate, isLocked }.
     * publicLinkToken is populated only while Status = Published (it is
     * null/cleared otherwise, same as the underlying field).
     *
     * The approval block is read from ProcessInstance rather than from
     * Status__c, so what the editor shows is what the platform actually holds.
     * If a field update ever fails to fire, the record's status label goes
     * stale but the buttons still match reality.
     *
     * Deliberately NOT cacheable. gtmReadoutReview.loadReadout() is this
     * method's only caller and it is the post-DML refetch for every action in
     * the editor -- save, approve, publish, unpublish all end in
     * `.then(() => this.loadReadout())`. Under cacheable=true that refetch
     * could be answered from the client cache with the value read *before* the
     * DML, which is how a rep could approve or publish and see neither the new
     * status badge nor the live link until reloading the page.
     *
     * The alternative -- @wire + refreshApex -- was not taken: this component
     * has no wired adapter today (it resolves its record Id from
     * CurrentPageReference and then calls imperatively), so wiring it would
     * mean restructuring loadReadout, its loading/error state and all four
     * action handlers to thread a wire result through refreshApex. Dropping
     * cacheable is the same correctness for one keyword, and nothing @wires
     * either of these two methods -- checked across every LWC and Aura caller.
     */

    /**
     * Resolve the most-recent readout for an Assessment Request record.
     *
     * Called by gtmReadoutReview when it is embedded on the
     * GTM_Assessment_Request__c record page and has no c__readout URL state
     * (the standalone-tab path). Returns a ReadoutSummary DTO so the
     * component can set its readoutId and then call getReadout() for the
     * full detail, exactly as it does in the standalone context.
     *
     * Returns null when no readout has been generated for the request yet;
     * the component shows its empty state in that case.
     *
     * Deliberately NOT cacheable — same reasoning as getReadout above.
     */
    @AuraEnabled
    public static ReadoutSummary getReadoutByRequest(Id requestId) {
        if (requestId == null) {
            throw new AuraHandledException('An Assessment Request Id is required.');
        }
        List<GTM_Readout__c> rows = [
            SELECT Id, Name, Status__c, LastModifiedDate,
                   Assessment_Request__c, Assessment_Request__r.Name,
                   Assessment_Request__r.Company__c
            FROM GTM_Readout__c
            WHERE Assessment_Request__c = :requestId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        GTM_Readout__c r = rows[0];
        ReadoutSummary s = new ReadoutSummary();
        s.id                    = r.Id;
        s.name                  = r.Name;
        s.status                = r.Status__c;
        s.assessmentRequestId   = r.Assessment_Request__c;
        s.assessmentRequestName = r.Assessment_Request__r != null ? r.Assessment_Request__r.Name : null;
        s.company               = r.Assessment_Request__r != null ? r.Assessment_Request__r.Company__c : null;
        s.lastModifiedDate      = r.LastModifiedDate;
        return s;
    }

    @AuraEnabled
    public static ReadoutDetail getReadout(Id readoutId) {
        if (readoutId == null) {
            throw new AuraHandledException('A readout Id is required.');
        }
        List<GTM_Readout__c> rows = [
            SELECT Id, OwnerId, Status__c, Draft_Content__c, Approved_Content__c,
                   Readout_Data__c, Approved_Data__c,
                   Approved_By__c, Approved_Date__c,
                   Public_Link_Token__c, Assessment_Request__c,
                   Assessment_Request__r.Name, Assessment_Request__r.Company__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Readout not found.');
        }
        GTM_Readout__c r = rows[0];

        ReadoutDetail d = new ReadoutDetail();
        d.id                    = r.Id;
        d.status                = r.Status__c;
        d.draftContent          = r.Draft_Content__c;
        d.approvedContent       = r.Approved_Content__c;
        // The measurement half, so gtmReadoutReview can show the rep the
        // designed readout rather than only the prose they are editing. An
        // approver who can only see the prose cannot see what they approved.
        d.dataJson              = r.Readout_Data__c;
        d.approvedDataJson      = r.Approved_Data__c;
        d.publicLinkToken       = r.Public_Link_Token__c;
        d.assessmentRequestId   = r.Assessment_Request__c;
        d.assessmentRequestName = r.Assessment_Request__r != null ? r.Assessment_Request__r.Name : null;
        d.company               = r.Assessment_Request__r != null ? r.Assessment_Request__r.Company__c : null;
        d.isOwner               = r.OwnerId == UserInfo.getUserId();
        d.selfApprovalEnabled   = isSelfApprovalEnabled();
        applyReviewCase(d, r.Id);
        applyApprovalState(d, r);
        return d;
    }

    /**
     * GTM_Readout_Approval_Settings__c is a Hierarchy Custom Setting (same
     * shape as GTM_Agent_Settings__c) -- getInstance() resolves org default /
     * profile / user layering for the running user, which is exactly the
     * single org-wide toggle this feature needs. Defaults to false (manager
     * mode, today's behavior) if the setting has never been configured.
     */
    private static Boolean isSelfApprovalEnabled() {
        GTM_Readout_Approval_Settings__c settings = GTM_Readout_Approval_Settings__c.getInstance();
        return settings != null && settings.Self_Approval_Enabled__c == true;
    }

    /**
     * The review Case, so the editor can link a rep straight to the thread
     * rather than making them find it. Same "oldest case wins" rule
     * GtmReadoutCommentController uses to pick where recipient comments land, so
     * the link and the thread can never point at different cases.
     *
     * Best-effort: a readout generated before this feature (or with the config
     * toggle off) simply has no case, and the editor shows no link.
     */
    private static void applyReviewCase(ReadoutDetail d, Id readoutId) {
        try {
            List<Case> cases = [
                SELECT Id, CaseNumber
                FROM Case
                WHERE Readout__c = :readoutId
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT 1
            ];
            if (!cases.isEmpty()) {
                d.caseId     = cases[0].Id;
                d.caseNumber = cases[0].CaseNumber;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Review case lookup failed: ' + e.getMessage());
        }
    }

    /**
     * Approval state, from the platform's own record of it.
     *
     * approvalState is one of None / Pending / Approved / Rejected / Recalled,
     * taken from the most recent ProcessInstance. Status__c is the reportable
     * label; this is the truth the buttons are driven from, which is why the
     * editor asks for both.
     *
     * Never throws: approval history is informational, and a readout must stay
     * openable even in an org where the approval process has not been deployed
     * yet (in which case there are no ProcessInstances and the state is None,
     * which is exactly right -- Submit for approval is then the offered
     * action and the platform will say what is missing).
     */
    private static void applyApprovalState(ReadoutDetail d, GTM_Readout__c readout) {
        d.approvalState = 'None';
        try {
            d.isLocked = Approval.isLocked(readout.Id);
        } catch (Exception e) {
            d.isLocked = false;
        }
        try {
            List<ProcessInstance> instances = [
                SELECT Id, Status, CompletedDate, CreatedDate,
                       (SELECT Id, ActorId FROM Workitems),
                       (SELECT Id, StepStatus, ActorId, CreatedDate
                        FROM Steps ORDER BY CreatedDate DESC LIMIT 1)
                FROM ProcessInstance
                WHERE TargetObjectId = :readout.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (instances.isEmpty()) {
                applyLegacyApprovalStamp(d, readout);
                return;
            }
            ProcessInstance instance = instances[0];
            d.approvalState  = stateOf(instance.Status);
            d.submittedDate  = instance.CreatedDate;

            Set<Id> userIds = new Set<Id>();
            if (instance.Workitems != null) {
                for (ProcessInstanceWorkitem item : instance.Workitems) {
                    userIds.add(item.ActorId);
                }
            }
            Id approverId;
            if (instance.Steps != null && !instance.Steps.isEmpty()) {
                approverId = instance.Steps[0].ActorId;
                userIds.add(approverId);
            }
            Map<Id, String> names = userNames(userIds);

            if (d.approvalState == 'Pending' && instance.Workitems != null) {
                List<String> waitingOn = new List<String>();
                for (ProcessInstanceWorkitem item : instance.Workitems) {
                    String name = names.get(item.ActorId);
                    if (String.isNotBlank(name)) {
                        waitingOn.add(name);
                    }
                }
                d.pendingApprover = waitingOn.isEmpty() ? null : String.join(waitingOn, ', ');
            } else if (approverId != null) {
                d.approverName = names.get(approverId);
                d.approvalDate = instance.CompletedDate;
            }
            if (d.approverName == null && readout.Status__c == 'Approved') {
                applyLegacyApprovalStamp(d, readout);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Approval state lookup failed: ' + e.getMessage());
            applyLegacyApprovalStamp(d, readout);
        }
    }

    /**
     * Readouts approved before the approval process existed (or approved by an
     * admin editing Status__c directly) have no ProcessInstance, but they do
     * have the fields the trigger stamps. Falling back to them means the editor
     * says "Approved by X" for those too, rather than going blank on history it
     * has no other way to know about.
     */
    private static void applyLegacyApprovalStamp(ReadoutDetail d, GTM_Readout__c readout) {
        if (readout.Approved_Date__c != null) {
            d.approvalDate = readout.Approved_Date__c;
        }
        if (readout.Approved_By__c == null) {
            return;
        }
        Map<Id, String> names = userNames(new Set<Id>{ readout.Approved_By__c });
        d.approverName = names.get(readout.Approved_By__c);
    }

    /** ProcessInstance.Status in the editor's vocabulary. */
    private static String stateOf(String processStatus) {
        if (processStatus == 'Pending' || processStatus == 'Reassigned') {
            return 'Pending';
        }
        if (processStatus == 'Approved') {
            return 'Approved';
        }
        if (processStatus == 'Rejected') {
            return 'Rejected';
        }
        if (processStatus == 'Removed') {
            return 'Recalled';
        }
        return 'None';
    }

    /** Names for a set of actor Ids; an actor may be a queue, which has none. */
    private static Map<Id, String> userNames(Set<Id> ids) {
        Map<Id, String> names = new Map<Id, String>();
        Set<Id> userIds = new Set<Id>();
        for (Id candidate : ids) {
            if (candidate != null && candidate.getSObjectType() == User.SObjectType) {
                userIds.add(candidate);
            }
        }
        if (userIds.isEmpty()) {
            return names;
        }
        try {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds]) {
                names.put(u.Id, u.Name);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Approver name lookup failed: ' + e.getMessage());
        }
        return names;
    }

    public class ReadoutDetail {
        @AuraEnabled public String id;
        @AuraEnabled public String status;
        @AuraEnabled public String draftContent;
        @AuraEnabled public String approvedContent;
        /** The frozen structured snapshot -- see GtmReadoutModel. */
        @AuraEnabled public String dataJson;
        /** Its copy taken at approval, which is what publishes. */
        @AuraEnabled public String approvedDataJson;
        @AuraEnabled public String publicLinkToken;
        @AuraEnabled public String assessmentRequestId;
        @AuraEnabled public String assessmentRequestName;
        @AuraEnabled public String company;
        /** The review Case that carries the recipient comment thread. */
        @AuraEnabled public String caseId;
        @AuraEnabled public String caseNumber;
        /** None | Pending | Approved | Rejected | Recalled. */
        @AuraEnabled public String approvalState;
        /** Who the request is sitting with, while Pending. */
        @AuraEnabled public String pendingApprover;
        /** Who decided it, once it is not. */
        @AuraEnabled public String approverName;
        @AuraEnabled public Datetime approvalDate;
        @AuraEnabled public Datetime submittedDate;
        /** True while the approval process holds the record. */
        @AuraEnabled public Boolean isLocked;
        /**
         * GTM_Readout_Approval_Settings__c.getInstance().Self_Approval_Enabled__c,
         * read here so gtmReadoutReview needs no direct Custom Setting access of
         * its own -- see GTM_Offering_User's permission-set grant note.
         */
        @AuraEnabled public Boolean selfApprovalEnabled;
        /** True when the viewing user is this readout's owner. */
        @AuraEnabled public Boolean isOwner;
    }

    // ------------------------------------------------------------------ CRUD

    /**
     * Rep edits, only allowed while Status = Draft.
     *
     * The pending-approval case gets its own message. Submitting locks the
     * record (recordEditability = AdminOnly on the approval process), which is
     * the point of submitting -- the content a manager is reading cannot change
     * under them. Without this check the DML would still fail, but with the
     * platform's own "record is locked" wording, which tells a rep nothing
     * about what to do next.
     */
    @AuraEnabled
    public static void saveDraftContent(Id readoutId, String content) {
        GTM_Readout__c readout = loadForUpdate(readoutId);
        if (readout.Status__c != 'Draft') {
            throw new AuraHandledException(
                isAwaitingApproval(readoutId, readout)
                    ? 'This readout is waiting on an approver, so it is locked for editing. ' +
                      'Recall the approval request to edit it again.'
                    : 'This readout can no longer be edited as a draft.'
            );
        }
        readout.Draft_Content__c = content;
        try {
            update readout;
        } catch (DmlException e) {
            throw dmlFailure(
                'The draft could not be saved. Please try again — if it keeps failing, contact your administrator.',
                readoutId,
                e
            );
        }
    }

    // ------------------------------------------------------------- approval
    //
    // Draft -> Approved is no longer a method here. It is the GTM_Readout_Approval
    // approval process, and these two methods are the thin front door onto the
    // platform's own submit and recall. Everything the approval implies beyond
    // Status__c -- the Approved_Content__c copy, the approver stamp, the version
    // snapshot -- happens in GtmReadoutApprovalSync, which reacts to the
    // transition regardless of what caused it.
    //
    // What is NOT here is just as deliberate: there is no approve() and no
    // reject(). A rep clicking a button in our own UI to approve their own
    // readout is the exact thing the approval process replaced. Approvers act
    // from the approval request -- email, the bell, the Approval History
    // related list, the Salesforce mobile app -- all of which the platform
    // provides and none of which we have to build.

    /**
     * Submits the readout into the approval process.
     *
     * Two conditions are checked before handing off, both because the platform
     * error for them is unreadable:
     *
     *   - Only a Draft can be submitted. That is also the process's entry
     *     criteria, so submitting anything else fails anyway -- with a
     *     "no applicable approval process" message that tells a rep nothing.
     *   - A queue-owned readout has no owner's manager to route to, so the
     *     approval would be assigned to nobody. Claiming the readout is the
     *     answer, and saying so is more useful than a routing error.
     */
    @AuraEnabled
    public static void submitForApproval(Id readoutId) {
        GTM_Readout__c readout = loadForUpdate(readoutId);
        if (readout.Status__c != 'Draft') {
            throw new AuraHandledException(
                isAwaitingApproval(readoutId, readout)
                    ? 'This readout has already been sent for approval.'
                    : 'Only a draft can be sent for approval. This readout is ' +
                      readout.Status__c.toLowerCase() + '.'
            );
        }
        if (String.isBlank(readout.Draft_Content__c)) {
            throw new AuraHandledException(
                'There is nothing to approve yet — write the readout before sending it for approval.'
            );
        }
        if (isQueueOwned(readoutId)) {
            throw new AuraHandledException(
                'This readout is still unassigned. Claim it first — approval is routed to the ' +
                'owner\'s manager, and a queue does not have one.'
            );
        }

        // Notification wiring point 1/5 (ADR-0010, Unit 3b): fired/closed
        // before the Approval.process() call below, deliberately -- placing
        // this after would mean a submission that never actually enters the
        // approval process (e.g. no manager set) fires a "waiting on your
        // approval" notification to nobody real. Every guard above has
        // already passed at this point, so this is the last moment before
        // the actual routing attempt.
        GtmNotificationSettingsController.NotificationSettingsDto settings =
            GtmNotificationSettingsController.getOrgDefaults();
        if (settings.notifyOnSubmitForApproval) {
            Id approverId = resolveManagerId(readout.OwnerId);
            if (approverId != null) {
                GtmLifecycleNotificationService.fireTask(
                    readoutId, approverId, GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT,
                    'A readout is waiting on your approval.');
                GtmLifecycleNotificationService.fireBell(approverId, readoutId,
                    'Readout awaiting your approval', 'A readout is waiting on your approval.');
            }
        }
        if (settings.autoCloseNewRequestTasks && readout.Assessment_Request__c != null) {
            GtmLifecycleNotificationService.closeOpenTasks(
                readout.Assessment_Request__c, GtmLifecycleNotificationService.SUBJECT_NEW_REQUEST);
        }
        // Hardcoded, not gated by any setting -- no admin toggle plausibly
        // wants a dangling "revise this" Task to survive its own
        // resubmission.
        GtmLifecycleNotificationService.closeOpenTasks(
            readoutId, GtmLifecycleNotificationService.SUBJECT_RETURNED_TO_DRAFT);

        try {
            Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
            request.setObjectId(readoutId);
            request.setSubmitterId(UserInfo.getUserId());
            // Named rather than left to "whichever process matches": this
            // object has one approval process and it should stay an error, not
            // a silent pick, if a second one is ever added.
            request.setProcessDefinitionNameOrId('GTM_Readout_Approval');
            request.setSkipEntryCriteria(false);
            request.setComments('Sent for approval from the readout editor.');

            Approval.ProcessResult result = Approval.process(request, false);
            if (!result.isSuccess()) {
                throw new AuraHandledException(approvalErrorFrom(result.getErrors()));
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Approval submission failed for readout ' + readoutId + ': ' +
                e.getTypeName() + ' at line ' + e.getLineNumber() + ' -- ' + e.getMessage()
            );
            throw new AuraHandledException(
                'This readout could not be sent for approval. Check that you have a manager set ' +
                'on your user record, then try again — if it keeps failing, contact your administrator.'
            );
        }
    }

    /**
     * The Draft -> Approved transition, restored under an explicit admin
     * toggle (GTM_Readout_Approval_Settings__c.Self_Approval_Enabled__c) for
     * orgs that want the creating rep to approve their own readout instead of
     * routing to a manager.
     *
     * This never touches Approval.process() -- it is a fully separate path
     * from submitForApproval/recallApproval, so flipping the toggle mid-flight
     * cannot corrupt an in-flight platform approval, and the existing
     * GTM_Readout_Approval ApprovalProcess and GtmReadoutApprovalHandler stay
     * completely untouched for manager mode.
     *
     * Setting Status__c = 'Approved' directly still gets the full approval
     * side effects for free: GtmReadoutApprovalHandler.isApprovalTransition is
     * keyed off the Status__c transition itself, not the trigger source (see
     * its own header comment), so Approved_Content__c/Approved_Data__c/
     * Approved_By__c/Approved_Date__c stamping and the GTM_Readout_Version__c
     * snapshot both happen exactly as they would from a manager's click --
     * this method must not duplicate any of that.
     *
     * What this method adds on top is the audit trail the platform Approval
     * Process would otherwise have provided: a GTM_Readout_Approval_Log__c
     * row (actor, timestamp, readout). Insert is best-effort, mirroring
     * GtmReadoutApprovalHandler.snapshotApprovals -- a logging failure must
     * not roll back an approval the rep already sees confirmed, but it is
     * always attempted and always visible in debug logs if it fails.
     */
    @AuraEnabled
    public static void selfApproveReadout(Id readoutId) {
        if (!isSelfApprovalEnabled()) {
            throw new AuraHandledException(
                'Self-approval is not enabled for this org. Send this readout for approval instead.'
            );
        }
        GTM_Readout__c readout = loadForUpdate(readoutId);
        if (readout.Status__c != 'Draft') {
            throw new AuraHandledException(
                isAwaitingApproval(readoutId, readout)
                    ? 'This readout has already been sent for approval.'
                    : 'Only a draft can be approved. This readout is ' +
                      readout.Status__c.toLowerCase() + '.'
            );
        }
        if (String.isBlank(readout.Draft_Content__c)) {
            throw new AuraHandledException(
                'There is nothing to approve yet — write the readout before approving it.'
            );
        }
        if (readout.OwnerId != UserInfo.getUserId()) {
            throw new AuraHandledException(
                'Only the readout\'s owner can self-approve it.'
            );
        }

        readout.Status__c = 'Approved';
        update readout;

        GTM_Readout_Approval_Log__c logEntry = new GTM_Readout_Approval_Log__c(
            Readout__c    = readoutId,
            Approved_By__c = UserInfo.getUserId(),
            Approved_Date__c = System.now()
        );
        try {
            insert logEntry;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'GtmReadoutController could not log self-approval for readout ' +
                readoutId + ': ' + e.getTypeName() + ' at line ' + e.getLineNumber() +
                ' -- ' + e.getMessage()
            );
        }
    }

    /**
     * Recalls a pending approval request, which the process's recall action
     * returns to Draft.
     *
     * The same thing the standard "Recall Approval Request" button on the
     * Approval History related list does -- offered here so a rep working in
     * the editor does not have to go and find it. The platform decides whether
     * they are allowed to (submitter or admin); a refusal comes back as its own
     * message rather than being pre-empted here.
     */
    @AuraEnabled
    public static void recallApproval(Id readoutId) {
        if (readoutId == null) {
            throw new AuraHandledException('A readout Id is required.');
        }
        List<ProcessInstanceWorkitem> workitems;
        try {
            workitems = [
                SELECT Id
                FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :readoutId
                AND ProcessInstance.Status = 'Pending'
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException(
                'The approval request could not be found. Refresh and try again.'
            );
        }
        if (workitems.isEmpty()) {
            throw new AuraHandledException(
                'There is no approval request outstanding on this readout.'
            );
        }

        try {
            Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
            request.setWorkitemId(workitems[0].Id);
            request.setAction('Removed');
            request.setComments('Recalled from the readout editor.');

            Approval.ProcessResult result = Approval.process(request, false);
            if (!result.isSuccess()) {
                throw new AuraHandledException(approvalErrorFrom(result.getErrors()));
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Approval recall failed for readout ' + readoutId + ': ' +
                e.getTypeName() + ' at line ' + e.getLineNumber() + ' -- ' + e.getMessage()
            );
            throw new AuraHandledException(
                'The approval request could not be recalled. Only the person who submitted it ' +
                '(or an administrator) can — otherwise ask the approver to reject it.'
            );
        }

        // Notification wiring point 2 (corollary of point 1/5, not an
        // independent settings field): recall's only notification job is
        // closing out whatever Task Notify_On_Submit_For_Approval__c
        // created -- it inherits that field's effective state rather than
        // reading a field of its own.
        if (GtmNotificationSettingsController.getOrgDefaults().notifyOnSubmitForApproval) {
            GtmLifecycleNotificationService.closeOpenTasks(
                readoutId, GtmLifecycleNotificationService.SUBJECT_APPROVE_READOUT);
        }
    }

    /**
     * The platform's own error text, which for approvals is genuinely useful to
     * a rep ("no approver found", "user has no manager") rather than the
     * internal detail a DmlException carries. Falls back to our own sentence
     * when there is nothing to relay.
     */
    private static String approvalErrorFrom(List<Database.Error> errors) {
        if (errors != null) {
            for (Database.Error error : errors) {
                if (String.isNotBlank(error.getMessage())) {
                    return error.getMessage();
                }
            }
        }
        return 'The approval step could not be completed. Please try again — if it keeps ' +
               'failing, contact your administrator.';
    }

    /**
     * True when the platform is holding an approval on this readout.
     *
     * ProcessInstance first, Status__c only as a hint: the field is set by a
     * workflow field update, so it is a consequence of the approval rather than
     * the approval itself, and a record whose field update failed to fire must
     * not be described as editable when the platform has it locked.
     */
    private static Boolean isAwaitingApproval(Id readoutId, GTM_Readout__c readout) {
        try {
            Integer pending = [
                SELECT COUNT()
                FROM ProcessInstance
                WHERE TargetObjectId = :readoutId AND Status = 'Pending'
            ];
            if (pending > 0) {
                return true;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Pending-approval check failed: ' + e.getMessage());
        }
        return readout != null && readout.Status__c == 'Pending Approval';
    }

    /**
     * The readout owner's manager, for routing the submit-for-approval
     * notification (Notify_On_Submit_For_Approval__c). Returns null rather
     * than throwing when the owner has no ManagerId set (e.g. a queue owner
     * slipped past isQueueOwned's guard, or a user with no manager
     * configured) -- a missing manager here is a silent no-op, exactly
     * mirroring how Approval.process() itself handles a manager-less
     * submitter (surfaced separately in approvalErrorFrom's catch, not
     * here).
     */
    private static Id resolveManagerId(Id ownerId) {
        if (ownerId == null || ownerId.getSObjectType() != User.SObjectType) {
            return null;
        }
        try {
            List<User> owners = [SELECT ManagerId FROM User WHERE Id = :ownerId LIMIT 1];
            return owners.isEmpty() ? null : owners[0].ManagerId;
        } catch (Exception e) {
            return null;
        }
    }

    /** Whether the readout is still sitting on the triage queue. */
    private static Boolean isQueueOwned(Id readoutId) {
        try {
            List<GTM_Readout__c> rows = [SELECT OwnerId FROM GTM_Readout__c WHERE Id = :readoutId LIMIT 1];
            return !rows.isEmpty()
                && rows[0].OwnerId != null
                && rows[0].OwnerId.getSObjectType() == Group.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Approved -> Published. Generates a cryptographically random token,
     * stamps Published_Date__c, and writes a version snapshot. Throws if the
     * readout is not currently Approved (blocks Draft -> Published,
     * Pending Approval -> Published and Published -> Published).
     *
     * THIS IS THE STEP APPROVAL DOES NOT DO, and the separation is a product
     * requirement, not an implementation detail. Approval says the content is
     * fit to send; this says send it, and it mints the token that makes the
     * link resolve. Folding the two together would mean a manager clicking
     * Approve in an email put a live link in a prospect's inbox without anyone
     * deciding to send it. Nothing in
     * approvalProcesses/GTM_Readout__c.GTM_Readout_Approval calls this, and
     * nothing should.
     */
    @AuraEnabled
    public static void publishReadout(Id readoutId) {
        GTM_Readout__c readout = loadForUpdate(readoutId);
        if (readout.Status__c != 'Approved') {
            throw new AuraHandledException(
                readout.Status__c == 'Published'
                    ? 'This readout has already been published.'
                    : 'This readout has to be approved before it can be published.'
            );
        }

        readout.Public_Link_Token__c = generatePublicToken();
        readout.Published_Date__c    = System.now();
        readout.Status__c            = 'Published';

        // Both halves. A version row carrying only the prose could not prove
        // what numbers, bands or provenance chips the approver saw, because the
        // designed readout renders those from Approved_Data__c rather than from
        // the prose -- so a prose-only snapshot would be evidence of half a
        // document.
        GTM_Readout_Version__c version = new GTM_Readout_Version__c(
            Readout__c            = readout.Id,
            Version_Number__c     = nextVersionNumber(readout.Id),
            Snapshot__c           = readout.Approved_Content__c,
            Data_Snapshot__c      = readout.Approved_Data__c,
            Change_Summary__c     = 'Published',
            Status_At_Snapshot__c = 'Published'
        );

        Savepoint sp = Database.setSavepoint();
        try {
            update readout;
            insert version;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw dmlFailure(
                'The readout could not be published. Please try again — if it keeps failing, contact your administrator.',
                readoutId,
                e
            );
        }

        // Notification wiring points 4/5 (ADR-0010, Unit 3b) -- two
        // independent reads in this one method, not two separate methods.
        // Best-effort, same non-blocking guarantee as sendPublishNotification
        // just below: the readout is already Published above and nothing
        // past this point may roll back or block that transition.
        GtmNotificationSettingsController.NotificationSettingsDto settings =
            GtmNotificationSettingsController.getOrgDefaults();
        if (settings.autoCloseApprovedTasks) {
            GtmLifecycleNotificationService.closeOpenTasks(
                readoutId, GtmLifecycleNotificationService.SUBJECT_READOUT_APPROVED);
        }
        if (settings.publishedNotificationMode != GtmNotificationSettingsController.MODE_NONE) {
            Boolean withTask = settings.publishedNotificationMode == GtmNotificationSettingsController.MODE_BELL_AND_TASK;
            if (withTask) {
                GtmLifecycleNotificationService.fireTask(readoutId, readout.OwnerId,
                    GtmLifecycleNotificationService.SUBJECT_READOUT_PUBLISHED,
                    'Your readout was published.');
                // Auto_Close_Published_Tasks__c has no defined close trigger
                // in this unit (owner-resolved Option 1, no-op -- see the
                // scope doc's 1c-RESOLVED section). Deliberately not read
                // here; do not wire it to unpublishReadout or anywhere else.
            }
            GtmLifecycleNotificationService.fireBell(readout.OwnerId, readoutId,
                'Readout published', 'Your readout was published.');
        }

        // Issue #31 engagement-state Task, independent of
        // publishedNotificationMode above (that setting only gates the
        // readout-owner-facing "your readout was published" Task/bell
        // against readoutId; this one always fires against the prospect's
        // own Contact/Account, same as every other engagement-state call
        // site, replacing the retired Engagement Links tab's own always-on
        // published_unsent row). GTM_Assessment_Request__c carries
        // Contact__c/Account__c directly -- loadForUpdate's own SELECT list
        // does not include them since none of its other 5 call sites need
        // them, so this is its own small, targeted query rather than
        // widening a shared helper 5 other methods also use.
        if (readout.Assessment_Request__c != null) {
            List<GTM_Assessment_Request__c> engagementReqs = [
                SELECT Contact__c, Account__c
                FROM GTM_Assessment_Request__c
                WHERE Id = :readout.Assessment_Request__c
                LIMIT 1
            ];
            if (!engagementReqs.isEmpty()) {
                Id engagementWhatId = engagementReqs[0].Contact__c != null
                    ? engagementReqs[0].Contact__c : engagementReqs[0].Account__c;
                if (engagementWhatId != null) {
                    GtmLifecycleNotificationService.syncEngagementStateTask(
                        engagementWhatId, readout.OwnerId, GtmEngagementStateClassifier.STATE_PUBLISHED_UNSENT
                    );
                }
            }
        }

        // Best-effort, non-blocking. The readout is already Published above --
        // nothing past this point may roll back or block that transition. See
        // sendPublishNotification's own header for why every failure inside it
        // is caught and logged rather than re-thrown.
        sendPublishNotification(readoutId, readout.Assessment_Request__c, readout.Public_Link_Token__c);
    }

    /**
     * Emails the prospect a link back to their Experience Cloud configurator
     * page, with `?readout=<token>` appended so gtmConfigurator's already-built
     * checkReadoutToken(token) picks it up on load. This method only sends the
     * link; it does not add or change any of that receiving-end logic.
     *
     * Deliberately swallows every failure. publishReadout has already
     * committed the Approved -> Published transition by the time this runs,
     * and a manager who approved a readout must never have a rep's publish
     * click fail, or roll back, because a mail send hiccuped or a prospect
     * contact is missing an email. The trade-off: a silent miss here is
     * findable only via Notification_Sent_Date__c staying null on the readout,
     * or debug logs -- there is no rep-facing toast for it. That is judged
     * acceptable because publishing is a deliberate, visible rep action
     * already, and the field gives a rep or admin something to check.
     *
     * Notification_Sent_Date__c is stamped only on a confirmed send, in a
     * second, separate DML from the publish update above -- so a failure here
     * can never be blamed for undoing the publish, and the field is never
     * stamped to imply an email went out when it did not.
     */
    @TestVisible
    private static Boolean forceSendFailureForTests = false;

    /**
     * Test-only seam -- see forceSendFailureForTests' own comment inside
     * sendPublishNotification for why this exists instead of a malformed
     * email address or a governor-limit trick. Never called outside test
     * context; the field it flips defaults to false in every real
     * transaction.
     */
    @TestVisible
    private static void setForceSendFailureForTests(Boolean value) {
        forceSendFailureForTests = value;
    }

    /**
     * Test-only seam for the no-page fallback link below. Real unit test
     * context never has an Experience Cloud site ConnectApi.Communities can
     * see (confirmed against GtmSavedConfigurationControllerTest's own
     * orgAndSiteUrlHelpersDoNotThrowEvenWithoutASiteConfigured), so
     * GtmSavedConfigurationController.getReadoutBaseUrl() always resolves
     * null in a test -- there is no way to exercise the fallback branch
     * below deterministically without this, same reasoning as
     * forceSendFailureForTests just above. Defaults to null in every real
     * transaction, which is a no-op (the real getReadoutBaseUrl() call is
     * used).
     */
    @TestVisible
    private static String readoutBaseUrlOverrideForTests = null;

    @TestVisible
    private static void setReadoutBaseUrlOverrideForTests(String value) {
        readoutBaseUrlOverrideForTests = value;
    }

    @TestVisible
    private static void sendPublishNotification(Id readoutId, Id assessmentRequestId, String token) {
        try {
            if (assessmentRequestId == null || String.isBlank(token)) {
                System.debug(
                    LoggingLevel.WARN,
                    'Skipping publish notification for readout ' + readoutId +
                    ': no assessment request or token to notify from.'
                );
                return;
            }

            List<GTM_Assessment_Request__c> reqs = [
                SELECT Requester_Email__c, Requester_Name__c, Company__c, Contact__c, Account__c,
                       Saved_Configuration__r.Generated_URL__c
                FROM GTM_Assessment_Request__c
                WHERE Id = :assessmentRequestId
                LIMIT 1
            ];
            if (reqs.isEmpty()) {
                return;
            }
            GTM_Assessment_Request__c req = reqs[0];

            String toAddress = req.Requester_Email__c;
            if (String.isBlank(toAddress)) {
                System.debug(
                    LoggingLevel.WARN,
                    'Skipping publish notification for readout ' + readoutId +
                    ': missing prospect email on assessment request ' + assessmentRequestId + '.'
                );
                return;
            }

            // A page-linked assessment re-enters the prospect at their branded
            // configurator page with the readout token appended
            // (gtmConfigurator's checkReadoutToken picks it up on load). A
            // Rep_Direct / pageless assessment (rep-initiated-assessment-no-page
            // #1) has no Saved_Configuration__c page and so no
            // Generated_URL__c to build that link from -- falling back to
            // skipping the email entirely here would mean a pageless
            // assessment's prospect NEVER gets notified their readout is
            // ready, silently, forever. The standalone readout route
            // (gtmReadoutReview's own public link, `<site base>/readout?token=`)
            // needs no page at all, so it is what gets used whenever there is
            // no page-linked URL to prefer.
            String pageUrl = req.Saved_Configuration__r != null
                ? req.Saved_Configuration__r.Generated_URL__c
                : null;
            String link;
            if (String.isNotBlank(pageUrl)) {
                link = pageUrl + (pageUrl.contains('?') ? '&' : '?') +
                    'readout=' + EncodingUtil.urlEncode(token, 'UTF-8');
            } else {
                String readoutBase = readoutBaseUrlOverrideForTests != null
                    ? readoutBaseUrlOverrideForTests
                    : GtmSavedConfigurationController.getReadoutBaseUrl();
                if (String.isBlank(readoutBase)) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Skipping publish notification for readout ' + readoutId +
                        ': no page-linked URL and the site base URL could not be resolved ' +
                        'for assessment request ' + assessmentRequestId + '.'
                    );
                    return;
                }
                link = readoutBase + '/readout?token=' + EncodingUtil.urlEncode(token, 'UTF-8');
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String> { toAddress });
            mail.setSaveAsActivity(false);
            mail.setSubject(
                'Your migration readout is ready' +
                (String.isBlank(req.Company__c) ? '' : ' — ' + req.Company__c)
            );
            mail.setPlainTextBody(
                'Hi' + (String.isBlank(req.Requester_Name__c) ? '' : ' ' + req.Requester_Name__c) + ',\n\n' +
                'Your migration readout has been published. View it here:\n\n' + link + '\n\n' +
                'Thanks.'
            );

            // forceSendFailureForTests exists only so a unit test can prove
            // sendPublishNotification's catch-all/non-blocking guarantee for
            // a genuine send failure. There is no way to exercise that branch
            // otherwise: Requester_Email__c is a real Email-type field, so a
            // malformed address can never actually be persisted (Salesforce
            // rejects it with INVALID_EMAIL_ADDRESS before this code runs),
            // any well-formed address reports success in test context (unit
            // tests never really dispatch mail), and governor-limit
            // exceptions -- confirmed directly against gtm-dev -- cannot be
            // caught at all, so they can't be used to simulate this either.
            // Defaults to false in every real transaction; only ever flipped
            // by @TestVisible setForceSendFailureForTests, which only exists
            // in test context.
            Boolean sent = false;
            List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();
            if (!forceSendFailureForTests) {
                results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage> { mail }, false
                );
                sent = !results.isEmpty() && results[0].isSuccess();
            }
            if (!sent) {
                String errorMessage = forceSendFailureForTests
                    ? 'forced failure (test)'
                    : 'unknown error';
                if (!results.isEmpty() && results[0].getErrors() != null && !results[0].getErrors().isEmpty()) {
                    errorMessage = results[0].getErrors()[0].getMessage();
                }
                System.debug(
                    LoggingLevel.WARN,
                    'Publish notification email failed for readout ' + readoutId + ': ' + errorMessage
                );
                return;
            }

            try {
                update new GTM_Readout__c(Id = readoutId, Notification_Sent_Date__c = System.now());
                // Issue #31 engagement-state Task: sent_complete's
                // STATE_ACTION is 'none' -- there is nothing new to fire,
                // only publishReadout's earlier published_unsent Task to
                // close now that the prospect has actually been notified.
                // No ownerId to pass -- syncEngagementStateTask only needs
                // one to fire, and this state never fires.
                Id engagementWhatId = req.Contact__c != null ? req.Contact__c : req.Account__c;
                if (engagementWhatId != null) {
                    GtmLifecycleNotificationService.syncEngagementStateTask(
                        engagementWhatId, null, GtmEngagementStateClassifier.STATE_SENT_COMPLETE
                    );
                }
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'Publish notification email sent for readout ' + readoutId +
                    ' but Notification_Sent_Date__c could not be stamped: ' + e.getMessage()
                );
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Publish notification failed for readout ' + readoutId + ': ' +
                e.getTypeName() + ' at line ' + e.getLineNumber() + ' -- ' + e.getMessage()
            );
        }
    }

    /**
     * Published -> Approved. Clears Public_Link_Token__c in the same
     * transaction that flips Status__c -- this is a security requirement: an
     * old token must stop resolving instantly, not on some later cleanup pass.
     */
    @AuraEnabled
    public static void unpublishReadout(Id readoutId) {
        GTM_Readout__c readout = loadForUpdate(readoutId);
        if (readout.Status__c != 'Published') {
            throw new AuraHandledException(
                'This readout is not published, so there is no public link to revoke.'
            );
        }

        readout.Status__c             = 'Approved';
        readout.Public_Link_Token__c  = null;

        try {
            update readout;
        } catch (DmlException e) {
            throw dmlFailure(
                'The readout could not be unpublished, so its public link may still be live. ' +
                'Please try again — if it keeps failing, contact your administrator.',
                readoutId,
                e
            );
        }
    }

    /**
     * Approved -> Draft. The way back out of a mis-approval: without it an
     * approval is a dead end, because saveDraftContent refuses anything but a
     * Draft and unpublishReadout only ever lands on Approved.
     *
     * SAFETY: this deliberately refuses a **Published** readout rather than
     * reverting it, and the rep has to unpublish first.
     *
     * The alternative -- folding the unpublish into this method so the token
     * dies in the same DML -- would also close the "Draft record with a live
     * token" window, since both fields would be written by one update
     * statement. It was not taken, for three reasons:
     *
     *   1. Revoking a link a prospect already has is a distinct, consequential
     *      act. Bundling it into "let me edit this again" hides it inside
     *      another intent, and the rep gets one toast where two things
     *      happened. Unpublish already exists, already says what it does, and
     *      is one extra click.
     *   2. It keeps every method in this class to exactly one transition,
     *      which is the property that makes the state machine readable.
     *   3. It is the smaller safety surface. This method cannot leave a live
     *      token behind because it never runs on a record that has one --
     *      that is a structural guarantee from the guard below, not a
     *      correctly-ordered pair of field assignments that a later refactor
     *      could split across two DML statements.
     *
     * Public_Link_Token__c is nulled anyway as belt and braces: an Approved
     * readout should already have none (publish sets it, unpublish clears it),
     * so this only matters for a record left inconsistent by some earlier
     * partial failure -- and in that case a Draft is exactly where we do not
     * want the token to survive.
     *
     * The approval is snapshotted to GTM_Readout_Version__c *before* it is
     * cleared, so what was approved, and by whom, stays provable after the
     * revert. Approved_By__c / Approved_Date__c are then cleared on the record
     * itself: leaving them set on a Draft would read as though the draft were
     * still approved.
     */
    @AuraEnabled
    public static void returnToDraft(Id readoutId) {
        GTM_Readout__c readout = loadForUpdate(readoutId);
        if (readout.Status__c == 'Published') {
            throw new AuraHandledException(
                'This readout is published, so its link is live with the prospect. ' +
                'Unpublish it first — that revokes the link — then return it to draft.'
            );
        }
        if (readout.Status__c != 'Approved') {
            throw new AuraHandledException(
                isAwaitingApproval(readoutId, readout)
                    ? 'This readout is waiting on an approver. Recall the approval request ' +
                      'instead — that is what returns it to draft.'
                    : 'Only an approved readout can be returned to draft. This one is already a draft.'
            );
        }

        // Snapshot the approval as it stands, before any of it is cleared.
        // Status_At_Snapshot__c records the status the *content* was in --
        // Approved -- which is what makes this row evidence of the approval;
        // Change_Summary__c records the event that caused the snapshot.
        GTM_Readout_Version__c version = new GTM_Readout_Version__c(
            Readout__c            = readout.Id,
            Version_Number__c     = nextVersionNumber(readout.Id),
            Snapshot__c           = readout.Approved_Content__c,
            Data_Snapshot__c      = readout.Approved_Data__c,
            Change_Summary__c     = returnToDraftSummary(readout),
            Status_At_Snapshot__c = 'Approved'
        );

        readout.Status__c            = 'Draft';
        readout.Approved_By__c       = null;
        readout.Approved_Date__c     = null;
        readout.Public_Link_Token__c = null;

        Savepoint sp = Database.setSavepoint();
        try {
            // The snapshot goes in first: if it fails, the rollback leaves the
            // readout Approved, which is the safe direction to fail in. The
            // reverse order could clear an approval whose only record of
            // itself then failed to save.
            insert version;
            update readout;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw dmlFailure(
                'The readout could not be returned to draft. Please try again — if it keeps ' +
                'failing, contact your administrator.',
                readoutId,
                e
            );
        }

        // Notification wiring point 6 (ADR-0010, Unit 3b). This Task's own
        // auto-close-on-resubmission is the hardcoded closeOpenTasks call
        // inside submitForApproval above, not a field read here.
        if (GtmNotificationSettingsController.getOrgDefaults().notifyOnReturnedToDraft) {
            GtmLifecycleNotificationService.fireTask(readoutId, readout.OwnerId,
                GtmLifecycleNotificationService.SUBJECT_RETURNED_TO_DRAFT,
                'A manager returned your readout to draft for revision.');
            GtmLifecycleNotificationService.fireBell(readout.OwnerId, readoutId,
                'Readout returned to draft', 'A manager returned your readout to draft for revision.');
        }
    }

    /**
     * "Returned to draft (approved 12/03/2026)" -- capped at the 255-character
     * Change_Summary__c field. Carries no prospect content, so it is safe in a
     * list view.
     */
    private static String returnToDraftSummary(GTM_Readout__c readout) {
        String summary = 'Returned to draft';
        if (readout.Approved_Date__c != null) {
            summary += ' (approved ' + readout.Approved_Date__c.format() + ')';
        }
        return summary.length() > 255 ? summary.substring(0, 255) : summary;
    }

    // ----------------------------------------------------------------- helpers

    /**
     * Turns a DML failure into something safe to put in front of a rep.
     *
     * gtmReadoutReview.messageFrom() renders `err.body.message` verbatim into a
     * toast, so whatever goes into an AuraHandledException here is what a rep
     * reads on screen. A DmlException's own message is not that: it quotes the
     * offending field values back (here, prospect content out of
     * Draft_Content__c) alongside internal API names, status codes and field
     * lists -- detail that belongs in a log an admin reads, not in a toast
     * someone screenshots into Slack.
     *
     * So the platform text is logged server-side against the readout Id, and
     * the caller-supplied sentence -- fixed, human, and specific to the action
     * that failed -- is the only thing that crosses back to the client. The
     * *distinguishable* failures a rep can act on (already approved, already
     * published, no longer a draft) are separate state-machine throws above,
     * with our own wording; those are worth telling apart, a DML status code
     * is not.
     */
    private static AuraHandledException dmlFailure(String repMessage, Id readoutId, Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'GtmReadoutController DML failure on readout ' + readoutId + ': ' +
            e.getTypeName() + ' at line ' + e.getLineNumber() + ' -- ' + e.getMessage()
        );
        return new AuraHandledException(repMessage);
    }

    private static GTM_Readout__c loadForUpdate(Id readoutId) {
        if (readoutId == null) {
            throw new AuraHandledException('A readout Id is required.');
        }
        List<GTM_Readout__c> rows = [
            SELECT Id, OwnerId, Status__c, Draft_Content__c, Approved_Content__c,
                   Readout_Data__c, Approved_Data__c,
                   Approved_By__c, Approved_Date__c, Published_Date__c,
                   Public_Link_Token__c, Assessment_Request__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Readout not found.');
        }
        return rows[0];
    }

    private static Integer nextVersionNumber(Id readoutId) {
        Integer count = [SELECT COUNT() FROM GTM_Readout_Version__c WHERE Readout__c = :readoutId];
        return count + 1;
    }

    /**
     * A cryptographically random, URL-safe, 43-character token (256 bits of
     * randomness base64url-encoded) -- not a UUID or anything derived from
     * record data, so it cannot be guessed or enumerated.
     */
    private static String generatePublicToken() {
        // Crypto.getRandomBlob(Integer) does not exist in this org (confirmed
        // directly against gtm-dev -- "Method does not exist or incorrect
        // signature"). generateAesKey(256) is a documented, ordinary way to
        // get 32 cryptographically random bytes when what is wanted is bytes,
        // not an AES key -- "256" names the bit length, matching the 32-byte
        // (256-bit) token this method has always produced. Pre-existing bug,
        // never caught because this class had never been deployed either.
        Blob bytes = Crypto.generateAesKey(256);
        String token = EncodingUtil.base64Encode(bytes)
            .replace('+', '-')
            .replace('/', '_')
            .replace('=', '');
        return token.length() > 64 ? token.substring(0, 64) : token;
    }
}
