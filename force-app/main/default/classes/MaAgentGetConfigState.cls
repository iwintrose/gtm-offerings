/**
 * Agentforce invocable action: read current GTM configurator state.
 * Returns config values and available industry keys for the AI assistant.
 */
public without sharing class MaAgentGetConfigState {

    public class Input {
        @InvocableVariable(required=false label='Config Id'
            description='MA_Saved_Configuration__c Id; blank for unsaved sessions')
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

        if (String.isNotBlank(configId)) {
            List<MA_Saved_Configuration__c> saved = [
                SELECT Config_Payload__c
                FROM   MA_Saved_Configuration__c
                WHERE  Id = :configId
                LIMIT  1
            ];
            if (!saved.isEmpty() && String.isNotBlank(saved[0].Config_Payload__c)) {
                try {
                    Map<String, Object> payload =
                        (Map<String, Object>) JSON.deserializeUntyped(saved[0].Config_Payload__c);
                    out.company      = MaAgentConfigActions.strOf(payload, 'company');
                    out.industry     = MaAgentConfigActions.strOf(payload, 'industry');
                    out.accent       = MaAgentConfigActions.strOf(payload, 'accent');
                    out.objectsCount = MaAgentConfigActions.intOf(payload, 'objectsCount');
                    out.depsCount    = MaAgentConfigActions.intOf(payload, 'depsCount');
                    out.healthScore  = MaAgentConfigActions.intOf(payload, 'healthScore');
                    out.note         = MaAgentConfigActions.strOf(payload, 'note');
                } catch (Exception e) {
                    // Malformed payload — return defaults
                }
            }
        }

        // Collect unique industry keys from active content records
        List<MA_Page_Content__c> iRecs = [
            SELECT Industry_Key__c
            FROM   MA_Page_Content__c
            WHERE  Offering_Key__c  = 'migration-accelerator'
            AND    Template_Type__c = 'story'
            AND    Industry_Key__c != null
            AND    Active__c = true
            LIMIT  200
        ];
        Set<String> seen = new Set<String>();
        for (MA_Page_Content__c rec : iRecs) {
            seen.add(rec.Industry_Key__c);
        }
        out.availableIndustries = new List<String>(seen);
        out.availableIndustries.sort();

        return out;
    }
}
