/**
 * ISSUE #overview-sales-dashboard-3-offerings-results
 * Self-created data only; assertions are on keys this class creates.
 */
@IsTest
private class GtmOverviewOfferingCountsTest {

    private static final String KEY_A = 'zz-oc-test-a';
    private static final String KEY_B = 'zz-oc-test-b';

    private static User createUser(String alias, String permSetName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'OC ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permSetName LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static GTM_Saved_Configuration__c link(Id ownerId, String key, String stage, Boolean active) {
        return new GTM_Saved_Configuration__c(
            OwnerId = ownerId, Offering__c = key, Company__c = 'Co ' + stage,
            Generated_URL__c = 'https://example.com/' + stage,
            Presentation_Stage__c = stage, Active__c = active
        );
    }

    private static GTM_Assessment_Request__c request(Id ownerId, String key, String status, Integer n) {
        return new GTM_Assessment_Request__c(
            OwnerId = ownerId, Offering_Key__c = key,
            Requester_Name__c = 'Alex Rivera', Requester_Email__c = 'alex' + n + '@example.com',
            Company__c = 'Acme ' + n, Status__c = status
        );
    }

    private static Map<String, GtmOverviewOfferingCounts.OfferingCount> byKey(
        List<GtmOverviewOfferingCounts.OfferingCount> rows
    ) {
        Map<String, GtmOverviewOfferingCounts.OfferingCount> m =
            new Map<String, GtmOverviewOfferingCounts.OfferingCount>();
        for (GtmOverviewOfferingCounts.OfferingCount r : rows) { m.put(r.offeringKey, r); }
        return m;
    }

    @TestSetup
    static void setup() {
        User repA = createUser('ocrepa', 'GTM_Offering_User');
        User repB = createUser('ocrepb', 'GTM_Offering_User');
        List<GTM_Saved_Configuration__c> links = new List<GTM_Saved_Configuration__c>{
            link(repA.Id, KEY_A, 'Sent', true),
            link(repA.Id, KEY_A, 'Assessment', true),
            link(repA.Id, KEY_A, 'Sent', false),        // inactive: excluded
            link(repA.Id, KEY_A, 'Draft', true),        // excluded
            link(repA.Id, KEY_A, 'Rep_Direct', true),   // excluded
            link(repA.Id, KEY_A, null, true),           // excluded
            link(repA.Id, 'zz-oc-unknown', 'Sent', true),
            link(repB.Id, KEY_A, 'Sent', true),
            link(repB.Id, KEY_B, 'Sent', true)
        };
        insert links;
        List<GTM_Assessment_Request__c> reqs = new List<GTM_Assessment_Request__c>{
            request(repA.Id, KEY_A, 'New', 1),
            request(repA.Id, KEY_A, 'Completed', 2),
            request(repA.Id, KEY_A, 'Contacted', 3),
            request(repB.Id, KEY_A, 'New', 4),
            request(repB.Id, KEY_B, 'New', 5)
        };
        insert reqs;
    }

    private static User userNamed(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
    }

    @IsTest
    static void repASeesOnlyOwnCountsWithActiveAndStageRules() {
        List<GtmOverviewOfferingCounts.OfferingCount> rows;
        System.runAs(userNamed('ocrepa')) {
            rows = GtmOverviewOfferingCounts.getOfferingCounts();
        }
        Map<String, GtmOverviewOfferingCounts.OfferingCount> m = byKey(rows);
        System.assertEquals(2, m.get(KEY_A).liveLinkCount, 'Sent + Assessment only; not Draft/Rep_Direct/null/inactive');
        System.assertEquals(3, m.get(KEY_A).submittedAssessmentCount, 'all statuses');
        System.assert(!m.containsKey(KEY_B), 'rep A has no data under B and B is not in the mdt');
    }

    @IsTest
    static void repBSeesOnlyOwnCounts() {
        List<GtmOverviewOfferingCounts.OfferingCount> rows;
        System.runAs(userNamed('ocrepb')) {
            rows = GtmOverviewOfferingCounts.getOfferingCounts();
        }
        Map<String, GtmOverviewOfferingCounts.OfferingCount> m = byKey(rows);
        System.assertEquals(1, m.get(KEY_A).liveLinkCount);
        System.assertEquals(1, m.get(KEY_A).submittedAssessmentCount);
        System.assertEquals(1, m.get(KEY_B).liveLinkCount);
        System.assertEquals(1, m.get(KEY_B).submittedAssessmentCount);
        System.assert(!m.containsKey('zz-oc-unknown'), 'rep A link is not visible to rep B');
    }

    @IsTest
    static void adminWithViewAllSeesEveryone() {
        User admin = createUser('ocadm', 'GTM_Offering_Admin');
        List<GtmOverviewOfferingCounts.OfferingCount> rows;
        System.runAs(admin) {
            rows = GtmOverviewOfferingCounts.getOfferingCounts();
        }
        Map<String, GtmOverviewOfferingCounts.OfferingCount> m = byKey(rows);
        System.assertEquals(3, m.get(KEY_A).liveLinkCount);
        System.assertEquals(4, m.get(KEY_A).submittedAssessmentCount);
        System.assertEquals(1, m.get(KEY_B).liveLinkCount);
        System.assertEquals(1, m.get(KEY_B).submittedAssessmentCount);
    }

    @IsTest
    static void unknownKeyGetsRawKeyLabelAndMdtOfferingsDefaultToZero() {
        List<GtmOverviewOfferingCounts.OfferingCount> rows;
        System.runAs(userNamed('ocrepa')) {
            rows = GtmOverviewOfferingCounts.getOfferingCounts();
        }
        Map<String, GtmOverviewOfferingCounts.OfferingCount> m = byKey(rows);
        System.assertEquals('zz-oc-unknown', m.get('zz-oc-unknown').offeringLabel);
        System.assertEquals(1, m.get('zz-oc-unknown').liveLinkCount);
        System.assertEquals(0, m.get('zz-oc-unknown').submittedAssessmentCount);
        // Never drops an mdt offering, and no null counts.
        for (GTM_Offering__mdt off : [SELECT Offering_Key__c FROM GTM_Offering__mdt]) {
            if (String.isNotBlank(off.Offering_Key__c)) {
                System.assert(m.containsKey(off.Offering_Key__c), off.Offering_Key__c + ' missing');
            }
        }
        for (GtmOverviewOfferingCounts.OfferingCount r : rows) {
            System.assertNotEquals(null, r.liveLinkCount);
            System.assertNotEquals(null, r.submittedAssessmentCount);
        }
    }

    @IsTest
    static void rowsAreSortedByLabelThenKey() {
        List<GtmOverviewOfferingCounts.OfferingCount> rows;
        System.runAs(userNamed('ocrepb')) {
            rows = GtmOverviewOfferingCounts.getOfferingCounts();
        }
        for (Integer i = 1; i < rows.size(); i++) {
            System.assert(
                rows[i - 1].offeringLabel.toLowerCase() <= rows[i].offeringLabel.toLowerCase(),
                'sorted by label'
            );
        }
    }

    @IsTest
    static void executesNoDml() {
        Integer before;
        Integer after;
        System.runAs(userNamed('ocrepa')) {
            before = Limits.getDmlStatements();
            GtmOverviewOfferingCounts.getOfferingCounts();
            after = Limits.getDmlStatements();
        }
        System.assertEquals(before, after, 'read-only');
    }
}
