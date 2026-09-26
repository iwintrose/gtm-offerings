/**
 * Curated, controller-driven rebuild of gtm-staging's Migration Accelerator
 * demo/seed data (issue demo-seed-integrity-rebuild).
 *
 * WHY THIS EXISTS. `python3 scripts/seed-synthetic-data.py --load` builds the
 * live `[DEMO] ...` Accounts/Contacts/Opportunities/GTM_Saved_Configuration__c/
 * GTM_Assessment_Request__c set from a raw `sf data import tree` plan -- it
 * never runs a single line of this app's own Apex, so none of the
 * validation/derivation/side-effect logic a real rep's click would trigger
 * ever fires. That produced provable integrity bugs (Opportunities with
 * Offering_Key__c/Engagement_Link__c null, an Assessment Request whose
 * Contact__c didn't match its own linked config's Contact__c, zero Tasks for
 * twelve "submitted" requests). Full audit: docs/agent-artifacts/
 * task-scope-demo-seed-integrity-rebuild.md.
 *
 * This script generalizes scripts/data/reset-accelerator-demo.apex's
 * already-proven methodology (real Apex entry points, real sequence, a
 * `dupOptions` raw insert ONLY for the one Account/Contact pair that has no
 * link yet to resolve them through) -- but substitutes
 * GtmSavedConfigurationController.createRepDirectAssessment() everywhere
 * that script used saveConfiguration(), and never calls
 * GtmStageActionsController.advanceStage() at all.
 *
 * WHY REP_DIRECT ONLY. migration-accelerator has zero Published
 * Template_Type__c = 'configurator' GTM_Page_Section__c rows -- the branded
 * Configurator chapters run 100% off gtmConfiguratorCopy.js's CHAPTER_DEFAULTS
 * hardcode. Seeding a Draft/Sent/In_Review/Assessment-stage link right now
 * would create a "prospect-facing seed record valid for a given Offering"
 * that isn't (requirement 7). Rep_Direct is the one currently-supported,
 * currently-real path that is NOT gated by that gap: gtmConfigurator.js's
 * isRepDirect branch renders the questionnaire directly and never reaches
 * CHAPTER_DEFAULTS at all. Full Draft/Sent/In_Review/Assessment variety is
 * deferred to a follow-up issue once issue #39's Configurator content ships
 * and is Published (see the scope doc's §7 Dependency).
 *
 * PRECONDITIONS -- run in this order:
 *   1. python3 scripts/seed-synthetic-data.py --teardown --dry-run -o gtm-staging
 *      (review), then
 *      python3 scripts/seed-synthetic-data.py --teardown -o gtm-staging \
 *        --i-understand-this-writes-to-org gtm-staging
 *      to remove the old, broken, loader-created [DEMO] set first -- this
 *      script does not delete anything itself.
 *   2. This script (step 0 below flips the real org-default notification
 *      setting through GtmNotificationSettingsController -- a genuine admin
 *      config step, not a workaround -- BEFORE any submitRequest() call, so
 *      Task-firing is live for every one of them).
 *
 * Run:  sf apex run --file scripts/data/rebuild-gtm-demo-seed.apex --target-org gtm-staging
 *
 * REAL OPERATIONAL SIDE EFFECT: submitRequest()'s own notify path
 * (GTM_Assessment_Config__mdt Default: Send_Email__c = true, Notify_Email__c
 * null) falls back to the link's own Notify_Email__c, which defaults to the
 * user running this script -- expect one real "Assessment request --
 * <Company>" email per converted client in that inbox. Expected, not a bug.
 */

// ─── 0. org-default notification setting -- genuine admin config, not a
//        seeding workaround. GtmNotificationSettingsController.getOrgDefaults()
//        currently defaults every checkbox to false because zero
//        GTM_Notification_Settings__c rows exist in gtm-staging; this is the
//        real, already-wired Task/bell-firing switch
//        GtmAssessmentRequestController.postInsertBestEffort reads before
//        every submitRequest() call below. ─────────────────────────────────
GtmNotificationSettingsController.NotificationSettingsDto notifSettings =
    GtmNotificationSettingsController.getOrgDefaults();
