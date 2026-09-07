/**
 * Everything GUS is allowed to READ on the readout editor, plus the two
 * @AuraEnabled methods gtmReadoutAssist uses to store the rep's own context.
 *
 * ── Access ────────────────────────────────────────────────────────────────
 * GTM_Readout__c is sharingModel Private: access flows from OwnerId, and a rep
 * legitimately sees the readouts they own plus the orphans sitting in the
 * GTM_Readout_Triage queue. This class is `with sharing` so every query here
 * runs under that model even though its caller
 * (GtmAgentProxyController.runLoop) is `without sharing` — in Apex the sharing
 * keyword belongs to the class the code executes in, not to the caller.
 *
 * That alone is not what this relies on. `with sharing` is a property of a
 * file, and files get refactored; a readout tool that can read and rewrite
 * client deal content should not be one keyword away from leaking. So
 * assertReadable/assertEditable additionally query UserRecordAccess for the
 * running user and throw if the answer is no. That check is explicit, is made
 * on every entry point and every tool call, and would still hold if this class
 * were flipped to `without sharing` tomorrow. Belt and braces, deliberately.
 *
 * ── Untrusted content ─────────────────────────────────────────────────────
 * Three of the things read here are written by someone other than the rep:
 * the prospect's own assessment answers, the recipient's case comments, and
 * whatever the rep pasted or dropped in (which is very often a client's own
 * document). None of it is instructions. It is wrapped by
 * GtmReadoutAgentSurface in explicit data fences before it reaches the model,
 * and this class deliberately hands it back as plain strings on labelled keys
 * rather than pre-formatted prose, so there is exactly one place responsible
 * for that fencing.
 */
