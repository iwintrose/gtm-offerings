/**
 * The second axis of the readout: how BIG the job is, kept deliberately apart
 * from how READY the client is.
 *
 * GtmAssessmentScoring answers "can this be scoped and sold?" (8-32, high =
 * small/simple/low-risk). This class answers "how much work is in there?"
 * (6-18, high = heavy). They are reported side by side and never summed,
 * because a heavy estate means a BIGGER ENGAGEMENT, not a worse client --
 * blending them would turn the most valuable opportunities into the
 * lowest-scoring ones.
 *
 * Six dimensions scored 1-3, the band shape borrowed from the accelerator's own
 * complexity model (ma-migrator, skills/mce-mcn-helper/references/scoring-model.md)
 * so a pre-sales self-estimate and a post-scan measurement land on the same
 * scale and can be compared directly. Which of the two a stored number is
 * lives on GTM_Assessment_Request__c.Estate_Complexity_Basis__c: pre-scan it is
 * the prospect's own estimate collected in the questionnaire, post-scan it is
 * recomputed from an actual extract. Same maths, different evidence.
 *
 * Same shape and same trust rules as GtmAssessmentScoring -- pure computation,
 * unknown keys unreadable, out-of-range answers dropped rather than clamped --
 * because it is fed from the same guest-reachable submit endpoint.
 *
 * As there, the keys are code (the allowlist) and every human-readable string
 * is metadata (GTM_Assessment_Question__mdt, Instrument__c = 'Complexity').
 */
