@IsTest
private class GtmLinkStageServiceTest {

    // ---- helpers -------------------------------------------------------

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Stage ' + alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static void assignAdmin(User u) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'GTM_Offering_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    private static GTM_Saved_Configuration__c newLink(Id ownerId, String stage, Boolean active) {
        return new GTM_Saved_Configuration__c(
            OwnerId = ownerId,
            Offering__c = 'migration-accelerator',
            Company__c = 'Co ' + stage,
            Generated_URL__c = 'https://example.com/' + stage,
            Presentation_Stage__c = stage,
            Active__c = active
        );
    }

    private static SObject newEvent(Id ownerId, Id linkId, String type, String session) {
        // Dynamic construction: no compile-time reference to Saved_Configuration__c.
        SObject e = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        e.put('OwnerId', ownerId);
        e.put('Saved_Configuration__c', linkId);
        e.put('Event_Type__c', type);
        if (session != null) { e.put('Session_Id__c', session); }
        return e;
    }

    private static SObject newRequest(Id ownerId, Id linkId) {
        SObject r = Schema.getGlobalDescribe().get('GTM_Assessment_Request__c').newSObject();
        r.put('OwnerId', ownerId);
        r.put('Requester_Name__c', 'Alex Rivera');
        r.put('Requester_Email__c', 'alex@example.com');
        r.put('Company__c', 'Acme');
        r.put('Status__c', 'New');
        r.put('Saved_Configuration__c', linkId);
        return r;
    }

    private static Set<Id> asSet(List<Id> ids) {
        return new Set<Id>(ids);
    }

    // ---- every key + boundaries ----------------------------------------