notifSettings.notifyOnNewAssessmentRequest = true;
GtmNotificationSettingsController.setNotificationSettings(notifSettings);
System.debug('=== Notify_On_New_Assessment_Request__c is now true (org default) ===');

// ─── 1. the clients ──────────────────────────────────────────────────────
// One row per curated Account. Industry/stage/platform-pair/score inputs are
// deliberately varied per requirement 6 (curated variation, not volume) --
// five industries with real Published migration-accelerator Story variant
// content, four distinct Opportunity StageName values, two source/target
// platform pairs already proven against GTM_Migration_Pair__mdt by
// reset-accelerator-demo.apex, plus two more common ones. Exactly one client
// (Ironclad) never submits -- a real deal that has an assessment started but
// never finished is a normal state the Overview needs to show, not a bug to
// seed away (reset-accelerator-demo.apex's own comment, same spirit here).
public class ClientSpec {
    public String accountName;
    public String stdIndustry;      // standard Account.Industry picklist value
    public String industrySlug;     // GTM_Saved_Configuration__c.Industry__c -- matches a Published Story variant
    public String firstName;
    public String lastName;
    public String email;
    public String secondFirstName;  // null unless this account gets a 2nd contact
    public String secondLastName;
    public String secondEmail;
    public String sourcePlatform;
    public String targetPlatform;
    public Integer readiness;       // 1-4, GtmAssessmentScoring.DIMENSIONS value
    public Integer complexity;      // 1-3, GtmEstateComplexity.DIMENSIONS value
    public String targetStage;      // null for the non-converting client
    public Boolean converts;

    public ClientSpec(String accountName, String stdIndustry, String industrySlug,
            String firstName, String lastName, String email,
            String sourcePlatform, String targetPlatform,
            Integer readiness, Integer complexity, String targetStage, Boolean converts) {
        this.accountName = accountName;
        this.stdIndustry = stdIndustry;
        this.industrySlug = industrySlug;
        this.firstName = firstName;
        this.lastName = lastName;
        this.email = email;
        this.sourcePlatform = sourcePlatform;
        this.targetPlatform = targetPlatform;
        this.readiness = readiness;
        this.complexity = complexity;
        this.targetStage = targetStage;
        this.converts = converts;
    }
}

List<ClientSpec> spec = new List<ClientSpec>{
    new ClientSpec('[DEMO] Brightfield Financial Partners', 'Financial Services', 'financial-services',
        'Elena', 'Marsh', 'elena.marsh@brightfield-demo.invalid',
        'Marketo', 'Salesforce Marketing Cloud', 3, 2, 'Value Proposition', true),
    new ClientSpec('[DEMO] Cascade Regional Health', 'Healthcare', 'health',
        'Raj', 'Patel', 'raj.patel@cascade-demo.invalid',
        'Braze', 'Salesforce Marketing Cloud Next', 4, 1, 'Needs Analysis', true),
    new ClientSpec('[DEMO] Civic Works Authority', 'Government', 'public-sector',
        'Monica', 'Alvarez', 'monica.alvarez@civicworks-demo.invalid',
        'HubSpot', 'Salesforce Marketing Cloud', 2, 3, 'Prospecting', true),
    new ClientSpec('[DEMO] Northwind Apparel Group', 'Retail', 'retail',
        'Tom', 'Reilly', 'tom.reilly@northwind-demo.invalid',
        'Eloqua', 'Salesforce Marketing Cloud', 4, 2, 'Closed Won', true),
    // Never converts: Rep_Direct record created, no submission, no
    // Opportunity, no GTM_Link_Event__c -- see the class header.
    new ClientSpec('[DEMO] Ironclad Freight & Logistics', 'Transportation', 'transportation-mobility',
        'Sarah', 'Kim', 'sarah.kim@ironclad-demo.invalid',
        null, null, null, null, null, false)
};
// Brightfield gets a second stakeholder to exercise the
// multi-contact-per-Opportunity path (ensureOpportunityContactRole) --
// added as a plain, standard OpportunityContactRole insert once the
// Opportunity exists below, same reasoning the scope doc gives for the
// StageName update: this is standard Salesforce relationship modeling, not
// app-specific business logic, so there is no bespoke GTM entry point for it.
spec[0].secondFirstName = 'David';
spec[0].secondLastName = 'Chen';
spec[0].secondEmail = 'david.chen@brightfield-demo.invalid';

