/**
 * Agentforce invocable action: read a whole-section industry variant's
 * current field values plus that industry's research brief.
 *
 * Modeled on GtmAgentGetConfigState. Read-only, no DML, no callout, fails
 * quiet (blank output) rather than throwing, so a bad sectionKey degrades a
 * conversation instead of ending it.
 *
 * Contract: docs/architecture/industry-variants-agentforce-draft.md §2.
 */
public with sharing class GtmAgentGetSectionContent {

    public class Input {
        @InvocableVariable(required=true label='Offering Key')
        public String offeringKey;
        @InvocableVariable(required=true label='Template Type')
        public String templateType;
        @InvocableVariable(required=true label='Section Key'
            description='The VARIANT section''s own Section_Key__c (e.g. problem--healthcare), not the base key.')
        public String sectionKey;
    }

    public class FieldSnapshot {
        @InvocableVariable public String fieldKey;
        @InvocableVariable public String fieldType;
        @InvocableVariable public String label;
        @InvocableVariable public String currentValue;
    }

    public class Output {
        @InvocableVariable public String sectionLabel;
        @InvocableVariable public String layoutType;
        @InvocableVariable public String industryKey;
        @InvocableVariable public String industryLabel;
        @InvocableVariable public String baseSectionKey;
        @InvocableVariable public List<FieldSnapshot> fields;
        @InvocableVariable(label='Industry brief (JSON)')
        public String industryBriefJson;
    }

    // Only these column types are draftable via this pathway (see contract
    // doc §5/§8 -- json/icontext/enum fields are out of scope for Track A).
    private static final Set<String> DRAFTABLE_TYPES = new Set<String>{ 'text', 'rich' };

    @InvocableMethod(
        label='Get GTM Section Content'
        description='Reads an industry variant section''s current field values and the matching industry research brief, for the Content Drafting Assistant.'
        category='GTM Offerings'
    )
    public static List<Output> execute(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(buildOutput(inp));
        }
        return results;
    }

    private static Output buildOutput(Input inp) {
        Output out = new Output();
        out.sectionLabel      = '';
        out.layoutType        = '';
        out.industryKey       = '';
        out.industryLabel     = '';
        out.baseSectionKey    = '';
        out.fields            = new List<FieldSnapshot>();
        out.industryBriefJson = '{}';

        if (String.isBlank(inp?.offeringKey) || String.isBlank(inp?.templateType)
            || String.isBlank(inp?.sectionKey)) {
            return out;
        }

        List<GTM_Page_Section__c> secs = [
            SELECT Label__c, Layout_Type__c, Industry_Key__c, Base_Section_Key__c
            FROM   GTM_Page_Section__c
            WHERE  Offering_Key__c  = :inp.offeringKey
            AND    Template_Type__c = :inp.templateType
            AND    Section_Key__c   = :inp.sectionKey
            LIMIT  1
        ];
        if (secs.isEmpty() || String.isBlank(secs[0].Industry_Key__c)) {
            // Missing row, or an ordinary (non-variant) section -- refuse to
            // proceed rather than let a model point this tool at a section
            // that was never scoped to one industry.
            return out;
        }

        GTM_Page_Section__c sec = secs[0];
        out.sectionLabel   = sec.Label__c;
        out.layoutType      = sec.Layout_Type__c;
        out.industryKey     = sec.Industry_Key__c;
        out.baseSectionKey  = sec.Base_Section_Key__c;

        for (GTM_Page_Content__c rec : [
            SELECT Field_Key__c, Field_Type__c, Label__c, Text_Value__c, Rich_Value__c
            FROM   GTM_Page_Content__c
            WHERE  Offering_Key__c  = :inp.offeringKey
            AND    Template_Type__c = :inp.templateType
            AND    Section_Key__c   = :inp.sectionKey
            AND    Active__c        = true
            LIMIT  200
        ]) {
            if (!DRAFTABLE_TYPES.contains(rec.Field_Type__c)) continue;
            FieldSnapshot fs = new FieldSnapshot();
            fs.fieldKey      = rec.Field_Key__c;
            fs.fieldType     = rec.Field_Type__c;
            fs.label         = rec.Label__c;
            fs.currentValue  = 'rich'.equals(rec.Field_Type__c) ? rec.Rich_Value__c : rec.Text_Value__c;
            out.fields.add(fs);
        }

        // Reuse the already-loaded industry brief taxonomy -- see contract
        // doc §1. No hardcoded brief table, no new storage.
        for (GtmPageContentReader.IndustryProfile p : GtmPageContentReader.getIndustryProfiles(
                GtmPageContentController.FRAMEWORK_KEY, 'industry-chooser')) {
            if (p.industryKey == sec.Industry_Key__c) {
                out.industryLabel     = p.industryLabel;
                out.industryBriefJson = JSON.serialize(p);
                break;
            }
        }

        return out;
    }
}
