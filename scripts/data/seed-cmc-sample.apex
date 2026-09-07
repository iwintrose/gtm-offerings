/**
 * Portable sample scenario: Commercial Metals Company (CMC), a fictional
 * BD-rep walkthrough of the full engagement-link -> assessment -> readout
 * flow, built entirely through this app's own public Apex entry points --
 * the same calls the LWCs make, not raw DML -- so it can never drift out of
 * sync with real validation, FLS, or scoring behavior the way a hand-rolled
 * insert can.
 *
 * This is a SAMPLE, not a real client relationship. cmc.com is a real
 * company; nothing here represents an actual engagement with them -- it is
 * a stand-in used to prove and demonstrate the app's own flow end to end.
 * Safe to keep, edit, or delete in any org this runs against.
 *
 * Idempotent: if an Account named "Commercial Metals Company (Sample)" already
 * exists, this prints its record Ids and exits rather than creating a
 * duplicate. Delete that Account (and Salesforce will cascade the Contact,
 * Opportunity, and this app's own records that point at it) to re-seed.
 *
 * Run:  sf apex run --file scripts/data/seed-cmc-sample.apex --target-org <alias>
 */

String ACCOUNT_NAME = 'Commercial Metals Company (Sample)';

List<Account> existing = [SELECT Id FROM Account WHERE Name = :ACCOUNT_NAME LIMIT 1];
if (!existing.isEmpty()) {
    Id acctId = existing[0].Id;
    List<GTM_Saved_Configuration__c> links = [
        SELECT Id, Generated_URL__c FROM GTM_Saved_Configuration__c WHERE Account__c = :acctId
    ];
    System.debug('=== CMC sample already present, not re-seeding ===');
    System.debug('ACCOUNT=' + acctId);
    for (GTM_Saved_Configuration__c l : links) {
        System.debug('LINK=' + l.Id + ' URL=' + l.Generated_URL__c);
    }
    System.debug('Delete the Account above (cascades Contact/Opportunity/this app\'s records) to re-seed.');
    return;
}

// ─── 1. the account, as a BD rep would enter it ──────────────────────────────
// Standard duplicate-detection rules (Account/Contact matching) are active in
// many orgs by default and will hard-fail this insert if a similarly-named
// record already exists -- expected here, since "Commercial Metals Company"
// is a real company name other sample/demo data may also reference. Allow
// the save explicitly rather than suppressing the rule org-wide.
Database.DMLOptions dupOptions = new Database.DMLOptions();
dupOptions.DuplicateRuleHeader.allowSave = true;

Account acc = new Account(
    Name = ACCOUNT_NAME,
    Industry = 'Manufacturing',
    Website = 'https://www.cmc.com/en-us'
);
Database.insert(acc, dupOptions);

Contact con = new Contact(
    FirstName = 'Jordan', LastName = 'Reyes',
    Email = 'jordan.reyes@cmc-sample.example',
    Title = 'VP, Marketing Operations',
    AccountId = acc.Id
);
Database.insert(con, dupOptions);

Opportunity opp = new Opportunity(
    Name = GtmDealNaming.nameFor(ACCOUNT_NAME, 'migration-accelerator', null),
    AccountId = acc.Id, StageName = 'Prospecting',
    CloseDate = Date.today().addDays(90)
);
insert opp;

// ─── 2. the engagement link, via the real save path ──────────────────────────
GtmSavedConfigurationController.SaveInput saveInput = new GtmSavedConfigurationController.SaveInput();
saveInput.offering = 'migration-accelerator';
saveInput.industry = 'fintech';
saveInput.company = ACCOUNT_NAME;
saveInput.website = 'https://www.cmc.com/en-us';
saveInput.accountId = acc.Id;
saveInput.contactId = con.Id;
saveInput.opportunityId = opp.Id;
saveInput.clientContactName = 'Jordan Reyes';
saveInput.clientContactEmail = con.Email;
saveInput.estimatedValue = '250000';
saveInput.linkPassword = 'CMC-Sample-2026';
saveInput.accountIndustry = 'fintech';
saveInput.generatedUrl = GtmSavedConfigurationController.getConfiguratorPageUrl();
saveInput.configPayload = JSON.serialize(new Map<String, String>{
    'SOURCE_PLATFORM' => 'Eloqua', 'TARGET_PLATFORM' => 'SFMC'
});
Id linkId = GtmSavedConfigurationController.saveConfiguration(saveInput);

