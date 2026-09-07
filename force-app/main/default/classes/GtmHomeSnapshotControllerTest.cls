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

        Assert.areEqual(1, snap.stalledCount,
            'Exactly one link was opened and never submitted');
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

        Assert.areEqual(0, snap.stalledCount, 'Reading the page is not starting the form');
        Assert.areEqual(0, deals.size());
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
