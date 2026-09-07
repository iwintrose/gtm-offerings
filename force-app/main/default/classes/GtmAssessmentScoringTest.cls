@isTest
private class GtmAssessmentScoringTest {

    /** Every dimension answered at the same value. */
    private static Map<String, Integer> allAt(Integer value) {
        Map<String, Integer> answers = new Map<String, Integer>();
        for (String dimension : GtmAssessmentScoring.DIMENSIONS) {
            answers.put(dimension, value);
        }
        return answers;
    }

    /** Every dimension at `value`, then the named ones overridden. */
    private static Map<String, Integer> allAtExcept(Integer value, Map<String, Integer> overrides) {
        Map<String, Integer> answers = allAt(value);
        answers.putAll(overrides);
        return answers;
    }

    private static GtmAssessmentScoring.PairEligibility unsupported(String reason) {
        return new GtmAssessmentScoring.PairEligibility(false, reason);
    }

    private static GtmAssessmentScoring.PairEligibility supported() {
        return new GtmAssessmentScoring.PairEligibility(true, null);
    }

    // ------------------------------------------------------------- the scale

    @isTest
    static void thereAreEightScoredDimensionsWorthThirtyTwoPoints() {
        // The invariant the whole feature hangs on: 8 dimensions, 4 points
        // each, 32 maximum -- not the 10/40 an earlier fixture assumed.
        Assert.areEqual(8, GtmAssessmentScoring.DIMENSIONS.size(), 'There are eight scored dimensions');
        Assert.areEqual(4, GtmAssessmentScoring.MAX_ANSWER_VALUE);
        Assert.areEqual(32, GtmAssessmentScoring.MAX_TOTAL_SCORE, 'Eight dimensions at four points is 32');
        Assert.areEqual(8, GtmAssessmentScoring.MIN_TOTAL_SCORE);

        Set<String> unique = new Set<String>(GtmAssessmentScoring.DIMENSIONS);
        Assert.areEqual(8, unique.size(), 'Dimension keys must be distinct');
    }

    @isTest
    static void theDimensionsAreTheAgreedMigrationOnesNotTheInheritedMaturityOnes() {
        // The old set came from a marketing-maturity survey and measured the
        // wrong thing. Naming both halves here so a silent revert is loud.
        Set<String> actual = new Set<String>(GtmAssessmentScoring.DIMENSIONS);
        for (String expected : new List<String>{
            'estate_scale', 'source_access', 'orchestration_portability',
            'content_portability', 'data_model_readiness', 'integration_containment',
            'consent_portability', 'decision_readiness'
        }) {
            Assert.isTrue(actual.contains(expected), 'Missing agreed dimension: ' + expected);
        }
        for (String retired : new List<String>{
            'data_foundation', 'segmentation', 'campaign_orchestration',
            'content_operations', 'lifecycle_automation', 'measurement_analytics',
            'governance_compliance', 'ai_personalization'
        }) {
            Assert.isFalse(actual.contains(retired), 'Retired maturity dimension is back: ' + retired);
        }
    }

    @isTest
    static void aPerfectQuestionnaireScoresThirtyTwoAndFastTracks() {
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', allAt(4));
        Assert.areEqual(32, scored.total);
        Assert.areEqual(GtmAssessmentScoring.TIER_FAST_TRACK, scored.tier);
        Assert.areEqual(8, scored.sectionScores.size());
        Assert.isFalse(scored.advisory);
        Assert.isFalse(scored.cappedByAccessGate);
    }

    @isTest
    static void aFloorQuestionnaireScoresEight() {
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', allAt(1));
        Assert.areEqual(8, scored.total);
        Assert.areEqual(GtmAssessmentScoring.TIER_DISCOVERY_FIRST, scored.tier);
    }

    // ------------------------------------------------------------- the bands

    @isTest
    static void tierBandsCoverTheWholeRangeWithNoGapOrOverlap() {
        Assert.areEqual('Discovery First',   GtmAssessmentScoring.tierFor(8));
        Assert.areEqual('Discovery First',   GtmAssessmentScoring.tierFor(14));
        Assert.areEqual('Prep Required',     GtmAssessmentScoring.tierFor(15));
        Assert.areEqual('Prep Required',     GtmAssessmentScoring.tierFor(20));
        Assert.areEqual('Accelerator-Ready', GtmAssessmentScoring.tierFor(21));
        Assert.areEqual('Accelerator-Ready', GtmAssessmentScoring.tierFor(26));
        Assert.areEqual('Fast-Track',        GtmAssessmentScoring.tierFor(27));
        Assert.areEqual('Fast-Track',        GtmAssessmentScoring.tierFor(32));
        Assert.isNull(GtmAssessmentScoring.tierFor(null), 'No score means no tier, not a default tier');
    }

