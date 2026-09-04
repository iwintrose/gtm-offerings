/**
 * Apex API for the GTM Content Manager CMS framework.
 *
 * Content resolution priority:
 *   1. Saved-config override (Config_Payload__c.content.<field_key>) — not handled here, done client-side in LWC
 *   2. Industry-scoped record (Offering_Key__c + Template_Type__c + Section_Key__c + Field_Key__c + Industry_Key__c)
 *   3. Offering-default record (same address with blank Industry_Key__c)
 *   4. LWC DEFAULTS constant — handled client-side in LWC
 *
 * All methods are without sharing so Experience Cloud guest users can read content.
 */
public without sharing class MaPageContentController {

    /**
     * Returns all active content records for the given offering + template as a flat map.
     * Key = Section_Key__c + '::' + Field_Key__c  (+ '::' + Industry_Key__c when set)
     * Value = the resolved value string (Text_Value__c | Rich_Value__c | JSON_Value__c)
     *
     * LWC calls this once in connectedCallback and builds its local content map.
     * industryKey may be null/blank — when provided, industry-scoped records are included
     * and automatically take precedence over blanks with the same section+field key.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPageContent(String offeringKey, String templateType, String industryKey) {
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) {
            return new Map<String, String>();
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

        // Build map — industry-scoped records win over offering defaults for the same key.
        // Records are ordered: industry rows first (NULLS LAST reverses that — industry rows
        // have a non-null Industry_Key__c so they sort before nulls), then by Sort_Order__c.
        // We iterate forward and only set a key if it hasn't been set by a higher-priority row.
        Map<String, String> result = new Map<String, String>();
        for (MA_Page_Content__c rec : records) {
            String mapKey = rec.Section_Key__c + '::' + rec.Field_Key__c;
            if (!result.containsKey(mapKey)) {
                result.put(mapKey, resolveValue(rec));
            }
        }
        return result;
    }

    /**
     * Returns all active content records for a template as a list of ContentRecord wrappers.
     * Used by the GTM Content Manager Lightning App for the admin edit surface.
     * Does NOT filter by industry — returns all records including industry-scoped ones.
     */
    @AuraEnabled(cacheable=false)
    public static List<ContentRecord> getAllContent(String offeringKey, String templateType) {
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) {
            return new List<ContentRecord>();
        }

        List<MA_Page_Content__c> records = [
            SELECT Id, Name, Section_Key__c, Field_Key__c, Field_Type__c,
                   Text_Value__c, Rich_Value__c, JSON_Value__c,
                   Industry_Key__c, Sort_Order__c, Active__c,
                   Content_Address__c, Offering_Key__c, Template_Type__c,
                   Label__c, Help_Text__c, Draft_Value__c, Status__c
            FROM   MA_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            ORDER BY Section_Key__c ASC, Sort_Order__c ASC
            LIMIT 2000
        ];

        List<ContentRecord> result = new List<ContentRecord>();
        for (MA_Page_Content__c rec : records) {
            result.add(new ContentRecord(rec));
        }
        return result;
    }

    /**
     * Upsert a single content record. Matches on Content_Address__c external ID.
     * Used by the GTM Content Manager app when a BA saves a field.
     */
    @AuraEnabled
    public static String saveContentRecord(ContentRecord payload) {
        if (payload == null) {
            throw new AuraHandledException('Payload is required.');
        }
        MA_Page_Content__c rec = payload.toSObject();
        // Upsert by external ID so re-saves don't create duplicates.
        upsert rec Content_Address__c;
        return rec.Id;
    }

    /**
     * Bulk upsert. Used by seed/import flows in the Manager app.
     * Returns a list of record IDs in the same order as the input.
     */
    @AuraEnabled
    public static List<String> saveContentRecords(List<ContentRecord> payloads) {
        if (payloads == null || payloads.isEmpty()) {
            return new List<String>();
        }
        List<MA_Page_Content__c> toUpsert = new List<MA_Page_Content__c>();
        for (ContentRecord cr : payloads) {
            toUpsert.add(cr.toSObject());
        }
        upsert toUpsert Content_Address__c;
        List<String> ids = new List<String>();
        for (MA_Page_Content__c rec : toUpsert) {
            ids.add(rec.Id);
        }
        return ids;
    }

    /**
     * Delete a content record by ID. Used by the Manager app.
     */
    @AuraEnabled
    public static void deleteContentRecord(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required.');
        }
        delete [SELECT Id FROM MA_Page_Content__c WHERE Id = :recordId LIMIT 1];
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    /**
     * Sections for the editor: every row including inactive ones, so the rail
     * can show and restore a section that has been switched off. Distinct from
     * MaPageContentReader.getPageLayout, which is cacheable, guest-facing and
     * returns only what renders.
     */
    @AuraEnabled(cacheable=false)
    public static List<EditorSection> getEditorSections(String offeringKey, String templateType) {
        List<EditorSection> out = new List<EditorSection>();
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) {
            return out;
        }
        for (MA_Page_Section__c sec : [
            SELECT Id, Section_Key__c, Label__c, Help_Text__c, Layout_Type__c,
                   Width__c, Sort_Order__c, Active__c
            FROM   MA_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            ORDER BY Sort_Order__c ASC NULLS LAST, Section_Key__c ASC
            LIMIT 200
        ]) {
            EditorSection e = new EditorSection();
            e.id         = sec.Id;
            e.sectionKey = sec.Section_Key__c;
            e.label      = sec.Label__c;
            e.helpText   = sec.Help_Text__c;
            e.layoutType = sec.Layout_Type__c;
            e.width      = sec.Width__c;
            e.sortOrder  = sec.Sort_Order__c;
            e.active     = sec.Active__c;
            out.add(e);
        }
        return out;
    }

    /**
     * Persists a new section order. Takes ids in the order the rail shows them
     * and rewrites Sort_Order__c to match, so the page follows the records.
     */
    @AuraEnabled
    public static void saveSectionOrder(List<String> sectionIds) {
        if (sectionIds == null || sectionIds.isEmpty()) {
            return;
        }
        List<MA_Page_Section__c> updates = new List<MA_Page_Section__c>();
        Integer position = 0;
        for (String id : sectionIds) {
            position += 10;
            updates.add(new MA_Page_Section__c(Id = id, Sort_Order__c = position));
        }
        try {
            update updates;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not save the section order: ' + e.getMessage());
        }
    }

    /**
     * Toggles a section on or off without deleting it or its content rows.
     */
    @AuraEnabled
    public static void setSectionActive(String sectionId, Boolean active) {
        if (String.isBlank(sectionId) || active == null) {
            throw new AuraHandledException('A section id and active flag are both required.');
        }
        try {
            update new MA_Page_Section__c(Id = sectionId, Active__c = active);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not update the section: ' + e.getMessage());
        }
    }

    public class EditorSection {
        @AuraEnabled public String  id          { get; set; }
        @AuraEnabled public String  sectionKey  { get; set; }
        @AuraEnabled public String  label       { get; set; }
        @AuraEnabled public String  helpText    { get; set; }
        @AuraEnabled public String  layoutType  { get; set; }
        @AuraEnabled public String  width       { get; set; }
        @AuraEnabled public Decimal sortOrder   { get; set; }
        @AuraEnabled public Boolean active      { get; set; }
    }

    /**
     * The offerings this org knows about, from MA_Offering__mdt. The editor
     * asks for these rather than assuming one, so adding an offering is a
     * metadata record and never a code change.
     */
    @AuraEnabled(cacheable=true)
    public static List<OfferingOption> getOfferings() {
        List<OfferingOption> out = new List<OfferingOption>();
        String host = siteHost();
        for (MA_Offering__mdt off : [
            SELECT Offering_Key__c, Label__c, Site_Path__c FROM MA_Offering__mdt
            ORDER BY Label__c ASC
        ]) {
            OfferingOption o = new OfferingOption();
            o.offeringKey = off.Offering_Key__c;
            o.label       = off.Label__c;
            o.publicUrl   = publicUrlFor(host, off.Site_Path__c);
            out.add(o);
        }
        return out;
    }

    /**
     * The org's Experience Cloud host, read from the platform rather than
     * assembled from the org URL: a sandbox, a scratch org and production all
     * spell this differently, and getting it wrong produces a link that 404s
     * without anything failing loudly.
     */
    private static String siteHost() {
        for (Domain d : [SELECT Domain FROM Domain WHERE DomainType = 'DNS' LIMIT 50]) {
            if (d.Domain != null && d.Domain.contains('.my.site.com')) {
                return d.Domain;
            }
        }
        return null;
    }

    /**
     * Only returns a URL for a site that actually exists and is Live. A
     * configured Site_Path__c that no longer matches a Network is a broken
     * link, and a blank link the editor can hide is better than a dead one.
     */
    private static String publicUrlFor(String host, String sitePath) {
        if (String.isBlank(host) || String.isBlank(sitePath)) return null;
        String prefix = sitePath.trim().removeStart('/').removeEnd('/');
        if (String.isBlank(prefix)) return null;
        List<Network> nets = [
            SELECT Id FROM Network
            WHERE UrlPathPrefix = :prefix AND Status = 'Live'
            LIMIT 1
        ];
        if (nets.isEmpty()) return null;
        return 'https://' + host + '/' + prefix + '/s/';
    }

    /**
     * Per template: how many sections are modelled and how many content rows
     * exist. Lets the editor say which pages are actually built for an
     * offering instead of offering four picklist values, three of which
     * silently resolve to nothing.
     */
    @AuraEnabled(cacheable=false)
    public static List<TemplateSummary> getTemplateSummary(String offeringKey) {
        Map<String, TemplateSummary> byTemplate = new Map<String, TemplateSummary>();
        if (String.isBlank(offeringKey)) {
            return byTemplate.values();
        }
        for (AggregateResult ar : [
            SELECT Template_Type__c t, COUNT(Id) c
            FROM   MA_Page_Section__c
            WHERE  Offering_Key__c = :offeringKey AND Active__c = true
            GROUP BY Template_Type__c
        ]) {
            TemplateSummary ts = new TemplateSummary();
            ts.templateType  = (String) ar.get('t');
            ts.sectionCount  = (Integer) ar.get('c');
            byTemplate.put(ts.templateType, ts);
        }
        for (AggregateResult ar : [
            SELECT Template_Type__c t, COUNT(Id) c
            FROM   MA_Page_Content__c
            WHERE  Offering_Key__c = :offeringKey AND Active__c = true
            GROUP BY Template_Type__c
        ]) {
            String t = (String) ar.get('t');
            TemplateSummary ts = byTemplate.get(t);
            if (ts == null) {
                ts = new TemplateSummary();
                ts.templateType = t;
                ts.sectionCount = 0;
                byTemplate.put(t, ts);
            }
            ts.fieldCount = (Integer) ar.get('c');
        }
        return byTemplate.values();
    }

    public class OfferingOption {
        @AuraEnabled public String offeringKey { get; set; }
        @AuraEnabled public String label       { get; set; }
        // Absolute URL of the offering's public site, or blank when the
        // offering has no site path configured. Absolute because the editor
        // runs on the Lightning domain and Experience sites are served from
        // my.site.com: a relative /gtmstory/s/ link 404s from Lightning.
        @AuraEnabled public String publicUrl   { get; set; }
    }

    public class TemplateSummary {
        @AuraEnabled public String  templateType { get; set; }
        @AuraEnabled public Integer sectionCount { get; set; }
        @AuraEnabled public Integer fieldCount   { get; set; }
    }

    /**
     * Everything the Content Manager home needs in one call: each offering,
     * the pages under it with their section and field counts, and the most
     * recently edited fields across the org.
     */
    @AuraEnabled(cacheable=false)
    public static HomeSummary getHomeSummary() {
        HomeSummary home = new HomeSummary();

        Map<String, OfferingSummary> byKey = new Map<String, OfferingSummary>();
        for (MA_Offering__mdt off : [SELECT Offering_Key__c, Label__c FROM MA_Offering__mdt ORDER BY Label__c]) {
            OfferingSummary o = new OfferingSummary();
            o.offeringKey = off.Offering_Key__c;
            o.label       = off.Label__c;
            byKey.put(o.offeringKey, o);
            home.offerings.add(o);
        }

        // Sections modelled per offering + template.
        Map<String, PageSummary> pages = new Map<String, PageSummary>();
        for (AggregateResult ar : [
            SELECT Offering_Key__c o, Template_Type__c t, COUNT(Id) c
            FROM   MA_Page_Section__c WHERE Active__c = true
            GROUP BY Offering_Key__c, Template_Type__c
        ]) {
            PageSummary p = new PageSummary();
            p.offeringKey  = (String) ar.get('o');
            p.templateType = (String) ar.get('t');
            p.sectionCount = (Integer) ar.get('c');
            pages.put(p.offeringKey + '::' + p.templateType, p);
        }
        // Content rows per offering + template, including templates with no sections.
        for (AggregateResult ar : [
            SELECT Offering_Key__c o, Template_Type__c t, COUNT(Id) c
            FROM   MA_Page_Content__c WHERE Active__c = true
            GROUP BY Offering_Key__c, Template_Type__c
        ]) {
            String k = (String) ar.get('o') + '::' + (String) ar.get('t');
            PageSummary p = pages.get(k);
            if (p == null) {
                p = new PageSummary();
                p.offeringKey  = (String) ar.get('o');
                p.templateType = (String) ar.get('t');
                p.sectionCount = 0;
                pages.put(k, p);
            }
            p.fieldCount = (Integer) ar.get('c');
        }
        for (PageSummary p : pages.values()) {
            OfferingSummary o = byKey.get(p.offeringKey);
            if (o != null) { o.pages.add(p); }
        }

        for (MA_Page_Content__c rec : [
            SELECT Offering_Key__c, Template_Type__c, Section_Key__c, Field_Key__c,
                   Label__c, LastModifiedDate
            FROM   MA_Page_Content__c
            WHERE  Active__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 8
        ]) {
            RecentEdit e = new RecentEdit();
            e.offeringKey  = rec.Offering_Key__c;
            e.templateType = rec.Template_Type__c;
            e.sectionKey   = rec.Section_Key__c;
            e.fieldKey     = rec.Field_Key__c;
            e.label        = rec.Label__c;
            e.modified     = rec.LastModifiedDate;
            home.recent.add(e);
        }
        return home;
    }

    public class HomeSummary {
        @AuraEnabled public List<OfferingSummary> offerings = new List<OfferingSummary>();
        @AuraEnabled public List<RecentEdit> recent = new List<RecentEdit>();
    }

    public class OfferingSummary {
        @AuraEnabled public String offeringKey { get; set; }
        @AuraEnabled public String label       { get; set; }
        @AuraEnabled public List<PageSummary> pages = new List<PageSummary>();
    }

    public class PageSummary {
        @AuraEnabled public String  offeringKey  { get; set; }
        @AuraEnabled public String  templateType { get; set; }
        @AuraEnabled public Integer sectionCount { get; set; }
        @AuraEnabled public Integer fieldCount   { get; set; }
    }

    public class RecentEdit {
        @AuraEnabled public String   offeringKey  { get; set; }
        @AuraEnabled public String   templateType { get; set; }
        @AuraEnabled public String   sectionKey   { get; set; }
        @AuraEnabled public String   fieldKey     { get; set; }
        @AuraEnabled public String   label        { get; set; }
        @AuraEnabled public Datetime modified     { get; set; }
    }

    /**
     * Saves a working copy without touching what the public page shows.
     *
     * The live page reads Text_Value__c / Rich_Value__c / JSON_Value__c, so a
     * draft is written to Draft_Value__c instead and the row is marked Draft.
     * Nothing an editor types reaches the site until publishPage runs.
     */
    @AuraEnabled
    public static void saveDrafts(List<DraftEdit> edits) {
        if (edits == null || edits.isEmpty()) {
            return;
        }
        Map<Id, MA_Page_Content__c> updates = new Map<Id, MA_Page_Content__c>();
        for (DraftEdit e : edits) {
            if (String.isBlank(e.id)) { continue; }
            updates.put(e.id, new MA_Page_Content__c(
                Id             = e.id,
                Draft_Value__c = e.value,
                Status__c      = 'Draft'
            ));
        }
        if (updates.isEmpty()) { return; }
        try {
            update updates.values();
        } catch (DmlException ex) {
            throw new AuraHandledException('Draft could not be saved: ' + ex.getMessage());
        }
    }

    /**
     * Publishes every draft on a page: snapshots the value being replaced into
     * MA_Page_Content_Version__c, moves the draft into the column the page
     * reads, clears the draft and marks the row Published.
     *
     * The snapshot holds the OUTGOING value, so a version is what you roll back
     * to, not what you just published.
     */
    @AuraEnabled
    public static Integer publishPage(String offeringKey, String templateType) {
        // Draft_Value__c is a long text area, which SOQL cannot filter on, so
        // the "has a draft" test happens in Apex.
        List<MA_Page_Content__c> drafts = new List<MA_Page_Content__c>();
        for (MA_Page_Content__c rec : [
            SELECT Id, Field_Type__c, Text_Value__c, Rich_Value__c, JSON_Value__c,
                   Draft_Value__c, Version_Number__c, Section_Key__c, Field_Key__c
            FROM   MA_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Status__c        = 'Draft'
            LIMIT 2000
        ]) {
            if (rec.Draft_Value__c != null) { drafts.add(rec); }
        }
        if (drafts.isEmpty()) { return 0; }

        List<MA_Page_Content_Version__c> versions = new List<MA_Page_Content_Version__c>();
        for (MA_Page_Content__c rec : drafts) {
            Decimal next = (rec.Version_Number__c == null ? 0 : rec.Version_Number__c) + 1;
            versions.add(new MA_Page_Content_Version__c(
                Content__c        = rec.Id,
                Version_Number__c = next,
                Snapshot__c       = resolveValue(rec),
                Change_Summary__c = 'Replaced by publish of ' + rec.Section_Key__c + '::' + rec.Field_Key__c
            ));

            String draft = rec.Draft_Value__c;
            if (rec.Field_Type__c == 'rich')      { rec.Rich_Value__c = draft; }
            else if (rec.Field_Type__c == 'json') { rec.JSON_Value__c = draft; }
            else                                  { rec.Text_Value__c = draft; }

            rec.Draft_Value__c        = null;
            rec.Status__c             = 'Published';
            rec.Version_Number__c     = next;
            rec.Last_Published_Date__c = System.now();
        }
        try {
            insert versions;
            update drafts;
        } catch (DmlException ex) {
            throw new AuraHandledException('Publish failed: ' + ex.getMessage());
        }
        return drafts.size();
    }

    /**
     * Throws away unpublished edits on a page. The published value is untouched
     * because it was never overwritten.
     */
    @AuraEnabled
    public static Integer discardDrafts(String offeringKey, String templateType) {
        List<MA_Page_Content__c> drafts = [
            SELECT Id FROM MA_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Status__c        = 'Draft'
            LIMIT 2000
        ];
        if (drafts.isEmpty()) { return 0; }
        for (MA_Page_Content__c rec : drafts) {
            rec.Draft_Value__c = null;
            rec.Status__c      = 'Published';
        }
        try {
            update drafts;
        } catch (DmlException ex) {
            throw new AuraHandledException('Changes could not be discarded: ' + ex.getMessage());
        }
        return drafts.size();
    }

    public class DraftEdit {
        @AuraEnabled public String id    { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    private static String resolveValue(MA_Page_Content__c rec) {
        if (rec.Field_Type__c == 'rich')   return rec.Rich_Value__c;
        if (rec.Field_Type__c == 'json')   return rec.JSON_Value__c;
        return rec.Text_Value__c;
    }

    private static String contentAddress(String offeringKey, String templateType, String sectionKey, String fieldKey) {
        return offeringKey + '::' + templateType + '::' + sectionKey + '::' + fieldKey;
    }

    // ─── Inner wrapper ────────────────────────────────────────────────────────

    public class ContentRecord {
        @AuraEnabled public String id               { get; set; }
        @AuraEnabled public String name             { get; set; }
        @AuraEnabled public String offeringKey      { get; set; }
        @AuraEnabled public String templateType     { get; set; }
        @AuraEnabled public String sectionKey       { get; set; }
        @AuraEnabled public String fieldKey         { get; set; }
        @AuraEnabled public String fieldType        { get; set; }
        @AuraEnabled public String label            { get; set; }
        @AuraEnabled public String helpText         { get; set; }
        @AuraEnabled public String draftValue       { get; set; }
        @AuraEnabled public String status           { get; set; }
        @AuraEnabled public Boolean isDraft         { get; set; }
        @AuraEnabled public String textValue        { get; set; }
        @AuraEnabled public String richValue        { get; set; }
        @AuraEnabled public String jsonValue        { get; set; }
        @AuraEnabled public String industryKey      { get; set; }
        @AuraEnabled public Integer sortOrder       { get; set; }
        @AuraEnabled public Boolean active          { get; set; }
        @AuraEnabled public String contentAddress   { get; set; }

        public ContentRecord() {}

        public ContentRecord(MA_Page_Content__c rec) {
            this.id                = rec.Id;
            this.name              = rec.Name;
            this.offeringKey       = rec.Offering_Key__c;
            this.templateType      = rec.Template_Type__c == null ? null : rec.Template_Type__c;
            this.sectionKey        = rec.Section_Key__c;
            this.fieldKey          = rec.Field_Key__c;
            this.fieldType         = rec.Field_Type__c == null ? 'text' : rec.Field_Type__c;
            this.textValue         = rec.Text_Value__c;
            this.richValue         = rec.Rich_Value__c;
            this.jsonValue         = rec.JSON_Value__c;
            this.industryKey       = rec.Industry_Key__c;
            this.sortOrder         = rec.Sort_Order__c == null ? 0 : rec.Sort_Order__c.intValue();
            this.active            = rec.Active__c;
            this.contentAddress    = rec.Content_Address__c;
            this.label             = rec.Label__c;
            this.helpText          = rec.Help_Text__c;
            this.draftValue        = rec.Draft_Value__c;
            this.status            = rec.Status__c;
            this.isDraft           = rec.Status__c == 'Draft' && rec.Draft_Value__c != null;
        }

        public MA_Page_Content__c toSObject() {
            MA_Page_Content__c rec = new MA_Page_Content__c();
            if (String.isNotBlank(this.id)) rec.Id = this.id;
            rec.Offering_Key__c    = this.offeringKey;
            rec.Template_Type__c   = this.templateType;
            rec.Section_Key__c     = this.sectionKey;
            rec.Field_Key__c       = this.fieldKey;
            rec.Field_Type__c      = this.fieldType;
            rec.Text_Value__c      = this.textValue;
            rec.Rich_Value__c      = this.richValue;
            rec.JSON_Value__c      = this.jsonValue;
            rec.Industry_Key__c    = this.industryKey;
            rec.Sort_Order__c      = this.sortOrder == null ? 0 : this.sortOrder;
            rec.Active__c          = this.active == null ? true : this.active;
            // Content_Address__c is a plain Text external ID — Apex must set it.
            rec.Content_Address__c = contentAddress(this.offeringKey, this.templateType, this.sectionKey, this.fieldKey);
            return rec;
        }
    }
}
