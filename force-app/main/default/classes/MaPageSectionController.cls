/**
 * The shape of a page: which sections exist, in what order, and which fields
 * each of them has a record for.
 *
 * Split from MaPageContentController on the line between structure and value.
 * This class decides what a page is made of; that one holds what is written in
 * it. Creating a section creates its content rows because a section without
 * them renders built-in fallbacks and looks like content nobody can edit —
 * that is a structural act, not an edit.
 */
public with sharing class MaPageSectionController {

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
                   Width__c, Sort_Order__c, Active__c, Status__c, Draft_State__c
            FROM   MA_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            LIMIT 200
        ]) {
            Map<String, Object> d = draftOf(sec);
            EditorSection e = new EditorSection();
            e.id         = sec.Id;
            e.sectionKey = sec.Section_Key__c;
            e.label      = sec.Label__c;
            e.helpText   = sec.Help_Text__c;
            e.layoutType = sec.Layout_Type__c;
            e.width      = sec.Width__c;
            e.sortOrder  = effectiveSort(sec);
            e.active     = effectiveActive(sec);
            e.isNew      = sec.Status__c == 'Draft';
            e.isMoved    = d.containsKey('sortOrder');
            e.isHidden   = d.containsKey('active');
            e.isDeleted  = d.get('deleted') == true;
            e.isDraft    = e.isNew || !d.isEmpty();
            out.add(e);
        }
        // Ordered on the effective sort, which is the pending order where one
        // exists. SOQL cannot order on a value that lives inside a JSON column.
        out.sort(new BySortOrder());
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
        Set<Id> ids = new Set<Id>();
        for (String raw : sectionIds) { if (String.isNotBlank(raw)) ids.add((Id) raw); }
        Map<Id, MA_Page_Section__c> byId = new Map<Id, MA_Page_Section__c>([
            SELECT Id, Sort_Order__c, Draft_State__c FROM MA_Page_Section__c WHERE Id IN :ids
        ]);

        // The new order is a pending change, not a write to the live page.
        // Reordering used to take effect the moment you dropped a section,
        // which made structure behave differently from every other edit.
        List<MA_Page_Section__c> updates = new List<MA_Page_Section__c>();
        Integer position = 0;
        for (String raw : sectionIds) {
            position += 10;
            MA_Page_Section__c sec = byId.get((Id) raw);
            if (sec == null) continue;
            putDraft(sec, 'sortOrder', position, sec.Sort_Order__c);
            updates.add(sec);
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
        List<MA_Page_Section__c> found = [
            SELECT Id, Active__c, Draft_State__c FROM MA_Page_Section__c WHERE Id = :sectionId LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('That section no longer exists.');
        }
        MA_Page_Section__c sec = found[0];
        putDraft(sec, 'active', active, sec.Active__c);
        try {
            update sec;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not update the section: ' + e.getMessage());
        }
    }

    /**
     * Creates a section and, in the same transaction, the content rows its
     * layout declares. The field list comes from the client because the layout
     * vocabulary is defined once, in c/gtmPageLayouts, and shared by the
     * renderer and the editor; duplicating it here is how the two would drift.
     * Everything in it is validated below rather than trusted.
     *
     * A section without its rows would render built-in fallbacks and look
     * broken, so the two are created together or not at all.
     */
    @AuraEnabled
    public static String createSection(
        String offeringKey,
        String templateType,
        String sectionKey,
        String label,
        String layoutType,
        String width,
        List<FieldSeed> fields
    ) {
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) {
            throw new AuraHandledException('An offering and a page are both required.');
        }
        String key = MaContentAddress.normaliseKey(sectionKey);
        if (String.isBlank(key)) {
            throw new AuraHandledException(
                'A section needs a name made of letters or numbers.'
            );
        }
        if (String.isBlank(layoutType)) {
            throw new AuraHandledException('A section needs a layout.');
        }
        // The key is the address of every field under it, so a collision would
        // silently merge two sections' content.
        if (![
            SELECT Id FROM MA_Page_Section__c
            WHERE Offering_Key__c = :offeringKey
            AND   Template_Type__c = :templateType
            AND   Section_Key__c = :key
            LIMIT 1
        ].isEmpty()) {
            throw new AuraHandledException(
                'This page already has a section called "' + key + '". Pick another name.'
            );
        }

        MA_Page_Section__c sec = new MA_Page_Section__c();
        sec.Section_Address__c = MaContentAddress.forSection(offeringKey, templateType, key);
        sec.Offering_Key__c    = offeringKey;
        sec.Template_Type__c   = templateType;
        sec.Section_Key__c     = key;
        sec.Label__c           = String.isBlank(label) ? key : label;
        sec.Layout_Type__c     = layoutType;
        sec.Width__c           = String.isBlank(width) ? 'standard' : width;
        sec.Active__c          = true;
        // Unpublished until Publish runs, so adding a section does not change
        // the public page the moment you name it.
        sec.Status__c          = 'Draft';
        sec.Sort_Order__c      = nextSortOrder(offeringKey, templateType);

        List<MA_Page_Content__c> rows = new List<MA_Page_Content__c>();
        Integer position = 0;
        for (FieldSeed f : (fields == null ? new List<FieldSeed>() : fields)) {
            if (f == null || String.isBlank(f.fieldKey)) continue;
            position += 10;
            MA_Page_Content__c row = new MA_Page_Content__c();
            row.Content_Address__c = MaContentAddress.forField(offeringKey, templateType, key, f.fieldKey);
            row.Offering_Key__c    = offeringKey;
            row.Template_Type__c   = templateType;
            row.Section_Key__c     = key;
            row.Field_Key__c       = f.fieldKey;
            row.Field_Type__c      = String.isBlank(f.fieldType) ? 'text' : f.fieldType;
            row.Label__c           = f.label;
            row.Sort_Order__c      = position;
            row.Active__c          = true;
            // A json field with no value is not an empty string, it is an
            // empty list; the editor parses this column to build its repeater.
            // A list starts as an empty list and a button as an empty button; the
        // editor parses this column to build its controls, and null is neither.
        if (row.Field_Type__c == 'json') row.JSON_Value__c = '[]';
        if (row.Field_Type__c == 'icontext') row.JSON_Value__c = '{"label":"","icon":""}';
            rows.add(row);
        }

        Savepoint sp = Database.setSavepoint();
        try {
            insert sec;
            if (!rows.isEmpty()) insert rows;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('The section could not be created: ' + e.getMessage());
        }
        return sec.Id;
    }

    /**
     * Deletes a section and every content row addressed under it. Content rows
     * are matched by offering + template + section key rather than by a lookup,
     * because the address is what ties them together.
     *
     * This is the destructive counterpart to setSectionActive: hiding a section
     * keeps its content, deleting it does not.
     */
    @AuraEnabled
    public static Integer deleteSection(String sectionId) {
        if (String.isBlank(sectionId)) {
            throw new AuraHandledException('A section id is required.');
        }
        List<MA_Page_Section__c> found = [
            SELECT Id, Offering_Key__c, Template_Type__c, Section_Key__c,
                   Status__c, Draft_State__c
            FROM   MA_Page_Section__c
            WHERE  Id = :sectionId
            LIMIT  1
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('That section no longer exists.');
        }
        MA_Page_Section__c sec = found[0];
        List<MA_Page_Content__c> rows = [
            SELECT Id FROM MA_Page_Content__c
            WHERE  Offering_Key__c  = :sec.Offering_Key__c
            AND    Template_Type__c = :sec.Template_Type__c
            AND    Section_Key__c   = :sec.Section_Key__c
            LIMIT  2000
        ];

        // A section that has never been published exists only in the editor, so
        // deleting it is not a change to the live page and there is nothing to
        // publish. Anything else is marked and removed at publish time, the
        // same as every other structural edit.
        if (sec.Status__c != 'Draft') {
            putDraft(sec, 'deleted', true, null);
            try {
                update sec;
            } catch (DmlException e) {
                throw new AuraHandledException('The section could not be deleted: ' + e.getMessage());
            }
            return rows.size();
        }

        Savepoint sp = Database.setSavepoint();
        try {
            if (!rows.isEmpty()) delete rows;
            delete sec;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('The section could not be deleted: ' + e.getMessage());
        }
        return rows.size();
    }

    /**
     * Takes back a pending delete. Nothing has been removed yet, so this is
     * just clearing the mark.
     */
    @AuraEnabled
    public static void restoreSection(String sectionId) {
        if (String.isBlank(sectionId)) {
            throw new AuraHandledException('A section id is required.');
        }
        List<MA_Page_Section__c> found = [
            SELECT Id, Draft_State__c FROM MA_Page_Section__c WHERE Id = :sectionId LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('That section no longer exists.');
        }
        MA_Page_Section__c sec = found[0];
        putDraft(sec, 'deleted', null, null);
        try {
            update sec;
        } catch (DmlException e) {
            throw new AuraHandledException('The section could not be restored: ' + e.getMessage());
        }
    }

    /**
     * Creates one content row on a section.
     *
     * Two things arrive here. A field the layout declares but has no record
     * for — a gap, where the page falls back to a built-in default. And a
     * field nobody declared, which the renderer draws generically after the
     * layout's own fields. Both are just a row; what differs is whether the
     * layout already had a place for it.
     */
    @AuraEnabled
    public static String createField(
        String offeringKey,
        String templateType,
        String sectionKey,
        String fieldKey,
        String fieldType,
        String label,
        String helpText
    ) {
        if (String.isBlank(offeringKey) || String.isBlank(templateType)
            || String.isBlank(sectionKey) || String.isBlank(fieldKey)) {
            throw new AuraHandledException('An offering, page, section and field are all required.');
        }
        if (!VALUE_TYPES.contains(fieldType)) {
            throw new AuraHandledException(
                'A field type must be one of: ' + String.join(new List<String>(VALUE_TYPES), ', ') + '.'
            );
        }
        String address = MaContentAddress.forField(offeringKey, templateType, sectionKey, fieldKey);
        if (![SELECT Id FROM MA_Page_Content__c WHERE Content_Address__c = :address LIMIT 1].isEmpty()) {
            throw new AuraHandledException('That field already exists on this section.');
        }
        MA_Page_Content__c row = new MA_Page_Content__c();
        row.Content_Address__c = address;
        row.Offering_Key__c    = offeringKey;
        row.Template_Type__c   = templateType;
        row.Section_Key__c     = sectionKey;
        row.Field_Key__c       = fieldKey;
        row.Field_Type__c      = fieldType;
        row.Label__c           = label;
        row.Help_Text__c       = helpText;
        row.Active__c          = true;
        row.Sort_Order__c      = nextFieldSortOrder(offeringKey, templateType, sectionKey);
        // A list starts as an empty list and a button as an empty button; the
        // editor parses this column to build its controls, and null is neither.
        if (row.Field_Type__c == 'json') row.JSON_Value__c = '[]';
        if (row.Field_Type__c == 'icontext') row.JSON_Value__c = '{"label":"","icon":""}';
        try {
            insert row;
        } catch (DmlException e) {
            throw new AuraHandledException('The field could not be added: ' + e.getMessage());
        }
        return row.Id;
    }

    /**
     * Sort order for a section appended to the end of a page. Steps of 10 so a
     * later reorder has room to move one section between two others without
     * rewriting every row.
     */
    private static Decimal nextSortOrder(String offeringKey, String templateType) {
        AggregateResult[] top = [
            SELECT MAX(Sort_Order__c) top
            FROM   MA_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
        ];
        Decimal current = (top.isEmpty() || top[0].get('top') == null)
            ? 0
            : (Decimal) top[0].get('top');
        return current + 10;
    }


    /** One field to create alongside a new section. */
    public class FieldSeed {
        @AuraEnabled public String fieldKey  { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public String label     { get; set; }
    }

    public class EditorSection {
        @AuraEnabled public String  id          { get; set; }
        @AuraEnabled public String  sectionKey  { get; set; }
        @AuraEnabled public String  label       { get; set; }
        @AuraEnabled public String  helpText    { get; set; }
        @AuraEnabled public String  layoutType  { get; set; }
        @AuraEnabled public String  width       { get; set; }
        // Effective values: the pending change where there is one, the
        // published value otherwise. The editor shows the page as it will be.
        @AuraEnabled public Decimal sortOrder   { get; set; }
        @AuraEnabled public Boolean active      { get; set; }
        // What is pending, so the editor can mark it and Publish can count it.
        @AuraEnabled public Boolean isNew       { get; set; }
        @AuraEnabled public Boolean isMoved     { get; set; }
        @AuraEnabled public Boolean isHidden    { get; set; }
        @AuraEnabled public Boolean isDeleted   { get; set; }
        @AuraEnabled public Boolean isDraft     { get; set; }
    }

    /** Orders sections by their effective sort, blanks last, key as tiebreak. */
    private class BySortOrder implements Comparator<EditorSection> {
        public Integer compare(EditorSection a, EditorSection b) {
            if (a.sortOrder == null && b.sortOrder == null) {
                return a.sectionKey.compareTo(b.sectionKey);
            }
            if (a.sortOrder == null) return 1;
            if (b.sortOrder == null) return -1;
            if (a.sortOrder == b.sortOrder) return a.sectionKey.compareTo(b.sectionKey);
            return a.sortOrder > b.sortOrder ? 1 : -1;
        }
    }

    // ─── draft state ──────────────────────────────────────────────────────────
    // Structural edits are drafts for the same reason content edits are: the
    // published page must not change until someone says so. Draft_State__c holds
    // the pending version of a section's editable state as JSON — the structural
    // counterpart to Draft_Value__c — so one column covers order, visibility and
    // deletion without a column per verb.

    public static Map<String, Object> draftOf(MA_Page_Section__c sec) {
        if (sec == null || String.isBlank(sec.Draft_State__c)) return new Map<String, Object>();
        try {
            Object parsed = JSON.deserializeUntyped(sec.Draft_State__c);
            return (parsed instanceof Map<String, Object>)
                ? (Map<String, Object>) parsed
                : new Map<String, Object>();
        } catch (Exception e) {
            // A draft we cannot read is not a reason to fail the page; treat it
            // as no pending change rather than blocking the editor.
            return new Map<String, Object>();
        }
    }

    /**
     * Merges one pending change into a section's draft state. Keys whose value
     * matches what is already published are removed rather than stored, so
     * moving a section and moving it back leaves nothing to publish.
     */
    private static void putDraft(MA_Page_Section__c sec, String key, Object value, Object publishedValue) {
        Map<String, Object> d = draftOf(sec);
        if (value == null || value == publishedValue) {
            d.remove(key);
        } else {
            d.put(key, value);
        }
        sec.Draft_State__c = d.isEmpty() ? null : JSON.serialize(d);
    }

    private static Decimal effectiveSort(MA_Page_Section__c sec) {
        Object v = draftOf(sec).get('sortOrder');
        if (v == null) return sec.Sort_Order__c;
        return Decimal.valueOf(String.valueOf(v));
    }

    private static Boolean effectiveActive(MA_Page_Section__c sec) {
        Object v = draftOf(sec).get('active');
        if (v == null) return sec.Active__c;
        return Boolean.valueOf(v);
    }

    /** The value columns a field can resolve from. */
    private static final Set<String> VALUE_TYPES = new Set<String>{
        'text', 'rich', 'json', 'icontext'
    };

    private static Decimal nextFieldSortOrder(String offeringKey, String templateType, String sectionKey) {
        AggregateResult[] top = [
            SELECT MAX(Sort_Order__c) top FROM MA_Page_Content__c
            WHERE Offering_Key__c = :offeringKey
            AND   Template_Type__c = :templateType
            AND   Section_Key__c = :sectionKey
        ];
        Decimal current = (top.isEmpty() || top[0].get('top') == null)
            ? 0 : (Decimal) top[0].get('top');
        return current + 10;
    }

    /**
     * Marks a field for removal at the next publish, or removes it outright if
     * it has never been published. Same rule as sections: what is on the live
     * page does not change until someone publishes.
     */
    @AuraEnabled
    public static Boolean deleteField(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('A field id is required.');
        }
        List<MA_Page_Content__c> found = [
            SELECT Id, Status__c, Text_Value__c, Rich_Value__c, JSON_Value__c
            FROM   MA_Page_Content__c WHERE Id = :recordId LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('That field no longer exists.');
        }
        MA_Page_Content__c rec = found[0];
        // Never published and never given a value: it exists only in the
        // editor, so removing it changes nothing anyone has seen.
        Boolean neverLive = rec.Status__c != 'Published'
            && String.isBlank(rec.Text_Value__c)
            && String.isBlank(rec.Rich_Value__c)
            && (String.isBlank(rec.JSON_Value__c) || rec.JSON_Value__c == '[]');
        try {
            if (neverLive) { delete rec; return true; }
            rec.Pending_Delete__c = true;
            update rec;
            return false;
        } catch (DmlException e) {
            throw new AuraHandledException('The field could not be deleted: ' + e.getMessage());
        }
    }

    /** Takes back a pending field delete. Nothing has been removed yet. */
    @AuraEnabled
    public static void restoreField(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('A field id is required.');
        }
        try {
            update new MA_Page_Content__c(Id = recordId, Pending_Delete__c = false);
        } catch (DmlException e) {
            throw new AuraHandledException('The field could not be restored: ' + e.getMessage());
        }
    }

    /**
     * Reorders the fields within a section. This is an editor-only ordering —
     * the renderer resolves a layout's fields by name, not by position — so
     * unlike section order it is not a pending change and needs no publish.
     */
    @AuraEnabled
    public static void saveFieldOrder(List<String> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) return;
        List<MA_Page_Content__c> updates = new List<MA_Page_Content__c>();
        Integer position = 0;
        for (String id : recordIds) {
            if (String.isBlank(id)) continue;
            position += 10;
            updates.add(new MA_Page_Content__c(Id = id, Sort_Order__c = position));
        }
        try {
            update updates;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not save the field order: ' + e.getMessage());
        }
    }

    /** One section to create as part of a new page. */
    public class SectionSeed {
        @AuraEnabled public String sectionKey { get; set; }
        @AuraEnabled public String label      { get; set; }
        @AuraEnabled public String helpText   { get; set; }
        @AuraEnabled public String layoutType { get; set; }
        @AuraEnabled public String width      { get; set; }
        @AuraEnabled public List<FieldSeed> fields { get; set; }
    }

    /**
     * Creates a whole page: its sections, in order, each with the fields its
     * layout declares.
     *
     * "New page" used to mean "open the editor and hope" — the page did not
     * exist until someone added a section by hand, which is why every page but
     * the story was empty. A template is a starting shape, so creating one
     * lays that shape down and leaves everything about it editable.
     *
     * Refuses a page that already has sections rather than merging into it:
     * scaffolding on top of real content would duplicate section keys and
     * quietly merge two pages' worth of fields.
     */
    @AuraEnabled
    public static Integer createPage(
        String offeringKey, String templateType, List<SectionSeed> sections
    ) {
        if (String.isBlank(offeringKey) || String.isBlank(templateType)) {
            throw new AuraHandledException('An offering and a page are both required.');
        }
        if (sections == null || sections.isEmpty()) {
            throw new AuraHandledException('This page has no starting shape defined.');
        }
        if (![
            SELECT Id FROM MA_Page_Section__c
            WHERE Offering_Key__c = :offeringKey AND Template_Type__c = :templateType
            LIMIT 1
        ].isEmpty()) {
            throw new AuraHandledException(
                'That page already has sections. Open it and add to it instead.'
            );
        }

        List<MA_Page_Section__c> newSections = new List<MA_Page_Section__c>();
        List<MA_Page_Content__c> newRows = new List<MA_Page_Content__c>();
        Decimal order = 0;
        for (SectionSeed seed : sections) {
            String key = MaContentAddress.normaliseKey(seed.sectionKey);
            if (String.isBlank(key)) continue;
            order += 10;

            MA_Page_Section__c sec = new MA_Page_Section__c();
            sec.Section_Address__c = MaContentAddress.forSection(offeringKey, templateType, key);
            sec.Offering_Key__c    = offeringKey;
            sec.Template_Type__c   = templateType;
            sec.Section_Key__c     = key;
            sec.Label__c           = String.isBlank(seed.label) ? key : seed.label;
            sec.Help_Text__c       = seed.helpText;
            sec.Layout_Type__c     = seed.layoutType;
            sec.Width__c           = String.isBlank(seed.width) ? 'standard' : seed.width;
            sec.Active__c          = true;
            // Draft until published, so creating a page does not change
            // anything public the moment it is named.
            sec.Status__c          = 'Draft';
            sec.Sort_Order__c      = order;
            newSections.add(sec);

            Integer position = 0;
            for (FieldSeed f : (seed.fields == null ? new List<FieldSeed>() : seed.fields)) {
                if (f == null || String.isBlank(f.fieldKey)) continue;
                position += 10;
                MA_Page_Content__c row = new MA_Page_Content__c();
                row.Content_Address__c = MaContentAddress.forField(offeringKey, templateType, key, f.fieldKey);
                row.Offering_Key__c    = offeringKey;
                row.Template_Type__c   = templateType;
                row.Section_Key__c     = key;
                row.Field_Key__c       = f.fieldKey;
                row.Field_Type__c      = String.isBlank(f.fieldType) ? 'text' : f.fieldType;
                row.Label__c           = f.label;
                row.Sort_Order__c      = position;
                row.Active__c          = true;
                if (row.Field_Type__c == 'json') row.JSON_Value__c = '[]';
                if (row.Field_Type__c == 'icontext') row.JSON_Value__c = '{"label":"","icon":""}';
                newRows.add(row);
            }
        }
        if (newSections.isEmpty()) {
            throw new AuraHandledException('None of the section names were usable.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            insert newSections;
            if (!newRows.isEmpty()) insert newRows;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('The page could not be created: ' + e.getMessage());
        }
        return newSections.size();
    }
}
