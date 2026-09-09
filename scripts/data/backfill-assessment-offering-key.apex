// ADR-0007 -- one-time backfill of GTM_Assessment_Request__c.Offering_Key__c.
//
// Every request row submitted before Offering_Key__c existed was, in practice,
// Migration Accelerator's: it is the only offering that has ever had an
// assessment instrument, so it is the only offering any of these rows could
// have been scored against. This is not a guess dressed up as a default -- it
// is the historical fact the ADR is built on.
//
// IDEMPOTENT. Only rows where the field is still blank are touched, so running
// it twice, or running it after Phase 2's Apex has already started populating
// the field on new rows, is a no-op rather than a second write.
//
// ADDITIVE ONLY. It sets one field. No score, tier, section-score blob,
// complexity value, instrument pair, answer or timestamp is recomputed or
// touched -- which is the data-preservation guarantee the whole change hangs
// on, and it is verified by diffing those fields before and after rather than
// by trusting this comment.
//
// Database.update(..., false) -- allOrNone false -- deliberately: one row
// failing a validation rule must not roll back the other twelve. Failures are
// printed rather than swallowed.
//
// Run via: sf apex run --file scripts/data/backfill-assessment-offering-key.apex -o gtm-dev

final String OFFERING_KEY = 'migration-accelerator';

List<GTM_Assessment_Request__c> toFix = [
    SELECT Id
    FROM GTM_Assessment_Request__c
    WHERE Offering_Key__c = null
];
System.debug('Backfilling ' + toFix.size() + ' request(s) to ' + OFFERING_KEY + '.');

for (GTM_Assessment_Request__c r : toFix) {
    r.Offering_Key__c = OFFERING_KEY;
}

if (!toFix.isEmpty()) {
    List<Database.SaveResult> results = Database.update(toFix, false);
    Integer ok = 0;
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            ok++;
            continue;
        }
        for (Database.Error e : results[i].getErrors()) {
            System.debug(LoggingLevel.ERROR,
                'FAILED ' + toFix[i].Id + ': ' + e.getStatusCode() + ' ' + e.getMessage());
        }
    }
    System.debug('Updated ' + ok + ' of ' + toFix.size() + '.');
}

// Verify in the same transaction rather than trusting the loop above.
System.debug('Remaining blank: ' + [
    SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Offering_Key__c = null
]);
