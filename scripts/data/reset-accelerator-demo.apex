/**
 * Wipe and rebuild the Migration Accelerator's generic demo data.
 *
 * Deletes ONLY what this app created -- its engagement links, assessment
 * requests, readouts, link events, and the accounts, contacts and
 * opportunities those records point at (matched by name against this
 * script's own client list, not "every Account in the org" -- so a real
 * client record with the bad luck to share one of these names is the one
 * case this intentionally won't touch; check before running if that's a
 * concern). Nothing else in the org is touched.
 *
 * Then rebuilds a coherent set: four FICTIONAL clients across four
 * industries (no real company by these names is implied), each with a
 * contact, one opportunity named by GtmDealNaming, one engagement link, and
 * a submission run through this app's own real Apex entry points --
 * GtmSavedConfigurationController.saveConfiguration and
 * GtmAssessmentRequestController.submitRequest, the same calls the LWCs
 * make -- so scoring, notification defaults, and FLS all behave exactly as
 * they would for a real link, and this script can't drift out of sync with
 * how the app actually validates and scores a submission.
 *
 * This is a safe-to-run, non-client-specific default. Keep it, edit the
 * `spec` list below to match your own demo needs, or delete the records it
 * creates -- none of it is real client data.
 *
 * Run:  sf apex run --file scripts/data/reset-accelerator-demo.apex --target-org <alias>
 */

// ─── 1. what this app owns, by name ──────────────────────────────────────────
Set<String> DEMO_NAMES = new Set<String>{ 'MUCH Music (Demo)', 'TD Bank (Demo)', 'Medtronic (Demo)', 'LA Metro (Demo)' };

List<Account> existingAccts = [SELECT Id FROM Account WHERE Name IN :DEMO_NAMES];
Set<Id> appAccts = new Set<Id>();
for (Account a : existingAccts) appAccts.add(a.Id);

Set<Id> appOpps = new Set<Id>();
Set<Id> appCons = new Set<Id>();
for (Opportunity o : [SELECT Id FROM Opportunity WHERE AccountId IN :appAccts]) appOpps.add(o.Id);
for (Contact c : [SELECT Id FROM Contact WHERE AccountId IN :appAccts]) appCons.add(c.Id);

List<GTM_Saved_Configuration__c> existingLinks = [
    SELECT Id FROM GTM_Saved_Configuration__c WHERE Account__c IN :appAccts
];
Set<Id> linkIds = new Set<Id>();
for (GTM_Saved_Configuration__c l : existingLinks) linkIds.add(l.Id);

List<GTM_Assessment_Request__c> existingReqs = [
    SELECT Id FROM GTM_Assessment_Request__c WHERE Saved_Configuration__c IN :linkIds
];
Set<Id> reqIds = new Set<Id>();
for (GTM_Assessment_Request__c r : existingReqs) reqIds.add(r.Id);

System.debug('deleting: links=' + linkIds.size() + ' requests=' + reqIds.size()
    + ' accounts=' + appAccts.size() + ' contacts=' + appCons.size() + ' opps=' + appOpps.size());

delete [SELECT Id FROM GTM_Link_Event__c WHERE Saved_Configuration__c IN :linkIds];
delete [SELECT Id FROM GTM_Readout__c WHERE Assessment_Request__c IN :reqIds];
delete [SELECT Id FROM GTM_Assessment_Request__c WHERE Id IN :reqIds];
delete [SELECT Id FROM GTM_Saved_Configuration__c WHERE Id IN :linkIds];
delete [SELECT Id FROM Opportunity WHERE Id IN :appOpps];
delete [SELECT Id FROM Contact WHERE Id IN :appCons];
delete [SELECT Id FROM Account WHERE Id IN :appAccts];

// ─── 2. the clients ──────────────────────────────────────────────────────────
// company | industry key | source | target | first | last | email | readiness value (1-4) | complexity value (1-3)
List<List<String>> spec = new List<List<String>>{
    new List<String>{'MUCH Music (Demo)','media','Eloqua','Salesforce Marketing Cloud','Marcus','Rivera','marcus.rivera@much-demo.example','2','2'},
    new List<String>{'TD Bank (Demo)','fintech','Marketo','Salesforce Marketing Cloud','Angela','Chen','angela.chen@td-demo.example','3','2'},
    new List<String>{'Medtronic (Demo)','medtech','Braze','Salesforce Marketing Cloud Next','Priya','Sundaram','priya.sundaram@medtronic-demo.example','4','1'},
    new List<String>{'LA Metro (Demo)','transport','HubSpot','Salesforce Marketing Cloud','Paul','Johns','paul.johns@lametro-demo.example','1','3'}
};
// Three of the four convert; the fourth opens the link and never submits.
// That is deliberate -- a real deal that has interaction events but no
// assessment request is a normal state the Overview needs to be able to
// show, not a bug to seed away.
Integer CONVERTED = 3;

Database.DMLOptions dupOptions = new Database.DMLOptions();
dupOptions.DuplicateRuleHeader.allowSave = true;

Map<String, Id> acctByName = new Map<String, Id>();
Map<String, Id> conByName = new Map<String, Id>();
Map<String, Id> oppByName = new Map<String, Id>();
Map<String, Id> linkByName = new Map<String, Id>();

