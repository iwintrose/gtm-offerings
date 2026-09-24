/**
 * Guest-accessible controller for password-gating shared engagement links.
 *
 * Runs `without sharing` so unauthenticated Experience Cloud visitors can
 * query the Link_Password__c field and log access tasks on the record.
 * The only data exposed is a boolean (does a password exist?) and whether
 * a supplied password matches — the plaintext password itself is never
 * returned to the caller.
 *
 * Token gate: verifyAndIssueToken() is the preferred method for the LWC to
 * call. On a correct password it emits a short-lived HMAC token that
 * submitRequest() requires for password-protected links, preventing an
 * unauthenticated caller from submitting directly to the Apex endpoint.
 * Token format: "<recordId>:<epochSeconds>:<hmacSHA256Hex>"
 * Secret: the stored Link_Password__c (never transmitted to the caller).
 * Validity window: 30 minutes (matches typical session length).
 */
public without sharing class GtmLinkAuthController {

    @TestVisible
    private static final Integer TOKEN_WINDOW_SECONDS = 1800; // 30 min

    /** Returned by verifyAndIssueToken — exposes only what the LWC needs. */
    public class VerifyResult {
        @AuraEnabled public Boolean matched    { get; set; }
        @AuraEnabled public String  submissionToken { get; set; }
    }

    /** Returns true when the engagement link record has a password set.
     *  Safe to call from a guest page — reveals nothing about the password
     *  itself, only whether one exists. */
    @AuraEnabled(cacheable=false)
    public static Boolean checkPasswordRequired(String recordId) {
        Id resolvedId = GtmLegacyConfigId.resolve(recordId);
        if (resolvedId == null) return false;
        List<GTM_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];
        return !rows.isEmpty() && String.isNotBlank(rows[0].Link_Password__c);
    }

    /**
     * Verifies the password AND, on success, issues a signed submission token.
     * The LWC calls this instead of verifyPassword() so it gets back both the
     * yes/no result and the token it must pass to submitRequest().
     */
    @AuraEnabled(cacheable=false)
    public static VerifyResult verifyAndIssueToken(String recordId, String password) {
        VerifyResult res = new VerifyResult();
        res.matched = false;
        res.submissionToken = null;

        if (String.isBlank(password)) return res;
        Id resolvedId = GtmLegacyConfigId.resolve(recordId);
        if (resolvedId == null) return res;

        List<GTM_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Link_Password__c)) return res;

        Boolean success = rows[0].Link_Password__c.equals(password.trim());
        logAccess(resolvedId, success);
        if (!success) return res;

        res.matched = true;
        // The token embeds the caller's own recordId string, unresolved --
        // GtmAssessmentRequestController.validateTokenIfRequired compares it
        // against the same savedRecordId the client resubmits verbatim later
        // in the flow, so both sides have to keep using whatever the client
        // is actually holding (legacy or current format), not the resolved
        // Id, or a legitimate legacy-link submission would fail that check.
        res.submissionToken = issueToken(recordId, rows[0].Link_Password__c);
        return res;
    }

    /**
     * Kept for backward compatibility and test coverage. The LWC uses
     * verifyAndIssueToken() instead.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean verifyPassword(String recordId, String password) {
        if (String.isBlank(password)) return false;
        Id resolvedId = GtmLegacyConfigId.resolve(recordId);
        if (resolvedId == null) return false;

        List<GTM_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Link_Password__c)) return false;
        Boolean success = rows[0].Link_Password__c.equals(password.trim());
        logAccess(resolvedId, success);
        return success;
    }

    /**
     * Validates a "preview" bypass token minted by
     * GtmSavedConfigurationController.saveConfiguration() for the creating
     * rep's own immediate "Preview the page" click.
     *
     * This is intentionally guest-callable: the caller is a page load on the
     * public site presenting a token in the URL, exactly like a returning
     * prospect's cached submissionToken -- the trust decision already
     * happened at mint time (saveConfiguration() is with sharing, not
     * guest-granted, so only an authenticated rep saving their own record
     * can ever cause a token to be minted). This method only ever confirms
     * a token already minted; it has no path to mint one itself.
     *
     * Reuses the same HMAC format/verification as the password-entry path
     * (see verifyAndIssueToken/issueToken above) and the same 30-minute
     * window, so a preview link left open behaves the same way an ordinary
     * submission token would once it goes stale.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean validatePreviewToken(String recordId, String token) {
        if (String.isBlank(token)) return false;
        Id resolvedId = GtmLegacyConfigId.resolve(recordId);
        if (resolvedId == null) return false;

        List<GTM_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Link_Password__c)) return false;

        return isTokenValid(recordId, token, rows[0].Link_Password__c);
    }

    // ----------------------------------------------------------------- token

    /**
     * Builds a self-validating HMAC token.
     * Format: "<recordId>:<epochSeconds>:<hmacSHA256Hex>"
     * The HMAC secret is the stored password, which is never exposed to callers.
     *
     * Package-visible (not private) so GtmSavedConfigurationController can
     * mint the same shape of token as a side effect of saveConfiguration()
     * setting Link_Password__c -- that is the ONLY other place allowed to
     * call this, since it is `with sharing` and never guest-granted, unlike
     * this class. Do not add a guest-callable method anywhere that mints a
     * token for an arbitrary recordId with no password check.
     */
    public static String issueToken(String recordId, String secret) {
        Long epoch = System.now().getTime() / 1000L;
        String payload = recordId + ':' + epoch;
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
        return payload + ':' + EncodingUtil.convertToHex(mac);
    }

    /**
     * Verifies a token of issueToken()'s format against the given secret,
     * within TOKEN_WINDOW_SECONDS. Shared by validatePreviewToken() here;
     * GtmAssessmentRequestController.validateTokenIfRequired() keeps its own
     * copy of this same check (see the comment there) since it is verifying
     * a token it never mints itself and has its own record-id-format
     * constraints to honor.
     */
    private static Boolean isTokenValid(String recordId, String token, String secret) {
        List<String> parts = token.split(':');
        if (parts.size() != 3) return false;

        String tokenRecordId = parts[0];
        Long tokenEpoch;
        try {
            tokenEpoch = Long.valueOf(parts[1]);
        } catch (Exception e) {
            return false;
        }
        String tokenHmac = parts[2];

        if (tokenRecordId != recordId) return false;

        Long nowEpoch = System.now().getTime() / 1000L;
        if (nowEpoch - tokenEpoch > TOKEN_WINDOW_SECONDS) return false;

        String payload = tokenRecordId + ':' + parts[1];
        Blob expected = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
        String expectedHex = EncodingUtil.convertToHex(expected);
        return constantTimeEqual(expectedHex, tokenHmac);
    }

    private static Boolean constantTimeEqual(String a, String b) {
        if (a == null || b == null || a.length() != b.length()) return false;
        Integer diff = 0;
        for (Integer i = 0; i < a.length(); i++) {
            diff |= a.charAt(i) ^ b.charAt(i);
        }
        return diff == 0;
    }


    private static void logAccess(Id recordId, Boolean success) {
        try {
            Task access = new Task(
                Subject = success
                    ? 'Engagement link accessed'
                    : 'Engagement link — access attempt failed',
                Status = 'Completed',
                Priority = 'Normal',
                WhatId = recordId,
                ActivityDate = Date.today()
            );
            if (recordId != null && recordId.getSObjectType() == GTM_Saved_Configuration__c.SObjectType) {
                GtmLinkOwnerStamp.stamp(new List<SObject>{ access }, GtmLinkOwnerStamp.ownerForLink(recordId));
            }
            insert access;
        } catch (Exception e) {
            // Task logging is best-effort; the access result is not affected.
        }
    }
}
