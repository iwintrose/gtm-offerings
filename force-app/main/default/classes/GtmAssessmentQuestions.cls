/**
 * Where the questionnaire's WORDS come from.
 *
 * The split this class exists to enforce:
 *
 *   GtmAssessmentScoring / GtmEstateComplexity  own the dimension KEYS, the
 *       scales and the bands. They are Apex because they are the allowlist a
 *       guest-reachable endpoint scores against -- a consultant editing a text
 *       field must never be able to change what counts.
 *
 *   GTM_Assessment_Question__mdt               owns every human-readable string:
 *       the dimension name, the question, the ascending answer options and the
 *       one-line "what this measures". A consultant reworders a question in
 *       Setup, deploys nothing, and no developer is involved.
 *
 * Everything is served as DATA, not branches. The questionnaire renders
 * whatever rows come back, in Sort_Order__c order, with Max_Answer_Value__c
 * options each -- so the adaptive layer that varies questions per source x
 * target pair can add rows and per-pair overrides without this class or the
 * component growing a single `if (platform == ...)`.
 *
 * DRIFT IS VISIBLE, NOT SILENT. A row whose Dimension_Key__c is not in the
 * matching Apex allowlist still renders, but comes back with `scored = false`
 * -- collected and shown, contributing nothing. unscoredKeys() and
 * missingKeys() name both halves of any mismatch so a test or an admin can see
 * it rather than discovering it as a total that quietly stopped adding up.
 */
