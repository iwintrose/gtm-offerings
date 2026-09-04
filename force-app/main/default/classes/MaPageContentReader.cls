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
        if (rec.Field_Type__c == 'rich') return rec.Rich_Value__c;
        if (rec.Field_Type__c == 'json') return rec.JSON_Value__c;
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
            SELECT Section_Key__c, Field_Key__c, Field_Type__c, Label__c
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
            out.add(m);
        }
        return out;
    }
}