    @IsTest
    static void everyKeyMatchesItsDefinitionIncludingBoundaries() {
        User rep = createUser('stgrep1');
        User other = createUser('stgrep2');
        // Whole seconds: CreatedDate is stored at second precision, so a
        // sub-second "now" would make the exact-48h boundary meaningless.
        Datetime now = Datetime.newInstance((System.now().getTime() / 1000) * 1000);
        GtmLinkStageService.nowOverride = now;

        Map<String, GTM_Saved_Configuration__c> links = new Map<String, GTM_Saved_Configuration__c>();
        for (String n : new List<String>{
            'none', 'oneView', 'twoSess', 'sameSess', 'nullSess', 'boundary', 'over', 'noise',
            'resume', 'openedNoPv', 'dropoff', 'submittedEvt', 'request', 'submittedHot', 'inactive'
        }) {
            links.put(n, newLink(rep.Id, 'Sent', n != 'inactive'));
        }
        // Excluded from every key.
        links.put('repDirect', newLink(rep.Id, 'Rep_Direct', true));
        links.put('draft', newLink(rep.Id, 'Draft', true));
        links.put('nullStage', newLink(rep.Id, null, true));
        // Another rep's link: never visible to `rep`.
        links.put('otherRep', newLink(other.Id, 'Sent', true));
        insert links.values();

        List<SObject> events = new List<SObject>();
        Map<Integer, Datetime> dated = new Map<Integer, Datetime>(); // index in `events` -> CreatedDate
        // helper closure substitute: add(name, type, session, hoursAgoTimes)
        // hoursAgo given in seconds so 48h and 48h+1s are expressible.
        Long h1 = 3600L; Long h48 = 48L * 3600L;
        addEv(events, dated, rep, links, now, 'oneView', 'Page View', 's1', h1);
        addEv(events, dated, rep, links, now, 'twoSess', 'Page View', 's1', 2 * h1);
        addEv(events, dated, rep, links, now, 'twoSess', 'Page View', 's2', h1);
        addEv(events, dated, rep, links, now, 'sameSess', 'Page View', 's1', 2 * h1);
        addEv(events, dated, rep, links, now, 'sameSess', 'Page View', 's1', h1);
        addEv(events, dated, rep, links, now, 'nullSess', 'Page View', null, 2 * h1);
        addEv(events, dated, rep, links, now, 'nullSess', 'Page View', null, h1);
        addEv(events, dated, rep, links, now, 'boundary', 'Page View', 'b1', h48 + 24 * h1);
        addEv(events, dated, rep, links, now, 'boundary', 'Page View', 'b2', h48);        // exactly 48h
        addEv(events, dated, rep, links, now, 'over', 'Page View', 'o1', h48 + 24 * h1);
        addEv(events, dated, rep, links, now, 'over', 'Page View', 'o2', h48 + 1);        // 48h + 1s
        // Two OLD page views, plus fresh in-session noise that must not refresh "recent".
        addEv(events, dated, rep, links, now, 'noise', 'Page View', 'n1', 100 * h1);
        addEv(events, dated, rep, links, now, 'noise', 'Page View', 'n2', 99 * h1);
        addEv(events, dated, rep, links, now, 'noise', 'Section Viewed', 'n2', h1);
        addEv(events, dated, rep, links, now, 'noise', 'CTA Clicked', 'n2', h1);
        addEv(events, dated, rep, links, now, 'noise', 'Session End', 'n2', h1);
        // Two old page views + a recent Form Resumed: resume refreshes recency and opens the form.
        addEv(events, dated, rep, links, now, 'resume', 'Page View', 'r1', 100 * h1);
        addEv(events, dated, rep, links, now, 'resume', 'Page View', 'r2', 99 * h1);
        addEv(events, dated, rep, links, now, 'resume', 'Form Resumed', 'r3', h1);
        addEv(events, dated, rep, links, now, 'openedNoPv', 'Form Opened', 'f1', h1);
        addEv(events, dated, rep, links, now, 'dropoff', 'Form Opened', 'd1', h1);
        addEv(events, dated, rep, links, now, 'dropoff', 'Drop-off', 'd1', h1);
        addEv(events, dated, rep, links, now, 'submittedEvt', 'Form Opened', 'e1', h1);
        addEv(events, dated, rep, links, now, 'submittedEvt', 'Form Submitted', 'e1', h1);
        addEv(events, dated, rep, links, now, 'submittedHot', 'Page View', 'h1', 2 * h1);
        addEv(events, dated, rep, links, now, 'submittedHot', 'Page View', 'h2', h1);
        addEv(events, dated, rep, links, now, 'submittedHot', 'Form Submitted', 'h2', h1);
        addEv(events, dated, rep, links, now, 'inactive', 'Page View', 'i1', h1);
        // Excluded / foreign links carry activity too.
        addEv(events, dated, rep, links, now, 'repDirect', 'Form Submitted', 'x1', h1);
        addEv(events, dated, rep, links, now, 'draft', 'Form Opened', 'x2', h1);
        addEv(events, dated, rep, links, now, 'nullStage', 'Page View', 'x3', h1);
        addEv(events, dated, other, links, now, 'otherRep', 'Form Opened', 'x4', h1);
        insert events;
        for (Integer i : dated.keySet()) {
            Test.setCreatedDate(events[i].Id, dated.get(i));
        }

        // Request with no events at all; requests on excluded links.
        insert new List<SObject>{
            newRequest(rep.Id, links.get('request').Id),
            newRequest(rep.Id, links.get('repDirect').Id)
        };

        GtmLinkStageService.StageCounts counts;
        Map<String, Set<Id>> ids = new Map<String, Set<Id>>();
        System.runAs(rep) {
            Test.startTest();
            counts = GtmLinkStageService.getStageCounts();
            for (String k : GtmLinkStageService.STAGE_KEYS) {
                ids.put(k, asSet(GtmLinkStageService.getLinkIdsForStage(k)));
            }
            Test.stopTest();
        }

        Map<String, List<String>> expected = new Map<String, List<String>>{
            'engaged' => new List<String>{
                'oneView', 'twoSess', 'sameSess', 'nullSess', 'boundary', 'over', 'noise', 'resume',
                'openedNoPv', 'dropoff', 'submittedEvt', 'request', 'submittedHot', 'inactive'
            },
            'started' => new List<String>{
                'resume', 'openedNoPv', 'dropoff', 'submittedEvt', 'request', 'submittedHot'
            },
            'submitted' => new List<String>{ 'submittedEvt', 'request', 'submittedHot' },
            'quiet' => new List<String>{ 'resume', 'openedNoPv', 'dropoff' },
            'hot' => new List<String>{ 'twoSess', 'nullSess', 'boundary', 'resume', 'submittedHot' },
            'not_opened' => new List<String>{ 'none' }
        };
        for (String k : expected.keySet()) {
            Set<Id> want = new Set<Id>();
            for (String n : expected.get(k)) { want.add(links.get(n).Id); }
            Assert.areEqual(want, ids.get(k), 'membership of ' + k);
        }
        Assert.areEqual(15, ids.get('sent').size(), 'sent = the 15 owned, non-excluded links (inactive included)');
        Assert.isTrue(ids.get('sent').contains(links.get('inactive').Id));
        Assert.isFalse(ids.get('sent').contains(links.get('repDirect').Id));
        Assert.isFalse(ids.get('sent').contains(links.get('draft').Id));
        Assert.isFalse(ids.get('sent').contains(links.get('nullStage').Id));
        Assert.isFalse(ids.get('sent').contains(links.get('otherRep').Id));

        // Explicit boundary + noise + request assertions.
        Assert.isTrue(ids.get('hot').contains(links.get('boundary').Id), 'exactly 48h old is included');
        Assert.isFalse(ids.get('hot').contains(links.get('over').Id), '48h + 1s is excluded');
        Assert.isFalse(ids.get('hot').contains(links.get('sameSess').Id), 'same session twice is one visit');
        Assert.isFalse(ids.get('hot').contains(links.get('oneView').Id), 'a single view is not hot');
        Assert.isFalse(ids.get('hot').contains(links.get('noise').Id), 'in-session noise never refreshes recency');
        Assert.isTrue(ids.get('hot').contains(links.get('nullSess').Id), 'null-session views each count');
        Assert.isTrue(ids.get('submitted').contains(links.get('request').Id), 'request without event is submitted');
        Assert.isFalse(ids.get('quiet').contains(links.get('request').Id), 'request without event is not quiet');
        Assert.isTrue(ids.get('quiet').contains(links.get('openedNoPv').Id), 'form opened without page view is quiet');
        Assert.isFalse(ids.get('not_opened').contains(links.get('request').Id));

        // Counts equal list sizes for every key, and the invariants hold.
        Assert.areEqual(ids.get('sent').size(), counts.sent);
        Assert.areEqual(ids.get('engaged').size(), counts.engaged);
        Assert.areEqual(ids.get('started').size(), counts.started);
        Assert.areEqual(ids.get('submitted').size(), counts.submitted);
        Assert.areEqual(ids.get('quiet').size(), counts.quiet);
        Assert.areEqual(ids.get('hot').size(), counts.hot);
        Assert.areEqual(ids.get('not_opened').size(), counts.notOpened);
        Assert.areEqual(counts.sent, counts.engaged + counts.notOpened);
        Assert.isTrue(counts.submitted <= counts.started && counts.started <= counts.engaged
            && counts.engaged <= counts.sent);
        Assert.isFalse(counts.truncated);
    }

