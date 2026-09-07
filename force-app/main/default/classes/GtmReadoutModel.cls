/**
 * The structured half of a readout, frozen once at generation.
 *
 * ── Why this class exists ─────────────────────────────────────────────────
 * A readout is two different kinds of thing wearing one coat.
 *
 *   PROSE      — the verdict sentence, the findings, the framing. A human owns
 *                it. It lives in Draft_Content__c, the rep edits it in
 *                gtmReadoutReview, and GUS proposes section edits into it.
 *   MEASUREMENT — 21 out of 32; Accelerator-Ready, foundation-gated; the band
 *                ladder those numbers were scored against; which rows are
 *                measured and which are what the client told us; the named
 *                gaps and their hedges. Nobody edits these. They are what the
 *                assessment found.
 *
 * The designed readout (gtmReadoutView) needs the second kind as DATA — a
 * staircase has to know which step is lit, a scorecard row has to know its
 * provenance chip — and prose cannot carry that through a rich-text editor
 * that strips classes and data attributes on save. So the measurement half is
 * serialised here, once, and stored in Readout_Data__c.
 *
 * ── Why it is FROZEN ──────────────────────────────────────────────────────
 * Everything in the snapshot is a value, never a reference. The band edges are
 * written out as numbers rather than read from GtmAssessmentScoring at render
 * time; the maximum is the maximum this score was measured against; the
 * platform labels are resolved now, not later. That is the same reasoning
 * GtmAssessmentScoring.Score.maxTotal already applies to itself, extended to
 * everything a reader can see.
 *
 * The property it buys is the one that makes render-time design safe: a
 * recalibration of the bands next quarter, a renamed platform, an edited
 * capability manifest — none of them can reach backwards and change what an
 * already-approved readout asserts. The template may change how a readout
 * looks. It must never change what it says.
 *
 * ── What is NOT in here ───────────────────────────────────────────────────
 * No prose the rep is expected to edit, and no defaults. A field with no value
 * is absent from the JSON, and gtmReadoutView renders nothing for it rather
 * than a plausible-looking placeholder. A renderer that can invent
 * "Accelerator-Ready" when the data does not say so is a renderer that can
 * change meaning, which is the whole thing this design is arranged to prevent.
 *
 * Pure apart from the metadata reads it delegates (the instrument pack and the
 * dimension labels), and every one of those is best-effort: a failure costs a
 * section of the snapshot, never the snapshot.
 */