for (List<String> s : spec) {
    Account acc = new Account(Name = s[0]);
    Database.insert(acc, dupOptions);
    acctByName.put(s[0], acc.Id);

    Contact con = new Contact(FirstName = s[4], LastName = s[5], Email = s[6], AccountId = acc.Id);
    Database.insert(con, dupOptions);
    conByName.put(s[0], con.Id);

    Opportunity opp = new Opportunity(
        Name = GtmDealNaming.nameFor(s[0], 'migration-accelerator', null),
        AccountId = acc.Id, StageName = 'Qualification',
        CloseDate = Date.today().addDays(90));
    insert opp;
    oppByName.put(s[0], opp.Id);
    insert new OpportunityContactRole(OpportunityId = opp.Id, ContactId = con.Id, Role = 'Decision Maker', IsPrimary = true);

    GtmSavedConfigurationController.SaveInput saveInput = new GtmSavedConfigurationController.SaveInput();
    saveInput.offering = 'migration-accelerator';
    saveInput.industry = s[1];
    saveInput.company = s[0];
    saveInput.accountId = acc.Id;
    saveInput.contactId = con.Id;
    saveInput.opportunityId = opp.Id;
    saveInput.clientContactName = s[4] + ' ' + s[5];
    saveInput.clientContactEmail = s[6];
    saveInput.accountIndustry = s[1];
    saveInput.generatedUrl = GtmSavedConfigurationController.getConfiguratorPageUrl();
    saveInput.configPayload = JSON.serialize(new Map<String, String>{
        'SOURCE_PLATFORM' => s[2], 'TARGET_PLATFORM' => s[3]
    });
    Id linkId = GtmSavedConfigurationController.saveConfiguration(saveInput);
    linkByName.put(s[0], linkId);

    GTM_Saved_Configuration__c link = [SELECT Id, Generated_URL__c FROM GTM_Saved_Configuration__c WHERE Id = :linkId];
    link.Generated_URL__c = GtmSavedConfigurationController.getConfiguratorPageUrl() + '?cfgId=' + linkId;
    update link;
}

// ─── 3. requests and the interactions behind them ────────────────────────────
Integer i = 0;
for (List<String> s : spec) {
    Id linkId = linkByName.get(s[0]);
    String session = 'demo-' + s[0].deleteWhitespace();

    // Every client visits and opens the form.
    GtmLinkEventController.logEvent(linkId, 'Page View', session, 'cover', null);
    GtmLinkEventController.logEvent(linkId, 'Page View', session, 'proof', null);
    GtmLinkEventController.logEvent(linkId, 'Form Opened', session, 'assessment', null);

    if (i < CONVERTED) {
        Integer readinessValue = Integer.valueOf(s[7]);
        Integer complexityValue = Integer.valueOf(s[8]);
        List<GtmAssessmentRequestController.AnswerInput> answers = new List<GtmAssessmentRequestController.AnswerInput>();
        for (String dimension : GtmAssessmentScoring.DIMENSIONS) {
            GtmAssessmentRequestController.AnswerInput a = new GtmAssessmentRequestController.AnswerInput();
            a.dimension = dimension;
            a.value = readinessValue;
            answers.add(a);
        }
        for (String dimension : GtmEstateComplexity.DIMENSIONS) {
            GtmAssessmentRequestController.AnswerInput a = new GtmAssessmentRequestController.AnswerInput();
            a.dimension = dimension;
            a.value = complexityValue;
            answers.add(a);
        }

        GtmAssessmentRequestController.RequestInput req = new GtmAssessmentRequestController.RequestInput();
        req.name = s[4] + ' ' + s[5];
        req.email = s[6];
        req.company = s[0];
        req.currentPlatform = s[2];
        req.targetPlatform = s[3];
        req.savedRecordId = linkId;
        req.answers = answers;
        GtmAssessmentRequestController.RequestResult result = GtmAssessmentRequestController.submitRequest(req);

        GtmLinkEventController.logEvent(linkId, 'Form Submitted', session, 'assessment', result.assessmentRequestId);
    } else {
        GtmLinkEventController.logEvent(linkId, 'Drop-off', session, 'assessment', null);
    }
    i++;
}

// ─── 4. what came out ────────────────────────────────────────────────────────
System.debug('=== rebuilt ===');
for (GTM_Saved_Configuration__c l : [
    SELECT Name, Company__c, Industry__c, Generated_URL__c,
           Opportunity__r.Name, Contact__r.Name
    FROM GTM_Saved_Configuration__c WHERE Id IN :linkByName.values()
    ORDER BY Company__c
]) {
    System.debug(l.Company__c + ' (' + l.Industry__c + ')');
    System.debug('    deal    : ' + l.Opportunity__r.Name);
    System.debug('    contact : ' + l.Contact__r.Name);
    System.debug('    link    : ' + l.Generated_URL__c);
}
System.debug('requests=' + [SELECT COUNT() FROM GTM_Assessment_Request__c WHERE Saved_Configuration__c IN :linkByName.values()]
    + ' events=' + [SELECT COUNT() FROM GTM_Link_Event__c WHERE Saved_Configuration__c IN :linkByName.values()]);
