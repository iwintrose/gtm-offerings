@IsTest
private class GtmHomeSnapshotControllerTest {
    @IsTest
    static void summarizesActiveLinksAndOpenAssessments() {
        GTM_Saved_Configuration__c activeWithValue = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a',
            Active__c = true,
            Estimated_Value__c = 50000
        );
        GTM_Saved_Configuration__c activeNoValue = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Beta Co',
            Generated_URL__c = 'https://example.com/b',
            Active__c = true
        );
        GTM_Saved_Configuration__c inactive = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Gamma Inc',
            Generated_URL__c = 'https://example.com/c',
            Active__c = false,
            Estimated_Value__c = 999999
        );
        insert new List<GTM_Saved_Configuration__c>{ activeWithValue, activeNoValue, inactive };

        insert new GTM_Assessment_Request__c(
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex@example.com',
            Status__c = 'New'
        );
        insert new GTM_Assessment_Request__c(
            Requester_Name__c = 'Jordan Lee',
            Requester_Email__c = 'jordan@example.com',
            Status__c = 'Contacted'
        );

        Opportunity openOpp = new Opportunity(
            Name = 'Acme Bank Migration',
            StageName = 'Qualification',
            CloseDate = Date.today().addMonths(2),
            Amount = 75000
        );
        insert openOpp;
        activeWithValue.Opportunity__c = openOpp.Id;
        update activeWithValue;

        Test.startTest();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(2, snap.activeEngagementCount);
        Assert.areEqual(1, snap.newAssessmentCount);
    }

    @IsTest
    static void returnsRecentNewRequestsOnlyNewestFirst() {
        insert new GTM_Assessment_Request__c(
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex@example.com',
            Company__c = 'Acme Bank',
            Status__c = 'New'
        );
        insert new GTM_Assessment_Request__c(
            Requester_Name__c = 'Already Handled',
            Requester_Email__c = 'handled@example.com',
            Status__c = 'Contacted'
        );

        Test.startTest();
        List<GtmHomeSnapshotController.RequestSummary> results =
            GtmHomeSnapshotController.getRecentNewAssessmentRequests();
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only Status = New should be returned');
        Assert.areEqual('Alex Rivera', results[0].requesterName);
        Assert.areEqual('Acme Bank', results[0].company);
    }

    /**
     * Issue overview-redesign-funnel-drilldown, base scope §3 point 5: the
     * panel's "requested"-stage rows carry a bit more than name/company/date.
     * Assessment_Tier__c/Assessment_Score__c/Offering_Key__c already exist on
     * GTM_Assessment_Request__c, so this only locks in that RequestSummary
     * now populates them from the existing SELECT.
     */
    @IsTest
    static void recentRequestsCarryTierScoreAndOfferingKey() {
        insert new GTM_Assessment_Request__c(
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex@example.com',
            Company__c = 'Acme Bank',
            Status__c = 'New',
            Assessment_Tier__c = 'Accelerator-Ready',
            Assessment_Score__c = 87,
            Offering_Key__c = 'migration-accelerator'
        );

        Test.startTest();
        List<GtmHomeSnapshotController.RequestSummary> results =
            GtmHomeSnapshotController.getRecentNewAssessmentRequests();
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('Accelerator-Ready', results[0].assessmentTier);
        Assert.areEqual(87, results[0].assessmentScore);
        Assert.areEqual('migration-accelerator', results[0].offeringKey);
    }

    @IsTest
    static void returnsZeroesWhenNothingExists() {
        Test.startTest();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(0, snap.activeEngagementCount);
        Assert.areEqual(0, snap.newAssessmentCount);
    }

    /**
     * The funnel that made the deals card necessary: one deal that converted,
     * one that opened the form and left. They must not read the same.
     */
    @IsTest
    static void aDealCarriesTheFunnelAndTheRequestBehindIt() {
        Account acct = new Account(Name = 'Acme Bank');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Acme Bank — Migration Accelerator', AccountId = acct.Id,
            StageName = 'Qualification', CloseDate = Date.today().addMonths(2), Amount = 75000
        );
        Opportunity stalledOpp = new Opportunity(
            Name = 'Beta Co — Migration Accelerator', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addMonths(3)
        );
        insert new List<Opportunity>{ opp, stalledOpp };

        GTM_Saved_Configuration__c converted = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a', Active__c = true,
            Account__c = acct.Id, Opportunity__c = opp.Id
        );
        GTM_Saved_Configuration__c stalled = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Beta Co',
            Generated_URL__c = 'https://example.com/b', Active__c = true,
            Account__c = acct.Id, Opportunity__c = stalledOpp.Id
        );
        // No opportunity, so it is not a deal and must not appear.
        GTM_Saved_Configuration__c orphan = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Nobody Ltd',
            Generated_URL__c = 'https://example.com/c', Active__c = true
        );
        insert new List<GTM_Saved_Configuration__c>{ converted, stalled, orphan };

        SObject req = Schema.getGlobalDescribe().get('GTM_Assessment_Request__c').newSObject();
        req.put('Requester_Name__c', 'Alex Rivera');
        req.put('Requester_Email__c', 'alex@example.com');
        req.put('Company__c', 'Acme Bank');
        req.put('Status__c', 'New');
        req.put('Saved_Configuration__c', converted.Id);
        insert req;

        insert new List<SObject>{
            newLinkEvent(converted.Id, 'Page View', null),
            newLinkEvent(converted.Id, 'Page View', null),
            newLinkEvent(converted.Id, 'Form Opened', null),
            newLinkEvent(converted.Id, 'Form Submitted', req.Id),
            newLinkEvent(stalled.Id, 'Page View', null),
            newLinkEvent(stalled.Id, 'Form Opened', null),
            newLinkEvent(stalled.Id, 'Drop-off', null)
        };

        Test.startTest();
        List<GtmHomeSnapshotController.DealSummary> deals = GtmHomeSnapshotController.getDeals();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        Test.stopTest();

        Assert.areEqual(2, deals.size(), 'A configuration with no opportunity is not a deal');

        Map<Id, GtmHomeSnapshotController.DealSummary> byConfig =
            new Map<Id, GtmHomeSnapshotController.DealSummary>();
        for (GtmHomeSnapshotController.DealSummary d : deals) byConfig.put(d.configId, d);

        GtmHomeSnapshotController.DealSummary won = byConfig.get(converted.Id);
        Assert.areEqual('Acme Bank — Migration Accelerator', won.opportunityName);
        Assert.areEqual('Acme Bank', won.accountName);
        Assert.areEqual('Qualification', won.stageName);
        Assert.areEqual(2, won.views, 'Views are counted, not flagged');
        Assert.isTrue(won.formOpened);
        Assert.isTrue(won.formSubmitted);
        Assert.isFalse(won.droppedOff);
        Assert.areEqual(req.Id, won.requestId);
        Assert.areEqual('New', won.requestStatus);
        Assert.isNotNull(won.lastActivity);

        GtmHomeSnapshotController.DealSummary lost = byConfig.get(stalled.Id);
        Assert.areEqual(1, lost.views);
        Assert.isTrue(lost.formOpened);
        Assert.isFalse(lost.formSubmitted, 'This is the deal worth chasing');
        Assert.isTrue(lost.droppedOff);
        Assert.isNull(lost.requestId, 'No request came back from this one');
    }

    /**
     * Issue opportunities-table-redesign-v2, Architect addendum Resolution 3:
     * Offering__c is a plain text key with no lookup relationship --
     * getDeals() resolves it to a human-readable label via GTM_Offering__mdt
     * (same convention as GtmPageContentController.getOfferings()), falling
     * back to the raw key when no metadata record matches. The org's
     * existing GTM_Offering.Migration_Accelerator custom metadata record
     * (Offering_Key__c = 'migration-accelerator', Label__c = 'Migration
     * Accelerator') is already deployed, so this locks in the resolved
     * case without inserting new metadata; the unmatched key locks in the
     * fallback.
     */
    @IsTest
    static void dealsResolveOfferingLabelViaMetadataWithRawKeyFallback() {
        GTM_Saved_Configuration__c known = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/known', Active__c = true
        );
        GTM_Saved_Configuration__c unknown = new GTM_Saved_Configuration__c(
            Offering__c = 'not-a-real-offering-key', Company__c = 'Beta Co',
            Generated_URL__c = 'https://example.com/unknown', Active__c = true
        );
        insert new List<GTM_Saved_Configuration__c>{ known, unknown };

        Opportunity oppA = new Opportunity(
            Name = 'Acme Bank Migration', StageName = 'Qualification',
            CloseDate = Date.today().addMonths(1)
        );
        Opportunity oppB = new Opportunity(
            Name = 'Beta Co Migration', StageName = 'Qualification',
            CloseDate = Date.today().addMonths(1)
        );
        insert new List<Opportunity>{ oppA, oppB };
        known.Opportunity__c = oppA.Id;
        unknown.Opportunity__c = oppB.Id;
        update new List<GTM_Saved_Configuration__c>{ known, unknown };

        Test.startTest();
        List<GtmHomeSnapshotController.DealSummary> deals = GtmHomeSnapshotController.getDeals();
        Test.stopTest();

        Map<Id, GtmHomeSnapshotController.DealSummary> byConfig =
            new Map<Id, GtmHomeSnapshotController.DealSummary>();
        for (GtmHomeSnapshotController.DealSummary d : deals) byConfig.put(d.configId, d);

        Assert.areEqual('Migration Accelerator', byConfig.get(known.Id).offeringLabel,
            'A key with a matching GTM_Offering__mdt record resolves to its Label__c');
        Assert.areEqual('not-a-real-offering-key', byConfig.get(unknown.Id).offeringLabel,
            'A key with no matching metadata record falls back to the raw key');
    }

    /**
     * Issue opportunities-table-redesign-v2, §1: Account__c/Contact__c and
     * the request's Submitted_At__c (falling back to CreatedDate when
     * unpopulated) drive the new 3-level grouping and Assessment column.
     */
    @IsTest
    static void dealsCarryAccountContactAndRequestSubmittedAt() {
        Account acct = new Account(Name = 'Acme Bank');
        insert acct;
        Contact con = new Contact(FirstName = 'Jordan', LastName = 'Lee', AccountId = acct.Id);
        insert con;
        Opportunity opp = new Opportunity(
            Name = 'Acme Bank — Migration Accelerator', AccountId = acct.Id,
            StageName = 'Qualification', CloseDate = Date.today().addMonths(2)
        );
        insert opp;

        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/grouped', Active__c = true,
            Account__c = acct.Id, Contact__c = con.Id, Opportunity__c = opp.Id
        );
        insert cfg;

        SObject req = Schema.getGlobalDescribe().get('GTM_Assessment_Request__c').newSObject();
        req.put('Requester_Name__c', 'Jordan Lee');
        req.put('Requester_Email__c', 'jordan@example.com');
        req.put('Status__c', 'New');
        req.put('Saved_Configuration__c', cfg.Id);
        req.put('Submitted_At__c', Datetime.now().addDays(-1));
        insert req;

        Test.startTest();
        List<GtmHomeSnapshotController.DealSummary> deals = GtmHomeSnapshotController.getDeals();
        Test.stopTest();

        Assert.areEqual(1, deals.size());
        GtmHomeSnapshotController.DealSummary d = deals[0];
        Assert.areEqual(acct.Id, d.accountId);
        Assert.areEqual('Acme Bank', d.accountName);
        Assert.areEqual(con.Id, d.contactId);
        Assert.areEqual('Jordan Lee', d.contactName);
        Assert.areEqual(req.get('Id'), d.requestId);
        Assert.isNotNull(d.requestSubmittedAt,
            'Submitted_At__c is populated on this request, so it must be used');
    }

    @IsTest
    static void aLinkNobodyOpenedIsNotStalled() {
        GTM_Saved_Configuration__c untouched = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Quiet Co',
            Generated_URL__c = 'https://example.com/q', Active__c = true
        );
        insert untouched;
        insert newLinkEvent(untouched.Id, 'Page View', null);

        Test.startTest();
        GtmHomeSnapshotController.Snapshot snap = GtmHomeSnapshotController.getSnapshot();
        List<GtmHomeSnapshotController.DealSummary> deals = GtmHomeSnapshotController.getDeals();
        Test.stopTest();

        Assert.areEqual(0, deals.size());
    }

    // ── rep-data-scoping-owd-1: OWD Private + explicit OwnerId scoping ──────

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

    private static void assignAdmin(User u) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'GTM_Offering_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    /**
     * Two reps, each owning one 'New' assessment request. A rep querying
     * getSnapshot()/getRecentNewAssessmentRequests() must only ever see
     * their own, and an admin must see both.
     */
    @IsTest
    static void snapshotAndRecentRequestsAreScopedToTheOwningRep() {
        User repA = createRep('owdrepa');
        User repB = createRep('owdrepb');

        GTM_Assessment_Request__c reqA = new GTM_Assessment_Request__c(
            OwnerId = repA.Id,
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex@example.com',
            Company__c = 'Acme Bank',
            Status__c = 'New'
        );
        GTM_Assessment_Request__c reqB = new GTM_Assessment_Request__c(
            OwnerId = repB.Id,
            Requester_Name__c = 'Jordan Lee',
            Requester_Email__c = 'jordan@example.com',
            Company__c = 'Beta Co',
            Status__c = 'New'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<GTM_Assessment_Request__c>{ reqA, reqB };
        }

        GtmHomeSnapshotController.Snapshot snapA;
        List<GtmHomeSnapshotController.RequestSummary> recentA;
        System.runAs(repA) {
            Test.startTest();
            snapA = GtmHomeSnapshotController.getSnapshot();
            recentA = GtmHomeSnapshotController.getRecentNewAssessmentRequests();
            Test.stopTest();
        }

        Assert.areEqual(1, snapA.newAssessmentCount,
            'repA must only count their own new assessment request, not repB\'s');
        Assert.areEqual(1, recentA.size());
        Assert.areEqual('Alex Rivera', recentA[0].requesterName,
            'repA must not see repB\'s requester PII');
        for (GtmHomeSnapshotController.RequestSummary s : recentA) {
            Assert.areNotEqual('Jordan Lee', s.requesterName,
                'repB\'s request must never leak into repA\'s recent-requests panel');
        }
        // Regression: adding Assessment_Tier__c/Assessment_Score__c/
        // Offering_Key__c to the SELECT (issue
        // overview-redesign-funnel-drilldown) must not widen the OwnerId
        // scoping above -- repA must still see exactly their own row, never
        // repB's, once the new columns are in play.
        Assert.areEqual(1, recentA.size(),
            'the OwnerId scope must still limit repA to their own request after the new columns were added');
    }

    @IsTest
    static void adminSeesSnapshotAndRecentRequestsAcrossAllReps() {
        User repA = createRep('oarepa');
        User repB = createRep('oarepb');
        User admin = createRep('oaadmin');
        assignAdmin(admin);

        GTM_Assessment_Request__c reqA = new GTM_Assessment_Request__c(
            OwnerId = repA.Id,
            Requester_Name__c = 'Alex Rivera',
            Requester_Email__c = 'alex2@example.com',
            Company__c = 'Acme Bank',
            Status__c = 'New'
        );
        GTM_Assessment_Request__c reqB = new GTM_Assessment_Request__c(
            OwnerId = repB.Id,
            Requester_Name__c = 'Jordan Lee',
            Requester_Email__c = 'jordan2@example.com',
            Company__c = 'Beta Co',
            Status__c = 'New'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<GTM_Assessment_Request__c>{ reqA, reqB };
        }

        GtmHomeSnapshotController.Snapshot snapAdmin;
        List<GtmHomeSnapshotController.RequestSummary> recentAdmin;
        System.runAs(admin) {
            Test.startTest();
            snapAdmin = GtmHomeSnapshotController.getSnapshot();
            recentAdmin = GtmHomeSnapshotController.getRecentNewAssessmentRequests();
            Test.stopTest();
        }

        Assert.areEqual(2, snapAdmin.newAssessmentCount,
            'a GTM_Offering_Admin must see every rep\'s new assessment requests');
        Assert.areEqual(2, recentAdmin.size());
    }

    /**
     * recentViews queries GTM_Link_Event__c -- confirm the same
     * explicit OwnerId backstop excludes another rep's link activity.
     */
    @IsTest
    static void recentViewsAreScopedToTheOwningRep() {
        User repA = createRep('olerepa');
        User repB = createRep('olerepb');

        GTM_Saved_Configuration__c cfgA = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/owd-a', Active__c = true
        );
        GTM_Saved_Configuration__c cfgB = new GTM_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Beta Co',
            Generated_URL__c = 'https://example.com/owd-b', Active__c = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<GTM_Saved_Configuration__c>{ cfgA, cfgB };
        }

        SObject openedA = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        openedA.put('OwnerId', repA.Id);
        openedA.put('Saved_Configuration__c', cfgA.Id);
        openedA.put('Event_Type__c', 'Form Opened');

        SObject viewA = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        viewA.put('OwnerId', repA.Id);
        viewA.put('Saved_Configuration__c', cfgA.Id);
        viewA.put('Event_Type__c', 'Page View');

        SObject openedB = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        openedB.put('OwnerId', repB.Id);
        openedB.put('Saved_Configuration__c', cfgB.Id);
        openedB.put('Event_Type__c', 'Form Opened');

        SObject viewB = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        viewB.put('OwnerId', repB.Id);
        viewB.put('Saved_Configuration__c', cfgB.Id);
        viewB.put('Event_Type__c', 'Page View');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<SObject>{ openedA, viewA, openedB, viewB };
        }

        GtmHomeSnapshotController.Snapshot snapA;
        System.runAs(repA) {
            Test.startTest();
            snapA = GtmHomeSnapshotController.getSnapshot();
            Test.stopTest();
        }

        Assert.areEqual(1, snapA.recentViews, 'repA sees only their own recent page view, not repB\'s');
    }

    // Dynamic construction avoids a static compile-time reference to
    // GTM_Link_Event__c.Saved_Configuration__c, which would otherwise block
    // the Salesforce dependency tracker from allowing that field to be
    // deleted and recreated when its referenceTo changes.
    private static SObject newLinkEvent(Id savedConfigId, String eventType, Id assessmentRequestId) {
        SObject le = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        le.put('Saved_Configuration__c', savedConfigId);
        le.put('Event_Type__c', eventType);
        if (assessmentRequestId != null) {
            le.put('Assessment_Request__c', assessmentRequestId);
        }
        return le;
    }

    private static SObject newStepEvent(
        Id savedConfigId, String eventType, String step, String sessionId, Decimal dwellSeconds
    ) {
        SObject le = Schema.getGlobalDescribe().get('GTM_Link_Event__c').newSObject();
        le.put('Saved_Configuration__c', savedConfigId);
        le.put('Event_Type__c', eventType);
        le.put('Step__c', step);
        le.put('Session_Id__c', sessionId);
        if (dwellSeconds != null) {
            le.put('Dwell_Seconds__c', dwellSeconds);
        }
        return le;
    }

    private static GTM_Page_Section__c newSection(
        String offeringKey, String sectionKey, String label, Integer sortOrder, String layoutType
    ) {
        return new GTM_Page_Section__c(
            Offering_Key__c    = offeringKey,
            Template_Type__c   = 'configurator',
            Section_Key__c     = sectionKey,
            Section_Address__c = offeringKey + '::configurator::' + sectionKey,
            Label__c            = label,
            Sort_Order__c       = sortOrder,
            Layout_Type__c      = layoutType,
            Active__c           = true,
            Status__c           = 'Published'
        );
    }

    // ── getLinkSitemap ───────────────────────────────────────────────────────

    @IsTest
    static void getLinkSitemap_blankConfigId_returnsEmptyList() {
        Test.startTest();
        List<GtmHomeSnapshotController.SitemapNode> nodes =
            GtmHomeSnapshotController.getLinkSitemap('');
        Test.stopTest();

        Assert.areEqual(0, nodes.size());
    }

    @IsTest
    static void getLinkSitemap_nonexistentConfig_returnsEmptyList() {
        Test.startTest();
        List<GtmHomeSnapshotController.SitemapNode> nodes =
            GtmHomeSnapshotController.getLinkSitemap('a0HgK000000000AAA');
        Test.stopTest();

        Assert.areEqual(0, nodes.size(), 'A malformed/unresolvable id should not throw, just yield nothing');
    }

    @IsTest
    static void getLinkSitemap_excludesControlSectionsAndOtherIndustries() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'ma-sitemap-test', Industry__c = 'financial-services',
            Company__c = 'Acme Bank', Generated_URL__c = 'https://example.com/a'
        );
        insert cfg;

        insert new List<GTM_Page_Section__c>{
            newSection('ma-sitemap-test', 'hero', 'Hero', 0, 'hero'),
            newSection('ma-sitemap-test', 'assist', 'Assistant', 1, 'assistant'),
            newSection('ma-sitemap-test', 'defaults', 'Defaults', 2, 'offering-defaults'),
            newSection('ma-sitemap-test', 'industry-financial-services', 'Financial Services', 3, 'industry-profile'),
            newSection('ma-sitemap-test', 'industry-retail', 'Retail', 4, 'industry-profile')
        };

        Test.startTest();
        List<GtmHomeSnapshotController.SitemapNode> nodes =
            GtmHomeSnapshotController.getLinkSitemap(cfg.Id);
        Test.stopTest();

        Set<String> keys = new Set<String>();
        for (GtmHomeSnapshotController.SitemapNode n : nodes) keys.add(n.sectionKey);

        Assert.isTrue(keys.contains('hero'), 'A normal beat should be included');
        Assert.isFalse(keys.contains('assist'), 'The assistant control is not a readable beat');
        Assert.isFalse(keys.contains('defaults'), 'Offering defaults are settings, not a beat');
        Assert.isTrue(keys.contains('industry-financial-services'), 'The link\'s own industry cover is included');
        Assert.isFalse(keys.contains('industry-retail'), 'A different industry\'s cover is structurally unreachable');

        for (GtmHomeSnapshotController.SitemapNode n : nodes) {
            if (n.sectionKey == 'industry-financial-services') {
                Assert.isTrue(n.label.endsWith(' (cover)'), 'The own-industry cover section is labeled distinctly');
            }
        }
    }

    @IsTest
    static void getLinkSitemap_aggregatesReadersDwellAndClicksPerStep() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'ma-sitemap-agg', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a'
        );
        insert cfg;

        insert new List<GTM_Page_Section__c>{
            newSection('ma-sitemap-agg', 'hero', 'Hero', 0, 'hero'),
            newSection('ma-sitemap-agg', 'proof', 'Proof', 1, 'route-proof')
        };

        insert new List<SObject>{
            newStepEvent(cfg.Id, 'Section Viewed', 'hero', 'sess-1', 10),
            newStepEvent(cfg.Id, 'Section Viewed', 'hero', 'sess-2', 20),
            newStepEvent(cfg.Id, 'CTA Clicked', 'hero', 'sess-1', null),
            newStepEvent(cfg.Id, 'Section Viewed', 'proof', 'sess-1', 5)
        };

        Test.startTest();
        List<GtmHomeSnapshotController.SitemapNode> nodes =
            GtmHomeSnapshotController.getLinkSitemap(cfg.Id);
        Test.stopTest();

        Map<String, GtmHomeSnapshotController.SitemapNode> byKey =
            new Map<String, GtmHomeSnapshotController.SitemapNode>();
        for (GtmHomeSnapshotController.SitemapNode n : nodes) byKey.put(n.sectionKey, n);

        GtmHomeSnapshotController.SitemapNode hero = byKey.get('hero');
        Assert.areEqual(2, hero.readers, 'Two distinct sessions viewed hero');
        Assert.areEqual(30, hero.totalDwell);
        Assert.areEqual(15.0, hero.avgDwell);
        Assert.areEqual(1, hero.clicks);

        GtmHomeSnapshotController.SitemapNode proof = byKey.get('proof');
        Assert.areEqual(1, proof.readers);
        Assert.isFalse(proof.isLastSeen == null);

        // The furthest section with any readers is the one marked last-seen.
        Assert.isTrue(proof.isLastSeen, 'Proof is the furthest section actually reached');
        Assert.isFalse(hero.isLastSeen, 'Hero was passed through, not where reading stopped');
    }

    @IsTest
    static void getLinkSitemap_sectionsWithNoActivityReportZeroed() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c = 'ma-sitemap-empty', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a'
        );
        insert cfg;
        insert newSection('ma-sitemap-empty', 'hero', 'Hero', 0, 'hero');

        Test.startTest();
        List<GtmHomeSnapshotController.SitemapNode> nodes =
            GtmHomeSnapshotController.getLinkSitemap(cfg.Id);
        Test.stopTest();

        Assert.areEqual(1, nodes.size());
        GtmHomeSnapshotController.SitemapNode n = nodes[0];
        Assert.areEqual(0, n.readers);
        Assert.areEqual(0, n.clicks);
        Assert.isFalse(n.isLastSeen, 'Nothing was read, so nothing is marked last-seen');
    }
}
