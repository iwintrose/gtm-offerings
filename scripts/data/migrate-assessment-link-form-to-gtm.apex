// D6 Stage 4 -- copies MA_Assessment_Request__c, MA_Link_Event__c, and
// MA_Form_Draft__c data onto the new GTM_-prefixed objects.
//
// None of these three objects have their own Id in any distributed guest
// URL (only MA_Saved_Configuration__c does -- Stage 5, not migrated yet).
// Their own Saved_Configuration__c lookups deliberately still point at the
// OLD MA_Saved_Configuration__c object (a Lookup, not a Master-Detail, so
// it can be repointed later as part of Stage 5 without recreating the
// field) -- so this migration copies that lookup's value unchanged.
//
// GTM_Link_Event__c.Assessment_Request__c DOES need remapping: it points
// at the new GTM_Assessment_Request__c (both migrate in this same stage),
// so each event's old Assessment_Request__c Id has to resolve through the
// old->new Id map built while migrating requests first.
//
// No natural external-id/unique key exists on either object (unlike
// Page_Content's Content_Address__c), so idempotency here is a simple
// "already has rows -- leave alone" guard per object, matching the
// pattern used for GTM_Page_Content_Version__c (also a no-natural-key
// child object) in Stage 3's script.
//
// Run via: sf apex run --file scripts/data/migrate-assessment-link-form-to-gtm.apex -o gtm-prod

Set<String> SYSTEM_FIELDS = new Set<String>{
    'id', 'name', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid',
    'systemmodstamp', 'ownerid', 'isdeleted', 'lastactivitydate',
    'lastvieweddate', 'lastreferenceddate'
};

Map<Id, Id> oldToNewRequestId = migrateAssessmentRequests();
System.debug('=== Assessment Requests migrated: ' + oldToNewRequestId.size() + ' ===');

Integer linkEventsMigrated = migrateLinkEvents(oldToNewRequestId);
System.debug('=== Link Events migrated: ' + linkEventsMigrated + ' ===');

Integer formDraftsMigrated = migrateFormDrafts();
System.debug('=== Form Drafts migrated: ' + formDraftsMigrated + ' ===');

Integer oldReqCount = Database.countQuery('SELECT COUNT() FROM MA_Assessment_Request__c');
Integer newReqCount = Database.countQuery('SELECT COUNT() FROM GTM_Assessment_Request__c');
Integer oldEvtCount = Database.countQuery('SELECT COUNT() FROM MA_Link_Event__c');
Integer newEvtCount = Database.countQuery('SELECT COUNT() FROM GTM_Link_Event__c');
Integer oldDraftCount = Database.countQuery('SELECT COUNT() FROM MA_Form_Draft__c');
Integer newDraftCount = Database.countQuery('SELECT COUNT() FROM GTM_Form_Draft__c');
System.debug('=== VERIFY: Request old=' + oldReqCount + ' new=' + newReqCount
    + ' | Event old=' + oldEvtCount + ' new=' + newEvtCount
    + ' | Draft old=' + oldDraftCount + ' new=' + newDraftCount + ' ===');

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

// Returns old Id -> new Id, for every row (whether just-migrated or
// already-migrated on a re-run), so migrateLinkEvents can always resolve
// against it regardless of whether this is a first run or a retry.
Map<Id, Id> migrateAssessmentRequests() {
    Map<Id, Id> oldToNew = new Map<Id, Id>();
    Integer existingNew = Database.countQuery('SELECT COUNT() FROM GTM_Assessment_Request__c');
    if (existingNew > 0) {
        System.debug('GTM_Assessment_Request__c already has rows -- skipping copy, but still building the old->new map from Saved_Configuration__c (the one field that uniquely identifies which old row a new one came from, since neither object has a request-specific external id)');
        return mapExistingRequests();
    }

    List<String> fields = fieldsToCopy('MA_Assessment_Request__c');
    List<SObject> oldRows = Database.query('SELECT Id, ' + String.join(fields, ', ') + ' FROM MA_Assessment_Request__c');

    List<SObject> toInsert = new List<SObject>();
    List<Id> oldIdsInOrder = new List<Id>();
    for (SObject oldRow : oldRows) {
        SObject newRow = Schema.getGlobalDescribe().get('GTM_Assessment_Request__c').newSObject();
        for (String f : fields) {
            newRow.put(f, oldRow.get(f));
        }
        toInsert.add(newRow);
        oldIdsInOrder.add((Id) oldRow.get('Id'));
    }
    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
    for (Integer i = 0; i < toInsert.size(); i++) {
        oldToNew.put(oldIdsInOrder[i], toInsert[i].Id);
    }
    return oldToNew;
}

