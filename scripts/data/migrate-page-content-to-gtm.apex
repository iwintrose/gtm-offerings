// D6 Stage 3 -- copies MA_Page_Section__c and MA_Page_Content__c data onto
// the new GTM_-prefixed objects (schema mirrored field-for-field in the
// same commit). Neither object embeds a record Id in any distributed URL
// (see the D6 scope report in docs/backlog.md) -- these are internal CMS
// rows, so a hard cutover to a new object with new Ids is safe here in a
// way it is not for MA_Saved_Configuration__c.
//
// Idempotent by hand rather than by upsert-on-external-id: both new
// objects' address fields are marked externalId/unique, but their unique
// index was still building well past the point that normally takes
// (5+ minutes, several retries) -- a second instance of the same
// platform-side metadata-propagation slowness Stage 2 hit on CustomMetadata
// record deploys, this time on a plain custom object's external-id index.
// Since these objects start empty, a plain `insert` doesn't need that
// index at all (only upsert-by-field does) -- so this checks for an
// existing address first (a dynamic SOQL SELECT, unaffected by the index
// build) and only inserts rows that aren't there yet, which gives the same
// re-run safety without waiting on the stuck index.
//
// Sections copied first (no ordering dependency exists -- content
// attaches to a section by matching Section_Key__c/Offering_Key__c/
// Template_Type__c strings, not a lookup Id -- but it reads clearer this
// way). Field lists are built from describe rather than hand-typed, so a
// field this script's author forgot about still gets copied.
//
// Run via: sf apex run --file scripts/data/migrate-page-content-to-gtm.apex -o gtm-dev

Set<String> SYSTEM_FIELDS = new Set<String>{
    'id', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid',
    'systemmodstamp', 'ownerid', 'isdeleted', 'lastactivitydate',
    'lastvieweddate', 'lastreferenceddate'
};

List<String> sectionFields = fieldsToCopy('MA_Page_Section__c', true);
List<String> contentFields = fieldsToCopy('MA_Page_Content__c', false);

System.debug('=== Page_Section: ' + sectionFields.size() + ' fields, Page_Content: ' + contentFields.size() + ' fields ===');

Integer sectionsMigrated = migrateSections(sectionFields);
Integer contentMigrated = migrateContent(contentFields);

System.debug('=== Sections upserted: ' + sectionsMigrated + ' / Content upserted: ' + contentMigrated + ' ===');

Integer newSectionCount = Database.countQuery('SELECT COUNT() FROM GTM_Page_Section__c');
Integer newContentCount = Database.countQuery('SELECT COUNT() FROM GTM_Page_Content__c');
Integer oldSectionCount = Database.countQuery('SELECT COUNT() FROM MA_Page_Section__c');
Integer oldContentCount = Database.countQuery('SELECT COUNT() FROM MA_Page_Content__c');
System.debug('=== VERIFY: old Section=' + oldSectionCount + ' new Section=' + newSectionCount
    + ' | old Content=' + oldContentCount + ' new Content=' + newContentCount + ' ===');

// ------------------------------------------------------------------------

List<String> fieldsToCopy(String objApiName, Boolean includeName) {
    Map<String, Schema.SObjectField> fieldMap =
        Schema.getGlobalDescribe().get(objApiName).getDescribe().fields.getMap();
    List<String> out = new List<String>();
    for (String apiName : fieldMap.keySet()) {
        if (SYSTEM_FIELDS.contains(apiName)) continue;
        if (apiName == 'name' && !includeName) continue; // AutoNumber Name on Page_Content -- read-only
        Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
        if (!dfr.isCreateable() && apiName != 'name') continue;
        out.add(dfr.getName());
    }
    return out;
}

Integer migrateSections(List<String> fields) {
    String soql = 'SELECT ' + String.join(fields, ', ') + ' FROM MA_Page_Section__c';
    List<SObject> oldRows = Database.query(soql);

    Set<String> existingAddresses = new Set<String>();
    for (SObject s : Database.query('SELECT Section_Address__c FROM GTM_Page_Section__c')) {
        existingAddresses.add((String) s.get('Section_Address__c'));
    }

    List<GTM_Page_Section__c> toUpsert = new List<GTM_Page_Section__c>();
    for (SObject oldRow : oldRows) {
        String address = (String) oldRow.get('Section_Address__c');
        if (existingAddresses.contains(address)) continue; // leave a live edit alone on re-run
        GTM_Page_Section__c newRow = new GTM_Page_Section__c();
        for (String f : fields) {
            newRow.put(f, oldRow.get(f));
        }
        toUpsert.add(newRow);
    }
    if (!toUpsert.isEmpty()) {
        insert toUpsert;
    }
    return toUpsert.size();
}