    private static void addEv(
        List<SObject> events, Map<Integer, Datetime> dated, User owner,
        Map<String, GTM_Saved_Configuration__c> links, Datetime now,
        String linkName, String type, String session, Long secondsAgo
    ) {
        events.add(newEvent(owner.Id, links.get(linkName).Id, type, session));
        dated.put(events.size() - 1, now.addSeconds(-Integer.valueOf(secondsAgo)));
    }

    // ---- scoping -------------------------------------------------------

    @IsTest
    static void repsSeeOnlyTheirOwnLinksAndAdminSeesAll() {
        User repA = createUser('stgowda');
        User repB = createUser('stgowdb');
        User admin = createUser('stgowdc');
        assignAdmin(admin);

        GTM_Saved_Configuration__c a = newLink(repA.Id, 'Sent', true);
        GTM_Saved_Configuration__c b1 = newLink(repB.Id, 'Sent', true);
        GTM_Saved_Configuration__c b2 = newLink(repB.Id, 'Sent', true);
        insert new List<GTM_Saved_Configuration__c>{ a, b1, b2 };
        insert new List<SObject>{
            newEvent(repA.Id, a.Id, 'Form Opened', 'a1'),
            newEvent(repB.Id, b1.Id, 'Form Opened', 'b1'),
            newEvent(repB.Id, b1.Id, 'Form Submitted', 'b1')
        };

        System.runAs(repA) {
            GtmLinkStageService.StageCounts c = GtmLinkStageService.getStageCounts();
            Assert.areEqual(1, c.sent);
            Assert.areEqual(1, c.quiet);
            Assert.areEqual(0, c.submitted, 'repB\'s submission must not leak into repA');
            Assert.areEqual(new Set<Id>{ a.Id }, asSet(GtmLinkStageService.getLinkIdsForStage('sent')));
        }
        System.runAs(repB) {
            GtmLinkStageService.StageCounts c = GtmLinkStageService.getStageCounts();
            Assert.areEqual(2, c.sent);
            Assert.areEqual(1, c.submitted);
            Assert.areEqual(0, c.quiet);
            Assert.areEqual(1, c.notOpened);
        }
        System.runAs(admin) {
            GtmLinkStageService.StageCounts c = GtmLinkStageService.getStageCounts();
            Assert.areEqual(3, c.sent, 'a viewAllRecords holder sees every rep\'s links');
            Assert.areEqual(1, c.quiet);
            Assert.areEqual(1, c.submitted);
            Assert.areEqual(3, GtmLinkStageService.getLinkIdsForStage('sent').size());
        }
    }

