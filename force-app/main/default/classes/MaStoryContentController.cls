/**
 * Reads the GTM Offerings story page's editorial content (industry blocks,
 * FAQ, site defaults) from Salesforce CMS, replacing what used to be
 * hardcoded JS constants in maConfigData.js/maStory.js so a non-engineer can
 * edit it directly in the CMS Workspace.
 *
 * Uses Http/HttpRequest self-callouts to this org's own Connect REST
 * delivery API, authenticated with UserInfo.getSessionId(), rather than
 * ConnectApi.ManagedContent -- that class's exact method signatures for
 * querying content by space/type couldn't be verified against live docs,
 * and these are the same REST calls already proven working (create, get-
 * by-key, publish, channel delivery) while building and seeding this
 * content. Requires a synchronous session context (an LWC page load), which
 * is the only context this is ever called from.
 *
 * The CMS delivery API here has no working "list everything of type X"
 * query (tried content-type filters, search terms, POST variants, waited
 * out possible index lag) -- MA_CMS_Content_Index__c is the bridge:  one row
 * per CMS record this page should show, giving this controller a plain
 * SOQL-queryable list of record Ids to fetch by key. See that object's
 * description and DEPLOYMENT.md.
 */
public with sharing class MaStoryContentController {
    private static final Integer TIMEOUT_MS = 8000;
    private static final String API_VERSION = 'v66.0';
    private static final String INDUSTRY_TYPE = 'ma_industry_story';
    private static final String FAQ_TYPE = 'ma_faq_item';
    private static final String SETTING_TYPE = 'ma_story_setting';

    public class StoryContent {
        @AuraEnabled public List<IndustryStory> industries = new List<IndustryStory>();
        @AuraEnabled public List<FaqItem> faqs = new List<FaqItem>();
        @AuraEnabled public StorySetting setting;
    }

    public class IndustryStory {
        @AuraEnabled public String industryKey;
        @AuraEnabled public String industryLabel;
        @AuraEnabled public String coverSub;
        @AuraEnabled public String problem;
        @AuraEnabled public String useCase;
        @AuraEnabled public String solution;
        @AuraEnabled public List<String> uniquePoints = new List<String>();
        @AuraEnabled public String proofLine;
        @AuraEnabled public String whyLine;
        @AuraEnabled public String whyHead;
        @AuraEnabled public String demoRoot;
        @AuraEnabled public List<String> demoDeps = new List<String>();
    }

    public class FaqItem {
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String verdict;
    }

    public class Swatch {
        @AuraEnabled public String name;
        @AuraEnabled public String hex;
    }

    public class StorySetting {
        @AuraEnabled public String defaultSourcePlatform;
        @AuraEnabled public String defaultTargetPlatform;
        @AuraEnabled public String defaultAssetCount;
        @AuraEnabled public String defaultDependencyCount;
        @AuraEnabled public String defaultHealthScore;
        @AuraEnabled public String genericDemoRoot;
        @AuraEnabled public List<String> genericDemoDeps = new List<String>();
        @AuraEnabled public List<String> genericChips = new List<String>();
        @AuraEnabled public List<Swatch> swatches = new List<Swatch>();
    }

    @AuraEnabled(cacheable=true)
    public static StoryContent getStoryContent(String offeringKey) {
        if (String.isBlank(offeringKey)) {
            throw new AuraHandledException('No offering key given.');
        }

        List<MA_Offering__mdt> offerings = [
            SELECT CMS_Channel_Id__c
            FROM MA_Offering__mdt
            WHERE Offering_Key__c = :offeringKey
            LIMIT 1
        ];
        if (offerings.isEmpty()) {
            throw new AuraHandledException('No MA_Offering__mdt record found for offering key "' + offeringKey + '".');
        }
        if (String.isBlank(offerings[0].CMS_Channel_Id__c)) {
            throw new AuraHandledException(
                'No CMS Channel Id set on MA_Offering__mdt for "' + offeringKey + '". ' +
                'Set MA_Offering__mdt.CMS_Channel_Id__c (Setup > Custom Metadata Types > MA Offering).'
            );
        }
        String channelId = offerings[0].CMS_Channel_Id__c;

        List<MA_CMS_Content_Index__c> indexRows = [
            SELECT CMS_Record_Id__c, Content_Type__c
            FROM MA_CMS_Content_Index__c
            WHERE Offering_Key__c = :offeringKey AND Active__c = true
            ORDER BY Content_Type__c, Display_Order__c NULLS LAST, CMS_Record_Id__c
        ];

        StoryContent result = new StoryContent();
        for (MA_CMS_Content_Index__c row : indexRows) {
            Map<String, Object> contentBody = fetchContentBody(channelId, row.CMS_Record_Id__c);
            if (contentBody == null) {
                continue;
            }
            if (row.Content_Type__c == INDUSTRY_TYPE) {
                result.industries.add(toIndustryStory(contentBody));
            } else if (row.Content_Type__c == FAQ_TYPE) {
                result.faqs.add(toFaqItem(contentBody));
            } else if (row.Content_Type__c == SETTING_TYPE && result.setting == null) {
                result.setting = toStorySetting(contentBody);
            }
        }
        return result;
    }

    // ---------------------------------------------------------------- fetch

    private static Map<String, Object> fetchContentBody(String channelId, String recordId) {
        try {
            String endpoint = URL.getOrgDomainUrl().toExternalForm()
                + '/services/data/' + API_VERSION
                + '/connect/cms/delivery/channels/' + channelId + '/contents/' + recordId;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(TIMEOUT_MS);
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                return null;
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (Map<String, Object>) body.get('contentBody');
        } catch (Exception e) {
            return null;
        }
    }

    // -------------------------------------------------------------- mapping

    private static IndustryStory toIndustryStory(Map<String, Object> body) {
        IndustryStory s = new IndustryStory();
        s.industryKey = str(body, 'industryKey');
        s.industryLabel = str(body, 'industryLabel');
        s.coverSub = str(body, 'coverSub');
        s.problem = str(body, 'problem');
        s.useCase = str(body, 'useCase');
        s.solution = str(body, 'solution');
        s.uniquePoints = lines(body, 'uniquePoints');
        s.proofLine = str(body, 'proofLine');
        s.whyLine = str(body, 'whyLine');
        s.whyHead = str(body, 'whyHead');
        s.demoRoot = str(body, 'demoRoot');
        s.demoDeps = lines(body, 'demoDeps');
        return s;
    }

    private static FaqItem toFaqItem(Map<String, Object> body) {
        FaqItem f = new FaqItem();
        f.question = str(body, 'title');
        f.answer = str(body, 'answer');
        f.verdict = str(body, 'verdict');
        return f;
    }

    private static StorySetting toStorySetting(Map<String, Object> body) {
        StorySetting s = new StorySetting();
        s.defaultSourcePlatform = str(body, 'defaultSourcePlatform');
        s.defaultTargetPlatform = str(body, 'defaultTargetPlatform');
        s.defaultAssetCount = str(body, 'defaultAssetCount');
        s.defaultDependencyCount = str(body, 'defaultDependencyCount');
        s.defaultHealthScore = str(body, 'defaultHealthScore');
        s.genericDemoRoot = str(body, 'genericDemoRoot');
        s.genericDemoDeps = lines(body, 'genericDemoDeps');
        s.genericChips = lines(body, 'genericChips');
        for (String line : lines(body, 'swatches')) {
            List<String> parts = line.split('\\|', 2);
            if (parts.size() == 2) {
                Swatch sw = new Swatch();
                sw.name = parts[0].trim();
                sw.hex = parts[1].trim();
                s.swatches.add(sw);
            }
        }
        return s;
    }

    private static String str(Map<String, Object> body, String key) {
        Object value = body.get(key);
        if (value == null) {
            return null;
        }
        return unwrapOuterParagraph(String.valueOf(value).unescapeHtml4());
    }

    /**
     * RTE node values come back as a single wrapping <p>...</p> for a
     * plain-paragraph field (the CMS authoring editor's default block).
     * Every template consuming these already supplies its own block-level
     * wrapper with its own CSS classes, so stripping just the one
     * outermost pair here avoids double-nested <p> tags once rendered --
     * invalid HTML that would otherwise silently break layout. Any inline
     * markup a BA adds inside (bold, a link) is untouched; this only
     * unwraps a single leading/trailing paragraph tag, not markup generally.
     * A no-op for TEXT/MTEXT field values, which were never <p>-wrapped.
     */
    private static String unwrapOuterParagraph(String html) {
        if (String.isBlank(html)) {
            return html;
        }
        String trimmed = html.trim();
        Boolean wrapped =
            trimmed.toLowerCase().startsWith('<p>') &&
            trimmed.toLowerCase().endsWith('</p>') &&
            trimmed.toLowerCase().indexOf('<p>', 3) == -1;
        if (!wrapped) {
            return html;
        }
        return trimmed.substring(3, trimmed.length() - 4).trim();
    }

    private static List<String> lines(Map<String, Object> body, String key) {
        String raw = str(body, key);
        List<String> result = new List<String>();
        if (String.isBlank(raw)) {
            return result;
        }
        for (String line : raw.split('\n')) {
            if (String.isNotBlank(line)) {
                result.add(line.trim());
            }
        }
        return result;
    }
}
