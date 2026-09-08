/**
 * The single source of truth for migration-readiness scoring.
 *
 * Scoring used to happen in the browser: the questionnaire computed
 * `assessmentScore` / `assessmentTier` and GtmAssessmentRequestController stored
 * whatever arrived, verbatim. That made the score a *prospect-supplied* value —
 * anyone who could reach the guest submit endpoint could name their own
 * tier, and that tier is what drives the readout a rep then sends
 * them. This class exists so the stored score is derived from the raw answers
 * on the server and nowhere else.
 *
 * Pure computation: no SOQL, no DML, no callouts. It is called from a
 * `without sharing`, guest-reachable path, so it deliberately reads nothing and
 * writes nothing — the only thing it touches is the argument it was handed.
 * Everything it needs to know about the outside world (which source/target
 * pairs the accelerator can process) arrives as a PairEligibility argument,
 * resolved by GtmMigrationPairs, so the class that decides the tier stays
 * deterministic and unit-testable without any org data.
 *
 * WHAT THE SCORE MEANS — this instrument is not a marketing-maturity survey and
 * must not be read as one. Every dimension is scored so that **4 is the lowest
 * migration risk**. A high total therefore describes a *small, simple,
 * well-owned, portable* estate — not a sophisticated marketing operation. A
 * large, sophisticated, heavily-customised estate scores LOW here, and that is
 * the correct reading: it is harder to migrate. How big the resulting
 * engagement is belongs to the *other* axis (GtmEstateComplexity), which is
 * deliberately never added into this total.
 *
 * The trust rules it enforces, all of them because the input is untrusted:
 *   - only the eight dimensions in DIMENSIONS are read; a client that invents
 *     extra keys cannot add to the total, because unknown keys are never looked
 *     at rather than filtered out afterwards;
 *   - an answer outside MIN_ANSWER_VALUE..MAX_ANSWER_VALUE is dropped, not
 *     clamped. Clamping a submitted 0 up to 1, or a submitted 999 down to 4,
 *     both invent an answer the prospect did not give; treating it as
 *     unanswered is the only reading that adds nothing;
 *   - a Map is the input shape, so a duplicated dimension collapses to one
 *     entry instead of being counted repeatedly.
 *
 * ADAPTIVE, WITHOUT LOSING THE ALLOWLIST — the eight keys the scorer reads are
 * now RESOLVED from a GtmAssessmentInstrument.Pack rather than always being the
 * literal below, because a pair may substitute one slot for another that
 * carries the same risk in a different form. What did NOT change is the
 * property that matters: the resolved list is still an allowlist, still
 * exactly eight, and still iterated instead of the caller's keySet, so a key
 * we did not ask for is never read. What a pack can do is swap which eight
 * questions are asked; what nothing can do is make a ninth answer count, or
 * make the total anything other than out of 32. A malformed or short pack
 * falls back to the literal.
 *
 * TWO MORE THINGS AN AUTHOR CAN NOW SET, AND THE ONE THING THEY STILL CANNOT.
 * A content author sets what each option is WORTH (Option.points) and, through
 * Show_When_JSON__c, WHICH of several authored questions fills a slot for a
 * given respondent. Neither can change the shape of the result:
 *
 *   - branches SUBSTITUTE, they never remove. A slot resolves to exactly one
 *     asked question on every path, so eight slots are always answered. The
 *     enforcement is structural, in GtmAssessmentInstrument.buildVariants: a
 *     variant is a copy of the default with the variant's row merged over it,
 *     so there is no code path that yields a slot with no question;
 *   - points may make a scale NON-LINEAR but never LONGER or SHORTER. The
 *     maximum is derived from the authored points (Pack.maxTotal()), and if it
 *     comes to anything other than MAX_TOTAL_SCORE the authored points are
 *     refused wholesale and the identity scale is used -- see
 *     pointsAreTrustworthy(). The band edges were calibrated against 32; an
 *     instrument scored out of 31 wearing the same bands is not a smaller
 *     instrument, it is an incomparable one.
 *
 * Only supplements are genuinely additive, and they score into their own named
 * index in GtmAssessmentReadout, never into the 32.
 *
 * THE FRAME IS PER-OFFERING NOW, AND THE CONSTANTS BELOW ARE MIGRATION
 * ACCELERATOR'S. Everything from DIMENSIONS down to the band edges used to be
 * "the frame"; since ADR-0007 it is "the migration-accelerator fallback frame".
 * score() takes an offeringKey, reads that offering's GTM_Assessment_Frame__mdt
 * through GtmAssessmentFrames, and falls back to these constants whenever no
 * such record exists — which is every migration-accelerator submission, by
 * design, so the fallback is the well-trodden path rather than an error branch.
 * What did NOT change is any trust property above: the resolved keys are still
 * an allowlist, still iterated rather than read from the caller's keySet, and a
 * total is still measured against a maximum derived rather than typed. What
 * changed is that WHICH maximum, and which band edges, are now a property of
 * the offering being assessed instead of a property of the codebase.
 *
 * WHERE THE WORDING LIVES — the dimension *keys* below are the base allowlist,
 * and they are code on purpose: a consultant editing a picklist
 * label must never be able to change what a guest-reachable endpoint will
 * score. Every human-readable string that goes with them (dimension name, the
 * question, the four ascending answer options) lives in
 * GTM_Assessment_Question__mdt and is read by GtmAssessmentQuestions. Rewording a
 * question is a metadata edit; adding a dimension is a code change. That split
 * is the point, not an oversight.
 */
