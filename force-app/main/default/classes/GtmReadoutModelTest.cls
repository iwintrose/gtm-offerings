/**
 * UNVERIFIED — no Salesforce CLI and no org in this environment, so nothing
 * here was compiled or run. Written to the same contract as the rest of the
 * suite; run before merge.
 *
 * The properties under test are the ones that make render-time design safe.
 * gtmReadoutView draws a staircase, a provenance chip and a tier-grouped gap
 * table from this snapshot and asserts nothing of its own — so if the snapshot
 * is wrong, or invents, or silently drops a caveat, the readout a prospect
 * reads is wrong in a way no test on the component can catch.
 *
 * Three things are being pinned here:
 *
 *   1. FROZEN BY VALUE. Band edges, maxima and platform labels come out as
 *      numbers and strings, not as references to whatever those things mean
 *      later. This is what stops a recalibration redrawing an old readout.
 *   2. OMISSION, NEVER INVENTION. A field with no value is absent from the
 *      JSON. There is no default anywhere, because a default is an assertion
 *      nobody made.
 *   3. THE CAVEATS SURVIVE. Advisory suppresses the tier; posture drives the
 *      illustrative marker; verification_required rides on the row it belongs
 *      to; all six limits, every time.
 */
@IsTest
private class GtmReadoutModelTest {

    /** A request with the fields the snapshot reads, none of them persisted. */
    private static GTM_Assessment_Request__c request() {
        return new GTM_Assessment_Request__c(
            Company__c                    = 'Commercial Metals Company',
            Current_Platform__c           = 'hubspot',
            Target_Platform__c            = 'sfmc',
            Assessment_Score__c           = 19,
            Assessment_Tier__c            = GtmAssessmentScoring.TIER_PREP_REQUIRED,
            Estate_Complexity_Score__c    = 13,
            Estate_Complexity_Band__c     = GtmEstateComplexity.BAND_MODERATE,
            Estate_Complexity_Basis__c    = GtmEstateComplexity.BASIS_SELF_ESTIMATED,
            Contact_Count__c              = 240000,
            Monthly_Send_Volume__c        = 310000,
            Environment_Size__c           = 'One portal',
            Timeline__c                   = 'Q3 2027'
        );
    }