// The exact Description-marker PREFIX scripts/seed-synthetic-data.py's
// orphan-sweep teardown step matches via String.startswith() (DESC_MARKERS in
// that file) -- kept byte-identical up to the marker itself so this data
// stays teardown-compatible even in the (should-never-happen) case a
// GTM_Saved_Configuration__c loses its Account__c/Opportunity__c linkage
// before a future teardown runs. The bracketed suffix is this script's own,
// honest correction of provenance for a human reading the record directly.
String ACCOUNT_MARKER = 'Synthetic demo account seeded by scripts/seed-synthetic-data.py'
    + ' [tagging-convention only -- this record was actually created by '
    + 'scripts/data/rebuild-gtm-demo-seed.apex through real Apex controller '
    + 'calls (createRepDirectAssessment/submitRequest), not the JSON-tree '
    + 'loader -- issue demo-seed-integrity-rebuild]. Safe to delete via '
    + '`python3 scripts/seed-synthetic-data.py --teardown`.';
String OPPORTUNITY_MARKER = 'Synthetic demo opportunity seeded by scripts/seed-synthetic-data.py'
    + ' [tagging-convention only -- this record was actually created by '
    + 'GtmAssessmentRequestController.submitRequest()\'s own ensureOpportunity(), '
    + 'invoked from scripts/data/rebuild-gtm-demo-seed.apex -- issue '
    + 'demo-seed-integrity-rebuild]. Safe to delete via '
    + '`python3 scripts/seed-synthetic-data.py --teardown`.';

Database.DMLOptions dupOptions = new Database.DMLOptions();
dupOptions.DuplicateRuleHeader.allowSave = true;

Map<String, Id> accountByName = new Map<String, Id>();
Map<String, Id> primaryContactByName = new Map<String, Id>();
Map<String, Id> configByName = new Map<String, Id>();
Set<Id> allConfigIds = new Set<Id>();
Set<Id> allRequestIds = new Set<Id>();
Map<String, Id> opportunityByName = new Map<String, Id>();
Map<String, Id> requestIdByAccountName = new Map<String, Id>();

// ─── 2. Accounts + Contacts -- the one legitimate raw-insert step, per
//        CLAUDE.md §6 (duplicate-rule bypass via DuplicateRuleHeader) and
//        requirement 8's own entry-point table: nothing else in this script
//        ever inserts an Account or Contact directly. ─────────────────────
for (ClientSpec c : spec) {
    Account acc = new Account(
        Name = c.accountName,
        Industry = c.stdIndustry,
        Description = ACCOUNT_MARKER
    );
    Database.insert(acc, dupOptions);
    accountByName.put(c.accountName, acc.Id);

    Contact con = new Contact(
        FirstName = c.firstName,
        LastName = c.lastName,
        Email = c.email,
        AccountId = acc.Id
    );
    Database.insert(con, dupOptions);
    primaryContactByName.put(c.accountName, con.Id);

    if (String.isNotBlank(c.secondEmail)) {
        Contact con2 = new Contact(
            FirstName = c.secondFirstName,
            LastName = c.secondLastName,
            Email = c.secondEmail,
            AccountId = acc.Id
        );
        Database.insert(con2, dupOptions);
    }
}

// ─── 3. Rep_Direct assessments -- GtmSavedConfigurationController.
//        createRepDirectAssessment(), the real entry point for every
//        migration-accelerator config this script creates. Never
//        saveConfiguration(): see the class header. ────────────────────────
for (ClientSpec c : spec) {
    GtmSavedConfigurationController.RepDirectInput input =
        new GtmSavedConfigurationController.RepDirectInput();
    input.contactId = primaryContactByName.get(c.accountName);
    input.accountId = accountByName.get(c.accountName);
    input.offering = GtmAssessmentFrames.MIGRATION_ACCELERATOR;

    Id configId = GtmSavedConfigurationController.createRepDirectAssessment(input);
    configByName.put(c.accountName, configId);
    allConfigIds.add(configId);

    // Industry__c isn't settable through RepDirectInput (createRepDirectAssessment's
    // own doc comment: "deliberately narrow"), so this is the one small
    // supplementary housekeeping update the scope doc calls out -- same
    // class of write as the Is_Synthetic__c stamp below, not a shortcut
    // around any business rule (Industry__c has no Apex validation gating
    // it, unlike Configurator chapter content).
    update new GTM_Saved_Configuration__c(
        Id = configId,
        Industry__c = c.industrySlug
    );
}

