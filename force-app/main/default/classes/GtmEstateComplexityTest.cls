@isTest
private class GtmEstateComplexityTest {

    private static Map<String, Integer> allAt(Integer value) {
        Map<String, Integer> answers = new Map<String, Integer>();
        for (String dimension : GtmEstateComplexity.DIMENSIONS) {
            answers.put(dimension, value);
        }
        return answers;
    }

    @isTest
    static void thereAreSixDimensionsWorthEighteenPoints() {
        Assert.areEqual(6, GtmEstateComplexity.DIMENSIONS.size());
        Assert.areEqual(3, GtmEstateComplexity.MAX_ANSWER_VALUE);
        Assert.areEqual(18, GtmEstateComplexity.MAX_TOTAL_SCORE);
        Assert.areEqual(6, GtmEstateComplexity.MIN_TOTAL_SCORE);
        Assert.areEqual(6, new Set<String>(GtmEstateComplexity.DIMENSIONS).size(), 'Keys must be distinct');
    }

    @isTest
    static void complexityIsScoredOnItsOwnScaleNotTheReadinessOne() {
        // The two instruments share a shape and nothing else. If complexity
        // ever started accepting 4s it would be silently borrowing the
        // readiness scale, and the two axes would stop being comparable.
        GtmEstateComplexity.Complexity scored = GtmEstateComplexity.score('migration-accelerator', allAt(4));
        Assert.isFalse(scored.hasAnswers, 'A 4 is out of range for a 1-3 dimension');
        Assert.isNull(scored.total);
    }

    @isTest
    static void theTwoAxesAreNeverTheSameNumber() {
        // A guard against anyone "simplifying" by folding one into the other:
        // the maxima differ, so a blended total could not be printed against
        // either scale honestly.
        Assert.areNotEqual(
            GtmAssessmentScoring.MAX_TOTAL_SCORE,
            GtmEstateComplexity.MAX_TOTAL_SCORE,
            'Readiness is out of 32 and complexity out of 18 -- they are separate axes'
        );
    }

    @isTest
    static void bandsCoverTheWholeRange() {
        Assert.areEqual('Light',    GtmEstateComplexity.bandFor(6));
        Assert.areEqual('Light',    GtmEstateComplexity.bandFor(9));
        Assert.areEqual('Moderate', GtmEstateComplexity.bandFor(10));
        Assert.areEqual('Moderate', GtmEstateComplexity.bandFor(13));
        Assert.areEqual('Heavy',    GtmEstateComplexity.bandFor(14));
        Assert.areEqual('Heavy',    GtmEstateComplexity.bandFor(18));
        Assert.isNull(GtmEstateComplexity.bandFor(null));
    }

    @isTest
    static void everyBandIsAValidPicklistValue() {
        Set<String> allowed = new Set<String>{ 'Light', 'Moderate', 'Heavy' };
        Assert.areEqual(allowed, new Set<String>(GtmEstateComplexity.BANDS));
        for (Integer total = 0; total <= 25; total++) {
            Assert.isTrue(allowed.contains(GtmEstateComplexity.bandFor(total)),
                'Unexpected band for ' + total);
        }
    }

    @isTest
    static void aLightestAndHeaviestEstateBandCorrectly() {
        GtmEstateComplexity.Complexity light = GtmEstateComplexity.score('migration-accelerator', allAt(1));
        Assert.areEqual(6, light.total);
        Assert.areEqual('Light', light.band);

        GtmEstateComplexity.Complexity heavy = GtmEstateComplexity.score('migration-accelerator', allAt(3));
        Assert.areEqual(18, heavy.total);
        Assert.areEqual('Heavy', heavy.band);
        Assert.areEqual(6, heavy.dimensionScores.size());
    }

    @isTest
    static void unknownKeysAndOutOfRangeAnswersContributeNothing() {
        Map<String, Integer> answers = new Map<String, Integer>{
            'journey_footprint'         => 3,
            'scripting_depth'           => 99,
            'business_unit_structure'   => 0,
            'not_a_dimension'           => 3,
            'consent_suppression_model' => null
        };
        GtmEstateComplexity.Complexity scored = GtmEstateComplexity.score('migration-accelerator', answers);
        Assert.areEqual(3, scored.total);
        Assert.areEqual(1, scored.dimensionScores.size());
        Assert.isFalse(scored.dimensionScoresJson.contains('not_a_dimension'));
    }

    @isTest
    static void nothingAnsweredIsNullNotZero() {
        for (Map<String, Integer> empty : new List<Map<String, Integer>>{
            null, new Map<String, Integer>(), new Map<String, Integer>{ 'nope' => 2 }
        }) {
            GtmEstateComplexity.Complexity scored = GtmEstateComplexity.score('migration-accelerator', empty);
            Assert.isFalse(scored.hasAnswers);
            Assert.isNull(scored.total);
            Assert.isNull(scored.band);
            Assert.isNull(scored.dimensionScoresJson);
        }
    }

    // ------------------------------------------------ the resolved list

