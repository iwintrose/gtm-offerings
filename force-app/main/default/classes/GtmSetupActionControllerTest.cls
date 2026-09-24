@IsTest
private class GtmSetupActionControllerTest {

    private static User makeUser(String suffix, Boolean active) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String u = 'gsb' + suffix + Integer.valueOf(Math.random() * 1000000);
        return new User(
            Alias = 'gsb' + suffix.left(4), Email = u + '@example.com', Username = u + '@gsb.example.com',
            LastName = 'GsB' + suffix, ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            IsActive = active
        );
    }

    private static Integer assignmentCount(Id userId, String psName) {
        return [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name = :psName
        ];
    }

    private static void assertRejected(Id userId, String psName) {
        Boolean threw = false;
        try {
            GtmSetupActionController.assignPermissionSet(userId, psName);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected rejection for ' + psName);
        System.assertEquals(0, assignmentCount(userId, psName));
    }

    private static GtmPageSectionController.SectionSeed seed(String key) {
        GtmPageSectionController.SectionSeed s = new GtmPageSectionController.SectionSeed();
        s.sectionKey = key;
        s.label = key;
        s.layoutType = 'faq';
        GtmPageSectionController.FieldSeed f = new GtmPageSectionController.FieldSeed();
        f.fieldKey = 'body';
        f.fieldType = 'text';
        f.label = 'Body';
        s.fields = new List<GtmPageSectionController.FieldSeed>{ f };
        return s;
    }

    @IsTest
    static void assignsAllowListedSetsToOtherUserAndIsIdempotent() {
        User target = makeUser('a', true);
        insert target;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            for (String n : new List<String>{ 'GTM_Offering_User', 'GTM_Content_Manager' }) {
                if ([SELECT COUNT() FROM PermissionSet WHERE Name = :n AND IsOwnedByProfile = false] == 0) continue;
                GtmSetupActionController.AssignResult r1 = GtmSetupActionController.assignPermissionSet(target.Id, n);
                System.assertEquals(true, r1.assigned);
                System.assertEquals(false, r1.fallbackToSetup);
                GtmSetupActionController.AssignResult r2 = GtmSetupActionController.assignPermissionSet(target.Id, n);
                System.assertEquals(false, r2.assigned);
                System.assertEquals(1, assignmentCount(target.Id, n));
            }
        }
    }

    @IsTest
    static void adminTierSelfOnly() {
        User target = makeUser('b', true);
        insert target;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            assertRejected(target.Id, 'GTM_Offering_Admin');
            assertRejected(target.Id, 'GTM_Content_Admin');
            Boolean threw = false;
            try {
                GtmSetupActionController.assignPermissionSetToMe('GTM_Guest');
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw);
            Integer before = assignmentCount(UserInfo.getUserId(), 'GTM_Content_Admin');
            if (before == 0
                && [SELECT COUNT() FROM PermissionSet WHERE Name = 'GTM_Content_Admin' AND IsOwnedByProfile = false] > 0) {
                GtmSetupActionController.AssignResult r =
                    GtmSetupActionController.assignPermissionSetToMe('GTM_Content_Admin');
                System.assertEquals(true, r.assigned);
                System.assertEquals(1, assignmentCount(UserInfo.getUserId(), 'GTM_Content_Admin'));
            }
        }
    }

    @IsTest
    static void rejectsNonAllowListedNames() {
        User target = makeUser('c', true);
        insert target;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            for (String n : new List<String>{ 'GTM_Guest', 'Conduit_User', 'Invented_Set', null, '', '  ' }) {
                Boolean threw = false;
                try {
                    GtmSetupActionController.assignPermissionSet(target.Id, n);
                } catch (AuraHandledException e) {
                    threw = true;
                }
                System.assert(threw, 'Expected rejection for ' + n);
            }
            System.assertEquals(0, [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :target.Id AND PermissionSet.Name LIKE 'GTM_%']);
        }
    }

    @IsTest
    static void rejectsInactiveAndNullTargets() {
        User inactive = makeUser('d', false);
        insert inactive;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            assertRejected(inactive.Id, 'GTM_Offering_User');
            Boolean threw = false;
            try {
                GtmSetupActionController.assignPermissionSet(null, 'GTM_Offering_User');
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw);
        }
    }

    @IsTest
    static void platformFailureReturnsSetupFallbackNeverAssigned() {
        User target = makeUser('e', true);
        insert target;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            if ([SELECT COUNT() FROM PermissionSet WHERE Name = 'GTM_Offering_User' AND IsOwnedByProfile = false] == 0) return;
            GtmSetupActionController.forceAssignFailure = true;
            GtmSetupActionController.AssignResult r =
                GtmSetupActionController.assignPermissionSet(target.Id, 'GTM_Offering_User');
            System.assertNotEquals(true, r.assigned);
            System.assertEquals(true, r.fallbackToSetup);
            System.assertEquals(GtmSetupActionController.SETUP_PATH_PERMSETS, r.setupPath);
            System.assertEquals(0, assignmentCount(target.Id, 'GTM_Offering_User'));
        }
    }

    @IsTest
    static void frameworkPageRejectsBadTemplatesWithoutDml() {
        for (String t : new List<String>{ 'story', 'configurator', 'offerings-listing', null, '', 'nope' }) {
            Boolean threw = false;
            try {
                GtmSetupActionController.createFrameworkPage(t, new List<GtmPageSectionController.SectionSeed>{ seed('a') });
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw, 'Expected rejection for ' + t);
        }
        System.assertEquals(0, [SELECT COUNT() FROM GTM_Page_Section__c]);
    }

    @IsTest
    static void frameworkPageCreatesEmptyStructureAndIsIdempotent() {
        List<GtmPageSectionController.SectionSeed> seeds = new List<GtmPageSectionController.SectionSeed>{
            seed('intro'), seed('more')
        };
        GtmSetupActionController.FrameworkPageResult r1 =
            GtmSetupActionController.createFrameworkPage('faq-bd', seeds);
        System.assertEquals(true, r1.created);
        System.assertEquals(2, r1.sectionCount);
        System.assertEquals(2, [SELECT COUNT() FROM GTM_Page_Section__c WHERE Offering_Key__c = 'gtm' AND Template_Type__c = 'faq-bd']);

        GtmSetupActionController.FrameworkPageResult r2 =
            GtmSetupActionController.createFrameworkPage('faq-bd', seeds);
        System.assertEquals(false, r2.created);
        System.assertEquals(2, [SELECT COUNT() FROM GTM_Page_Section__c WHERE Template_Type__c = 'faq-bd']);
        System.assertEquals(2, [SELECT COUNT() FROM GTM_Page_Content__c WHERE Template_Type__c = 'faq-bd']);
        for (GTM_Page_Content__c c : [
            SELECT Text_Value__c FROM GTM_Page_Content__c WHERE Template_Type__c = 'faq-bd'
        ]) {
            System.assert(String.isBlank(c.Text_Value__c), 'No text may be seeded');
        }
    }

    @IsTest
    static void frameworkPageNeverTouchesExistingPage() {
        insert new GTM_Page_Section__c(
            Section_Address__c = GtmContentAddress.forSection('gtm', 'assistant', 'existing'),
            Offering_Key__c = 'gtm', Template_Type__c = 'assistant', Section_Key__c = 'existing',
            Label__c = 'Existing', Layout_Type__c = 'assistant', Status__c = 'Published', Active__c = true, Sort_Order__c = 10
        );
        GtmSetupActionController.FrameworkPageResult r =
            GtmSetupActionController.createFrameworkPage('assistant', new List<GtmPageSectionController.SectionSeed>{ seed('x') });
        System.assertEquals(false, r.created);
        System.assertEquals(1, [SELECT COUNT() FROM GTM_Page_Section__c WHERE Template_Type__c = 'assistant']);
        System.assertEquals('Published', [SELECT Status__c FROM GTM_Page_Section__c WHERE Template_Type__c = 'assistant'].Status__c);
    }

    @IsTest
    static void onlyOfferingAdminGrantsNewClasses() {
        List<String> classes = new List<String>{
            'GtmSetupChecklistController', 'GtmSetupActionController', 'GtmScheduledJobsController'
        };
        for (String cn : classes) {
            List<ApexClass> found = [SELECT Id FROM ApexClass WHERE Name = :cn LIMIT 1];
            if (found.isEmpty()) continue;
            for (SetupEntityAccess sea : [
                SELECT Parent.Name, Parent.IsOwnedByProfile FROM SetupEntityAccess
                WHERE SetupEntityType = 'ApexClass' AND SetupEntityId = :found[0].Id
                AND Parent.Name LIKE 'GTM_%'
            ]) {
                System.assertEquals('GTM_Offering_Admin', sea.Parent.Name, cn + ' granted to ' + sea.Parent.Name);
            }
        }
        for (ApexClass c : [SELECT Id FROM ApexClass WHERE Name = 'GtmPageSectionController' LIMIT 1]) {
            for (SetupEntityAccess sea : [
                SELECT Parent.Name FROM SetupEntityAccess
                WHERE SetupEntityType = 'ApexClass' AND SetupEntityId = :c.Id
            ]) {
                System.assertNotEquals('GTM_Offering_Admin', sea.Parent.Name);
            }
        }
    }
}