GTM_Saved_Configuration__c link = [SELECT Id, Generated_URL__c FROM GTM_Saved_Configuration__c WHERE Id = :linkId];
link.Generated_URL__c = GtmSavedConfigurationController.getConfiguratorPageUrl() + '?cfgId=' + linkId;
update link;

// ─── 3. the recipient's submission, via the real guest path ──────────────────
// A mid-tier, "Prep Required"-ish answer set -- deliberately not maxed out,
// so the sample readout shows a realistic mix rather than a perfect score.
List<GtmAssessmentRequestController.AnswerInput> answers = new List<GtmAssessmentRequestController.AnswerInput>();
for (String dimension : GtmAssessmentScoring.DIMENSIONS) {
    GtmAssessmentRequestController.AnswerInput a = new GtmAssessmentRequestController.AnswerInput();
    a.dimension = dimension;
    a.value = 3;
    answers.add(a);
}
for (String dimension : GtmEstateComplexity.DIMENSIONS) {
    GtmAssessmentRequestController.AnswerInput a = new GtmAssessmentRequestController.AnswerInput();
    a.dimension = dimension;
    a.value = 2;
    answers.add(a);
}

// The link carries a password, so submitRequest requires a signed submission
// token -- the same gate a real guest hits after entering the password
// correctly (see GtmLinkAuthController.verifyAndIssueToken).
GtmLinkAuthController.VerifyResult auth =
    GtmLinkAuthController.verifyAndIssueToken(linkId, saveInput.linkPassword);
if (!auth.matched) {
    System.debug('FATAL: password verification failed against the link just created.');
    return;
}

GtmAssessmentRequestController.RequestInput req = new GtmAssessmentRequestController.RequestInput();
req.name = 'Jordan Reyes';
req.email = con.Email;
req.company = ACCOUNT_NAME;
req.role = 'VP Marketing Operations';
req.currentPlatform = 'Eloqua';
req.targetPlatform = 'SFMC';
req.environmentSize = '500k contacts';
req.timeline = 'Q1 2027';
req.context = 'Sample scenario: consolidating platforms post-acquisition, evaluating SFMC as the migration target.';
req.savedRecordId = linkId;
req.submissionToken = auth.submissionToken;
req.answers = answers;

GtmAssessmentRequestController.RequestResult result = GtmAssessmentRequestController.submitRequest(req);

// ─── 4. what came out ────────────────────────────────────────────────────────
System.debug('=== CMC sample seeded ===');
System.debug('ACCOUNT=' + acc.Id + ' CONTACT=' + con.Id + ' OPPORTUNITY=' + opp.Id);
System.debug('LINK=' + linkId + ' URL=' + link.Generated_URL__c + ' PASSWORD=' + saveInput.linkPassword);
System.debug('SUBMIT_RESULT=' + JSON.serialize(result));
if (result.assessmentRequestId != null) {
    GTM_Assessment_Request__c ar = [
        SELECT Assessment_Score__c, Assessment_Tier__c FROM GTM_Assessment_Request__c
        WHERE Id = :result.assessmentRequestId
    ];
    System.debug('ASSESSMENT_REQUEST=' + result.assessmentRequestId
        + ' score=' + ar.Assessment_Score__c + ' tier=' + ar.Assessment_Tier__c);
    List<GTM_Readout__c> readouts = [
        SELECT Id, Status__c FROM GTM_Readout__c WHERE Assessment_Request__c = :result.assessmentRequestId
    ];
    for (GTM_Readout__c r : readouts) {
        System.debug('READOUT=' + r.Id + ' status=' + r.Status__c);
    }
}
