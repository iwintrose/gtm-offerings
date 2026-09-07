// D6 Stage 5 -- copies the 4 MA_Saved_Configuration__c rows onto the new
// GTM_Saved_Configuration__c object, stamping Legacy_Id__c with each row's
// old Id.
//
// This is the ONLY stage where the old Id has to keep working after
// cutover: all 4 rows are Active and carry externally-distributed guest
// URLs (?cfgId=<old id>) already sent to real prospects (MUCH Music, TD
// Bank, Medtronic, LA Metro). Salesforce Ids are permanently bound to
// their originating object, so the old Id can never resolve directly
// against the new record -- Legacy_Id__c plus GtmLegacyConfigId.resolve()
// is the redirect that lets every guest-facing entry point keep accepting
// the old Id transparently once the Apex/LWC rewiring (not this script)
// switches over to querying the new object.
//
// Every other Saved_Configuration__c lookup elsewhere in the schema
// (GTM_Assessment_Request__c.Saved_Configuration__c, GTM_Link_Event__c.
// Saved_Configuration__c, GTM_Form_Draft__c.Saved_Configuration__c) still
// points at the OLD MA_Saved_Configuration__c -- repointing those, like
// repointing GTM_Link_Event__c.Assessment_Request__c was in Stage 4, is
// part of the Apex/LWC rewiring pass, not this data copy.
//
// Run via: sf apex run --file scripts/data/migrate-saved-configuration-to-gtm.apex -o gtm-dev

Set<String> SYSTEM_FIELDS = new Set<String>{
    'id', 'name', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid',
    'systemmodstamp', 'ownerid', 'isdeleted', 'lastactivitydate',
    'lastvieweddate', 'lastreferenceddate'
};

Integer migrated = migrateSavedConfigurations();
System.debug('=== Saved Configurations migrated: ' + migrated + ' ===');

// Verification is intentionally best-effort and isolated in its own
// try/catch: an uncaught exception anywhere in an anonymous-Apex run
// rolls back the WHOLE transaction, including DML that already
// succeeded earlier in the same run -- Legacy_Id__c is a brand-new
// unique/external-id field, and querying it immediately after its own
// deploy can hit the same index-build propagation lag Content_Address__c/
// Section_Address__c hit in Stage 3. A verification failure here must
// never take the successful insert above down with it.
try {
    Integer oldCount = Database.countQuery('SELECT COUNT() FROM MA_Saved_Configuration__c');
    Integer newCount = Database.countQuery('SELECT COUNT() FROM GTM_Saved_Configuration__c');
    Integer newWithLegacyId = Database.countQuery(
        'SELECT COUNT() FROM GTM_Saved_Configuration__c WHERE Legacy_Id__c != null'
    );
    System.debug('=== VERIFY: old=' + oldCount + ' new=' + newCount
        + ' new-with-legacy-id=' + newWithLegacyId + ' ===');
} catch (Exception ex) {
    System.debug('=== VERIFY FAILED (likely index-build lag on Legacy_Id__c, '
        + 're-check separately): ' + ex.getMessage() + ' ===');
}

// ------------------------------------------------------------------------

List<String> fieldsToCopy(String objApiName) {
    Map<String, Schema.SObjectField> fieldMap =
        Schema.getGlobalDescribe().get(objApiName).getDescribe().fields.getMap();
    List<String> out = new List<String>();
    for (String apiName : fieldMap.keySet()) {
        if (SYSTEM_FIELDS.contains(apiName)) continue;
        Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
        if (!dfr.isCreateable()) continue;
        out.add(dfr.getName());
    }
    return out;
}

Integer migrateSavedConfigurations() {
    Integer existingNew = Database.countQuery('SELECT COUNT() FROM GTM_Saved_Configuration__c');
    if (existingNew > 0) {
        System.debug('GTM_Saved_Configuration__c already has rows -- skipping (re-run safety)');
        return 0;
    }

    List<String> fields = fieldsToCopy('MA_Saved_Configuration__c');
    List<SObject> oldRows = Database.query(
        'SELECT Id, OwnerId, ' + String.join(fields, ', ') + ' FROM MA_Saved_Configuration__c'
    );

    List<SObject> toInsert = new List<SObject>();
    for (SObject oldRow : oldRows) {
        SObject newRow = Schema.getGlobalDescribe().get('GTM_Saved_Configuration__c').newSObject();
        for (String f : fields) {
            newRow.put(f, oldRow.get(f));
        }
        newRow.put('Legacy_Id__c', String.valueOf(oldRow.get('Id')));
        // Private sharing model, and OwnerId identifies which rep owns this
        // engagement link (used for attribution elsewhere, e.g.
        // GtmAssessmentRequestController.resolveConfigContext) -- unlike the
        // system fields excluded above, this one has to survive the copy or
        // every migrated link silently reassigns to whoever runs this script.
        newRow.put('OwnerId', oldRow.get('OwnerId'));
        toInsert.add(newRow);
    }
    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
    return toInsert.size();
}
