/**
 * Shared helpers and types for the GTM Configurator Agentforce actions.
 * Invocable methods live in MaAgentGetConfigState and MaAgentApplyConfigUpdate
 * (Salesforce allows only one @InvocableMethod per class).
 */
public without sharing class MaAgentConfigActions {

    public static final Set<String> ALLOWED_DELTA_KEYS = new Set<String>{
        'company', 'industry', 'accent', 'objectsCount', 'depsCount', 'healthScore', 'note'
    };

    public static String strOf(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v == null ? '' : String.valueOf(v);
    }

    public static Integer intOf(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v == null) return 0;
        try { return Integer.valueOf(String.valueOf(v)); } catch (Exception e) { return 0; }
    }

    public static String validateDeltaField(String key, Object val) {
        if (key == 'accent') {
            if (!Pattern.matches('#[0-9a-fA-F]{6}', String.valueOf(val))) {
                return 'accent must be a 6-digit hex color (e.g. #FF5733).';
            }
        } else if (key == 'company' || key == 'note') {
            Integer maxLen = (key == 'company') ? 120 : 500;
            if (String.valueOf(val).length() > maxLen) {
                return key + ' must be ' + maxLen + ' characters or fewer.';
            }
        } else if (key == 'objectsCount' || key == 'depsCount') {
            try {
                Integer v = Integer.valueOf(String.valueOf(val));
                if (v < 0 || v > 999999) return key + ' must be between 0 and 999999.';
            } catch (Exception e) {
                return key + ' must be an integer.';
            }
        } else if (key == 'healthScore') {
            try {
                Integer v = Integer.valueOf(String.valueOf(val));
                if (v < 0 || v > 100) return 'healthScore must be between 0 and 100.';
            } catch (Exception e) {
                return 'healthScore must be an integer.';
            }
        }
        return null;
    }
}