// Re-run path only: match old and new Assessment Request rows by their
// Saved_Configuration__c value, which is unique per request in practice
// (one request per engagement link) even though it isn't a formal unique
// key on the object.
Map<Id, Id> mapExistingRequests() {
    Map<Id, Id> oldToNew = new Map<Id, Id>();
    Map<Id, Id> configToOldReq = new Map<Id, Id>();
    for (SObject r : Database.query('SELECT Id, Saved_Configuration__c FROM MA_Assessment_Request__c WHERE Saved_Configuration__c != null')) {
        configToOldReq.put((Id) r.get('Saved_Configuration__c'), (Id) r.get('Id'));
    }
    for (SObject r : Database.query('SELECT Id, Saved_Configuration__c FROM GTM_Assessment_Request__c WHERE Saved_Configuration__c != null')) {
        Id configId = (Id) r.get('Saved_Configuration__c');
        if (configToOldReq.containsKey(configId)) {
            oldToNew.put(configToOldReq.get(configId), (Id) r.get('Id'));
        }
    }
    return oldToNew;
}

Integer migrateLinkEvents(Map<Id, Id> oldToNewRequestId) {
    Integer existingNew = Database.countQuery('SELECT COUNT() FROM GTM_Link_Event__c');
    if (existingNew > 0) {
        System.debug('GTM_Link_Event__c already has rows -- skipping (re-run safety)');
        return 0;
    }

    List<String> fields = fieldsToCopy('MA_Link_Event__c');
    List<SObject> oldRows = Database.query('SELECT ' + String.join(fields, ', ') + ' FROM MA_Link_Event__c');

    List<SObject> toInsert = new List<SObject>();
    for (SObject oldRow : oldRows) {
        SObject newRow = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        for (String f : fields) {
            if (f == 'Assessment_Request__c') continue; // remapped below
            newRow.put(f, oldRow.get(f));
        }
        Id oldReqId = (Id) oldRow.get('Assessment_Request__c');
        if (oldReqId != null && oldToNewRequestId.containsKey(oldReqId)) {
            newRow.put('Assessment_Request__c', oldToNewRequestId.get(oldReqId));
        }
        toInsert.add(newRow);
    }
    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
    return toInsert.size();
}

Integer migrateFormDrafts() {
    Integer existingNew = Database.countQuery('SELECT COUNT() FROM GTM_Form_Draft__c');
    if (existingNew > 0) {
        System.debug('GTM_Form_Draft__c already has rows -- skipping (re-run safety)');
        return 0;
    }

    List<String> fields = fieldsToCopy('MA_Form_Draft__c');
    List<SObject> oldRows = Database.query('SELECT ' + String.join(fields, ', ') + ' FROM MA_Form_Draft__c');

    List<SObject> toInsert = new List<SObject>();
    for (SObject oldRow : oldRows) {
        SObject newRow = Schema.getGlobalDescribe().get('GTM_Form_Draft__c').newSObject();
        for (String f : fields) {
            newRow.put(f, oldRow.get(f));
        }
        toInsert.add(newRow);
    }
    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
    return toInsert.size();
}
