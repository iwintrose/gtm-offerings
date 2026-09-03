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

    private static String resolveValue(MA_Page_Content__c rec) {
        if (rec.Field_Type__c == 'rich') return rec.Rich_Value__c;
        if (rec.Field_Type__c == 'json') return rec.JSON_Value__c;
        return rec.Text_Value__c;
    }
}
