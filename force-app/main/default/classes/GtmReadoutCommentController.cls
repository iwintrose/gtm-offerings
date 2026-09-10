/**
 * SECURITY-SENSITIVE -- this is the guest-accessible WRITE surface for
 * published readouts. Any change here needs security-review before merge.
 * Read GtmReadoutPublicController's header first; this class is the write-side
 * twin of it and holds itself to the same contract.
 *
 * It exposes exactly two methods to an unauthenticated caller:
 *
 *   getCommentSections()  -- a constant list of section labels. No arguments,
 *                            no record access, nothing to leak. It exists so
 *                            the picker on the guest page and the validation
 *                            here cannot drift apart.
 *   submitComment()       -- appends one recipient comment to the review Case
 *                            of the readout a token resolves to.
 *
 * WHY THIS IS SAFE WITHOUT ANY OBJECT PERMISSION
 * ----------------------------------------------
 * The guest user has NO object permission on Case, CaseComment or
 * GTM_Readout__c, and must not be given one -- see the "do not re-add" comment
 * in GTM_Assessment_Guest.permissionset. `without sharing` Apex SOQL/DML runs in
 * system mode for CRUD/FLS, so class access is the entire grant this needs, and
 * that grant is per class: it buys the caller these two methods and nothing
 * else. Granting object permissions instead would open a second, token-free
 * path (LDS / uiRecordApi / list views) onto client conversations.
 *
 * NO EXISTENCE LEAK
 * -----------------
 * The token check is the same WHERE clause as the read path
 * (Status__c = 'Published' AND Public_Link_Token__c = :token), enforced in
 * SOQL, never fetch-then-check. From that lookup onward EVERY outcome --
 * token never issued, token for a Draft/Pending/Approved readout, token
 * revoked by unpublish, readout with no review case, rate limit hit, DML
 * failure -- returns the byte-identical refusal. A caller cannot tell any of
 * them apart, so a comment box cannot be used as an oracle for "is a readout
 * being prepared for this deal".
 *
 * The only failures that say something specific are the ones decided purely
 * from the caller's own input (empty comment, over-length comment, unknown
 * section). Those are evaluated FIRST, before the token is looked at at all,
 * so no specific message can ever depend on whether a token resolves. That
 * ordering is load-bearing -- do not move the token lookup above it.
 *
 * WRITE-ONLY, DELIBERATELY
 * ------------------------
 * There is no method here that reads comments back. The rep replies from the
 * Case in Salesforce, and the same thread is where they will write internal
 * notes to each other; there is no native, reliable way to tell an internal
 * note from a reply meant for the prospect without building the custom
 * machinery this design exists to avoid. So the guest page can post to the
 * thread and can never read from it, and CaseComment.IsPublished is set false
 * to say the same thing in the platform's own vocabulary. A rep who wants the
 * prospect to have their reply sends it to them.
 */