public with sharing class GtmReadoutAgentContext {

    /** Ceilings on what one tool result may carry back to the model. */
    public static final Integer MAX_NOTES_CHARS      = 20000;
    public static final Integer MAX_COMMENT_CHARS    = 8000;
    public static final Integer MAX_COMMENTS         = 25;

    // ────────────────────────────────────────────────────────── access gates

    /**
     * Throws unless the running user can READ this readout.
     *
     * UserRecordAccess is the platform's own answer to "can this user see this
     * record", covering ownership, role hierarchy, sharing rules and manual
     * shares in one query — which is why it is used rather than re-deriving
     * ownership from OwnerId.
     */
    public static void assertReadable(Id readoutId) {
        if (readoutId == null) {
            throw new AuraHandledException('A readout Id is required.');
        }
        if (!hasAccess(readoutId, false)) {
            // Same message for "does not exist" and "not yours": a rep must not
            // be able to probe for readouts they cannot see.
            throw new AuraHandledException(
                'That readout is not available to you. Open it from the Readout Queue.'
            );
        }
    }

    /** Throws unless the running user can EDIT this readout. */
    public static void assertEditable(Id readoutId) {
        if (readoutId == null) {
            throw new AuraHandledException('A readout Id is required.');
        }
        if (!hasAccess(readoutId, true)) {
            throw new AuraHandledException(
                'You do not have edit access to that readout.'
            );
        }
    }

    /**
     * The non-throwing form, for tool execution — a tool must return a JSON
     * error the model can explain, not an exception that kills the turn.
     */
    public static Boolean hasAccess(Id readoutId, Boolean needEdit) {
        if (readoutId == null) return false;
        List<UserRecordAccess> rows = [
            SELECT RecordId, HasReadAccess, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId()
              AND RecordId = :readoutId
            LIMIT 1
        ];
        if (rows.isEmpty()) return false;
        return needEdit == true ? rows[0].HasEditAccess : rows[0].HasReadAccess;
    }

    // ─────────────────────────────────────────────────────── readout context

    /**
     * The readout, its assessment, its opportunity and its instrument pair, as
     * a plain map ready to be JSON-serialised into a tool result.
     *
     * Returns a map with an `error` key rather than throwing, for the same
     * reason hasAccess exists.
     */
    public static Map<String, Object> readoutContext(Id readoutId) {
        if (!hasAccess(readoutId, false)) {
            return new Map<String, Object>{
                'error' => 'You do not have access to this readout.'
            };
        }

        List<GTM_Readout__c> rows = [
            SELECT Id, Name, Status__c, Draft_Content__c, Approved_Content__c,
                   Rep_Context_Notes__c, Offering_Key__c, OwnerId,
                   Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName,
                   Opportunity__r.Amount, Opportunity__r.CloseDate,
                   Assessment_Request__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new Map<String, Object>{ 'error' => 'Readout not found.' };
        }
        GTM_Readout__c r = rows[0];

        Map<String, Object> out = new Map<String, Object>{
            'readoutId'       => r.Id,
            'readoutName'     => r.Name,
            'status'          => r.Status__c,
            'editable'        => isDraftEditable(r.Status__c),
            'offeringKey'     => r.Offering_Key__c,
            'hasRepNotes'     => String.isNotBlank(r.Rep_Context_Notes__c)
        };

        if (r.Opportunity__c != null && r.Opportunity__r != null) {
            out.put('opportunity', new Map<String, Object>{
                'name'      => r.Opportunity__r.Name,
                'stage'     => r.Opportunity__r.StageName,
                'amount'    => r.Opportunity__r.Amount,
                'closeDate' => String.valueOf(r.Opportunity__r.CloseDate)
            });
        }

        out.put('assessment', assessmentContext(r.Assessment_Request__c));
        return out;
    }

    /** True only in the one status where a draft edit can legally land. */
    public static Boolean isDraftEditable(String status) {
        return 'Draft'.equals(status);
    }

    /**
     * The prospect's submitted assessment: scores, both axes, the tier, the
     * per-dimension answers with their human wording, and the qualitative
     * free-text fields.
     *
     * The free-text fields are the PROSPECT'S OWN WORDS. They are returned on
     * their own labelled sub-map so the surface can fence them as data — a
     * prospect who typed instructions into "what's prompting the move" is
     * still just a prospect who typed something.
     */
    public static Map<String, Object> assessmentContext(Id requestId) {
        if (requestId == null) {
            return new Map<String, Object>{
                'present' => false,
                'note'    => 'This readout has no linked assessment request.'
            };
        }

        List<GTM_Assessment_Request__c> rows = [
            SELECT Id, Name, Company__c, Status__c, Submitted_At__c,
                   Current_Platform__c, Target_Platform__c, Branch_Platform__c,
                   Assessment_Score__c, Assessment_Tier__c, Section_Scores__c,
                   Assessment_Flags__c, Assessment_Advisory__c, Advisory_Reason__c,
                   Estate_Complexity_Score__c, Estate_Complexity_Band__c,
                   Estate_Complexity_Basis__c, Estate_Complexity_Dimensions__c,
                   Context__c, Pain_Points__c, Migration_Goals__c,
                   Success_Criteria__c, Timeline__c, Urgency_Driver__c,
                   Budget_Range__c, Environment_Size__c, Contact_Count__c,
                   Monthly_Send_Volume__c, Internal_Team_Size__c,
                   Key_Integrations__c, Decision_Makers__c,
                   Executive_Sponsorship__c, Role__c
            FROM GTM_Assessment_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new Map<String, Object>{
                'present' => false,
                'note'    => 'The linked assessment request is not visible to you.'
            };
        }
        GTM_Assessment_Request__c a = rows[0];

        Map<String, Object> out = new Map<String, Object>{
            'present'            => true,
            'company'            => a.Company__c,
            'submittedAt'        => String.valueOf(a.Submitted_At__c),
            'currentPlatform'    => a.Current_Platform__c,
            'targetPlatform'     => a.Target_Platform__c,
            'branchPlatform'     => a.Branch_Platform__c,
            'advisoryOnly'       => a.Assessment_Advisory__c == true,
            'advisoryReason'     => a.Advisory_Reason__c,
            // "18 out of 32" is the only honest shape — the maximum comes from
            // the scorer so this can never disagree with what produced it.
            'readinessScore'     => a.Assessment_Score__c,
            'readinessMaxScore'  => GtmAssessmentScoring.MAX_TOTAL_SCORE,
            'tier'               => a.Assessment_Advisory__c == true ? null : a.Assessment_Tier__c,
            'complexityScore'    => a.Estate_Complexity_Score__c,
            'complexityMaxScore' => GtmEstateComplexity.MAX_TOTAL_SCORE,
            'complexityBand'     => a.Estate_Complexity_Band__c,
            'complexityBasis'    => a.Estate_Complexity_Basis__c,
            'scoreMeaning'       =>
                'A HIGHER readiness score means a smaller, simpler, lower-risk estate — not a more ' +
                'sophisticated marketing operation. A large, heavily-customised estate scores LOW ' +
                'because it is harder to migrate. Engagement size lives on the separate complexity ' +
                'axis and is never added to the readiness total.',
            'readinessDimensions'  => dimensionBreakdown(a.Section_Scores__c),
            'complexityDimensions' => dimensionBreakdown(a.Estate_Complexity_Dimensions__c),
            'annotations'          => annotationMessages(a.Assessment_Flags__c),
            'pairEligibility'      => pairEligibility(a.Current_Platform__c, a.Target_Platform__c)
        };

        // Prospect-authored free text, fenced by the caller. Facts about the
        // deal, never directions to follow.
        out.put('prospectAnswers', new Map<String, Object>{
            'whatsPromptingTheMove' => a.Context__c,
            'painPoints'            => a.Pain_Points__c,
            'migrationGoals'        => a.Migration_Goals__c,
            'successCriteria'       => a.Success_Criteria__c,
            'timeline'              => a.Timeline__c,
            'urgencyDriver'         => a.Urgency_Driver__c,
            'budgetRange'           => a.Budget_Range__c,
            'environmentSize'       => a.Environment_Size__c,
            'contactCount'          => a.Contact_Count__c,
            'monthlySendVolume'     => a.Monthly_Send_Volume__c,
            'internalTeamSize'      => a.Internal_Team_Size__c,
            'keyIntegrations'       => a.Key_Integrations__c,
            'decisionMakers'        => a.Decision_Makers__c,
            'executiveSponsorship'  => a.Executive_Sponsorship__c,
            'requesterRole'         => a.Role__c
        });

        return out;
    }

    /**
     * "{dimension name}: {value}" pairs from one of the stored score blobs.
     * Machine keys are what is stored; the wording lives in
     * GTM_Assessment_Question__mdt. A key with no configured name still appears
     * as the key — a missing label must not silently delete a dimension.
     */
    private static List<Object> dimensionBreakdown(String scoresJson) {
        List<Object> out = new List<Object>();
        if (String.isBlank(scoresJson)) return out;
        Map<String, String> names;
        try {
            names = GtmAssessmentQuestions.dimensionNames();
        } catch (Exception e) {
            names = new Map<String, String>();
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(scoresJson);
            for (String key : parsed.keySet()) {
                String label = names.get(key);
                out.add(new Map<String, Object>{
                    'key'   => key,
                    'name'  => String.isBlank(label) ? key : label,
                    'value' => parsed.get(key)
                });
            }
        } catch (Exception e) {
            // Malformed blob: the rest of the context is still worth having.
        }
        return out;
    }

    /** The non-blocking observations the scorer raised, as plain messages. */
    private static List<Object> annotationMessages(String flagsJson) {
        List<Object> out = new List<Object>();
        if (String.isBlank(flagsJson)) return out;
        try {
            for (Object raw : (List<Object>) JSON.deserializeUntyped(flagsJson)) {
                Object message = ((Map<String, Object>) raw).get('message');
                if (message != null) out.add(String.valueOf(message));
            }
        } catch (Exception e) {
            // Malformed blob: skip.
        }
        return out;
    }

    /** Whether the accelerator can actually process this source/target pair. */
    private static Map<String, Object> pairEligibility(String source, String target) {
        try {
            GtmAssessmentScoring.PairEligibility p = GtmMigrationPairs.evaluate(source, target);
            return new Map<String, Object>{
                'evaluated' => p.evaluated,
                'supported' => p.supported,
                'reason'    => p.reason
            };
        } catch (Exception e) {
            return new Map<String, Object>{ 'evaluated' => false };
        }
    }

    // ────────────────────────────────────────────────── rep-supplied context

    /**
     * What the rep has dropped in: their own notes, the text of any files
     * attached to the readout, and the recipient comment thread.
     *
     * ALL THREE ARE DATA. The rep's notes are the only part written by the
     * person in the chair, and even those routinely contain pasted client
     * emails and meeting transcripts. The caller fences the lot.
     */
    public static Map<String, Object> repContext(Id readoutId) {
        if (!hasAccess(readoutId, false)) {
            return new Map<String, Object>{
                'error' => 'You do not have access to this readout.'
            };
        }

        String notes = '';
        List<GTM_Readout__c> rows = [
            SELECT Id, Rep_Context_Notes__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
            LIMIT 1
        ];
        if (!rows.isEmpty() && String.isNotBlank(rows[0].Rep_Context_Notes__c)) {
            notes = truncate(rows[0].Rep_Context_Notes__c, MAX_NOTES_CHARS);
        }

        return new Map<String, Object>{
            'repNotes'          => notes,
            'attachments'       => GtmReadoutAgentFiles.extractAll(readoutId),
            'recipientComments' => recipientComments(readoutId)
        };
    }

    /**
     * The review Case's comment thread — where the recipient's feedback lands
     * and where the rep replies. Same "oldest case wins" rule
     * GtmReadoutCommentController uses to pick where comments go, so this can
     * never read a different case than the editor links to.
     *
     * Best-effort: a readout generated before the review-case feature simply
     * has no case, and this returns an empty list.
     */
    private static List<Object> recipientComments(Id readoutId) {
        List<Object> out = new List<Object>();
        try {
            List<Case> cases = [
                SELECT Id FROM Case WHERE Readout__c = :readoutId
                ORDER BY CreatedDate ASC, Id ASC LIMIT 1
            ];
            if (cases.isEmpty()) return out;

            Integer budget = MAX_COMMENT_CHARS;
            for (CaseComment c : [
                SELECT CommentBody, CreatedDate, CreatedById
                FROM CaseComment
                WHERE ParentId = :cases[0].Id
                ORDER BY CreatedDate ASC
                LIMIT :MAX_COMMENTS
            ]) {
                if (budget <= 0) break;
                String body = truncate(c.CommentBody, budget);
                budget -= (body == null ? 0 : body.length());
                out.add(new Map<String, Object>{
                    'createdDate' => String.valueOf(c.CreatedDate),
                    'body'        => body
                });
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Recipient comment read failed: ' + e.getMessage());
        }
        return out;
    }

    private static String truncate(String value, Integer max) {
        if (String.isBlank(value)) return '';
        return value.length() <= max
            ? value
            : value.substring(0, max) + '\n[truncated]';
    }

    // ──────────────────────────────────────────────────────── LWC entry points

    /** The rep's stored notes, for gtmReadoutAssist's textarea. */
    @AuraEnabled
    public static String getRepNotes(Id readoutId) {
        assertReadable(readoutId);
        List<GTM_Readout__c> rows = [
            SELECT Id, Rep_Context_Notes__c FROM GTM_Readout__c
            WHERE Id = :readoutId LIMIT 1
        ];
        return rows.isEmpty() ? '' : rows[0].Rep_Context_Notes__c;
    }

    /**
     * Stores the rep's own deal context.
     *
     * This writes an INTERNAL field. It is not readout content, it is never
     * published, and it does not pass through approval — so unlike
     * saveDraftContent it is not restricted to Draft. A rep who has just been
     * told something on a call should be able to write it down whatever state
     * the readout is in.
     *
     * The one state that refuses is Pending Approval, and not by our choice:
     * the approval process locks the record (recordEditability AdminOnly), so
     * the DML would fail anyway. Saying why beats the platform's own wording.
     */
    @AuraEnabled
    public static void saveRepNotes(Id readoutId, String notes) {
        assertEditable(readoutId);
        if (notes != null && notes.length() > MAX_NOTES_CHARS) {
            throw new AuraHandledException(
                'Those notes are longer than ' + MAX_NOTES_CHARS + ' characters. Trim them, or attach the source as a file.'
            );
        }
        List<GTM_Readout__c> rows = [
            SELECT Id, Status__c FROM GTM_Readout__c WHERE Id = :readoutId LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Readout not found.');
        }
        GTM_Readout__c r = rows[0];
        r.Rep_Context_Notes__c = notes;
        try {
            update r;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                'Rep notes save failed on readout ' + readoutId + ': ' + e.getMessage());
            throw new AuraHandledException(
                'Pending Approval'.equals(r.Status__c)
                    ? 'This readout is locked while an approver has it. Recall the approval request to add notes.'
                    : 'Your notes could not be saved. Please try again.'
            );
        }
    }
}
