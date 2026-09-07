/**
 * Turns a score plus a resolved pack into the thing a rep actually reads out.
 *
 * Three jobs, and the first one is the reason the class exists:
 *
 * 1. GATES. A gate is a boolean predicate over the answers that adds a tier
 *    QUALIFIER and a block of prose. It never touches the number and never
 *    moves the band. "Fast-Track, foundation-gated" is a legitimate and common
 *    result -- a small, clean, portable estate that still cannot start for four
 *    months because the target's data layer does not exist yet -- and the
 *    readout has to say BOTH halves at once. Bending the score to express the
 *    gate would make two Fast-Tracks incomparable; suppressing the tier would
 *    throw away a true reading of the estate. So neither happens.
 *
 * 2. POSTURE. Above the fold, before the number, in the client's language:
 *    what here is measured and what here is what you told us. Whenever the
 *    SOURCE end is not instrumented, estate figures are marked illustrative --
 *    keyed on the source rather than the headline posture because the figures
 *    come from reading the source, so an instrumented source with an
 *    unverified target has real counts and an unverified destination.
 *
 * 3. HEDGING BY CONSTRUCTION. Callouts carrying verificationRequired render
 *    with the hedge attached, rather than relying on whoever writes the deck
 *    that week to remember which platform assertions are working assumptions.
 *
 * Pure: no SOQL, no DML. Everything it needs arrives as arguments, so the
 * class that decides what a readout says is unit-testable with no org data,
 * for the same reason GtmAssessmentScoring is.
 */