    @isTest
    static void everyTierIsAValidPicklistValue() {
        // Assessment_Tier__c is a restricted picklist, so a tier this class
        // invents would fail the insert in GtmAssessmentRequestController --
        // and it fails inside a best-effort catch, so it would silently lose
        // the whole assessment record rather than surfacing.
        Set<String> allowed = new Set<String>{
            'Discovery First', 'Prep Required', 'Accelerator-Ready', 'Fast-Track'
        };
        Assert.areEqual(allowed, new Set<String>(GtmAssessmentScoring.TIERS));
        for (Integer total = 0; total <= 40; total++) {
            Assert.isTrue(
                allowed.contains(GtmAssessmentScoring.tierFor(total)),
                'Unexpected tier for total ' + total + ': ' + GtmAssessmentScoring.tierFor(total)
            );
        }
    }

    @isTest
    static void theRetiredMaturityLabelsAreGoneEntirely() {
        Set<String> retired = new Set<String>{ 'Foundational', 'Developing', 'Advanced', 'AI-Ready' };
        for (Integer total = 0; total <= 40; total++) {
            Assert.isFalse(
                retired.contains(GtmAssessmentScoring.tierFor(total)),
                'A retired maturity label came back for total ' + total
            );
        }
    }

    // ------------------------------------------------------ the access gate

    @isTest
    static void noSourceAccessCapsAPerfectScoreAtDiscoveryFirst() {
        // 4s everywhere except access. The total is 29 -- Fast-Track territory
        // -- and it must still come back Discovery First, because there is no
        // offering to run without an extract.
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
            allAtExcept(4, new Map<String, Integer>{ 'source_access' => 1 })
        );