public with sharing class GtmEstateComplexity {

    /**
     * The six complexity dimensions, in questionnaire order.
     *
     * THE ALLOWLIST, and the fallback. A pair may now REWORD or RECALIBRATE any
     * of these, and may in principle substitute one for a differently-keyed
     * question in the same position (GtmAssessmentInstrument.ComplexityDimension)
     * -- so the keys a given respondent was actually asked come from the
     * resolved pack, not from here. This list stays the definition of how many
     * there are and what they are called when nothing adapts them, and it is
     * what score() falls back to when no pack is supplied.
     */
    /**
     * PER-OFFERING SINCE ADR-0007: this list, the scale below it and the band
     * edges below that are MIGRATION ACCELERATOR's complexity frame, and the
     * fallback for any offering with no GTM_Assessment_Frame__mdt record of its
     * own. An offering with one is scored against its Complexity_* fields and
     * against whatever dimension count its own pack resolves to. Every trust
     * property in the header survives either way -- the maximum is still
     * DERIVED from the list that actually scored, never typed.
     */
    public static final List<String> DIMENSIONS = new List<String>{
        'journey_footprint',
        'data_extension_complexity',
        'scripting_depth',
        'business_unit_structure',
        'integration_surface',
        'consent_suppression_model'
    };

    public static final Integer MIN_ANSWER_VALUE = 1;
    public static final Integer MAX_ANSWER_VALUE = 3;

    /** 6 dimensions x 3 points = 18, derived so the two cannot drift apart. */
    public static final Integer MAX_TOTAL_SCORE = DIMENSIONS.size() * MAX_ANSWER_VALUE;
    public static final Integer MIN_TOTAL_SCORE = DIMENSIONS.size() * MIN_ANSWER_VALUE;

    public static final String BAND_LIGHT    = 'Light';
    public static final String BAND_MODERATE = 'Moderate';
    public static final String BAND_HEAVY    = 'Heavy';

    /** Every value Estate_Complexity_Band__c accepts, ascending. */
    public static final List<String> BANDS = new List<String>{
        BAND_LIGHT, BAND_MODERATE, BAND_HEAVY
    };

    //      6-9   Light      Greenfield adoption is realistic.
    //    10-13   Moderate   Bridge strategy; pilot while the old stack runs.
    //    14-18   Heavy      Multi-year convergence; parallel run essential.
    private static final Integer LIGHT_MAX    = 9;
    private static final Integer MODERATE_MAX = 13;

    /** Basis values, matching the Estate_Complexity_Basis__c picklist. */
    public static final String BASIS_SELF_ESTIMATED = 'Self-Estimated';
    public static final String BASIS_MEASURED       = 'Measured';

    // ---------------------------------------------------------------- types

    public class Complexity {
        public Decimal total;
        public String band;
        public Map<String, Integer> dimensionScores;
        public String dimensionScoresJson;
        public Boolean hasAnswers;

        public Complexity() {
            this.dimensionScores = new Map<String, Integer>();
            this.hasAnswers      = false;
        }
    }

    // --------------------------------------------------------------- scoring

    /**
     * Scores a raw dimension -> answer map. Never throws; an empty or hostile
     * payload produces an unscored result, which persists as nulls rather than
     * as a zero -- "complexity not estimated" and "complexity estimated as
     * light" are different claims and the readout says them differently.
     */
    public static Complexity score(String offeringKey, Map<String, Integer> rawAnswers) {
        return score(offeringKey, rawAnswers, null);
    }

    /**
     * Scores against the dimensions a PACK resolved, rather than against the
     * unadapted six.
     *
     * This is GtmAssessmentScoring's shape, deliberately: the scorer reads an
     * allowlist it was handed, and an answer submitted under a key that is not
     * on it is never read. Which keys are on it is a resolution decision made
     * before the first question was asked, and re-made on the server from the
     * submitted answers, so a client that rendered a different set of questions
     * -- through tampering or a stale cached pack -- submits answers nothing
     * looks for.
     *
     * EVERY INVARIANT THIS CLASS HAD IS STILL HERE, and none of them is
     * conditional on the list being the default one:
     *
     *   - six dimensions x 1-3, with the maximum DERIVED from the list's own
     *     size rather than typed, so the two cannot drift apart;
     *   - out-of-range answers DROPPED rather than clamped, because a clamped
     *     answer is an invented one;
     *   - a key the resolved list does not contain is never read at all;
     *   - no SOQL and no DML: a resolved list arrives as an argument.
     *
     * A supplied list of the wrong LENGTH is refused outright rather than
     * scored, because a total out of 15 or 21 printed as "out of 18" is worse
     * than no total: GTM_Assessment_Request__c stores the number and the band
     * next to a basis that claims they are comparable with a post-scan
     * measurement, and they would not be.
     */
    public static Complexity score(
        String offeringKey, Map<String, Integer> rawAnswers, List<String> dimensionKeys
    ) {
        Complexity out = new Complexity();
        if (rawAnswers == null || rawAnswers.isEmpty()) {
            return out;
        }
        ResolvedFrame frame = frameFor(offeringKey);
        List<String> dimensions = acceptedDimensions(dimensionKeys, frame);

        Integer total = 0;
        for (String dimension : dimensions) {
            if (!rawAnswers.containsKey(dimension)) {
                continue;
            }
            Integer value = accepted(rawAnswers.get(dimension), frame);
            if (value == null) {
                continue;
            }
            out.dimensionScores.put(dimension, value);
            total += value;
        }

        if (out.dimensionScores.isEmpty()) {
            return out;
        }
        out.hasAnswers           = true;
        out.total                = total;
        out.band                 = GtmAssessmentFrames.tierFor(frame.bands, total);
        out.dimensionScoresJson  = JSON.serialize(out.dimensionScores);
        return out;
    }

    // ----------------------------------------------------------- the frame

    /**
     * One call's complexity frame: the answer scale, the bands, and whether
     * either came from an offering's own GTM_Assessment_Frame__mdt record or
     * from the compiled Migration Accelerator constants above.
     *
     * Same shape and same reasoning as GtmAssessmentScoring.ResolvedFrame,
     * reading the Complexity_* half of the same record. The two are separate
     * structs rather than one shared type for the same reason
     * ComplexityDimension is not a Slot: this axis is worth 1-3, carries no
     * ceiling and never branches, and a shared struct would hand every reader
     * of it fields that do not apply here.
     *
     * A blank Complexity_Min/Max on an offering's record means that offering
     * has NO complexity axis at all -- there is then nothing offering-specific
     * to read, and the compiled fallback is what a caller who scores complexity
     * anyway gets, rather than a half-configured scale.
     */
    private class ResolvedFrame {
        Integer minAnswer;
        Integer maxAnswer;
        List<GtmAssessmentScoring.Band> bands;
        Boolean fromRecord;
        /**
         * Whether the compiled DIMENSION list may be borrowed as a fallback.
         * True only for migration-accelerator and for a blank key. Separate
         * from fromRecord for the reason spelled out on the readiness axis:
         * the scale and bands are neutral numbers an offering may borrow, the
         * six dimension keys are Migration Accelerator's content and it may
         * not. See GtmAssessmentScoring.ResolvedFrame.compiledApplies.
         */
        Boolean compiledApplies;
    }

    private static ResolvedFrame frameFor(String offeringKey) {
        ResolvedFrame rf = new ResolvedFrame();
        rf.minAnswer  = MIN_ANSWER_VALUE;
        rf.maxAnswer  = MAX_ANSWER_VALUE;
        rf.bands      = migrationAcceleratorBands();
        rf.fromRecord = false;
        rf.compiledApplies = String.isBlank(offeringKey)
            || GtmAssessmentFrames.MIGRATION_ACCELERATOR.equalsIgnoreCase(offeringKey.trim());

        GTM_Assessment_Frame__mdt row = GtmAssessmentFrames.frameFor(offeringKey);
        if (row == null) {
            return rf;
        }
        Integer minValue = intOf(row.Complexity_Min_Answer_Value__c);
        Integer maxValue = intOf(row.Complexity_Max_Answer_Value__c);
        if (minValue != null && maxValue != null && minValue >= 1 && maxValue > minValue) {
            rf.minAnswer  = minValue;
            rf.maxAnswer  = maxValue;
            rf.fromRecord = true;
        }
        List<GtmAssessmentScoring.Band> authored =
            GtmAssessmentFrames.parseBands(row.Complexity_Bands_JSON__c);
        if (authored != null) {
            rf.bands      = authored;
            rf.fromRecord = true;
        }
        return rf;
    }

    private static Integer intOf(Decimal value) {
        return value == null ? null : value.intValue();
    }

    /** Migration Accelerator's Light / Moderate / Heavy edges, as bands. */
    private static List<GtmAssessmentScoring.Band> migrationAcceleratorBands() {
        return new List<GtmAssessmentScoring.Band>{
            new GtmAssessmentScoring.Band(BAND_LIGHT,    MIN_TOTAL_SCORE,  LIGHT_MAX),
            new GtmAssessmentScoring.Band(BAND_MODERATE, LIGHT_MAX + 1,    MODERATE_MAX),
            new GtmAssessmentScoring.Band(BAND_HEAVY,    MODERATE_MAX + 1, MAX_TOTAL_SCORE)
        };
    }

    /**
     * The dimension list to score against: the resolved one when it is the
     * right shape, else the default six.
     *
     * "The right shape" is exactly two things -- the frame's own count, and no
     * duplicates. A resolved list with a repeated key would read one submitted
     * answer twice and total more than 18 out of 18, which is the second-axis
     * form of the two-slots-one-key fault the readiness build check exists to
     * catch. Falling back rather than throwing keeps the guest submit path
     * whole: a half-deployed pack should cost the adapted WORDING, not the
     * score.
     */
    /**
     * Test seam. ResolvedFrame is a private inner type a test cannot build, so
     * the offering key -- which is what a caller actually has -- is the handle
     * tests get, and the frame is resolved here exactly as score() resolves it.
     */
    @TestVisible
    private static List<String> acceptedDimensions(String offeringKey, List<String> supplied) {
        return acceptedDimensions(supplied, frameFor(offeringKey));
    }

    private static List<String> acceptedDimensions(List<String> supplied, ResolvedFrame frame) {
        if (supplied == null || supplied.isEmpty()) {
            return frame.compiledApplies ? DIMENSIONS : new List<String>();
        }
        // The count check is Migration Accelerator's frame asserting itself, so
        // it applies only when Migration Accelerator's frame is the one in use.
        // An offering with its own frame record has its own dimension count,
        // and holding it to six would be this codebase overruling an authored
        // instrument. The no-blanks / no-duplicates half applies always: a
        // repeated key reads one submitted answer twice, whatever the frame.
        if (!frame.fromRecord && frame.compiledApplies
                && supplied.size() != DIMENSIONS.size()) {
            return DIMENSIONS;
        }
        Set<String> seen = new Set<String>();
        for (String key : supplied) {
            if (String.isBlank(key) || !seen.add(key)) {
                return frame.compiledApplies ? DIMENSIONS : new List<String>();
            }
        }
        return supplied;
    }

    /**
     * What a fully-answered complexity submission for ONE OFFERING is measured
     * out of, or NULL when that offering has no complexity axis at all.
     *
     * The complexity-axis twin of GtmAssessmentScoring.maxTotalFor(), and gated
     * the same way for the same reason: the compiled 18 is Migration
     * Accelerator's denominator. An offering with no instrument is measured
     * against nothing, so it is measured out of nothing -- printing "out of 18"
     * next to a null score borrows somebody else's six dimensions to describe a
     * submission that answered none of them.
     *
     * Exists because a caller may have an offering key and no pack -- the guest
     * questionnaire endpoint needs the maximum BEFORE any answer is given, and
     * score() only ever exposed the maximum implicitly, through its bands.
     */
    public static Integer maxTotalFor(String offeringKey) {
        ResolvedFrame frame = frameFor(offeringKey);
        List<String> dims = acceptedDimensions((List<String>) null, frame);
        if (frame.fromRecord) {
            return dims.size() * frame.maxAnswer;
        }
        return frame.compiledApplies ? MAX_TOTAL_SCORE : null;
    }

    /** The band for a total against ONE OFFERING's complexity edges. */
    public static String bandFor(String offeringKey, Decimal total) {
        return GtmAssessmentFrames.tierFor(frameFor(offeringKey).bands, total);
    }

    /**
     * Migration Accelerator's banding, for a caller with no offering in hand.
     * The same deliberate, named default as GtmAssessmentScoring's zero-arg
     * bands()/tierFor(): the readout-rendering callers were left un-threaded on
     * purpose (ADR-0007's plan scopes them out), and every readout that exists
     * today is Migration Accelerator's. Named here so the assumption is
     * greppable rather than implicit.
     */
    public static String bandFor(Decimal total) {
        return GtmAssessmentFrames.tierFor(migrationAcceleratorBands(), total);
    }

    /**
     * The basis if it is one of the two we recognise, else null. A basis we
     * cannot vouch for is worse than none: it would let a self-estimate be
     * presented as a measurement.
     */
    public static String acceptedBasis(String basis) {
        if (String.isBlank(basis)) {
            return null;
        }
        String trimmed = basis.trim();
        if (BASIS_SELF_ESTIMATED.equalsIgnoreCase(trimmed)) {
            return BASIS_SELF_ESTIMATED;
        }
        if (BASIS_MEASURED.equalsIgnoreCase(trimmed)) {
            return BASIS_MEASURED;
        }
        return null;
    }

    private static Integer accepted(Integer value, ResolvedFrame frame) {
        if (value == null || value < frame.minAnswer || value > frame.maxAnswer) {
            return null;
        }
        return value;
    }
}