public with sharing class GtmAssessmentReadout {

    /** Context keys a gate predicate may reference beyond the answer keys. */
    public static final String FIELD_SOURCE = 'source';
    public static final String FIELD_TARGET = 'target';

    // ---------------------------------------------------------------- types

    /** One scored dimension, ready to render. */
    public class DimensionResult {
        @AuraEnabled public Integer position;
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public Integer maxAttainable;
        @AuraEnabled public String ceilingReason;
        /** True when this slot was substituted in for this pair (layer 3). */
        @AuraEnabled public Boolean substituted;
        /** True when the pair explicitly asked the readout to lead with it. */
        @AuraEnabled public Boolean emphasised;
    }

    /** A gate that fired. */
    public class GateResult {
        @AuraEnabled public String key;
        @AuraEnabled public String qualifier;
        @AuraEnabled public String block;
        @AuraEnabled public String severity;
    }

    /** One supplement set's index. Never added to the readiness total. */
    public class IndexResult {
        @AuraEnabled public String indexKey;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer minimum;
        @AuraEnabled public Integer maximum;
        @AuraEnabled public Integer answered;
    }

    public class Readout {
        @AuraEnabled public String tier;
        /** The gates' qualifiers, joined. Null when nothing fired. */
        @AuraEnabled public String qualifier;
        /** tier + qualifier as one phrase, e.g. "Fast-Track, foundation-gated". */
        @AuraEnabled public String tierPhrase;
        @AuraEnabled public Decimal total;
        @AuraEnabled public Integer maxTotal;
        @AuraEnabled public List<DimensionResult> perDimension;
        @AuraEnabled public List<GtmAssessmentInstrument.Callout> callouts;
        @AuraEnabled public List<GateResult> gates;
        @AuraEnabled public String horizon;
        @AuraEnabled public String posture;
        @AuraEnabled public String postureStatement;
        @AuraEnabled public Boolean estateFiguresIllustrative;
        @AuraEnabled public List<IndexResult> supplementIndexes;
        /** Unscored verbatim probes, as said. */
        @AuraEnabled public Map<String, String> notes;
        @AuraEnabled public String pairKey;
        @AuraEnabled public String version;
        @AuraEnabled public String resolutionNote;
        /** True when any rendered callout is a working assumption. */
        @AuraEnabled public Boolean anyVerificationRequired;
        /**
         * base slot key -> the authored variant that filled it. Which PACK was
         * used is pairKey; this is which PATH through it the answers took, and
         * a readout that cannot say that cannot explain why two prospects on the
         * same pair were asked different questions.
         */
        @AuraEnabled public Map<String, String> branchPath;

        public Readout() {
            this.perDimension      = new List<DimensionResult>();
            this.callouts          = new List<GtmAssessmentInstrument.Callout>();
            this.gates             = new List<GateResult>();
            this.supplementIndexes = new List<IndexResult>();
            this.notes             = new Map<String, String>();
            this.maxTotal          = GtmAssessmentScoring.MAX_TOTAL_SCORE;
            this.branchPath        = new Map<String, String>();
            this.estateFiguresIllustrative = true;
            this.anyVerificationRequired   = false;
        }
    }

    /** What gets persisted to Supplement_Scores__c, plus what the readout needs. */
    public class SupplementResult {
        public Map<String, IndexResult> indexes;
        public Map<String, Integer> answers;
        public Map<String, String> notes;
        public String horizon;
        /** Null when nothing was answered — an empty blob is worse than none. */
        public String json;

        public SupplementResult() {
            this.indexes = new Map<String, IndexResult>();
            this.answers = new Map<String, Integer>();
            this.notes   = new Map<String, String>();
        }
    }

    // ------------------------------------------------------------- composing

    public static Readout compose(
        GtmAssessmentScoring.Score score,
        GtmAssessmentInstrument.Pack pack,
        Map<String, Integer> supplementAnswers
    ) {
        return compose(score, pack, supplementAnswers, null);
    }

    public static Readout compose(
        GtmAssessmentScoring.Score score,
        GtmAssessmentInstrument.Pack pack,
        Map<String, Integer> supplementAnswers,
        Map<String, String> supplementNotes
    ) {
        Readout out = new Readout();
        GtmAssessmentInstrument.Pack p = pack == null
            ? GtmAssessmentInstrument.basePack()
            : pack;

        out.posture          = p.posture;
        out.postureStatement = p.postureStatement;
        out.pairKey          = p.pairKey;
        out.version          = p.version;
        out.resolutionNote   = p.resolutionNote;
        out.estateFiguresIllustrative = p.getEstateFiguresIllustrative();

        if (score != null) {
            out.tier  = score.tier;
            out.total = score.total;
            // The maximum this score was measured against, not today's -- see
            // GtmAssessmentScoring.Score.maxTotal.
            if (score.maxTotal != null) {
                out.maxTotal = score.maxTotal;
            }
            if (score.branchPath != null) {
                out.branchPath = score.branchPath;
            }
        }

        SupplementResult supp = scoreSupplements(p, supplementAnswers, supplementNotes);
        out.supplementIndexes = supp.indexes.values();
        out.notes             = supp.notes;
        out.horizon           = supp.horizon;

        buildDimensions(out, score, p);
        buildCallouts(out, p);
        buildGates(out, score, p, supp.answers);
        return out;
    }

    private static void buildDimensions(
        Readout out, GtmAssessmentScoring.Score score, GtmAssessmentInstrument.Pack p
    ) {
        Set<String> emphasis = new Set<String>(
            p.emphasisSlots == null ? new List<String>() : p.emphasisSlots
        );
        // The chosen OPTION, not what it was worth: "3 of 4" is a position on
        // the scale the respondent saw. What that option contributed to the
        // total is a separate, author-set number and belongs in the total.
        Map<String, Integer> answers = (score == null || score.answerValues == null
                                        || score.answerValues.isEmpty())
            ? ((score == null || score.sectionScores == null)
                ? new Map<String, Integer>()
                : score.sectionScores)
            : score.answerValues;
        for (GtmAssessmentInstrument.Slot slot : p.slots) {
            DimensionResult d = new DimensionResult();
            d.position      = slot.position;
            d.key           = slot.key;
            d.label         = slot.label;
            d.value         = answers.get(slot.key);
            d.maxAttainable = slot.maxAttainable;
            d.ceilingReason = slot.ceilingReason;
            d.substituted   = slot.key != slot.baseKey;
            d.emphasised    = emphasis.contains(slot.key);
            out.perDimension.add(d);
        }
    }

    private static void buildCallouts(Readout out, GtmAssessmentInstrument.Pack p) {
        for (GtmAssessmentInstrument.Callout c : p.callouts) {
            out.callouts.add(c);
            if (c.verificationRequired == true) {
                out.anyVerificationRequired = true;
            }
        }
    }

    /**
     * Evaluates every gate and collects the ones that fire. The tier is copied
     * through untouched: a gate qualifies a band, it never replaces one.
     */
    private static void buildGates(
        Readout out,
        GtmAssessmentScoring.Score score,
        GtmAssessmentInstrument.Pack p,
        Map<String, Integer> supplementAnswers
    ) {
        Map<String, Object> context = new Map<String, Object>();
        context.put(FIELD_SOURCE, p.sourceKey);
        context.put(FIELD_TARGET, p.targetKey);
        // Copied key by key rather than putAll'd: Apex will not widen a
        // Map<String, Integer> to a Map<String, Object>, and a context that
        // silently lost the answers would leave every gate inert.
        // Answer values, not points -- the same context branching sees, so a
        // consultant who has learned one predicate language has learned both.
        Map<String, Integer> gateAnswers = (score == null) ? null
            : (score.answerValues != null && !score.answerValues.isEmpty()
                ? score.answerValues
                : score.sectionScores);
        if (gateAnswers != null) {
            for (String k : gateAnswers.keySet()) {
                context.put(k, gateAnswers.get(k));
            }
        }
        if (supplementAnswers != null) {
            for (String k : supplementAnswers.keySet()) {
                context.put(k, supplementAnswers.get(k));
            }
        }

        List<String> qualifiers = new List<String>();
        for (GtmAssessmentInstrument.Gate g : p.gates) {
            if (g.predicate == null || !matches(g.predicate, context)) {
                continue;
            }
            GateResult r = new GateResult();
            r.key       = g.key;
            r.qualifier = g.tierQualifier;
            r.block     = g.readoutBlock;
            r.severity  = g.severity;
            out.gates.add(r);
            if (String.isNotBlank(g.tierQualifier)) {
                qualifiers.add(g.tierQualifier);
            }
        }
        if (!qualifiers.isEmpty()) {
            out.qualifier = String.join(qualifiers, '; ');
        }
        out.tierPhrase = String.isBlank(out.tier)
            ? out.qualifier
            : (String.isBlank(out.qualifier) ? out.tier : out.tier + ', ' + out.qualifier);
    }

    // ----------------------------------------------------------- supplements

    /**
     * Scores the layer-4 sets into their OWN named indexes. Nothing here can
     * reach the readiness total: the answers land in a separate map, the totals
     * land in separate indexes, and the result is persisted to a separate field.
     * Making the separation structural rather than intentional is the point --
     * these questions measure whether the target's prerequisite stack exists,
     * which is a different question from how hard the estate is to move, and a
     * single blended number would answer neither.
     */
    public static SupplementResult scoreSupplements(
        GtmAssessmentInstrument.Pack pack,
        Map<String, Integer> answers,
        Map<String, String> notes
    ) {
        SupplementResult out = new SupplementResult();
        if (pack == null || pack.supplements == null || pack.supplements.isEmpty()) {
            return out;
        }
        Map<String, Integer> raw = answers == null ? new Map<String, Integer>() : answers;

        for (GtmAssessmentInstrument.Supplement s : pack.supplements) {
            if (s.scored != true) {
                // Unscored verbatim probe: recorded as said, computed on never.
                if (notes != null && String.isNotBlank(notes.get(s.key))) {
                    out.notes.put(s.key, notes.get(s.key));
                }
                continue;
            }
            Integer top = s.options == null || s.options.isEmpty() ? 3 : s.options.size();
            Integer value = raw.get(s.key);
            // Same drop-not-clamp rule the readiness scorer uses, for the same
            // reason: an out-of-range answer is not an answer.
            if (value == null || value < 1 || value > top) {
                continue;
            }
            out.answers.put(s.key, value);

            String indexKey = String.isBlank(s.indexKey) ? s.setKey : s.indexKey;
            IndexResult idx = out.indexes.get(indexKey);
            if (idx == null) {
                idx = new IndexResult();
                idx.indexKey = indexKey;
                idx.total    = 0;
                idx.minimum  = 0;
                idx.maximum  = 0;
                idx.answered = 0;
                out.indexes.put(indexKey, idx);
            }
            idx.total    += value;
            idx.minimum  += 1;
            idx.maximum  += top;
            idx.answered += 1;

            if (s.horizonDriver == true && s.horizonByValue != null) {
                String horizon = s.horizonByValue.get(String.valueOf(value));
                if (String.isNotBlank(horizon)) {
                    out.horizon = horizon;
                }
            }
        }

        if (out.answers.isEmpty() && out.notes.isEmpty()) {
            return out;
        }
        Map<String, Object> payload = new Map<String, Object>{
            'index'   => out.indexes,
            'answers' => out.answers,
            'notes'   => out.notes
        };
        out.json = JSON.serialize(payload);
        return out;
    }

    // ------------------------------------------------------------ predicates

    /**
     * Gate predicates are evaluated by GtmPredicate, which is also what
     * answer-driven branching uses. The evaluator used to live here; it moved
     * out when Show_When_JSON__c needed the same grammar, because the one thing
     * worse than a small language is two of them that drift.
     *
     * Kept as a wrapper rather than deleted so the existing tests still name
     * the behaviour at the level it matters -- "this gate fires on these
     * answers" -- rather than at the level of the evaluator.
     */
    @TestVisible
    private static Boolean matches(Object node, Map<String, Object> context) {
        return GtmPredicate.matches(node, context);
    }
}
