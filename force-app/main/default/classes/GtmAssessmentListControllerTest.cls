/**
 * Tests for GtmAssessmentListController (issue assessments-tab-filter).
 * Every test creates its own data; nothing here reads or seeds live records.
 * Written without an org run (not authorised); review against the class before
 * the first authorised deploy.
 */
@isTest
private class GtmAssessmentListControllerTest {

    // ------------------------------------------------------------- fixtures

    private static Integer seq = 0;

    private static GTM_Assessment_Request__c req(
        String status, String tier, Decimal score, Datetime submitted, String offering
    ) {
        seq++;
        return new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Requester ' + seq,
            Requester_Email__c  = 'req' + seq + '@example.com',
            Company__c          = 'Company ' + seq,
            Status__c           = status,
            Assessment_Tier__c  = tier,
            Assessment_Score__c = score,
            Submitted_At__c     = submitted,
            Offering_Key__c     = offering
        );
    }

    private static GTM_Assessment_Request__c seed(
        String status, String tier, Decimal score, Datetime submitted, String offering
    ) {
        GTM_Assessment_Request__c r = req(status, tier, score, submitted, offering);
        insert r;
        return r;
    }

    private static GTM_Assessment_Request__c seedBasic() {
        return seed('New', 'Prep Required', 18, Datetime.now(), 'offer-a');
    }

    private static GTM_Readout__c seedReadout(Id requestId, String status, Datetime notificationSent, Id ownerId) {
        GTM_Readout__c ro = new GTM_Readout__c(
            Assessment_Request__c    = requestId,
            Offering_Key__c          = 'offer-a',
            Status__c                = status,
            Notification_Sent_Date__c = notificationSent
        );
        if (ownerId != null) { ro.OwnerId = ownerId; }
        insert ro;
        return ro;
    }

    private static GtmAssessmentListController.AssessmentQuery query() {
        return new GtmAssessmentListController.AssessmentQuery();
    }

    private static Set<Id> ids(GtmAssessmentListController.AssessmentPage page) {
        Set<Id> out = new Set<Id>();
        for (GtmAssessmentListController.AssessmentRow r : page.rows) { out.add(r.recordId); }
        return out;
    }

    private static List<Id> orderedIds(GtmAssessmentListController.AssessmentPage page) {
        List<Id> out = new List<Id>();
        for (GtmAssessmentListController.AssessmentRow r : page.rows) { out.add(r.recordId); }
        return out;
    }

    private static Datetime dayStart(Date d) {
        return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
    }

    private static Datetime dayEnd(Date d) {
        return Datetime.newInstance(d, Time.newInstance(23, 59, 59, 0));
    }

    private static User createRep(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = alias,
            Email             = alias + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'Rep ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/New_York',
            Username          = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    /** The deployed triage queue if present, otherwise one created for the test. */
    private static Id ensureTriageQueue() {
        List<Group> existing = [
            SELECT Id FROM Group
            WHERE DeveloperName = 'GTM_Readout_Triage' AND Type = 'Queue'
            LIMIT 1
        ];
        if (!existing.isEmpty()) { return existing[0].Id; }
        Group q = new Group(Name = 'Unassigned Readouts', DeveloperName = 'GTM_Readout_Triage', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert q;
            insert new QueueSobject(QueueId = q.Id, SobjectType = 'GTM_Readout__c');
        }
        return q.Id;
    }

    // ------------------------------------------------------- grain and join

    @isTest
    static void oneRowPerRequestIncludingRequestsWithNoReadout() {
        GTM_Assessment_Request__c a = seedBasic();
        GTM_Assessment_Request__c b = seedBasic();
        seedReadout(b.Id, 'Draft', null, null);

        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(query());

        Assert.areEqual(2, page.totalCount);
        Assert.areEqual(2, page.rows.size());
        for (GtmAssessmentListController.AssessmentRow r : page.rows) {
            if (r.recordId == a.Id) {
                Assert.isNull(r.readoutId, 'No readout yet -> blank readoutId');
                Assert.isNull(r.readoutStatus, 'No readout yet -> blank readout status');
            } else {
                Assert.areEqual('Draft', r.readoutStatus);
                Assert.isNotNull(r.readoutId);
            }
        }
    }

    @isTest
    static void nullQueryIsTolerated() {
        seedBasic();
        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(null);
        Assert.areEqual(1, page.totalCount);
    }

    @isTest
    static void readoutJoinUsesTheMostRecentlyCreatedReadoutOfSeveral() {
        GTM_Assessment_Request__c r = seedBasic();
        seedReadout(r.Id, 'Draft', null, null);
        GTM_Readout__c newest = seedReadout(r.Id, 'Published', null, null);

        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(query());

        Assert.areEqual(1, page.rows.size(), 'Several readouts still yield ONE row per request');
        Assert.areEqual('Published', page.rows[0].readoutStatus);
        Assert.areEqual(newest.Id, page.rows[0].readoutId);

        // The filter uses the same chosen readout, never "any readout of the request".
        GtmAssessmentListController.AssessmentQuery q = query();
        q.readout = new List<String>{ 'draft' };
        Assert.areEqual(0, GtmAssessmentListController.getAssessmentPage(q).totalCount,
            'The older Draft readout must not make the request match draft');
    }

    @isTest
    static void rowCarriesContactAccountAndCompanyFallbacks() {
        Account acct = new Account(Name = 'Acme Holdings');
        insert acct;
        Contact c = new Contact(LastName = 'Rivera', AccountId = acct.Id);
        insert c;
        GTM_Assessment_Request__c r = req('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        r.Company__c = null;
        r.Contact__c = c.Id;
        r.Account__c = acct.Id;
        insert r;

        GtmAssessmentListController.AssessmentRow row =
            GtmAssessmentListController.getAssessmentPage(query()).rows[0];

        Assert.areEqual(c.Id, row.contactId);
        Assert.areEqual('Rivera', row.contactName);
        Assert.areEqual(acct.Id, row.accountId);
        Assert.areEqual('Acme Holdings', row.company, 'Company falls back to Account.Name');
        Assert.areEqual(4, row.tierRank);
    }

    @isTest
    static void companyPrefersAccountNameOverTypedCompanyWhenBothArePopulated() {
        // issue-pages-table-account-column-consistency: the governed Account
        // lookup must win over a hand-typed, possibly-stale Company__c value
        // whenever both exist on the same request.
        Account acct = new Account(Name = 'Globex Corp');
        insert acct;
        GTM_Assessment_Request__c r = req('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        r.Company__c = 'Stale Typed Name';
        r.Account__c = acct.Id;
        insert r;

        GtmAssessmentListController.AssessmentRow row =
            GtmAssessmentListController.getAssessmentPage(query()).rows[0];

        Assert.areEqual('Globex Corp', row.company, 'Account.Name wins over Company__c when both are populated');
    }

    // ----------------------------------------------------------- dimensions

    @isTest
    static void statusFilterIsMultiSelectWithinTheDimension() {
        GTM_Assessment_Request__c n = seed('New', 'Prep Required', 18, Datetime.now(), 'offer-a');
        GTM_Assessment_Request__c c = seed('Contacted', 'Prep Required', 18, Datetime.now(), 'offer-a');
        GTM_Assessment_Request__c ns = seed('No Show', 'Prep Required', 18, Datetime.now(), 'offer-a');
        seed('Completed', 'Prep Required', 18, Datetime.now(), 'offer-a');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.status = new List<String>{ 'new', 'no-show', 'contacted' };
        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(q);

        Assert.areEqual(new Set<Id>{ n.Id, c.Id, ns.Id }, ids(page));
        Assert.areEqual(3, page.totalCount);
    }

    @isTest
    static void tierFilterIsMultiSelectAndExcludesNullTier() {
        GTM_Assessment_Request__c ft = seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        GTM_Assessment_Request__c ar = seed('New', 'Accelerator-Ready', 22, Datetime.now(), 'offer-a');
        seed('New', 'Discovery First', 10, Datetime.now(), 'offer-a');
        seed('New', null, null, Datetime.now(), 'offer-a');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.tier = new List<String>{ 'fast-track', 'accelerator-ready' };

        Assert.areEqual(new Set<Id>{ ft.Id, ar.Id }, ids(GtmAssessmentListController.getAssessmentPage(q)));
    }

    @isTest
    static void dimensionsAndTogetherAcrossDimensions() {
        GTM_Assessment_Request__c hit = seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        seed('Contacted', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        seed('New', 'Prep Required', 18, Datetime.now(), 'offer-a');
        seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-b');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.status = new List<String>{ 'new' };
        q.tier = new List<String>{ 'fast-track' };
        q.offering = new List<String>{ 'offer-a' };

        Assert.areEqual(new Set<Id>{ hit.Id }, ids(GtmAssessmentListController.getAssessmentPage(q)));
    }

    @isTest
    static void offeringFilterAndOfferingOptions() {
        GTM_Assessment_Request__c a = seed('New', 'Prep Required', 18, Datetime.now(), 'offer-a');
        GTM_Assessment_Request__c b = seed('New', 'Prep Required', 18, Datetime.now(), 'offer-b');
        seed('New', 'Prep Required', 18, Datetime.now(), null);

        GtmAssessmentListController.AssessmentQuery q = query();
        q.offering = new List<String>{ 'offer-b', 'offer-c' };
        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(q);

        Assert.areEqual(new Set<Id>{ b.Id }, ids(page));
        // Options come from the SCOPE, not from the active filters, so choosing
        // one offering does not make the others vanish from the bar.
        Assert.areEqual(new List<String>{ 'offer-a', 'offer-b' }, page.offeringOptions);
        Assert.isNotNull(a.Id);
    }

    @isTest
    static void readoutKeysEvaluateTheChosenReadout() {
        GTM_Assessment_Request__c none = seedBasic();
        GTM_Assessment_Request__c draft = seedBasic();
        GTM_Assessment_Request__c pending = seedBasic();
        GTM_Assessment_Request__c unsent = seedBasic();
        GTM_Assessment_Request__c sent = seedBasic();
        GTM_Assessment_Request__c pub = seedBasic();
        seedReadout(draft.Id, 'Draft', null, null);
        seedReadout(pending.Id, 'Pending Approval', null, null);
        seedReadout(unsent.Id, 'Approved', null, null);
        seedReadout(sent.Id, 'Approved', Datetime.now(), null);
        seedReadout(pub.Id, 'Published', null, null);

        Assert.areEqual(new Set<Id>{ none.Id }, ids(byReadout('none')));
        Assert.areEqual(new Set<Id>{ draft.Id }, ids(byReadout('draft')));
        Assert.areEqual(new Set<Id>{ pending.Id }, ids(byReadout('pending')));
        Assert.areEqual(new Set<Id>{ unsent.Id }, ids(byReadout('approved-unsent')),
            'Approved with a notification already sent is NOT "approved, not sent"');
        Assert.areEqual(new Set<Id>{ pub.Id }, ids(byReadout('published')));

        GtmAssessmentListController.AssessmentPage anyReadout = GtmAssessmentListController.getAssessmentPage(query());
        Assert.areEqual(6, anyReadout.totalCount, 'No readout filter = any, including Published and sent-Approved');
        for (GtmAssessmentListController.AssessmentRow r : anyReadout.rows) {
            if (r.recordId == sent.Id) {
                Assert.areEqual('Approved', r.readoutStatus, 'The column shows the real status');
                Assert.isTrue(r.readoutNotificationSent);
            }
        }

        GtmAssessmentListController.AssessmentQuery multi = query();
        multi.readout = new List<String>{ 'none', 'draft' };
        Assert.areEqual(new Set<Id>{ none.Id, draft.Id }, ids(GtmAssessmentListController.getAssessmentPage(multi)));
    }

    private static GtmAssessmentListController.AssessmentPage byReadout(String key) {
        GtmAssessmentListController.AssessmentQuery q = query();
        q.readout = new List<String>{ key };
        return GtmAssessmentListController.getAssessmentPage(q);
    }

    // --------------------------------------------------------------- preset

    @isTest
    static void readyToBookIsNewAndFastTrackOrAcceleratorReady() {
        GTM_Assessment_Request__c ft = seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        GTM_Assessment_Request__c ar = seed('New', 'Accelerator-Ready', 22, Datetime.now(), 'offer-a');
        seed('New', 'Prep Required', 18, Datetime.now(), 'offer-a');
        seed('New', 'Discovery First', 10, Datetime.now(), 'offer-a');
        seed('New', null, null, Datetime.now(), 'offer-a');
        seed('Contacted', 'Fast-Track', 30, Datetime.now(), 'offer-a');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.preset = 'ready-to-book';

        Assert.areEqual(new Set<Id>{ ft.Id, ar.Id }, ids(GtmAssessmentListController.getAssessmentPage(q)));
    }

    @isTest
    static void readyToBookIsIntersectedWithOtherFiltersNotOverridden() {
        GTM_Assessment_Request__c ft = seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        seed('New', 'Accelerator-Ready', 22, Datetime.now(), 'offer-a');
        seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-b');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.preset = 'ready-to-book';
        q.tier = new List<String>{ 'fast-track', 'prep-required' };
        q.offering = new List<String>{ 'offer-a' };
        Assert.areEqual(new Set<Id>{ ft.Id }, ids(GtmAssessmentListController.getAssessmentPage(q)));

        GtmAssessmentListController.AssessmentQuery none = query();
        none.preset = 'ready-to-book';
        none.status = new List<String>{ 'completed' };
        GtmAssessmentListController.AssessmentPage noMatches = GtmAssessmentListController.getAssessmentPage(none);
        Assert.areEqual(0, noMatches.totalCount, 'Preset AND status=Completed cannot match anything');
        Assert.areEqual(0, noMatches.rows.size());
    }

    @isTest
    static void unknownKeysAreDroppedNotThrown() {
        seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        seed('Completed', 'Prep Required', 18, Datetime.now(), 'offer-b');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.status = new List<String>{ 'bogus', null };
        q.tier = new List<String>{ 'nope' };
        q.readout = new List<String>{ 'zzz' };
        q.offering = new List<String>{ '', null };
        q.range = 'not-a-range';
        q.preset = 'zzz';
        q.sortBy = 'zzz';
        q.sortDir = 'sideways';

        Assert.areEqual(2, GtmAssessmentListController.getAssessmentPage(q).totalCount,
            'Unknown values mean "no filter on that dimension"');
    }

    // ---------------------------------------------------------------- dates

    @isTest
    static void presetRangeIncludesTodayAndTheNMinusOneDayBack() {
        Date todayDate = Date.today();
        GTM_Assessment_Request__c edgeIn = seed('New', 'Prep Required', 18, dayStart(todayDate.addDays(-6)), 'offer-a');
        GTM_Assessment_Request__c todayEnd = seed('New', 'Prep Required', 18, dayEnd(todayDate), 'offer-a');
        GTM_Assessment_Request__c justOut = seed('New', 'Prep Required', 18, dayEnd(todayDate.addDays(-7)), 'offer-a');
        GTM_Assessment_Request__c oldRow = seed('New', 'Prep Required', 18, dayStart(todayDate.addDays(-40)), 'offer-a');

        GtmAssessmentListController.AssessmentQuery q7 = query();
        q7.range = '7';
        Set<Id> in7 = ids(GtmAssessmentListController.getAssessmentPage(q7));
        Assert.isTrue(in7.contains(edgeIn.Id), 'Day 7 (today - 6) at 00:00 is inside the last 7 days');
        Assert.isTrue(in7.contains(todayEnd.Id), 'Today 23:59:59 is inside');
        Assert.isFalse(in7.contains(justOut.Id), 'Day 8 (today - 7) 23:59:59 is outside');
        Assert.isFalse(in7.contains(oldRow.Id));

        GtmAssessmentListController.AssessmentQuery q30 = query();
        q30.range = '30';
        Set<Id> in30 = ids(GtmAssessmentListController.getAssessmentPage(q30));
        Assert.isTrue(in30.contains(justOut.Id));
        Assert.isFalse(in30.contains(oldRow.Id));

        GtmAssessmentListController.AssessmentQuery q90 = query();
        q90.range = '90';
        Assert.isTrue(ids(GtmAssessmentListController.getAssessmentPage(q90)).contains(oldRow.Id));
    }

    @isTest
    static void customRangeIsInclusiveOnBothWholeDays() {
        Date from1 = Date.today().addDays(-20);
        Date to1 = Date.today().addDays(-10);
        GTM_Assessment_Request__c firstRow = seed('New', 'Prep Required', 18, dayStart(from1), 'offer-a');
        GTM_Assessment_Request__c lastRow = seed('New', 'Prep Required', 18, dayEnd(to1), 'offer-a');
        GTM_Assessment_Request__c beforeRange = seed('New', 'Prep Required', 18, dayEnd(from1.addDays(-1)), 'offer-a');
        GTM_Assessment_Request__c afterRange = seed('New', 'Prep Required', 18, dayStart(to1.addDays(1)), 'offer-a');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.range = String.valueOf(from1) + '..' + String.valueOf(to1);
        Set<Id> got = ids(GtmAssessmentListController.getAssessmentPage(q));
        Assert.areEqual(new Set<Id>{ firstRow.Id, lastRow.Id }, got);
        Assert.isFalse(got.contains(beforeRange.Id));
        Assert.isFalse(got.contains(afterRange.Id));

        GtmAssessmentListController.AssessmentQuery reversed = query();
        reversed.range = String.valueOf(to1) + '..' + String.valueOf(from1);
        Assert.areEqual(got, ids(GtmAssessmentListController.getAssessmentPage(reversed)),
            'A reversed pair is swapped');
    }

    @isTest
    static void badCustomRangesAreDropped() {
        seedBasic();
        for (String bad : new List<String>{ '2026-02-31..2026-03-01', '2026-01-01', 'a..b', '2026-01-01..2026-01-02..2026-01-03', '14' }) {
            GtmAssessmentListController.AssessmentQuery q = query();
            q.range = bad;
            Assert.areEqual(1, GtmAssessmentListController.getAssessmentPage(q).totalCount,
                'Unparseable range "' + bad + '" must be ignored');
        }
    }

    @isTest
    static void nullSubmittedAtFallsBackToCreatedDate() {
        // Created just now, no Submitted_At__c: falls inside "last 7 days".
        GTM_Assessment_Request__c noSubmitted = seed('New', 'Prep Required', 18, null, 'offer-a');
        GTM_Assessment_Request__c oldSubmitted = seed('New', 'Prep Required', 18, dayStart(Date.today().addDays(-60)), 'offer-a');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.range = '7';
        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(q);

        Assert.areEqual(new Set<Id>{ noSubmitted.Id }, ids(page));
        Assert.isNotNull(page.rows[0].submittedAt, 'submittedAt falls back to createdDate for display');
        Assert.isNotNull(oldSubmitted.Id);
    }

    // ------------------------------------------------------- count and paging

    @isTest
    static void totalCountIsTheTrueTotalAndPagesSliceTheSameOrdering() {
        for (Integer i = 0; i < 5; i++) {
            seed('New', 'Prep Required', 10 + i, Datetime.now().addMinutes(-i), 'offer-a');
        }
        GtmAssessmentListController.AssessmentQuery q = query();
        q.pageSize = 2;

        q.offset = 0;
        GtmAssessmentListController.AssessmentPage p1 = GtmAssessmentListController.getAssessmentPage(q);
        q.offset = 2;
        GtmAssessmentListController.AssessmentPage p2 = GtmAssessmentListController.getAssessmentPage(q);
        q.offset = 4;
        GtmAssessmentListController.AssessmentPage p3 = GtmAssessmentListController.getAssessmentPage(q);

        Assert.areEqual(2, p1.rows.size());
        Assert.areEqual(2, p2.rows.size());
        Assert.areEqual(1, p3.rows.size());
        Assert.areEqual(5, p1.totalCount, 'totalCount is the true total, not the page size');
        Assert.areEqual(5, p2.totalCount);
        Assert.areEqual(5, p3.totalCount);
        Set<Id> seen = new Set<Id>();
        seen.addAll(ids(p1));
        seen.addAll(ids(p2));
        seen.addAll(ids(p3));
        Assert.areEqual(5, seen.size(), 'Pages must not overlap or skip');
        Assert.isFalse(p1.totalIsCapped);
        Assert.isTrue(p2.offeringOptions.isEmpty(), 'offeringOptions are only computed for the first page');

        q.offset = 99;
        Assert.areEqual(0, GtmAssessmentListController.getAssessmentPage(q).rows.size(), 'Past the end is empty, not an error');
    }

    @isTest
    static void pageSizeDefaultsToFiftyAndIsClamped() {
        List<GTM_Assessment_Request__c> many = new List<GTM_Assessment_Request__c>();
        for (Integer i = 0; i < 55; i++) {
            many.add(req('New', 'Prep Required', 18, Datetime.now(), 'offer-a'));
        }
        insert many;

        GtmAssessmentListController.AssessmentPage defaultPage = GtmAssessmentListController.getAssessmentPage(query());
        Assert.areEqual(50, defaultPage.rows.size(), 'Default page size is 50');
        Assert.areEqual(55, defaultPage.totalCount);

        GtmAssessmentListController.AssessmentQuery tiny = query();
        tiny.pageSize = -5;
        Assert.areEqual(1, GtmAssessmentListController.getAssessmentPage(tiny).rows.size());

        GtmAssessmentListController.AssessmentQuery huge = query();
        huge.pageSize = 100000;
        Assert.areEqual(55, GtmAssessmentListController.getAssessmentPage(huge).rows.size(), 'Clamped to 200, all 55 fit');
    }

    @isTest
    static void safetyCeilingSetsTotalIsCapped() {
        for (Integer i = 0; i < 5; i++) { seedBasic(); }
        GtmAssessmentListController.candidateCeiling = 3;

        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(query());

        Assert.isTrue(page.totalIsCapped, 'Hitting the ceiling is disclosed');
        Assert.areEqual(3, page.totalCount);
    }

    @isTest
    static void totalCountUnderFiltersIsNotTheUnfilteredCount() {
        seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        seed('Completed', 'Prep Required', 18, Datetime.now(), 'offer-a');
        seed('Completed', 'Prep Required', 18, Datetime.now(), 'offer-a');
        GtmAssessmentListController.AssessmentQuery q = query();
        q.status = new List<String>{ 'completed' };
        q.pageSize = 1;
        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(q);
        Assert.areEqual(2, page.totalCount);
        Assert.areEqual(1, page.rows.size());
    }

    // ---------------------------------------------------------------- sorting

    @isTest
    static void defaultSortIsBestFitTierThenScoreThenNewest() {
        Datetime now1 = Datetime.now();
        GTM_Assessment_Request__c noTier = seed('New', null, 31, now1, 'offer-a');
        GTM_Assessment_Request__c df = seed('New', 'Discovery First', 14, now1, 'offer-a');
        GTM_Assessment_Request__c pr = seed('New', 'Prep Required', 20, now1, 'offer-a');
        GTM_Assessment_Request__c ar = seed('New', 'Accelerator-Ready', 22, now1, 'offer-a');
        GTM_Assessment_Request__c ft27 = seed('New', 'Fast-Track', 27, now1.addDays(-1), 'offer-a');
        GTM_Assessment_Request__c ft30 = seed('New', 'Fast-Track', 30, now1.addDays(-5), 'offer-a');
        GTM_Assessment_Request__c ft27Newer = seed('New', 'Fast-Track', 27, now1, 'offer-a');

        List<Id> order = orderedIds(GtmAssessmentListController.getAssessmentPage(query()));

        Assert.areEqual(
            new List<Id>{ ft30.Id, ft27Newer.Id, ft27.Id, ar.Id, pr.Id, df.Id, noTier.Id },
            order,
            'Tier rank DESC, score DESC, newest DESC; a null tier is shown, but last, even with the highest score'
        );
    }

    @isTest
    static void columnSortsApplyTheNamedKeyWithNullsLast() {
        GTM_Assessment_Request__c lo = seed('Contacted', 'Discovery First', 10, Datetime.now(), 'offer-a');
        GTM_Assessment_Request__c hi = seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        GTM_Assessment_Request__c nul = seed('Completed', null, null, Datetime.now(), 'offer-a');

        GtmAssessmentListController.AssessmentQuery q = query();
        q.sortBy = 'score';
        q.sortDir = 'asc';
        Assert.areEqual(new List<Id>{ lo.Id, hi.Id, nul.Id }, orderedIds(GtmAssessmentListController.getAssessmentPage(q)),
            'score asc, null last');
        q.sortDir = 'desc';
        Assert.areEqual(new List<Id>{ hi.Id, lo.Id, nul.Id }, orderedIds(GtmAssessmentListController.getAssessmentPage(q)),
            'score desc, null STILL last');

        q.sortBy = 'tier';
        q.sortDir = 'asc';
        Assert.areEqual(new List<Id>{ lo.Id, hi.Id, nul.Id }, orderedIds(GtmAssessmentListController.getAssessmentPage(q)),
            'tier asc = lowest rank first, null last');

        q.sortBy = 'status';
        q.sortDir = 'asc';
        Assert.areEqual(new List<Id>{ nul.Id, lo.Id, hi.Id }, orderedIds(GtmAssessmentListController.getAssessmentPage(q)),
            'Completed, Contacted... alphabetical: Completed < Contacted < New');
    }

    @isTest
    static void submittedAndCompanySortsWork() {
        GTM_Assessment_Request__c oldest = req('New', 'Prep Required', 18, Datetime.now().addDays(-3), 'offer-a');
        oldest.Company__c = 'Zeta';
        GTM_Assessment_Request__c newest = req('New', 'Prep Required', 18, Datetime.now(), 'offer-a');
        newest.Company__c = 'alpha';
        insert new List<GTM_Assessment_Request__c>{ oldest, newest };

        GtmAssessmentListController.AssessmentQuery q = query();
        q.sortBy = 'submitted';
        q.sortDir = 'asc';
        Assert.areEqual(new List<Id>{ oldest.Id, newest.Id }, orderedIds(GtmAssessmentListController.getAssessmentPage(q)));

        q.sortBy = 'company';
        q.sortDir = 'asc';
        Assert.areEqual(new List<Id>{ newest.Id, oldest.Id }, orderedIds(GtmAssessmentListController.getAssessmentPage(q)),
            'Company sort is case-insensitive');
        q.sortDir = 'desc';
        Assert.areEqual(new List<Id>{ oldest.Id, newest.Id }, orderedIds(GtmAssessmentListController.getAssessmentPage(q)));
    }

    // ---------------------------------------------------------------- scoping

    /**
     * Ported and widened from getReadoutsForReview's rep-data-scoping-owd-2
     * test: the Private model means a rep sees their own rows and nothing else,
     * the same with and without filters.
     */
    @isTest
    static void twoRepsEachSeeOnlyTheirOwnRequestsWithAndWithoutFilters() {
        User repA = createRep('gtmla1');
        User repB = createRep('gtmlb1');
        GTM_Assessment_Request__c ra = req('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        ra.OwnerId = repA.Id;
        GTM_Assessment_Request__c rb = req('New', 'Fast-Track', 30, Datetime.now(), 'offer-b');
        rb.OwnerId = repB.Id;
        insert new List<GTM_Assessment_Request__c>{ ra, rb };

        GtmAssessmentListController.AssessmentQuery filtered = query();
        filtered.preset = 'ready-to-book';

        GtmAssessmentListController.AssessmentPage aPlain;
        GtmAssessmentListController.AssessmentPage aFiltered;
        GtmAssessmentListController.AssessmentPage bPlain;
        System.runAs(repA) {
            aPlain = GtmAssessmentListController.getAssessmentPage(query());
            aFiltered = GtmAssessmentListController.getAssessmentPage(filtered);
        }
        System.runAs(repB) {
            bPlain = GtmAssessmentListController.getAssessmentPage(query());
        }

        Assert.areEqual(new Set<Id>{ ra.Id }, ids(aPlain));
        Assert.areEqual(1, aPlain.totalCount, 'The count is scoped exactly like the rows');
        Assert.areEqual(new Set<Id>{ ra.Id }, ids(aFiltered));
        Assert.areEqual(new Set<Id>{ rb.Id }, ids(bPlain));
        Assert.areEqual(new List<String>{ 'offer-a' }, aPlain.offeringOptions,
            'offeringOptions never leak another rep\'s offerings');
    }

    @isTest
    static void adminWithViewAllSeesEveryRequestWithAndWithoutFilters() {
        User repA = createRep('gtmlc1');
        User adminUser = createRep('gtmlc2');
        List<PermissionSet> adminSets = [
            SELECT Id FROM PermissionSet WHERE Name = 'GTM_Offering_Admin' LIMIT 1
        ];
        if (adminSets.isEmpty()) {
            return; // Permission set not deployed in this org: nothing to assert.
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = adminUser.Id, PermissionSetId = adminSets[0].Id);
        }
        GTM_Assessment_Request__c owned = req('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        owned.OwnerId = repA.Id;
        GTM_Assessment_Request__c other = req('Completed', 'Prep Required', 18, Datetime.now(), 'offer-b');
        other.OwnerId = UserInfo.getUserId();
        insert new List<GTM_Assessment_Request__c>{ owned, other };

        GtmAssessmentListController.AssessmentPage plain;
        GtmAssessmentListController.AssessmentPage filtered;
        GtmAssessmentListController.AssessmentQuery q = query();
        q.status = new List<String>{ 'new' };
        System.runAs(adminUser) {
            plain = GtmAssessmentListController.getAssessmentPage(query());
            filtered = GtmAssessmentListController.getAssessmentPage(q);
        }

        Assert.areEqual(new Set<Id>{ owned.Id, other.Id }, ids(plain), 'View-all sees requests owned by anyone');
        Assert.areEqual(new Set<Id>{ owned.Id }, ids(filtered));
        Assert.areEqual(new List<String>{ 'offer-a', 'offer-b' }, plain.offeringOptions);
    }

    @isTest
    static void repSeesReadoutStatusEvenWhenAnotherUserOwnsTheReadout() {
        // A readout's owner is the Opportunity owner first, so it can differ
        // from the rep who owns the request. The join must still show it,
        // or the row would read "None yet" and invite a duplicate Generate.
        User repA = createRep('gtmld1');
        User dealOwner = createRep('gtmld2');
        GTM_Assessment_Request__c r = req('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');
        r.OwnerId = repA.Id;
        insert r;
        GTM_Readout__c ro = seedReadout(r.Id, 'Pending Approval', null, dealOwner.Id);

        GtmAssessmentListController.AssessmentPage page;
        GtmAssessmentListController.AssessmentQuery q = query();
        q.readout = new List<String>{ 'pending' };
        System.runAs(repA) {
            page = GtmAssessmentListController.getAssessmentPage(q);
        }

        Assert.areEqual(1, page.totalCount);
        Assert.areEqual('Pending Approval', page.rows[0].readoutStatus);
        Assert.areEqual(ro.Id, page.rows[0].readoutId);
    }

    /**
     * Ported from getReadoutsForReview's queue-orphan test. A queue-owned
     * orphan readout must keep its request reachable for every member of that
     * queue, and only for them. The request itself is NOT owned by the queue
     * member (the GTM_Readout_Triage case), so a bare `OwnerId = me` would
     * drop it.
     */
    @isTest
    static void queueMemberSeesRequestBehindQueueOwnedOrphanReadoutButNonMemberDoesNot() {
        Id queueId = ensureTriageQueue();
        User queueMember = createRep('gtmlq1');
        User nonMember = createRep('gtmlq2');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(GroupId = queueId, UserOrGroupId = queueMember.Id);
        }

        // Owned by the test runner, i.e. by neither rep.
        GTM_Assessment_Request__c orphan = seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-orphan');
        GTM_Readout__c ro = seedReadout(orphan.Id, 'Draft', null, queueId);
        // A request with no queue readout must stay invisible to the member.
        GTM_Assessment_Request__c unrelated = seed('New', 'Fast-Track', 30, Datetime.now(), 'offer-a');

        GtmAssessmentListController.AssessmentPage memberView;
        GtmAssessmentListController.AssessmentPage memberFiltered;
        GtmAssessmentListController.AssessmentPage nonMemberView;
        GtmAssessmentListController.AssessmentQuery q = query();
        q.preset = 'ready-to-book';
        q.readout = new List<String>{ 'draft' };
        System.runAs(queueMember) {
            memberView = GtmAssessmentListController.getAssessmentPage(query());
            memberFiltered = GtmAssessmentListController.getAssessmentPage(q);
        }
        System.runAs(nonMember) {
            nonMemberView = GtmAssessmentListController.getAssessmentPage(query());
        }

        Assert.areEqual(new Set<Id>{ orphan.Id }, ids(memberView),
            'A queue member still reaches the request behind a queue-owned orphan readout');
        Assert.areEqual(ro.Id, memberView.rows[0].readoutId);
        Assert.areEqual(new Set<Id>{ orphan.Id }, ids(memberFiltered), 'Filters apply to the orphan arm too');
        Assert.isTrue(memberView.offeringOptions.contains('offer-orphan'));
        Assert.isFalse(ids(memberView).contains(unrelated.Id));
        Assert.areEqual(0, nonMemberView.totalCount, 'A rep outside the queue must not see the orphan');
        Assert.isTrue(nonMemberView.rows.isEmpty());
    }

    // ============================================ account / contact filters
    // (issue assessments-account-filters-apex). Hermetic: each test builds its
    // own Accounts, Contacts and requests; no offering or MA data is assumed.

    private static Account acct(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    private static Contact contactOf(Account a, String lastName) {
        Contact c = new Contact(LastName = lastName, AccountId = a.Id);
        insert c;
        return c;
    }

    private static GTM_Assessment_Request__c seedFor(
        Account a, Contact c, Id ownerId, String status, Datetime submitted
    ) {
        GTM_Assessment_Request__c r = req(status, 'Prep Required', 18, submitted, 'offer-a');
        r.Account__c = a == null ? null : a.Id;
        r.Contact__c = c == null ? null : c.Id;
        if (ownerId != null) { r.OwnerId = ownerId; }
        insert r;
        return r;
    }

    private static List<String> asStrings(List<Id> values) {
        List<String> out = new List<String>();
        for (Id v : values) { out.add(String.valueOf(v)); }
        return out;
    }

    private static Set<String> optionValues(List<GtmAssessmentListController.FilterOption> options) {
        Set<String> out = new Set<String>();
        for (GtmAssessmentListController.FilterOption o : options) { out.add(o.value); }
        return out;
    }

    private static Set<Id> pageIds(GtmAssessmentListController.AssessmentQuery q) {
        return ids(GtmAssessmentListController.getAssessmentPage(q));
    }

    @isTest
    static void accountFilterNarrowsRowsAndOrsWithinTheFilter() {
        Account a1 = acct('Acct One ' + (++seq));
        Account a2 = acct('Acct Two ' + (++seq));
        Account a3 = acct('Acct Three ' + (++seq));
        GTM_Assessment_Request__c r1 = seedFor(a1, null, null, 'New', Datetime.now());
        GTM_Assessment_Request__c r2 = seedFor(a2, null, null, 'New', Datetime.now());
        seedFor(a3, null, null, 'New', Datetime.now());
        seedFor(null, null, null, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery q = query();
        q.accountIds = new List<String>{ String.valueOf(a1.Id) };
        Assert.areEqual(new Set<Id>{ r1.Id }, pageIds(q));

        q.accountIds = new List<String>{ String.valueOf(a1.Id), String.valueOf(a2.Id) };
        GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(q);
        Assert.areEqual(new Set<Id>{ r1.Id, r2.Id }, ids(page));
        Assert.areEqual(2, page.totalCount);
    }

    @isTest
    static void contactFilterNarrowsRows() {
        Account a = acct('Acct C ' + (++seq));
        Contact c1 = contactOf(a, 'Alpha' + seq);
        Contact c2 = contactOf(a, 'Beta' + seq);
        GTM_Assessment_Request__c r1 = seedFor(a, c1, null, 'New', Datetime.now());
        seedFor(a, c2, null, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery q = query();
        q.contactIds = new List<String>{ String.valueOf(c1.Id) };
        Assert.areEqual(new Set<Id>{ r1.Id }, pageIds(q));
    }

    @isTest
    static void accountAndContactAreAndedTogether() {
        Account a1 = acct('Acct AND1 ' + (++seq));
        Account a2 = acct('Acct AND2 ' + (++seq));
        Contact c1 = contactOf(a1, 'And' + seq);
        Contact c2 = contactOf(a2, 'And' + (++seq));
        GTM_Assessment_Request__c both = seedFor(a1, c1, null, 'New', Datetime.now());
        seedFor(a1, c2, null, 'New', Datetime.now());
        seedFor(a2, c1, null, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery q = query();
        q.accountIds = new List<String>{ String.valueOf(a1.Id) };
        q.contactIds = new List<String>{ String.valueOf(c1.Id) };
        Assert.areEqual(new Set<Id>{ both.Id }, pageIds(q));
    }

    @isTest
    static void accountFilterIsAndedWithStatusAndDateRange() {
        Account a = acct('Acct Combo ' + (++seq));
        Account other = acct('Acct Other ' + (++seq));
        GTM_Assessment_Request__c hit = seedFor(a, null, null, 'New', Datetime.now());
        seedFor(a, null, null, 'Contacted', Datetime.now());
        seedFor(a, null, null, 'New', Datetime.now().addDays(-40));
        seedFor(other, null, null, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery q = query();
        q.accountIds = new List<String>{ String.valueOf(a.Id) };
        q.status = new List<String>{ 'new' };
        q.range = '7';
        Assert.areEqual(new Set<Id>{ hit.Id }, pageIds(q));
    }

    @isTest
    static void invalidIdsAreDroppedAndAllInvalidNonEmptyListReturnsZeroRows() {
        Account a = acct('Acct Valid ' + (++seq));
        Contact c = contactOf(a, 'Wrongtype' + seq);
        GTM_Assessment_Request__c r = seedFor(a, c, null, 'New', Datetime.now());
        seedBasic();

        GtmAssessmentListController.AssessmentQuery q = query();
        q.accountIds = new List<String>{ 'not-an-id', String.valueOf(a.Id), null, '' };
        Assert.areEqual(new Set<Id>{ r.Id }, pageIds(q), 'A valid id with junk beside it still filters');

        q.accountIds = new List<String>{ 'not-an-id', 'x\' OR Id != \'' };
        Assert.areEqual(0, GtmAssessmentListController.getAssessmentPage(q).totalCount,
            'Non-empty but all-invalid must be zero rows, never unfiltered');

        q.accountIds = new List<String>{ String.valueOf(c.Id) };
        Assert.areEqual(0, GtmAssessmentListController.getAssessmentPage(q).totalCount,
            'A Contact id in accountIds is the wrong type and therefore invalid');

        q.accountIds = null;
        q.contactIds = new List<String>{ String.valueOf(a.Id) };
        Assert.areEqual(0, GtmAssessmentListController.getAssessmentPage(q).totalCount,
            'An Account id in contactIds is the wrong type and therefore invalid');

        q.contactIds = new List<String>();
        Assert.areEqual(2, GtmAssessmentListController.getAssessmentPage(q).totalCount, 'Empty list = no filter');
        q.contactIds = null;
        Assert.areEqual(2, GtmAssessmentListController.getAssessmentPage(q).totalCount, 'Null list = no filter');
    }

    @isTest
    static void idFilterListsAreCappedAtFifty() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 51; i++) { accounts.add(new Account(Name = 'Cap ' + i + ' ' + (++seq))); }
        insert accounts;
        GTM_Assessment_Request__c first = seedFor(accounts[0], null, null, 'New', Datetime.now());
        seedFor(accounts[50], null, null, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery q = query();
        q.accountIds = new List<String>();
        for (Account a : accounts) { q.accountIds.add(String.valueOf(a.Id)); }

        Assert.areEqual(new Set<Id>{ first.Id }, pageIds(q), 'Only the first 50 ids are honoured');
    }

    @isTest
    static void repNeverSeesAnotherRepsRequestsThroughTheFilters() {
        User repA = createRep('gtmfa1');
        User repB = createRep('gtmfb1');
        Account shared = acct('Acct Shared ' + (++seq));
        Contact sharedContact = contactOf(shared, 'Shared' + seq);
        Account onlyB = acct('Acct OnlyB ' + (++seq));
        GTM_Assessment_Request__c ra = seedFor(shared, sharedContact, repA.Id, 'New', Datetime.now());
        GTM_Assessment_Request__c rb = seedFor(shared, sharedContact, repB.Id, 'New', Datetime.now());
        seedFor(onlyB, null, repB.Id, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery byAccount = query();
        byAccount.accountIds = new List<String>{ String.valueOf(shared.Id) };
        GtmAssessmentListController.AssessmentQuery byContact = query();
        byContact.contactIds = new List<String>{ String.valueOf(sharedContact.Id) };
        GtmAssessmentListController.AssessmentQuery byB = query();
        byB.accountIds = new List<String>{ String.valueOf(onlyB.Id) };

        Set<Id> viaAccount;
        Set<Id> viaContact;
        Set<Id> viaOtherRepsAccount;
        List<GtmAssessmentListController.FilterOption> accountOptions;
        List<GtmAssessmentListController.FilterOption> contactOptions;
        List<GtmAssessmentListController.FilterOption> included;
        System.runAs(repA) {
            viaAccount = pageIds(byAccount);
            viaContact = pageIds(byContact);
            viaOtherRepsAccount = pageIds(byB);
            accountOptions = GtmAssessmentListController.getAssessmentFilterOptions('account', null, null);
            contactOptions = GtmAssessmentListController.getAssessmentFilterOptions('contact', null, null);
            included = GtmAssessmentListController.getAssessmentFilterOptions(
                'account', null, new List<String>{ String.valueOf(onlyB.Id) }
            );
        }

        Assert.areEqual(new Set<Id>{ ra.Id }, viaAccount, 'Filtering by a shared account never reveals rep B\'s request');
        Assert.isFalse(viaAccount.contains(rb.Id));
        Assert.areEqual(new Set<Id>{ ra.Id }, viaContact);
        Assert.areEqual(0, viaOtherRepsAccount.size());
        Assert.areEqual(new Set<String>{ String.valueOf(shared.Id) }, optionValues(accountOptions),
            'Rep A gets only the account behind A\'s own request');
        Assert.areEqual(new Set<String>{ String.valueOf(sharedContact.Id) }, optionValues(contactOptions));
        Assert.isTrue(included.size() == 1 && included[0].value == String.valueOf(shared.Id),
            'includeIds cannot smuggle in a party only another rep can see');
    }

    @isTest
    static void viewAllUserSeesEveryRequestAndPartyThroughTheFilters() {
        User repA = createRep('gtmfc1');
        User adminUser = createRep('gtmfc2');
        List<PermissionSet> adminSets = [
            SELECT Id FROM PermissionSet WHERE Name = 'GTM_Offering_Admin' LIMIT 1
        ];
        if (adminSets.isEmpty()) {
            return; // Permission set not deployed in this org: nothing to assert.
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = adminUser.Id, PermissionSetId = adminSets[0].Id);
        }
        Account a = acct('Acct ViewAll ' + (++seq));
        GTM_Assessment_Request__c r = seedFor(a, null, repA.Id, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery q = query();
        q.accountIds = new List<String>{ String.valueOf(a.Id) };
        Set<Id> rows;
        List<GtmAssessmentListController.FilterOption> options;
        System.runAs(adminUser) {
            rows = pageIds(q);
            options = GtmAssessmentListController.getAssessmentFilterOptions('account', null, null);
        }
        Assert.areEqual(new Set<Id>{ r.Id }, rows);
        Assert.isTrue(optionValues(options).contains(String.valueOf(a.Id)));
    }

    @isTest
    static void queueOrphanArmAppliesToFilteredRowsAndOptions() {
        Id queueId = ensureTriageQueue();
        User queueMember = createRep('gtmfq1');
        User nonMember = createRep('gtmfq2');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(GroupId = queueId, UserOrGroupId = queueMember.Id);
        }
        Account orphanAcct = acct('Acct Orphan ' + (++seq));
        Contact orphanContact = contactOf(orphanAcct, 'Orphan' + seq);
        Account otherAcct = acct('Acct Unrelated ' + (++seq));
        GTM_Assessment_Request__c orphan = seedFor(orphanAcct, orphanContact, null, 'New', Datetime.now());
        seedReadout(orphan.Id, 'Draft', null, queueId);
        seedFor(otherAcct, null, null, 'New', Datetime.now());

        GtmAssessmentListController.AssessmentQuery q = query();
        q.accountIds = new List<String>{ String.valueOf(orphanAcct.Id) };
        GtmAssessmentListController.AssessmentQuery qOther = query();
        qOther.accountIds = new List<String>{ String.valueOf(otherAcct.Id) };

        Set<Id> memberRows;
        Set<Id> memberOtherRows;
        List<GtmAssessmentListController.FilterOption> memberAccounts;
        List<GtmAssessmentListController.FilterOption> memberContacts;
        List<GtmAssessmentListController.FilterOption> nonMemberAccounts;
        Set<Id> nonMemberRows;
        System.runAs(queueMember) {
            memberRows = pageIds(q);
            memberOtherRows = pageIds(qOther);
            memberAccounts = GtmAssessmentListController.getAssessmentFilterOptions('account', null, null);
            memberContacts = GtmAssessmentListController.getAssessmentFilterOptions('contact', null, null);
        }
        System.runAs(nonMember) {
            nonMemberRows = pageIds(q);
            nonMemberAccounts = GtmAssessmentListController.getAssessmentFilterOptions('account', null, null);
        }

        Assert.areEqual(new Set<Id>{ orphan.Id }, memberRows);
        Assert.areEqual(0, memberOtherRows.size(), 'An account behind no queue readout stays invisible');
        Assert.areEqual(new Set<String>{ String.valueOf(orphanAcct.Id) }, optionValues(memberAccounts));
        Assert.areEqual(new Set<String>{ String.valueOf(orphanContact.Id) }, optionValues(memberContacts));
        Assert.areEqual(0, nonMemberRows.size());
        Assert.areEqual(0, nonMemberAccounts.size());
    }

    // ------------------------------------------------------- options method

    @isTest
    static void optionsListOnlyPartiesThatHaveAVisibleRequest() {
        Account withReq = acct('Acct Has ' + (++seq));
        Account noReq = acct('Acct None ' + (++seq));
        Contact cWith = contactOf(withReq, 'Has' + seq);
        Contact cWithout = contactOf(noReq, 'Without' + seq);
        seedFor(withReq, cWith, null, 'New', Datetime.now());
        seedBasic(); // a request with no account or contact at all

        Set<String> accountValues = optionValues(
            GtmAssessmentListController.getAssessmentFilterOptions('account', null, null));
        List<GtmAssessmentListController.FilterOption> contacts =
            GtmAssessmentListController.getAssessmentFilterOptions('contact', '', null);

        Assert.areEqual(new Set<String>{ String.valueOf(withReq.Id) }, accountValues);
        Assert.isFalse(accountValues.contains(String.valueOf(noReq.Id)), 'No request = never an option');
        Assert.areEqual(1, contacts.size());
        Assert.areEqual(String.valueOf(cWith.Id), contacts[0].value);
        Assert.areNotEqual(String.valueOf(cWithout.Id), contacts[0].value);
        Assert.areEqual(cWith.LastName, contacts[0].label);
        Assert.areEqual(withReq.Name, contacts[0].sublabel, 'Contact sublabel is the account name');
    }

    @isTest
    static void optionsSearchMatchesNoMatchAndIsCaseInsensitive() {
        Account hit = acct('Zephyrine Holdings ' + (++seq));
        Account miss = acct('Quokka Partners ' + (++seq));
        seedFor(hit, null, null, 'New', Datetime.now());
        seedFor(miss, null, null, 'New', Datetime.now());

        Assert.areEqual(new Set<String>{ String.valueOf(hit.Id) }, optionValues(
            GtmAssessmentListController.getAssessmentFilterOptions('account', '  zEPHyr ', null)));
        Assert.isTrue(GtmAssessmentListController.getAssessmentFilterOptions(
            'account', 'no-such-party-zzzz', null).isEmpty());
    }

    @isTest
    static void likeWildcardsInTheSearchTermAreNeutral() {
        Account pct = acct('Wild%Card ' + (++seq));
        Account under = acct('Wild_Card ' + (++seq));
        Account plain = acct('WildXCard ' + (++seq));
        for (Account a : new List<Account>{ pct, under, plain }) {
            seedFor(a, null, null, 'New', Datetime.now());
        }

        Assert.areEqual(new Set<String>{ String.valueOf(pct.Id) }, optionValues(
            GtmAssessmentListController.getAssessmentFilterOptions('account', 'Wild%Card', null)),
            'A percent sign matches only a literal percent sign');
        Assert.areEqual(new Set<String>{ String.valueOf(under.Id) }, optionValues(
            GtmAssessmentListController.getAssessmentFilterOptions('account', 'Wild_Card', null)),
            'An underscore matches only a literal underscore');
        Assert.areEqual(new Set<String>{ String.valueOf(pct.Id) }, optionValues(
            GtmAssessmentListController.getAssessmentFilterOptions('account', '%', null)),
            'A lone percent must not match everything');
        Assert.isTrue(GtmAssessmentListController.getAssessmentFilterOptions('account', '\\', null).isEmpty(),
            'A lone backslash is inert');
    }

    @isTest
    static void injectionAttemptsInTheSearchTermAreInertText() {
        Account a = acct('Acct Inject ' + (++seq));
        seedFor(a, null, null, 'New', Datetime.now());

        List<String> attacks = new List<String>{
            'x\' OR Name != \'',
            '%\' OR Id != null OR Name LIKE \'%',
            '\'; DELETE',
            'x) OR (Id != null'
        };
        for (String attack : attacks) {
            Assert.isTrue(GtmAssessmentListController.getAssessmentFilterOptions('account', attack, null).isEmpty(),
                'Injection text must match nothing: ' + attack);
            Assert.isTrue(GtmAssessmentListController.getAssessmentFilterOptions('contact', attack, null).isEmpty());
        }
    }

    @isTest
    static void overlongSearchTermIsTruncatedNotRejected() {
        Account a = acct('Truncate Me ' + (++seq));
        seedFor(a, null, null, 'New', Datetime.now());
        String longTerm = 'Truncate Me ' + 'y'.repeat(200);
        // 80 chars kept: "Truncate Me " + 68 'y' does not match the name, so empty, but no exception.
        Assert.isTrue(GtmAssessmentListController.getAssessmentFilterOptions('account', longTerm, null).isEmpty());
    }

    @isTest
    static void optionsAreLimitedToFiftyOrderedByNameAndIncludeIdsAddsRestoredValues() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 55; i++) {
            accounts.add(new Account(Name = 'Lim ' + String.valueOf(1000 + i).substring(1) + ' ' + (++seq)));
        }
        insert accounts;
        List<GTM_Assessment_Request__c> requests = new List<GTM_Assessment_Request__c>();
        for (Account a : accounts) {
            GTM_Assessment_Request__c r = req('New', 'Prep Required', 18, Datetime.now(), 'offer-a');
            r.Account__c = a.Id;
            requests.add(r);
        }
        insert requests;

        List<GtmAssessmentListController.FilterOption> blank =
            GtmAssessmentListController.getAssessmentFilterOptions('account', null, null);
        Assert.areEqual(50, blank.size(), 'LIMIT 50');
        Assert.areEqual(accounts[0].Name, blank[0].label, 'Alphabetical: first');
        Assert.areEqual(accounts[49].Name, blank[49].label, 'Alphabetical: fiftieth');
        Assert.isFalse(optionValues(blank).contains(String.valueOf(accounts[54].Id)));

        List<GtmAssessmentListController.FilterOption> restored =
            GtmAssessmentListController.getAssessmentFilterOptions(
                'account', null, new List<String>{ String.valueOf(accounts[54].Id), 'bogus', String.valueOf(accounts[0].Id) }
            );
        Assert.areEqual(51, restored.size(), 'Restored value added once; duplicate and bogus ignored');
        Assert.isTrue(optionValues(restored).contains(String.valueOf(accounts[54].Id)));
        Assert.areEqual(accounts[54].Name, restored[50].label, 'The restored value carries its label');
    }

    @isTest
    static void includeIdsSkipsWrongTypeAndPartiesWithoutARequest() {
        Account withReq = acct('Acct Inc ' + (++seq));
        Account noReq = acct('Acct IncNone ' + (++seq));
        Contact c = contactOf(withReq, 'Inc' + seq);
        seedFor(withReq, c, null, 'New', Datetime.now());

        List<GtmAssessmentListController.FilterOption> out =
            GtmAssessmentListController.getAssessmentFilterOptions('account', 'no-such-party-zzzz', new List<String>{
                String.valueOf(withReq.Id), String.valueOf(noReq.Id), String.valueOf(c.Id)
            });

        Assert.areEqual(1, out.size(), 'Only the visible, correctly typed id is returned');
        Assert.areEqual(String.valueOf(withReq.Id), out[0].value);
        Assert.areEqual(withReq.Name, out[0].label);
    }

    @isTest
    static void unknownKindThrowsAPlainAuraHandledException() {
        for (String kind : new List<String>{ 'offering', '', null, 'account; DROP' }) {
            try {
                GtmAssessmentListController.getAssessmentFilterOptions(kind, null, null);
                Assert.fail('Expected an AuraHandledException for kind: ' + kind);
            } catch (AuraHandledException e) {
                Assert.areEqual('Unsupported filter kind.', e.getMessage());
            }
        }
    }

    // ===================== readout key totality and vocabulary drift (A1, A2)

    @isTest
    static void approvedAndSentReadoutIsFoundByItsOwnKeyAndNoOther() {
        GTM_Assessment_Request__c none = seedBasic();
        GTM_Assessment_Request__c draft = seedBasic();
        GTM_Assessment_Request__c pending = seedBasic();
        GTM_Assessment_Request__c unsent = seedBasic();
        GTM_Assessment_Request__c sent = seedBasic();
        GTM_Assessment_Request__c pub = seedBasic();
        seedReadout(draft.Id, 'Draft', null, null);
        seedReadout(pending.Id, 'Pending Approval', null, null);
        seedReadout(unsent.Id, 'Approved', null, null);
        seedReadout(sent.Id, 'Approved', Datetime.now(), null);
        seedReadout(pub.Id, 'Published', null, null);

        Assert.areEqual(new Set<Id>{ sent.Id }, ids(byReadout('approved-sent')));
        Assert.areEqual(new Set<Id>{ none.Id }, ids(byReadout('none')));
        Assert.areEqual(new Set<Id>{ draft.Id }, ids(byReadout('draft')));
        Assert.areEqual(new Set<Id>{ pending.Id }, ids(byReadout('pending')));
        Assert.areEqual(new Set<Id>{ unsent.Id }, ids(byReadout('approved-unsent')));
        Assert.areEqual(new Set<Id>{ pub.Id }, ids(byReadout('published')));

        for (GtmAssessmentListController.AssessmentRow r
             : GtmAssessmentListController.getAssessmentPage(query()).rows) {
            Assert.isTrue(String.isNotBlank(r.readoutKey), 'Every row carries exactly one readout key');
            if (r.recordId == sent.Id) { Assert.areEqual('approved-sent', r.readoutKey); }
            if (r.recordId == unsent.Id) { Assert.areEqual('approved-unsent', r.readoutKey); }
        }
    }

    @isTest
    static void everyReadoutStateMapsToExactlyOneKey() {
        Set<String> keys = new Set<String>{ 'none', 'draft', 'pending', 'approved-unsent', 'approved-sent', 'published' };
        Map<String, String> seen = new Map<String, String>();
        List<String> states = new List<String>{ null };
        for (Schema.PicklistEntry pe : GTM_Readout__c.Status__c.getDescribe().getPicklistValues()) {
            states.add(pe.getValue());
        }
        Set<String> used = new Set<String>();
        for (String state : states) {
            List<Boolean> sentFlags = state == 'Approved' ? new List<Boolean>{ false, true } : new List<Boolean>{ false };
            for (Boolean sent : sentFlags) {
                String key = GtmAssessmentListController.readoutKeyFor(state, sent);
                Assert.isTrue(keys.contains(key), 'State ' + state + '/' + sent + ' must map to a real key, got: ' + key);
                Assert.isTrue(used.add(key), 'Two states share the key ' + key);
            }
        }
        Assert.areEqual(keys, used, 'Every key is reachable from exactly one state');
    }

    @isTest
    static void uiFilterVocabulariesMatchThePicklistsTheyFilter() {
        Set<String> requestStatuses = new Set<String>();
        for (Schema.PicklistEntry pe : GTM_Assessment_Request__c.Status__c.getDescribe().getPicklistValues()) {
            requestStatuses.add(pe.getValue());
        }
        Set<String> tiers = new Set<String>();
        for (Schema.PicklistEntry pe : GTM_Assessment_Request__c.Assessment_Tier__c.getDescribe().getPicklistValues()) {
            tiers.add(pe.getValue());
        }
        // The UI keys reach the class only through the query, so exercise them:
        // a key the class accepts must select exactly the request with that value.
        Map<String, String> statusByKey = new Map<String, String>{
            'new' => 'New', 'contacted' => 'Contacted', 'scheduled' => 'Scheduled',
            'completed' => 'Completed', 'no-show' => 'No Show'
        };
        Map<String, String> tierByKey = new Map<String, String>{
            'fast-track' => 'Fast-Track', 'accelerator-ready' => 'Accelerator-Ready',
            'prep-required' => 'Prep Required', 'discovery-first' => 'Discovery First'
        };
        for (String key : statusByKey.keySet()) {
            Assert.isTrue(requestStatuses.contains(statusByKey.get(key)),
                'Status option "' + statusByKey.get(key) + '" is not a Status__c picklist value');
        }
        for (String key : tierByKey.keySet()) {
            Assert.isTrue(tiers.contains(tierByKey.get(key)),
                'Tier option "' + tierByKey.get(key) + '" is not an Assessment_Tier__c picklist value');
        }
        // And the class maps each UI key to that value: one request per value, one hit per key.
        Map<String, GTM_Assessment_Request__c> byStatus = new Map<String, GTM_Assessment_Request__c>();
        for (String label : statusByKey.values()) {
            byStatus.put(label, seed(label, null, null, Datetime.now(), 'offer-a'));
        }
        for (String key : statusByKey.keySet()) {
            GtmAssessmentListController.AssessmentQuery q = query();
            q.status = new List<String>{ key };
            Assert.areEqual(new Set<Id>{ byStatus.get(statusByKey.get(key)).Id }, pageIds(q),
                'Status key ' + key + ' must select exactly the ' + statusByKey.get(key) + ' request');
        }
        for (String label : tierByKey.values()) {
            seed('New', label, 10, Datetime.now(), 'offer-a');
        }
        for (String key : tierByKey.keySet()) {
            GtmAssessmentListController.AssessmentQuery q = query();
            q.tier = new List<String>{ key };
            GtmAssessmentListController.AssessmentPage page = GtmAssessmentListController.getAssessmentPage(q);
            Assert.areEqual(1, page.totalCount, 'Tier key ' + key + ' selects exactly one request');
            Assert.areEqual(tierByKey.get(key), page.rows[0].tier);
        }
    }
}
