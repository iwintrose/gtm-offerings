/**
 * Reads the GTM Offerings story page's editorial content (industry blocks,
 * FAQ, site defaults) from Salesforce CMS via HTTP self-callout.
 *
 * Must be cacheable=false: the LDS wire cache blocks HTTP callouts in
 * cacheable=true methods and silently returns empty results.
 *
 * Must be without sharing: CMS index rows are owned by the admin user;
 * with sharing returns zero rows for Experience Cloud community members.
 *
 * MA_CMS_Content_Index__c is the bridge: one row per CMS record, giving this
 * controller a SOQL-queryable list of managed content IDs to fetch.
 */
public without sharing class MaStoryContentController {
    private static final String INDUSTRY_TYPE = 'ma_industry_story';
    private static final String FAQ_TYPE = 'ma_faq_item';
    private static final String SETTING_TYPE = 'ma_story_setting';
    private static final String PAGE_TYPE = 'ma_story_page';
    private static final String BODY_TYPE = 'ma_story_body';
    private static final Integer TIMEOUT_MS = 8000;
    private static final String API_VERSION = 'v66.0';

    public class SiteInfo {
        @AuraEnabled public String networkId;
        @AuraEnabled public String urlPathPrefix;
    }

    public class StoryContent {
        @AuraEnabled public List<IndustryStory> industries = new List<IndustryStory>();
        @AuraEnabled public List<FaqItem> faqs = new List<FaqItem>();
        @AuraEnabled public StorySetting setting;
        @AuraEnabled public StoryPage page;
        @AuraEnabled public StoryBody body;
        @AuraEnabled public String orgUrl;
        @AuraEnabled public String lightningUrl;
        @AuraEnabled public String cmsChannelId;
        @AuraEnabled public String pageContentId;
        @AuraEnabled public String pageIndexRecordId;
        @AuraEnabled public String bodyContentId;
        @AuraEnabled public String bodyIndexRecordId;
        @AuraEnabled public List<SiteInfo> sites = new List<SiteInfo>();
    }

    public class IndustryStory {
        @AuraEnabled public String industryKey;
        @AuraEnabled public String industryLabel;
        @AuraEnabled public String pickerBlurb;
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
        @AuraEnabled public String contentId;
        @AuraEnabled public String indexRecordId;
    }

    public class FaqItem {
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String verdict;
        @AuraEnabled public String contentId;
        @AuraEnabled public String indexRecordId;
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
        @AuraEnabled public String offeringTileDescription;
    }

    public class StoryPage {
        @AuraEnabled public String heroEyebrow;
        @AuraEnabled public String heroHeadline;
        @AuraEnabled public String heroSubhead;
        @AuraEnabled public String proofObjectsCount;
        @AuraEnabled public String proofDepsCount;
        @AuraEnabled public String proofHealthScore;
        @AuraEnabled public String problemLede;
        @AuraEnabled public List<String> problemChips = new List<String>();
        @AuraEnabled public String problemClose;
        @AuraEnabled public String mechanismHead;
        @AuraEnabled public String mechanismSub;
        @AuraEnabled public String closingHead;
        @AuraEnabled public String closingSub;
    }

    public class RouteStep {
        @AuraEnabled public String stepLabel;
        @AuraEnabled public String stepDesc;
    }

    public class CapabilityCard {
        @AuraEnabled public String icon;
        @AuraEnabled public String cardTitle;
        @AuraEnabled public String cardDesc;
        @AuraEnabled public Boolean isNew;
    }

    public class UseCase {
        @AuraEnabled public String caseTitle;
        @AuraEnabled public String caseDesc;
    }

    public class StoryBody {
        @AuraEnabled public List<RouteStep> routeSteps = new List<RouteStep>();
        @AuraEnabled public String proofCtaText;
        @AuraEnabled public String proofDemoRoot;
        @AuraEnabled public List<String> proofDemoDeps = new List<String>();
        @AuraEnabled public List<CapabilityCard> capabilities = new List<CapabilityCard>();
        @AuraEnabled public String bonusCard;
        @AuraEnabled public String clientStatBig;
        @AuraEnabled public String clientStatDesc;
        @AuraEnabled public String clientNote;
        @AuraEnabled public String bdHead;
        @AuraEnabled public String bdLede;
        @AuraEnabled public List<UseCase> bdUseCases = new List<UseCase>();
        @AuraEnabled public List<String> pitchOldChips = new List<String>();
        @AuraEnabled public List<String> pitchNewChips = new List<String>();
    }

    @AuraEnabled(cacheable=false)
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
        String channelId = offerings[0].CMS_Channel_Id__c;

        List<MA_CMS_Content_Index__c> indexRows = [
            SELECT Id, CMS_Record_Id__c, Content_Type__c
            FROM MA_CMS_Content_Index__c
            WHERE Offering_Key__c = :offeringKey AND Active__c = true
            ORDER BY Content_Type__c, Display_Order__c NULLS LAST, CMS_Record_Id__c
        ];

        if (indexRows.isEmpty()) {
            return new StoryContent();
        }

        StoryContent result = new StoryContent();
        String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
        result.orgUrl = orgDomainUrl;
        // Experience Builder runs on the Lightning domain, not the My Domain URL.
        // Transform: https://org.develop.my.salesforce.com
        //         -> https://org.develop.lightning.force.com
        result.lightningUrl = orgDomainUrl.replace('.my.salesforce.com', '.lightning.force.com');
        result.cmsChannelId = channelId;

        // Build Experience Builder deep-link data: one entry per Experience Cloud site.
        // NetworkPage is not SOQL-accessible (metadata-only), so we return networkId +
        // urlPathPrefix only. LWC matches on urlPathPrefix to open Builder inside the
        // correct site rather than the generic All-Sites list.
        try {
            for (Network net : [SELECT Id, UrlPathPrefix FROM Network ORDER BY UrlPathPrefix]) {
                SiteInfo si = new SiteInfo();
                si.networkId = String.valueOf(net.Id);
                si.urlPathPrefix = net.UrlPathPrefix;
                result.sites.add(si);
            }
        } catch (Exception e) {
            System.debug('[MaStoryContentController] Network query: ' + e.getMessage());
        }

        for (MA_CMS_Content_Index__c row : indexRows) {
            Map<String, Object> body = fetchContentBody(channelId, row.CMS_Record_Id__c);
            if (body == null) {
                continue;
            }
            if (row.Content_Type__c == INDUSTRY_TYPE) {
                result.industries.add(toIndustryStory(body, row));
            } else if (row.Content_Type__c == FAQ_TYPE) {
                result.faqs.add(toFaqItem(body, row));
            } else if (row.Content_Type__c == SETTING_TYPE && result.setting == null) {
                result.setting = toStorySetting(body);
            } else if (row.Content_Type__c == PAGE_TYPE && result.page == null) {
                result.page = toStoryPage(body);
                result.pageContentId = row.CMS_Record_Id__c;
                result.pageIndexRecordId = String.valueOf(row.Id);
            } else if (row.Content_Type__c == BODY_TYPE && result.body == null) {
                result.body = toStoryBody(body);
                result.bodyContentId = row.CMS_Record_Id__c;
                result.bodyIndexRecordId = String.valueOf(row.Id);
            }
        }
        return result;
    }

    private static Map<String, Object> fetchContentBody(String channelId, String recordId) {
        try {
            String sid = UserInfo.getSessionId();
            String endpoint = URL.getOrgDomainUrl().toExternalForm()
                + '/services/data/' + API_VERSION
                + '/connect/cms/delivery/channels/' + channelId
                + '/contents/' + recordId;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(TIMEOUT_MS);
            // Guest users have no API session ID; the CMS delivery channel is
            // configured for public access on this Experience Cloud site, so
            // the callout works without an Authorization header for them.
            // Authenticated reps get the header as before.
            if (String.isNotBlank(sid)) {
                req.setHeader('Authorization', 'Bearer ' + sid);
            }

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                System.debug('[MaStoryContentController] HTTP ' + res.getStatusCode()
                    + ' for ' + recordId + ': ' + res.getBody());
                return null;
            }
            Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (Map<String, Object>) envelope.get('contentBody');
        } catch (Exception e) {
            System.debug('[MaStoryContentController] callout error for ' + recordId + ': ' + e.getMessage());
            return null;
        }
    }

    // -------------------------------------------------------------- mapping

    private static IndustryStory toIndustryStory(Map<String, Object> body, MA_CMS_Content_Index__c row) {
        IndustryStory s = new IndustryStory();
        s.industryKey = str(body, 'industryKey');
        s.industryLabel = str(body, 'industryLabel');
        s.pickerBlurb = str(body, 'pickerBlurb');
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
        s.contentId = row.CMS_Record_Id__c;
        s.indexRecordId = String.valueOf(row.Id);
        return s;
    }

    private static FaqItem toFaqItem(Map<String, Object> body, MA_CMS_Content_Index__c row) {
        FaqItem f = new FaqItem();
        f.question = str(body, 'title');
        f.answer = str(body, 'answer');
        f.verdict = str(body, 'verdict');
        f.contentId = row.CMS_Record_Id__c;
        f.indexRecordId = String.valueOf(row.Id);
        return f;
    }

    private static StorySetting toStorySetting(Map<String, Object> body) {
        StorySetting s = new StorySetting();
        s.offeringTileDescription = str(body, 'offeringTileDescription');
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

    private static StoryPage toStoryPage(Map<String, Object> body) {
        StoryPage p = new StoryPage();
        p.heroEyebrow = str(body, 'heroEyebrow');
        p.heroHeadline = str(body, 'heroHeadline');
        p.heroSubhead = str(body, 'heroSubhead');
        p.proofObjectsCount = str(body, 'proofObjectsCount');
        p.proofDepsCount = str(body, 'proofDepsCount');
        p.proofHealthScore = str(body, 'proofHealthScore');
        p.problemLede = str(body, 'problemLede');
        p.problemChips = lines(body, 'problemChips');
        p.problemClose = str(body, 'problemClose');
        p.mechanismHead = str(body, 'mechanismHead');
        p.mechanismSub = str(body, 'mechanismSub');
        p.closingHead = str(body, 'closingHead');
        p.closingSub = str(body, 'closingSub');
        return p;
    }

    private static StoryBody toStoryBody(Map<String, Object> body) {
        StoryBody b = new StoryBody();
        for (String line : lines(body, 'routeSteps')) {
            List<String> parts = line.split('\\|', 2);
            if (parts.size() == 2) {
                RouteStep rs = new RouteStep();
                rs.stepLabel = parts[0].trim();
                rs.stepDesc = parts[1].trim();
                b.routeSteps.add(rs);
            }
        }
        b.proofCtaText = str(body, 'proofCtaText');
        List<String> demoNodes = lines(body, 'proofDemoNodes');
        if (!demoNodes.isEmpty()) {
            b.proofDemoRoot = demoNodes[0];
            for (Integer i = 1; i < demoNodes.size(); i++) {
                b.proofDemoDeps.add(demoNodes[i]);
            }
        }
        for (String line : lines(body, 'capabilities')) {
            List<String> parts = line.split('\\|', 4);
            if (parts.size() >= 3) {
                CapabilityCard c = new CapabilityCard();
                c.icon = parts[0].trim();
                c.cardTitle = parts[1].trim();
                c.cardDesc = parts[2].trim();
                c.isNew = parts.size() == 4 && parts[3].trim().equalsIgnoreCase('true');
                b.capabilities.add(c);
            }
        }
        b.bonusCard = str(body, 'bonusCard');
        b.clientStatBig = str(body, 'clientStatBig');
        b.clientStatDesc = str(body, 'clientStatDesc');
        b.clientNote = str(body, 'clientNote');
        b.bdHead = str(body, 'bdHead');
        b.bdLede = str(body, 'bdLede');
        for (String line : lines(body, 'bdUseCases')) {
            List<String> parts = line.split('\\|', 2);
            if (parts.size() == 2) {
                UseCase uc = new UseCase();
                uc.caseTitle = parts[0].trim();
                uc.caseDesc = parts[1].trim();
                b.bdUseCases.add(uc);
            }
        }
        b.pitchOldChips = lines(body, 'pitchOldChips');
        b.pitchNewChips = lines(body, 'pitchNewChips');
        return b;
    }

    private static String str(Map<String, Object> body, String key) {
        if (body == null) return null;
        Object val = body.get(key);
        if (val == null) return null;
        return unwrapOuterParagraph(String.valueOf(val).unescapeHtml4());
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
