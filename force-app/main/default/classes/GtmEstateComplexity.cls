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
    public static Complexity score(Map<String, Integer> rawAnswers) {
        return score(rawAnswers, null);
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
    public static Complexity score(Map<String, Integer> rawAnswers, List<String> dimensionKeys) {
        Complexity out = new Complexity();
        if (rawAnswers == null || rawAnswers.isEmpty()) {
            return out;
        }
        List<String> dimensions = acceptedDimensions(dimensionKeys);

        Integer total = 0;
        for (String dimension : dimensions) {
            if (!rawAnswers.containsKey(dimension)) {
                continue;
            }
            Integer value = accepted(rawAnswers.get(dimension));
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
        out.band                 = bandFor(total);
        out.dimensionScoresJson  = JSON.serialize(out.dimensionScores);
        return out;
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
    @TestVisible
    private static List<String> acceptedDimensions(List<String> supplied) {
        if (supplied == null || supplied.size() != DIMENSIONS.size()) {
            return DIMENSIONS;
        }
        Set<String> seen = new Set<String>();
        for (String key : supplied) {
            if (String.isBlank(key) || !seen.add(key)) {
                return DIMENSIONS;
            }
        }
        return supplied;
    }

    /** The band for a total. Public so the readout reads it from here. */
    public static String bandFor(Decimal total) {
        if (total == null) {
            return null;
        }
        if (total <= LIGHT_MAX) {
            return BAND_LIGHT;
        }
        if (total <= MODERATE_MAX) {
            return BAND_MODERATE;
        }
        return BAND_HEAVY;
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

    private static Integer accepted(Integer value) {
        if (value == null || value < MIN_ANSWER_VALUE || value > MAX_ANSWER_VALUE) {
            return null;
        }
        return value;
    }
}