public with sharing class GtmAssessmentQuestions {

    public static final String INSTRUMENT_READINESS  = 'Readiness';
    public static final String INSTRUMENT_COMPLEXITY = 'Complexity';

    /** Test seam: supply rows without deploying custom metadata. */
    @TestVisible
    private static List<GTM_Assessment_Question__mdt> rowOverride;

    private static Map<String, List<GTM_Assessment_Question__mdt>> cachedRows
        = new Map<String, List<GTM_Assessment_Question__mdt>>();

    // ---------------------------------------------------------------- types

    public class AnswerOption {
        @AuraEnabled public Integer value;
        @AuraEnabled public String label;

        public AnswerOption(Integer value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class Question {
        @AuraEnabled public String instrument;
        @AuraEnabled public String dimensionKey;
        @AuraEnabled public String dimensionName;
        @AuraEnabled public String measures;
        @AuraEnabled public String questionText;
        @AuraEnabled public Integer maxAnswerValue;
        @AuraEnabled public Decimal sortOrder;
        @AuraEnabled public List<AnswerOption> options;
        /**
         * False when this row's key is not in the Apex allowlist for its
         * instrument. The question is still shown -- an answer to it is simply
         * worth nothing. Surfaced rather than hidden so the gap is diagnosable.
         */
        @AuraEnabled public Boolean scored;

        public Question() {
            this.options = new List<AnswerOption>();
            this.scored  = false;
        }
    }

    public class Questionnaire {
        @AuraEnabled public List<Question> readiness;
        @AuraEnabled public List<Question> complexity;
        /** Maximums, so the client prints "18 out of 32" from the server. */
        @AuraEnabled public Integer readinessMaxScore;
        @AuraEnabled public Integer complexityMaxScore;

        public Questionnaire() {
            this.readiness          = new List<Question>();
            this.complexity         = new List<Question>();
            this.readinessMaxScore  = GtmAssessmentScoring.MAX_TOTAL_SCORE;
            this.complexityMaxScore = GtmEstateComplexity.MAX_TOTAL_SCORE;
        }
    }

    // ------------------------------------------------------------- retrieval

    /**
     * Both instruments in one round trip, for the booking questionnaire.
     * Cacheable: the wording changes when an admin edits metadata, not when a
     * prospect does anything, so a stale client cache is a non-event.
     */
    @AuraEnabled(cacheable=true)
    public static Questionnaire getQuestionnaire(String offeringKey) {
        Questionnaire out = new Questionnaire();
        for (Question q : questionsFor(offeringKey, INSTRUMENT_READINESS)) {
            out.readiness.add(q);
        }
        for (Question q : questionsFor(offeringKey, INSTRUMENT_COMPLEXITY)) {
            out.complexity.add(q);
        }
        return out;
    }

    /**
     * The active questions for ONE OFFERING's instrument, in display order.
     *
     * The offering filter is applied in the SOQL rather than in the loop below,
     * because this is a security boundary as much as a content one: this class
     * is reachable from the guest questionnaire, and "return every offering's
     * questions and let the caller pick" would put an unrelated offering's
     * unreleased content on a public endpoint.
     */
    public static List<Question> questionsFor(String offeringKey, String instrument) {
        Set<String> allowed = allowlistFor(offeringKey, instrument);
        List<Question> out = new List<Question>();
        for (GTM_Assessment_Question__mdt row : rows(offeringKey)) {
            if (row.Active__c == false ||
                !instrument.equalsIgnoreCase(String.valueOf(row.Instrument__c))) {
                continue;
            }
            out.add(toQuestion(row, allowed));
        }
        return out;
    }

    /**
     * dimension key -> display name, for rendering a stored Section_Scores__c /
     * Estate_Complexity_Dimensions__c blob as something a prospect can read.
     * Includes inactive rows on purpose: a retired question still has to have a
     * name when an old readout is reopened.
     */
    /**
     * Migration Accelerator's dimension names, for a caller with no offering in
     * hand.
     *
     * The readout-rendering callers (GtmReadoutModel, GtmReadoutController,
     * GtmReadoutAgentContext) look up display wording for a stored score blob,
     * and threading an offering key through that whole stack is a separate
     * change ADR-0007's plan deliberately scopes out. They read Migration
     * Accelerator's names because every readout that exists today is Migration
     * Accelerator's. A second offering's readout degrades to showing raw
     * dimension keys -- which is the documented, already-handled degradation in
     * those callers, not a wrong name from another offering. Named here so the
     * assumption is greppable rather than implicit.
     */
    public static Map<String, String> dimensionNames() {
        return dimensionNames(GtmAssessmentFrames.MIGRATION_ACCELERATOR);
    }

    public static Map<String, String> dimensionNames(String offeringKey) {
        Map<String, String> names = new Map<String, String>();
        for (GTM_Assessment_Question__mdt row : rows(offeringKey)) {
            if (String.isNotBlank(row.Dimension_Key__c)) {
                names.put(row.Dimension_Key__c.trim(), row.Dimension_Name__c);
            }
        }
        return names;
    }

    // ------------------------------------------------------------ drift aids

    /** Configured keys that the scorer will ignore. Empty is the healthy state. */
    public static Set<String> unscoredKeys(String offeringKey, String instrument) {
        Set<String> allowed = allowlistFor(offeringKey, instrument);
        Set<String> unscored = new Set<String>();
        for (Question q : questionsFor(offeringKey, instrument)) {
            if (!allowed.contains(q.dimensionKey)) {
                unscored.add(q.dimensionKey);
            }
        }
        return unscored;
    }

    /** Scoreable keys with no wording configured -- a question nobody can answer. */
    public static Set<String> missingKeys(String offeringKey, String instrument) {
        Set<String> missing = new Set<String>(allowlistFor(offeringKey, instrument));
        for (Question q : questionsFor(offeringKey, instrument)) {
            missing.remove(q.dimensionKey);
        }
        return missing;
    }

    // --------------------------------------------------------------- private

    /**
     * The keys the scorer will actually read for this offering.
     *
     * For migration-accelerator that is the compiled allowlist, exactly as
     * before. For any other offering the compiled lists say nothing -- they are
     * Migration Accelerator's dimensions -- so the offering's OWN configured
     * keys are the allowlist, which is what makes `scored` true for its own
     * questions instead of marking every one of them as drift. The drift aids
     * below then compare an offering against itself rather than against
     * Migration Accelerator, which is the only comparison that means anything.
     */
    private static Set<String> allowlistFor(String offeringKey, String instrument) {
        if (GtmAssessmentFrames.MIGRATION_ACCELERATOR.equalsIgnoreCase(
                String.isBlank(offeringKey) ? '' : offeringKey.trim())) {
            return INSTRUMENT_COMPLEXITY.equalsIgnoreCase(instrument)
                ? new Set<String>(GtmEstateComplexity.DIMENSIONS)
                : new Set<String>(GtmAssessmentScoring.DIMENSIONS);
        }
        Set<String> keys = new Set<String>();
        for (GTM_Assessment_Question__mdt row : rows(offeringKey)) {
            if (row.Active__c != false
                    && instrument.equalsIgnoreCase(String.valueOf(row.Instrument__c))
                    && String.isNotBlank(row.Dimension_Key__c)) {
                keys.add(row.Dimension_Key__c.trim());
            }
        }
        return keys;
    }

    private static Question toQuestion(GTM_Assessment_Question__mdt row, Set<String> allowed) {
        Question q       = new Question();
        q.instrument     = String.valueOf(row.Instrument__c);
        q.dimensionKey   = row.Dimension_Key__c == null ? null : row.Dimension_Key__c.trim();
        q.dimensionName  = row.Dimension_Name__c;
        q.measures       = row.Measures__c;
        q.questionText   = row.Question_Text__c;
        q.sortOrder      = row.Sort_Order__c;
        q.scored         = allowed.contains(q.dimensionKey);
        q.maxAnswerValue = row.Max_Answer_Value__c == null
            ? 0
            : row.Max_Answer_Value__c.intValue();

        // Options are built from the max, not from which labels happen to be
        // filled in: a blank option in the middle of a scale is a config error
        // worth seeing as a blank choice rather than silently renumbering the
        // ones after it, which would change what every stored answer means.
        List<String> labels = new List<String>{
            row.Option_1_Label__c, row.Option_2_Label__c,
            row.Option_3_Label__c, row.Option_4_Label__c
        };
        for (Integer i = 0; i < q.maxAnswerValue && i < labels.size(); i++) {
            q.options.add(new AnswerOption(i + 1, labels[i]));
        }
        return q;
    }

    private static List<GTM_Assessment_Question__mdt> rows(String offeringKey) {
        String key = String.isBlank(offeringKey) ? '' : offeringKey.trim().toLowerCase();
        if (cachedRows.containsKey(key)) {
            return cachedRows.get(key);
        }
        cachedRows.put(key, rowOverride != null
            ? rowOverride
            : [
                SELECT Instrument__c, Dimension_Key__c, Dimension_Name__c, Measures__c,
                       Question_Text__c, Option_1_Label__c, Option_2_Label__c,
                       Option_3_Label__c, Option_4_Label__c, Max_Answer_Value__c,
                       Sort_Order__c, Active__c
                FROM GTM_Assessment_Question__mdt
                WHERE Offering_Key__c = :offeringKey
                ORDER BY Sort_Order__c NULLS LAST, Dimension_Key__c
                LIMIT 200
            ]);
        return cachedRows.get(key);
    }

    /** Clears the per-transaction cache. Test-only. */
    @TestVisible
    private static void resetCache() {
        cachedRows = new Map<String, List<GTM_Assessment_Question__mdt>>();
    }
}