    // ---- scale, query budget, truncation --------------------------------

    @IsTest
    static void moreThan200LinksAreCountedWithABoundedQueryCount() {
        User rep = createUser('stgbulk1');
        List<GTM_Saved_Configuration__c> manyLinks = new List<GTM_Saved_Configuration__c>();
        for (Integer i = 0; i < 201; i++) {
            manyLinks.add(newLink(rep.Id, 'Sent', true));
        }
        insert manyLinks;

        System.runAs(rep) {
            Test.startTest();
            Integer before = Limits.getQueries();
            GtmLinkStageService.StageCounts c = GtmLinkStageService.getStageCounts();
            Integer used = Limits.getQueries() - before;
            Test.stopTest();
            Assert.areEqual(201, c.sent, 'no 200 cap');
            Assert.areEqual(201, c.notOpened);
            Assert.areEqual(4, used, 'universe + events + requests + the viewAll permission probe; no per-link queries');
        }
    }

    @IsTest
    static void truncatedFlagIsSetWhenTheUniverseHitsItsCap() {
        User rep = createUser('stgtrunc');
        List<GTM_Saved_Configuration__c> three = new List<GTM_Saved_Configuration__c>();
        for (Integer i = 0; i < 3; i++) {
            three.add(newLink(rep.Id, 'Sent', true));
        }
        insert three;

        System.runAs(rep) {
            GtmLinkStageService.universeLimitOverride = 2;
            GtmLinkStageService.StageCounts capped = GtmLinkStageService.getStageCounts();
            Assert.isTrue(capped.truncated, 'universe reached its cap');
            Assert.areEqual(2, capped.sent);

            GtmLinkStageService.universeLimitOverride = 5;
            GtmLinkStageService.StageCounts full = GtmLinkStageService.getStageCounts();
            Assert.isFalse(full.truncated);
            Assert.areEqual(3, full.sent);
        }
    }

    @IsTest
    static void emptyUniverseReturnsZeros() {
        User rep = createUser('stgempty');
        System.runAs(rep) {
            GtmLinkStageService.StageCounts c = GtmLinkStageService.getStageCounts();
            Assert.areEqual(0, c.sent);
            Assert.areEqual(0, c.notOpened);
            Assert.isFalse(c.truncated);
            Assert.areEqual(0, GtmLinkStageService.getLinkIdsForStage('hot').size());
        }
    }

