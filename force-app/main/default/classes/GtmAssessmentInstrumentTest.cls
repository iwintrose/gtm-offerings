/**
 * UNVERIFIED — there is no Salesforce CLI and no org in the environment this
 * was written in, so nothing here has been compiled or executed. It is written
 * to the same contract as the rest of the suite and should be run before merge.
 *
 * What it is trying to pin down is the set of properties the adaptive layer
 * would be worthless without: the frame never bends, the chain merges in the
 * documented order, a ceiling is visible rather than silent, and a broken pack
 * degrades to base instead of taking the questionnaire with it.
 */
@IsTest
private class GtmAssessmentInstrumentTest {

    private static final String READINESS = 'Readiness';
    private static final String COMPLEXITY = 'Complexity';

    // ---------------------------------------------------------------- setup

    private static GTM_Assessment_Question__mdt question(String key, Integer sortOrder) {
        return new GTM_Assessment_Question__mdt(
            Instrument__c      = READINESS,
            Dimension_Key__c   = key,
            Dimension_Name__c  = key + ' name',
            Measures__c        = key + ' measures',
            Question_Text__c   = key + ' question?',
            Option_1_Label__c  = key + ' one',
            Option_2_Label__c  = key + ' two',
            Option_3_Label__c  = key + ' three',
            Option_4_Label__c  = key + ' four',
            Max_Answer_Value__c = 4,
            Sort_Order__c      = sortOrder,
            Active__c          = true
        );
    }

    /** A base complexity dimension: three options, not four. */
    private static GTM_Assessment_Question__mdt complexityQuestion(String key, Integer sortOrder) {
        return new GTM_Assessment_Question__mdt(
            Instrument__c      = COMPLEXITY,
            Dimension_Key__c   = key,
            Dimension_Name__c  = key + ' name',
            Measures__c        = key + ' measures',
            Question_Text__c   = key + ' question?',
            Option_1_Label__c  = key + ' one',
            Option_2_Label__c  = key + ' two',
            Option_3_Label__c  = key + ' three',
            Max_Answer_Value__c = 3,
            Sort_Order__c      = sortOrder,
            Active__c          = true
        );
    }

    private static void seedBaseWording() {
        List<GTM_Assessment_Question__mdt> rows = new List<GTM_Assessment_Question__mdt>();
        Integer i = 10;
        for (String key : GtmAssessmentScoring.DIMENSIONS) {
            rows.add(question(key, i));
            i += 10;
        }
        for (String key : GtmEstateComplexity.DIMENSIONS) {
            rows.add(complexityQuestion(key, i));
            i += 10;
        }
        GtmAssessmentQuestions.rowOverride = rows;
        GtmAssessmentQuestions.resetCache();
    }

    private static GTM_Assessment_Dimension_Override__mdt complexityOverride(
        String pairKey, String dimension, String layer
    ) {
        GTM_Assessment_Dimension_Override__mdt row = dimOverride(pairKey, dimension, layer);
        row.Instrument__c = COMPLEXITY;
        return row;
    }

    private static GTM_Migration_Platform__mdt platform(String key, String family) {
        return new GTM_Migration_Platform__mdt(
            Platform_Key__c = key,
            Display_Label__c = key,
            Family_Key__c = family,
            Active__c = true
        );
    }

    private static GTM_Assessment_Pair__mdt pair(
        String name, String src, String tgt, Decimal specificity,
        String posture, String sourcePosture, String targetPosture
    ) {
        return new GTM_Assessment_Pair__mdt(
            DeveloperName        = name,
            Source_Key__c        = src,
            Target_Key__c        = tgt,
            Specificity__c       = specificity,
            Capability_Posture__c = posture,
            Source_Posture__c    = sourcePosture,
            Target_Posture__c    = targetPosture,
            Posture_Statement__c = name + ' posture statement',
            Version__c           = '1.0',
            Active__c            = true
        );
    }

    private static void seedPacks() {
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('hubspot', 'inbound_suite'),
            platform('marketo', 'inbound_suite'),
            platform('sfmc_next', 'core_native')
        };
        GtmMigrationPairs.resetCache();