// ─── 4. Assessment submissions -- GtmAssessmentRequestController.
//        submitRequest(), for every client that converts. This is also what
//        creates each Opportunity for real (ensureOpportunity, keyed off the
//        Rep_Direct config having no Opportunity__c yet) -- Offering_Key__c
//        and Engagement_Link__c both get stamped by that method, never by
//        this script directly. ─────────────────────────────────────────────
for (ClientSpec c : spec) {
    if (!c.converts) {
        continue; // Ironclad: Rep_Direct record only, exactly as designed.
    }
    Id configId = configByName.get(c.accountName);

    List<GtmAssessmentRequestController.AnswerInput> answers =
        new List<GtmAssessmentRequestController.AnswerInput>();
    for (String dimension : GtmAssessmentScoring.DIMENSIONS) {
        GtmAssessmentRequestController.AnswerInput a = new GtmAssessmentRequestController.AnswerInput();
        a.dimension = dimension;
        a.value = c.readiness;
        answers.add(a);
    }
    List<GtmAssessmentRequestController.AnswerInput> complexityAnswers =
        new List<GtmAssessmentRequestController.AnswerInput>();
    for (String dimension : GtmEstateComplexity.DIMENSIONS) {
        GtmAssessmentRequestController.AnswerInput a = new GtmAssessmentRequestController.AnswerInput();
        a.dimension = dimension;
        a.value = c.complexity;
        complexityAnswers.add(a);
    }

    GtmAssessmentRequestController.RequestInput req = new GtmAssessmentRequestController.RequestInput();
    req.name = c.firstName + ' ' + c.lastName;
    req.email = c.email;
    req.company = c.accountName;
    req.currentPlatform = c.sourcePlatform;
    req.targetPlatform = c.targetPlatform;
    req.savedRecordId = configId;
    req.answers = answers;
    req.complexityAnswers = complexityAnswers;

    GtmAssessmentRequestController.RequestResult result = GtmAssessmentRequestController.submitRequest(req);
    if (!result.success) {
        throw new System.DmlException('submitRequest did not succeed for ' + c.accountName + ': ' + result.message);
    }
    allRequestIds.add((Id) result.assessmentRequestId);
    requestIdByAccountName.put(c.accountName, (Id) result.assessmentRequestId);
    Id opportunityId = (Id) result.opportunityId;
    opportunityByName.put(c.accountName, opportunityId);

    // Only log activity for a client that actually reached a real
    // submission -- a Rep_Direct record was never "visited" as a page the
    // way a branded link is, so there is nothing honest to log for the
    // non-converting client (see class header / scope doc §6).
    GtmLinkEventController.logEvent(
        configId, 'Form Submitted', 'demo-' + c.accountName.deleteWhitespace(),
        'assessment', result.assessmentRequestId
    );

    // Plain, standard Opportunity field updates -- StageName and Description
    // are ordinary CRM record management with no bespoke GTM Apex method of
    // their own (the scope doc's own reasoning for why this isn't a
    // requirement-8 violation: Opportunity stage management is standard
    // Salesforce functionality, not app-specific business logic). The
    // Opportunity itself was still only ever INSERTED by submitRequest's
    // ensureOpportunity() above -- this never creates one.
    update new Opportunity(
        Id = opportunityId,
        StageName = c.targetStage,
        Description = OPPORTUNITY_MARKER
    );

    // The second stakeholder (Brightfield only) -- standard
    // OpportunityContactRole insert, see the spec-building comment above.
    if (String.isNotBlank(c.secondEmail)) {
        List<Contact> second = [
            SELECT Id FROM Contact WHERE Email = :c.secondEmail LIMIT 1
        ];
        if (!second.isEmpty()) {
            insert new OpportunityContactRole(
                OpportunityId = opportunityId,
                ContactId = second[0].Id,
                Role = 'Influencer',
                IsPrimary = false
            );
        }
    }
}