    @isTest
    static void scoresAgainstTheDimensionsTheResolvedPackAsked() {
        // A pair may reword or recalibrate any dimension, and may in principle
        // substitute one; when it does, the answer arrives under the key the
        // respondent was actually asked, and that is the key the scorer has to
        // read. Nothing else about the axis moves.
        List<String> resolved = new List<String>(GtmEstateComplexity.DIMENSIONS);
        resolved[0] = 'workflow_footprint_native';

        Map<String, Integer> answers = new Map<String, Integer>{
            'workflow_footprint_native' => 3,
            GtmEstateComplexity.DIMENSIONS[1] => 2,
            // The key it REPLACED. Never asked, so never read.
            GtmEstateComplexity.DIMENSIONS[0] => 3
        };

        GtmEstateComplexity.Complexity scored = GtmEstateComplexity.score('migration-accelerator', answers, resolved);
        Assert.areEqual(5, scored.total, 'Only the two answers under resolved keys count');
        Assert.areEqual(2, scored.dimensionScores.size());
        Assert.isTrue(scored.dimensionScores.containsKey('workflow_footprint_native'));
        Assert.isFalse(
            scored.dimensionScores.containsKey(GtmEstateComplexity.DIMENSIONS[0]),
            'A key the pack did not resolve is never read, which is the allowlist ' +
            'property this class has always had, reached from a new direction'
        );
    }

    @isTest
    static void aResolvedListOfTheWrongShapeFallsBackRatherThanScoring() {
        Map<String, Integer> answers = new Map<String, Integer>{
            GtmEstateComplexity.DIMENSIONS[0] => 3,
            GtmEstateComplexity.DIMENSIONS[1] => 3
        };
        // Too short, and a repeated key. Either would produce a total that is
        // not out of 18 while the readout prints "out of 18" beside a basis
        // claiming it is comparable with a post-scan measurement.
        List<String> tooShort = new List<String>{ GtmEstateComplexity.DIMENSIONS[0] };
        List<String> duplicated = new List<String>(GtmEstateComplexity.DIMENSIONS);
        duplicated[5] = duplicated[0];

        for (List<String> bad : new List<List<String>>{ null, tooShort, duplicated }) {
            GtmEstateComplexity.Complexity scored = GtmEstateComplexity.score('migration-accelerator', answers, bad);
            Assert.areEqual(6, scored.total, 'Scored against the default six instead');
            Assert.areEqual(2, scored.dimensionScores.size());
        }
    }

    @isTest
    static void theInvariantsSurviveAResolvedList() {
        List<String> resolved = new List<String>(GtmEstateComplexity.DIMENSIONS);
        resolved[0] = 'workflow_footprint_native';
        Map<String, Integer> answers = new Map<String, Integer>{
            'workflow_footprint_native' => 4,   // out of range: DROPPED, not clamped
            GtmEstateComplexity.DIMENSIONS[1] => 0,
            GtmEstateComplexity.DIMENSIONS[2] => 3,
            'not_a_dimension' => 3
        };
        GtmEstateComplexity.Complexity scored = GtmEstateComplexity.score('migration-accelerator', answers, resolved);
        Assert.areEqual(3, scored.total, 'A 4 on a 1-3 scale is dropped, never clamped to 3');
        Assert.areEqual(1, scored.dimensionScores.size());
        Assert.isFalse(scored.dimensionScoresJson.contains('not_a_dimension'));
        Assert.areEqual(
            18, GtmEstateComplexity.MAX_TOTAL_SCORE,
            'and the maximum is still derived from the frame, not typed'
        );
    }

    @isTest
    static void theComplexityMaximumIsPerOfferingAndNullWhereThereIsNoInstrument() {
        // QA round 1, Finding 3. This method is new: nothing exposed the
        // complexity MAXIMUM to a caller holding only an offering key, so the
        // guest questionnaire endpoint -- which needs it before any answer
        // exists -- printed the compiled 18 for every offering alive.
        GtmAssessmentFrames.rowOverride = new List<GTM_Assessment_Frame__mdt>();
        GtmAssessmentFrames.resetCache();

        Assert.areEqual(
            18, GtmEstateComplexity.maxTotalFor('migration-accelerator'),
            'Migration Accelerator is still measured out of its own six dimensions'
        );
        Assert.areEqual(
            18, GtmEstateComplexity.maxTotalFor(null),
            'and a blank key still means Migration Accelerator'
        );
        Assert.isNull(
            GtmEstateComplexity.maxTotalFor('an-offering-with-no-instrument'),
            'LEAK: an offering with no complexity axis was measured out of somebody else\'s 18'
        );
    }

    @isTest
    static void onlyTheTwoRecognisedBasesAreAccepted() {
        Assert.areEqual('Self-Estimated', GtmEstateComplexity.acceptedBasis('self-estimated'));
        Assert.areEqual('Measured', GtmEstateComplexity.acceptedBasis('  MEASURED '));
        // Anything else is null rather than passed through: an unrecognised
        // basis printed next to a number would read as provenance it does not
        // have, and would also fail the restricted picklist on insert.
        Assert.isNull(GtmEstateComplexity.acceptedBasis('Guessed'));
        Assert.isNull(GtmEstateComplexity.acceptedBasis(''));
        Assert.isNull(GtmEstateComplexity.acceptedBasis(null));
    }
}
