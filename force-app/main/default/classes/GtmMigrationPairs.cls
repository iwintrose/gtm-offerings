/**
 * Resolves "what are they moving from, and to?" into "can the accelerator
 * actually process that?".
 *
 * This is the data half of the unsupported-pair gate. GtmAssessmentScoring owns
 * the *rule* (an unsupported pair suppresses the tier and marks the assessment
 * advisory) and stays free of SOQL; this class owns the *list*, and the list is
 * configuration, never code:
 *
 *   GTM_Migration_Platform__mdt  one row per platform: a canonical key, a
 *                               display label, and the free-text spellings that
 *                               resolve to it (Aliases__c, semicolon-separated)
 *   GTM_Migration_Pair__mdt      one row per source -> target combination, with
 *                               Supported__c and, when it is not, the sentence
 *                               a rep should read
 *
 * Adding a platform, a spelling, or a newly-supported pair is a metadata edit.
 * Nothing here branches on a platform name, which is the point: the adaptive
 * layer that varies questions per source x target pair extends the same two
 * tables rather than adding cases to this file.
 *
 * WHY Current_Platform__c / Target_Platform__c ARE FREE TEXT AND STILL WORK:
 * normalize() strips case, punctuation and spacing before matching, so
 * "Marketing-Cloud Engagement", "marketing cloud engagement" and "MCE" all land
 * on the same platform record via its aliases.
 *
 * FAIL-OPEN, DELIBERATELY. If no pair metadata is deployed at all, or the pair
 * simply is not listed, the verdict is "not evaluated" and the gate stays
 * inert. An empty config table is a deployment state, not a product judgement,
 * and turning every assessment advisory because a table has not been populated
 * yet would break the instrument for everyone. Once pairs ARE listed, a listed
 * pair with Supported__c unticked is a real "no" and carries its own wording.
 */
