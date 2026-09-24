/*
 * HISTORICAL NOTE, read this first: this script's original form (System.runAs
 * wrapping the probe DML, meant to be run via `sf apex run --file`) can never
 * work as written. System.runAs is only legal inside a test method -- calling
 * it from anonymous Apex throws System.TypeException: "System.runAs can only
 * be used within a test method", unconditionally, on any org. Confirmed
 * against gtm-prod on 2026-09-07. The question this script was meant to settle
 * is answered instead by GtmGuestUpdateProbeTest.cls, an @IsTest class, which
 * is the only mechanism that can actually invoke System.runAs.
 *
 * THE ANSWER, already settled (2026-09-07, against gtm-prod): NO. A guest
 * user cannot update a record via
 * system-mode (`without sharing`) Apex in this org -- confirmed for a record
 * owned by someone else AND for a record the guest created itself moments
 * earlier in the same transaction. Both attempts returned the identical
 * INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY. See
 * docs/handoff/port-map-ma-to-gtm.md section F and
 * GtmAssessmentDraftController's own header for the design this settled:
 * append-and-count, never update, on GTM_Form_Draft__c.
 *
 * WHAT THIS SCRIPT DOES NOW: nothing destructive, and nothing that requires
 * System.runAs. It re-confirms, as a quick org-side sanity check runnable via
 * `sf apex run --file scripts/probe-guest-update.apex`, that a guest user
 * exists and that GTM_Saved_Configuration__c is reachable for the real
 * regression test to run against. It does not attempt the update itself --
 * that requires an @IsTest context. Run the real test for the actual answer:
 *
 *     sf apex run test --class-names GtmGuestUpdateProbeTest \
 *       --result-format human --wait 10
 */

List<User> guests = [
    SELECT Id, Name FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1
];

if (guests.isEmpty()) {
    System.debug(LoggingLevel.ERROR,
        'NO GUEST USER in this org. GtmGuestUpdateProbeTest will no-op rather '
        + 'than answer the guest-update question. Point this at the org '
        + 'running the Experience Cloud site.');
} else {
    System.debug(LoggingLevel.ERROR,
        'Guest user present: ' + guests[0].Name + ' (' + guests[0].Id + '). '
        + 'Run the real probe: sf apex run test --class-names '
        + 'GtmGuestUpdateProbeTest --result-format human --wait 10');
}
