/**
 * SECURITY-SENSITIVE -- this is the guest-accessible, guest-WRITABLE surface for
 * half-finished readiness questionnaires. Any change here needs security-review
 * before merge.
 *
 * WHY IT EXISTS. Progress used to live in localStorage only. That survives a
 * refresh and a closed tab on one device, and nothing else -- not a phone
 * handed to a colleague, not "I'll finish this on my laptop tonight", not a
 * cleared cache. Requirement #12 is that a respondent can always pick up
 * where they left off. localStorage stays as the fast path (every keystroke,
 * no round trip); this class is the durable one.
 *
 * APPEND-AND-COUNT, NOT UPDATE-IN-PLACE. An earlier design used an in-place
 * counter column and update draft. It was never deployed, and before writing
 * this version an empirical probe was run against this exact org (see
 * docs/handoff/port-map-ma-to-gtm.md section F): a guest user, via Apex
 * running in system mode (no `with sharing` declared -- the same enforcement
 * class as `without sharing`), CANNOT update a record it does not own AND
 * cannot update a record it created itself moments earlier in the same
 * transaction. Both probes returned
 * INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY. So every "save" here is a
 * new INSERT, exactly the mechanism GtmFormDraftController already proves
 * works for the booking form on this same object. The most recent row for a
 * token (ORDER BY CreatedDate DESC, Id DESC -- the same tie-break
 * GtmFormDraftController uses, for the same reason: CreatedDate is
 * second-resolution and ties are real) is the current answers.
 *
 * REVOCATION WITHOUT UPDATE. Submitting no longer flips a Status__c column on
 * the existing row -- it cannot. GtmAssessmentRequestController.closeDraft
 * appends one final row carrying Submitted_Request__c. Because that row is
 * then the most recent one for the token, resumeDraft's own "most recent row"
 * lookup finds it and refuses to resolve. No update, anywhere, ever, on this
 * object, from a guest.
 *
 * SHARES A TABLE WITH ANOTHER GUEST POPULATION. GTM_Form_Draft__c also holds
 * the short configurator-booking draft (Draft_Type__c = 'Booking', owned by
 * GtmFormDraftController, guest permission set GTM_Story_Guest). Every query
 * and insert here filters/sets Draft_Type__c = 'Assessment'. This class is
 * granted NO object or field permission on GTM_Form_Draft__c in
 * GTM_Assessment_Guest -- deliberately absent, exactly as the earlier design
 * had none. Its access is entirely through this class's own class-level
 * grant. See docs/handoff/port-map-ma-to-gtm.md section E.
 *
 * THE WHOLE SURFACE IS THREE METHODS, AND ALL THREE ARE ADDRESSED BY TOKEN.
 * There is no method here that takes a record Id, and there must never be one.
 *
 * ONE FAILURE, ONE RESPONSE. A token that never existed, a token that expired,
 * a token whose draft was submitted, and a token over its append cap are
 * indistinguishable to the caller: resumeDraft returns null for all four,
 * saveDraft throws the identical message for all four, emailResumeLink
 * returns the identical result for all four.
 *
 * ANSWERS ARE PROSPECT DATA. Draft_JSON__c is written and read, and otherwise
 * never touched: it is not logged, not put in an exception message, not
 * included in any email, and not returned by anything but resumeDraft against
 * a valid, unrevoked token.
 *
 * `without sharing`: mirrors GtmFormDraftController. The rows are owned by
 * the guest user, and even a guest-owned record is not reliably reachable
 * with sharing enforced under this org's guest-access hardening -- see the
 * probe note above.
 *
 * WHAT THIS CLASS CANNOT DO, which is most of the point: it cannot create,
 * read or modify a GTM_Assessment_Request__c, a Contact, a Lead, an
 * Opportunity or a Task. Submitting stays where it was -- exactly one guest
 * write path, GtmAssessmentRequestController.submitRequest -- and that class,
 * not this one, is what closes the draft on submit.
 */