public with sharing class GtmReadoutModel {

    /** Snapshot schema version. Bump when a reader would need to behave differently. */
    public static final Integer SCHEMA_VERSION = 1;

    /** Provenance chips, keyed off the pack's SOURCE posture — see chipFor(). */
    public static final String CHIP_MEASURED      = 'MEASURED';
    public static final String CHIP_PARTIAL       = 'PARTIAL';
    public static final String CHIP_SELF_REPORTED = 'SELF-REPORTED';

    /**
     * The seven section headings the generated draft uses, in readout order.
     *
     * This is one vocabulary doing four jobs, which is the point of it being a
     * constant rather than four separate lists:
     *
     *   1. GtmReadoutController.buildReadoutHtml emits these as its <h2>s;
     *   2. GtmReadoutAgentEdit.replace_section targets them by name, so GUS's
     *      splice keeps working unchanged;
     *   3. GtmReadoutCommentController.SECTIONS is the same seven, so a
     *      recipient's comment names a section that exists;
     *   4. gtmReadoutView routes each heading's body into its designed panel.
     *
     * A heading the renderer does not recognise is never dropped — it lands in
     * an "additional notes" panel — which is what lets readouts generated
     * before this vocabulary existed still render inside the new design.
     */
    public static final List<String> SECTIONS = new List<String>{
        'Verdict',
        'Findings',
        'The path',
        'Capability gaps',
        'Context',
        'Scorecard',
        'Next steps'
    };

    /**
     * The six limits, in full, every time.
     *
     * They are here rather than in the prose because they are the part of the
     * readout that must not be editable away. A rep under time pressure
     * trimming "what we can't see" down to the two that look least awkward is
     * exactly the failure this list exists to make impossible, and listing the
     * limits is what makes the rest of the numbers worth trusting.
     */
    public static final List<String> LIMITS = new List<String>{
        'Contact and subscriber rows.|Never extracted. Schema is in scope; your data migration is a separate workstream.',
        'Forms outside the tenant.|Anything posting in from a microsite or partner site is invisible without a domain list and a separate scan.',
        'Preference-centre mapping.|Consent structures are assessed by hand, not derived automatically.',
        'A point-in-time snapshot.|Anything built in the source system after the assessment date is not reflected here.',
        'List membership.|Audience containers move; who is inside them is reconciled separately.',
        'Decisions stay yours.|The accelerator proposes what to port, refactor or retire. A human signs it off.'
    };

    /**
     * Gap tiers, in the vocabulary the readout prints. A tier says how much of
     * the move is automatic, which is the question a reader is actually asking
     * when they look at a list of things that do not port.
     */
    private static final Map<String, String> TIER_LABELS = new Map<String, String>{
        'A' => 'FULLY AUTOMATED',
        'B' => 'SETUP REQUIRED',
        'C' => 'CUSTOM DEVELOPMENT',
        'D' => 'NO EQUIVALENT — REBUILD REQUIRED'
    };

    // ------------------------------------------------------------- building

    /**
     * The frozen snapshot for one assessment request, as JSON, or null when
     * there is nothing worth freezing.
     *
     * Never throws. Draft generation runs inside the guest submit transaction
     * (see GtmReadoutController.Generator) and a snapshot that could take the
     * readout down with it would be a worse trade than a readout that renders
     * its prose half and omits its designed panels.
     */
    public static String buildJson(GTM_Assessment_Request__c req) {
        try {
            Map<String, Object> snapshot = build(req);
            return snapshot == null ? null : JSON.serialize(snapshot, true);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Readout data snapshot could not be built for request ' +
                (req == null ? null : req.Id) + ' -- ' + e.getTypeName() +
                '. The prose half of the draft is unaffected.'
            );
            return null;
        }
    }

    /** The snapshot as a map, for tests and for buildJson. */
    @TestVisible
    private static Map<String, Object> build(GTM_Assessment_Request__c req) {
        if (req == null) {
            return null;
        }
        GtmAssessmentReadout.Readout adaptive = adaptiveReadout(req);

        Map<String, Object> out = new Map<String, Object>();
        out.put('v', SCHEMA_VERSION);
        out.put('generatedAt', String.valueOf(System.now()));
        putIfPresent(out, 'company', req.Company__c);

        // Platforms as LABELS, resolved now. A readout for a HubSpot -> MC Next
        // assessment has to say HubSpot and MC Next everywhere the sample said
        // Eloqua and SFMC, and it has to keep saying them after somebody
        // renames a platform row.
        Map<String, Object> pair = new Map<String, Object>();
        putIfPresent(pair, 'sourceLabel', platformLabel(req.Current_Platform__c));
        putIfPresent(pair, 'targetLabel', platformLabel(req.Target_Platform__c));
        putIfPresent(pair, 'pairKey', req.Instrument_Pair__c);
        putIfPresent(pair, 'instrumentVersion', req.Instrument_Version__c);
        putIfPresent(pair, 'track', req.Branch_Platform__c);
        if (!pair.isEmpty()) {
            out.put('pair', pair);
        }

        // Advisory FIRST, and the tier suppressed under it -- the same
        // ordering decision buildReadoutHtml makes in prose, expressed as data
        // so the designed form cannot quietly reorder it.
        if (req.Assessment_Advisory__c == true) {
            Map<String, Object> advisory = new Map<String, Object>{ 'on' => true };
            advisory.put('reason', String.isBlank(req.Advisory_Reason__c)
                ? 'The selected source/target combination is not one the accelerator can process.'
                : req.Advisory_Reason__c);
            advisory.put('note',
                'No readiness tier is shown, because banding this pair would promise a delivery ' +
                'path that does not exist yet. The scores below are still useful input for the ' +
                'conversation.');
            out.put('advisory', advisory);
        }

        putPosture(out, adaptive);
        putReadiness(out, req, adaptive);
        putComplexity(out, req);
        putDimensions(out, req, adaptive);
        putGaps(out, adaptive);
        putEstate(out, req);
        putAnnotations(out, req);
        putGates(out, adaptive);
        putBasis(out, adaptive);

        if (adaptive != null && String.isNotBlank(adaptive.horizon)) {
            out.put('horizon', adaptive.horizon);
        }
        if (adaptive != null && String.isNotBlank(adaptive.resolutionNote)) {
            out.put('resolutionNote', adaptive.resolutionNote);
        }
        out.put('limits', limitRows());
        return out;
    }

    // ------------------------------------------------------------- sections

    /**
     * POSTURE. Above the fold and above the number, because a caveat printed
     * under a number is a footnote and footnotes are not read out loud. The
     * illustrative marker is keyed on the SOURCE posture, not the headline:
     * estate figures come from reading the source, so an instrumented source
     * with an unverified target has real counts and an unverified destination.
     */
    private static void putPosture(Map<String, Object> out, GtmAssessmentReadout.Readout adaptive) {
        if (adaptive == null) {
            return;
        }
        Map<String, Object> posture = new Map<String, Object>();
        putIfPresent(posture, 'headline', adaptive.posture);
        putIfPresent(posture, 'statement', adaptive.postureStatement);
        posture.put('illustrative', adaptive.estateFiguresIllustrative == true);
        if (adaptive.estateFiguresIllustrative == true) {
            posture.put('illustrativeNote',
                'Estate figures in this readout are illustrative — they are the client\'s ' +
                'account of the estate, not a measurement taken from it.');
        }
        if (!posture.isEmpty()) {
            out.put('posture', posture);
        }
    }

    /**
     * The first axis, with the ladder it was scored against written out as
     * values. "n out of MAX" is never a bare number, and MAX is the maximum
     * THIS score was measured against (Readout.maxTotal), not today's.
     *
     * The tier is omitted entirely when the pair is advisory rather than being
     * emitted as a dash: a suppressed tier is a decision, and printing "Tier: —"
     * next to a real score invites someone to fill the dash back in.
     */
    private static void putReadiness(
        Map<String, Object> out, GTM_Assessment_Request__c req, GtmAssessmentReadout.Readout adaptive
    ) {
        if (req.Assessment_Score__c == null) {
            return;
        }
        Integer max = (adaptive != null && adaptive.maxTotal != null)
            ? adaptive.maxTotal
            : GtmAssessmentScoring.MAX_TOTAL_SCORE;

        Map<String, Object> readiness = new Map<String, Object>();
        readiness.put('score', req.Assessment_Score__c);
        readiness.put('max', max);
        readiness.put('scale', 'a higher score means a smaller, simpler, lower-risk estate');

        if (req.Assessment_Advisory__c != true) {
            // Tier AND qualifier as one phrase. "Fast-Track, foundation-gated"
            // is a real and common result and a readout that prints only one
            // half of it is wrong whichever half it picks.
            String tierPhrase = (adaptive != null && String.isNotBlank(adaptive.tierPhrase))
                ? adaptive.tierPhrase
                : req.Assessment_Tier__c;
            putIfPresent(readiness, 'tier', req.Assessment_Tier__c);
            putIfPresent(readiness, 'tierPhrase', tierPhrase);
            putIfPresent(readiness, 'qualifier', adaptive == null ? null : adaptive.qualifier);
            readiness.put('bands', readinessBands(req.Assessment_Tier__c));
        }
        out.put('readiness', readiness);
    }

    private static List<Object> readinessBands(String currentTier) {
        List<Object> rows = new List<Object>();
        try {
            for (GtmAssessmentScoring.Band b : GtmAssessmentScoring.bands()) {
                rows.add(new Map<String, Object>{
                    'label'   => b.tier,
                    'low'     => b.lowest,
                    'high'    => b.highest,
                    'current' => b.tier == currentTier
                });
            }
        } catch (Exception e) {
            // No ladder rather than a wrong ladder.
        }
        return rows;
    }

    /**
     * The second axis, on its own line and never blended with the first: a
     * heavy estate is a bigger engagement, not a worse client. The basis
     * travels with it, because a self-estimate presented as a measurement is
     * the one way this number can lie.
     */
    private static void putComplexity(Map<String, Object> out, GTM_Assessment_Request__c req) {
        if (req.Estate_Complexity_Score__c == null) {
            return;
        }
        Map<String, Object> complexity = new Map<String, Object>();
        complexity.put('score', req.Estate_Complexity_Score__c);
        complexity.put('max', GtmEstateComplexity.MAX_TOTAL_SCORE);
        putIfPresent(complexity, 'band', req.Estate_Complexity_Band__c);
        putIfPresent(complexity, 'basis', req.Estate_Complexity_Basis__c);
        complexity.put('scale', 'a higher score means a bigger job, not a worse client');
        complexity.put('bands', new List<Object>{
            band('Light',    6,  9,  req.Estate_Complexity_Band__c),
            band('Moderate', 10, 13, req.Estate_Complexity_Band__c),
            band('Heavy',    14, 18, req.Estate_Complexity_Band__c)
        });
        List<Object> dims = scoreRows(req.Estate_Complexity_Dimensions__c, GtmEstateComplexity.MAX_ANSWER_VALUE);
        if (!dims.isEmpty()) {
            complexity.put('dimensions', dims);
        }
        out.put('complexity', complexity);
    }

    private static Map<String, Object> band(String label, Integer low, Integer high, String current) {
        return new Map<String, Object>{
            'label' => label, 'low' => low, 'high' => high, 'current' => label == current
        };
    }

    /**
     * The scorecard, weakest first -- that is the order of the work, and it is
     * the only ordering that makes the strip above it readable.
     *
     * Every row carries a provenance chip. Where the chip comes from is the
     * honest part: we do not have per-dimension evidence, we have a pack
     * posture, so every row gets the chip the pack's SOURCE posture earns and
     * the basis panel says so in as many words. Inventing a per-row provenance
     * we cannot substantiate would be worse than one true chip repeated.
     */
    private static void putDimensions(
        Map<String, Object> out, GTM_Assessment_Request__c req, GtmAssessmentReadout.Readout adaptive
    ) {
        List<Object> rows = new List<Object>();
        String chip = chipFor(adaptive);

        if (adaptive != null && !adaptive.perDimension.isEmpty()) {
            List<GtmAssessmentReadout.DimensionResult> sorted = weakestFirst(adaptive.perDimension);
            for (GtmAssessmentReadout.DimensionResult d : sorted) {
                if (d.value == null) {
                    continue;
                }
                Map<String, Object> row = new Map<String, Object>();
                putIfPresent(row, 'label', String.isBlank(d.label) ? d.key : d.label);
                row.put('value', d.value);
                row.put('max', d.maxAttainable == null
                    ? GtmAssessmentScoring.MAX_ANSWER_VALUE : d.maxAttainable);
                row.put('chip', chip);
                putIfPresent(row, 'read', d.ceilingReason);
                if (d.emphasised == true) {
                    row.put('emphasised', true);
                }
                if (d.substituted == true) {
                    row.put('substituted', true);
                }
                rows.add(row);
            }
        }
        if (rows.isEmpty()) {
            // No pack, or a pack that could not be resolved: fall back to the
            // stored breakdown so the scorecard still exists.
            for (Object row : scoreRows(req.Section_Scores__c, GtmAssessmentScoring.MAX_ANSWER_VALUE)) {
                Map<String, Object> r = (Map<String, Object>) row;
                r.put('chip', chip);
                rows.add(r);
            }
        }
        if (!rows.isEmpty()) {
            out.put('dimensions', rows);
        }
    }

    /**
     * Weakest first. Bubble sort over eight rows is not the problem here, and
     * a stable order matters more than the algorithm: two dimensions on the
     * same score keep their questionnaire order, so the same answers always
     * produce the same readout.
     */
    private static List<GtmAssessmentReadout.DimensionResult> weakestFirst(
        List<GtmAssessmentReadout.DimensionResult> rows
    ) {
        List<GtmAssessmentReadout.DimensionResult> sorted = rows.clone();
        for (Integer i = 0; i < sorted.size(); i++) {
            for (Integer j = 0; j < sorted.size() - 1 - i; j++) {
                Integer a = sorted[j].value == null ? 99 : sorted[j].value;
                Integer b = sorted[j + 1].value == null ? 99 : sorted[j + 1].value;
                if (a > b) {
                    GtmAssessmentReadout.DimensionResult tmp = sorted[j];
                    sorted[j] = sorted[j + 1];
                    sorted[j + 1] = tmp;
                }
            }
        }
        return sorted;
    }

    /** The provenance chip the pack's source posture earns. */
    @TestVisible
    private static String chipFor(GtmAssessmentReadout.Readout adaptive) {
        if (adaptive == null) {
            return CHIP_SELF_REPORTED;
        }
        if (adaptive.estateFiguresIllustrative != true) {
            return CHIP_MEASURED;
        }
        return GtmAssessmentInstrument.POSTURE_ASSISTED.equals(adaptive.posture)
            ? CHIP_PARTIAL
            : CHIP_SELF_REPORTED;
    }

    /**
     * What will not port, grouped by tier rather than listed flat.
     *
     * A reader scanning a flat list cannot tell a rebuild from a config task,
     * and those are the two facts they need. The hedge rides on the row --
     * from verification_required, not from whoever writes the deck that week.
     */
    private static void putGaps(Map<String, Object> out, GtmAssessmentReadout.Readout adaptive) {
        if (adaptive == null || adaptive.callouts.isEmpty()) {
            return;
        }
        Map<String, List<Object>> byTier = new Map<String, List<Object>>();
        for (GtmAssessmentInstrument.Callout c : adaptive.callouts) {
            String tier = tierFor(c);
            Map<String, Object> row = new Map<String, Object>();
            putIfPresent(row, 'construct', String.isBlank(c.issue) ? c.pattern : c.issue);
            putIfPresent(row, 'onTarget', c.gloss);
            putIfPresent(row, 'takes', c.workaround);
            putIfPresent(row, 'severity', c.severity);
            putIfPresent(row, 'category', c.category);
            if (c.verificationRequired == true) {
                row.put('hedged', true);
                row.put('hedge',
                    'Unverified against a live tenant — state this as our working model, ' +
                    'not as a platform guarantee.');
            }
            if (c.manualSteps != null && !c.manualSteps.isEmpty()) {
                row.put('steps', c.manualSteps);
            }
            if (!byTier.containsKey(tier)) {
                byTier.put(tier, new List<Object>());
            }
            byTier.get(tier).add(row);
        }

        List<Object> groups = new List<Object>();
        // Heaviest tier first: what cannot move at all is the thing a reader
        // has to see before anything that merely needs setting up.
        for (String tier : new List<String>{ 'D', 'C', 'B', 'A' }) {
            if (!byTier.containsKey(tier)) {
                continue;
            }
            groups.add(new Map<String, Object>{
                'tier'  => tier,
                'label' => TIER_LABELS.get(tier),
                'rows'  => byTier.get(tier)
            });
        }
        out.put('gaps', new Map<String, Object>{
            'key' => 'Tiers describe how much of the move is automatic: A fully automated · ' +
                     'B setup required · C custom development · D no equivalent, rebuild required.',
            'groups' => groups
        });
    }

    /**
     * Status first, severity only as a fallback. Status is the manifest's own
     * statement about the target's capability; severity is how much it hurts,
     * and a blocker that is merely fiddly to configure is still a B.
     */
    @TestVisible
    private static String tierFor(GtmAssessmentInstrument.Callout c) {
        String status = c.status == null ? '' : c.status.trim().toLowerCase();
        if (status == 'unsupported' || status == 'none') {
            return 'D';
        }
        if (status == 'partial' || status == 'custom') {
            return 'C';
        }
        if (status == 'configuration' || status == 'setup' || status == 'manual') {
            return 'B';
        }
        if (status == 'supported' || status == 'automatic') {
            return 'A';
        }
        String severity = c.severity == null ? '' : c.severity.trim().toLowerCase();
        if (severity == 'blocker') {
            return 'D';
        }
        if (severity == 'major') {
            return 'C';
        }
        if (severity == 'minor') {
            return 'B';
        }
        return 'C';
    }

    /**
     * The estate, from the figures the assessment actually holds. There are
     * two numeric ones and three descriptive ones, and the panel prints what
     * exists -- a grid of five tiles where three would be blank is a grid that
     * looks like missing data rather than like an estate.
     */
    private static void putEstate(Map<String, Object> out, GTM_Assessment_Request__c req) {
        List<Object> tiles = new List<Object>();
        addTile(tiles, req.Contact_Count__c, 'CONTACTS / LEADS');
        addTile(tiles, req.Monthly_Send_Volume__c, 'SENDS PER MONTH');

        List<Object> facts = new List<Object>();
        addFact(facts, 'Environment', req.Environment_Size__c);
        addFact(facts, 'Migration team', req.Internal_Team_Size__c);
        addFact(facts, 'Timeline', req.Timeline__c);
        addFact(facts, 'Integrations to keep', req.Key_Integrations__c);

        if (tiles.isEmpty() && facts.isEmpty()) {
            return;
        }
        Map<String, Object> estate = new Map<String, Object>();
        if (!tiles.isEmpty()) {
            estate.put('tiles', tiles);
        }
        if (!facts.isEmpty()) {
            estate.put('facts', facts);
        }
        out.put('estate', estate);
    }

    private static void addTile(List<Object> tiles, Decimal value, String label) {
        if (value == null) {
            return;
        }
        tiles.add(new Map<String, Object>{ 'n' => value, 'label' => label });
    }

    private static void addFact(List<Object> facts, String label, String value) {
        if (String.isBlank(value)) {
            return;
        }
        facts.add(new Map<String, Object>{ 'label' => label, 'value' => value.trim() });
    }

    /**
     * The non-blocking annotations GtmAssessmentScoring raised -- the things
     * that are true even when the headline number looks good. They sit beside
     * the verdict rather than inside the breakdown, which is where the
     * high-rebuild-ratio note needs to be to do its job.
     */
    private static void putAnnotations(Map<String, Object> out, GTM_Assessment_Request__c req) {
        if (String.isBlank(req.Assessment_Flags__c)) {
            return;
        }
        List<Object> notes = new List<Object>();
        try {
            for (Object raw : (List<Object>) JSON.deserializeUntyped(req.Assessment_Flags__c)) {
                Map<String, Object> flag = (Map<String, Object>) raw;
                Object message = flag.get('message');
                if (message == null) {
                    continue;
                }
                Map<String, Object> row = new Map<String, Object>{ 'text' => String.valueOf(message) };
                putIfPresent(row, 'key', str(flag.get('key')));
                notes.add(row);
            }
        } catch (Exception e) {
            // Malformed -- the rest of the snapshot is still worth having.
        }
        if (!notes.isEmpty()) {
            out.put('annotations', notes);
        }
    }

    /** The gates that fired: a qualifier and a block of prose, never a band change. */
    private static void putGates(Map<String, Object> out, GtmAssessmentReadout.Readout adaptive) {
        if (adaptive == null || adaptive.gates.isEmpty()) {
            return;
        }
        List<Object> gates = new List<Object>();
        for (GtmAssessmentReadout.GateResult g : adaptive.gates) {
            Map<String, Object> row = new Map<String, Object>();
            putIfPresent(row, 'title', String.isBlank(g.qualifier) ? g.key : g.qualifier);
            putIfPresent(row, 'block', g.block);
            putIfPresent(row, 'severity', g.severity);
            gates.add(row);
        }
        out.put('gates', gates);
    }

    /**
     * "How we know" — the four provenance statements, worded from the posture
     * actually in force rather than from a fixed script. This is the panel that
     * earns the numbers above it.
     */
    private static void putBasis(Map<String, Object> out, GtmAssessmentReadout.Readout adaptive) {
        String source = adaptive == null ? null : adaptive.posture;
        Boolean instrumented = adaptive != null && adaptive.estateFiguresIllustrative != true;

        List<Object> rows = new List<Object>();
        rows.add(basis('Source scan.', instrumented
            ? 'The source estate was read directly and the counts above come from that read. ' +
              'A point-in-time snapshot, not a live feed.'
            : 'No connector read the source system. The estate figures above are your ' +
              'description of it, structured against what we know about the target.'));
        rows.add(basis('Self-reported.', 'Integrations, consent and team capacity are not ' +
            'machine-readable and came from your answers.'));
        rows.add(basis('Target modelled.', 'Constructs were checked against the target\'s real ' +
            'capability set, not a generic checklist.'));
        rows.add(basis('Not yet run.', 'No writes have been made to any system of yours. ' +
            'Nothing here changed anything.'));

        Map<String, Object> basisBlock = new Map<String, Object>{ 'how' => rows };
        putIfPresent(basisBlock, 'posture', source);
        out.put('basis', basisBlock);
    }

    private static Map<String, Object> basis(String lead, String rest) {
        return new Map<String, Object>{ 'lead' => lead, 'text' => rest };
    }

    private static List<Object> limitRows() {
        List<Object> rows = new List<Object>();
        for (String limitLine : LIMITS) {
            List<String> halves = limitLine.split('\\|');
            rows.add(new Map<String, Object>{
                'lead' => halves[0],
                'text' => halves.size() > 1 ? halves[1] : ''
            });
        }
        return rows;
    }

    // -------------------------------------------------------------- helpers

    /**
     * Rebuilds the adaptive half from what the request recorded. Moved here
     * from GtmReadoutController so the prose template and the data snapshot
     * cannot disagree about what the pack said -- they are now two renderings
     * of one composition, not two compositions.
     *
     * The pack is re-resolved from Instrument_Pair__c rather than from the
     * platform names, so reopening a year-old request reproduces the chain
     * that actually scored it.
     */
    public static GtmAssessmentReadout.Readout adaptiveReadout(GTM_Assessment_Request__c req) {
        if (req == null) {
            return null;
        }
        try {
            GtmAssessmentInstrument.Pack pack =
                GtmAssessmentInstrument.resolveByPairKey(req.Instrument_Pair__c);

            GtmAssessmentScoring.Score score = new GtmAssessmentScoring.Score();
            score.total = req.Assessment_Score__c;
            score.tier  = req.Assessment_Tier__c;
            score.sectionScores = intMap(req.Section_Scores__c);

            Map<String, Object> supplements = objectMap(req.Supplement_Scores__c);
            Map<String, Integer> answers = supplements.get('answers') == null
                ? new Map<String, Integer>()
                : toIntMap((Map<String, Object>) supplements.get('answers'));
            Map<String, String> notes = new Map<String, String>();
            if (supplements.get('notes') instanceof Map<String, Object>) {
                Map<String, Object> raw = (Map<String, Object>) supplements.get('notes');
                for (String k : raw.keySet()) {
                    notes.put(k, String.valueOf(raw.get(k)));
                }
            }
            return GtmAssessmentReadout.compose(score, pack, answers, notes);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Adaptive readout could not be composed for request ' + req.Id +
                ' -- ' + e.getTypeName() + '. The scored half of the draft is unaffected.'
            );
            return null;
        }
    }

    /** Display label for a platform key, falling back to what was stored. */
    private static String platformLabel(String rawName) {
        if (String.isBlank(rawName)) {
            return null;
        }
        try {
            return GtmMigrationPairs.labelFor(rawName);
        } catch (Exception e) {
            return rawName;
        }
    }

    /**
     * A stored "key -> value" score blob as display rows, with the wording
     * from GTM_Assessment_Question__mdt. A key with no configured label still
     * prints -- as the key -- because a missing label must not be able to
     * delete a line from the breakdown.
     */
    private static List<Object> scoreRows(String scoresJson, Integer max) {
        List<Object> rows = new List<Object>();
        if (String.isBlank(scoresJson)) {
            return rows;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(scoresJson);
            Map<String, String> names = dimensionNamesSafely();
            for (String key : parsed.keySet()) {
                String label = names.get(key);
                Map<String, Object> row = new Map<String, Object>();
                row.put('label', String.isBlank(label) ? key : label);
                try {
                    row.put('value', Integer.valueOf(String.valueOf(parsed.get(key))));
                } catch (Exception e) {
                    continue;
                }
                row.put('max', max);
                rows.add(row);
            }
        } catch (Exception e) {
            // Malformed JSON -- skip the breakdown, keep the rest.
        }
        return rows;
    }

    private static Map<String, String> dimensionNamesSafely() {
        try {
            return GtmAssessmentQuestions.dimensionNames();
        } catch (Exception e) {
            return new Map<String, String>();
        }
    }

    private static void putIfPresent(Map<String, Object> target, String key, String value) {
        if (String.isNotBlank(value)) {
            target.put(key, value);
        }
    }

    private static String str(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Map<String, Object> objectMap(String jsonStr) {
        if (String.isBlank(jsonStr)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static Map<String, Integer> intMap(String jsonStr) {
        return toIntMap(objectMap(jsonStr));
    }

    private static Map<String, Integer> toIntMap(Map<String, Object> raw) {
        Map<String, Integer> out = new Map<String, Integer>();
        for (String key : raw.keySet()) {
            try {
                out.put(key, Integer.valueOf(String.valueOf(raw.get(key))));
            } catch (Exception e) {
                // A non-numeric value is not an answer; skip it.
            }
        }
        return out;
    }
}
