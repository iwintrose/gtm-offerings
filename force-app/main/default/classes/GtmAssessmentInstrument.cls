/**
 * Resolves "what are they moving from, and to?" into WHICH EIGHT QUESTIONS to
 * ask -- and, just as importantly, into an honest statement of how much of the
 * answer we can actually verify.
 *
 * THE FRAME IS FIXED; ONLY THE CONTENT ADAPTS. Eight slots, 1-4 each, 8-32
 * total, four fixed bands, for every pair. No per-pair weighting and no
 * per-pair band edges. That is not conservatism, it is the instrument's only
 * real output: a score is worth something because it can be compared to the
 * last one. "19 would have been Accelerator-Ready if you'd come from Marketo"
 * is a sentence that ends a meeting, and a per-pair band is the only way to
 * produce it. Per-pair severity is expressed instead through option
 * calibration (a 4 is harder to earn on a hostile pair) and through gates,
 * which annotate the tier without touching the number.
 *
 * FIVE LAYERS OF VARIATION, authored at the lowest one that does the job:
 *
 *   L0  constant       the slot does not vary at all
 *   L1  reword         same anchors, this pair's examples and nouns
 *   L2  recalibrate    the anchors move; a 4 is harder or easier to earn
 *   L3  substitute     a different question in the same POSITION carrying the
 *                      same RISK THEME. Reserved for differences of kind, not
 *                      of degree -- in HubSpot the CRM is the marketing
 *                      platform, so "is your data model mappable" is not a
 *                      harder version of the right question, it is a different
 *                      one. Positions 1 and 8 are never substitutable; that
 *                      invariant spine is what keeps two prospects' 24s
 *                      describing the same eight things.
 *   L4  supplement     extra questions OUTSIDE the 32, producing their own
 *                      named index. See GTM_Assessment_Supplement__mdt.
 *
 * AND ONE AXIS THAT IS NOT A LAYER: BRANCHING. The five layers above vary a
 * slot by WHO IS MOVING WHERE, decided before the first question is asked.
 * Show_When_JSON__c varies it by WHAT THEY HAVE ALREADY SAID -- "ask the MCE
 * version of slot 5 if they told us slot 1 is MCE, else ask the MCAE version".
 * It is authored per slot as a list of VARIANTS, each a complete question, and
 * exactly one of them (or the unconditional default) fills the slot. See
 * applyBranches(): branches substitute, they never remove, so eight slots are
 * answered on every path and the total is out of 32 on every path. The predicate
 * grammar is GTM_Assessment_Gate__mdt's, evaluated by GtmPredicate -- one language
 * for both, deliberately, rather than a second one to learn.
 *
 * RESOLUTION CHAIN, most specific wins, shallow-merged per slot:
 *
 *     exact pair (hubspot__mcn)
 *       -> source-family x target (inbound_suite__mcn)
 *         -> target-only (any__mcn)
 *           -> base
 *
 * Merging runs least-specific first so the most specific pack overwrites, and
 * it is per SLOT and per FIELD: a target-only pack can move the anchors on
 * consent_portability while the exact pair leaves them alone and only reworks
 * slot 5. A target of "Not decided yet" resolves to base and says so.
 *
 * NO BRANCHING ON PLATFORM. There is not one platform name in this file, and
 * there must never be. Everything a pair varies is a row in
 * GTM_Assessment_Pair__mdt / GTM_Assessment_Dimension_Override__mdt, resolved by
 * key. Adding HubSpot as a source was a metadata edit; adding Braze will be
 * too.
 *
 * COST AND FAILURE. Custom metadata queries do not consume SOQL query or row
 * limits, so resolve() can be called from a guest transaction that is already
 * doing real work. It is pure in the sense that matters -- it writes nothing,
 * and reads only configuration -- and it FAILS OPEN: any exception, any
 * missing table, any half-deployed pack falls back to the base pack built from
 * GtmAssessmentScoring.DIMENSIONS. An unpopulated config table is a deployment
 * state, not a product judgement, and an assessment that refuses to render
 * because a pack is missing is worse than one that renders the base questions.
 */
