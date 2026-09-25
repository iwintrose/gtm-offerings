/**
 * Public, read-only reader for GTM_Page_Content__c.
 *
 * Why this class exists instead of reusing GtmPageContentController:
 * Apex class access is granted per CLASS, not per method. Granting an
 * Experience Cloud guest user access to GtmPageContentController would also
 * expose its @AuraEnabled write methods (saveContentRecord,
 * saveContentRecords, deleteContentRecord) to anonymous site traffic. This
 * class exposes the read path only, so the guest profile can resolve page
 * content without ever gaining a write surface.
 *
 * without sharing: content rows are owned by the admin who authored them, so
 * a guest user running with sharing would resolve zero rows.
 */
public without sharing class GtmPageContentReader {

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

        List<GTM_Page_Content__c> records = [
            SELECT Section_Key__c, Field_Key__c, Field_Type__c,
                   Text_Value__c, Rich_Value__c, JSON_Value__c, Industry_Key__c
            FROM   GTM_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            AND    (Industry_Key__c = :industryKey OR Industry_Key__c = null OR Industry_Key__c = '')
            ORDER BY Industry_Key__c NULLS LAST, Sort_Order__c ASC
            LIMIT 1000
        ];

        // Whole-section-variant keys, per base section, for this industry.
        // Any content row addressed under a live variant's own section key
        // is remapped to the base key below, so the renderer never needs to
        // know a variant key exists.
        Map<String, GTM_Page_Section__c> variantsByBase =
            variantSectionsByBase(offeringKey, templateType, industryKey);
        Map<String, String> baseKeyByVariantKey = new Map<String, String>();
        for (String baseKey : variantsByBase.keySet()) {
            baseKeyByVariantKey.put(variantsByBase.get(baseKey).Section_Key__c, baseKey);
        }

        for (GTM_Page_Content__c rec : records) {
            String sectionKey = baseKeyByVariantKey.containsKey(rec.Section_Key__c)
                ? baseKeyByVariantKey.get(rec.Section_Key__c)
                : rec.Section_Key__c;
            String mapKey = sectionKey + '::' + rec.Field_Key__c;
            if (!result.containsKey(mapKey)) {
                result.put(mapKey, resolveValue(rec));
            }
        }
        return result;
    }

    /**
     * The Published/Active variant section per base section key, for one
     * industry -- keyed by Base_Section_Key__c. Empty when no industry is
     * selected, so the no-industry / generic case is untouched.
     *
     * Only Published + Active variant rows are considered, the same "what is
     * live" rule every other section is read under (see getPageLayout).
     */
    private static Map<String, GTM_Page_Section__c> variantSectionsByBase(
        String offeringKey, String templateType, String industryKey
    ) {
        Map<String, GTM_Page_Section__c> out = new Map<String, GTM_Page_Section__c>();
        if (String.isBlank(offeringKey) || String.isBlank(templateType) || String.isBlank(industryKey)) {
            return out;
        }
        for (GTM_Page_Section__c sec : [
            SELECT Section_Key__c, Base_Section_Key__c, Label__c, Layout_Type__c, Width__c
            FROM   GTM_Page_Section__c
            WHERE  Offering_Key__c    = :offeringKey
            AND    Template_Type__c   = :templateType
            AND    Active__c          = true
            AND    Status__c          = 'Published'
            AND    Industry_Key__c    = :industryKey
            AND    Base_Section_Key__c != null
            LIMIT  200
        ]) {
            out.put(sec.Base_Section_Key__c, sec);
        }
        return out;
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

        // Whole-section variant substitution: a base section whose base key
        // has a live variant for this industry shows the variant's label/
        // layout/width, but keeps its own sectionKey.
        Map<String, GTM_Page_Section__c> variantsByBase =
            variantSectionsByBase(offeringKey, templateType, industryKey);

        List<GTM_Page_Section__c> baseSections = [
            SELECT Section_Key__c, Label__c, Help_Text__c, Layout_Type__c, Width__c, Sort_Order__c,
                   Hidden_For_Industry__c, Industry_Sort_Overrides__c
            FROM   GTM_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            // Draft_State__c is deliberately not read here: the public page
            // shows what was published, and a pending reorder, hide or delete
            // is not published. A section created in the editor is Draft until
            // someone publishes it, so it does not appear at all.
            AND    Status__c        = 'Published'
            // Variant rows are addressed under their own key
            // (<baseKey>--<industrySlug>) and never render as their own
            // sequence entry -- they only substitute into their base's entry
            // above, via variantsByBase.
            AND    Base_Section_Key__c = null
            ORDER BY Sort_Order__c ASC NULLS LAST, Section_Key__c ASC
            LIMIT 200
        ];

        layout.sections = resolveForIndustry(baseSections, variantsByBase, industryKey);
        return layout;
    }

    /**
     * The single resolution point for everything industry-aware about a
     * page's section sequence: skip a section hidden for this industry,
     * substitute a live whole-section variant where one exists, apply this
     * industry's sort override, then re-sort. Every caller that needs an
     * industry-resolved section list goes through here rather than
     * duplicating any one of these three steps on its own -- see
     * #industry-variants-visibility-nav.
     */
    private static List<SectionDto> resolveForIndustry(
        List<GTM_Page_Section__c> baseSections,
        Map<String, GTM_Page_Section__c> variantsByBase,
        String industryKey
    ) {
        List<SectionDto> out = new List<SectionDto>();
        for (GTM_Page_Section__c sec : baseSections) {
            if (isHiddenForIndustry(sec, industryKey)) continue;
            GTM_Page_Section__c variant = variantsByBase.get(sec.Section_Key__c);
            SectionDto dto = new SectionDto();
            dto.sectionKey = sec.Section_Key__c;
            dto.label      = variant != null ? variant.Label__c      : sec.Label__c;
            dto.helpText   = sec.Help_Text__c;
            dto.layoutType = variant != null ? variant.Layout_Type__c : sec.Layout_Type__c;
            dto.width      = variant != null ? variant.Width__c       : sec.Width__c;
            dto.sortOrder  = sortOrderForIndustry(sec, industryKey);
            out.add(dto);
        }
        out.sort(new BySortOrder());
        return out;
    }

    /** True when this base section's Hidden_For_Industry__c names this industry. */
    private static Boolean isHiddenForIndustry(GTM_Page_Section__c sec, String industryKey) {
        if (String.isBlank(industryKey) || String.isBlank(sec.Hidden_For_Industry__c)) return false;
        for (String slug : sec.Hidden_For_Industry__c.split(',')) {
            if (slug.trim().equalsIgnoreCase(industryKey)) return true;
        }
        return false;
    }

    /**
     * This section's sort value for one industry: the override for that
     * industry where Industry_Sort_Overrides__c names one, the section's own
     * Sort_Order__c otherwise. Sort_Order__c itself is never written by this
     * -- the generic/default order stays owned by the core issue's fields.
     */
    private static Decimal sortOrderForIndustry(GTM_Page_Section__c sec, String industryKey) {
        if (String.isBlank(industryKey) || String.isBlank(sec.Industry_Sort_Overrides__c)) {
            return sec.Sort_Order__c;
        }
        try {
            Object parsed = JSON.deserializeUntyped(sec.Industry_Sort_Overrides__c);
            if (!(parsed instanceof Map<String, Object>)) return sec.Sort_Order__c;
            Map<String, Object> overrides = (Map<String, Object>) parsed;
            // 'override' is an Apex reserved word (virtual/override methods)
            // and cannot be used as a variable identifier here.
            Object overrideValue = overrides.get(industryKey);
            if (overrideValue == null) return sec.Sort_Order__c;
            return Decimal.valueOf(String.valueOf(overrideValue));
        } catch (Exception e) {
            // An unreadable override is not a reason to fail the page; fall
            // back to the section's own order.
            return sec.Sort_Order__c;
        }
    }

    /** Orders resolved sections by their (possibly overridden) sort, key as tiebreak. */
    private class BySortOrder implements Comparator<SectionDto> {
        public Integer compare(SectionDto a, SectionDto b) {
            if (a.sortOrder == null && b.sortOrder == null) {
                return a.sectionKey.compareTo(b.sectionKey);
            }
            if (a.sortOrder == null) return 1;
            if (b.sortOrder == null) return -1;
            if (a.sortOrder == b.sortOrder) return a.sectionKey.compareTo(b.sectionKey);
            return a.sortOrder > b.sortOrder ? 1 : -1;
        }
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

    private static String resolveValue(GTM_Page_Content__c rec) {
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
        // Same remap as getPageContent: a field meta row addressed under a
        // live variant's own section key is re-keyed to the base key, so
        // getPageLayout's fieldMeta and its content map agree on the same
        // section::field keys. Without this, a variant's fields would resolve
        // in content but never be drawn, because fieldMeta would still say
        // they live under a key the renderer never asks about.
        Map<String, GTM_Page_Section__c> variantsByBase =
            variantSectionsByBase(offeringKey, templateType, industryKey);
        Map<String, String> baseKeyByVariantKey = new Map<String, String>();
        for (String baseKey : variantsByBase.keySet()) {
            baseKeyByVariantKey.put(variantsByBase.get(baseKey).Section_Key__c, baseKey);
        }
        for (GTM_Page_Content__c rec : [
            SELECT Section_Key__c, Field_Key__c, Field_Type__c, Label__c,
                   Css_Class__c, Html_Id__c, Inline_Style__c
            FROM   GTM_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            AND    (Industry_Key__c = :industryKey OR Industry_Key__c = null OR Industry_Key__c = '')
            ORDER BY Industry_Key__c NULLS LAST, Sort_Order__c ASC
            LIMIT 1000
        ]) {
            String sectionKey = baseKeyByVariantKey.containsKey(rec.Section_Key__c)
                ? baseKeyByVariantKey.get(rec.Section_Key__c)
                : rec.Section_Key__c;
            String addr = sectionKey + '::' + rec.Field_Key__c;
            // Same precedence as getPageContent: the industry-specific row wins
            // and the generic one is skipped, so the two never disagree.
            if (seen.contains(addr)) continue;
            seen.add(addr);
            FieldMeta m = new FieldMeta();
            m.sectionKey = sectionKey;
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
        for (GTM_Offering__mdt off : [
            SELECT Offering_Key__c, Label__c FROM GTM_Offering__mdt ORDER BY Label__c
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

        for (GTM_Page_Content__c rec : [
            SELECT Offering_Key__c, Field_Key__c, Field_Type__c,
                   Text_Value__c, Rich_Value__c, JSON_Value__c
            FROM   GTM_Page_Content__c
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

        // Offering_Status__c and Archived__c live on the offering's own tile
        // section (Section_Key__c='tile', Template_Type__c='offerings-listing'),
        // not on GTM_Page_Content__c -- they are offering-level flags, not
        // content. Additive gates alongside isLive, not a replacement for it:
        // an offering can be "live" content-wise and still excluded from the
        // dashboard listing because it was explicitly set to Draft or archived.
        //
        // The tile-status query itself lives in
        // GTM_RecycleBinController.getOfferingTileStatus() -- a shared helper
        // so this "is this offering archived/published" check has exactly one
        // implementation instead of an independent copy here and another in
        // GtmPageContentController.
        Map<String, GTM_RecycleBinController.TileStatus> tileStatusByKey =
            GTM_RecycleBinController.getOfferingTileStatus(byKey.keySet());
        for (String offeringKey : tileStatusByKey.keySet()) {
            OfferingTile t = byKey.get(offeringKey);
            if (t == null) continue;
            GTM_RecycleBinController.TileStatus status = tileStatusByKey.get(offeringKey);
            if (status.offeringStatus != 'Published' || status.archived == true) {
                out.remove(out.indexOf(t));
            }
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
     *
     * Reads whatever owner/template the caller passes, per-offering:
     * c/chooseIndustry (the framework's Industry Chooser) always passes
     * offeringKey='gtm', templateType='industry-chooser' explicitly, so it
     * keeps reading the shared industry-tile taxonomy exactly as before.
     * c/gtmConfigurator passes its own offeringKey/templateType('configurator'),
     * so it now reads that offering's own industry-profile sections instead of
     * the framework's -- restoring per-offering industry copy. industry-tile
     * (framework) carries industryLabel/pickerBlurb; industry-profile
     * (per-offering) does not model those fields at all, so they simply stay
     * null on a per-offering profile, which is by design (the taxonomy name
     * stays framework-owned; only what this offering says to that industry is
     * offering-owned).
     *
     * An industry is returned only while its section is Published and Active
     * (the getPageLayout rule), so a new industry stays out of the public
     * chooser until Publish, and hiding or deleting one takes it off the site.
     */
    @AuraEnabled(cacheable=true)
    public static List<IndustryProfile> getIndustryProfiles(String offeringKey, String templateType) {
        List<IndustryProfile> out = new List<IndustryProfile>();
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) return out;

        // Only sections that are live: Published and Active, exactly as
        // getPageLayout decides. Draft_State__c is deliberately not read, so a
        // pending hide, reorder or delete does not change the public page until
        // Publish. Status__c is compared positively so a null status is
        // excluded whatever SOQL does with != and null.
        Set<String> liveKeys = new Set<String>();
        for (GTM_Page_Section__c sec : [
            SELECT Section_Key__c
            FROM   GTM_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            AND    Status__c        = 'Published'
            AND    Section_Key__c LIKE 'industry-%'
            LIMIT  200
        ]) {
            liveKeys.add(sec.Section_Key__c);
        }
        if (liveKeys.isEmpty()) return out;

        Map<String, IndustryProfile> bySection = new Map<String, IndustryProfile>();
        for (GTM_Page_Content__c rec : [
            SELECT Section_Key__c, Field_Key__c, Field_Type__c,
                   Text_Value__c, Rich_Value__c, JSON_Value__c
            FROM   GTM_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Active__c        = true
            AND    Section_Key__c LIKE 'industry-%'
            AND    Section_Key__c IN :liveKeys
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