public with sharing class GtmAssessmentScoring {

    /**
     * The eight scored dimensions, in questionnaire order. EIGHT, not ten: the
     * maximum total is DIMENSIONS.size() * MAX_ANSWER_VALUE = 32, and any code,
     * template or test that assumes a 40-point maximum is wrong.
     *
     * These keys are the agreed instrument, not a proposal — the earlier
     * `data_foundation` / `segmentation` / `ai_personalization` set was
     * inherited from a Salesforce marketing-maturity survey and measured the
     * wrong thing entirely.
     */
    /**
     * MIGRATION ACCELERATOR's base eight, and the fallback whenever a resolved
     * pack is missing, short, or malformed. A pair pack may substitute a slot
     * (see GtmAssessmentInstrument), which changes WHICH eight keys are scored
     * but never how many.
     *
     * Not "the" eight any more: an offering with its own
     * GTM_Assessment_Frame__mdt record scores against whatever its own pack
     * resolves to, in whatever count that offering authored. This list is what
     * an offering with no frame record of its own falls back to.
     */
    public static final List<String> DIMENSIONS = new List<String>{
        'estate_scale',
        'source_access',
        'orchestration_portability',
        'content_portability',
        'data_model_readiness',
        'integration_containment',
        'consent_portability',
        'decision_readiness'
    };

    /** The dimensions the override rules below key on, named once. */
    public static final String DIM_SOURCE_ACCESS   = 'source_access';
    public static final String DIM_ORCHESTRATION   = 'orchestration_portability';
    public static final String DIM_CONTENT         = 'content_portability';

    /**
     * Lowest and highest value one scored answer may contribute — Migration
     * Accelerator's scale, and the fallback for any offering with no
     * GTM_Assessment_Frame__mdt record. An offering with one uses its own
     * Min_Answer_Value__c / Max_Answer_Value__c instead.
     */
    public static final Integer MIN_ANSWER_VALUE = 1;
    public static final Integer MAX_ANSWER_VALUE = 4;

    /**
     * 8 dimensions x 4 points = 32. Derived rather than typed, so the two can
     * never drift apart, and exposed so the readout template can print
     * "18 out of 32" from the same constant instead of hard-coding a maximum.
     */
    public static final Integer MAX_TOTAL_SCORE = DIMENSIONS.size() * MAX_ANSWER_VALUE;

    /** The lowest total a fully-answered questionnaire can produce. */
    public static final Integer MIN_TOTAL_SCORE = DIMENSIONS.size() * MIN_ANSWER_VALUE;

    // ----------------------------------------------------------------- tiers
    //
    // The four bands say what to SELL, which is the only reason the tier
    // exists. They replaced Foundational / Developing / Advanced / AI-Ready,
    // which came from a marketing-maturity survey and were actively wrong here:
    // "AI-Ready" as the output of a migration-feasibility questionnaire is a
    // claim the offering cannot stand behind, and the whole set inverted the
    // meaning of the score.
    //
    //     8-14   Discovery First     Cannot responsibly scope yet — access,
    //                                documentation or estate knowledge is
    //                                missing. Sell discovery, not migration.
    //    15-20   Prep Required       Migratable with named prerequisites before
    //                                build: credentials, rationalisation,
    //                                decision owners, a form/consent audit.
    //    21-26   Accelerator-Ready   Estate is knowable and largely portable.
    //                                Standard engagement path.
    //    27-32   Fast-Track          Small, clean, well-owned estate.
    //                                Compressed engagement; fixed-scope
    //                                candidate.
    //
    // The band edges matter less than the two override rules below them: a
    // boundary being one point out changes which of two adjacent stories a rep
    // tells, whereas an override firing or not changes whether the offering is
    // sellable at all.
    //
    public static final String TIER_DISCOVERY_FIRST   = 'Discovery First';
    public static final String TIER_PREP_REQUIRED     = 'Prep Required';
    public static final String TIER_ACCELERATOR_READY = 'Accelerator-Ready';
    public static final String TIER_FAST_TRACK        = 'Fast-Track';

    /** Every value Assessment_Tier__c accepts, in ascending band order. */
    public static final List<String> TIERS = new List<String>{
        TIER_DISCOVERY_FIRST,
        TIER_PREP_REQUIRED,
        TIER_ACCELERATOR_READY,
        TIER_FAST_TRACK
    };

    private static final Integer DISCOVERY_FIRST_MAX   = 14;
    private static final Integer PREP_REQUIRED_MAX     = 20;
    private static final Integer ACCELERATOR_READY_MAX = 26;

    /** One band, as a range. */
    public class Band {
        @AuraEnabled public String tier;
        @AuraEnabled public Integer lowest;
        @AuraEnabled public Integer highest;

        public Band(String tier, Integer lowest, Integer highest) {
            this.tier    = tier;
            this.lowest  = lowest;
            this.highest = highest;
        }
    }

    /**
     * The four bands with their edges, so the authoring preview can show which
     * band a set of answers lands in WITHOUT the client holding its own copy of
     * 14/20/26. A band edge duplicated into a component is a band edge that will
     * eventually disagree with the one that scores, and the disagreement would
     * surface as an author confidently publishing a question they had previewed
     * against the wrong scale.
     */
    public static List<Band> bands(String offeringKey) {
        GTM_Assessment_Frame__mdt f = GtmAssessmentFrames.frameFor(offeringKey);
        List<Band> authored = f == null
            ? null
            : GtmAssessmentFrames.parseBands(f.Bands_JSON__c);
        return authored == null ? migrationAcceleratorBands() : authored;
    }

    /**
     * Migration Accelerator's bands, for a caller with no offering in hand.
     *
     * Kept, rather than removed with the rest of the singleton, for the display
     * callers ADR-0007's plan deliberately left un-threaded: GtmReadoutModel
     * renders a band LADDER beside a stored score, and threading an offering
     * key through the whole readout-rendering stack is a separate change with
     * its own blast radius. Those callers show Migration Accelerator's ladder
     * because every readout that exists today is Migration Accelerator's. This
     * overload is where that assumption is written down, so it is one named,
     * greppable place rather than an unstated default — and so a second
     * offering's first readout has an obvious thing to fix.
     */
    public static List<Band> bands() {
        return migrationAcceleratorBands();
    }

    private static List<Band> migrationAcceleratorBands() {
        return new List<Band>{
            new Band(TIER_DISCOVERY_FIRST,   MIN_TOTAL_SCORE,             DISCOVERY_FIRST_MAX),
            new Band(TIER_PREP_REQUIRED,     DISCOVERY_FIRST_MAX + 1,     PREP_REQUIRED_MAX),
            new Band(TIER_ACCELERATOR_READY, PREP_REQUIRED_MAX + 1,       ACCELERATOR_READY_MAX),
            new Band(TIER_FAST_TRACK,        ACCELERATOR_READY_MAX + 1,   MAX_TOTAL_SCORE)
        };
    }

    // ----------------------------------------------------------- annotations

    /**
     * Non-blocking annotation code: both orchestration and content scored at
     * the floor, so most of the estate has to be rebuilt rather than moved —
     * true even when the headline total is high, which is exactly why it is
     * said out loud rather than folded into the number.
     */
    public static final String FLAG_HIGH_REBUILD_RATIO = 'high_rebuild_ratio';

    private static final String HIGH_REBUILD_RATIO_MESSAGE =
        'High rebuild ratio — expect automation levels C/D to dominate.';

    // ---------------------------------------------------------------- types

    /**
     * Whether the accelerator can process the source/target pair the routing
     * question selected. A plain value object with no behaviour, defined here
     * rather than on GtmMigrationPairs so this class keeps zero dependencies on
     * anything that touches the database: the resolver depends on the scorer,
     * never the other way round.
     *
     * `evaluated` false means nothing was resolved (no pair supplied, or the
     * org has no pair metadata deployed at all) and the gate stays inert. That
     * is the honest default: suppressing every tier because a config table is
     * empty would break the instrument rather than protect anyone.
     */
    public class PairEligibility {
        public Boolean evaluated;
        public Boolean supported;
        public String reason;

        public PairEligibility() {
            this.evaluated = false;
            this.supported = true;
        }

        public PairEligibility(Boolean supported, String reason) {
            this.evaluated = true;
            this.supported = supported;
            this.reason = reason;
        }
    }

    /** One non-blocking observation about the answers. */
    public class Annotation {
        public String code;
        public String message;

        public Annotation(String code, String message) {
            this.code = code;
            this.message = message;
        }
    }

    /**
     * The computed result. `total`, `tier` and `sectionScoresJson` are all null
     * when nothing scorable was submitted, which is the case every unscored
     * submission takes -- an older client, or a booking form with no
     * questionnaire attached. Callers persist the nulls rather than
     * substituting a zero, because "not assessed" and "assessed at the floor"
     * are different things and the readout renders them differently.
     *
     * `tier` is also null when `advisory` is true -- see the unsupported-pair
     * gate in score(). A null tier with a non-null total is the shape that says
     * "scored, but deliberately not banded".
     */
    public class Score {
        public Decimal total;
        public String tier;
        public Map<String, Integer> sectionScores;
        public String sectionScoresJson;
        public Boolean hasAnswers;
        /** True when the tier was suppressed because the pair is unsupported. */
        public Boolean advisory;
        /** One line saying why, for Advisory_Reason__c. Null unless advisory. */
        public String advisoryReason;
        /** True when the access gate pulled the tier down to Discovery First. */
        public Boolean cappedByAccessGate;
        public List<Annotation> annotations;
        /** JSON for Assessment_Flags__c; null when there are no annotations. */
        public String annotationsJson;
        /**
         * DeveloperName of the pack that decided which eight questions these
         * answers were given to, and its version. Stored on the request record,
         * because a breakdown whose keys nobody can look up any more is not a
         * breakdown -- see GTM_Assessment_Request__c.Instrument_Pair__c.
         */
        public String instrumentPairKey;
        public String instrumentVersion;
        /** The eight keys actually scored, in questionnaire order. */
        public List<String> dimensionKeys;
        /**
         * The raw option each slot was answered with (1-4), as distinct from
         * what that option was WORTH. Identical to sectionScores until a content
         * author sets non-linear points, and it is this map -- not the points --
         * that gates and branch predicates are evaluated against: an author
         * writes about the answer their respondent can see on the screen, not
         * about a weighting they may retune next week.
         */
        public Map<String, Integer> answerValues;
        /**
         * What this submission was scored OUT OF, summed from the authored
         * points of the slots actually presented rather than typed. Always
         * MAX_TOTAL_SCORE in a healthy instrument -- see maxTotalFor() for what
         * happens when it is not. Persisted, because points are editable and a
         * stored total needs the maximum it was measured against to stay
         * readable a year later.
         */
        public Integer maxTotal;
        /** base slot key -> the authored variant that filled it. */
        public Map<String, String> branchPath;
        public String branchPathJson;

        public Score() {
            this.sectionScores      = new Map<String, Integer>();
            this.answerValues       = new Map<String, Integer>();
            this.hasAnswers         = false;
            this.advisory           = false;
            this.cappedByAccessGate = false;
            this.annotations        = new List<Annotation>();
            this.dimensionKeys      = new List<String>();
            this.maxTotal           = MAX_TOTAL_SCORE;
            this.branchPath         = new Map<String, String>();
        }
    }

    // ----------------------------------------------------------- the frame

    /**
     * The frame ONE call to score() is measured against: the answer scale, the
     * bands, and whether either came from an offering's own
     * GTM_Assessment_Frame__mdt record or from the compiled Migration
     * Accelerator constants.
     *
     * Resolved ONCE per score() call and passed down, rather than each helper
     * re-reading it. Two helpers that resolved the frame independently could,
     * in principle, disagree — and a submission scored against one scale and
     * banded against another is the exact failure mode this whole class is
     * built to make impossible.
     */
    private class ResolvedFrame {
        Integer minAnswer;
        Integer maxAnswer;
        List<Band> bands;
        /**
         * True when a real frame record drove this. It is what decides whether
         * the slot COUNT is also the offering's own business: with no record,
         * the "exactly DIMENSIONS.size() slots or fall back to the literal"
         * rule stays exactly as it was, because that rule is Migration
         * Accelerator's frame asserting itself. With a record, the offering's
         * own pack defines how many slots it has, and asserting 8 would be this
         * codebase overruling the offering's authored instrument.
         */
        Boolean fromRecord;
        /**
         * Whether the COMPILED DIMENSION LIST may be used as a fallback for
         * this offering.
         *
         * True only for migration-accelerator itself, and for a blank key (the
         * display-path callers). It is deliberately a separate flag from
         * fromRecord: an offering can have no frame record -- so it borrows
         * this class's SCALE and BANDS, which are neutral numbers -- while
         * still having no business borrowing Migration Accelerator's eight
         * DIMENSION KEYS, which are content.
         *
         * Found by running the ADR-0007 isolation proof against real deployed
         * classes rather than by unit test: with an empty pack, resolvedDimensions
         * fell back to DIMENSIONS for EVERY offering, so a second offering with
         * no instrument deployed scored 32 out of 32 against Migration
         * Accelerator's allowlist. That is the exact cross-offering leak the
         * ADR exists to prevent, and it looked completely correct in a unit
         * test that supplied a well-formed pack.
         */
        Boolean compiledApplies;
    }

    private static ResolvedFrame frameFor(String offeringKey) {
        ResolvedFrame rf = new ResolvedFrame();
        rf.minAnswer  = MIN_ANSWER_VALUE;
        rf.maxAnswer  = MAX_ANSWER_VALUE;
        rf.bands      = migrationAcceleratorBands();
        rf.fromRecord = false;
        rf.compiledApplies =
            String.isBlank(offeringKey) || isMigrationAccelerator(offeringKey);

        GTM_Assessment_Frame__mdt row = GtmAssessmentFrames.frameFor(offeringKey);
        if (row == null) {
            return rf;
        }
        // Every field is taken only when it is usable. A record with a good
        // scale and unparseable bands keeps its scale and borrows Migration
        // Accelerator's bands, rather than being discarded whole — the same
        // per-field fail-open the instrument's own pack merge uses.
        Integer minValue = intOf(row.Min_Answer_Value__c);
        Integer maxValue = intOf(row.Max_Answer_Value__c);
        if (minValue != null && maxValue != null && minValue >= 1 && maxValue > minValue) {
            rf.minAnswer  = minValue;
            rf.maxAnswer  = maxValue;
            rf.fromRecord = true;
        }
        List<Band> authored = GtmAssessmentFrames.parseBands(row.Bands_JSON__c);
        if (authored != null) {
            rf.bands      = authored;
            rf.fromRecord = true;
        }
        return rf;
    }

    private static Integer intOf(Decimal value) {
        return value == null ? null : value.intValue();
    }

    // --------------------------------------------------------------- scoring

    /** Scores with no pair information — the gate stays inert. */
    public static Score score(String offeringKey, Map<String, Integer> rawAnswers) {
        return score(offeringKey, rawAnswers, null, null);
    }

    /** Scores against a resolved instrument pack, with no pair gate. */
    public static Score score(
        String offeringKey, Map<String, Integer> rawAnswers, GtmAssessmentInstrument.Pack pack
    ) {
        return score(offeringKey, rawAnswers, null, pack);
    }

    /**
     * Scores a raw dimension -> answer map. Never throws: a malformed or
     * hostile payload produces an unscored result, never a failed submission.
     *
     * Three things happen on top of the arithmetic, in this order, because the
     * order is the policy:
     *
     *   1. ANNOTATIONS are collected from the raw answers. They never change
     *      the number or the band; they are things a rep has to say out loud.
     *      Migration Accelerator only — see annotate().
     *
     *   2. The ACCESS GATE caps the tier at Discovery First when source_access
     *      scored at the floor. Without an extract there is no offering to run,
     *      so no total — however good — may promise otherwise. It caps rather
     *      than suppresses: Discovery First is a real, sellable recommendation.
     *      Migration Accelerator only, for the same reason as (1).
     *
     *   3. The UNSUPPORTED-PAIR GATE suppresses the tier entirely when the
     *      routing answer named a source or target the accelerator cannot
     *      process. Banding a migration-feasibility instrument for a pair the
     *      tool cannot handle is a false promise, so there is no band at all —
     *      the score and the breakdown survive as qualitative input for a
     *      manual conversation, and Advisory_Reason__c carries the why. The
     *      caller decides whether this even applies; every offering that is not
     *      a migration hands in a never-evaluated PairEligibility.
     */
    public static Score score(
        String offeringKey, Map<String, Integer> rawAnswers, PairEligibility pair
    ) {
        return score(offeringKey, rawAnswers, pair, null);
    }

    /**
     * The full form. `offeringKey` decides WHICH FRAME this is measured
     * against; `pack` supplies the resolved slot keys and any per-slot ceiling.
     * A null pack means the offering's base dimensions with no ceilings, which
     * is exactly what every caller got before the adaptive layer existed.
     *
     * A ceiling is enforced HERE, not only in the UI, and it DROPS rather than
     * clamps -- the same rule the class already applied to any out-of-range
     * value, for the same reason. A prospect who submits a top answer to a slot
     * capped below it is claiming an answer that was rendered visibly
     * unavailable to them; clamping it would invent an answer they did not
     * give, and accepting it would let a guest-reachable endpoint score past a
     * ceiling that exists because the capability does not.
     */
    public static Score score(
        String offeringKey,
        Map<String, Integer> rawAnswers,
        PairEligibility pair,
        GtmAssessmentInstrument.Pack pack
    ) {
        ResolvedFrame frame = frameFor(offeringKey);
        Score out = new Score();
        out.dimensionKeys = resolvedDimensions(pack, frame);
        // Whether the authored points are trusted at all is decided ONCE, here,
        // before a single answer is read -- see maxTotalFor().
        Boolean trustPoints = pointsAreTrustworthy(pack, frame);
        out.maxTotal = frameMaxTotal(out.dimensionKeys, frame);
        if (pack != null) {
            out.instrumentPairKey = pack.pairKey;
            out.instrumentVersion = pack.version;
            out.branchPath        = pack.branchPath();
            out.branchPathJson    = out.branchPath.isEmpty()
                ? null
                : JSON.serialize(out.branchPath);
        }
        if (rawAnswers == null || rawAnswers.isEmpty()) {
            applyPairGate(out, pair);
            return out;
        }

        Integer total = 0;
        // Iterating the RESOLVED dimensions (not the caller's keySet) is what
        // makes an invented dimension unscorable: a key we do not ask for is
        // never read.
        for (String dimension : out.dimensionKeys) {
            if (!rawAnswers.containsKey(dimension)) {
                continue;
            }
            Integer value = accepted(rawAnswers.get(dimension), ceilingFor(pack, dimension), frame);
            if (value == null) {
                continue;
            }
            // The option is what they chose; the points are what it is worth.
            // With no pack, or with points the instrument refused to trust, the
            // two are the same number and this is the arithmetic it always was.
            Integer points = trustPoints ? pointsFor(pack, dimension, value) : value;
            if (points == null) {
                // An answer the resolved pack has no option for is not an
                // answer to the question we asked. Dropped, for the same reason
                // an out-of-range value is dropped: inventing a worth for it
                // would be inventing an answer.
                continue;
            }
            out.answerValues.put(dimension, value);
            out.sectionScores.put(dimension, points);
            total += points;
        }

        if (out.sectionScores.isEmpty()) {
            applyPairGate(out, pair);
            return out;
        }
        out.hasAnswers        = true;
        out.total             = total;
        out.sectionScoresJson = JSON.serialize(out.sectionScores);

        annotate(out, pack, offeringKey, frame);

        out.tier = GtmAssessmentFrames.tierFor(frame.bands, total);
        // (2) Access gate. MIGRATION ACCELERATOR ONLY, and deliberately not
        // generalised: "no credentials to the source platform means you cannot
        // responsibly be sold a migration" is a business judgement about
        // migrations, not a framework rule, and an offering that is not a
        // migration has no source platform to have access to. An offering
        // wanting an equivalent already has the generic mechanism for it -- a
        // GTM_Assessment_Gate__mdt row with a Predicate_JSON__c, which was
        // built generic from the start for exactly this. See ADR-0007 6.
        //
        // Only an *accepted* answer at the floor counts -- a dropped
        // out-of-range value is unanswered, and an unanswered access question
        // is not evidence that access is missing. Keyed on the RESOLVED key for
        // the access slot, so a pair that rewords or recalibrates it (and every
        // pair may) still trips the gate.
        if (isMigrationAccelerator(offeringKey)) {
            String accessKey = resolvedKeyFor(pack, DIM_SOURCE_ACCESS);
            // Read against the ANSWER, not the points: "they picked the bottom
            // option on access" is the fact the gate is about, and it must not
            // stop being true because someone retuned what that option is worth.
            if (out.answerValues.get(accessKey) == frame.minAnswer) {
                out.cappedByAccessGate = true;
                out.tier = TIER_DISCOVERY_FIRST;
            }
        }

        applyPairGate(out, pair);
        return out;
    }

    /** Whether this offering is the one the compiled business rules belong to. */
    private static Boolean isMigrationAccelerator(String offeringKey) {
        return String.isNotBlank(offeringKey)
            && GtmAssessmentFrames.MIGRATION_ACCELERATOR.equalsIgnoreCase(offeringKey.trim());
    }

    /**
     * (3) The unsupported-pair gate. Applied last and unconditionally, so an
     * unsupported pair suppresses the tier no matter which path produced it --
     * including the unscored paths, where there was no tier to begin with and
     * the advisory flag is still the thing a rep needs to see.
     */
    private static void applyPairGate(Score out, PairEligibility pair) {
        if (pair == null || pair.evaluated != true || pair.supported == true) {
            return;
        }
        out.advisory       = true;
        out.tier           = null;
        out.advisoryReason = String.isBlank(pair.reason)
            ? 'The selected source/target combination is not one the accelerator can process. ' +
              'Treat this as an advisory conversation, not a scoped migration.'
            : pair.reason;
    }

    /**
     * (1) Non-blocking observations. Deliberately additive and deliberately
     * separate from the total: an annotation that moved the score would be
     * double-counting answers that already scored.
     *
     * MIGRATION ACCELERATOR ONLY. "Both orchestration and content at the floor
     * means most of the estate is rebuilt rather than moved" is genuine
     * Migration Accelerator business judgement about migrations, not generic
     * configuration, and it is keyed on three dimension names no other offering
     * is required to have. It is NOT promoted to data (ADR-0007 6): an
     * offering wanting its own "annotate without touching the number" writes a
     * GTM_Assessment_Gate__mdt row, which is the generic mechanism that already
     * exists for it.
     */
    private static void annotate(
        Score out, GtmAssessmentInstrument.Pack pack, String offeringKey, ResolvedFrame frame
    ) {
        if (isMigrationAccelerator(offeringKey)) {
            Integer orchestration = out.answerValues.get(resolvedKeyFor(pack, DIM_ORCHESTRATION));
            Integer content       = out.answerValues.get(resolvedKeyFor(pack, DIM_CONTENT));
            if (orchestration == frame.minAnswer && content == frame.minAnswer) {
                out.annotations.add(
                    new Annotation(FLAG_HIGH_REBUILD_RATIO, HIGH_REBUILD_RATIO_MESSAGE)
                );
            }
        }
        out.annotationsJson = out.annotations.isEmpty()
            ? null
            : JSON.serialize(out.annotations);
    }

    /**
     * The tier band for a total against ONE OFFERING's bands, before either
     * override. Public so the readout template and any future reporting read
     * the bands from here rather than re-deriving them -- but note that this is
     * the *band*, not necessarily the stored tier: score() may cap or suppress
     * it.
     */
    public static String tierFor(String offeringKey, Decimal total) {
        return GtmAssessmentFrames.tierFor(bands(offeringKey), total);
    }

    /**
     * Migration Accelerator's banding, for a caller with no offering in hand.
     * Same deliberate, named default as the zero-arg bands() above; see its
     * comment for which callers rely on it and why they were left un-threaded.
     */
    public static String tierFor(Decimal total) {
        return GtmAssessmentFrames.tierFor(migrationAcceleratorBands(), total);
    }

    /**
     * The answer if it is in range for this offering's scale, null if it is
     * not. Out of range is dropped rather than clamped -- see the class header
     * for why. `ceiling` is the slot's max_attainable for this pair, never
     * above the frame's own maximum.
     */
    private static Integer accepted(Integer value, Integer ceiling, ResolvedFrame frame) {
        Integer top = (ceiling == null || ceiling > frame.maxAnswer) ? frame.maxAnswer : ceiling;
        if (value == null || value < frame.minAnswer || value > top) {
            return null;
        }
        return value;
    }

    /**
     * The keys to score.
     *
     * With NO frame record (Migration Accelerator, and any offering yet to
     * author one) this is exactly the rule it always was: a pack that is
     * absent, or that does not resolve to exactly DIMENSIONS.size() distinct
     * keys, is not trusted and the base literal is used instead. A short pack
     * would otherwise produce a total out of 28 while the readout still printed
     * "out of 32", which is the failure mode that looks most like a correct
     * answer.
     *
     * WITH a frame record, the offering's own pack decides how many slots it
     * has. Holding it to eight would be this codebase overruling an authored
     * instrument -- the precise thing ADR-0007 exists to stop. The invariant
     * that survives either way is the one that matters: no blanks, no
     * duplicates, and a maximum derived from the same list that scored.
     */
    private static List<String> resolvedDimensions(
        GtmAssessmentInstrument.Pack pack, ResolvedFrame frame
    ) {
        if (pack == null || pack.slots == null || pack.slots.isEmpty()) {
            return untrustedPackFallback(frame);
        }
        if (!frame.fromRecord && frame.compiledApplies
                && pack.slots.size() != DIMENSIONS.size()) {
            return untrustedPackFallback(frame);
        }
        List<String> keys = new List<String>();
        Set<String> seen  = new Set<String>();
        for (GtmAssessmentInstrument.Slot slot : pack.slots) {
            if (String.isBlank(slot.key) || !seen.add(slot.key)) {
                return untrustedPackFallback(frame);
            }
            keys.add(slot.key);
        }
        return keys;
    }

    /**
     * What to score against when the pack cannot be trusted.
     *
     * For Migration Accelerator: its own compiled eight, exactly as before --
     * a half-deployed pack should cost the adapted wording, not the score.
     *
     * For ANY OTHER offering: NOTHING. An empty allowlist means no answer is
     * read and the submission scores to nulls, which is the same shape an
     * unscored submission has always produced and which the whole stack
     * already renders as "not assessed". Borrowing Migration Accelerator's
     * eight keys here would be worse than useless: it would produce a
     * confident 32-out-of-32 for an offering whose instrument does not exist,
     * against questions its respondent was never asked. "Not assessed" and
     * "assessed against somebody else's instrument" are very different claims,
     * and only one of them is true.
     */
    private static List<String> untrustedPackFallback(ResolvedFrame frame) {
        return frame.compiledApplies ? DIMENSIONS : new List<String>();
    }

    /** The key a base slot resolved to for this pack, or the base key itself. */
    private static String resolvedKeyFor(GtmAssessmentInstrument.Pack pack, String baseKey) {
        if (pack == null || pack.slots == null) {
            return baseKey;
        }
        for (GtmAssessmentInstrument.Slot slot : pack.slots) {
            if (baseKey.equals(slot.baseKey)) {
                return String.isBlank(slot.key) ? baseKey : slot.key;
            }
        }
        return baseKey;
    }

    /**
     * The points a slot's chosen option is worth, or null when the resolved
     * pack has no such option.
     */
    private static Integer pointsFor(
        GtmAssessmentInstrument.Pack pack, String key, Integer value
    ) {
        if (pack == null || pack.slots == null) {
            return value;
        }
        for (GtmAssessmentInstrument.Slot slot : pack.slots) {
            if (key.equals(slot.key)) {
                Integer p = slot.pointsForValue(value);
                // A slot with no authored options at all (no question metadata
                // deployed) still has to score, and identity is what it scored
                // with before points existed.
                return slot.options.isEmpty() ? value : p;
            }
        }
        return value;
    }

    /**
     * What a fully-answered submission against this frame is measured out of,
     * or NULL when this offering has no maximum to speak of.
     *
     * Gated on compiledApplies as well as fromRecord, for exactly the reason
     * untrustedPackFallback() above is: the compiled 32 is Migration
     * Accelerator's denominator, not a universal one. Handing it to an offering
     * with no instrument writes "scored out of 32" onto a row whose score is
     * correctly null -- the same borrowed-instrument lie as a confident 32/32,
     * one layer out, and the milder form is the harder one to notice. An
     * offering that is measured against nothing is measured out of nothing.
     */
    private static Integer frameMaxTotal(List<String> dimensionKeys, ResolvedFrame frame) {
        if (frame.fromRecord) {
            return dimensionKeys.size() * frame.maxAnswer;
        }
        return frame.compiledApplies ? MAX_TOTAL_SCORE : null;
    }

    /**
     * Whether the pack's AUTHORED POINTS may be used at all.
     *
     * This is the load-bearing guard on the whole feature. Points are editable
     * by a content author, and an author who sets a slot's top option to 3
     * points has quietly built an instrument scored out of 31 -- whose 24 is not
     * the same 24 as everybody else's, and whose bands were calibrated against
     * a maximum it no longer has. The build script blocks that at authoring
     * time (rule 10). This is the second lock, for the same reason the
     * pinned-slot rule has two: a hand-edited custom metadata record never
     * passes through the build script.
     *
     * When the derived maximum is anything but the FRAME's maximum the authored
     * points are refused wholesale and the identity scale is used instead --
     * fail to the frame, never to a private scale. It is the same "a short pack
     * falls back to the base list" instinct resolvedDimensions() already has,
     * and it is now measured against the offering's own maximum rather than
     * always against 32.
     */
    private static Boolean pointsAreTrustworthy(
        GtmAssessmentInstrument.Pack pack, ResolvedFrame frame
    ) {
        if (pack == null || pack.slots == null || pack.slots.isEmpty()) {
            return false;
        }
        if (!frame.fromRecord && frame.compiledApplies
                && pack.slots.size() != DIMENSIONS.size()) {
            return false;
        }
        return pack.maxTotal() == frameMaxTotal(pack.dimensionKeys(), frame);
    }

    /**
     * The maximum a submission against this pack is scored out of. Derived from
     * the pack when its authored points hold together, and from the offering's
     * own frame -- itself derived, never typed -- whenever they do not, which is
     * the same number by definition. Exposed so the controller can persist it
     * and a readout can print "18 out of N" from what it was actually measured
     * against rather than from today's configuration.
     *
     * Ceilings are deliberately NOT subtracted -- see Slot.topPoints().
     */
    public static Integer maxTotalFor(String offeringKey, GtmAssessmentInstrument.Pack pack) {
        ResolvedFrame frame = frameFor(offeringKey);
        return pointsAreTrustworthy(pack, frame)
            ? pack.maxTotal()
            : frameMaxTotal(
                pack == null ? untrustedPackFallback(frame) : pack.dimensionKeys(), frame
              );
    }

    /** The max_attainable for a resolved key, or null when uncapped. */
    private static Integer ceilingFor(GtmAssessmentInstrument.Pack pack, String key) {
        if (pack == null || pack.slots == null) {
            return null;
        }
        for (GtmAssessmentInstrument.Slot slot : pack.slots) {
            if (key.equals(slot.key)) {
                return slot.maxAttainable;
            }
        }
        return null;
    }
}
