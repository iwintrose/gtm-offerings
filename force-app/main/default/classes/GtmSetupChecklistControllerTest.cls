/**
 * Hermetic tests for GtmSetupChecklistController: no SeeAllData, no Migration
 * Accelerator data, every record created here uses unique keys. Org state the
 * test cannot control (existing offerings, Network, scheduled jobs) is handled
 * with before/after comparison or by asserting a valid status set.
 */
@IsTest
private class GtmSetupChecklistControllerTest {

    private static final Set<String> VALID_TIERS = new Set<String>{'REQUIRED', 'RECOMMENDED', 'OPTIONAL', 'INFO'};
    private static final Set<String> VALID_STATUSES = new Set<String>{'DONE', 'TODO', 'NOT_SET', 'BLOCKED', 'UNKNOWN', 'INFO'};
    private static final List<String> ALWAYS_KEYS = new List<String>{
        'admin_assigned', 'reps_assigned', 'guest_permset', 'site_active', 'framework_pages',
        'industry_added', 'offering_created', 'offering_published', 'offering_listed',
        'triage_queue', 'scheduled_jobs', 'site_members', 'page_offerings', 'page_faq_bd',
        'page_faq_cm', 'page_assistant', 'analytics_digest', 'ai_keys', 'approval_routing',
        'offering_pages', 'org_digital_experiences', 'org_my_domain', 'org_chatter', 'org_email'
    };

    private static Map<String, GtmSetupChecklistController.SetupItem> byKey(GtmSetupChecklistController.SetupChecklist c) {
        Map<String, GtmSetupChecklistController.SetupItem> m = new Map<String, GtmSetupChecklistController.SetupItem>();
        for (GtmSetupChecklistController.SetupItem i : c.items) {
            Assert.isFalse(m.containsKey(i.key), 'duplicate key ' + i.key);
            m.put(i.key, i);
        }
        return m;
    }

    private static void setApproval(Boolean selfApproval) {
        GTM_Readout_Approval_Settings__c s = GTM_Readout_Approval_Settings__c.getOrgDefaults();
        s.Self_Approval_Enabled__c = selfApproval;
        upsert s;
    }

    private static User newUser(String tag, String profileName, Boolean active) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        String uniq = tag + String.valueOf(Math.abs(Crypto.getRandomLong()));
        return new User(
            LastName = 'Gsetup' + uniq, Alias = uniq.left(8), Email = uniq + '@example.invalid',
            Username = uniq + '@gsetup.example.invalid', ProfileId = p.Id, IsActive = active,
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
    }

