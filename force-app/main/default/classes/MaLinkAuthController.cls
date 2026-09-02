/**
 * Guest-accessible controller for password-gating shared engagement links.
 *
 * Runs `without sharing` so unauthenticated Experience Cloud visitors can
 * query the Link_Password__c field and log access tasks on the record.
 * The only data exposed is a boolean (does a password exist?) and whether
 * a supplied password matches — the plaintext password itself is never
 * returned to the caller.
 */
public without sharing class MaLinkAuthController {

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

    /** Returns true when `password` matches the record's stored password.
     *  Logs an Activity task on the record for both successful and failed
     *  attempts so the rep sees a full access history on the record's
     *  Activity timeline. */
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
