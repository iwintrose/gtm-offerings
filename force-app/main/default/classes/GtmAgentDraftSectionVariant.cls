/**
 * Agentforce invocable action: validates a model-proposed set of field
 * values for an industry variant section. Read-only against the schema --
 * it re-derives the section's actual draftable fields server-side and drops
 * anything that isn't one of them -- and NEVER writes GTM_Page_Content__c or
 * GTM_Page_Section__c. No DML, no callout.
 *
 * Deliberately does not know about a surface's accumulatedChanges delta bag
 * (unlike GtmAgentApplyConfigUpdate): this class is a pure validator so it
 * can be unit tested and reused independent of the tool-use loop. The
 * calling surface (GtmContentDraftAgentSurface) is what merges appliedJson
 * into the delta the LWC applies afterwards, through the existing
 * Draft -> Publish path -- never here.
 *
 * Contract: docs/architecture/industry-variants-agentforce-draft.md §2.
 */
public with sharing class GtmAgentDraftSectionVariant {

    private static final Set<String> DRAFTABLE_TYPES = new Set<String>{ 'text', 'rich' };
    private static final Integer MAX_FIELD_LENGTH = 8000;

    public class Input {
        @InvocableVariable(required=true label='Offering Key')
        public String offeringKey;
        @InvocableVariable(required=true label='Template Type')
        public String templateType;
        @InvocableVariable(required=true label='Section Key'
            description='The VARIANT section''s own Section_Key__c.')
        public String sectionKey;
        @InvocableVariable(required=true label='Field Values JSON'
            description='JSON object: {"fieldKey": "proposed copy", ...}. Only the section''s own text/rich fields are accepted.')
        public String fieldValuesJson;
    }

    public class Output {
        @InvocableVariable public Boolean success;
        @InvocableVariable(label='Applied JSON') public String appliedJson;
        @InvocableVariable(label='Error message') public String errorMessage;
    }

    @InvocableMethod(
        label='Draft GTM Section Variant Copy'
        description='Validates proposed field values for an industry variant section. Returns a proposal only -- never writes content.'
        category='GTM Offerings'
    )
    public static List<Output> execute(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(validate(inp));
        }
        return results;
    }

    private static Output validate(Input inp) {
        Output out = new Output();
        out.success      = false;
        out.appliedJson  = '';
        out.errorMessage = '';

        if (String.isBlank(inp?.offeringKey) || String.isBlank(inp?.templateType)
            || String.isBlank(inp?.sectionKey)) {
            out.errorMessage = 'offeringKey, templateType and sectionKey are required.';
            return out;
        }
        if (String.isBlank(inp.fieldValuesJson)) {
            out.errorMessage = 'fieldValuesJson is required.';
            return out;
        }

        Map<String, String> allowedFields = draftableFieldTypes(inp.offeringKey, inp.templateType, inp.sectionKey);
        if (allowedFields.isEmpty()) {
            out.errorMessage = 'That section is not a draftable industry variant.';
            return out;
        }

        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(inp.fieldValuesJson);
        } catch (Exception e) {
            out.errorMessage = 'fieldValuesJson is not valid JSON.';
            return out;
        }

        Map<String, Object> clean = new Map<String, Object>();
        List<String> errors = new List<String>();
        for (String key : raw.keySet()) {
            if (!allowedFields.containsKey(key)) continue; // over-proposed key, silently dropped
            String val = raw.get(key) == null ? '' : String.valueOf(raw.get(key));
            if (val.length() > MAX_FIELD_LENGTH) {
                errors.add(key + ' exceeds ' + MAX_FIELD_LENGTH + ' characters.');
                continue;
            }
            clean.put(key, val);
        }

        if (!errors.isEmpty()) {
            out.errorMessage = String.join(errors, ' ');
            return out;
        }
        if (clean.isEmpty()) {
            out.errorMessage = 'No recognised draftable fields found in fieldValuesJson.';
            return out;
        }

        out.success     = true;
        out.appliedJson = JSON.serialize(clean);
        return out;
    }

    /** fieldKey -> fieldType, for the section's own draftable (text/rich) fields, iff it is a live variant row. */
    private static Map<String, String> draftableFieldTypes(String offeringKey, String templateType, String sectionKey) {
        Map<String, String> out = new Map<String, String>();

        List<GTM_Page_Section__c> secs = [
            SELECT Industry_Key__c
            FROM   GTM_Page_Section__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Section_Key__c   = :sectionKey
            LIMIT  1
        ];
        if (secs.isEmpty() || String.isBlank(secs[0].Industry_Key__c)) return out;

        for (GTM_Page_Content__c rec : [
            SELECT Field_Key__c, Field_Type__c
            FROM   GTM_Page_Content__c
            WHERE  Offering_Key__c  = :offeringKey
            AND    Template_Type__c = :templateType
            AND    Section_Key__c   = :sectionKey
            AND    Active__c        = true
            LIMIT  200
        ]) {
            if (DRAFTABLE_TYPES.contains(rec.Field_Type__c)) {
                out.put(rec.Field_Key__c, rec.Field_Type__c);
            }
        }
        return out;
    }
}