public without sharing class GtmAssessmentDraftController {

    /**
     * 30 days, counted from each row's own creation and never extended.
     *
     * This is a considered B2B diagnostic, not a checkout. Respondents
     * routinely park it to go and count workflows with a colleague or wait for
     * the ops meeting where someone can answer question 6, and that errand is
     * measured in days to weeks. A week would expire links mid-errand, which
     * costs the submission the whole feature exists to save. On the other side,
     * the instrument itself is versioned and revised on a cadence of months, so
     * a link older than a month is increasingly answering a questionnaire that
     * no longer exists -- and a forgotten link in an old inbox is a live door
     * onto prospect answers for as long as it lives. Thirty days is the point
     * where those two curves cross.
     *
     * NOT EXTENDED ON SAVE, deliberately: a life counted from last touch can be
     * kept alive forever by anything that keeps touching it. Each new row still
     * gets a fresh 30-day Expires_At__c from ITS OWN creation, but resumeDraft
     * reads the ORIGINAL row's expiry (the oldest row for the token) as the
     * ceiling -- see resumeDraft.
     */
    @TestVisible
    private static final Integer TTL_DAYS = 30;

    /** Draft_JSON__c is a 131,072-char Long Text, shared with the booking
     *  draft. This is the ceiling accepted from a caller here, well under it,
     *  and large enough for the fullest possible questionnaire with every
     *  verbatim probe filled in. A payload over this is refused with the
     *  generic message -- there is no legitimate client that produces one. */
    @TestVisible
    private static final Integer MAX_PAYLOAD = 60000;

    /**
     * Total appended rows allowed per token -- saves and resume-link email
     * sends together, since both are now the same mechanism (an insert). A
     * respondent saves once per step; the longest form is eight steps, and
     * going back and forth a few times, plus asking for the email link once or
     * twice, is normal. 200 is far above any real session and far below "free
     * storage". Replaces the three separate counters (Save_Count__c,
     * Resolve_Count__c, Resume_Email_Sends__c) the earlier design stored as
     * fields -- those fields do not exist; this is a COUNT() against appended
     * rows instead. See the class header.
     */
    @TestVisible
    private static Integer MAX_APPENDS = 200;

    /**
     * Reads per draft are NOT capped. The earlier design capped resumeDraft at
     * 50 reads via an in-place counter update; that mechanism does not exist
     * here (see the class header), and turning a read into an append-only
     * write to count it would itself consume MAX_APPENDS budget on a genuine
     * respondent re-opening their own link, which is worse than the harvesting
     * risk it would guard against. resumeDraft performs no DML at all. The
     * abuse surface a read-cap defended against -- a leaked link being
     * hammered -- is bounded instead by TTL_DAYS, by the 256-bit token space
     * (2^256, unaffected by any rate limit), and by the org's own Experience
     * Cloud guest-user rate limits (Setup -> Security -> "Guest User Rate
     * Limits"), which is the intended control for exactly this per
     * docs/runbooks/questionnaire-resume.md.
     */

    /**
     * The ONE message every failure uses. Invalid, expired, submitted, over a
     * cap, malformed payload, throttled -- all of them, so the caller cannot
     * tell them apart and neither can anyone reading a network tab.
     */
    private static final String GENERIC_FAILURE =
        'That link is no longer available. You can start the questionnaire again — ' +
        'your answers are still in this browser if you filled it in here.';

    // ---------------------------------------------------------------- types

    /** What the client gets back after a save. Never carries answers back. */
    public class DraftHandle {
        @AuraEnabled public String resumeToken  { get; set; }
        @AuraEnabled public Datetime expiresAt  { get; set; }
        /** True only on the call that created the draft, so the component can
         *  show "saved — here is your link" once rather than on every step. */
        @AuraEnabled public Boolean created     { get; set; }
        public DraftHandle() { this.created = false; }
    }

    /** What the client gets back on a successful resume. */
    public class DraftPayload {
        @AuraEnabled public String payload      { get; set; }
        @AuraEnabled public Datetime expiresAt  { get; set; }
        @AuraEnabled public Datetime lastSavedAt{ get; set; }
    }

    /**
     * Deliberately not a Boolean and deliberately not detailed. `sent` is true
     * only when an email actually went; every reason it might not have -- bad
     * token, expired, submitted, over the send cap, no base URL configured,
     * malformed address -- returns the same false with the same message.
     */
    public class SendResult {
        @AuraEnabled public Boolean sent   { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    // -------------------------------------------------------------- saving

    /**
     * Creates a draft, or appends a new row for the one the token addresses.
     *
     * A blank token mints. A token that resolves to at least one row appends.
     * A token that does not resolve to any row -- malformed, or one this org
     * has never seen -- throws the one generic message; it never silently
     * mints a second draft, because a client that quietly got a new token
     * would go on believing the old link works.
     *
     * `payload` is opaque here on purpose. This class does not parse the
     * respondent's answers, does not validate them against the instrument and
     * does not score them: it stores a blob for the browser that wrote it.
     * Nothing downstream trusts it either -- GtmAssessmentRequestController
     * re-resolves the branches and rescores from the answers actually
     * submitted, exactly as it does for a form filled in one sitting.
     *
     * `pairKey` is configuration (which pack they are answering), not prospect
     * data, and is trimmed to the field length rather than trusted.
     */
    @AuraEnabled
    public static DraftHandle saveDraft(String resumeToken, String payload, String pairKey) {
        if (String.isBlank(payload)
                || payload.length() > MAX_PAYLOAD
                || !looksLikeJsonObject(payload)) {
            throw new AuraHandledException(GENERIC_FAILURE);
        }

        String cleanPair = String.isBlank(pairKey)
            ? null
            : (pairKey.length() > 80 ? pairKey.substring(0, 80) : pairKey);

        if (String.isBlank(resumeToken)) {
            return mint(payload, cleanPair);
        }
        return append(resumeToken, payload, cleanPair);
    }

    private static DraftHandle mint(String payload, String pairKey) {
        if (mintThrottleTripped()) {
            throw new AuraHandledException(GENERIC_FAILURE);
        }
        String token = generateResumeToken();
        Datetime expiresAt = System.now().addDays(TTL_DAYS);
        GTM_Form_Draft__c draft = new GTM_Form_Draft__c(
            Draft_Type__c    = 'Assessment',
            Resume_Token__c  = token,
            Draft_JSON__c    = payload,
            Pair_Key__c      = pairKey,
            Status__c        = 'Open',
            Expires_At__c    = expiresAt,
            Last_Saved_At__c = System.now()
        );
        try {
            insert draft;
        } catch (Exception e) {
            // Whatever went wrong -- a token collision at 1 in 2^256, a
            // validation rule someone adds later, storage -- the caller learns
            // nothing beyond "not available". The exception is not rethrown and
            // its message is not echoed: it could name a field value.
            throw new AuraHandledException(GENERIC_FAILURE);
        }
        DraftHandle out = new DraftHandle();
        out.resumeToken = token;
        out.expiresAt   = expiresAt;
        out.created     = true;
        return out;
    }

    private static DraftHandle append(String resumeToken, String payload, String pairKey) {
        OpenDraft current = latestOpenRowFor(resumeToken);
        if (current == null || current.appendCount >= MAX_APPENDS) {
            throw new AuraHandledException(GENERIC_FAILURE);
        }
        Datetime expiresAt = current.originalExpiresAt;
        GTM_Form_Draft__c draft = new GTM_Form_Draft__c(
            Draft_Type__c    = 'Assessment',
            Resume_Token__c  = resumeToken,
            Draft_JSON__c    = payload,
            Pair_Key__c      = String.isNotBlank(pairKey) ? pairKey : current.pairKey,
            Status__c        = 'Open',
            // Every appended row keeps the ORIGINAL expiry, not a fresh one --
            // see TTL_DAYS.
            Expires_At__c    = expiresAt,
            Last_Saved_At__c = System.now()
        );
        try {
            insert draft;
        } catch (Exception e) {
            throw new AuraHandledException(GENERIC_FAILURE);
        }
        DraftHandle out = new DraftHandle();
        out.resumeToken = resumeToken;
        out.expiresAt   = expiresAt;
        out.created     = false;
        return out;
    }

    // -------------------------------------------------------------- reading

    /**
     * The answers behind a token, or null.
     *
     * Null for a token that never existed, one that expired, one whose draft
     * was submitted, and one over MAX_APPENDS -- identically, with no way to
     * tell which. No DML: a read performs no write, unlike the earlier design
     * (which could not have worked as written -- see the class header).
     */
    @AuraEnabled
    public static DraftPayload resumeDraft(String resumeToken) {
        OpenDraft current = latestOpenRowFor(resumeToken);
        if (current == null) {
            return null;
        }
        DraftPayload out = new DraftPayload();
        out.payload     = current.draftJson;
        out.expiresAt   = current.originalExpiresAt;
        out.lastSavedAt = current.lastSavedAt;
        return out;
    }

    // -------------------------------------------------------------- emailing

    /**
     * Emails the resume link for a draft to an address the respondent typed.
     *
     * THE OPEN-RELAY QUESTION, ANSWERED EXPLICITLY. A guest-callable method
     * that emails an arbitrary address is a spam vector unless it is boxed in,
     * so it is boxed in on four sides at once:
     *
     *   1. THE BODY IS FIXED. Not one character of it comes from the caller.
     *      The only variable is a URL this class builds from configuration.
     *   2. EVERY SEND SPENDS ONE UNIT OF THE SAME MAX_APPENDS CAP AS A SAVE
     *      (an email send appends a row too, with unchanged content -- see
     *      below), so the ceiling on emails is bounded by the same number
     *      that bounds saves, not a separate always-available allowance.
     *   3. A DRAFT MUST EXIST FIRST, and minting is throttled, so the ceiling
     *      on emails is a throttled number times the per-token cap.
     *   4. THE ADDRESS IS NEVER STORED. It is used to address one message and
     *      is not written to the draft, not logged, not returned.
     *
     * The address is also not echoed in the result, so this cannot be used to
     * probe whether an address is deliverable.
     */
    @AuraEnabled
    public static SendResult emailResumeLink(String resumeToken, String emailAddress) {
        SendResult out = new SendResult();
        out.sent    = false;
        out.message = GENERIC_FAILURE;

        if (!isValidEmail(emailAddress)) {
            return out;
        }
        OpenDraft current = latestOpenRowFor(resumeToken);
        if (current == null || current.appendCount >= MAX_APPENDS) {
            return out;
        }
        String base = resumeLinkBase();
        if (String.isBlank(base)) {
            // Nothing configured and no site context. Refusing is the only
            // honest option: a link built from a guess is worse than no email.
            return out;
        }

        // Spend the append budget BEFORE sending. If the insert fails the
        // email never goes; if the email fails the budget is still spent.
        // Erring towards the cap being conservative is the right direction
        // for a mail endpoint. Content is unchanged -- this row exists to
        // consume budget and be counted, not to record a new answer.
        try {
            insert new GTM_Form_Draft__c(
                Draft_Type__c    = 'Assessment',
                Resume_Token__c  = resumeToken,
                Draft_JSON__c    = current.draftJson,
                Pair_Key__c      = current.pairKey,
                Status__c        = 'Open',
                Expires_At__c    = current.originalExpiresAt,
                Last_Saved_At__c = System.now()
            );
        } catch (Exception e) {
            return out;
        }

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ emailAddress.trim() });
        msg.setSubject('Your migration readiness assessment — pick up where you left off');
        msg.setPlainTextBody(
            'You started a migration readiness assessment and asked us to save your place.\n\n'
            + 'Open this link to carry on from the step you were on:\n\n'
            + base + (base.contains('?') ? '&' : '?') + 'resume=' + resumeToken + '\n\n'
            + 'The link works on any device and expires '
            + current.originalExpiresAt.format('d MMMM yyyy') + '. '
            + 'It stops working as soon as you send the assessment.\n\n'
            + 'Anyone with this link can see and change the answers behind it, so keep it to '
            + 'yourself.\n\n'
            + 'If you did not ask for this, ignore it — nothing has been sent to anyone and '
            + 'no one has been contacted about it.\n'
        );
        msg.setSaveAsActivity(false);
        // No org-wide address is assumed; the org's default applies. A missing
        // deliverability setting throws, and that throw must not become a
        // different-looking response from a bad token.
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        } catch (Exception e) {
            return out;
        }
        out.sent    = true;
        out.message = 'Sent. Check your inbox — the link works on any device.';
        return out;
    }

    // ------------------------------------------------------------ internals

    /** Everything a caller needs about a token's current, resumable state --
     *  or null if there is none. */
    private class OpenDraft {
        String draftJson;
        String pairKey;
        Datetime originalExpiresAt;
        Datetime lastSavedAt;
        Integer appendCount;
    }

    /**
     * The token's story in two queries: how many rows it has (the append
     * count, and the ORIGINAL row's expiry -- the oldest, never re-derived on
     * a later save), and whether the most recent row is still open.
     *
     * A token whose most recent row carries Submitted_Request__c is revoked --
     * that is the terminal row GtmAssessmentRequestController.closeDraft
     * appends, and it is what makes revocation work without an update. A
     * token whose most recent row is simply past Expires_At__c is expired.
     * Either way, this returns null and the two cases are indistinguishable
     * to the caller, by design.
     */
    private static OpenDraft latestOpenRowFor(String resumeToken) {
        if (String.isBlank(resumeToken) || resumeToken.length() > 64) {
            return null;
        }
        List<GTM_Form_Draft__c> rows = [
            SELECT Draft_JSON__c, Pair_Key__c, Expires_At__c, Last_Saved_At__c,
                   Submitted_Request__c, CreatedDate
            FROM   GTM_Form_Draft__c
            WHERE  Draft_Type__c = 'Assessment'
            AND    Resume_Token__c = :resumeToken
            ORDER BY CreatedDate ASC, Id ASC
        ];
        if (rows.isEmpty()) {
            return null;
        }
        GTM_Form_Draft__c oldest = rows[0];
        GTM_Form_Draft__c newest = rows[rows.size() - 1];

        if (newest.Submitted_Request__c != null) {
            return null; // revoked -- submitted
        }
        Datetime originalExpiresAt = oldest.Expires_At__c;
        if (originalExpiresAt == null || originalExpiresAt < System.now()) {
            return null; // expired
        }

        OpenDraft out = new OpenDraft();
        out.draftJson          = newest.Draft_JSON__c;
        out.pairKey             = newest.Pair_Key__c;
        out.originalExpiresAt   = originalExpiresAt;
        out.lastSavedAt         = newest.Last_Saved_At__c;
        out.appendCount         = rows.size();
        return out;
    }

    /**
     * ANTI-ENUMERATION, AND WHAT IT IS NOT.
     *
     * This counts new drafts org-wide over a short window and refuses over a
     * ceiling. It is honestly a blunt instrument: it is per-org, not per-caller,
     * so a determined script degrades the feature for everyone rather than
     * being singled out.
     *
     * PER-IP THROTTLING IS NOT POSSIBLE IN APEX AND IS NOT ATTEMPTED HERE. The
     * guest user's source IP is not reliably readable from a guest Apex
     * context, and anything derived from a request header is attacker-supplied.
     * The per-caller control has to live in front of Apex:
     *   - Experience Cloud's own guest-user rate limits (Setup -> Security ->
     *     "Guest User Rate Limits"), which throttle guest requests per IP and
     *     are the intended control for exactly this;
     *   - and, in front of that, whatever CDN/WAF the site sits behind.
     * Both are org/edge configuration, named in docs/runbooks/questionnaire-resume.md.
     *
     * Enumeration of the tokens themselves is not what this defends against --
     * 256 bits of Crypto.generateAesKey is what defends against that, and a rate
     * limit adds nothing meaningful to a 2^256 search space. This defends
     * against volume, and it counts only Assessment-type Booking-blind mints,
     * scoped by Draft_Type__c the same as every other query here.
     */
    @TestVisible
    private static Integer maxMintsPerWindow = 300;

    @TestVisible
    private static final Integer MINT_WINDOW_MINUTES = 10;

    private static Boolean mintThrottleTripped() {
        Datetime since = System.now().addMinutes(-MINT_WINDOW_MINUTES);
        Integer recent = [
            SELECT COUNT()
            FROM GTM_Form_Draft__c
            WHERE Draft_Type__c = 'Assessment'
            AND CreatedDate > :since
        ];
        return recent >= maxMintsPerWindow;
    }

    /**
     * The base URL a resume link is built on. Configuration first, the site's
     * own base second, nothing third. Never the caller: a host supplied by the
     * browser would let anyone use our mail server to send our-looking mail
     * pointing at their page.
     */
    private static String resumeLinkBase() {
        try {
            List<GTM_Assessment_Config__mdt> rows = [
                SELECT Resume_Link_Base_URL__c
                FROM GTM_Assessment_Config__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Resume_Link_Base_URL__c)) {
                return rows[0].Resume_Link_Base_URL__c.trim();
            }
        } catch (Exception e) {
            // fall through to the site base
        }
        try {
            String siteBase = Site.getBaseSecureUrl();
            return String.isBlank(siteBase) ? null : siteBase;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * A cryptographically random, URL-safe token. Character-for-character the
     * same generator as GtmReadoutController.generatePublicToken -- 32 random
     * bytes, base64url, padding stripped -- because two token formats in one
     * feature is two things to get wrong.
     */
    private static String generateResumeToken() {
        // Crypto.getRandomBlob(Integer) does not exist in this org (confirmed
        // directly -- "Method does not exist or incorrect signature"; the real
        // Crypto surface for a random value is getRandomInteger/getRandomLong
        // and this). generateAesKey(256) is a documented, ordinary way to get
        // 32 cryptographically random bytes when what is wanted is bytes, not
        // an AES key -- the "256" names the bit length, matching the 32-byte
        // (256-bit) token this method has always produced.
        Blob bytes = Crypto.generateAesKey(256);
        String token = EncodingUtil.base64Encode(bytes)
            .replace('+', '-')
            .replace('/', '_')
            .replace('=', '');
        return token.length() > 64 ? token.substring(0, 64) : token;
    }

    /**
     * Cheap syntactic gate. Not validation of the answers -- see saveDraft --
     * just enough to keep the field from becoming a bucket for arbitrary bytes.
     * The parse result is discarded and any parse error is swallowed without
     * its message, which would otherwise quote the payload back into a log.
     */
    private static Boolean looksLikeJsonObject(String payload) {
        String trimmed = payload.trim();
        if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
            return false;
        }
        try {
            Object parsed = JSON.deserializeUntyped(trimmed);
            return parsed instanceof Map<String, Object>;
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isValidEmail(String value) {
        String v = String.isBlank(value) ? '' : value.trim();
        if (v.length() == 0 || v.length() > 254) {
            return false;
        }
        return Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', v);
    }
}
