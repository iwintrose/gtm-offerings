/**
 * Agentforce invocable action: read current GTM configurator state.
 * Returns config values and available industry keys for the AI assistant.
 *
 * Runs with sharing: a link the running user cannot see (another rep's) yields
 * the blank defaults, never its payload, and never an exception. No DML.
 */
public with sharing class GtmAgentGetConfigState {

    // Industries are a shared taxonomy, not offering-specific copy: they live
    // under the framework's own industry-chooser page (Offering_Key__c='gtm',
    // Template_Type__c='industry-chooser'), one section per industry, keyed
    // 'industry-<key>' -- exactly the pattern GtmPageContentReader.getIndustryProfiles
    // already reads from. This used to hardcode Offering_Key__c='migration-accelerator'
    // and Template_Type__c='story', which (a) reported one offering's industry set
    // regardless of which offering a rep was actually configuring, once a second
    // offering exists, and (b) was reading the wrong template type for the taxonomy
    // in the first place. Reusing the framework key here, rather than any one
    // offering's, is the fix for both at once -- there is no offering to "resolve"
    // for a value that was never offering-scoped.
    private static final String INDUSTRY_TEMPLATE = 'industry-chooser';

    public class Input {
        @InvocableVariable(required=false label='Config Id'
            description='GTM_Saved_Configuration__c Id (current- or legacy-format); blank for unsaved sessions')
        public String configId;
    }

    public class Output {
        @InvocableVariable(label='Company')              public String company;
        @InvocableVariable(label='Industry')             public String industry;
        @InvocableVariable(label='Accent color (hex)')   public String accent;
        @InvocableVariable(label='Objects count')        public Integer objectsCount;
        @InvocableVariable(label='Dependencies count')   public Integer depsCount;
        @InvocableVariable(label='Health score (0-100)') public Integer healthScore;
        @InvocableVariable(label='Note')                 public String note;
        @InvocableVariable(label='Available industry keys') public List<String> availableIndustries;
    }

    @InvocableMethod(
        label='Get GTM Configurator State'
        description='Returns the current page configuration values and available industry keys for the GTM Configurator Assistant.'
        category='GTM Offerings'
    )
    public static List<Output> execute(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(buildOutput(inp.configId));
        }
        return results;
    }

    private static Output buildOutput(String configId) {
        Output out = new Output();
        out.company             = '';
        out.industry            = '';
        out.accent              = '';
        out.objectsCount        = 0;
        out.depsCount           = 0;
        out.healthScore         = 0;
        out.note                = '';
        out.availableIndustries = new List<String>();

        Id resolvedConfigId = GtmLegacyConfigId.resolve(configId);
        if (resolvedConfigId != null) {
            List<GTM_Saved_Configuration__c> saved = [
                SELECT Config_Payload__c
                FROM   GTM_Saved_Configuration__c
                WHERE  Id = :resolvedConfigId
                LIMIT  1
            ];
            if (!saved.isEmpty() && String.isNotBlank(saved[0].Config_Payload__c)) {
                try {
                    Map<String, Object> payload =
                        (Map<String, Object>) JSON.deserializeUntyped(saved[0].Config_Payload__c);
                    out.company      = GtmAgentConfigActions.strOf(payload, 'company');
                    out.industry     = GtmAgentConfigActions.strOf(payload, 'industry');
                    out.accent       = GtmAgentConfigActions.strOf(payload, 'accent');
                    out.objectsCount = GtmAgentConfigActions.intOf(payload, 'objectsCount');
                    out.depsCount    = GtmAgentConfigActions.intOf(payload, 'depsCount');
                    out.healthScore  = GtmAgentConfigActions.intOf(payload, 'healthScore');
                    out.note         = GtmAgentConfigActions.strOf(payload, 'note');
                } catch (Exception e) {
                    // Malformed payload — return defaults
                }
            }
        }

        // Collect unique industry keys from the framework's industry-chooser
        // taxonomy -- the one place industries live, whichever offering this
        // GUS session is configuring.
        List<GTM_Page_Content__c> iRecs = [
            SELECT Section_Key__c
            FROM   GTM_Page_Content__c
            WHERE  Offering_Key__c  = :GtmPageContentController.FRAMEWORK_KEY
            AND    Template_Type__c = :INDUSTRY_TEMPLATE
            AND    Section_Key__c LIKE 'industry-%'
            AND    Active__c = true
            LIMIT  200
        ];
        Set<String> seen = new Set<String>();
        for (GTM_Page_Content__c rec : iRecs) {
            // 'industry-' is 9 characters; strip it to recover the key --
            // same convention GtmPageContentReader.getIndustryProfiles uses.
            seen.add(rec.Section_Key__c.substring(9));
        }
        out.availableIndustries = new List<String>(seen);
        out.availableIndustries.sort();

        return out;
    }
}