public with sharing class GtmMigrationPairs {

    /** Cached per transaction; custom metadata cannot change mid-transaction. */
    private static Map<String, String> aliasToKey;
    private static Map<String, String> keyToLabel;
    private static Map<String, String> keyToFamily;
    private static Map<String, GTM_Migration_Pair__mdt> pairsByKey;

    /** Test seams: let a test supply config without deploying metadata. */
    @TestVisible
    private static List<GTM_Migration_Platform__mdt> platformOverride;
    @TestVisible
    private static List<GTM_Migration_Pair__mdt> pairOverride;

    // ------------------------------------------------------------ platforms

    /**
     * The canonical platform key a free-text platform name resolves to, or null
     * when nothing matches. Both the key itself and every alias are matched, so
     * a client that already sends canonical keys needs no aliases configured.
     */
    public static String resolvePlatformKey(String rawName) {
        if (String.isBlank(rawName)) {
            return null;
        }
        loadPlatforms();
        return aliasToKey.get(normalize(rawName));
    }

    /**
     * The family a canonical platform key belongs to, or null when it declares
     * none. Families are the second link in the assessment instrument's
     * resolution chain -- exact pair, then source-family x target, then
     * target-only, then base -- so a pack can say the true thing about several
     * sources at once (every inbound suite has the same "the CRM is the
     * marketing platform" problem) without anyone copying a pack per platform.
     *
     * Purely additive: a platform with no Family_Key__c simply skips that link
     * in the chain. It is deliberately here rather than in the instrument
     * resolver, because "which platforms behave alike" is the same kind of
     * configuration as "which spellings mean the same platform", and both
     * belong to the table that already owns platform identity.
     */
    public static String familyFor(String rawName) {
        String key = resolvePlatformKey(rawName);
        if (key == null) {
            return null;
        }
        String family = keyToFamily.get(key);
        return String.isBlank(family) ? null : family;
    }

    /**
     * One option for the engagement-link wizard's Source/Target platform
     * pickers. `label` is what the wizard stores (the human display string the
     * page renders), never `key`.
     */
    public class PlatformOption implements Comparable {
        @AuraEnabled public String key;
        @AuraEnabled public String label;

        public PlatformOption(String key, String label) {
            this.key = key;
            this.label = label;
        }

        public Integer compareTo(Object other) {
            PlatformOption o = (PlatformOption) other;
            String a = label == null ? '' : label.toLowerCase();
            String b = o.label == null ? '' : o.label.toLowerCase();
            return a.compareTo(b);
        }
    }

    /**
     * Active platforms as {key, label}, ordered by label. Read-only (SOQL via
     * platformRows(), zero DML). A row with a blank key is skipped; a row with
     * a blank label falls back to its key so it is still selectable.
     */
    @AuraEnabled(cacheable=true)
    public static List<PlatformOption> listPlatforms() {
        List<PlatformOption> options = new List<PlatformOption>();
        for (GTM_Migration_Platform__mdt row : platformRows()) {
            if (row.Active__c == false || String.isBlank(row.Platform_Key__c)) {
                continue;
            }
            String key = row.Platform_Key__c.trim();
            String label = String.isBlank(row.Display_Label__c) ? key : row.Display_Label__c;
            options.add(new PlatformOption(key, label));
        }
        options.sort();
        return options;
    }

    /**
     * The display label a free-text default (e.g. an offering's CMS
     * defaultSourcePlatform) resolves to through the platform aliases, or null
     * when it is blank or matches nothing -- the wizard then shows the raw text
     * under "Other". Read-only.
     */
    @AuraEnabled(cacheable=true)
    public static String resolveDefaultLabel(String raw) {
        String key = resolvePlatformKey(raw);
        if (key == null) {
            return null;
        }
        String label = keyToLabel.get(key);
        return String.isBlank(label) ? null : label;
    }

    /** Display label for a canonical key; falls back to what was passed in. */
    public static String labelFor(String rawName) {
        String key = resolvePlatformKey(rawName);
        if (key == null) {
            return rawName;
        }
        String label = keyToLabel.get(key);
        return String.isBlank(label) ? rawName : label;
    }

    // ---------------------------------------------------------------- pairs

    /**
     * The verdict for one source/target combination, in the shape
     * GtmAssessmentScoring.score() takes.
     *
     * Three outcomes, and the difference between the last two matters:
     *   - a listed, supported pair  -> evaluated, supported
     *   - a listed, unsupported one -> evaluated, NOT supported, with the
     *                                  configured reason
     *   - anything else (unknown platform name, unlisted combination, no pair
     *     metadata at all) -> NOT evaluated, and the gate does nothing
     *
     * The third case covers an unrecognised free-text platform. Suppressing a
     * tier because a prospect typed a platform name nobody had added an alias
     * for would punish the prospect for a config gap; the assessment is still
     * scored and a rep still sees what they typed.
     */
    public static GtmAssessmentScoring.PairEligibility evaluate(String sourceName, String targetName) {
        String sourceKey = resolvePlatformKey(sourceName);
        String targetKey = resolvePlatformKey(targetName);
        if (sourceKey == null || targetKey == null) {
            return new GtmAssessmentScoring.PairEligibility();
        }

        loadPairs();
        GTM_Migration_Pair__mdt pair = pairsByKey.get(pairKey(sourceKey, targetKey));
        if (pair == null) {
            return new GtmAssessmentScoring.PairEligibility();
        }
        if (pair.Supported__c == true) {
            return new GtmAssessmentScoring.PairEligibility(true, null);
        }

        String reason = String.isBlank(pair.Unsupported_Reason__c)
            ? labelFor(sourceName) + ' to ' + labelFor(targetName) +
              ' is not a combination the accelerator can process. ' +
              'Treat this as an advisory conversation, not a scoped migration.'
            : pair.Unsupported_Reason__c;
        return new GtmAssessmentScoring.PairEligibility(false, reason);
    }

    // --------------------------------------------------------------- loading

    private static List<GTM_Migration_Platform__mdt> platformRows() {
        return platformOverride != null
            ? platformOverride
            : [
                SELECT Platform_Key__c, Display_Label__c, Aliases__c,
                       Family_Key__c, Active__c
                FROM GTM_Migration_Platform__mdt
                WHERE Active__c = true
                LIMIT 500
            ];
    }

    private static void loadPlatforms() {
        if (aliasToKey != null) {
            return;
        }
        aliasToKey  = new Map<String, String>();
        keyToLabel  = new Map<String, String>();
        keyToFamily = new Map<String, String>();

        for (GTM_Migration_Platform__mdt row : platformRows()) {
            if (row.Active__c == false || String.isBlank(row.Platform_Key__c)) {
                continue;
            }
            String key = row.Platform_Key__c.trim();
            keyToLabel.put(key, row.Display_Label__c);
            if (String.isNotBlank(row.Family_Key__c)) {
                keyToFamily.put(key, row.Family_Key__c.trim());
            }
            // The key is always its own alias, so a canonical value needs no
            // configuration to resolve.
            aliasToKey.put(normalize(key), key);
            // So is the display label -- the proper name a person would type
            // ("Marketing Cloud Engagement", punctuation/spacing noise and
            // all) is exactly as valid free text as anything in Aliases__c,
            // and requiring it to ALSO be listed there is a configuration
            // trap: whoever authors the CMDT record reads the label right
            // next to it and has no reason to expect it needs restating.
            if (String.isNotBlank(row.Display_Label__c)) {
                String normLabel = normalize(row.Display_Label__c);
                if (String.isNotBlank(normLabel)) {
                    aliasToKey.put(normLabel, key);
                }
            }
            if (String.isBlank(row.Aliases__c)) {
                continue;
            }
            for (String alias : row.Aliases__c.split(';')) {
                String norm = normalize(alias);
                if (String.isNotBlank(norm)) {
                    aliasToKey.put(norm, key);
                }
            }
        }
    }

    private static void loadPairs() {
        if (pairsByKey != null) {
            return;
        }
        pairsByKey = new Map<String, GTM_Migration_Pair__mdt>();

        List<GTM_Migration_Pair__mdt> rows = pairOverride != null
            ? pairOverride
            : [
                SELECT Source_Key__c, Target_Key__c, Supported__c,
                       Unsupported_Reason__c, Active__c
                FROM GTM_Migration_Pair__mdt
                WHERE Active__c = true
                LIMIT 1000
            ];

        for (GTM_Migration_Pair__mdt row : rows) {
            if (row.Active__c == false ||
                String.isBlank(row.Source_Key__c) ||
                String.isBlank(row.Target_Key__c)) {
                continue;
            }
            pairsByKey.put(pairKey(row.Source_Key__c.trim(), row.Target_Key__c.trim()), row);
        }
    }

    private static String pairKey(String sourceKey, String targetKey) {
        return normalize(sourceKey) + '>' + normalize(targetKey);
    }

    /**
     * Case, spacing and punctuation all removed, so "SFMC Next", "sfmc_next"
     * and "Marketing-Cloud  Next" compare equal. Aggressive on purpose: the
     * input is a human typing a product name into a free-text box.
     */
    @TestVisible
    private static String normalize(String value) {
        if (value == null) {
            return '';
        }
        return value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    /** Clears the per-transaction cache. Test-only. */
    @TestVisible
    private static void resetCache() {
        aliasToKey  = null;
        keyToLabel  = null;
        keyToFamily = null;
        pairsByKey  = null;
    }
}
