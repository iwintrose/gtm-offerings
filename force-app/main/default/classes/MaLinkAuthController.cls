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
public without sharing class MaLinkAuthController {

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
        if (String.isBlank(recordId) || !isValidLinkId(recordId)) return false;
        List<MA_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :recordId
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

        if (String.isBlank(recordId) || String.isBlank(password) || !isValidLinkId(recordId)) {
            return res;
        }
        List<MA_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Link_Password__c)) return res;

        Boolean success = rows[0].Link_Password__c.equals(password.trim());
        logAccess(recordId, success);
        if (!success) return res;

        res.matched = true;
        res.submissionToken = issueToken(recordId, rows[0].Link_Password__c);
        return res;
    }

    /**
     * Kept for backward compatibility and test coverage. The LWC uses
     * verifyAndIssueToken() instead.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean verifyPassword(String recordId, String password) {
        if (String.isBlank(recordId) || String.isBlank(password) || !isValidLinkId(recordId)) {
            return false;
        }
        List<MA_Saved_Configuration__c> rows = [
            SELECT Link_Password__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Link_Password__c)) return false;
        Boolean success = rows[0].Link_Password__c.equals(password.trim());
        logAccess(recordId, success);
        return success;
    }

    // ----------------------------------------------------------------- token

    /**
     * Builds a self-validating HMAC token.
     * Format: "<recordId>:<epochSeconds>:<hmacSHA256Hex>"
     * The HMAC secret is the stored password, which is never exposed to callers.
     */
    private static String issueToken(String recordId, String secret) {
        Long epoch = System.now().getTime() / 1000L;
        String payload = recordId + ':' + epoch;
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
        return payload + ':' + EncodingUtil.convertToHex(mac);
    }

    /**
     * Returns the window in seconds a token stays valid.
     * Exposed via @TestVisible so MaAssessmentRequestControllerTest can
     * generate tokens that haven't expired.
     */
    @TestVisible
    static Integer tokenWindowSeconds() { return TOKEN_WINDOW_SECONDS; }

    private static void logAccess(String recordId, Boolean success) {
        try {
            insert new Task(
                Subject = success
                    ? 'Engagement link accessed'
                    : 'Engagement link — access attempt failed',
                Status = 'Completed',
                Priority = 'Normal',
                WhatId = recordId,
                ActivityDate = Date.today()
            );
        } catch (Exception e) {
            // Task logging is best-effort; the access result is not affected.
        }
    }

    private static Boolean isValidLinkId(String value) {
        try {
            Id candidate = (Id) value;
            return candidate.getSObjectType() == MA_Saved_Configuration__c.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }
}