public with sharing class GtmAssessmentInstrument {

    public static final String POSTURE_INSTRUMENTED  = 'instrumented';
    public static final String POSTURE_ASSISTED      = 'assisted';
    public static final String POSTURE_INTERVIEW     = 'interview_only';

    public static final String LAYER_REWORD      = 'reword';
    public static final String LAYER_RECALIBRATE = 'recalibrate';
    public static final String LAYER_SUBSTITUTE  = 'substitute';

    /**
     * The value of GTM_Assessment_Dimension_Override__mdt.Instrument__c that
     * routes a row to the second axis. Blank means the first, so nothing
     * authored before complexity became adaptive had to be rewritten.
     */
    public static final String INSTRUMENT_COMPLEXITY = 'Complexity';

    /** DeveloperName of the pack every chain terminates at. */
    public static final String BASE_PAIR_KEY = 'base';
    /** The wildcard both key columns use to mean "any". */
    public static final String ANY_KEY = '*';

    /**
     * The variant key of the unconditional row -- the question a slot asks when
     * no branch fires. Every slot has one, which is the whole reason branching
     * cannot leave a slot empty.
     */
    public static final String DEFAULT_VARIANT = 'default';

    private static final String UNDECIDED_TARGET_NOTE =
        'No target platform was named, so this assessment used the base questions. ' +
        'The eight dimensions are the same either way; what changes once a target ' +
        'is chosen is how hard some of the top answers are to earn, and which ' +
        'platform-specific gaps get named.';

    // -------------------------------------------------------------- caching

    private static List<GTM_Assessment_Pair__mdt> cachedPairs;
    private static List<GTM_Assessment_Dimension_Override__mdt> cachedOverrides;
    private static List<GTM_Assessment_Supplement__mdt> cachedSupplements;
    private static List<GTM_Assessment_Gate__mdt> cachedGates;

    @TestVisible private static List<GTM_Assessment_Pair__mdt> pairOverride;
    @TestVisible private static List<GTM_Assessment_Dimension_Override__mdt> overrideOverride;
    @TestVisible private static List<GTM_Assessment_Supplement__mdt> supplementOverride;
    @TestVisible private static List<GTM_Assessment_Gate__mdt> gateOverride;

    // ---------------------------------------------------------------- types

    /**
     * One answer choice. `available` false is the whole reason this is a class
     * rather than a label: an option a pair has capped out still RENDERS, greyed,
     * with `unavailableReason` next to it. Silently dropping it would leave a
     * prospect scoring 3 out of an apparent 3 with no way to see that a 4 was
     * never on offer -- which is the difference between a defensible ceiling and
     * a rigged one.
     */
    public class Option {
        /**
         * The option's IDENTITY -- 1..4, ascending, stable forever. This is
         * what a submitted answer names and what Section_Scores__c used to
         * store, so it must not be reused to mean "how much it is worth".
         */
        @AuraEnabled public Integer value;
        @AuraEnabled public String label;
        /**
         * What the option is WORTH, set by the content author. Defaults to
         * `value`, which is what every option was worth before points became
         * authorable -- so existing content scores identically.
         *
         * Points buy a NON-LINEAR scale (1/1/3/4: "two of these four answers
         * are equally bad"), not a bigger or smaller one. The build script
         * requires every option set to bottom out at 1 and top out at 4 with no
         * descent, which is what keeps the slot worth 1-4, the frame worth 32,
         * and one prospect's total comparable to another's.
         */
        @AuraEnabled public Integer points;
        @AuraEnabled public Boolean available;
        @AuraEnabled public String unavailableReason;

        public Option(Integer value, String label) {
            this(value, label, value);
        }

        public Option(Integer value, String label, Integer points) {
            this.value     = value;
            this.label     = label;
            this.points    = points == null ? value : points;
            this.available = true;
        }

        public Option copy() {
            Option o = new Option(value, label, points);
            o.available          = available;
            o.unavailableReason  = unavailableReason;
            return o;
        }
    }

    /** One of the eight. Always one of exactly eight. */
    public class Slot {
        @AuraEnabled public Integer position;
        /** The key answers are stored under -- the substituted key, if any. */
        @AuraEnabled public String key;
        /** The frame's key for this position, which never changes. */
        @AuraEnabled public String baseKey;
        @AuraEnabled public String label;
        @AuraEnabled public String question;
        @AuraEnabled public String measures;
        /**
         * CONSULTANT-ONLY, AND DELIBERATELY NOT @AuraEnabled.
         *
         * This is the interviewer's note -- "Ask for five numbers, not an
         * adjective", "Ask who logs into HubSpot who is not in marketing" --
         * written in the second person ABOUT the person answering. For months
         * every one of the eight slots ended with one of these in the guest
         * questionnaire, so a prospect read eight instructions for interrogating
         * themselves. It was authored as consultant guidance and nobody checked
         * where it surfaced.
         *
         * Dropping the annotation is the fix that cannot regress: an Apex field
         * with no @AuraEnabled is not part of the response the Lightning
         * controller serialises, so no template can render it by accident and no
         * future author can reintroduce it by adding a line to the HTML. It is
         * still here, still read by rep-assisted and agent-side Apex, and still
         * on GTM_Assessment_Dimension_Override__mdt where a consultant edits it.
         *
         * respondentHint below is the half the prospect sees.
         */
        public String evidencePrompt;
        /**
         * The prospect-facing hint: where, in their own platform, the numbers
         * this question asks for actually live. Addressed TO the respondent.
         * scripts/build-instrument.py rejects one that begins "Ask", which is
         * the shape of the mistake this pair of fields exists to separate.
         */
        @AuraEnabled public String respondentHint;
        /** Null when nothing overrode this slot for this pair (layer 0). */
        @AuraEnabled public String layer;
        @AuraEnabled public List<Option> options;
        @AuraEnabled public Integer maxAttainable;
        @AuraEnabled public String ceilingReason;
        @AuraEnabled public Boolean substitutable;
        /**
         * Which authored variant filled this slot. DEFAULT_VARIANT until a
         * branch fires. Recorded on the request so a historical readout can say
         * which question was asked, not merely which pack was used.
         */
        @AuraEnabled public String variantKey;
        /** The predicate that selected this variant. Null on the default. */
        @AuraEnabled public String showWhenJson;
        /**
         * The branch alternatives for this slot, in author-set evaluation
         * order. Each is a COMPLETE slot -- the default with the variant's row
         * merged over it -- so choosing a branch is picking one of these, never
         * assembling one. That is the shape that makes "branches substitute,
         * they never remove" true by construction: whatever happens, the slot
         * is one of {default} u variants, and it is always exactly one.
         *
         * Serialized to the client so the questionnaire can branch as the
         * respondent answers, without a round trip per question. The client's
         * choice is advisory: the server re-resolves the same branches from the
         * submitted answers, and its answer is the one that scores.
         */
        @AuraEnabled public List<Slot> variants;

        public Slot() {
            this.options       = new List<Option>();
            this.maxAttainable = GtmAssessmentScoring.MAX_ANSWER_VALUE;
            this.substitutable = true;
            this.variantKey    = DEFAULT_VARIANT;
            this.variants      = new List<Slot>();
        }

        /**
         * A copy carrying everything except the variant list -- a variant of a
         * variant is not a thing this design has, and letting one exist would
         * make the branch path a tree instead of a choice.
         */
        public Slot copy() {
            Slot c           = new Slot();
            c.position       = position;
            c.key            = key;
            c.baseKey        = baseKey;
            c.label          = label;
            c.question       = question;
            c.measures       = measures;
            c.evidencePrompt = evidencePrompt;
            c.respondentHint = respondentHint;
            c.layer          = layer;
            c.maxAttainable  = maxAttainable;
            c.ceilingReason  = ceilingReason;
            c.substitutable  = substitutable;
            c.variantKey     = variantKey;
            c.showWhenJson   = showWhenJson;
            for (Option o : options) {
                c.options.add(o.copy());
            }
            return c;
        }

        /**
         * The most this slot can be worth, from the authored points and
         * IGNORING any ceiling. Ceilings are a handicap on a hostile pair, not
         * a smaller instrument: hubspot__mcn caps two slots at 3 and is still
         * scored out of 32, which is precisely what makes the cap cost
         * something. A slot with no options falls back to the frame's 4.
         */
        public Integer topPoints() {
            Integer top = null;
            for (Option o : options) {
                if (o.points != null && (top == null || o.points > top)) {
                    top = o.points;
                }
            }
            return top == null ? GtmAssessmentScoring.MAX_ANSWER_VALUE : top;
        }

        /** The points an answer VALUE is worth here, or null if it is not an option. */
        public Integer pointsForValue(Integer value) {
            if (value == null) {
                return null;
            }
            for (Option o : options) {
                if (value.equals(o.value)) {
                    return o.points == null ? o.value : o.points;
                }
            }
            return null;
        }
    }

    /**
     * One of the six ESTATE COMPLEXITY dimensions, resolved for this pair.
     *
     * A separate type from Slot, on purpose. A Slot is worth 1-4, can carry a
     * ceiling and can be branched; a complexity dimension is worth 1-3, can do
     * neither, and is never added to the 32. Reusing Slot would have inherited
     * a maxAttainable that defaults to 4 and a topPoints() that falls back to 4,
     * and the first person to read a complexity dimension through Slot's API
     * would have been reading a scale that does not exist.
     *
     * WHY IT IS ADAPTIVE AT ALL. The base wording lives in
     * GTM_Assessment_Question__mdt (Instrument__c = 'Complexity') and was written
     * once, in the TARGET's vocabulary, then asked about a SOURCE estate: a
     * HubSpot marketer was asked about "30-100 tables, moderate SQL" and
     * "standard publication or subscription lists". They have neither, so they
     * could not answer honestly and the axis produced noise. The five-layer
     * adaptive machinery already solved exactly this for the eight readiness
     * slots; this is that machinery pointed at the second axis, through the same
     * table and the same merge.
     */
    public class ComplexityDimension {
        @AuraEnabled public Integer position;
        /** The key answers are stored under -- the substituted key, if any. */
        @AuraEnabled public String key;
        /** The frame's key for this position, which never changes. */
        @AuraEnabled public String baseKey;
        @AuraEnabled public String label;
        @AuraEnabled public String question;
        @AuraEnabled public String measures;
        @AuraEnabled public String respondentHint;
        /** Consultant-only, for the same reason as Slot.evidencePrompt. */
        public String evidencePrompt;
        /** Null when nothing overrode this dimension for this pair (layer 0). */
        @AuraEnabled public String layer;
        @AuraEnabled public List<Option> options;

        public ComplexityDimension() {
            this.options = new List<Option>();
        }
    }

    /** A layer-4 question. Outside the 32, always. */
    public class Supplement {
        @AuraEnabled public String setKey;
        @AuraEnabled public String key;
        @AuraEnabled public String question;
        @AuraEnabled public List<Option> options;
        @AuraEnabled public Boolean scored;
        @AuraEnabled public String indexKey;
        @AuraEnabled public Boolean horizonDriver;
        @AuraEnabled public Decimal sortOrder;
        /** Per-option horizon text, keyed by option value. Empty when unused. */
        @AuraEnabled public Map<String, String> horizonByValue;

        public Supplement() {
            this.options        = new List<Option>();
            this.scored         = false;
            this.horizonDriver  = false;
            this.horizonByValue = new Map<String, String>();
        }
    }

    /** A gate definition. Evaluation lives in GtmAssessmentReadout. */
    public class Gate {
        @AuraEnabled public String key;
        @AuraEnabled public String tierQualifier;
        @AuraEnabled public String readoutBlock;
        @AuraEnabled public String severity;
        /** Parsed predicate; null when the JSON was unusable (gate stays inert). */
        public Object predicate;
    }

    /**
     * One gap pattern, in the shape ma-migrator's
     * capabilities/schema/capability.schema.json defines. Reused verbatim so a
     * callout a consultant typed and a callout lifted from a real platform
     * manifest render identically -- a reader who cannot tell which is which is
     * a reader who does not have to decide how much to trust each one.
     */
    public class Callout {
        @AuraEnabled public String pattern;
        @AuraEnabled public String status;
        @AuraEnabled public String severity;
        @AuraEnabled public String category;
        @AuraEnabled public String issue;
        @AuraEnabled public String gloss;
        @AuraEnabled public String workaround;
        @AuraEnabled public List<String> manualSteps;
        /**
         * True when the underlying capability assertion is a working assumption
         * pending verification against a real tenant. Carried through to the
         * readout so the rendered sentence hedges BY CONSTRUCTION rather than
         * depending on whoever writes the deck remembering to hedge.
         */
        @AuraEnabled public Boolean verificationRequired;

        public Callout() {
            this.manualSteps          = new List<String>();
            this.verificationRequired = false;
        }
    }

    /** The resolved instrument for one source/target combination. */
    public class Pack {
        @AuraEnabled public List<Slot> slots;
        /**
         * The second axis, resolved. Six of them, always -- the same guarantee
         * slots gives for eight, and for the same reason: GtmEstateComplexity
         * prints "out of 18" and a pack that resolved to five would print it
         * anyway. Never merged into slots and never summed with them.
         */
        @AuraEnabled public List<ComplexityDimension> complexityDimensions;
        @AuraEnabled public List<Supplement> supplements;
        public List<Gate> gates;
        @AuraEnabled public String posture;
        @AuraEnabled public String sourcePosture;
        @AuraEnabled public String targetPosture;
        @AuraEnabled public String postureStatement;
        @AuraEnabled public List<Callout> callouts;
        @AuraEnabled public String pairKey;
        @AuraEnabled public String version;
        @AuraEnabled public String sourceKey;
        @AuraEnabled public String targetKey;
        @AuraEnabled public List<String> emphasisSlots;
        /** Every pack DeveloperName that contributed, least specific first. */
        @AuraEnabled public List<String> resolutionChain;
        /** Non-null when something about the resolution needs saying out loud. */
        @AuraEnabled public String resolutionNote;
        /**
         * Whether estate figures on the readout are the client's account rather
         * than a measurement. A serialized FIELD rather than a getter, because
         * an @AuraEnabled instance method is not part of an Apex response and a
         * marker that silently never reaches the client is worse than none.
         * Kept in step with sourcePosture by markProvenance().
         */
        @AuraEnabled public Boolean estateFiguresIllustrative;

        public Pack() {
            this.slots                = new List<Slot>();
            this.complexityDimensions = new List<ComplexityDimension>();
            this.supplements     = new List<Supplement>();
            this.gates           = new List<Gate>();
            this.callouts        = new List<Callout>();
            this.emphasisSlots   = new List<String>();
            this.resolutionChain = new List<String>();
            this.posture         = POSTURE_INTERVIEW;
            this.sourcePosture   = POSTURE_INTERVIEW;
            this.targetPosture   = POSTURE_INTERVIEW;
            this.pairKey         = BASE_PAIR_KEY;
            this.estateFiguresIllustrative = true;
        }

        /**
         * The eight keys answers are scored against -- the allowlist, resolved.
         * Substitution changes what is in this list, never how long it is.
         */
        public List<String> dimensionKeys() {
            List<String> keys = new List<String>();
            for (Slot s : slots) {
                keys.add(s.key);
            }
            return keys;
        }

        /**
         * The six keys complexity answers are scored against -- the allowlist,
         * resolved. Substitution changes what is in this list, never how long it
         * is, which is what keeps a pre-scan self-estimate and a post-scan
         * measurement of the same estate comparable row by row.
         */
        public List<String> complexityKeys() {
            List<String> keys = new List<String>();
            for (ComplexityDimension d : complexityDimensions) {
                keys.add(d.key);
            }
            return keys;
        }

        /**
         * The maximum a fully-answered questionnaire can score against THIS
         * pack, summed from the authored points rather than typed. It exists
         * because points are author-editable: if it ever disagrees with
         * GtmAssessmentScoring.MAX_TOTAL_SCORE, someone has authored (or
         * hand-edited) an instrument whose totals are not comparable with every
         * other one, and the scorer refuses the authored points rather than
         * quietly printing "24 out of 31".
         *
         * Ceilings are deliberately NOT subtracted -- see Slot.topPoints().
         */
        public Integer maxTotal() {
            Integer total = 0;
            for (Slot s : slots) {
                total += s.topPoints();
            }
            return total;
        }

        /**
         * base slot key -> the variant that filled it, for every slot. Stored on
         * the request (Instrument_Branch_Path__c) so a readout reopened later
         * can say which of several authored questions this prospect was
         * actually asked, not merely which pack they were asked from.
         */
        public Map<String, String> branchPath() {
            Map<String, String> path = new Map<String, String>();
            for (Slot s : slots) {
                path.put(s.baseKey, String.isBlank(s.variantKey) ? DEFAULT_VARIANT : s.variantKey);
            }
            return path;
        }

        /** The slot a stored answer key belongs to, or null. */
        public Slot slotFor(String key) {
            for (Slot s : slots) {
                if (s.key == key) {
                    return s;
                }
            }
            return null;
        }

        /**
         * Keyed on the SOURCE posture, not the headline: counts come from
         * reading the source, so an instrumented source with an interview_only
         * target has measured figures and an unverified destination.
         * Collapsing the two would misreport one of them.
         */
        public Boolean markProvenance() {
            this.estateFiguresIllustrative = (sourcePosture != POSTURE_INSTRUMENTED);
            return this.estateFiguresIllustrative;
        }

        /** Convenience reader; always in step with markProvenance(). */
        public Boolean getEstateFiguresIllustrative() {
            return estateFiguresIllustrative == true;
        }
    }

    // ------------------------------------------------------------- resolving

    /** One selectable platform, for the questionnaire's routing step. */
    public class PlatformOption {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String family;

        public PlatformOption(String key, String label, String family) {
            this.key    = key;
            this.label  = label;
            this.family = family;
        }
    }

    /**
     * The platforms a respondent may name, read from the same table that
     * already owns platform identity (GTM_Migration_Platform__mdt).
     *
     * It exists so the questionnaire's first question is CONFIGURATION rather
     * than a list typed into a component. A hardcoded list in the client is how
     * "no platform branching in code" quietly becomes untrue: the day someone
     * adds Braze to the metadata and the dropdown does not offer it, the next
     * fix is a line in a component that knows a platform name.
     *
     * Deliberately does NOT say which platforms may be a source and which a
     * target. Both ends are free text as far as this instrument is concerned:
     * an unrecognised name resolves to the base pack, and an unsupported
     * combination is caught by GtmMigrationPairs and suppresses the tier with a
     * stated reason. Pre-filtering the dropdown would replace an honest,
     * explained refusal with a silent absence.
     */
    @AuraEnabled(cacheable=true)
    public static List<PlatformOption> getPlatforms() {
        List<PlatformOption> out = new List<PlatformOption>();
        try {
            for (GTM_Migration_Platform__mdt row : [
                SELECT Platform_Key__c, Display_Label__c, Family_Key__c
                FROM GTM_Migration_Platform__mdt
                WHERE Active__c = true
                ORDER BY Display_Label__c
                LIMIT 200
            ]) {
                if (String.isBlank(row.Platform_Key__c)) {
                    continue;
                }
                out.add(new PlatformOption(
                    row.Platform_Key__c.trim(),
                    String.isBlank(row.Display_Label__c)
                        ? row.Platform_Key__c.trim()
                        : row.Display_Label__c,
                    row.Family_Key__c
                ));
            }
        } catch (Exception e) {
            // An empty list is a questionnaire that asks for the platform as
            // free text, which still resolves. Failing the whole form because a
            // config table is missing would be worse.
        }
        return out;
    }

    /** The fixed frame, for the authoring preview. */
    public class Frame {
        @AuraEnabled public Integer slotCount;
        @AuraEnabled public Integer minAnswerValue;
        @AuraEnabled public Integer maxAnswerValue;
        @AuraEnabled public Integer minTotal;
        @AuraEnabled public Integer maxTotal;
        @AuraEnabled public List<GtmAssessmentScoring.Band> bands;
    }

    /**
     * The numbers the frame is made of, served rather than duplicated.
     *
     * The content-authoring preview has to say "these answers score 19, which is
     * Prep Required". It must do that from the same constants the scorer uses --
     * all of which are derived in GtmAssessmentScoring, none of which are typed --
     * or an author will one day preview a question against a scale that no
     * longer exists and ship it.
     */
    @AuraEnabled(cacheable=true)
    public static Frame getFrame() {
        Frame f          = new Frame();
        f.slotCount      = GtmAssessmentScoring.DIMENSIONS.size();
        f.minAnswerValue = GtmAssessmentScoring.MIN_ANSWER_VALUE;
        f.maxAnswerValue = GtmAssessmentScoring.MAX_ANSWER_VALUE;
        f.minTotal       = GtmAssessmentScoring.MIN_TOTAL_SCORE;
        f.maxTotal       = GtmAssessmentScoring.MAX_TOTAL_SCORE;
        f.bands          = GtmAssessmentScoring.bands();
        return f;
    }

    /** Free-text platform names in, resolved pack out. */
    @AuraEnabled(cacheable=true)
    public static Pack getPack(String sourceName, String targetName) {
        try {
            return resolve(
                GtmMigrationPairs.resolvePlatformKey(sourceName),
                GtmMigrationPairs.resolvePlatformKey(targetName)
            );
        } catch (Exception e) {
            return basePack();
        }
    }

    /**
     * Re-resolves the chain that produced a stored pack, from the DeveloperName
     * recorded on GTM_Assessment_Request__c.Instrument_Pair__c. Reading a
     * historical readout has to reproduce the questions that were actually
     * asked, and the recorded key plus its own two key columns is enough to
     * walk the same chain again.
     */
    public static Pack resolveByPairKey(String pairKey) {
        if (String.isBlank(pairKey)) {
            return basePack();
        }
        try {
            for (GTM_Assessment_Pair__mdt row : pairRows()) {
                if (pairKey.equalsIgnoreCase(row.DeveloperName)) {
                    return resolve(unwildcard(row.Source_Key__c), unwildcard(row.Target_Key__c));
                }
            }
        } catch (Exception e) {
            // fall through
        }
        return basePack();
    }

    /**
     * Canonical platform keys in, resolved pack out. Either may be null: a null
     * target is the "Not decided yet" case and resolves to base with a note.
     */
    public static Pack resolve(String sourceKey, String targetKey) {
        try {
            return resolveInternal(sourceKey, targetKey);
        } catch (Exception e) {
            // Fails open. A pack that cannot be resolved must not take the
            // questionnaire down with it -- the base eight are still the right
            // eight, they just say less about this particular move.
            Pack fallback = basePack();
            fallback.sourceKey = sourceKey;
            fallback.targetKey = targetKey;
            return fallback;
        }
    }

    /** The frame with base wording and nothing overridden. */
    public static Pack basePack() {
        Pack out = new Pack();
        out.slots            = baseSlots();
        out.complexityDimensions = baseComplexity();
        out.resolutionChain  = new List<String>();
        out.postureStatement = null;
        out.markProvenance();
        return out;
    }

    private static Pack resolveInternal(String sourceKey, String targetKey) {
        Pack out       = new Pack();
        out.slots      = baseSlots();
        out.complexityDimensions = baseComplexity();
        out.sourceKey  = sourceKey;
        out.targetKey  = targetKey;

        String familyKey = String.isBlank(sourceKey) ? null : GtmMigrationPairs.familyFor(sourceKey);

        // Candidates, least specific first, so a more specific pack overwrites.
        List<GTM_Assessment_Pair__mdt> chain = new List<GTM_Assessment_Pair__mdt>();
        for (Integer specificity = 4; specificity >= 1; specificity--) {
            for (GTM_Assessment_Pair__mdt row : pairRows()) {
                if (row.Active__c == false || matchRank(row, sourceKey, targetKey, familyKey) != specificity) {
                    continue;
                }
                chain.add(row);
            }
        }
        if (chain.isEmpty()) {
            out.markProvenance();
            out.resolutionNote = String.isBlank(targetKey) ? UNDECIDED_TARGET_NOTE : null;
            return out;
        }

        Map<String, Callout> calloutsByPattern = new Map<String, Callout>();
        Map<String, List<GTM_Assessment_Dimension_Override__mdt>> byPair = overridesByPair();
        Set<String> supplementSets = new Set<String>();
        List<String> supplementOrder = new List<String>();
        // Conditional rows are held back rather than merged: a variant is a
        // copy of the FINAL default slot with its row applied, so it cannot be
        // built until the whole chain has finished deciding what the default is.
        Map<String, List<GTM_Assessment_Dimension_Override__mdt>> variantRows =
            new Map<String, List<GTM_Assessment_Dimension_Override__mdt>>();

        for (GTM_Assessment_Pair__mdt row : chain) {
            out.resolutionChain.add(row.DeveloperName);
            out.pairKey = row.DeveloperName;
            applyIfPresent(out, row);

            // Callouts ACCUMULATE down the chain, keyed by pattern, with the
            // more specific pack winning a collision. A target-only pack's
            // structural gaps are still true when an exact pair adds its own;
            // replacing the list wholesale would make every exact pair re-state
            // everything its target already said, and one of them would forget.
            for (Callout c : parseCallouts(row.Callouts_JSON__c)) {
                if (String.isNotBlank(c.pattern)) {
                    calloutsByPattern.put(c.pattern, c);
                }
            }
            for (String setKey : splitList(row.Supplement_Set__c)) {
                if (supplementSets.add(setKey)) {
                    supplementOrder.add(setKey);
                }
            }
            for (GTM_Assessment_Dimension_Override__mdt o :
                    orDefault(byPair.get(row.DeveloperName))) {
                if (o.Active__c == false || String.isBlank(o.Dimension__c)) {
                    continue;
                }
                // One table, two instruments, distinguished by a column rather
                // than by a second custom metadata type. A blank Instrument__c
                // means Readiness, so every override authored before the second
                // axis became adaptive keeps its meaning without being rewritten.
                if (INSTRUMENT_COMPLEXITY.equalsIgnoreCase(trimmed(o.Instrument__c))) {
                    applyComplexityOverride(out, o);
                    continue;
                }
                if (String.isBlank(o.Show_When_JSON__c)) {
                    applyOverride(out, o);
                    continue;
                }
                String dim = o.Dimension__c.trim();
                if (!variantRows.containsKey(dim)) {
                    variantRows.put(dim, new List<GTM_Assessment_Dimension_Override__mdt>());
                }
                variantRows.get(dim).add(o);
            }
        }

        for (Slot s : out.slots) {
            applyCeiling(s);
            buildVariants(s, variantRows.get(s.baseKey));
        }
        out.markProvenance();
        out.callouts     = calloutsByPattern.values();
        out.supplements  = supplementsFor(supplementOrder);
        out.gates        = gates();
        if (String.isBlank(targetKey)) {
            out.resolutionNote = UNDECIDED_TARGET_NOTE;
        }
        return out;
    }

    /**
     * 1 exact, 2 family x target, 3 target-only, 4 base, 0 no match. The order
     * IS the policy, so it is one method rather than four conditions scattered
     * through the loop.
     */
    private static Integer matchRank(
        GTM_Assessment_Pair__mdt row, String sourceKey, String targetKey, String familyKey
    ) {
        String src = trimmed(row.Source_Key__c);
        String tgt = trimmed(row.Target_Key__c);
        Boolean targetAny   = ANY_KEY.equals(tgt);
        Boolean targetExact = String.isNotBlank(targetKey) && targetKey.equalsIgnoreCase(tgt);
        if (!targetAny && !targetExact) {
            return 0;
        }
        if (ANY_KEY.equals(src)) {
            return targetAny ? 4 : 3;
        }
        if (String.isNotBlank(sourceKey) && sourceKey.equalsIgnoreCase(src)) {
            return targetExact ? 1 : 0;
        }
        if (String.isNotBlank(familyKey) && familyKey.equalsIgnoreCase(src)) {
            return targetExact ? 2 : 0;
        }
        return 0;
    }

    // -------------------------------------------------------------- merging

    /** Pack-level fields: a blank on a more specific pack inherits, never clears. */
    private static void applyIfPresent(Pack out, GTM_Assessment_Pair__mdt row) {
        if (String.isNotBlank(row.Capability_Posture__c)) { out.posture = row.Capability_Posture__c; }
        if (String.isNotBlank(row.Source_Posture__c))     { out.sourcePosture = row.Source_Posture__c; }
        if (String.isNotBlank(row.Target_Posture__c))     { out.targetPosture = row.Target_Posture__c; }
        if (String.isNotBlank(row.Posture_Statement__c))  { out.postureStatement = row.Posture_Statement__c; }
        if (String.isNotBlank(row.Version__c))            { out.version = row.Version__c; }
        List<String> emphasis = splitList(row.Emphasis_Slots__c);
        if (!emphasis.isEmpty()) { out.emphasisSlots = emphasis; }
    }

    /**
     * Shallow merge, per slot, per field. A null column inherits whatever the
     * less specific pack left there; only a populated one replaces it. That is
     * what lets a target-only pack move the consent anchors while an exact pair
     * changes only slot 5, without either having to restate the other.
     */
    private static void applyOverride(Pack out, GTM_Assessment_Dimension_Override__mdt o) {
        if (o.Active__c == false || String.isBlank(o.Dimension__c)) {
            return;
        }
        String baseKey = o.Dimension__c.trim();
        for (Slot s : out.slots) {
            if (s.baseKey == baseKey) {
                applyRow(s, o);
                return;
            }
        }
    }

    /**
     * The same shallow, per-field merge as applyOverride, for the second axis.
     *
     * Complexity does not branch, so there is no variant path here and none is
     * wanted: a complexity score is recomputed post-scan from a real extract
     * against the same six keys, and a dimension whose question changed with an
     * earlier answer could not be recomputed at all. The build script rejects a
     * complexity override that declares show_when; this is the second lock, for
     * a hand-edited record that never passed through it.
     */
    private static void applyComplexityOverride(Pack out, GTM_Assessment_Dimension_Override__mdt o) {
        String baseKey = o.Dimension__c.trim();
        for (ComplexityDimension d : out.complexityDimensions) {
            if (d.baseKey == baseKey) {
                if (String.isNotBlank(o.Layer__c)) { d.layer = o.Layer__c; }
                if (LAYER_SUBSTITUTE.equalsIgnoreCase(o.Layer__c)
                        && String.isNotBlank(o.New_Key__c)) {
                    d.key = o.New_Key__c.trim();
                }
                if (String.isNotBlank(o.Label__c))           { d.label = o.Label__c; }
                if (String.isNotBlank(o.Question__c))        { d.question = o.Question__c; }
                if (String.isNotBlank(o.Measures__c))        { d.measures = o.Measures__c; }
                if (String.isNotBlank(o.Evidence_Prompt__c)) { d.evidencePrompt = o.Evidence_Prompt__c; }
                if (String.isNotBlank(o.Respondent_Hint__c)) { d.respondentHint = o.Respondent_Hint__c; }
                List<Option> parsed = parseOptions(o.Options_JSON__c);
                if (!parsed.isEmpty()) { d.options = parsed; }
                return;
            }
        }
    }

    /**
     * Merges one authored row onto one slot. Split out of applyOverride because
     * a branch VARIANT is the same merge applied to a copy of the resolved
     * default rather than to the default itself -- one merge rule, used twice,
     * so a variant can never end up obeying different authoring semantics than
     * the question it stands in for.
     */
    private static void applyRow(Slot s, GTM_Assessment_Dimension_Override__mdt o) {
        if (String.isNotBlank(o.Layer__c)) { s.layer = o.Layer__c; }
        if (LAYER_SUBSTITUTE.equalsIgnoreCase(o.Layer__c) && String.isNotBlank(o.New_Key__c)) {
            // A pinned position never substitutes, whatever a row says. The
            // build script blocks it at authoring time; this is the second
            // lock, because a hand-edited metadata record does not pass
            // through the build script.
            if (s.substitutable == true) {
                s.key = o.New_Key__c.trim();
            }
        }
        if (String.isNotBlank(o.Label__c))           { s.label = o.Label__c; }
        if (String.isNotBlank(o.Question__c))        { s.question = o.Question__c; }
        if (String.isNotBlank(o.Measures__c))         { s.measures = o.Measures__c; }
        if (String.isNotBlank(o.Evidence_Prompt__c)) { s.evidencePrompt = o.Evidence_Prompt__c; }
        if (String.isNotBlank(o.Respondent_Hint__c)) { s.respondentHint = o.Respondent_Hint__c; }
        if (String.isNotBlank(o.Ceiling_Reason__c))  { s.ceilingReason = o.Ceiling_Reason__c; }
        if (o.Max_Attainable__c != null)             { s.maxAttainable = o.Max_Attainable__c.intValue(); }
        List<Option> parsed = parseOptions(o.Options_JSON__c);
        if (!parsed.isEmpty()) { s.options = parsed; }
    }

    /**
     * Materialises a slot's branch alternatives.
     *
     * THE INVARIANT LIVES HERE. A variant is built as a COPY OF THE RESOLVED
     * DEFAULT with the variant's row merged over it, which is what makes
     * "branches substitute, they never remove" structural rather than a rule
     * someone has to remember: there is no code path that produces a slot with
     * no question, because every variant starts life as a complete slot. A
     * predicate that matches nothing leaves the default standing; a predicate
     * that matches swaps one complete question for another. Either way the slot
     * is filled, and eight slots are always answered.
     *
     * A variant with no Variant_Key__c is named by position so the branch path
     * recorded on the request is never ambiguous.
     */
    private static void buildVariants(Slot s, List<GTM_Assessment_Dimension_Override__mdt> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        // The default itself goes in as the first candidate, tagged
        // DEFAULT_VARIANT with a blank showWhenJson -- this is what makes
        // re-resolution correct on an already-substituted pack (applyBranches
        // called a second time, e.g. once by the questionnaire as the
        // respondent answers and again by the server on submit). Without
        // this, "fall back to the default" on a re-run had nothing but the
        // CURRENTLY-substituted slot to fall back to, which is not the
        // default once a branch has already fired once -- a predicate that
        // stopped matching left the previous branch standing instead of
        // reverting, which is not idempotent (bug found empirically:
        // GtmAssessmentInstrumentTest.applyBranchesIsIdempotent's second
        // assertion, never caught before because nothing on this branch had
        // ever run against a compiler until now).
        Slot defaultCandidate = s.copy();
        defaultCandidate.variantKey   = DEFAULT_VARIANT;
        defaultCandidate.showWhenJson = null;
        s.variants.add(defaultCandidate);

        Integer n = 0;
        for (GTM_Assessment_Dimension_Override__mdt o : rows) {
            n++;
            Slot v         = s.copy();
            applyRow(v, o);
            v.variantKey   = String.isBlank(o.Variant_Key__c)
                ? s.baseKey + '_variant_' + String.valueOf(n)
                : o.Variant_Key__c.trim();
            v.showWhenJson = o.Show_When_JSON__c;
            applyCeiling(v);
            s.variants.add(v);
        }
    }

    // -------------------------------------------------------------- branching

    /**
     * Chooses, for every slot, WHICH of its authored questions this respondent
     * is asked -- given the answers they have given so far.
     *
     * Pure and deterministic. Called twice for every submission: once by the
     * questionnaire as the respondent moves through it (so the next step shows
     * the right question without a round trip), and once again by
     * GtmAssessmentRequestController against the full submitted answer map, and
     * it is the SECOND call that decides what scores. A client that branched
     * differently -- through tampering or through a stale cached pack -- submits
     * answers under keys this method did not resolve, and an answer under a key
     * the server did not ask for is simply never read. That is the same
     * allowlist property the scorer has always had, reached from a new
     * direction.
     *
     * WHY IT CAN BE DONE IN ONE PASS. A predicate may only reference `source`,
     * `target`, or a slot at a strictly LOWER position (build script rule 8).
     * So walking the slots in order, a predicate's inputs are always already
     * decided: there is no fixpoint to iterate to and no cycle to detect.
     *
     * Predicates speak in ANSWER VALUES (the 1-4 option the respondent picked),
     * never in points. An author writing `{field: estate_scale, op: eq, value: 4}`
     * means "they chose the fourth option", which is what they can see on the
     * screen; what that option happens to be worth is a separate decision they
     * may retune without silently rewiring every branch in the instrument.
     */
    public static Pack applyBranches(Pack pack, Map<String, Integer> answers) {
        if (pack == null || pack.slots == null || pack.slots.isEmpty()) {
            return pack;
        }
        Map<String, Integer> given = answers == null ? new Map<String, Integer>() : answers;
        Map<String, Object> context = new Map<String, Object>();
        context.put('source', pack.sourceKey);
        context.put('target', pack.targetKey);

        List<Slot> resolved = new List<Slot>();
        for (Slot s : pack.slots) {
            // Falls back to the explicit DEFAULT_VARIANT candidate in
            // s.variants when one was built (see buildVariants), not to `s`
            // itself -- on a re-run, `s` is whatever slot won LAST time, not
            // the default, and a predicate that stops matching must revert,
            // not leave the previous branch standing.
            Slot chosen = s;
            for (Slot v : s.variants) {
                if (DEFAULT_VARIANT.equals(v.variantKey)) {
                    chosen = v;
                    break;
                }
            }
            for (Slot v : s.variants) {
                if (String.isBlank(v.showWhenJson)) {
                    continue;
                }
                if (GtmPredicate.matches(GtmPredicate.parse(v.showWhenJson), context)) {
                    chosen = v;
                    break;
                }
            }
            Slot filled    = chosen.copy();
            // The alternatives travel with the resolved slot so this is
            // idempotent: re-running it against more answers re-decides from
            // the same authored set rather than from whatever last won.
            filled.variants = s.variants;
            resolved.add(filled);

            Integer value = given.get(filled.key);
            if (value != null) {
                context.put(filled.baseKey, value);
                // Also under the resolved key, so a predicate authored against a
                // substituted key reads the same answer as one authored against
                // the base key it stands in for.
                context.put(filled.key, value);
            }
        }
        pack.slots = resolved;
        return pack;
    }

    /**
     * Marks the options a ceiling excludes as unavailable rather than removing
     * them. See Option.available -- a prospect who can see that a 4 was not on
     * offer, and why, can argue with the instrument; one who cannot has been
     * quietly marked down.
     */
    private static void applyCeiling(Slot s) {
        Integer cap = s.maxAttainable == null ? GtmAssessmentScoring.MAX_ANSWER_VALUE : s.maxAttainable;
        for (Option o : s.options) {
            if (o.value != null && o.value > cap) {
                o.available         = false;
                o.unavailableReason = String.isBlank(s.ceilingReason)
                    ? 'Not available for this source and target combination.'
                    : s.ceilingReason;
            }
        }
    }

    // ------------------------------------------------------------ base frame

    /**
     * The eight base slots, wording taken from GTM_Assessment_Question__mdt so a
     * consultant can still reword a base question in Setup and deploy nothing.
     * Positions come from GtmAssessmentScoring.DIMENSIONS, which stays the single
     * literal the whole instrument is measured against.
     */
    private static List<Slot> baseSlots() {
        Map<String, GtmAssessmentQuestions.Question> wording =
            new Map<String, GtmAssessmentQuestions.Question>();
        try {
            for (GtmAssessmentQuestions.Question q :
                    GtmAssessmentQuestions.questionsFor(GtmAssessmentQuestions.INSTRUMENT_READINESS)) {
                if (String.isNotBlank(q.dimensionKey)) {
                    wording.put(q.dimensionKey, q);
                }
            }
        } catch (Exception e) {
            // No question metadata deployed: the keys are still the instrument,
            // the labels are simply absent. A keyed questionnaire with no words
            // is broken for a prospect but correct for the scorer, and the
            // scorer is the half that must not be allowed to fail.
        }

        List<String> dims = GtmAssessmentScoring.DIMENSIONS;
        List<Slot> slots = new List<Slot>();
        for (Integer i = 0; i < dims.size(); i++) {
            Slot s   = new Slot();
            s.position = i + 1;
            s.key      = dims[i];
            s.baseKey  = dims[i];
            // First and last are the invariant spine. Derived from position
            // rather than listed, so the rule cannot drift from the list.
            s.substitutable = (i != 0 && i != dims.size() - 1);
            GtmAssessmentQuestions.Question q = wording.get(dims[i]);
            if (q != null) {
                s.label    = q.dimensionName;
                s.question = q.questionText;
                s.measures = q.measures;
                for (GtmAssessmentQuestions.AnswerOption ao : q.options) {
                    s.options.add(new Option(ao.value, ao.label));
                }
            }
            slots.add(s);
        }
        return slots;
    }

    /**
     * The six base complexity dimensions, wording from GTM_Assessment_Question__mdt
     * exactly as baseSlots takes the eight readiness ones -- so a consultant can
     * still reword a base complexity question in Setup and deploy nothing.
     *
     * Positions come from GtmEstateComplexity.DIMENSIONS, which stays the single
     * literal the second axis is measured against, for the same reason
     * GtmAssessmentScoring.DIMENSIONS is for the first. A pair adapts the WORDS;
     * it never adds a seventh dimension or removes a sixth.
     */
    private static List<ComplexityDimension> baseComplexity() {
        Map<String, GtmAssessmentQuestions.Question> wording =
            new Map<String, GtmAssessmentQuestions.Question>();
        try {
            for (GtmAssessmentQuestions.Question q :
                    GtmAssessmentQuestions.questionsFor(GtmAssessmentQuestions.INSTRUMENT_COMPLEXITY)) {
                if (String.isNotBlank(q.dimensionKey)) {
                    wording.put(q.dimensionKey, q);
                }
            }
        } catch (Exception e) {
            // Same trade as baseSlots: the keys are still the axis, the labels
            // are simply absent. The scorer is the half that must not fail.
        }

        List<String> dims = GtmEstateComplexity.DIMENSIONS;
        List<ComplexityDimension> out = new List<ComplexityDimension>();
        for (Integer i = 0; i < dims.size(); i++) {
            ComplexityDimension d = new ComplexityDimension();
            d.position = i + 1;
            d.key      = dims[i];
            d.baseKey  = dims[i];
            GtmAssessmentQuestions.Question q = wording.get(dims[i]);
            if (q != null) {
                d.label    = q.dimensionName;
                d.question = q.questionText;
                d.measures = q.measures;
                for (GtmAssessmentQuestions.AnswerOption ao : q.options) {
                    d.options.add(new Option(ao.value, ao.label));
                }
            }
            out.add(d);
        }
        return out;
    }

    // ------------------------------------------------------------ supplements

    private static List<Supplement> supplementsFor(List<String> setKeys) {
        List<Supplement> out = new List<Supplement>();
        if (setKeys == null || setKeys.isEmpty()) {
            return out;
        }
        List<GTM_Assessment_Supplement__mdt> rows = supplementRows();
        for (String setKey : setKeys) {
            for (GTM_Assessment_Supplement__mdt row : rows) {
                if (row.Active__c == false || !setKey.equalsIgnoreCase(trimmed(row.Set_Key__c))) {
                    continue;
                }
                Supplement s   = new Supplement();
                s.setKey        = trimmed(row.Set_Key__c);
                s.key           = trimmed(row.Key__c);
                s.question      = row.Question__c;
                s.scored        = row.Scored__c == true;
                s.indexKey      = trimmed(row.Index_Key__c);
                s.horizonDriver = row.Horizon_Driver__c == true;
                s.sortOrder     = row.Sort_Order__c;
                s.options       = parseOptions(row.Options_JSON__c);
                s.horizonByValue = parseHorizons(row.Options_JSON__c);
                out.add(s);
            }
        }
        return out;
    }

    // ----------------------------------------------------------------- gates

    private static List<Gate> gates() {
        List<Gate> out = new List<Gate>();
        for (GTM_Assessment_Gate__mdt row : gateRows()) {
            if (row.Active__c == false || String.isBlank(row.Key__c)) {
                continue;
            }
            Gate g          = new Gate();
            g.key           = row.Key__c.trim();
            g.tierQualifier = row.Tier_Qualifier__c;
            g.readoutBlock  = row.Readout_Block__c;
            g.severity      = row.Severity__c;
            // An unparseable predicate leaves the gate inert rather than firing
            // on everything or nothing in particular. GtmPredicate.parse is the
            // one place that decision is made, for gates and branches alike.
            g.predicate = GtmPredicate.parse(row.Predicate_JSON__c);
            out.add(g);
        }
        return out;
    }

    // --------------------------------------------------------------- parsing

    private static List<Option> parseOptions(String jsonStr) {
        List<Option> out = new List<Option>();
        if (String.isBlank(jsonStr)) {
            return out;
        }
        try {
            for (Object raw : (List<Object>) JSON.deserializeUntyped(jsonStr)) {
                Map<String, Object> m = (Map<String, Object>) raw;
                Object v = m.get('value');
                if (!(v instanceof Integer) && !(v instanceof Decimal)) {
                    continue;
                }
                Object pts = m.get('points');
                out.add(new Option(
                    Integer.valueOf(String.valueOf(v)),
                    String.valueOf(m.get('label')),
                    (pts instanceof Integer || pts instanceof Decimal)
                        ? Integer.valueOf(String.valueOf(pts))
                        : null
                ));
            }
        } catch (Exception e) {
            return new List<Option>();
        }
        return out;
    }

    /** value -> horizon text, for the one supplement flagged as horizon driver. */
    private static Map<String, String> parseHorizons(String jsonStr) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(jsonStr)) {
            return out;
        }
        try {
            for (Object raw : (List<Object>) JSON.deserializeUntyped(jsonStr)) {
                Map<String, Object> m = (Map<String, Object>) raw;
                if (m.get('horizon') != null && m.get('value') != null) {
                    out.put(String.valueOf(m.get('value')), String.valueOf(m.get('horizon')));
                }
            }
        } catch (Exception e) {
            return new Map<String, String>();
        }
        return out;
    }

    private static List<Callout> parseCallouts(String jsonStr) {
        List<Callout> out = new List<Callout>();
        if (String.isBlank(jsonStr)) {
            return out;
        }
        try {
            for (Object raw : (List<Object>) JSON.deserializeUntyped(jsonStr)) {
                Map<String, Object> m = (Map<String, Object>) raw;
                Callout c = new Callout();
                c.pattern    = str(m.get('pattern'));
                c.status     = str(m.get('status'));
                c.severity   = str(m.get('severity'));
                c.category   = str(m.get('category'));
                c.issue      = str(m.get('issue'));
                c.gloss      = str(m.get('gloss'));
                c.workaround = str(m.get('workaround'));
                c.verificationRequired =
                    'true'.equalsIgnoreCase(String.valueOf(m.get('verification_required')));
                if (m.get('manual_steps') instanceof List<Object>) {
                    for (Object step : (List<Object>) m.get('manual_steps')) {
                        c.manualSteps.add(String.valueOf(step));
                    }
                }
                out.add(c);
            }
        } catch (Exception e) {
            return new List<Callout>();
        }
        return out;
    }

    // ---------------------------------------------------------------- loading

    private static List<GTM_Assessment_Pair__mdt> pairRows() {
        if (cachedPairs == null) {
            cachedPairs = pairOverride != null ? pairOverride : [
                SELECT DeveloperName, Source_Key__c, Target_Key__c, Specificity__c,
                       Capability_Posture__c, Source_Posture__c, Target_Posture__c,
                       Posture_Statement__c, Emphasis_Slots__c, Supplement_Set__c,
                       Callouts_JSON__c, Version__c, Active__c
                FROM GTM_Assessment_Pair__mdt
                WHERE Active__c = true
                LIMIT 500
            ];
        }
        return cachedPairs;
    }

    private static Map<String, List<GTM_Assessment_Dimension_Override__mdt>> overridesByPair() {
        if (cachedOverrides == null) {
            cachedOverrides = overrideOverride != null ? overrideOverride : [
                SELECT Pair__c, Dimension__c, Layer__c, New_Key__c, Label__c, Question__c,
                       Options_JSON__c, Max_Attainable__c, Ceiling_Reason__c,
                       Measures__c, Evidence_Prompt__c, Respondent_Hint__c,
                       Instrument__c, Show_When_JSON__c, Variant_Key__c,
                       Variant_Order__c, Active__c
                FROM GTM_Assessment_Dimension_Override__mdt
                WHERE Active__c = true
                ORDER BY Variant_Order__c NULLS FIRST, DeveloperName
                LIMIT 2000
            ];
        }
        Map<String, List<GTM_Assessment_Dimension_Override__mdt>> byPair =
            new Map<String, List<GTM_Assessment_Dimension_Override__mdt>>();
        for (GTM_Assessment_Dimension_Override__mdt o : cachedOverrides) {
            String key = trimmed(o.Pair__c);
            if (String.isBlank(key)) {
                continue;
            }
            if (!byPair.containsKey(key)) {
                byPair.put(key, new List<GTM_Assessment_Dimension_Override__mdt>());
            }
            byPair.get(key).add(o);
        }
        return byPair;
    }

    private static List<GTM_Assessment_Supplement__mdt> supplementRows() {
        if (cachedSupplements == null) {
            cachedSupplements = supplementOverride != null ? supplementOverride : [
                SELECT Set_Key__c, Sort_Order__c, Key__c, Question__c, Options_JSON__c,
                       Scored__c, Index_Key__c, Horizon_Driver__c, Active__c
                FROM GTM_Assessment_Supplement__mdt
                WHERE Active__c = true
                ORDER BY Sort_Order__c NULLS LAST, Key__c
                LIMIT 500
            ];
        }
        return cachedSupplements;
    }

    private static List<GTM_Assessment_Gate__mdt> gateRows() {
        if (cachedGates == null) {
            cachedGates = gateOverride != null ? gateOverride : [
                SELECT Key__c, Predicate_JSON__c, Tier_Qualifier__c, Readout_Block__c,
                       Severity__c, Active__c
                FROM GTM_Assessment_Gate__mdt
                WHERE Active__c = true
                LIMIT 200
            ];
        }
        return cachedGates;
    }

    // ---------------------------------------------------------------- helpers

    private static List<GTM_Assessment_Dimension_Override__mdt> orDefault(
        List<GTM_Assessment_Dimension_Override__mdt> rows
    ) {
        return rows == null ? new List<GTM_Assessment_Dimension_Override__mdt>() : rows;
    }

    private static List<String> splitList(String value) {
        List<String> out = new List<String>();
        if (String.isBlank(value)) {
            return out;
        }
        for (String part : value.split(';')) {
            if (String.isNotBlank(part)) {
                out.add(part.trim());
            }
        }
        return out;
    }

    private static String unwildcard(String key) {
        return ANY_KEY.equals(trimmed(key)) ? null : trimmed(key);
    }

    private static String trimmed(String value) {
        return value == null ? null : value.trim();
    }

    private static String str(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    /** Clears the per-transaction caches. Test-only. */
    @TestVisible
    private static void resetCache() {
        cachedPairs       = null;
        cachedOverrides   = null;
        cachedSupplements = null;
        cachedGates       = null;
    }
}
