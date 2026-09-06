/**
 * Agentforce invocable action: apply a partial config delta to the LWC panel.
 * Validates the delta, then publishes a GTM_Config_Update__e platform event
 * that the maConfigCustomize LWC is subscribed to via empApi.
 */
public without sharing class GtmAgentApplyConfigUpdate {

    public class Input {
        @InvocableVariable(required=true label='Session Token'
            description='Opaque token from the LWC session; routes the event to the correct panel instance.')
        public String sessionToken;

        @InvocableVariable(required=true label='Updates JSON'
            description='JSON object with one or more fields to update: company, industry, accent, objectsCount, depsCount, healthScore, note.')
        public String updatesJson;
    }

    public class Output {
        @InvocableVariable(label='Success')        public Boolean success;
        @InvocableVariable(label='Applied JSON')   public String  appliedJson;
        @InvocableVariable(label='Error message')  public String  errorMessage;
    }

    @InvocableMethod(
        label='Apply GTM Configurator Update'
        description='Validates a partial config delta and publishes it to the GTM Configurator LWC via platform event.'
        category='GTM Offerings'
    )
    public static List<Output> execute(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(applyUpdate(inp));
        }
        return results;
    }

    private static Output applyUpdate(Input inp) {
        Output out = new Output();
        out.success      = false;
        out.appliedJson  = '';
        out.errorMessage = '';

        if (String.isBlank(inp.sessionToken)) {
            out.errorMessage = 'sessionToken is required.';
            return out;
        }
        if (String.isBlank(inp.updatesJson)) {
            out.errorMessage = 'updatesJson is required.';
            return out;
        }

        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(inp.updatesJson);
        } catch (Exception e) {
            out.errorMessage = 'updatesJson is not valid JSON.';
            return out;
        }

        // Strip unknown keys and validate allowed ones
        Map<String, Object> clean = new Map<String, Object>();
        List<String> errors = new List<String>();
        for (String key : raw.keySet()) {
            if (!GtmAgentConfigActions.ALLOWED_DELTA_KEYS.contains(key)) {
                continue;
            }
            String err = GtmAgentConfigActions.validateDeltaField(key, raw.get(key));
            if (err != null) {
                errors.add(err);
            } else {
                clean.put(key, raw.get(key));
            }
        }

        if (!errors.isEmpty()) {
            out.errorMessage = String.join(errors, ' ');
            return out;
        }
        if (clean.isEmpty()) {
            out.errorMessage = 'No recognised or valid fields found in updatesJson.';
            return out;
        }

        String cleanJson = JSON.serialize(clean);

        GTM_Config_Update__e evt = new GTM_Config_Update__e(
            Session_Token__c = inp.sessionToken,
            Updates_JSON__c  = cleanJson
        );
        Database.SaveResult sr = EventBus.publish(evt);

        if (sr.isSuccess()) {
            out.success     = true;
            out.appliedJson = cleanJson;
        } else {
            List<String> dbErrs = new List<String>();
            for (Database.Error e : sr.getErrors()) {
                dbErrs.add(e.getMessage());
            }
            out.errorMessage = 'Platform event publish failed: ' + String.join(dbErrs, '; ');
        }

        return out;
    }
}