    private static Map<String, Object> snapshot(GTM_Assessment_Request__c req) {
        String jsonStr = GtmReadoutModel.buildJson(req);
        System.assertNotEquals(null, jsonStr, 'A scored request must produce a snapshot.');
        return (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
    }

    private static Map<String, Object> child(Map<String, Object> parent, String key) {
        return (Map<String, Object>) parent.get(key);
    }

    // ─── frozen by value ─────────────────────────────────────────────────

    @IsTest
    static void readinessCarriesItsOwnMaximumAndLadder() {
        Map<String, Object> out = snapshot(request());
        Map<String, Object> readiness = child(out, 'readiness');

        System.assertEquals(19, ((Decimal) readiness.get('score')).intValue());
        // The maximum travels WITH the score. A readout that printed a bare 19
        // could be read against any scale a reader imagined.
        System.assertEquals(
            GtmAssessmentScoring.MAX_TOTAL_SCORE,
            ((Decimal) readiness.get('max')).intValue(),
            'The max must come from the scoring that produced the number.'
        );

        // The ladder is written out as edges, not as a promise to look them up
        // later -- that is what stops a recalibration redrawing an approved
        // readout next quarter.
        List<Object> bands = (List<Object>) readiness.get('bands');
        System.assertEquals(4, bands.size());
        Integer current = 0;
        for (Object raw : bands) {
            Map<String, Object> band = (Map<String, Object>) raw;
            System.assert(band.get('low') != null, 'Every band writes its own edges.');
            System.assert(band.get('high') != null, 'Every band writes its own edges.');
            if (band.get('current') == true) {
                current++;
                System.assertEquals(GtmAssessmentScoring.TIER_PREP_REQUIRED, band.get('label'));
            }
        }
        System.assertEquals(1, current, 'Exactly one band is the current one.');
    }

    @IsTest
    static void complexityIsItsOwnAxisAndCarriesItsBasis() {
        Map<String, Object> complexity = child(snapshot(request()), 'complexity');
        System.assertEquals(13, ((Decimal) complexity.get('score')).intValue());
        System.assertEquals(
            GtmEstateComplexity.MAX_TOTAL_SCORE,
            ((Decimal) complexity.get('max')).intValue()
        );
        System.assertEquals(GtmEstateComplexity.BAND_MODERATE, complexity.get('band'));
        // Without the basis, a self-estimate reads as a measurement.
        System.assertEquals(GtmEstateComplexity.BASIS_SELF_ESTIMATED, complexity.get('basis'));
        System.assertEquals(3, ((List<Object>) complexity.get('bands')).size());
    }

    @IsTest
    static void platformLabelsAreResolvedAtGenerationTime() {
        Map<String, Object> pair = child(snapshot(request()), 'pair');
        // Resolved at generation: a platform renamed next year must not rewrite
        // an already-approved readout's masthead.
        System.assertNotEquals(null, pair.get('sourceLabel'));
        System.assertNotEquals(null, pair.get('targetLabel'));
    }

    // ─── the caveats ─────────────────────────────────────────────────────

    @IsTest
    static void advisorySuppressesTheTierRatherThanDashingIt() {
        GTM_Assessment_Request__c req = request();
        req.Assessment_Advisory__c = true;
        req.Advisory_Reason__c = 'No adapter exists for this pair.';

        Map<String, Object> out = snapshot(req);
        Map<String, Object> advisory = child(out, 'advisory');
        System.assertEquals(true, advisory.get('on'));
        System.assertEquals('No adapter exists for this pair.', advisory.get('reason'));

        Map<String, Object> readiness = child(out, 'readiness');
        // The score is still there -- it is still useful input for the
        // conversation. The tier and its ladder are ABSENT, not dashed:
        // printing "Tier: —" invites someone to fill the dash back in.
        System.assertEquals(19, ((Decimal) readiness.get('score')).intValue());
        System.assertEquals(false, readiness.containsKey('tier'));
        System.assertEquals(false, readiness.containsKey('tierPhrase'));
        System.assertEquals(false, readiness.containsKey('bands'));
    }

    @IsTest
    static void advisoryReasonFallsBackToOurOwnSentence() {
        GTM_Assessment_Request__c req = request();
        req.Assessment_Advisory__c = true;
        Map<String, Object> advisory = child(snapshot(req), 'advisory');
        System.assert(
            String.valueOf(advisory.get('reason')).contains('not one the accelerator can process'),
            'A blank reason still says why there is no tier.'
        );
    }

    @IsTest
    static void allSixLimitsAreEmittedInFull() {
        List<Object> limits = (List<Object>) snapshot(request()).get('limits');
        // Six, always. They are here rather than in the editable prose because
        // a rep trimming them to the two that look least awkward is exactly the
        // failure this list exists to prevent.
        System.assertEquals(6, limits.size());
        for (Object raw : limits) {
            Map<String, Object> row = (Map<String, Object>) raw;
            System.assert(String.isNotBlank((String) row.get('lead')));
            System.assert(String.isNotBlank((String) row.get('text')));
        }
        System.assertEquals(6, GtmReadoutModel.LIMITS.size());
    }

    @IsTest
    static void basisIsWordedFromThePostureActuallyInForce() {
        Map<String, Object> basis = child(snapshot(request()), 'basis');
        List<Object> how = (List<Object>) basis.get('how');
        System.assertEquals(4, how.size(), 'Four provenance statements, always.');
        Map<String, Object> first = (Map<String, Object>) how[0];
        System.assertEquals('Source scan.', first.get('lead'));
    }

    // ─── omission, never invention ───────────────────────────────────────

    @IsTest
    static void anUnscoredRequestOmitsTheAxesRatherThanZeroingThem() {
        GTM_Assessment_Request__c req = request();
        req.Assessment_Score__c = null;
        req.Estate_Complexity_Score__c = null;

        Map<String, Object> out = snapshot(req);
        // "Not scored" and "scored zero" are different claims. Absence is the
        // only honest way to say the first.
        System.assertEquals(false, out.containsKey('readiness'));
        System.assertEquals(false, out.containsKey('complexity'));
        // Everything that does not depend on a score still renders.
        System.assertEquals(true, out.containsKey('limits'));
        System.assertEquals(true, out.containsKey('basis'));
    }

    @IsTest
    static void anEstateWithNoFiguresOmitsThePanelEntirely() {
        GTM_Assessment_Request__c req = request();
        req.Contact_Count__c = null;
        req.Monthly_Send_Volume__c = null;
        req.Environment_Size__c = null;
        req.Timeline__c = null;
        req.Internal_Team_Size__c = null;
        req.Key_Integrations__c = null;

        // A grid of five tiles where three are blank looks like missing data,
        // not like an estate.
        System.assertEquals(false, snapshot(req).containsKey('estate'));
    }

    @IsTest
    static void estateTilesAndFactsAreSeparateAndOnlyWhatExists() {
        Map<String, Object> estate = child(snapshot(request()), 'estate');
        System.assertEquals(2, ((List<Object>) estate.get('tiles')).size());
        // Environment and Timeline were supplied; team size and integrations
        // were not, and are simply not there.
        System.assertEquals(2, ((List<Object>) estate.get('facts')).size());
    }

    @IsTest
    static void aNullRequestProducesNoSnapshotRatherThanAnEmptyOne() {
        System.assertEquals(null, GtmReadoutModel.buildJson(null));
    }

    @IsTest
    static void malformedStoredJsonCostsASectionNotTheSnapshot() {
        GTM_Assessment_Request__c req = request();
        req.Section_Scores__c = '{not json';
        req.Assessment_Flags__c = 'also not json';
        req.Estate_Complexity_Dimensions__c = '][';

        // Draft generation runs inside the guest submit transaction. A
        // templating hiccup must never take the readout down with it.
        Map<String, Object> out = snapshot(req);
        System.assertEquals(false, out.containsKey('annotations'));
        System.assertEquals(true, out.containsKey('readiness'));
    }

    @IsTest
    static void annotationsAreCarriedThroughWithTheirText() {
        GTM_Assessment_Request__c req = request();
        req.Assessment_Flags__c =
            '[{"key":"high_rebuild_ratio","message":"More of this estate is rebuild than move."}]';

        List<Object> notes = (List<Object>) snapshot(req).get('annotations');
        System.assertEquals(1, notes.size());
        Map<String, Object> note = (Map<String, Object>) notes[0];
        System.assertEquals('high_rebuild_ratio', note.get('key'));
        System.assert(String.valueOf(note.get('text')).contains('rebuild than move'));
    }

    // ─── gap tiering ─────────────────────────────────────────────────────

    @IsTest
    static void statusDecidesTheTierAndSeverityIsOnlyTheFallback() {
        GtmAssessmentInstrument.Callout unsupported = new GtmAssessmentInstrument.Callout();
        unsupported.status = 'unsupported';
        unsupported.severity = 'minor';
        System.assertEquals('D', GtmReadoutModel.tierFor(unsupported),
            'The manifest\'s own capability statement outranks how much it hurts.');

        GtmAssessmentInstrument.Callout partial = new GtmAssessmentInstrument.Callout();
        partial.status = 'partial';
        System.assertEquals('C', GtmReadoutModel.tierFor(partial));

        GtmAssessmentInstrument.Callout configured = new GtmAssessmentInstrument.Callout();
        configured.status = 'configuration';
        System.assertEquals('B', GtmReadoutModel.tierFor(configured));

        GtmAssessmentInstrument.Callout supported = new GtmAssessmentInstrument.Callout();
        supported.status = 'supported';
        System.assertEquals('A', GtmReadoutModel.tierFor(supported));

        // No status at all: severity is all there is to go on.
        GtmAssessmentInstrument.Callout blocker = new GtmAssessmentInstrument.Callout();
        blocker.severity = 'blocker';
        System.assertEquals('D', GtmReadoutModel.tierFor(blocker));

        GtmAssessmentInstrument.Callout unknown = new GtmAssessmentInstrument.Callout();
        System.assertEquals('C', GtmReadoutModel.tierFor(unknown),
            'An unclassifiable gap is treated as work, not as free.');
    }

    // ─── the provenance chip ─────────────────────────────────────────────

    @IsTest
    static void theChipFollowsThePostureAndDefaultsToTheCautiousOne() {
        // No pack resolved at all: we cannot claim to have measured anything.
        System.assertEquals(
            GtmReadoutModel.CHIP_SELF_REPORTED,
            GtmReadoutModel.chipFor(null)
        );

        GtmAssessmentReadout.Readout instrumented = new GtmAssessmentReadout.Readout();
        instrumented.estateFiguresIllustrative = false;
        System.assertEquals(GtmReadoutModel.CHIP_MEASURED, GtmReadoutModel.chipFor(instrumented));

        GtmAssessmentReadout.Readout assisted = new GtmAssessmentReadout.Readout();
        assisted.estateFiguresIllustrative = true;
        assisted.posture = GtmAssessmentInstrument.POSTURE_ASSISTED;
        System.assertEquals(GtmReadoutModel.CHIP_PARTIAL, GtmReadoutModel.chipFor(assisted));

        GtmAssessmentReadout.Readout interview = new GtmAssessmentReadout.Readout();
        interview.estateFiguresIllustrative = true;
        interview.posture = GtmAssessmentInstrument.POSTURE_INTERVIEW;
        System.assertEquals(GtmReadoutModel.CHIP_SELF_REPORTED, GtmReadoutModel.chipFor(interview));
    }

    // ─── the section vocabulary ──────────────────────────────────────────

    @IsTest
    static void theSevenSectionsMatchTheCommentPickersOwnList() {
        // One vocabulary doing four jobs: the generated headings, GUS's
        // replace_section target, the recipient's comment picker and the
        // renderer's panel routing. If these two lists ever diverge, a
        // recipient can comment on a section that does not exist, or GUS can
        // be asked to edit one the renderer will not show.
        Set<String> sections = new Set<String>(GtmReadoutModel.SECTIONS);
        System.assertEquals(7, sections.size());
        for (String name : GtmReadoutCommentController.getCommentSections()) {
            System.assert(
                sections.contains(name),
                'Comment section "' + name + '" has no matching readout heading.'
            );
        }
    }
}
