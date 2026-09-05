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
     * Pages that belong to the framework rather than to any one offering.
     * Mirrors FRAMEWORK_KEY in c/gtmPageLayouts; the two must agree, because
     * one addresses the records and the other reads them.
     */
    public static final String FRAMEWORK_KEY = 'gtm';
    public static final String FRAMEWORK_LABEL = 'Framework (all offerings)';

    /**
     * Which pages exist under a given owner. Mirrors templatesFor() in
     * c/gtmPageLayouts: the framework owns the page that lists offerings, an
     * offering owns the pages that describe it.
     */
    private static List<String> templatesFor(String offeringKey) {
        // Industries are a shared taxonomy, so the chooser and the profiles
        // behind it are framework-level; every offering's configurator reads
        // the same set.
        return offeringKey == FRAMEWORK_KEY
            ? new List<String>{ 'offerings-page', 'industry-chooser' }
            : new List<String>{ 'story', 'configurator', 'offerings-listing' };
    }


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
                   Label__c, Help_Text__c, Draft_Value__c, Status__c, Pending_Delete__c,
                   Css_Class__c, Html_Id__c, Inline_Style__c
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


    // ─── compatibility shims ──────────────────────────────────────────────────
    // Section methods moved to MaPageSectionController. Lightning caches
    // component bundles in the browser, so a client loaded before that split
    // still imports them from here and would fail with "No apex action
    // available" until its cache cleared. These delegate rather than
    // duplicate, and can be deleted once no cached bundle can still be live.

    @AuraEnabled(cacheable=false)
    public static List<MaPageSectionController.EditorSection> getEditorSections(
        String offeringKey, String templateType
    ) {
        return MaPageSectionController.getEditorSections(offeringKey, templateType);
    }

    @AuraEnabled
    public static List<String> saveSectionOrder(List<String> sectionIds) {
        return MaPageSectionController.saveSectionOrder(sectionIds);
    }

    @AuraEnabled
    public static Boolean setSectionActive(String sectionId, Boolean active) {
        return MaPageSectionController.setSectionActive(sectionId, active);
    }

    @AuraEnabled
    public static Integer deleteSection(String sectionId) {
        return MaPageSectionController.deleteSection(sectionId);
    }

    @AuraEnabled
    public static String createSection(
        String offeringKey, String templateType, String sectionKey, String label,
        String layoutType, String width, List<MaPageSectionController.FieldSeed> fields
    ) {
        return MaPageSectionController.createSection(
            offeringKey, templateType, sectionKey, label, layoutType, width, fields);
    }

    @AuraEnabled
    public static String createField(
        String offeringKey, String templateType, String sectionKey,
        String fieldKey, String fieldType, String label
    ) {
        return MaPageSectionController.createField(
            offeringKey, templateType, sectionKey, fieldKey, fieldType, label, null);
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
        // The framework is not an offering, but it owns pages — the offerings
        // front door above them all — and the editor is the only place to edit
        // them. It leads the list because it sits above what follows.
        OfferingOption fw = new OfferingOption();
        fw.offeringKey = FRAMEWORK_KEY;
        fw.label       = FRAMEWORK_LABEL;
        out.add(fw);

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
        String path = sitePath.trim().removeStart('/').removeEnd('/');
        if (String.isBlank(path)) return null;

        // An offering's page now lives under the shared site rather than on a
        // site of its own, so this reads as "<site>/<page>": the first segment
        // is the Experience Cloud prefix to validate, the rest is the page
        // beneath it. A bare prefix still means the site's own home.
        Integer cut = path.indexOf('/');
        String prefix = cut > 0 ? path.substring(0, cut) : path;
        String page   = cut > 0 ? path.substring(cut + 1) : '';

        List<Network> nets = [
            SELECT Id FROM Network
            WHERE UrlPathPrefix = :prefix AND Status = 'Live'
            LIMIT 1
        ];
        if (nets.isEmpty()) return null;
        return 'https://' + host + '/' + prefix + '/s/' + page;
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
        // Seed every page this owner can have, so one with nothing in it is
        // still listed and can be built. Counting only what exists made an
        // empty page invisible, which is why there was no way to create one.
        for (String t : templatesFor(offeringKey)) {
            TemplateSummary ts = new TemplateSummary();
            ts.templateType = t;
            ts.sectionCount = 0;
            ts.fieldCount   = 0;
            byTemplate.put(t, ts);
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

        OfferingSummary fwSummary = new OfferingSummary();
        fwSummary.offeringKey = FRAMEWORK_KEY;
        fwSummary.label       = FRAMEWORK_LABEL;
        byKey.put(FRAMEWORK_KEY, fwSummary);
        home.offerings.add(fwSummary);

        for (MA_Offering__mdt off : [
            SELECT Offering_Key__c, Label__c FROM MA_Offering__mdt ORDER BY Label__c
        ]) {
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
            // An offering that has pages but no metadata row yet is a real
            // offering: custom metadata only deploys asynchronously, so one
            // created a moment ago would otherwise vanish from its own app
            // until the deployment landed. The metadata carries the site path;
            // the pages are what make it exist.
            String discovered = (String) ar.get('o');
            if (!byKey.containsKey(discovered)) {
                OfferingSummary o = new OfferingSummary();
                o.offeringKey = discovered;
                o.label       = discovered;
                byKey.put(discovered, o);
                home.offerings.add(o);
            }
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

        // The name an offering goes by is the name on the tile it publishes
        // about itself, so renaming it in the editor renames it everywhere it
        // appears. The metadata label is only the fallback for an offering
        // that has not written its tile yet.
        for (MA_Page_Content__c rec : [
            SELECT Offering_Key__c, Text_Value__c
            FROM   MA_Page_Content__c
            WHERE  Template_Type__c = 'offerings-listing'
            AND    Field_Key__c     = 'name'
            AND    Active__c        = true
            LIMIT  200
        ]) {
            OfferingSummary o = byKey.get(rec.Offering_Key__c);
            if (o != null && String.isNotBlank(rec.Text_Value__c)) o.label = rec.Text_Value__c;
        }
        for (OfferingSummary o : home.offerings) {
            o.isFramework = (o.offeringKey == FRAMEWORK_KEY);
            o.canRename   = !o.isFramework;
        }

        home.activity = getPageActivity();
        return home;
    }

    /**
     * Create an offering from a name.
     *
     * The name is the whole input: the key is derived from it, the offering's
     * own tile is written so it appears on the offerings page immediately, and
     * the metadata row is enqueued for the site path. Custom metadata deploys
     * asynchronously, so the pages -- which are ordinary records -- are what
     * make the offering real straight away; getHomeSummary picks it up from
     * them whether or not the deployment has landed.
     */
    @AuraEnabled
    public static String createOffering(String name) {
        String clean = name == null ? '' : name.trim();
        if (String.isBlank(clean)) {
            throw new AuraHandledException('Give the offering a name.');
        }
        if (clean.length() > 80) clean = clean.substring(0, 80);

        String key = clean.toLowerCase().replaceAll('[^a-z0-9]+', '-')
                          .replaceAll('^-+|-+$', '');
        if (String.isBlank(key)) {
            throw new AuraHandledException('That name has no letters or numbers to build a key from.');
        }
        if (key == FRAMEWORK_KEY) {
            throw new AuraHandledException('That name is reserved for the framework.');
        }
        Integer existing = [
            SELECT COUNT() FROM MA_Page_Section__c WHERE Offering_Key__c = :key
        ];
        if (existing > 0) {
            throw new AuraHandledException('An offering called "' + clean + '" already exists.');
        }

        // Its entry on the offerings page: the one thing a new offering needs
        // in order to be visible anywhere.
        MA_Page_Section__c tile = new MA_Page_Section__c(
            Section_Address__c = key + '::offerings-listing::tile',
            Offering_Key__c    = key,
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = 'tile',
            Label__c           = 'Offerings page entry',
            Layout_Type__c     = 'offering-tile',
            Width__c           = 'standard',
            Sort_Order__c      = 10,
            Active__c          = true,
            Status__c          = 'Published'
        );
        insert tile;

        List<MA_Page_Content__c> rows = new List<MA_Page_Content__c>{
            new MA_Page_Content__c(
                Content_Address__c = key + '::offerings-listing::tile::name',
                Offering_Key__c = key, Template_Type__c = 'offerings-listing',
                Section_Key__c = 'tile', Field_Key__c = 'name', Field_Type__c = 'text',
                Label__c = 'Name', Active__c = true, Status__c = 'Published',
                Text_Value__c = clean),
            new MA_Page_Content__c(
                Content_Address__c = key + '::offerings-listing::tile::mark',
                Offering_Key__c = key, Template_Type__c = 'offerings-listing',
                Section_Key__c = 'tile', Field_Key__c = 'mark', Field_Type__c = 'text',
                Label__c = 'Mark', Active__c = true, Status__c = 'Published',
                Text_Value__c = markFor(clean)),
            new MA_Page_Content__c(
                Content_Address__c = key + '::offerings-listing::tile::description',
                Offering_Key__c = key, Template_Type__c = 'offerings-listing',
                Section_Key__c = 'tile', Field_Key__c = 'description', Field_Type__c = 'rich',
                Label__c = 'Description', Active__c = true, Status__c = 'Published',
                Rich_Value__c = 'Describe ' + clean + ' here.')
        };
        insert rows;
        return key;
    }

    /** Initials, so a new offering's tile has a badge before anyone edits it. */
    private static String markFor(String name) {
        List<String> parts = name.split('\\s+');
        String out = '';
        for (String part : parts) {
            if (String.isBlank(part)) continue;
            out += part.substring(0, 1).toUpperCase();
            if (out.length() >= 2) break;
        }
        return out;
    }

    /**
     * Rename an offering.
     *
     * The name is content, not configuration: it is the name on the offering's
     * own tile, which is what the offerings page shows. Writing it here means
     * one edit renames the card, the tile and the page in the same move,
     * without a metadata deployment.
     */
    @AuraEnabled
    public static String renameOffering(String offeringKey, String name) {
        if (String.isBlank(offeringKey)) {
            throw new AuraHandledException('An offering is required.');
        }
        if (offeringKey == FRAMEWORK_KEY) {
            throw new AuraHandledException('The framework is not an offering and cannot be renamed.');
        }
        String clean = name == null ? '' : name.trim();
        if (String.isBlank(clean)) {
            throw new AuraHandledException('A name is required.');
        }
        if (clean.length() > 255) clean = clean.substring(0, 255);

        String sectionAddress = offeringKey + '::offerings-listing::tile';
        List<MA_Page_Section__c> secs = [
            SELECT Id FROM MA_Page_Section__c WHERE Section_Address__c = :sectionAddress LIMIT 1
        ];
        if (secs.isEmpty()) {
            // An offering with no tile yet gets one, so naming it is never
            // blocked on having built its listing page first.
            MA_Page_Section__c sec = new MA_Page_Section__c(
                Section_Address__c = sectionAddress,
                Offering_Key__c    = offeringKey,
                Template_Type__c   = 'offerings-listing',
                Section_Key__c     = 'tile',
                Label__c           = 'Offerings page entry',
                Layout_Type__c     = 'offering-tile',
                Width__c           = 'standard',
                Sort_Order__c      = 10,
                Active__c          = true,
                Status__c          = 'Published'
            );
            insert sec;
        }

        MA_Page_Content__c row = new MA_Page_Content__c(
            Content_Address__c = sectionAddress + '::name',
            Offering_Key__c    = offeringKey,
            Template_Type__c   = 'offerings-listing',
            Section_Key__c     = 'tile',
            Field_Key__c       = 'name',
            Field_Type__c      = 'text',
            Label__c           = 'Name',
            Active__c          = true,
            Status__c          = 'Published',
            Text_Value__c      = clean
        );
        upsert row Content_Address__c;
        return clean;
    }

    public class HomeSummary {
        @AuraEnabled public List<OfferingSummary> offerings = new List<OfferingSummary>();
        @AuraEnabled public List<PageActivity> activity = new List<PageActivity>();
    }

    public class OfferingSummary {
        @AuraEnabled public String offeringKey { get; set; }
        @AuraEnabled public String label       { get; set; }
        // The framework is not an offering: it owns the pages that sit above
        // them, is always shown first, and has no name of its own to change.
        @AuraEnabled public Boolean isFramework = false;
        @AuraEnabled public Boolean canRename   = false;
        @AuraEnabled public List<PageSummary> pages = new List<PageSummary>();
    }

    public class PageSummary {
        @AuraEnabled public String  offeringKey  { get; set; }
        @AuraEnabled public String  templateType { get; set; }
        @AuraEnabled public Integer sectionCount { get; set; }
        @AuraEnabled public Integer fieldCount   { get; set; }
    }

    public class PageActivity {
        @AuraEnabled public String  offeringKey  { get; set; }
        @AuraEnabled public String  templateType { get; set; }
        @AuraEnabled public String  summary      { get; set; }
        @AuraEnabled public Integer fieldCount   { get; set; }
        @AuraEnabled public Datetime occurred    { get; set; }
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
        // Structure first, and only then load the content rows. Publishing a
        // pending section delete removes that section's content, so a list of
        // drafts gathered beforehand would still hold rows that no longer
        // exist and the update below would fail on them.
        Integer structural = publishSections(offeringKey, templateType)
            + publishFieldDeletes(offeringKey, templateType);

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
        if (drafts.isEmpty()) { return structural; }

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
            if (rec.Field_Type__c == 'rich') {
                rec.Rich_Value__c = draft;
            } else if (rec.Field_Type__c == 'json' || rec.Field_Type__c == 'icontext') {
                rec.JSON_Value__c = draft;
            } else {
                rec.Text_Value__c = draft;
            }

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
        return drafts.size() + structural;
    }

    /**
     * Applies a page's pending structural changes: a new section goes live, a
     * pending order or visibility change is written to the real column, and a
     * section marked for deletion is removed along with its content.
     *
     * Deletion is the one publish step with no undo — there is no version
     * snapshot for a section — which is why the editor asks before marking one.
     */
    private static Integer publishSections(String offeringKey, String templateType) {
        List<MA_Page_Section__c> secs = [
            SELECT Id, Section_Key__c, Sort_Order__c, Active__c, Status__c, Draft_State__c
            FROM   MA_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            LIMIT  200
        ];
        List<MA_Page_Section__c> updates = new List<MA_Page_Section__c>();
        List<MA_Page_Section__c> removals = new List<MA_Page_Section__c>();
        Set<String> removedKeys = new Set<String>();

        for (MA_Page_Section__c sec : secs) {
            Map<String, Object> d = MaPageSectionController.draftOf(sec);
            Boolean wasNew = sec.Status__c == 'Draft';
            if (d.isEmpty() && !wasNew) continue;

            if (d.get('deleted') == true) {
                removals.add(sec);
                removedKeys.add(sec.Section_Key__c);
                continue;
            }
            if (d.containsKey('sortOrder')) {
                sec.Sort_Order__c = Decimal.valueOf(String.valueOf(d.get('sortOrder')));
            }
            if (d.containsKey('active')) {
                sec.Active__c = Boolean.valueOf(d.get('active'));
            }
            sec.Draft_State__c = null;
            sec.Status__c = 'Published';
            updates.add(sec);
        }
        if (updates.isEmpty() && removals.isEmpty()) return 0;

        List<MA_Page_Content__c> orphaned = removedKeys.isEmpty()
            ? new List<MA_Page_Content__c>()
            : [SELECT Id FROM MA_Page_Content__c
               WHERE Offering_Key__c = :offeringKey
               AND   Template_Type__c = :templateType
               AND   Section_Key__c IN :removedKeys
               LIMIT 2000];

        Savepoint sp = Database.setSavepoint();
        try {
            if (!updates.isEmpty())  update updates;
            if (!orphaned.isEmpty()) delete orphaned;
            if (!removals.isEmpty()) delete removals;
        } catch (DmlException ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Publish failed on the page structure: ' + ex.getMessage());
        }
        return updates.size() + removals.size();
    }

    /**
     * Throws away unpublished edits on a page. The published value is untouched
     * because it was never overwritten.
     */
    @AuraEnabled
    public static Integer discardDrafts(String offeringKey, String templateType) {
        // Same ordering rule as publish: discarding a section that was never
        // published deletes its content rows, so they must be gone before the
        // remaining drafts are read.
        Integer structural = discardSections(offeringKey, templateType)
            + discardFieldDeletes(offeringKey, templateType);
        List<MA_Page_Content__c> drafts = [
            SELECT Id FROM MA_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Status__c        = 'Draft'
            LIMIT 2000
        ];
        if (drafts.isEmpty()) { return structural; }
        for (MA_Page_Content__c rec : drafts) {
            rec.Draft_Value__c = null;
            rec.Status__c      = 'Published';
        }
        try {
            update drafts;
        } catch (DmlException ex) {
            throw new AuraHandledException('Changes could not be discarded: ' + ex.getMessage());
        }
        return drafts.size() + structural;
    }

    /**
     * Reverts pending structural changes. A section created since the last
     * publish is removed outright with its content: it has never been part of
     * the published page, so there is nothing to revert it to.
     */
    private static Integer discardSections(String offeringKey, String templateType) {
        List<MA_Page_Section__c> secs = [
            SELECT Id, Section_Key__c, Status__c, Draft_State__c
            FROM   MA_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            LIMIT  200
        ];
        List<MA_Page_Section__c> cleared = new List<MA_Page_Section__c>();
        List<MA_Page_Section__c> removals = new List<MA_Page_Section__c>();
        Set<String> removedKeys = new Set<String>();

        for (MA_Page_Section__c sec : secs) {
            if (sec.Status__c == 'Draft') {
                removals.add(sec);
                removedKeys.add(sec.Section_Key__c);
            } else if (String.isNotBlank(sec.Draft_State__c)) {
                sec.Draft_State__c = null;
                cleared.add(sec);
            }
        }
        if (cleared.isEmpty() && removals.isEmpty()) return 0;

        List<MA_Page_Content__c> orphaned = removedKeys.isEmpty()
            ? new List<MA_Page_Content__c>()
            : [SELECT Id FROM MA_Page_Content__c
               WHERE Offering_Key__c = :offeringKey
               AND   Template_Type__c = :templateType
               AND   Section_Key__c IN :removedKeys
               LIMIT 2000];

        Savepoint sp = Database.setSavepoint();
        try {
            if (!cleared.isEmpty())  update cleared;
            if (!orphaned.isEmpty()) delete orphaned;
            if (!removals.isEmpty()) delete removals;
        } catch (DmlException ex) {
            Database.rollback(sp);
            throw new AuraHandledException('Changes could not be discarded: ' + ex.getMessage());
        }
        return cleared.size() + removals.size();
    }

    public class DraftEdit {
        @AuraEnabled public String id    { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    private static String resolveValue(MA_Page_Content__c rec) {
        // icontext keeps a label and an icon together, so it stores where the
        // other structured type does. Anything unrecognised reads as text,
        // which is the one column every field has.
        if (rec.Field_Type__c == 'rich')   return rec.Rich_Value__c;
        if (rec.Field_Type__c == 'json' || rec.Field_Type__c == 'icontext')   return rec.JSON_Value__c;
        return rec.Text_Value__c;
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
        @AuraEnabled public Boolean pendingDelete   { get; set; }
        @AuraEnabled public String cssClass         { get; set; }
        @AuraEnabled public String htmlId           { get; set; }
        @AuraEnabled public String inlineStyle      { get; set; }
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
            this.pendingDelete     = rec.Pending_Delete__c == true;
            this.cssClass          = rec.Css_Class__c;
            this.htmlId            = rec.Html_Id__c;
            this.inlineStyle       = rec.Inline_Style__c;
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
            rec.Content_Address__c = MaContentAddress.forField(this.offeringKey, this.templateType, this.sectionKey, this.fieldKey);
            return rec;
        }
    }

    /**
     * Removes the fields marked for deletion. Runs with the structural pass and
     * before the content pass for the same reason sections do: these rows are
     * about to stop existing, so nothing downstream should be holding them.
     */
    private static Integer publishFieldDeletes(String offeringKey, String templateType) {
        List<MA_Page_Content__c> doomed = [
            SELECT Id FROM MA_Page_Content__c
            WHERE  Offering_Key__c   = :offeringKey
            AND    Template_Type__c  = :templateType
            AND    Pending_Delete__c = true
            LIMIT  2000
        ];
        if (doomed.isEmpty()) return 0;
        try {
            delete doomed;
        } catch (DmlException ex) {
            throw new AuraHandledException('Publish failed removing fields: ' + ex.getMessage());
        }
        return doomed.size();
    }

    /** Takes back every pending field delete on a page. */
    private static Integer discardFieldDeletes(String offeringKey, String templateType) {
        List<MA_Page_Content__c> marked = [
            SELECT Id FROM MA_Page_Content__c
            WHERE  Offering_Key__c   = :offeringKey
            AND    Template_Type__c  = :templateType
            AND    Pending_Delete__c = true
            LIMIT  2000
        ];
        if (marked.isEmpty()) return 0;
        for (MA_Page_Content__c rec : marked) { rec.Pending_Delete__c = false; }
        try {
            update marked;
        } catch (DmlException ex) {
            throw new AuraHandledException('Changes could not be discarded: ' + ex.getMessage());
        }
        return marked.size();
    }

    /**
     * Per-field presentation: the class, id and inline style applied to the
     * element on render. Saved immediately rather than held as a draft — it
     * changes how a field is drawn, not what it says, and holding it back
     * would mean a draft that cannot be seen in the preview it is for.
     */
    @AuraEnabled
    public static void savePresentation(String recordId, String key, String value) {
        if (String.isBlank(recordId) || String.isBlank(key)) {
            throw new AuraHandledException('A field and a property are both required.');
        }
        MA_Page_Content__c rec = new MA_Page_Content__c(Id = recordId);
        if (key == 'cssClass')          { rec.Css_Class__c = value; }
        else if (key == 'htmlId')       { rec.Html_Id__c = value; }
        else if (key == 'inlineStyle')  { rec.Inline_Style__c = value; }
        else {
            throw new AuraHandledException('Unknown presentation property: ' + key);
        }
        try {
            update rec;
        } catch (DmlException e) {
            throw new AuraHandledException('That could not be saved: ' + e.getMessage());
        }
    }

    /**
     * What has happened to these pages, as pages.
     *
     * The old list showed individual fields by LastModifiedDate, which counted
     * every autosaved keystroke as an event and could not see structural
     * changes at all. A publish is the thing that actually happened to a page,
     * and MA_Page_Content_Version__c already records one row per field per
     * publish — so the rows are grouped back into the publish they came from.
     */
    private static List<PageActivity> getPageActivity() {
        Map<Id, MA_Page_Content__c> byContent = new Map<Id, MA_Page_Content__c>([
            SELECT Id, Offering_Key__c, Template_Type__c FROM MA_Page_Content__c LIMIT 2000
        ]);

        // Rows published within the same minute are one act of publishing.
        Map<String, PageActivity> grouped = new Map<String, PageActivity>();
        List<String> order = new List<String>();
        for (MA_Page_Content_Version__c v : [
            SELECT Content__c, CreatedDate FROM MA_Page_Content_Version__c
            ORDER BY CreatedDate DESC LIMIT 500
        ]) {
            MA_Page_Content__c parent = byContent.get(v.Content__c);
            if (parent == null) continue;
            String bucket = parent.Offering_Key__c + '::' + parent.Template_Type__c + '::'
                + v.CreatedDate.formatGmt('yyyy-MM-dd HH:mm');
            PageActivity a = grouped.get(bucket);
            if (a == null) {
                a = new PageActivity();
                a.offeringKey  = parent.Offering_Key__c;
                a.templateType = parent.Template_Type__c;
                a.occurred     = v.CreatedDate;
                a.fieldCount   = 0;
                grouped.put(bucket, a);
                order.add(bucket);
            }
            a.fieldCount += 1;
        }

        List<PageActivity> out = new List<PageActivity>();
        for (String bucket : order) {
            PageActivity a = grouped.get(bucket);
            a.summary = 'Published — ' + a.fieldCount
                + (a.fieldCount == 1 ? ' field replaced' : ' fields replaced');
            out.add(a);
            if (out.size() >= 8) break;
        }
        return out;
    }
}
