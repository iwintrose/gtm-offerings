@IsTest
private class MaStoryContentControllerTest {
    private static final String INDUSTRY_ID = '020000000000001AAA';
    private static final String FAQ_ID = '020000000000002AAA';
    private static final String SETTING_ID = '020000000000003AAA';
    private static final String PAGE_ID = '020000000000004AAA';
    private static final String BODY_ID = '020000000000005AAA';

    @TestSetup
    static void setup() {
        insert new List<MA_CMS_Content_Index__c>{
            new MA_CMS_Content_Index__c(
                CMS_Record_Id__c = INDUSTRY_ID,
                Content_Type__c = 'ma_industry_story',
                Offering_Key__c = 'migration-accelerator',
                Display_Order__c = 1,
                Active__c = true
            ),
            new MA_CMS_Content_Index__c(
                CMS_Record_Id__c = FAQ_ID,
                Content_Type__c = 'ma_faq_item',
                Offering_Key__c = 'migration-accelerator',
                Display_Order__c = 1,
                Active__c = true
            ),
            new MA_CMS_Content_Index__c(
                CMS_Record_Id__c = SETTING_ID,
                Content_Type__c = 'ma_story_setting',
                Offering_Key__c = 'migration-accelerator',
                Display_Order__c = 1,
                Active__c = true
            ),
            new MA_CMS_Content_Index__c(
                CMS_Record_Id__c = PAGE_ID,
                Content_Type__c = 'ma_story_page',
                Offering_Key__c = 'migration-accelerator',
                Display_Order__c = 1,
                Active__c = true
            ),
            new MA_CMS_Content_Index__c(
                CMS_Record_Id__c = BODY_ID,
                Content_Type__c = 'ma_story_body',
                Offering_Key__c = 'migration-accelerator',
                Display_Order__c = 1,
                Active__c = true
            )
        };
    }