// ─── 5. Is_Synthetic__c housekeeping -- stamped AFTER each real controller
//        call, never instead of one, on every one of the 4 custom objects
//        this script touches (GTM_Saved_Configuration__c,
//        GTM_Assessment_Request__c, GTM_Readout__c, GTM_Link_Event__c),
//        exactly the tagging contract seed-synthetic-data.py --teardown
//        already relies on. Bulk, in one pass, rather than per-record
//        inside the loops above. ────────────────────────────────────────
List<SObject> synthTagUpdates = new List<SObject>();
for (Id configId : allConfigIds) {
    synthTagUpdates.add(new GTM_Saved_Configuration__c(Id = configId, Is_Synthetic__c = true));
}
for (Id requestId : allRequestIds) {
    synthTagUpdates.add(new GTM_Assessment_Request__c(Id = requestId, Is_Synthetic__c = true));
}
Map<Id, Id> readoutIdByRequestId = new Map<Id, Id>();
for (GTM_Readout__c r : [
    SELECT Id, Assessment_Request__c FROM GTM_Readout__c WHERE Assessment_Request__c IN :allRequestIds
]) {
    readoutIdByRequestId.put(r.Assessment_Request__c, r.Id);
    synthTagUpdates.add(new GTM_Readout__c(Id = r.Id, Is_Synthetic__c = true));
}
List<GTM_Link_Event__c> events = allConfigIds.isEmpty() ? new List<GTM_Link_Event__c>() : [
    SELECT Id FROM GTM_Link_Event__c WHERE Saved_Configuration__c IN :allConfigIds
];
for (GTM_Link_Event__c e : events) {
    synthTagUpdates.add(new GTM_Link_Event__c(Id = e.Id, Is_Synthetic__c = true));
}
if (!synthTagUpdates.isEmpty()) {
    update synthTagUpdates;
}
System.debug('=== Is_Synthetic__c stamped on '
    + allConfigIds.size() + ' config(s), ' + allRequestIds.size() + ' request(s), '
    + readoutIdByRequestId.size() + ' readout(s), ' + events.size() + ' event(s) ===');

// ─── 6. One readout driven to Pending Approval for real -- the highest
//        state a script alone can reach (native Approval.process() approval
//        step cannot be scripted). Best-effort: a manager-less running user
//        makes Approval.process() reject the submission, which must not
//        fail this script -- the Draft readout it would have advanced from
//        already exists and is itself a valid seeded state. ──────────────
// Northwind is the Closed Won deal -- picking the readout for the
// furthest-along deal to move toward approval reads naturally.
Id northwindRequestId = requestIdByAccountName.get('[DEMO] Northwind Apparel Group');
if (northwindRequestId != null && readoutIdByRequestId.containsKey(northwindRequestId)) {
    try {
        GtmReadoutController.submitForApproval(readoutIdByRequestId.get(northwindRequestId));
        System.debug('=== Northwind readout submitted for approval (Pending Approval) ===');
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN,
            '=== Could not submit Northwind readout for approval (non-fatal, Draft stands): '
            + e.getTypeName() + ' -- ' + e.getMessage() + ' ===');
    }
}

// ─── 7. what came out ────────────────────────────────────────────────────
System.debug('=== rebuilt ===');
for (GTM_Saved_Configuration__c l : [
    SELECT Name, Account__r.Name, Contact__r.Name, Industry__c, Presentation_Stage__c,
           Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName, Opportunity__r.Offering_Key__c,
           Opportunity__r.Engagement_Link__c
    FROM GTM_Saved_Configuration__c WHERE Id IN :allConfigIds
    ORDER BY Account__r.Name
]) {
    System.debug(l.Account__r.Name + ' (' + l.Industry__c + ') -- ' + l.Presentation_Stage__c);
    System.debug('    contact : ' + l.Contact__r.Name);
    if (l.Opportunity__c != null) {
        System.debug('    deal    : ' + l.Opportunity__r.Name + ' [' + l.Opportunity__r.StageName + ']'
            + ' offeringKey=' + l.Opportunity__r.Offering_Key__c
            + ' engagementLink=' + l.Opportunity__r.Engagement_Link__c);
    } else {
        System.debug('    deal    : none (no submitted assessment yet)');
    }
}
System.debug('requests=' + allRequestIds.size() + ' configs=' + allConfigIds.size());
