/**
 * Coverage for GtmAnalyticsController, issues #110 and #138. Seeds one
 * rep-owned link with a full opened -> submitted -> published trail plus a
 * second, quieter link whose request is scored/tiered but NOT in the
 * 'Completed' rep-pipeline status -- the exact shape issue #138 fixes: tier
 * mix and "submitted" must include it, since Status__c is a rep follow-up
 * stage, not an assessment-completion signal.
 */
@IsTest
private class GtmAnalyticsControllerTest {

    private static final String OFFERING_A = 'Data Cloud Migration Readiness';
    private static final String OFFERING_B = 'AI Enablement Assessment';

    @TestSetup
    static void seed() {
        Id uid = UserInfo.getUserId();

        GTM_Saved_Configuration__c cfgA = new GTM_Saved_Configuration__c(
            OwnerId = uid,
            Company__c = 'Globex',
            Offering__c = OFFERING_A,
            Link_Password__c = 'test-pw-1'
        );
        GTM_Saved_Configuration__c cfgB = new GTM_Saved_Configuration__c(
            OwnerId = uid,
            Company__c = 'Initech',
            Offering__c = OFFERING_B,
            Link_Password__c = 'test-pw-2'
        );
        insert new List<GTM_Saved_Configuration__c>{ cfgA, cfgB };

        insert new List<GTM_Link_Event__c>{
            new GTM_Link_Event__c(
                Saved_Configuration__c = cfgA.Id,
                Event_Type__c = 'Page View',
                Sequence__c = 1
            ),
            new GTM_Link_Event__c(
                Saved_Configuration__c = cfgA.Id,
                Event_Type__c = 'Form Opened',
                Sequence__c = 2
            )
        };

        DateTime submitted = DateTime.now().addDays(-5);
        // Rep has marked this lead's follow-up 'Completed' in their own pipeline.
        GTM_Assessment_Request__c reqA = new GTM_Assessment_Request__c(
            Saved_Configuration__c = cfgA.Id,
            Offering_Key__c = OFFERING_A,
            Company__c = 'Globex',
            Status__c = 'Completed',
            Assessment_Score__c = 27,
            Assessment_Tier__c = 'Fast-Track',
            Submitted_At__c = submitted
        );
        // Rep pipeline still 'Scheduled' -- but the assessment itself is
        // already fully scored/tiered, exactly like reqA. Pre-#138, this
        // request was invisible to tier mix and "completed" counted 0/2.
        GTM_Assessment_Request__c reqB = new GTM_Assessment_Request__c(
            Saved_Configuration__c = cfgB.Id,
            Offering_Key__c = OFFERING_B,
            Company__c = 'Initech',
            Status__c = 'Scheduled',
            Assessment_Score__c = 18,
            Assessment_Tier__c = 'Prep Required',
            Submitted_At__c = submitted
        );
        insert new List<GTM_Assessment_Request__c>{ reqA, reqB };

        insert new GTM_Readout__c(
            Assessment_Request__c = reqA.Id,
            Offering_Key__c = OFFERING_A,
            Status__c = 'Published',
            Published_Date__c = DateTime.now().addDays(-2)
        );
    }

    // Issue #140: summaryForOwner is the extracted body getSummary() now
    // delegates to, so GtmAnalyticsDigestJob computes identical numbers to
    // the tab, not a second definition. Prove they actually agree.
    @IsTest
    static void summaryForOwnerMatchesGetSummaryForTheSameOwnerAndRange() {
        Date rangeStart = Date.today().addDays(-30);
        Date rangeEnd = Date.today();

        Test.startTest();
        GtmAnalyticsController.AnalyticsSummary viaGetSummary =
            GtmAnalyticsController.getSummary(rangeStart, rangeEnd, null);
        GtmAnalyticsController.AnalyticsSummary viaSummaryForOwner =
            GtmAnalyticsController.summaryForOwner(UserInfo.getUserId(), rangeStart, rangeEnd, null);
        Test.stopTest();

        System.assertEquals(viaGetSummary.linksCreated, viaSummaryForOwner.linksCreated);
        System.assertEquals(viaGetSummary.assessmentsSubmitted, viaSummaryForOwner.assessmentsSubmitted);
        System.assertEquals(viaGetSummary.readoutsPublished, viaSummaryForOwner.readoutsPublished);
        System.assertEquals(viaGetSummary.avgDaysToPublish, viaSummaryForOwner.avgDaysToPublish);
    }

