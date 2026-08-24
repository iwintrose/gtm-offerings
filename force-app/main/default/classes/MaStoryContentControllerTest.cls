@IsTest
private class MaStoryContentControllerTest {
    private static final String INDUSTRY_ID = '020000000000001AAA';
    private static final String FAQ_ID = '020000000000002AAA';
    private static final String SETTING_ID = '020000000000003AAA';

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
    static void returnsMappedContentForAllThreeTypes() {
        Test.setMock(HttpCalloutMock.class, new MockResponse());

        Test.startTest();
        MaStoryContentController.StoryContent result =
            MaStoryContentController.getStoryContent('migration-accelerator');
        Test.stopTest();

        System.assertEquals(1, result.industries.size(), 'Expected one industry story');
        MaStoryContentController.IndustryStory industry = result.industries[0];
        System.assertEquals('fintech', industry.industryKey);
        System.assertEquals('<p>Banks & insurers</p>', industry.coverSub, 'HTML entities should be unescaped');
        System.assertEquals(3, industry.uniquePoints.size());
        System.assertEquals('Point & two', industry.uniquePoints[1], 'Entity unescaping applies to MTEXT lines too');
        System.assertEquals(2, industry.demoDeps.size());

        System.assertEquals(1, result.faqs.size(), 'Expected one FAQ item');
        System.assertEquals('Does it work?', result.faqs[0].question);
        System.assertEquals('<p>Yes it does</p>', result.faqs[0].answer);

        System.assertNotEquals(null, result.setting, 'Expected a story setting');
        System.assertEquals('Eloqua', result.setting.defaultSourcePlatform);
        System.assertEquals(2, result.setting.genericDemoDeps.size());
        System.assertEquals(2, result.setting.swatches.size());
        System.assertEquals('PS Coral (default)', result.setting.swatches[0].name);
        System.assertEquals('EE3D23', result.setting.swatches[0].hex);
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
    }
}