        Assert.areEqual(29, scored.total, 'The score itself is not altered by the gate');
        Assert.areEqual('Fast-Track', GtmAssessmentScoring.tierFor(scored.total),
            'The raw band really is the top one -- the gate is what overrides it');
        Assert.areEqual(GtmAssessmentScoring.TIER_DISCOVERY_FIRST, scored.tier);
        Assert.isTrue(scored.cappedByAccessGate);
        Assert.isFalse(scored.advisory, 'Capped is not the same as advisory: Discovery First is sellable');
    }

    @isTest
    static void theAccessGateFiresOnlyAtTheFloor() {
        for (Integer accessValue : new List<Integer>{ 2, 3, 4 }) {
            GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
                allAtExcept(4, new Map<String, Integer>{ 'source_access' => accessValue })
            );
            Assert.isFalse(scored.cappedByAccessGate,
                'source_access ' + accessValue + ' must not trip the gate');
            Assert.areEqual(GtmAssessmentScoring.tierFor(scored.total), scored.tier);
        }
    }

    @isTest
    static void anUnansweredOrOutOfRangeAccessQuestionDoesNotTripTheGate() {
        // A dropped answer is unanswered, and an unanswered access question is
        // not evidence that access is missing.
        Map<String, Integer> noAccessAnswer = allAt(4);
        noAccessAnswer.remove('source_access');
        Assert.isFalse(GtmAssessmentScoring.score('migration-accelerator', noAccessAnswer).cappedByAccessGate);

        GtmAssessmentScoring.Score outOfRange = GtmAssessmentScoring.score('migration-accelerator', 
            allAtExcept(4, new Map<String, Integer>{ 'source_access' => 0 })
        );
        Assert.isFalse(outOfRange.cappedByAccessGate, 'A dropped 0 is not an answer of 1');
    }

    // ----------------------------------------------- the unsupported-pair gate

    @isTest
    static void anUnsupportedPairSuppressesTheTierEntirely() {
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
            allAt(4), unsupported('Adobe Campaign is not a source we can extract from.')
        );

        Assert.areEqual(32, scored.total, 'The score survives -- it is still useful input');
        Assert.isNull(scored.tier, 'A tier here would be a promise the offering cannot keep');
        Assert.isTrue(scored.advisory);
        Assert.areEqual('Adobe Campaign is not a source we can extract from.', scored.advisoryReason);
        Assert.isNotNull(scored.sectionScoresJson, 'The breakdown survives too');
    }

    @isTest
    static void anUnsupportedPairBeatsTheAccessGateToo() {
        // Both overrides fire. Suppression wins: there is no band to cap.
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
            allAtExcept(4, new Map<String, Integer>{ 'source_access' => 1 }),
            unsupported(null)
        );
        Assert.isNull(scored.tier);
        Assert.isTrue(scored.advisory);
        Assert.isTrue(scored.cappedByAccessGate, 'The cap still happened; it just has nothing to show');
        Assert.isNotNull(scored.advisoryReason, 'A blank configured reason still yields a default one');
    }

    @isTest
    static void anUnsupportedPairIsFlaggedEvenWhenNothingWasScored() {
        // Nothing to band, but a rep still has to be told not to scope it.
        GtmAssessmentScoring.Score scored =
            GtmAssessmentScoring.score('migration-accelerator', new Map<String, Integer>(), unsupported('Nope.'));
        Assert.isFalse(scored.hasAnswers);
        Assert.isNull(scored.total);
        Assert.isTrue(scored.advisory);
        Assert.areEqual('Nope.', scored.advisoryReason);
    }

    @isTest
    static void aSupportedOrUnevaluatedPairLeavesTheTierAlone() {
        for (GtmAssessmentScoring.PairEligibility pair : new List<GtmAssessmentScoring.PairEligibility>{
            null,
            new GtmAssessmentScoring.PairEligibility(),  // not evaluated
            supported()
        }) {
            GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', allAt(4), pair);
            Assert.isFalse(scored.advisory);
            Assert.areEqual(GtmAssessmentScoring.TIER_FAST_TRACK, scored.tier);
            Assert.isNull(scored.advisoryReason);
        }
    }

    // ------------------------------------------------------- the annotation

    @isTest
    static void bothPortabilityDimensionsAtTheFloorRaiseTheRebuildFlag() {
        // Deliberately at a HIGH total: the whole point of the annotation is
        // that it is true even when the headline number looks good.
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
            allAtExcept(4, new Map<String, Integer>{
                'orchestration_portability' => 1,
                'content_portability'       => 1
            })
        );

        Assert.areEqual(26, scored.total);
        Assert.areEqual(GtmAssessmentScoring.TIER_ACCELERATOR_READY, scored.tier,
            'The annotation must not move the band');
        Assert.areEqual(1, scored.annotations.size());
        Assert.areEqual(GtmAssessmentScoring.FLAG_HIGH_REBUILD_RATIO, scored.annotations[0].code);
        Assert.isTrue(scored.annotations[0].message.contains('C/D'));
        Assert.isTrue(scored.annotationsJson.contains('high_rebuild_ratio'));
    }

    @isTest
    static void oneDimensionAtTheFloorIsNotEnoughToRaiseIt() {
        for (String only : new List<String>{ 'orchestration_portability', 'content_portability' }) {
            GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
                allAtExcept(4, new Map<String, Integer>{ only => 1 })
            );
            Assert.areEqual(0, scored.annotations.size(), only + ' alone must not flag');
            Assert.isNull(scored.annotationsJson, 'No annotations means null, not "[]"');
        }
    }

    // ------------------------------------------------------- untrusted input

    @isTest
    static void unknownDimensionsCannotAddToTheScore() {
        Map<String, Integer> answers = allAt(1);
        answers.put('invented_dimension', 4);
        answers.put('another_one', 4);
        answers.put('estate_scale_bonus', 4);

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', answers);

        Assert.areEqual(8, scored.total, 'Only the eight real dimensions count');
        Assert.areEqual(8, scored.sectionScores.size());
        Assert.isFalse(scored.sectionScores.containsKey('invented_dimension'));
        Assert.isFalse(scored.sectionScoresJson.contains('invented_dimension'));
    }

    @isTest
    static void outOfRangeAnswersAreDroppedNotClamped() {
        // Both directions matter. Clamping 999 down to 4 would credit an
        // answer the prospect never gave; clamping 0 up to 1 would do the same
        // at the bottom. Dropping is the only reading that adds nothing.
        Map<String, Integer> answers = new Map<String, Integer>{
            'estate_scale'              => 4,
            'source_access'             => 999,
            'orchestration_portability' => 0,
            'content_portability'       => -5,
            'data_model_readiness'      => null
        };

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', answers);

        Assert.areEqual(4, scored.total, 'Only the one in-range answer scores');
        Assert.areEqual(1, scored.sectionScores.size());
        Assert.areEqual(4, scored.sectionScores.get('estate_scale'));
    }

    @isTest
    static void aPartiallyAnsweredQuestionnaireScoresOnlyWhatWasAnswered() {
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
            new Map<String, Integer>{ 'estate_scale' => 3, 'source_access' => 2 }
        );
        Assert.areEqual(5, scored.total);
        Assert.areEqual(GtmAssessmentScoring.TIER_DISCOVERY_FIRST, scored.tier);
        Assert.areEqual(2, scored.sectionScores.size());
    }

    @isTest
    static void nothingAnsweredScoresToNullsRatherThanZero() {
        // "Not assessed" and "assessed at the floor" are different things and
        // the readout renders them differently, so an empty payload must not
        // become a zero-scored Discovery First record.
        for (Map<String, Integer> empty : new List<Map<String, Integer>>{
            null,
            new Map<String, Integer>(),
            new Map<String, Integer>{ 'not_a_dimension' => 4 }
        }) {
            GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', empty);
            Assert.isFalse(scored.hasAnswers);
            Assert.isNull(scored.total);
            Assert.isNull(scored.tier);
            Assert.isNull(scored.sectionScoresJson);
            Assert.isFalse(scored.advisory);
        }
    }

    @isTest
    static void sectionScoresJsonIsParseableAndCarriesOnlyScoredDimensions() {
        // GtmReadoutController.sectionScoreLines parses this blob to build the
        // readout's breakdown, so it has to be real JSON.
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', 
            new Map<String, Integer>{ 'estate_scale' => 3, 'source_access' => 2 }
        );

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(scored.sectionScoresJson);
        Assert.areEqual(2, parsed.size());
        Assert.areEqual(3, (Integer) parsed.get('estate_scale'));
        Assert.areEqual(2, (Integer) parsed.get('source_access'));
    }

    // ------------------------------------------------------- adaptive layer
    //
    // UNVERIFIED, like the rest of this suite in this environment: no CLI, no
    // org, nothing compiled. These pin the properties the pack overload must
    // not lose.

    /** A pack with the base eight, optionally one substituted and one capped. */
    private static GtmAssessmentInstrument.Pack packWith(
        String substituteBaseKey, String newKey, String cappedKey, Integer cap
    ) {
        GtmAssessmentInstrument.Pack pack = new GtmAssessmentInstrument.Pack();
        List<String> dims = GtmAssessmentScoring.DIMENSIONS;
        for (Integer i = 0; i < dims.size(); i++) {
            GtmAssessmentInstrument.Slot slot = new GtmAssessmentInstrument.Slot();
            slot.position      = i + 1;
            slot.baseKey       = dims[i];
            slot.key           = dims[i].equals(substituteBaseKey) ? newKey : dims[i];
            slot.substitutable = (i != 0 && i != dims.size() - 1);
            slot.maxAttainable = slot.key.equals(cappedKey)
                ? cap
                : GtmAssessmentScoring.MAX_ANSWER_VALUE;
            pack.slots.add(slot);
        }
        pack.pairKey = 'test_pack';
        pack.version = '1.2.3';
        return pack;
    }

    @isTest
    static void aSubstitutedSlotIsScoredUnderItsNewKeyAndTheBaseKeyStopsCounting() {
        GtmAssessmentInstrument.Pack pack =
            packWith('data_model_readiness', 'crm_and_data_model_entanglement', null, null);

        Map<String, Integer> answers = allAt(3);
        answers.remove('data_model_readiness');
        answers.put('crm_and_data_model_entanglement', 4);

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', answers, pack);

        Assert.areEqual(25, scored.total, '7 x 3 + 4');
        Assert.areEqual(4, scored.sectionScores.get('crm_and_data_model_entanglement'));
        Assert.isFalse(scored.sectionScores.containsKey('data_model_readiness'),
            'The base key is not part of this pair\'s instrument, so an answer to it ' +
            'is exactly as unreadable as any other invented key');
        Assert.areEqual('test_pack', scored.instrumentPairKey);
        Assert.areEqual('1.2.3', scored.instrumentVersion);
    }

    @isTest
    static void substitutionChangesWhichEightAreScoredNeverHowMany() {
        GtmAssessmentInstrument.Pack pack =
            packWith('data_model_readiness', 'crm_and_data_model_entanglement', null, null);
        Assert.areEqual(8, scoredKeys(pack).size());
        Assert.areEqual(
            GtmAssessmentScoring.MAX_TOTAL_SCORE,
            GtmAssessmentScoring.DIMENSIONS.size() * GtmAssessmentScoring.MAX_ANSWER_VALUE,
            'The maximum stays 32 whatever a pack substitutes'
        );
    }

    private static Set<String> scoredKeys(GtmAssessmentInstrument.Pack pack) {
        Map<String, Integer> answers = new Map<String, Integer>();
        for (GtmAssessmentInstrument.Slot slot : pack.slots) {
            answers.put(slot.key, 2);
        }
        return GtmAssessmentScoring.score('migration-accelerator', answers, pack).sectionScores.keySet();
    }

    @isTest
    static void anAnswerAboveAPairsCeilingIsDroppedNotClamped() {
        GtmAssessmentInstrument.Pack pack = packWith(null, null, 'source_access', 3);

        Map<String, Integer> answers = allAt(3);
        answers.put('source_access', 4);

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', answers, pack);

        Assert.isFalse(scored.sectionScores.containsKey('source_access'),
            'A 4 submitted to a slot the pair rendered as capped at 3 is a claim to an ' +
            'answer that was visibly not on offer. Clamping it to 3 would invent an ' +
            'answer nobody gave; accepting it would let a guest endpoint score past a ' +
            'ceiling that exists because the capability does not');
        Assert.areEqual(21, scored.total, '7 x 3, with the capped slot unanswered');
        Assert.isFalse(scored.cappedByAccessGate,
            'A dropped value is unanswered, and an unanswered access question is not ' +
            'evidence that access is missing');
    }

    @isTest
    static void anAnswerAtTheCeilingIsAcceptedNormally() {
        GtmAssessmentInstrument.Pack pack = packWith(null, null, 'source_access', 3);
        Map<String, Integer> answers = allAt(3);
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', answers, pack);
        Assert.areEqual(24, scored.total, '8 x 3 -- the ceiling is a maximum, not an exclusion');
        Assert.areEqual(3, scored.sectionScores.get('source_access'));
    }

    @isTest
    static void aShortOrMalformedPackFallsBackToTheBaseEight() {
        GtmAssessmentInstrument.Pack shortPack = new GtmAssessmentInstrument.Pack();
        GtmAssessmentInstrument.Slot only = new GtmAssessmentInstrument.Slot();
        only.key = 'estate_scale';
        only.baseKey = 'estate_scale';
        shortPack.slots.add(only);

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', allAt(4), shortPack);

        Assert.areEqual(GtmAssessmentScoring.MAX_TOTAL_SCORE, scored.total,
            'A seven-slot pack that scored out of 28 while the readout printed ' +
            '"out of 32" is the failure mode that looks most like a correct answer, ' +
            'so a pack that is not exactly eight distinct keys is not trusted at all');
        Assert.areEqual(GtmAssessmentScoring.DIMENSIONS, scored.dimensionKeys);
    }

    @isTest
    static void aPackWithDuplicateKeysFallsBackToTheBaseEight() {
        GtmAssessmentInstrument.Pack dupes =
            packWith('orchestration_portability', 'content_portability', null, null);
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', allAt(4), dupes);
        Assert.areEqual(GtmAssessmentScoring.DIMENSIONS, scored.dimensionKeys,
            'Two slots collapsing into one key would silently halve a dimension\'s weight');
    }

    @isTest
    static void anInventedKeyStillCannotScoreUnderAPack() {
        GtmAssessmentInstrument.Pack pack = packWith(null, null, null, null);
        Map<String, Integer> answers = allAt(2);
        answers.put('totally_made_up', 4);
        answers.put('another_invention', 4);

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', answers, pack);

        Assert.areEqual(16, scored.total, '8 x 2 and nothing else');
        Assert.areEqual(8, scored.sectionScores.size(),
            'The resolved list is still an allowlist, and it is still ITERATED rather ' +
            'than filtered -- a key we did not ask for is never read');
    }

    @isTest
    static void theNullPackOverloadBehavesExactlyAsTheOldTwoArgumentCallDid() {
        Map<String, Integer> answers = allAt(3);
        GtmAssessmentScoring.Score withoutPack = GtmAssessmentScoring.score('migration-accelerator', answers);
        GtmAssessmentScoring.Score withNullPack =
            GtmAssessmentScoring.score('migration-accelerator', answers, null, null);
        Assert.areEqual(withoutPack.total, withNullPack.total);
        Assert.areEqual(withoutPack.tier, withNullPack.tier);
        Assert.areEqual(GtmAssessmentScoring.DIMENSIONS, withoutPack.dimensionKeys);
    }

    // --------------------------------------------------- author-set points
    //
    // UNVERIFIED, as above. What these pin is the boundary between what a
    // content author may retune and what they may not: the SHAPE of a scale is
    // theirs, the SIZE of it is not, because the four bands were calibrated
    // against a 32-point maximum and an instrument scored out of anything else
    // is not comparable to one scored out of that.

    /** A pack whose slots carry authored options, so points are exercised. */
    private static GtmAssessmentInstrument.Pack packWithPoints(
        String pointedKey, List<Integer> points
    ) {
        GtmAssessmentInstrument.Pack pack = new GtmAssessmentInstrument.Pack();
        List<String> dims = GtmAssessmentScoring.DIMENSIONS;
        for (Integer i = 0; i < dims.size(); i++) {
            GtmAssessmentInstrument.Slot slot = new GtmAssessmentInstrument.Slot();
            slot.position      = i + 1;
            slot.baseKey       = dims[i];
            slot.key           = dims[i];
            slot.substitutable = (i != 0 && i != dims.size() - 1);
            for (Integer v = 1; v <= 4; v++) {
                Integer worth = dims[i].equals(pointedKey) ? points[v - 1] : v;
                slot.options.add(new GtmAssessmentInstrument.Option(v, 'option ' + v, worth));
            }
            pack.slots.add(slot);
        }
        pack.pairKey = 'points_pack';
        pack.version = '1.0';
        return pack;
    }

    @isTest
    static void authoredPointsDecideTheTotalAndTheRawAnswerIsKeptBeside() {
        // 1/1/3/4 on one slot: "the second-worst answer is just as bad as the
        // worst", which is a true thing an author may need to say.
        GtmAssessmentInstrument.Pack pack =
            packWithPoints('orchestration_portability', new List<Integer>{ 1, 1, 3, 4 });

        GtmAssessmentScoring.Score scored =
            GtmAssessmentScoring.score('migration-accelerator', allAtExcept(4, new Map<String, Integer>{
                'orchestration_portability' => 2
            }), pack);

        Assert.areEqual(29, scored.total,
            'Seven slots at 4 plus one answered at option 2, worth 1');
        Assert.areEqual(1, scored.sectionScores.get('orchestration_portability'),
            'The breakdown carries the POINTS, so it still adds up to the total');
        Assert.areEqual(2, scored.answerValues.get('orchestration_portability'),
            'And the raw answer survives beside it, because "3 of 4" is a ' +
            'position on the scale the respondent saw');
        Assert.areEqual(32, scored.maxTotal, 'Still out of 32');
    }

    @isTest
    static void anInstrumentThatDoesNotAddUpToThirtyTwoHasItsPointsRefused() {
        // The second lock. The build script blocks this at authoring time
        // (rule 10); this is what happens when a metadata record is hand-edited
        // past it. Refusing the authored points wholesale and falling back to
        // the identity scale is "fail to the frame", the same instinct that
        // makes a short pack fall back to the base eight.
        GtmAssessmentInstrument.Pack pack =
            packWithPoints('content_portability', new List<Integer>{ 1, 2, 3, 3 });
        Assert.areEqual(31, pack.maxTotal(), 'The pack as authored tops out at 31');

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', allAt(4), pack);
        Assert.areEqual(32, scored.total,
            'The authored points are refused and the identity scale used instead, ' +
            'rather than quietly printing a total out of 31 against bands ' +
            'calibrated for 32');
        Assert.areEqual(GtmAssessmentScoring.MAX_TOTAL_SCORE, scored.maxTotal);
        Assert.areEqual(
            GtmAssessmentScoring.MAX_TOTAL_SCORE, GtmAssessmentScoring.maxTotalFor('migration-accelerator', pack)
        );
    }

    @isTest
    static void pointsNeverMoveTheBandEdges() {
        // The sentence this whole design exists to make impossible is "19 would
        // have been Accelerator-Ready if you'd come from Marketo". Non-linear
        // points change which answers reach 19; they must not change what 19 is.
        GtmAssessmentInstrument.Pack pack =
            packWithPoints('consent_portability', new List<Integer>{ 1, 1, 3, 4 });
        GtmAssessmentScoring.Score scored =
            GtmAssessmentScoring.score('migration-accelerator', allAtExcept(3, new Map<String, Integer>{
                'consent_portability' => 2
            }), pack);
        Assert.areEqual(22, scored.total, 'Seven at 3, one worth 1');
        Assert.areEqual(GtmAssessmentScoring.TIER_ACCELERATOR_READY, scored.tier);
        Assert.areEqual(
            GtmAssessmentScoring.tierFor(22), scored.tier,
            'The band comes from the same tierFor everything else uses'
        );
    }

    @isTest
    static void anAnswerTheResolvedPackHasNoOptionForIsDropped() {
        GtmAssessmentInstrument.Pack pack =
            packWithPoints('estate_scale', new List<Integer>{ 1, 2, 3, 4 });
        // Value 4 exists; the drop path here is the one the ceiling already
        // owns, so assert the neighbouring case: a key with no slot at all.
        Map<String, Integer> answers = allAt(4);
        answers.put('invented_dimension', 4);

        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', answers, pack);
        Assert.areEqual(32, scored.total, 'An invented key adds nothing, as ever');
        Assert.isFalse(scored.sectionScores.containsKey('invented_dimension'));
    }

    @isTest
    static void theAccessGateReadsTheAnswerRatherThanThePoints() {
        // If the gate read points, an author retuning what "no access at all" is
        // worth would silently disarm the one override that says "there is no
        // offering to run here".
        GtmAssessmentInstrument.Pack pack =
            packWithPoints('source_access', new List<Integer>{ 1, 1, 3, 4 });
        GtmAssessmentScoring.Score scored =
            GtmAssessmentScoring.score('migration-accelerator', allAtExcept(4, new Map<String, Integer>{
                'source_access' => 1
            }), pack);
        Assert.isTrue(scored.cappedByAccessGate,
            'source_access answered at option 1 caps the tier, whatever it is worth');
        Assert.areEqual(GtmAssessmentScoring.TIER_DISCOVERY_FIRST, scored.tier);
    }

    @isTest
    static void theBranchPathIsRecordedForEverySlot() {
        GtmAssessmentInstrument.Pack pack = packWith(null, null, null, null);
        GtmAssessmentScoring.Score scored = GtmAssessmentScoring.score('migration-accelerator', allAt(3), pack);
        Assert.areEqual(8, scored.branchPath.size(),
            'Every slot names the question that filled it, so a readout reopened ' +
            'later can say what was actually asked');
        Assert.areEqual(
            GtmAssessmentInstrument.DEFAULT_VARIANT,
            scored.branchPath.get(GtmAssessmentScoring.DIMENSIONS[0])
        );
        Assert.isNotNull(scored.branchPathJson);
    }

    @isTest
    static void theBandsAreDerivedFromTheSameConstantsThatScore() {
        List<GtmAssessmentScoring.Band> bands = GtmAssessmentScoring.bands();
        Assert.areEqual(4, bands.size());
        Assert.areEqual(GtmAssessmentScoring.MIN_TOTAL_SCORE, bands[0].lowest);
        Assert.areEqual(GtmAssessmentScoring.MAX_TOTAL_SCORE, bands[3].highest);
        for (GtmAssessmentScoring.Band b : bands) {
            Assert.areEqual(b.tier, GtmAssessmentScoring.tierFor(b.lowest),
                'Every band edge must agree with tierFor, or the authoring ' +
                'preview shows an author a band the scorer would not give');
            Assert.areEqual(b.tier, GtmAssessmentScoring.tierFor(b.highest));
        }
    }
}