    private class MockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            Map<String, Object> contentBody;
            if (endpoint.endsWith(INDUSTRY_ID)) {
                contentBody = new Map<String, Object>{
                    'industryKey' => 'fintech',
                    'industryLabel' => 'Financial Services',
                    'pickerBlurb' => 'Consent and audit trails under the regulator\'s eye.',
                    'coverSub' => '&lt;p&gt;Banks &amp; insurers&lt;/p&gt;',
                    'problem' => '&lt;p&gt;The problem&lt;/p&gt;',
                    'useCase' => '&lt;p&gt;The use case&lt;/p&gt;',
                    'solution' => '&lt;p&gt;The solution&lt;/p&gt;',
                    'uniquePoints' => 'Point one\nPoint &amp; two\nPoint three',
                    'proofLine' => 'Proof line',
                    'whyLine' => 'Why line',
                    'whyHead' => 'Why head',
                    'demoRoot' => 'Root asset',
                    'demoDeps' => 'Dep one\nDep two'
                };
            } else if (endpoint.endsWith(FAQ_ID)) {
                contentBody = new Map<String, Object>{
                    'title' => 'Does it work?',
                    'answer' => '&lt;p&gt;Yes it does&lt;/p&gt;',
                    'verdict' => 'Yes'
                };
            } else if (endpoint.endsWith(SETTING_ID)) {
                contentBody = new Map<String, Object>{
                    'offeringTileDescription' => '&lt;p&gt;Reads a client\'s platform directly.&lt;/p&gt;',
                    'defaultSourcePlatform' => 'Eloqua',
                    'defaultTargetPlatform' => 'Salesforce Marketing Cloud',
                    'defaultAssetCount' => '4,128',
                    'defaultDependencyCount' => '9,640',
                    'defaultHealthScore' => '62',
                    'genericDemoRoot' => 'Welcome Series',
                    'genericDemoDeps' => 'Welcome email 1\nWelcome email 2',
                    'genericChips' => 'Chip one\nChip &amp; two',
                    'swatches' => 'PS Coral (default)|EE3D23\nCorporate blue|0B5FFF'
                };
            } else if (endpoint.endsWith(PAGE_ID)) {
                contentBody = new Map<String, Object>{
                    'heroEyebrow' => 'Internal positioning · GTM buy-in',
                    'heroHeadline' => '&lt;p&gt;Every migration starts with a decade nobody documented.&lt;/p&gt;',
                    'heroSubhead' => '&lt;p&gt;How Migration Accelerator turns an untrusted platform into a plan.&lt;/p&gt;',
                    'proofObjectsCount' => '1284',
                    'proofDepsCount' => '3140',
                    'proofHealthScore' => '84',
                    'problemLede' => '&lt;p&gt;Every enterprise migration starts the same way.&lt;/p&gt;',
                    'problemChips' => 'A platform nobody fully trusts\nA decade of undocumented campaigns\nA go-live date that won\'t move',
                    'problemClose' => '&lt;p&gt;Migration Accelerator starts working before the rebuild.&lt;/p&gt;',
                    'mechanismHead' => '&lt;p&gt;Point it at the platform. Get a plan you can act on.&lt;/p&gt;',
                    'mechanismSub' => '&lt;p&gt;Eloqua or Salesforce Marketing Cloud, in, a build-ready plan out.&lt;/p&gt;',
                    'closingHead' => '&lt;p&gt;This is Migration Accelerator today.&lt;/p&gt;',
                    'closingSub' => '&lt;p&gt;The next step is putting a name and an industry behind it.&lt;/p&gt;'
                };
            } else if (endpoint.endsWith(BODY_ID)) {
                contentBody = new Map<String, Object>{
                    'routeSteps' => 'Ingest|Every asset, read directly\nAudit|A live health score\nDecide|Port, rework, retire, logged\nPlan|Dependencies pulled automatically\nExecute|Dry run, then live, rollback ready',
                    'proofCtaText' => '&lt;p&gt;A snapshot of what the platform reads from an environment, automatically, on day one.&lt;/p&gt;',
                    'proofDemoNodes' => 'APAC Onboarding\nWelcome email\nShared data extension\nBrand header',
                    'capabilities' => 'In|Ingestion &amp; inventory|Automatic, for Eloqua and SFMC.|false\nAu|Automated audit|A health score generated on demand.|true',
                    'bonusCard' => '&lt;p&gt;&lt;strong&gt;Also in the toolkit:&lt;/strong&gt; a design-to-email pipeline.&lt;/p&gt;',
                    'clientStatBig' => '500–2,000+',
                    'clientStatDesc' => '&lt;p&gt;Objects is where this offering\'s advantage is largest.&lt;/p&gt;',
                    'clientNote' => '&lt;p&gt;Today, this runs through us, in working sessions.&lt;/p&gt;',
                    'bdHead' => 'One story. Here\'s how to run it.',
                    'bdLede' => '&lt;p&gt;This is the pitch, the same one a client hears.&lt;/p&gt;',
                    'bdUseCases' => 'Presales|Run a prospect\'s export before the SOW.\nDelivery|Run the full engagement through it.\nThe pitch|A real environment becoming a real plan.',
                    'pitchOldChips' => 'A promise to figure out scope after signature\nAn estimate built on intuition',
                    'pitchNewChips' => 'A real health score, produced live, in the room\nScope set from the actual environment'
                };
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
                return res;
            }

