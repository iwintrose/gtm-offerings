/**
 * Data migration: convert MA_Assessment_Request__c records that reference
 * a Lead (but no Contact) into Contact-backed records.
 *
 * For each affected AR:
 *   1. Pull the Lead's email.
 *   2. Find or create a Contact under the AR's Account with that email.
 *   3. Set Contact__c on the AR and clear Lead__c.
 *
 * Run once in the target org via Developer Console > Execute Anonymous.
 * Safe to re-run: already-migrated records (Contact__c != null) are skipped.
 */

List<MA_Assessment_Request__c> toMigrate = [
    SELECT Id, Lead__c, Account__c,
           Lead__r.FirstName, Lead__r.LastName, Lead__r.Email,
           Lead__r.Title
    FROM MA_Assessment_Request__c
    WHERE Lead__c != null
      AND Contact__c = null
];

if (toMigrate.isEmpty()) {
    System.debug('No records to migrate.');
    return;
}

System.debug('Migrating ' + toMigrate.size() + ' assessment request(s)...');

List<MA_Assessment_Request__c> toUpdate = new List<MA_Assessment_Request__c>();

for (MA_Assessment_Request__c ar : toMigrate) {
    String email = ar.Lead__r.Email;
    Id accountId = ar.Account__c;

    if (String.isBlank(email)) {
        System.debug('Skipping AR ' + ar.Id + ': Lead has no email.');
        continue;
    }

    // Find an existing Contact under this Account with the same email.
    // If no Account is set, match by email only (edge case).
    List<Contact> existing;
    if (accountId != null) {
        existing = [
            SELECT Id FROM Contact
            WHERE Email = :email AND AccountId = :accountId
            LIMIT 1
        ];
    } else {
        existing = [
            SELECT Id FROM Contact
            WHERE Email = :email
            LIMIT 1
        ];
    }

    Id contactId;
    if (!existing.isEmpty()) {
        contactId = existing[0].Id;
        System.debug('AR ' + ar.Id + ': reusing existing Contact ' + contactId);
    } else {
        // Create a Contact from the Lead data.
        // AllowSave = true lets the insert proceed when duplicate detection
        // rules would otherwise block it — this is a one-shot data migration
        // running under admin context, and we've already confirmed no existing
        // Contact matched above.
        Contact c = new Contact(
            FirstName = ar.Lead__r.FirstName,
            LastName  = String.isNotBlank(ar.Lead__r.LastName) ? ar.Lead__r.LastName : 'Unknown',
            Email     = email,
            AccountId = accountId,
            Title     = ar.Lead__r.Title
        );
        Database.DmlOptions opts = new Database.DmlOptions();
        opts.DuplicateRuleHeader.AllowSave = true;
        Database.insert(c, opts);
        contactId = c.Id;
        System.debug('AR ' + ar.Id + ': created new Contact ' + contactId);
    }

    toUpdate.add(new MA_Assessment_Request__c(
        Id         = ar.Id,
        Contact__c = contactId,
        Lead__c    = null
    ));
}

if (!toUpdate.isEmpty()) {
    update toUpdate;
    System.debug('Migration complete. Updated ' + toUpdate.size() + ' record(s).');
}
