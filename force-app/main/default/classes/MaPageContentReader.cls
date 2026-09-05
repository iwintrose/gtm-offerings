/**
 * Public, read-only reader for MA_Page_Content__c.
 *
 * Why this class exists instead of reusing MaPageContentController:
 * Apex class access is granted per CLASS, not per method. Granting an
 * Experience Cloud guest user access to MaPageContentController would also
 * expose its @AuraEnabled write methods (saveContentRecord,
 * saveContentRecords, deleteContentRecord) to anonymous site traffic. This
 * class exposes the read path only, so the guest profile can resolve page
 * content without ever gaining a write surface.
 *
 * without sharing: content rows are owned by the admin who authored them, so
 * a guest user running with sharing would resolve zero rows.
 */
public without sharing class MaPageContentReader {

    /** Where industries live: the framework's own industry chooser page. */
    private static final String INDUSTRY_OWNER    = 'gtm';
    private static final String INDUSTRY_TEMPLATE = 'industry-chooser';


    /**
     * Resolves every active content row for a template into a flat map keyed
     * 'section::field'. Industry-scoped rows win over offering-wide defaults
     * for the same key.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPageContent(String offeringKey, String templateType, String industryKey) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) {
            return result;
        }

        List<MA_Page_Content__c> records = [
            SELECT Section_Key__c, Field_Key__c, Field_Type__c,
                   Text_Value__c, Rich_Value__c, JSON_Value__c, Industry_Key__c
            FROM   MA_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            AND    (Industry_Key__c = :industryKey OR Industry_Key__c = null OR Industry_Key__c = '')
            ORDER BY Industry_Key__c NULLS LAST, Sort_Order__c ASC
            LIMIT 1000
        ];

        for (MA_Page_Content__c rec : records) {
            String mapKey = rec.Section_Key__c + '::' + rec.Field_Key__c;
            if (!result.containsKey(mapKey)) {
                result.put(mapKey, resolveValue(rec));
            }
        }
        return result;
    }

    /**
     * Returns the page's structure and its content together: the ordered,
     * active sections plus the flat content map. One call so the renderer
     * never paints a section before its content has arrived.
     */
    @AuraEnabled(cacheable=true)
    public static PageLayout getPageLayout(String offeringKey, String templateType, String industryKey) {
        PageLayout layout = new PageLayout();
        layout.content = getPageContent(offeringKey, templateType, industryKey);
        layout.fieldMeta = getFieldMeta(offeringKey, templateType, industryKey);
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) {
            return layout;
        }

        for (MA_Page_Section__c sec : [
            SELECT Section_Key__c, Label__c, Help_Text__c, Layout_Type__c, Width__c, Sort_Order__c
            FROM   MA_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            // Draft_State__c is deliberately not read here: the public page
            // shows what was published, and a pending reorder, hide or delete
            // is not published. A section created in the editor is Draft until
            // someone publishes it, so it does not appear at all.
            AND    Status__c        = 'Published'
            ORDER BY Sort_Order__c ASC NULLS LAST, Section_Key__c ASC
            LIMIT 200
        ]) {
            SectionDto dto = new SectionDto();
            dto.sectionKey = sec.Section_Key__c;
            dto.label      = sec.Label__c;
            dto.helpText   = sec.Help_Text__c;
            dto.layoutType = sec.Layout_Type__c;
            dto.width      = sec.Width__c;
            dto.sortOrder  = sec.Sort_Order__c;
            layout.sections.add(dto);
        }
        return layout;
    }

    public class PageLayout {
        @AuraEnabled public List<SectionDto> sections = new List<SectionDto>();
        @AuraEnabled public Map<String, String> content = new Map<String, String>();
        // Every field's type and label, so the renderer can draw fields the
        // layout never declared. The flat content map above carries values
        // only, which is enough to resolve a known field and not enough to
        // draw an unknown one.
        @AuraEnabled public List<FieldMeta> fieldMeta = new List<FieldMeta>();
    }

    public class FieldMeta {
        @AuraEnabled public String sectionKey;
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String fieldType;
        @AuraEnabled public String label;
        // Presentation, applied to the element on render.
        @AuraEnabled public String cssClass;
        @AuraEnabled public String htmlId;
        @AuraEnabled public String inlineStyle;
    }

    public class SectionDto {
        @AuraEnabled public String sectionKey;
        @AuraEnabled public String label;
        @AuraEnabled public String helpText;
        @AuraEnabled public String layoutType;
        @AuraEnabled public String width;
        @AuraEnabled public Decimal sortOrder;
    }

    private static String resolveValue(MA_Page_Content__c rec) {
        // icontext keeps a label and an icon together, so it stores where the
        // other structured type does. Anything unrecognised reads as text,
        // which is the one column every field has.
        if (rec.Field_Type__c == 'rich') return rec.Rich_Value__c;
        if (rec.Field_Type__c == 'json' || rec.Field_Type__c == 'icontext') return rec.JSON_Value__c;
        return rec.Text_Value__c;
    }

    /**
     * The type and label of every field on the page. A field marked for
     * deletion is still published, so it is still described here; it stops
     * being returned when the delete is published and the row goes.
     */
    private static List<FieldMeta> getFieldMeta(
        String offeringKey, String templateType, String industryKey
    ) {
        List<FieldMeta> out = new List<FieldMeta>();
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) return out;
        Set<String> seen = new Set<String>();
        for (MA_Page_Content__c rec : [
            SELECT Section_Key__c, Field_Key__c, Field_Type__c, Label__c,
                   Css_Class__c, Html_Id__c, Inline_Style__c
            FROM   MA_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            AND    (Industry_Key__c = :industryKey OR Industry_Key__c = null OR Industry_Key__c = '')
            ORDER BY Industry_Key__c NULLS LAST, Sort_Order__c ASC
            LIMIT 1000
        ]) {
            String addr = rec.Section_Key__c + '::' + rec.Field_Key__c;
            // Same precedence as getPageContent: the industry-specific row wins
            // and the generic one is skipped, so the two never disagree.
            if (seen.contains(addr)) continue;
            seen.add(addr);
            FieldMeta m = new FieldMeta();
            m.sectionKey = rec.Section_Key__c;
            m.fieldKey   = rec.Field_Key__c;
            m.fieldType  = rec.Field_Type__c;
            m.label      = rec.Label__c;
            m.cssClass    = rec.Css_Class__c;
            m.htmlId      = rec.Html_Id__c;
            m.inlineStyle = rec.Inline_Style__c;
            out.add(m);
        }
        return out;
    }

    public class OfferingTile {
        @AuraEnabled public String offeringKey  { get; set; }
        @AuraEnabled public String mark         { get; set; }
        @AuraEnabled public String name         { get; set; }
        @AuraEnabled public String description  { get; set; }
        @AuraEnabled public Boolean isLive      { get; set; }
    }

    /**
     * Every offering's own entry for the offerings page.
     *
     * The offerings page sits above offerings and lists them, so its tiles are
     * not its own content — each offering supplies its entry, under its own
     * offerings-listing page. Adding the second offering is then a metadata
     * record plus its tile copy, and the front door picks it up with no edit
     * of its own.
     *
     * An offering with no tile content yet is returned as a placeholder rather
     * than skipped, so the page shows the shape of what is coming.
     */
    @AuraEnabled(cacheable=true)
    public static List<OfferingTile> getOfferingTiles() {
        List<OfferingTile> out = new List<OfferingTile>();
        Map<String, OfferingTile> byKey = new Map<String, OfferingTile>();
        for (MA_Offering__mdt off : [
            SELECT Offering_Key__c, Label__c FROM MA_Offering__mdt ORDER BY Label__c
        ]) {
            if (String.isBlank(off.Offering_Key__c)) continue;
            OfferingTile t = new OfferingTile();
            t.offeringKey = off.Offering_Key__c;
            t.name        = off.Label__c;
            t.isLive      = false;
            byKey.put(t.offeringKey, t);
            out.add(t);
        }
        if (byKey.isEmpty()) return out;

        for (MA_Page_Content__c rec : [
            SELECT Offering_Key__c, Field_Key__c, Field_Type__c,
                   Text_Value__c, Rich_Value__c, JSON_Value__c
            FROM   MA_Page_Content__c
            WHERE  Template_Type__c = 'offerings-listing'
            AND    Section_Key__c   = 'tile'
            AND    Active__c        = true
            AND    Offering_Key__c IN :byKey.keySet()
            LIMIT  500
        ]) {
            OfferingTile t = byKey.get(rec.Offering_Key__c);
            if (t == null) continue;
            String value = resolveValue(rec);
            if (String.isBlank(value)) continue;
            if (rec.Field_Key__c == 'mark')             { t.mark = value; }
            else if (rec.Field_Key__c == 'name')        { t.name = value; }
            else if (rec.Field_Key__c == 'description') { t.description = value; }
            // A tile counts as live once it says something about itself.
            t.isLive = String.isNotBlank(t.description);
        }
        return out;
    }

    public class IndustryProfile {
        @AuraEnabled public String industryKey     { get; set; }
        @AuraEnabled public String industryLabel   { get; set; }
        @AuraEnabled public String pickerBlurb     { get; set; }
        @AuraEnabled public String coverSub        { get; set; }
        @AuraEnabled public String problem         { get; set; }
        @AuraEnabled public String useCase         { get; set; }
        @AuraEnabled public String solution        { get; set; }
        @AuraEnabled public List<String> uniquePoints = new List<String>();
        @AuraEnabled public String proofLine       { get; set; }
        @AuraEnabled public String whyLine         { get; set; }
        @AuraEnabled public String whyHead         { get; set; }
        @AuraEnabled public String demoRoot        { get; set; }
        @AuraEnabled public List<String> demoDeps  = new List<String>();
    }

    /**
     * Every industry profile modelled for a page, keyed by which section
     * carries it.
     *
     * An industry is not a section in the sequence the way a beat is — it is
     * one of several alternate profiles a visitor picks between — so each
     * lives under its own section key (industry-<key>) rather than sharing one
     * the way declared fields normally do. This is the enumeration query
     * the industry picker needs; a single industry's profile for the
     * configurator is one entry in this same list, matched by key.
     */
    @AuraEnabled(cacheable=true)
    public static List<IndustryProfile> getIndustryProfiles(String offeringKey, String templateType) {
        List<IndustryProfile> out = new List<IndustryProfile>();
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) return out;

        // Industries belong to the framework, not to an offering.
        //
        // The arguments are kept because every caller passes them and the
        // signature is public, but they no longer choose where the copy is
        // read from: an industry has one home. The configurator draws one
        // cover, so it had no business holding six industry sections -- the
        // editor listed six rows for a single element of the page, and the
        // same industry's copy existed twice.
        Map<String, IndustryProfile> bySection = new Map<String, IndustryProfile>();
        for (MA_Page_Content__c rec : [
            SELECT Section_Key__c, Field_Key__c, Field_Type__c,
                   Text_Value__c, Rich_Value__c, JSON_Value__c
            FROM   MA_Page_Content__c
            WHERE  Offering_Key__c  = :INDUSTRY_OWNER
            AND    Template_Type__c = :INDUSTRY_TEMPLATE
            AND    Active__c        = true
            AND    Section_Key__c LIKE 'industry-%'
            ORDER BY Section_Key__c
            LIMIT  2000
        ]) {
            IndustryProfile p = bySection.get(rec.Section_Key__c);
            if (p == null) {
                p = new IndustryProfile();
                // 'industry-' is 9 characters; strip it to recover the key.
                p.industryKey = rec.Section_Key__c.substring(9);
                bySection.put(rec.Section_Key__c, p);
                out.add(p);
            }
            String value = resolveValue(rec);
            if (String.isBlank(value)) continue;
            if (rec.Field_Key__c == 'industryLabel')     { p.industryLabel = value; }
            else if (rec.Field_Key__c == 'pickerBlurb')  { p.pickerBlurb = value; }
            else if (rec.Field_Key__c == 'coverSub')     { p.coverSub = value; }
            else if (rec.Field_Key__c == 'problem')      { p.problem = value; }
            else if (rec.Field_Key__c == 'useCase')      { p.useCase = value; }
            else if (rec.Field_Key__c == 'solution')     { p.solution = value; }
            else if (rec.Field_Key__c == 'proofLine')    { p.proofLine = value; }
            else if (rec.Field_Key__c == 'whyLine')      { p.whyLine = value; }
            else if (rec.Field_Key__c == 'whyHead')      { p.whyHead = value; }
            else if (rec.Field_Key__c == 'demoRoot')     { p.demoRoot = value; }
            else if (rec.Field_Key__c == 'uniquePoints') {
                try { p.uniquePoints = (List<String>) JSON.deserialize(value, List<String>.class); }
                catch (Exception e) { /* malformed row, leave empty rather than fail the page */ }
            } else if (rec.Field_Key__c == 'demoDeps') {
                try { p.demoDeps = (List<String>) JSON.deserialize(value, List<String>.class); }
                catch (Exception e) { /* malformed row, leave empty rather than fail the page */ }
            }
        }
        return out;
    }

    public class SiteInfo {
        @AuraEnabled public String orgUrl;
        @AuraEnabled public String lightningUrl;
        @AuraEnabled public List<NetworkSite> sites = new List<NetworkSite>();
    }

    public class NetworkSite {
        @AuraEnabled public String networkId;
        @AuraEnabled public String urlPathPrefix;
    }

    /**
     * The org and Experience Cloud site URLs the "Edit in Builder" chip needs.
     * Split out from what used to be part of the CMS-backed getStoryContent so
     * that call can be retired without losing the one thing every public page
     * still needs from it: none of this reads MA_CMS_Content_Index__c or the
     * CMS delivery API.
     */
    @AuraEnabled(cacheable=true)
    public static SiteInfo getSiteInfo() {
        SiteInfo info = new SiteInfo();
        String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
        info.orgUrl = orgDomainUrl;
        info.lightningUrl = orgDomainUrl.replace('.my.salesforce.com', '.lightning.force.com');
        try {
            for (Network net : [SELECT Id, UrlPathPrefix FROM Network ORDER BY UrlPathPrefix]) {
                NetworkSite si = new NetworkSite();
                si.networkId = String.valueOf(net.Id);
                si.urlPathPrefix = net.UrlPathPrefix;
                info.sites.add(si);
            }
        } catch (Exception e) {
            // Builder deep-link is progressive enhancement; a page still works
            // without the site list.
        }
        return info;
    }
}