    @IsTest
    static void summaryCountsLinksOpensRequestsAndReadouts() {
        Date rangeStart = Date.today().addDays(-30);
        Date rangeEnd = Date.today();

        Test.startTest();
        GtmAnalyticsController.AnalyticsSummary summary =
            GtmAnalyticsController.getSummary(rangeStart, rangeEnd, null);
        Test.stopTest();

        System.assertEquals(2, summary.linksCreated, 'both seeded links fall in range');
        System.assertEquals(1, summary.linksOpened, 'only cfgA has an opening event');
        System.assertEquals(2, summary.assessmentsSubmitted, 'a request exists for each link -- both count as submitted');
        System.assertEquals(1, summary.readoutsPublished, 'exactly one published readout traces back');
        System.assert(summary.avgDaysToPublish > 0, 'time-to-publish is measured from a real gap');

        // Issue #138: tier mix must include BOTH tiered requests, regardless
        // of Status__c -- reqB is 'Scheduled', not 'Completed', and must still count.
        System.assertEquals(2, summary.tierMix.size(), 'both tiered requests count, not just Status=Completed');
        Map<String, Integer> tierCounts = new Map<String, Integer>();
        for (GtmAnalyticsController.TierCount tc : summary.tierMix) {
            tierCounts.put(tc.tier, tc.count);
        }
        System.assertEquals(1, tierCounts.get('Fast-Track'));
        System.assertEquals(1, tierCounts.get('Prep Required'));

        // Issue #138: the rep follow-up pipeline is its own field now, not
        // conflated with assessment completion.
        Map<String, Integer> statusCounts = new Map<String, Integer>();
        for (GtmAnalyticsController.StatusCount sc : summary.followUpStatusCounts) {
            statusCounts.put(sc.status, sc.count);
        }
        System.assertEquals(1, statusCounts.get('Completed'));
        System.assertEquals(1, statusCounts.get('Scheduled'));

        System.assert(!summary.trend.isEmpty(), 'the seeded events/requests fall in the current week');
        Integer totalOpens = 0;
        Integer totalSubmitted = 0;
        for (GtmAnalyticsController.TrendPoint tp : summary.trend) {
            totalOpens += tp.opens;
            totalSubmitted += tp.submitted;
        }
        System.assertEquals(2, totalOpens, 'the two seeded open events land in the trend');
        System.assertEquals(2, totalSubmitted, 'both requests land in the trend');
    }

    @IsTest
    static void summaryFiltersByOffering() {
        Date rangeStart = Date.today().addDays(-30);
        Date rangeEnd = Date.today();

        Test.startTest();
        GtmAnalyticsController.AnalyticsSummary summaryA =
            GtmAnalyticsController.getSummary(rangeStart, rangeEnd, OFFERING_A);
        GtmAnalyticsController.AnalyticsSummary summaryB =
            GtmAnalyticsController.getSummary(rangeStart, rangeEnd, OFFERING_B);
        Test.stopTest();

        System.assertEquals(1, summaryA.linksCreated);
        System.assertEquals(1, summaryA.readoutsPublished);
        System.assertEquals(1, summaryB.linksCreated);
        System.assertEquals(0, summaryB.readoutsPublished, 'Initech never reached a published readout');
        System.assertEquals(1, summaryB.tierMix.size(), 'Initech has one tiered request even though it is only Scheduled');
    }

    @IsTest
    static void summaryHandlesEmptyRangeWithoutError() {
        Date rangeStart = Date.today().addYears(-5);
        Date rangeEnd = rangeStart.addDays(1);

        Test.startTest();
        GtmAnalyticsController.AnalyticsSummary summary =
            GtmAnalyticsController.getSummary(rangeStart, rangeEnd, null);
        Test.stopTest();

        System.assertEquals(0, summary.linksCreated);
        System.assertEquals(0, summary.readoutsPublished);
        System.assertEquals(0, summary.avgDaysToPublish);
        System.assert(summary.tierMix.isEmpty());
        System.assert(summary.followUpStatusCounts.isEmpty());
        System.assert(summary.trend.isEmpty());
    }

    @IsTest
    static void summaryRejectsInvertedRange() {
        Test.startTest();
        Boolean threw = false;
        try {
            GtmAnalyticsController.getSummary(Date.today(), Date.today().addDays(-1), null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'a range end before its start must be rejected');
    }

    @IsTest
    static void offeringBreakdownSortsByPublishedDescending() {
        Date rangeStart = Date.today().addDays(-30);
        Date rangeEnd = Date.today();

        Test.startTest();
        List<GtmAnalyticsController.OfferingRow> rows =
            GtmAnalyticsController.getOfferingBreakdown(rangeStart, rangeEnd);
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals(OFFERING_A, rows[0].offering, 'the offering with a published readout sorts first');
        System.assertEquals(1, rows[0].published);
        System.assertEquals(1, rows[0].submitted);
        System.assertEquals(27, rows[0].avgScore);
        System.assertEquals('Fast-Track', rows[0].topTier);
        System.assertEquals(0, rows[1].published);
        System.assertEquals('Prep Required', rows[1].topTier, 'Initech is tiered even though it is only Scheduled');
    }
}