        GtmAssessmentInstrument.pairOverride = new List<GTM_Assessment_Pair__mdt>{
            pair('base', '*', '*', 4, 'interview_only', 'interview_only', 'interview_only'),
            pair('any__mcn', '*', 'sfmc_next', 3, 'interview_only', 'interview_only', 'interview_only'),
            pair('inbound__mcn', 'inbound_suite', 'sfmc_next', 2,
                 'interview_only', 'interview_only', 'interview_only'),
            pair('hubspot__mcn', 'hubspot', 'sfmc_next', 1,
                 'interview_only', 'interview_only', 'interview_only')
        };
        GtmAssessmentInstrument.overrideOverride = new List<GTM_Assessment_Dimension_Override__mdt>();
        GtmAssessmentInstrument.supplementOverride = new List<GTM_Assessment_Supplement__mdt>();
        GtmAssessmentInstrument.gateOverride = new List<GTM_Assessment_Gate__mdt>();
        GtmAssessmentInstrument.resetCache();
        seedBaseWording();
    }

    private static GTM_Assessment_Dimension_Override__mdt dimOverride(
        String pairKey, String dimension, String layer
    ) {
        return new GTM_Assessment_Dimension_Override__mdt(
            Pair__c      = pairKey,
            Dimension__c = dimension,
            Layer__c     = layer,
            Active__c    = true
        );
    }

    private static String optionsJson(Integer count) {
        List<Object> out = new List<Object>();
        for (Integer i = 1; i <= count; i++) {
            out.add(new Map<String, Object>{ 'value' => i, 'label' => 'option ' + i });
        }
        return JSON.serialize(out);
    }

    // ------------------------------------------------------------ the frame

    @IsTest
    static void everyPairResolvesToExactlyEightSlots() {
        seedPacks();
        for (String target : new List<String>{ 'sfmc_next', 'nothing_configured', null }) {
            for (String source : new List<String>{ 'hubspot', 'marketo', 'eloqua', null }) {
                GtmAssessmentInstrument.Pack pack =
                    GtmAssessmentInstrument.resolve(source, target);
                System.assertEquals(
                    8, pack.slots.size(),
                    'The frame is eight slots for every pair; ' + source + '->' + target +
                    ' resolved to ' + pack.slots.size()
                );
                System.assertEquals(
                    8, new Set<String>(pack.dimensionKeys()).size(),
                    'Eight DISTINCT keys, or two slots would collapse into one score'
                );
            }
        }
    }

    @IsTest
    static void slotsOneAndEightAreNotSubstitutable() {
        seedPacks();
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        System.assertEquals(false, pack.slots[0].substitutable,
            'Slot 1 is the invariant spine and must never be substitutable');
        System.assertEquals(false, pack.slots[7].substitutable,
            'Slot 8 is the invariant spine and must never be substitutable');
        for (Integer i = 1; i < 7; i++) {
            System.assertEquals(true, pack.slots[i].substitutable,
                'Slot ' + (i + 1) + ' should be substitutable');
        }
    }

    @IsTest
    static void substitutionOnAPinnedSlotIsRefused() {
        seedPacks();
        GTM_Assessment_Dimension_Override__mdt bad =
            dimOverride('hubspot__mcn', GtmAssessmentScoring.DIMENSIONS[0], 'substitute');
        bad.New_Key__c = 'something_else';
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ bad };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        System.assertEquals(
            GtmAssessmentScoring.DIMENSIONS[0], pack.slots[0].key,
            'A hand-edited metadata row must not be able to substitute a pinned slot; ' +
            'the build script is the first lock and the resolver is the second'
        );
    }

    // -------------------------------------------------------- the chain

    @IsTest
    static void mostSpecificPackWinsAndTheChainIsRecorded() {
        seedPacks();
        String dim = GtmAssessmentScoring.DIMENSIONS[2];

        GTM_Assessment_Dimension_Override__mdt targetOnly = dimOverride('any__mcn', dim, 'reword');
        targetOnly.Question__c = 'target-only question';
        targetOnly.Evidence_Prompt__c = 'target-only prompt';

        GTM_Assessment_Dimension_Override__mdt family = dimOverride('inbound__mcn', dim, 'reword');
        family.Question__c = 'family question';

        GTM_Assessment_Dimension_Override__mdt exact = dimOverride('hubspot__mcn', dim, 'recalibrate');
        exact.Question__c = 'exact question';

        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ targetOnly, family, exact };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        GtmAssessmentInstrument.Slot slot = pack.slotFor(dim);
        System.assertEquals('exact question', slot.question, 'Exact pair wins the question');
        System.assertEquals('recalibrate', slot.layer, 'Exact pair wins the layer');
        System.assertEquals(
            'target-only prompt', slot.evidencePrompt,
            'Shallow merge is per FIELD: a field the more specific packs left null ' +
            'inherits rather than clearing'
        );
        System.assertEquals(
            new List<String>{ 'base', 'any__mcn', 'inbound__mcn', 'hubspot__mcn' },
            pack.resolutionChain,
            'The chain is recorded least specific first, which is the merge order'
        );
        System.assertEquals('hubspot__mcn', pack.pairKey);
    }

    @IsTest
    static void familyPackAppliesToASiblingSourceWithNoExactPack() {
        seedPacks();
        String dim = GtmAssessmentScoring.DIMENSIONS[2];
        GTM_Assessment_Dimension_Override__mdt family = dimOverride('inbound__mcn', dim, 'reword');
        family.Question__c = 'family question';
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ family };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('marketo', 'sfmc_next');
        System.assertEquals('family question', pack.slotFor(dim).question,
            'marketo shares the inbound_suite family, so the family pack applies');
        System.assertEquals('inbound__mcn', pack.pairKey);
    }

    @IsTest
    static void undecidedTargetResolvesToBaseWithANote() {
        seedPacks();
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', null);
        System.assertEquals('base', pack.pairKey, 'No target named resolves to base');
        System.assert(String.isNotBlank(pack.resolutionNote),
            'A base resolution caused by an undecided target has to say so on the readout');
    }

    // ------------------------------------------------------------- ceilings

    @IsTest
    static void aCeilingRendersTheExcludedOptionRatherThanRemovingIt() {
        seedPacks();
        String dim = GtmAssessmentScoring.DIMENSIONS[1];
        GTM_Assessment_Dimension_Override__mdt capped = dimOverride('hubspot__mcn', dim, 'recalibrate');
        capped.Options_JSON__c   = optionsJson(4);
        capped.Max_Attainable__c = 3;
        capped.Ceiling_Reason__c = 'no connector ships today';
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ capped };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Slot slot =
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next').slotFor(dim);

        System.assertEquals(4, slot.options.size(),
            'All four options still render -- a prospect must be able to SEE that a 4 ' +
            'was not on offer, or the ceiling is indistinguishable from a rigged scale');
        System.assertEquals(3, slot.maxAttainable);
        System.assertEquals(true, slot.options[2].available, 'A 3 is still on offer');
        System.assertEquals(false, slot.options[3].available, 'The 4 is not');
        System.assertEquals('no connector ships today', slot.options[3].unavailableReason,
            'And the reason is shown next to it');
    }

    // ------------------------------------------------------------- fallback

    @IsTest
    static void noPackMetadataAtAllStillYieldsTheBaseEight() {
        seedBaseWording();
        GtmAssessmentInstrument.pairOverride = new List<GTM_Assessment_Pair__mdt>();
        GtmAssessmentInstrument.overrideOverride = new List<GTM_Assessment_Dimension_Override__mdt>();
        GtmAssessmentInstrument.supplementOverride = new List<GTM_Assessment_Supplement__mdt>();
        GtmAssessmentInstrument.gateOverride = new List<GTM_Assessment_Gate__mdt>();
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        System.assertEquals(8, pack.slots.size(),
            'An unpopulated config table is a deployment state, not a product judgement');
        System.assertEquals(GtmAssessmentScoring.DIMENSIONS, pack.dimensionKeys());
    }

    @IsTest
    static void unparseableOptionsJsonLeavesTheInheritedOptionsAlone() {
        seedPacks();
        String dim = GtmAssessmentScoring.DIMENSIONS[3];
        GTM_Assessment_Dimension_Override__mdt broken = dimOverride('hubspot__mcn', dim, 'recalibrate');
        broken.Options_JSON__c = '{not json at all';
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ broken };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Slot slot =
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next').slotFor(dim);
        System.assertEquals(4, slot.options.size(),
            'A malformed override must not be able to empty a slot of its answers');
    }

    // ----------------------------------------------------------- provenance

    @IsTest
    static void estateFiguresAreIllustrativeUnlessTheSourceIsInstrumented() {
        seedPacks();
        GtmAssessmentInstrument.pairOverride = new List<GTM_Assessment_Pair__mdt>{
            pair('base', '*', '*', 4, 'interview_only', 'interview_only', 'interview_only'),
            // Instrumented SOURCE, unverified TARGET -- the SFMC to MCN shape.
            pair('sfmc__mcn', 'sfmc', 'sfmc_next', 1,
                 'interview_only', 'instrumented', 'interview_only')
        };
        GtmMigrationPairs.platformOverride = new List<GTM_Migration_Platform__mdt>{
            platform('sfmc', 'enterprise_ma'), platform('sfmc_next', 'core_native')
        };
        GtmMigrationPairs.resetCache();
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('sfmc', 'sfmc_next');
        System.assertEquals('interview_only', pack.posture,
            'The headline posture is the weaker end');
        System.assertEquals(
            false, pack.getEstateFiguresIllustrative(),
            'Estate figures come from reading the SOURCE. An instrumented source means ' +
            'measured counts, even when the target is unverified -- flattening the two ' +
            'would misreport one of them'
        );
    }

    @IsTest
    static void calloutsAccumulateDownTheChainAndTheSpecificPackWinsACollision() {
        seedPacks();
        List<GTM_Assessment_Pair__mdt> rows = GtmAssessmentInstrument.pairOverride;
        for (GTM_Assessment_Pair__mdt row : rows) {
            if (row.DeveloperName == 'any__mcn') {
                row.Callouts_JSON__c = JSON.serialize(new List<Object>{
                    new Map<String, Object>{ 'pattern' => 'shared', 'gloss' => 'target-level',
                                             'verification_required' => true },
                    new Map<String, Object>{ 'pattern' => 'target_only', 'gloss' => 'still true' }
                });
            }
            if (row.DeveloperName == 'hubspot__mcn') {
                row.Callouts_JSON__c = JSON.serialize(new List<Object>{
                    new Map<String, Object>{ 'pattern' => 'shared', 'gloss' => 'pair-level' },
                    new Map<String, Object>{ 'pattern' => 'hubdb_dependency',
                                             'severity' => 'blocker' }
                });
            }
        }
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        Map<String, GtmAssessmentInstrument.Callout> byPattern =
            new Map<String, GtmAssessmentInstrument.Callout>();
        for (GtmAssessmentInstrument.Callout c : pack.callouts) {
            byPattern.put(c.pattern, c);
        }
        System.assertEquals(3, byPattern.size(),
            'Target-level gaps stay true when a pair adds its own; replacing the list ' +
            'wholesale would make every pair restate its target, and one would forget');
        System.assertEquals('pair-level', byPattern.get('shared').gloss,
            'The more specific pack wins a collision on the same pattern');
        System.assert(byPattern.containsKey('target_only'));
        System.assert(byPattern.containsKey('hubdb_dependency'));
    }

    // ----------------------------------------------------------- branching

    private static GTM_Assessment_Dimension_Override__mdt variant(
        String pairKey, String dimension, String variantKey, Decimal order, String showWhen
    ) {
        GTM_Assessment_Dimension_Override__mdt v = dimOverride(pairKey, dimension, 'substitute');
        v.Variant_Key__c    = variantKey;
        v.Variant_Order__c  = order;
        v.Show_When_JSON__c = showWhen;
        v.Question__c       = variantKey + ' question?';
        return v;
    }

    /**
     * The load-bearing property of the whole branching feature, asserted first:
     * whatever the answers, the pack still resolves to eight slots with eight
     * distinct keys. A branch chooses WHICH question fills a slot; it can never
     * take the slot away, so two respondents who were asked different questions
     * are still both scored out of 32.
     */
    @IsTest
    static void branchingNeverChangesHowManySlotsAreAsked() {
        seedPacks();
        String earlier = GtmAssessmentScoring.DIMENSIONS[1];
        String branched = GtmAssessmentScoring.DIMENSIONS[6];

        GTM_Assessment_Dimension_Override__mdt v = variant(
            'hubspot__mcn', branched, 'owned_elsewhere', 10,
            '{"all":[{"field":"' + earlier + '","op":"lte","value":2}]}'
        );
        v.New_Key__c = 'consent_ownership_outside_platform';
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ v };
        GtmAssessmentInstrument.resetCache();

        for (Integer answer = 1; answer <= 4; answer++) {
            GtmAssessmentInstrument.Pack pack =
                GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
            pack = GtmAssessmentInstrument.applyBranches(
                pack, new Map<String, Integer>{ earlier => answer }
            );
            System.assertEquals(8, pack.slots.size(),
                'Eight slots whatever the answer to slot 2 was (' + answer + ')');
            System.assertEquals(8, new Set<String>(pack.dimensionKeys()).size(),
                'And eight DISTINCT keys, or two answers land in one score');
            System.assertEquals(8, pack.branchPath().size(),
                'Every slot names the variant that filled it, branch or default');
        }
    }

    @IsTest
    static void aBranchFiresOnAnEarlierAnswerAndTheDefaultCatchesEverythingElse() {
        seedPacks();
        String earlier = GtmAssessmentScoring.DIMENSIONS[1];
        String branched = GtmAssessmentScoring.DIMENSIONS[6];

        GTM_Assessment_Dimension_Override__mdt v = variant(
            'hubspot__mcn', branched, 'owned_elsewhere', 10,
            '{"all":[{"field":"' + earlier + '","op":"lte","value":2}]}'
        );
        v.New_Key__c = 'consent_ownership_outside_platform';
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ v };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack fired = GtmAssessmentInstrument.applyBranches(
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next'),
            new Map<String, Integer>{ earlier => 1 }
        );
        System.assertEquals('owned_elsewhere', fired.slots[6].variantKey);
        System.assertEquals('consent_ownership_outside_platform', fired.slots[6].key,
            'The branch substitutes the storage key too');
        System.assertEquals('owned_elsewhere question?', fired.slots[6].question);

        GtmAssessmentInstrument.Pack notFired = GtmAssessmentInstrument.applyBranches(
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next'),
            new Map<String, Integer>{ earlier => 4 }
        );
        System.assertEquals(GtmAssessmentInstrument.DEFAULT_VARIANT, notFired.slots[6].variantKey);
        System.assertEquals(branched, notFired.slots[6].key);
    }

    @IsTest
    static void anUnansweredDependencyLeavesTheDefaultStanding() {
        seedPacks();
        String earlier = GtmAssessmentScoring.DIMENSIONS[1];
        String branched = GtmAssessmentScoring.DIMENSIONS[6];
        GTM_Assessment_Dimension_Override__mdt v = variant(
            'hubspot__mcn', branched, 'owned_elsewhere', 10,
            '{"all":[{"field":"' + earlier + '","op":"lte","value":2}]}'
        );
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ v };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.applyBranches(
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next'),
            new Map<String, Integer>()
        );
        System.assertEquals(GtmAssessmentInstrument.DEFAULT_VARIANT, pack.slots[6].variantKey,
            'Unknown data must never be able to empty or re-point a slot');
        System.assertEquals(8, pack.slots.size());
    }

    @IsTest
    static void variantsAreEvaluatedInAuthorOrderAndTheFirstMatchWins() {
        seedPacks();
        String earlier = GtmAssessmentScoring.DIMENSIONS[1];
        String branched = GtmAssessmentScoring.DIMENSIONS[6];
        // Both predicates are true for an answer of 1; the ordering decides.
        GTM_Assessment_Dimension_Override__mdt first = variant(
            'hubspot__mcn', branched, 'narrow', 10,
            '{"all":[{"field":"' + earlier + '","op":"eq","value":1}]}'
        );
        GTM_Assessment_Dimension_Override__mdt second = variant(
            'hubspot__mcn', branched, 'broad', 20,
            '{"all":[{"field":"' + earlier + '","op":"lte","value":3}]}'
        );
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ first, second };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.applyBranches(
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next'),
            new Map<String, Integer>{ earlier => 1 }
        );
        System.assertEquals('narrow', pack.slots[6].variantKey,
            'First matching variant wins; "whichever row the query returned first" ' +
            'is not an answer an author can reason about');
    }

    @IsTest
    static void aPinnedSlotCannotBeBranchedAwayEither() {
        seedPacks();
        String pinned = GtmAssessmentScoring.DIMENSIONS[0];
        GTM_Assessment_Dimension_Override__mdt v = variant(
            'hubspot__mcn', pinned, 'sneaky', 10,
            '{"all":[{"field":"target","op":"eq","value":"sfmc_next"}]}'
        );
        v.New_Key__c = 'something_else';
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ v };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.applyBranches(
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next'),
            new Map<String, Integer>()
        );
        System.assertEquals(pinned, pack.slots[0].key,
            'The spine holds against a branch exactly as it holds against a substitution');
    }

    @IsTest
    static void applyBranchesIsIdempotent() {
        seedPacks();
        String earlier = GtmAssessmentScoring.DIMENSIONS[1];
        String branched = GtmAssessmentScoring.DIMENSIONS[6];
        GTM_Assessment_Dimension_Override__mdt v = variant(
            'hubspot__mcn', branched, 'owned_elsewhere', 10,
            '{"all":[{"field":"' + earlier + '","op":"lte","value":2}]}'
        );
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ v };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        Map<String, Integer> answers = new Map<String, Integer>{ earlier => 1 };
        pack = GtmAssessmentInstrument.applyBranches(pack, answers);
        pack = GtmAssessmentInstrument.applyBranches(pack, answers);
        System.assertEquals(8, pack.slots.size(),
            'Running it twice must not compound: the questionnaire re-runs it on ' +
            'every answer and the server runs it again on submit');
        System.assertEquals('owned_elsewhere', pack.slots[6].variantKey);

        // And re-running it with a DIFFERENT answer re-decides from the same
        // authored set rather than from whatever last won.
        pack = GtmAssessmentInstrument.applyBranches(
            pack, new Map<String, Integer>{ earlier => 4 }
        );
        System.assertEquals(GtmAssessmentInstrument.DEFAULT_VARIANT, pack.slots[6].variantKey);
    }

    // -------------------------------------------------------- derived max

    @IsTest
    static void theDerivedMaximumIsTheFrameMaximum() {
        seedPacks();
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        System.assertEquals(
            GtmAssessmentScoring.MAX_TOTAL_SCORE, pack.maxTotal(),
            'Derived from the authored points, and it must come to the same 32 the ' +
            'four bands were calibrated against'
        );
    }

    @IsTest
    static void aCeilingDoesNotShrinkTheDerivedMaximum() {
        seedPacks();
        String dim = GtmAssessmentScoring.DIMENSIONS[1];
        GTM_Assessment_Dimension_Override__mdt capped = dimOverride('hubspot__mcn', dim, 'recalibrate');
        capped.Max_Attainable__c = 3;
        capped.Ceiling_Reason__c = 'no connector ships today';
        capped.Options_JSON__c = optionsJson(4);
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ capped };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        System.assertEquals(
            GtmAssessmentScoring.MAX_TOTAL_SCORE, pack.maxTotal(),
            'A ceiling is a handicap on a hostile pair, not a smaller instrument. ' +
            'hubspot__mcn caps two slots and is still scored out of 32, which is ' +
            'precisely what makes the cap cost something.'
        );
    }

    @IsTest
    static void authoredPointsAreReadFromTheOptionsJson() {
        seedPacks();
        String dim = GtmAssessmentScoring.DIMENSIONS[2];
        GTM_Assessment_Dimension_Override__mdt row = dimOverride('hubspot__mcn', dim, 'recalibrate');
        row.Options_JSON__c = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'value' => 1, 'label' => 'a', 'points' => 1 },
            new Map<String, Object>{ 'value' => 2, 'label' => 'b', 'points' => 1 },
            new Map<String, Object>{ 'value' => 3, 'label' => 'c', 'points' => 3 },
            new Map<String, Object>{ 'value' => 4, 'label' => 'd', 'points' => 4 }
        });
        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ row };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Slot slot =
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next').slotFor(dim);
        System.assertEquals(1, slot.pointsForValue(2),
            'Non-linear points: "these two answers are equally bad" is a thing an ' +
            'author is allowed to say');
        System.assertEquals(4, slot.topPoints(), 'And the slot is still worth 4 at the top');
        System.assertEquals(null, slot.pointsForValue(9),
            'An option the slot does not have has no worth at all');
    }

    @IsTest
    static void anOptionWithNoAuthoredPointsIsWorthItsValue() {
        seedPacks();
        GtmAssessmentInstrument.Slot slot =
            GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next').slots[0];
        for (Integer v = 1; v <= 4; v++) {
            System.assertEquals(v, slot.pointsForValue(v),
                'Existing content must score exactly as it did before points existed');
        }
    }

    // ------------------------------------------------- the second axis

    @IsTest
    static void everyPackResolvesToSixComplexityDimensions() {
        seedPacks();
        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        System.assertEquals(
            GtmEstateComplexity.DIMENSIONS.size(), pack.complexityDimensions.size(),
            'Six, on every pair, for the same reason the readiness half is eight: ' +
            'GtmEstateComplexity prints "out of 18" and a pack that resolved to ' +
            'five would print it anyway'
        );
        System.assertEquals(
            GtmEstateComplexity.DIMENSIONS, pack.complexityKeys(),
            'Unadapted, the resolved keys are the frame keys'
        );
        System.assertEquals(
            6, GtmAssessmentInstrument.basePack().complexityDimensions.size(),
            'Including the pack every chain terminates at'
        );
    }

    @IsTest
    static void aPairRewordsAComplexityDimensionWithoutChangingTheAxis() {
        seedPacks();
        String dim = GtmEstateComplexity.DIMENSIONS[0];

        GTM_Assessment_Dimension_Override__mdt row = complexityOverride('hubspot__mcn', dim, 'recalibrate');
        row.Label__c        = 'Workflow Footprint';
        row.Question__c     = 'How many workflows are switched on?';
        row.Measures__c     = 'How many automated programmes are live';
        row.Respondent_Hint__c = 'Your workflows list shows the active count.';
        row.Options_JSON__c = optionsJson(3);

        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ row };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        GtmAssessmentInstrument.ComplexityDimension d = pack.complexityDimensions[0];
        System.assertEquals('Workflow Footprint', d.label);
        System.assertEquals('How many workflows are switched on?', d.question);
        System.assertEquals('Your workflows list shows the active count.', d.respondentHint);
        System.assertEquals(3, d.options.size(), 'The complexity scale is 1-3 and stays 1-3');
        System.assertEquals(
            GtmEstateComplexity.DIMENSIONS.size(), pack.complexityDimensions.size(),
            'Adapting the words never changes how many there are'
        );
        System.assertEquals(
            8, pack.slots.size(),
            'And it never reaches the readiness half'
        );
    }

    @IsTest
    static void aComplexityRowNeverLandsOnAReadinessSlot() {
        seedPacks();
        // Same key on both axes would be the worst possible authoring slip: an
        // override meant for the size axis silently rewriting a scored slot.
        // Instrument__c is what keeps the two apart, and a blank one means
        // Readiness so nothing authored before this change moved.
        String readinessDim = GtmAssessmentScoring.DIMENSIONS[2];
        GTM_Assessment_Dimension_Override__mdt stray =
            complexityOverride('hubspot__mcn', readinessDim, 'reword');
        stray.Question__c = 'should reach nothing';

        GtmAssessmentInstrument.overrideOverride =
            new List<GTM_Assessment_Dimension_Override__mdt>{ stray };
        GtmAssessmentInstrument.resetCache();

        GtmAssessmentInstrument.Pack pack = GtmAssessmentInstrument.resolve('hubspot', 'sfmc_next');
        System.assertNotEquals(
            'should reach nothing', pack.slotFor(readinessDim).question,
            'A row marked Complexity must not be merged onto a readiness slot'
        );
        for (GtmAssessmentInstrument.ComplexityDimension d : pack.complexityDimensions) {
            System.assertNotEquals(
                'should reach nothing', d.question,
                'and it matches no complexity dimension either, because there is no ' +
                'complexity dimension by that name'
            );
        }
    }

    @IsTest
    static void getFrameServesTheDerivedNumbersRatherThanTypedOnes() {
        GtmAssessmentInstrument.Frame f = GtmAssessmentInstrument.getFrame();
        System.assertEquals(GtmAssessmentScoring.MAX_TOTAL_SCORE, f.maxTotal);
        System.assertEquals(GtmAssessmentScoring.MIN_TOTAL_SCORE, f.minTotal);
        System.assertEquals(4, f.bands.size(), 'Four bands, and the client holds none of them');
        System.assertEquals(GtmAssessmentScoring.MIN_TOTAL_SCORE, f.bands[0].lowest);
        System.assertEquals(GtmAssessmentScoring.MAX_TOTAL_SCORE, f.bands[3].highest);
    }
}