    // ---- unknown keys + Aura entries -------------------------------------

    @IsTest
    static void unknownOrBlankKeyThrowsWithValidKeysListed() {
        for (String bad : new List<String>{ 'bogus', '', null, 'Quiet' }) {
            try {
                GtmLinkStageService.getLinkIdsForStage(bad);
                Assert.fail('expected IllegalArgumentException for ' + bad);
            } catch (IllegalArgumentException e) {
                Assert.isTrue(e.getMessage().contains('not_opened'), 'message lists valid keys');
            }
            try {
                GtmLinkStageService.getLinkIdsForStageAura(bad);
                Assert.fail('expected AuraHandledException for ' + bad);
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('not_opened'), 'message lists valid keys');
            }
        }
    }

    @IsTest
    static void auraEntriesDelegateToTheSameComputation() {
        User rep = createUser('stgaura');
        GTM_Saved_Configuration__c l = newLink(rep.Id, 'Sent', true);
        insert l;
        insert newEvent(rep.Id, l.Id, 'Form Opened', 'z1');

        System.runAs(rep) {
            GtmLinkStageService.StageCounts c = GtmLinkStageService.getStageCountsAura();
            Assert.areEqual(1, c.quiet);
            Assert.areEqual(
                new List<Id>{ l.Id }, GtmLinkStageService.getLinkIdsForStageAura('quiet')
            );
        }
        Assert.areEqual(7, GtmLinkStageService.STAGE_KEYS.size());
    }

    // ---- link stats (issue pages-tab-table-view) ---------------------------

    private static Map<Id, GtmLinkStageService.LinkStat> statsById(GtmLinkStageService.LinkStatsResult r) {
        Map<Id, GtmLinkStageService.LinkStat> m = new Map<Id, GtmLinkStageService.LinkStat>();
        for (GtmLinkStageService.LinkStat st : r.stats) { m.put(st.linkId, st); }
        return m;
    }

    @IsTest
    static void linkStatsCarryVisitsLastVisitAndFunnelStageConsistentWithIdLists() {
        User rep = createUser('stgstat1');
        Datetime now = Datetime.newInstance((System.now().getTime() / 1000) * 1000);
        GtmLinkStageService.nowOverride = now;

        Map<String, GTM_Saved_Configuration__c> links = new Map<String, GTM_Saved_Configuration__c>();
        for (String n : new List<String>{ 'none', 'viewed', 'twoVisits', 'opened', 'submitted', 'request' }) {
            links.put(n, newLink(rep.Id, 'Sent', true));
        }
        links.put('repDirect', newLink(rep.Id, 'Rep_Direct', true));
        insert links.values();

        List<SObject> events = new List<SObject>();
        Map<Integer, Datetime> dated = new Map<Integer, Datetime>();
        Long h1 = 3600L;
        addEv(events, dated, rep, links, now, 'viewed', 'Page View', 'v1', 5 * h1);
        addEv(events, dated, rep, links, now, 'twoVisits', 'Page View', 't1', 10 * h1);
        addEv(events, dated, rep, links, now, 'twoVisits', 'Page View', null, 2 * h1);
        addEv(events, dated, rep, links, now, 'opened', 'Form Opened', 'o1', h1);
        addEv(events, dated, rep, links, now, 'submitted', 'Form Submitted', 's1', h1);
        insert events;
        for (Integer i : dated.keySet()) {
            Test.setCreatedDate(events[i].Id, dated.get(i));
        }
        insert new List<SObject>{ newRequest(rep.Id, links.get('request').Id) };

        System.runAs(rep) {
            Test.startTest();
            GtmLinkStageService.LinkStatsResult r = GtmLinkStageService.getLinkStats();
            Map<String, Set<Id>> ids = new Map<String, Set<Id>>();
            for (String k : GtmLinkStageService.STAGE_KEYS) {
                ids.put(k, asSet(GtmLinkStageService.getLinkIdsForStage(k)));
            }
            Test.stopTest();

            Assert.isFalse(r.viewAll, 'a rep is not viewAll');
            Assert.isFalse(r.truncated);
            Assert.areEqual(6, r.stats.size(), 'one stat per universe link; Rep_Direct excluded');
            Map<Id, GtmLinkStageService.LinkStat> st = statsById(r);
            Assert.isFalse(st.containsKey(links.get('repDirect').Id));

            Assert.areEqual(0, st.get(links.get('none').Id).visits);
            Assert.isNull(st.get(links.get('none').Id).lastVisitAt);
            Assert.areEqual('not_opened', st.get(links.get('none').Id).funnelStage);
            Assert.areEqual(1, st.get(links.get('viewed').Id).visits);
            Assert.areEqual(now.addSeconds(-Integer.valueOf(5 * h1)), st.get(links.get('viewed').Id).lastVisitAt);
            Assert.areEqual('engaged', st.get(links.get('viewed').Id).funnelStage);
            Assert.areEqual(2, st.get(links.get('twoVisits').Id).visits, 'a null-session view is its own visit');
            Assert.areEqual(now.addSeconds(-Integer.valueOf(2 * h1)), st.get(links.get('twoVisits').Id).lastVisitAt);
            Assert.areEqual('started', st.get(links.get('opened').Id).funnelStage);
            Assert.isNull(st.get(links.get('opened').Id).lastVisitAt, 'Form Opened is not a visit');
            Assert.areEqual('submitted', st.get(links.get('submitted').Id).funnelStage);
            Assert.areEqual('submitted', st.get(links.get('request').Id).funnelStage);

            // funnelStage agrees with the id lists for every link.
            for (GtmLinkStageService.LinkStat s : r.stats) {
                Assert.areEqual(s.funnelStage == 'submitted', ids.get('submitted').contains(s.linkId));
                Assert.areEqual(s.funnelStage == 'submitted' || s.funnelStage == 'started',
                    ids.get('started').contains(s.linkId));
                Assert.areEqual(s.funnelStage != 'not_opened', ids.get('engaged').contains(s.linkId));
                Assert.areEqual(s.funnelStage == 'not_opened', ids.get('not_opened').contains(s.linkId));
            }
        }
    }

    @IsTest
    static void linkStatsAreScopedAndViewAllIsExplicit() {
        User repA = createUser('stgstsa');
        User repB = createUser('stgstsb');
        User admin = createUser('stgstsc');
        assignAdmin(admin);
        GTM_Saved_Configuration__c a = newLink(repA.Id, 'Sent', true);
        GTM_Saved_Configuration__c b = newLink(repB.Id, 'Sent', true);
        insert new List<GTM_Saved_Configuration__c>{ a, b };
        insert newEvent(repB.Id, b.Id, 'Form Submitted', 'b1');

        System.runAs(repA) {
            GtmLinkStageService.LinkStatsResult r = GtmLinkStageService.getLinkStatsAura();
            Assert.isFalse(r.viewAll);
            Assert.areEqual(1, r.stats.size());
            Assert.areEqual(a.Id, r.stats[0].linkId);
            Assert.areEqual('not_opened', r.stats[0].funnelStage, 'repB activity must not leak');
        }
        System.runAs(repB) {
            GtmLinkStageService.LinkStatsResult r = GtmLinkStageService.getLinkStatsAura();
            Assert.areEqual(1, r.stats.size());
            Assert.areEqual('submitted', r.stats[0].funnelStage);
        }
        System.runAs(admin) {
            GtmLinkStageService.LinkStatsResult r = GtmLinkStageService.getLinkStatsAura();
            Assert.isTrue(r.viewAll, 'a viewAllRecords holder is flagged viewAll');
            Assert.areEqual(2, r.stats.size());
        }
    }

    @IsTest
    static void linkStatsUseNoMoreQueriesThanTheCountsAndReportTruncation() {
        User rep = createUser('stgstq');
        List<GTM_Saved_Configuration__c> three = new List<GTM_Saved_Configuration__c>();
        for (Integer i = 0; i < 3; i++) {
            three.add(newLink(rep.Id, 'Sent', true));
        }
        insert three;

        System.runAs(rep) {
            Test.startTest();
            Integer beforeCounts = Limits.getQueries();
            GtmLinkStageService.getStageCountsAura();
            Integer countsUsed = Limits.getQueries() - beforeCounts;
            Integer beforeStats = Limits.getQueries();
            GtmLinkStageService.LinkStatsResult r = GtmLinkStageService.getLinkStatsAura();
            Integer statsUsed = Limits.getQueries() - beforeStats;
            Test.stopTest();
            Assert.areEqual(countsUsed, statsUsed, 'no query beyond the shared computation');
            Assert.areEqual(3, r.stats.size());
            Assert.isFalse(r.truncated);

            GtmLinkStageService.universeLimitOverride = 2;
            GtmLinkStageService.LinkStatsResult capped = GtmLinkStageService.getLinkStats();
            Assert.isTrue(capped.truncated);
            Assert.areEqual(2, capped.stats.size());
        }
    }

    // ---- heat grid (issue overview-bd-heat-redesign-2-heat-grid) -------

    @IsTest
    static void heatGridBucketsTheTrailing14DayWindowInclusiveOfDay14AndExcludesDay15() {
        User rep = createUser('stghg1');
        Account acc = new Account(Name = 'Heat Co');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert acc;
        }
        GTM_Saved_Configuration__c link = newLink(rep.Id, 'Sent', true);
        link.Account__c = acc.Id;
        insert link;

        GtmLinkStageService.heatTodayOverride = Date.today();
        Date today = Date.today();

        SObject onDay14 = newEvent(rep.Id, link.Id, 'Page View', 'sess-14');
        SObject onDay15 = newEvent(rep.Id, link.Id, 'Page View', 'sess-15');
        insert new List<SObject>{ onDay14, onDay15 };
        Test.setCreatedDate(onDay14.Id, Datetime.newInstance(today.addDays(-13), Time.newInstance(9, 0, 0, 0)));
        Test.setCreatedDate(onDay15.Id, Datetime.newInstance(today.addDays(-14), Time.newInstance(9, 0, 0, 0)));

        System.runAs(rep) {
            GtmLinkStageService.HeatGridResult result = GtmLinkStageService.getHeatGrid();
            Assert.areEqual(1, result.rows.size());
            GtmLinkStageService.HeatRow row = result.rows[0];
            Assert.areEqual(14, row.days.size(), 'always 14 day buckets');
            Assert.areEqual(today.addDays(-13), row.days[0].day, 'oldest bucket is day -13, not day -14');
            Assert.areEqual('engaged', row.days[0].tier, 'the day-14-back event IS included');
            // Nothing in the response carries a day -14 bucket at all -- the
            // window starts at day -13, so the excluded event contributes
            // nothing to any bucket or to latestSignal.
            for (GtmLinkStageService.HeatDay d : row.days) {
                Assert.isTrue(d.day >= today.addDays(-13), 'no bucket older than day -13');
            }
        }
    }

    @IsTest
    static void heatGridBucketsEachTierIndependentlyPerDayAndRollsUpMultipleConfigsToOneAccountRow() {
        User rep = createUser('stghg2');
        Account acc = new Account(Name = 'Multi Link Co');
        Contact con = new Contact(LastName = 'Prospect', AccountId = null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert acc;
            con.AccountId = acc.Id;
            insert con;
        }
        GTM_Saved_Configuration__c older = newLink(rep.Id, 'Sent', true);
        older.Account__c = acc.Id;
        GTM_Saved_Configuration__c newer = newLink(rep.Id, 'Sent', true);
        newer.Account__c = acc.Id;
        newer.Contact__c = con.Id;
        insert new List<GTM_Saved_Configuration__c>{ older, newer };
        // newLink()/insert order alone doesn't guarantee CreatedDate ordering
        // within the same transaction, so pin it explicitly.
        Test.setCreatedDate(older.Id, Datetime.now().addMinutes(-10));
        Test.setCreatedDate(newer.Id, Datetime.now());

        Date today = Date.today();
        GtmLinkStageService.heatTodayOverride = today;

        SObject engagedEvt = newEvent(rep.Id, older.Id, 'Page View', 'sess-a');
        SObject startedEvt = newEvent(rep.Id, older.Id, 'Form Opened', null);
        SObject submittedEvt = newEvent(rep.Id, newer.Id, 'Form Submitted', null);
        insert new List<SObject>{ engagedEvt, startedEvt, submittedEvt };
        Test.setCreatedDate(engagedEvt.Id, Datetime.newInstance(today.addDays(-5), Time.newInstance(9, 0, 0, 0)));
        Test.setCreatedDate(startedEvt.Id, Datetime.newInstance(today.addDays(-5), Time.newInstance(10, 0, 0, 0)));
        Test.setCreatedDate(submittedEvt.Id, Datetime.newInstance(today, Time.newInstance(9, 0, 0, 0)));

        System.runAs(rep) {
            GtmLinkStageService.HeatGridResult result = GtmLinkStageService.getHeatGrid();
            Assert.areEqual(1, result.rows.size(), 'two configs for one Account roll up to one row');
            GtmLinkStageService.HeatRow row = result.rows[0];
            Assert.areEqual(con.Id, row.contactId, 'contact comes from the most-recently-created config');
            Assert.areEqual('submitted', row.currentTier);
            Assert.areEqual('nudge', row.nextAction, 'submitted -> the nudge stub action, rendered disabled by the LWC');

            GtmLinkStageService.HeatDay dayMinus5 = null;
            for (GtmLinkStageService.HeatDay d : row.days) {
                if (d.day == today.addDays(-5)) { dayMinus5 = d; }
            }
            Assert.isNotNull(dayMinus5);
            Assert.areEqual('started', dayMinus5.tier, 'stronger same-day event wins the day bucket');
        }
    }

    @IsTest
    static void heatGridExcludesConfigsWithNoAccountAndSortsHottestFirst() {
        User rep = createUser('stghg3');
        Account hot = new Account(Name = 'Hot Co');
        Account cold = new Account(Name = 'Cold Co');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<Account>{ hot, cold };
        }
        GTM_Saved_Configuration__c noAccountLink = newLink(rep.Id, 'Sent', true);
        GTM_Saved_Configuration__c hotLink = newLink(rep.Id, 'Sent', true);
        hotLink.Account__c = hot.Id;
        GTM_Saved_Configuration__c coldLink = newLink(rep.Id, 'Sent', true);
        coldLink.Account__c = cold.Id;
        insert new List<GTM_Saved_Configuration__c>{ noAccountLink, hotLink, coldLink };

        Date today = Date.today();
        GtmLinkStageService.heatTodayOverride = today;

        // hot: submitted several days ago (still the strongest tier -> outranks recency).
        SObject hotEvt = newEvent(rep.Id, hotLink.Id, 'Form Submitted', null);
        // cold: a mere page view today.
        SObject coldEvt = newEvent(rep.Id, coldLink.Id, 'Page View', 'sess-cold');
        insert new List<SObject>{ hotEvt, coldEvt };
        Test.setCreatedDate(hotEvt.Id, Datetime.newInstance(today.addDays(-5), Time.newInstance(9, 0, 0, 0)));
        Test.setCreatedDate(coldEvt.Id, Datetime.newInstance(today, Time.newInstance(9, 0, 0, 0)));

        System.runAs(rep) {
            GtmLinkStageService.HeatGridResult result = GtmLinkStageService.getHeatGrid();
            Assert.areEqual(2, result.rows.size(), 'the no-Account config contributes no row');
            Assert.areEqual('Hot Co', result.rows[0].accountName, 'strength beats raw recency');
            Assert.areEqual('Cold Co', result.rows[1].accountName);
        }
    }
}