Integer migrateContent(List<String> fields) {
    String soql = 'SELECT ' + String.join(fields, ', ') + ' FROM MA_Page_Content__c';
    List<SObject> oldRows = Database.query(soql);

    Set<String> existingAddresses = new Set<String>();
    for (SObject c : Database.query('SELECT Content_Address__c FROM GTM_Page_Content__c')) {
        existingAddresses.add((String) c.get('Content_Address__c'));
    }

    List<GTM_Page_Content__c> toUpsert = new List<GTM_Page_Content__c>();
    for (SObject oldRow : oldRows) {
        String address = (String) oldRow.get('Content_Address__c');
        if (existingAddresses.contains(address)) continue;
        GTM_Page_Content__c newRow = new GTM_Page_Content__c();
        for (String f : fields) {
            newRow.put(f, oldRow.get(f));
        }
        toUpsert.add(newRow);
    }
    if (!toUpsert.isEmpty()) {
        insert toUpsert;
    }
    return toUpsert.size();
}

// ------------------------------------------------------------------------
// Page Content Version -- Master-Detail to Page_Content, so it has to move
// in the same stage (a Master-Detail field can't point at two object types,
// and can't be repointed after creation). Content__c on the new object
// already points at GTM_Page_Content__c (created alongside it) -- so each
// version's new Content__c must resolve via the OLD content record's
// address, looked up in the just-built GTM_Page_Content__c set.
Integer versionsMigrated = migrateVersions();
System.debug('=== Versions upserted: ' + versionsMigrated + ' ===');
Integer oldVersionCount = Database.countQuery('SELECT COUNT() FROM MA_Page_Content_Version__c');
Integer newVersionCount = Database.countQuery('SELECT COUNT() FROM GTM_Page_Content_Version__c');
System.debug('=== VERIFY Version: old=' + oldVersionCount + ' new=' + newVersionCount + ' ===');

Integer migrateVersions() {
    Map<Id, String> oldContentIdToAddress = new Map<Id, String>();
    for (SObject c : Database.query('SELECT Id, Content_Address__c FROM MA_Page_Content__c')) {
        oldContentIdToAddress.put((Id) c.get('Id'), (String) c.get('Content_Address__c'));
    }
    Map<String, Id> addressToNewContentId = new Map<String, Id>();
    for (SObject c : Database.query('SELECT Id, Content_Address__c FROM GTM_Page_Content__c')) {
        addressToNewContentId.put((String) c.get('Content_Address__c'), (Id) c.get('Id'));
    }

    Integer existingNewVersions = Database.countQuery('SELECT COUNT() FROM GTM_Page_Content_Version__c');
    if (existingNewVersions > 0) {
        System.debug('GTM_Page_Content_Version__c already has rows -- skipping (re-run safety, no per-row key to match on for a Master-Detail child)');
        return 0;
    }

    List<String> versionFields = new List<String>{
        'Change_Summary__c', 'Snapshot__c', 'Version_Number__c', 'Content__c'
    };
    List<SObject> oldVersions = Database.query(
        'SELECT ' + String.join(versionFields, ', ') + ' FROM MA_Page_Content_Version__c'
    );

    List<SObject> toInsert = new List<SObject>();
    Integer skippedNoMatch = 0;
    for (SObject oldVer : oldVersions) {
        Id oldContentId = (Id) oldVer.get('Content__c');
        String address = oldContentIdToAddress.get(oldContentId);
        Id newContentId = address == null ? null : addressToNewContentId.get(address);
        if (newContentId == null) {
            skippedNoMatch++;
            continue;
        }
        SObject newVer = Schema.getGlobalDescribe().get('GTM_Page_Content_Version__c').newSObject();
        newVer.put('Change_Summary__c', oldVer.get('Change_Summary__c'));
        newVer.put('Snapshot__c', oldVer.get('Snapshot__c'));
        newVer.put('Version_Number__c', oldVer.get('Version_Number__c'));
        newVer.put('Content__c', newContentId);
        toInsert.add(newVer);
    }
    if (skippedNoMatch > 0) {
        System.debug('WARNING: ' + skippedNoMatch + ' version(s) skipped -- no matching new Content record found');
    }
    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
    return toInsert.size();
}