            Map<String, Object> fullBody = new Map<String, Object>{ 'contentBody' => contentBody };
            res.setBody(JSON.serialize(fullBody));
            return res;
        }
    }

    @IsTest
    static void returnsMappedContentForAllFiveTypes() {
        Test.setMock(HttpCalloutMock.class, new MockResponse());

        Test.startTest();
        MaStoryContentController.StoryContent result =
            MaStoryContentController.getStoryContent('migration-accelerator');
        Test.stopTest();

        // industry
        System.assertEquals(1, result.industries.size(), 'Expected one industry story');
        MaStoryContentController.IndustryStory industry = result.industries[0];
        System.assertEquals('fintech', industry.industryKey);
        System.assertEquals('Consent and audit trails under the regulator\'s eye.', industry.pickerBlurb);
        System.assertEquals('Banks & insurers', industry.coverSub, 'Entities unescaped and outer <p> stripped');
        System.assertEquals(3, industry.uniquePoints.size());
        System.assertEquals('Point & two', industry.uniquePoints[1]);
        System.assertEquals(2, industry.demoDeps.size());

        // faq
        System.assertEquals(1, result.faqs.size());
        System.assertEquals('Does it work?', result.faqs[0].question);
        System.assertEquals('Yes it does', result.faqs[0].answer);

        // setting
        System.assertNotEquals(null, result.setting);
        System.assertEquals('Reads a client\'s platform directly.', result.setting.offeringTileDescription);
        System.assertEquals('Eloqua', result.setting.defaultSourcePlatform);
        System.assertEquals(2, result.setting.swatches.size());
        System.assertEquals('PS Coral (default)', result.setting.swatches[0].name);

        // page
        System.assertNotEquals(null, result.page);
        System.assertEquals('Internal positioning · GTM buy-in', result.page.heroEyebrow);
        System.assertEquals('Every migration starts with a decade nobody documented.', result.page.heroHeadline);
        System.assertEquals('1284', result.page.proofObjectsCount);
        System.assertEquals(3, result.page.problemChips.size());
        System.assertEquals('A platform nobody fully trusts', result.page.problemChips[0]);
        System.assertEquals('Every enterprise migration starts the same way.', result.page.problemLede);
        System.assertEquals('Point it at the platform. Get a plan you can act on.', result.page.mechanismHead);
        System.assertEquals('This is Migration Accelerator today.', result.page.closingHead);

        // body
        System.assertNotEquals(null, result.body);
        System.assertEquals(5, result.body.routeSteps.size());
        System.assertEquals('Ingest', result.body.routeSteps[0].stepLabel);
        System.assertEquals('Every asset, read directly', result.body.routeSteps[0].stepDesc);
        System.assertEquals('APAC Onboarding', result.body.proofDemoRoot);
        System.assertEquals(3, result.body.proofDemoDeps.size());
        System.assertEquals(2, result.body.capabilities.size());
        System.assertEquals('In', result.body.capabilities[0].icon);
        System.assertEquals('Ingestion & inventory', result.body.capabilities[0].cardTitle);
        System.assertEquals(false, result.body.capabilities[0].isNew);
        System.assertEquals(true, result.body.capabilities[1].isNew);
        System.assertEquals('500–2,000+', result.body.clientStatBig);
        System.assertEquals('One story. Here\'s how to run it.', result.body.bdHead);
        System.assertEquals(3, result.body.bdUseCases.size());
        System.assertEquals('Presales', result.body.bdUseCases[0].caseTitle);
        System.assertEquals(2, result.body.pitchOldChips.size());
        System.assertEquals(2, result.body.pitchNewChips.size());
        System.assertEquals('A real health score, produced live, in the room', result.body.pitchNewChips[0]);
    }

    @IsTest
    static void rejectsBlankOfferingKey() {
        Boolean threw = false;
        try {
            MaStoryContentController.getStoryContent('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected an AuraHandledException for a blank offering key');
    }

    @IsTest
    static void rejectsUnknownOfferingKey() {
        Test.setMock(HttpCalloutMock.class, new MockResponse());
        Boolean threw = false;
        try {
            MaStoryContentController.getStoryContent('not-a-real-offering');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected an AuraHandledException for an offering with no MA_Offering__mdt record');
    }

    private class FailingMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('error');
            return res;
        }
    }

    @IsTest
    static void skipsIndexRowsWhoseCalloutFails() {
        Test.setMock(HttpCalloutMock.class, new FailingMockResponse());

        Test.startTest();
        MaStoryContentController.StoryContent result =
            MaStoryContentController.getStoryContent('migration-accelerator');
        Test.stopTest();

        System.assertEquals(0, result.industries.size(), 'A failed callout should be skipped, not thrown');
        System.assertEquals(0, result.faqs.size());
        System.assertEquals(null, result.setting);
        System.assertEquals(null, result.page);
        System.assertEquals(null, result.body);
    }
}