    private static void assign(Id userId, String setName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :setName LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
        }
    }

    private static void insertTile(String key, String status) {
        insert new GTM_Page_Section__c(
            Section_Address__c = key + '::offerings-listing::tile', Offering_Key__c = key,
            Template_Type__c = 'offerings-listing', Section_Key__c = 'tile', Label__c = 'Tile',
            Layout_Type__c = 'industry-tile', Width__c = 'standard', Sort_Order__c = 1,
            Active__c = true, Status__c = 'Published', Offering_Status__c = status);
    }

    private static void insertIndustry(String indKey, Boolean withLabel) {
        String sk = 'industry-' + indKey;
        insert new GTM_Page_Section__c(
            Section_Address__c = 'gtm::industry-chooser::' + sk, Offering_Key__c = 'gtm',
            Template_Type__c = 'industry-chooser', Section_Key__c = sk, Label__c = 'Ind',
            Layout_Type__c = 'industry-tile', Width__c = 'standard', Sort_Order__c = 99,
            Active__c = true, Status__c = 'Published');
        if (withLabel) {
            insert new GTM_Page_Content__c(
                Content_Address__c = 'gtm::industry-chooser::' + sk + '::industryLabel',
                Offering_Key__c = 'gtm', Template_Type__c = 'industry-chooser',
                Section_Key__c = sk, Field_Key__c = 'industryLabel', Field_Type__c = 'text',
                Text_Value__c = 'Gsetup Test Industry', Active__c = true, Status__c = 'Published');
        }
    }

    @IsTest
    static void blankOrgReturnsWholeCatalogueWithinBudget() {
        Test.startTest();
        Integer before = Limits.getQueries();
        GtmSetupChecklistController.SetupChecklist c = GtmSetupChecklistController.getChecklist();
        Integer used = Limits.getQueries() - before;
        Test.stopTest();

        Map<String, GtmSetupChecklistController.SetupItem> m = byKey(c);
        for (String k : ALWAYS_KEYS) {
            Assert.isTrue(m.containsKey(k), 'missing ' + k);
        }
        for (GtmSetupChecklistController.SetupItem i : c.items) {
            Assert.isTrue(VALID_TIERS.contains(i.tier), i.key);
            Assert.isTrue(VALID_STATUSES.contains(i.status), i.key + ' ' + i.status);
            Assert.isNotNull(i.blockedBy, i.key);
            Assert.isNotNull(i.humanMustAct, i.key);
            Assert.isNotNull(i.actionType, i.key);
            Assert.isNotNull(i.linkKind, i.key);
            Assert.isFalse(String.isBlank(i.why), i.key);
            Assert.areEqual(i.tier == 'OPTIONAL' || i.tier == 'INFO', i.collapsedByDefault, i.key);
        }
        Assert.areEqual(8, c.requiredTotal);
        Assert.isTrue(c.requiredDone >= 0 && c.requiredDone <= 8);
        Assert.isTrue(used <= 30, 'SOQL used: ' + used);
        Assert.isNotNull(c.checkedAt);
    }

    @IsTest
    static void optionalAndInfoRowsAreNeverCountedOrTodo() {
        GtmSetupChecklistController.SetupChecklist c = GtmSetupChecklistController.getChecklist();
        Integer required = 0;
        for (GtmSetupChecklistController.SetupItem i : c.items) {
            if (i.tier == 'REQUIRED') required++;
            if (i.tier == 'OPTIONAL' || i.tier == 'INFO') {
                Assert.areNotEqual('TODO', i.status, i.key);
                Assert.areNotEqual('BLOCKED', i.status, i.key);
            }
        }
        Assert.areEqual(c.requiredTotal, required);
        // Ordering: required rows first, then recommended, optional, info.
        Map<String, Integer> rank = new Map<String, Integer>{'REQUIRED' => 0, 'RECOMMENDED' => 1, 'OPTIONAL' => 2, 'INFO' => 3};
        Integer last = 0;
        for (GtmSetupChecklistController.SetupItem i : c.items) {
            Assert.isTrue(rank.get(i.tier) >= last, 'tier order at ' + i.key);
            last = rank.get(i.tier);
        }
    }

    @IsTest
    static void draftOfferingCreatesButDoesNotPublishThenPublishFlipsOnlyThatRow() {
        Map<String, GtmSetupChecklistController.SetupItem> before = byKey(GtmSetupChecklistController.getChecklist());

        insertTile('gsetup-draft-x', 'Draft');
        Map<String, GtmSetupChecklistController.SetupItem> drafted = byKey(GtmSetupChecklistController.getChecklist());
        Assert.areEqual('DONE', drafted.get('offering_created').status);
        if (before.get('offering_published').status != 'DONE') {
            Assert.areEqual('TODO', drafted.get('offering_published').status);
            Assert.isTrue(drafted.get('offering_published').detail.contains('draft'), drafted.get('offering_published').detail);
        }

        GTM_Page_Section__c tile = [SELECT Id FROM GTM_Page_Section__c WHERE Offering_Key__c = 'gsetup-draft-x' LIMIT 1];
        tile.Offering_Status__c = 'Published';
        update tile;
        Map<String, GtmSetupChecklistController.SetupItem> published = byKey(GtmSetupChecklistController.getChecklist());
        Assert.areEqual('DONE', published.get('offering_published').status);
        Assert.areEqual('DONE', published.get('offering_created').status);
        // Published but with no GTM_Offering__mdt record of our own key: never a false DONE from this test's data.
        Assert.isTrue(VALID_STATUSES.contains(published.get('offering_listed').status));
    }

    @IsTest
    static void archivedOfferingDoesNotCountAsPublished() {
        Map<String, GtmSetupChecklistController.SetupItem> before = byKey(GtmSetupChecklistController.getChecklist());
        insertTile('gsetup-arch-x', 'Published');
        GTM_Page_Section__c tile = [SELECT Id FROM GTM_Page_Section__c WHERE Offering_Key__c = 'gsetup-arch-x' LIMIT 1];
        tile.Archived__c = true;
        update tile;
        Map<String, GtmSetupChecklistController.SetupItem> after = byKey(GtmSetupChecklistController.getChecklist());
        if (before.get('offering_published').status != 'DONE') {
            Assert.areNotEqual('DONE', after.get('offering_published').status);
        }
    }

    @IsTest
    static void industryWithLabelIsDoneAndWithoutLabelIsNot() {
        Map<String, GtmSetupChecklistController.SetupItem> before = byKey(GtmSetupChecklistController.getChecklist());
        insertIndustry('gsetupnolabel', false);
        Map<String, GtmSetupChecklistController.SetupItem> unlabelled = byKey(GtmSetupChecklistController.getChecklist());
        if (before.get('industry_added').status != 'DONE') {
            Assert.areNotEqual('DONE', unlabelled.get('industry_added').status);
        }
        insertIndustry('gsetuplabel', true);
        Map<String, GtmSetupChecklistController.SetupItem> labelled = byKey(GtmSetupChecklistController.getChecklist());
        Assert.areEqual('DONE', labelled.get('industry_added').status);
    }

    @IsTest
    static void frameworkPagesDoneOnceAllFiveTemplatesHaveSections() {
        List<GTM_Page_Section__c> secs = new List<GTM_Page_Section__c>();
        for (String t : new List<String>{'offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager', 'assistant'}) {
            secs.add(new GTM_Page_Section__c(
                Section_Address__c = 'gtm::' + t + '::gsetup-probe', Offering_Key__c = 'gtm',
                Template_Type__c = t, Section_Key__c = 'gsetup-probe', Label__c = 'Probe',
                Layout_Type__c = 'industry-tile', Width__c = 'standard', Sort_Order__c = 98,
                Active__c = true, Status__c = 'Published'));
        }
        insert secs;
        GtmSetupChecklistController.SetupItem f = byKey(GtmSetupChecklistController.getChecklist()).get('framework_pages');
        Assert.areEqual('DONE', f.status);
        Assert.areEqual('NONE', f.actionType);
    }

    @IsTest
    static void frameworkPagesDetailListsMissingTemplateIdsLiterally() {
        GtmSetupChecklistController.SetupItem f = byKey(GtmSetupChecklistController.getChecklist()).get('framework_pages');
        if (f.status == 'TODO') {
            Assert.isTrue(f.detail.startsWith('Missing: '), f.detail);
            Assert.isFalse(f.detail.endsWith('.'), f.detail);
            Assert.areEqual('CREATE_FRAMEWORK_PAGES', f.actionType);
        }
        // Force exactly two missing templates by creating the other three.
        List<GTM_Page_Section__c> secs = new List<GTM_Page_Section__c>();
        for (String t : new List<String>{'offerings-page', 'faq-content-manager', 'assistant'}) {
            secs.add(new GTM_Page_Section__c(
                Section_Address__c = 'gtm::' + t + '::gsetup-probe2', Offering_Key__c = 'gtm',
                Template_Type__c = t, Section_Key__c = 'gsetup-probe2', Label__c = 'Probe',
                Layout_Type__c = 'industry-tile', Width__c = 'standard', Sort_Order__c = 97,
                Active__c = true, Status__c = 'Published'));
        }
        insert secs;
        GtmSetupChecklistController.SetupItem g = byKey(GtmSetupChecklistController.getChecklist()).get('framework_pages');
        if (g.status == 'TODO') {
            Assert.isTrue(g.detail.startsWith('Missing: '), g.detail);
            Assert.isTrue(g.detail.contains('industry-chooser') || g.detail.contains('faq-bd'), g.detail);
            Assert.isFalse(g.detail.contains('offerings-page'), g.detail);
        }
    }

    @IsTest
    static void managerRowShownOnlyInManagerApprovalMode() {
        setApproval(false);
        GtmSetupChecklistController.SetupChecklist disabled = GtmSetupChecklistController.getChecklist();
        Assert.isTrue(byKey(disabled).containsKey('manager_on_reps'));
        Assert.isFalse(disabled.selfApprovalEnabled);
        Assert.isTrue(byKey(disabled).get('approval_routing').detail.contains('Manager approval'));

        setApproval(true);
        GtmSetupChecklistController.SetupChecklist enabled = GtmSetupChecklistController.getChecklist();
        Assert.isFalse(byKey(enabled).containsKey('manager_on_reps'));
        Assert.isTrue(enabled.selfApprovalEnabled);
        Assert.areEqual('INFO', byKey(enabled).get('approval_routing').status);
    }

    @IsTest
    static void aiKeysRowNeverExposesKeyText() {
        GTM_Agent_Settings__c s = GTM_Agent_Settings__c.getOrgDefaults();
        s.Claude_API_Key__c = 'sk-gsetup-SECRET-VALUE-123';
        upsert s;
        GtmSetupChecklistController.SetupChecklist c = GtmSetupChecklistController.getChecklist();
        String json = JSON.serialize(c);
        Assert.isFalse(json.contains('SECRET-VALUE'), 'key text leaked');
        GtmSetupChecklistController.SetupItem k = byKey(c).get('ai_keys');
        Assert.areEqual('DONE', k.status);
        Assert.areEqual('OPTIONAL', k.tier);
    }

    @IsTest
    static void permissionSetAssignmentsAreDetected() {
        User u = newUser('rep', 'Standard User', true);
        System.runAs(new User(Id = UserInfo.getUserId())) { insert u; }
        assign(u.Id, 'GTM_Offering_User');
        assign(u.Id, 'GTM_Offering_Admin');
        assign(UserInfo.getUserId(), 'GTM_Content_Manager');

        Map<String, GtmSetupChecklistController.SetupItem> m = byKey(GtmSetupChecklistController.getChecklist());
        Assert.areEqual('DONE', m.get('admin_assigned').status);
        Assert.areEqual('DONE', m.get('reps_assigned').status);
        Assert.isFalse(m.containsKey('content_access'), 'helper row hidden once met');
    }

    @IsTest
    static void unassignedAdminOffersAssignToMeAction() {
        // Only meaningful when no active admin exists (a blank org); otherwise DONE.
        GtmSetupChecklistController.SetupItem a = byKey(GtmSetupChecklistController.getChecklist()).get('admin_assigned');
        if (a.status == 'TODO') {
            Assert.areEqual('ASSIGN_TO_ME', a.actionType);
            Assert.areEqual('GTM_Offering_Admin', a.permissionSetName);
        } else {
            Assert.areEqual('DONE', a.status);
            Assert.areEqual('NONE', a.actionType);
        }
    }

    @IsTest
    static void aFailingDetectorIsIsolatedToItsOwnRow() {
        GtmSetupChecklistController.forceFailKey = 'scheduled_jobs';
        GtmSetupChecklistController.SetupChecklist c = GtmSetupChecklistController.getChecklist();
        Map<String, GtmSetupChecklistController.SetupItem> m = byKey(c);
        Assert.areEqual('UNKNOWN', m.get('scheduled_jobs').status);
        Assert.areNotEqual('UNKNOWN', m.get('approval_routing').status);
        Assert.areNotEqual('UNKNOWN', m.get('framework_pages').status);

        GtmSetupChecklistController.forceFailKey = 'framework_pages';
        GtmSetupChecklistController.SetupChecklist c2 = GtmSetupChecklistController.getChecklist();
        Assert.areEqual('UNKNOWN', byKey(c2).get('framework_pages').status);
        Assert.isTrue(c2.requiredUnknown >= 1);
        Assert.areEqual(8, c2.requiredTotal);
    }

    @IsTest
    static void guestAndSiteRowsAreNeverFalselyDoneWithoutASite() {
        Map<String, GtmSetupChecklistController.SetupItem> m = byKey(GtmSetupChecklistController.getChecklist());
        for (String k : new List<String>{'guest_permset', 'site_active', 'site_members'}) {
            Assert.isTrue(VALID_STATUSES.contains(m.get(k).status), k);
            Assert.areNotEqual('ASSIGN_TO_ME', m.get(k).actionType, k);
            Assert.areNotEqual('ASSIGN_PICKER', m.get(k).actionType, k);
            // Status-consistent invariant (org-independent): a DONE row needs no action; any other row links out.
            Assert.isTrue(m.get(k).actionType == 'NONE' || m.get(k).actionType == 'LINK', k);
            if (m.get(k).status == 'DONE') {
                Assert.areEqual('NONE', m.get(k).actionType, k);
                Assert.areEqual('NONE', m.get(k).linkKind, k);
            } else {
                Assert.areEqual('LINK', m.get(k).actionType, k);
            }
        }
        if ([SELECT COUNT() FROM Network] == 0) {
            Assert.areNotEqual('DONE', m.get('guest_permset').status);
        }
    }

    @IsTest
    static void settingsSectionRowsCarryTheirSectionId() {
        Map<String, GtmSetupChecklistController.SetupItem> m = byKey(GtmSetupChecklistController.getChecklist());
        Assert.areEqual('analytics-notifications', m.get('analytics_digest').navState.get('sectionId'));
        Assert.areEqual('claude-gus', m.get('ai_keys').navState.get('sectionId'));
        Assert.areEqual('approval-routing', m.get('approval_routing').navState.get('sectionId'));
        Assert.areEqual('NAV_ITEM', m.get('page_faq_bd').linkKind);
        Assert.areEqual('faq-bd', m.get('page_faq_bd').navState.get('c__template'));
        Assert.areEqual('gtm', m.get('page_faq_bd').navState.get('c__offering'));
    }

    @IsTest
    static void noDetailContainsAnOrgIdOrUsername() {
        GtmSetupChecklistController.SetupChecklist c = GtmSetupChecklistController.getChecklist();
        Pattern orgId = Pattern.compile('00D[A-Za-z0-9]{12,15}');
        for (GtmSetupChecklistController.SetupItem i : c.items) {
            String text = String.valueOf(i.detail) + ' ' + String.valueOf(i.why);
            Assert.isFalse(orgId.matcher(text).find(), i.key);
            Assert.isFalse(text.contains(UserInfo.getUserName()), i.key);
        }
    }

    @IsTest
    static void searchAssignableUsersFiltersAndCaps() {
        User active = newUser('actv', 'Standard User', true);
        User inactive = newUser('inac', 'Standard User', false);
        System.runAs(new User(Id = UserInfo.getUserId())) { insert new List<User>{active, inactive}; }

        List<GtmSetupChecklistController.UserOption> hits = GtmSetupChecklistController.searchAssignableUsers(active.LastName);
        Assert.areEqual(1, hits.size());
        Assert.areEqual(active.Id, hits[0].userId);
        Assert.areEqual(0, GtmSetupChecklistController.searchAssignableUsers(inactive.LastName).size());

        // A non-Standard (Chatter Free) user is excluded, when the profile exists in this org.
        List<Profile> chatter = [SELECT Id FROM Profile WHERE Name = 'Chatter Free User' LIMIT 1];
        if (!chatter.isEmpty()) {
            User free = newUser('free', 'Chatter Free User', true);
            System.runAs(new User(Id = UserInfo.getUserId())) {
                try { insert free; } catch (DmlException e) { free = null; }
            }
            if (free != null && free.Id != null) {
                Assert.areEqual(0, GtmSetupChecklistController.searchAssignableUsers(free.LastName).size());
            }
        }
    }

    @IsTest
    static void searchAssignableUsersCapsAtTwentyFive() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String tag = 'Gscap' + String.valueOf(Math.abs(Crypto.getRandomLong())).left(6);
        List<User> users = new List<User>();
        for (Integer k = 0; k < 26; k++) {
            String uniq = tag + k;
            users.add(new User(
                LastName = tag + 'Name' + k, Alias = ('c' + k + tag).left(8), Email = uniq + '@example.invalid',
                Username = uniq + '@gsetup.example.invalid', ProfileId = p.Id, IsActive = true,
                TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
        }
        System.runAs(new User(Id = UserInfo.getUserId())) { insert users; }
        Assert.areEqual(25, GtmSetupChecklistController.searchAssignableUsers(tag).size());
        // Over-long and wildcard terms are tolerated.
        Assert.isNotNull(GtmSetupChecklistController.searchAssignableUsers('%'.repeat(200)));
        Assert.isNotNull(GtmSetupChecklistController.searchAssignableUsers(null));
    }
}