public without sharing class GtmReadoutCommentController {

    /**
     * The readout's sections, in reading order. Comments are per section, and
     * this is the only list of them -- the guest page fetches it rather than
     * carrying its own copy, so a section added here cannot silently become an
     * option the server then rejects.
     */
    private static final List<String> SECTIONS = new List<String>{
        'Verdict',
        'Context',
        'Scorecard',
        'Capability gaps',
        'Findings',
        'The path',
        'Next steps'
    };

    /**
     * Comment body cap. CaseComment.CommentBody holds 4000 characters; the
     * headroom is for the section header line this class prepends, and for the
     * fact that sanitising can only ever shorten the text.
     */
    @TestVisible
    private static final Integer MAX_BODY_LENGTH = 3000;

    /** Hard ceiling on what one CaseComment may ever contain. */
    private static final Integer COMMENT_BODY_LIMIT = 4000;

    /** Throttle: at most this many recipient comments per readout per window. */
    @TestVisible
    private static final Integer MAX_PER_WINDOW = 5;

    @TestVisible
    private static final Integer WINDOW_MINUTES = 10;

    /** Lifetime ceiling per readout, so a thread cannot be grown without end. */
    @TestVisible
    private static final Integer MAX_PER_READOUT = 100;

    /**
     * The single refusal. Every failure that could reveal anything about a
     * token, a readout or a case uses this exact text.
     */
    @TestVisible
    private static final String GENERIC_REFUSAL =
        'Your comment could not be sent. Please reach out to your Publicis Sapient contact.';

    private static final String SUCCESS_MESSAGE =
        'Thanks — your comment has been sent to your Publicis Sapient contact.';

    // ------------------------------------------------------------- sections

    /**
     * Cacheable and argument-free: the response is a compile-time constant, so
     * there is nothing for the client cache to serve stale and nothing a caller
     * can vary to probe with.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getCommentSections() {
        return new List<String>(SECTIONS);
    }

    // -------------------------------------------------------------- writing

    /**
     * Appends one recipient comment to the readout's review Case.
     *
     * Returns a CommentResult rather than throwing, because an
     * AuraHandledException's message and an exception's mere occurrence are
     * both signal, and this method must emit the same signal for every
     * server-state failure.
     */
    @AuraEnabled
    public static CommentResult submitComment(String token, String section, String body) {
        // ---- 1. Input-shape checks. These depend on nothing but the caller's
        // own arguments, so a specific message here reveals nothing about the
        // org. They MUST stay above the token lookup.
        String canonicalSection = canonicalSectionOf(section);
        if (canonicalSection == null) {
            return refused(
                'Please choose which section of the readout your comment is about.'
            );
        }
        if (body != null && body.length() > MAX_BODY_LENGTH) {
            return refused(
                'Your comment is a little long — please keep it under ' +
                MAX_BODY_LENGTH + ' characters.'
            );
        }
        String cleaned = sanitize(body);
        if (String.isBlank(cleaned)) {
            return refused('Please write a comment before sending.');
        }

        // ---- 2. Everything below here is indistinguishable on failure.
        if (String.isBlank(token)) {
            return refused(GENERIC_REFUSAL);
        }

        // Same clause as GtmReadoutPublicController.getPublishedReadout, and for
        // the same reason: the filter IS the access control, so it belongs in
        // the WHERE clause where no later refactor can drop it. A comment may
        // only ever be attached to a currently-published readout.
        List<GTM_Readout__c> readouts = [
            SELECT Id
            FROM GTM_Readout__c
            WHERE Status__c = 'Published'
            AND Public_Link_Token__c = :token
            LIMIT 1
        ];
        if (readouts.isEmpty()) {
            return refused(GENERIC_REFUSAL);
        }
        Id readoutId = readouts[0].Id;

        Id caseId = reviewCaseIdFor(readoutId);
        if (caseId == null) {
            // No review case: the readout predates this feature, or the Case
            // insert failed at generation. Nothing to attach to, and saying so
            // would confirm the token is good.
            System.debug(
                LoggingLevel.WARN,
                'Recipient comment dropped: readout ' + readoutId + ' has no review Case. ' +
                'Create one (or re-run generation) to reopen the thread.'
            );
            return refused(GENERIC_REFUSAL);
        }

        if (isRateLimited(caseId)) {
            // Silent by design. A "you are commenting too fast" message is only
            // reachable with a valid token, so it would be an oracle.
            System.debug(
                LoggingLevel.WARN,
                'Recipient comment throttled on case ' + caseId + ' for readout ' + readoutId
            );
            return refused(GENERIC_REFUSAL);
        }

        try {
            insert new CaseComment(
                ParentId    = caseId,
                CommentBody = formatBody(canonicalSection, cleaned),
                // Internal. The prospect never reads this thread back -- see
                // the class header -- and IsPublished = true would additionally
                // expose it to any portal/community user on the case.
                IsPublished = false
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Recipient comment insert failed on case ' + caseId + ': ' +
                e.getTypeName() + ' at line ' + e.getLineNumber()
            );
            return refused(GENERIC_REFUSAL);
        }
        return accepted(SUCCESS_MESSAGE);
    }

    // -------------------------------------------------------------- helpers

    /**
     * The review Case for a readout: the OLDEST case pointing at it.
     *
     * Deterministic on purpose. GtmReadoutController.Generator files exactly one
     * case per readout, but a rep can raise more later from the readout's Cases
     * related list, and the recipient's thread must not migrate to whichever
     * case happens to be newest. The first one is the review case by
     * construction, so the conversation stays where the rep has been reading
     * it.
     */
    private static Id reviewCaseIdFor(Id readoutId) {
        List<Case> cases = [
            SELECT Id
            FROM Case
            WHERE Readout__c = :readoutId
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 1
        ];
        return cases.isEmpty() ? null : cases[0].Id;
    }

    /**
     * Cheap, native throttling: count what this caller has already written to
     * this thread.
     *
     * CreatedById is the site guest user for everything posted through the
     * public page, and a rep's own replies carry their own user Id -- so this
     * counts recipient comments only, and rep activity can never throttle the
     * prospect. (CommentBody is a Long Text Area and cannot be filtered with
     * LIKE, so the author Id is also the only filter available.)
     *
     * KNOWN LIMIT, stated rather than implied: the bucket is per readout, not
     * per visitor, because a token is the only identity an anonymous caller
     * has. It bounds storage growth and stops a flood; it does not stop a
     * determined holder of a valid token from spending that readout's own
     * quota. Per-IP throttling needs an edge/WAF or Platform Cache, neither of
     * which is deployable from this repo -- see the runbook.
     */
    private static Boolean isRateLimited(Id caseId) {
        try {
            Id author = UserInfo.getUserId();
            Integer total = [
                SELECT COUNT()
                FROM CaseComment
                WHERE ParentId = :caseId AND CreatedById = :author
            ];
            if (total >= MAX_PER_READOUT) {
                return true;
            }
            Datetime windowStart = System.now().addMinutes(-WINDOW_MINUTES);
            Integer recent = [
                SELECT COUNT()
                FROM CaseComment
                WHERE ParentId = :caseId
                AND CreatedById = :author
                AND CreatedDate >= :windowStart
            ];
            return recent >= MAX_PER_WINDOW;
        } catch (Exception e) {
            // Fail closed. A counting query that will not run is not a licence
            // to accept unlimited writes from an anonymous caller.
            System.debug(LoggingLevel.WARN, 'Comment throttle check failed: ' + e.getMessage());
            return true;
        }
    }

    /**
     * The stored shape. A header line naming the source and the section, then
     * the text:
     *
     *     [Recipient comment — Scorecard]
     *     We think the integration score is generous...
     *
     * Per-section state is carried as a prefix convention rather than as a
     * field because CaseComment does not accept custom fields at all, and a
     * field on Case could not work either: there is one Case per readout
     * carrying many comments across different sections, so a Case-level field
     * has nowhere to vary. The alternatives were a custom object (which is the
     * net-new build this design exists to avoid) or nothing. A prefix is
     * readable in the native related list, greppable, and survives a rep
     * replying natively in the same thread.
     */
    private static String formatBody(String section, String cleaned) {
        String formatted = '[Recipient comment — ' + section + ']\n' + cleaned;
        return formatted.length() > COMMENT_BODY_LIMIT
            ? formatted.substring(0, COMMENT_BODY_LIMIT)
            : formatted;
    }

    /**
     * Matches the caller's section against SECTIONS case-insensitively and
     * returns OUR spelling of it -- so what is stored is always one of seven
     * known strings and never anything the caller chose. Returns null for
     * anything unrecognised.
     */
    private static String canonicalSectionOf(String section) {
        if (String.isBlank(section)) {
            return null;
        }
        String needle = section.trim().toLowerCase();
        for (String known : SECTIONS) {
            if (known.toLowerCase() == needle) {
                return known;
            }
        }
        return null;
    }

    /**
     * Recipient text is rendered back to reps inside Salesforce, so it is
     * treated as hostile all the way through:
     *
     *   - HTML tags are stripped outright. CommentBody renders as plain text in
     *     the Case Comments related list, but "renders as plain text today" is
     *     not a property to bet a client's org on -- the same string turns up
     *     in report exports, email templates and anything a future component
     *     chooses to render.
     *   - Control characters go, so a comment cannot smuggle terminal escapes
     *     or line-break trickery into a related list or an export.
     *   - A leading =, + or @ is defused with a quote: those are the characters
     *     a spreadsheet treats as the start of a formula when someone exports
     *     the case to CSV. ('-' is deliberately left alone -- it is how people
     *     write bullet lists, and it is only dangerous in combination.)
     *   - Runs of blank lines collapse, so the thread cannot be padded out.
     */
    @TestVisible
    private static String sanitize(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String cleaned = raw.replace('\r\n', '\n').replace('\r', '\n');
        // Anything tag-shaped, then any stray angle bracket. Done with plain
        // regexes rather than String.stripHtmlTags(), which is deprecated --
        // this is security-relevant enough that it should not sit on a method
        // Salesforce has already said not to use.
        cleaned = cleaned.replaceAll('<[^>]*>', ' ');
        cleaned = cleaned.replaceAll('[<>]', ' ');
        cleaned = cleaned.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]', ' ');
        cleaned = cleaned.replaceAll('\n{3,}', '\n\n');
        cleaned = cleaned.trim();
        if (cleaned.startsWith('=') || cleaned.startsWith('+') || cleaned.startsWith('@')) {
            cleaned = '\'' + cleaned;
        }
        return cleaned.length() > MAX_BODY_LENGTH
            ? cleaned.substring(0, MAX_BODY_LENGTH)
            : cleaned;
    }

    /**
     * Deliberately carries no record Id, no case number and no token -- there
     * is nothing in this shape for a caller to correlate.
     *
     * Built through the two static helpers below rather than by the inner class
     * itself: Apex does not allow static members on an inner class.
     */
    public class CommentResult {
        @AuraEnabled public Boolean accepted { get; set; }
        @AuraEnabled public String  message  { get; set; }
    }

    private static CommentResult accepted(String message) {
        CommentResult result = new CommentResult();
        result.accepted = true;
        result.message  = message;
        return result;
    }

    private static CommentResult refused(String message) {
        CommentResult result = new CommentResult();
        result.accepted = false;
        result.message  = message;
        return result;
    }
}
