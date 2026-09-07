import { createElement } from 'lwc';
import GtmReadoutView from 'c/gtmReadoutView';
import { splitSections, buildViewModel } from 'c/gtmReadoutView';
import getPublishedReadout from '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout';
import getCommentSections from '@salesforce/apex/GtmReadoutCommentController.getCommentSections';
import submitComment from '@salesforce/apex/GtmReadoutCommentController.submitComment';

const { SNAPSHOT, CONTENT } = require('./data/fixtures.js');

jest.mock(
    '@salesforce/apex/GtmReadoutPublicController.getPublishedReadout',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutCommentController.getCommentSections',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutCommentController.submitComment',
    () => ({ default: jest.fn() }), { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

/** Renders the component through the guest path with a given snapshot/prose. */
async function render({ data = SNAPSHOT, content = CONTENT, rep } = {}) {
    delete window.location;
    window.location = { search: '?token=abc123', hash: '', pathname: '/s/readout' };
    getPublishedReadout.mockResolvedValue({
        content,
        dataJson: data === null ? null : JSON.stringify(data),
        repName: rep ? rep.name : undefined,
        repEmail: rep ? rep.email : undefined,
        repPhone: rep ? rep.phone : undefined
    });
    const element = createElement('c-gtm-readout-view', { is: GtmReadoutView });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function text(element) {
    return element.shadowRoot.textContent.replace(/\s+/g, ' ');
}

/**
 * The prose, as it was handed to lightning-formatted-rich-text. The stub jest
 * substitutes for that component renders nothing, so textContent cannot see
 * prose — and reading the value is the more honest assertion anyway: it is
 * exactly what the sanitising component was asked to render.
 */
function prose(element) {
    return [...element.shadowRoot.querySelectorAll('lightning-formatted-rich-text')]
        .map((node) => node.value || '')
        .join(' ');
}

describe('the readout renders as the designed experience', () => {
    beforeEach(() => {
        getCommentSections.mockResolvedValue(['Verdict', 'Scorecard']);
        submitComment.mockResolvedValue({ accepted: true, message: 'Thanks' });
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('draws the designed furniture, not a wall of prose', async () => {
        const el = await render();
        // The pieces of the design that carry meaning, each present exactly
        // because the snapshot said something.
        expect(el.shadowRoot.querySelector('.verdict-masthead')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.stair')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.cx-grid')).not.toBeNull();
        expect(el.shadowRoot.querySelector('table.scorecard')).not.toBeNull();
        expect(el.shadowRoot.querySelector('table.wontport')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.inv')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.lanes')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.limits')).not.toBeNull();
        // Eight designed panels for this snapshot.
        expect(el.shadowRoot.querySelectorAll('.panel').length).toBe(8);
    });

    // ─── the scenario is data, not markup ────────────────────────────────

    it('says HubSpot and Marketing Cloud Engagement because the DATA says so', async () => {
        const el = await render();
        const body = text(el);
        expect(body).toContain('HUBSPOT MARKETING HUB → SFMC ENGAGEMENT');
        expect(body).toContain('COMMERCIAL METALS COMPANY');
        // Nothing from the mockup's original scenario survives anywhere.
        expect(body).not.toContain('Eloqua');
        expect(body).not.toContain('ELOQUA');
    });

    it('renders a different source and target from the same markup', async () => {
        // The architecture test: change the snapshot, change the readout. If
        // this ever needs a component edit, the split has not gone far enough.
        const other = clone(SNAPSHOT);
        other.company = 'Northwind Traders';
        other.pair.sourceLabel = 'Oracle Eloqua';
        other.pair.targetLabel = 'SFMC Next';
        const el = await render({ data: other });
        const body = text(el);
        expect(body).toContain('ORACLE ELOQUA → SFMC NEXT');
        expect(body).toContain('NORTHWIND TRADERS');
        expect(body).not.toContain('HubSpot Marketing Hub →');
    });

    // ─── the load-bearing content behaviours ─────────────────────────────

    it('never prints a bare score: the max travels with it', async () => {
        const el = await render();
        expect(text(el)).toContain('19 / 32');
        expect(text(el)).toContain('13 / 18');
    });

    it('uses the max frozen in the snapshot, not a max the renderer knows', async () => {
        // A recalibration next quarter must not redraw an already-approved
        // readout. The renderer has no opinion about what 32 should be.
        const other = clone(SNAPSHOT);
        other.readiness.max = 40;
        other.readiness.score = 24;
        const el = await render({ data: other });
        expect(text(el)).toContain('24 / 40');
    });

    it('prints tier and qualifier as one phrase', async () => {
        const el = await render();
        // "Prep Required" alone and "CRM-decision-gated" alone are each wrong.
        expect(text(el)).toContain('Prep Required, CRM-decision-gated');
    });

    it('puts the posture sentence ABOVE the score, not under it', async () => {
        const el = await render();
        const html = el.shadowRoot.querySelector('.panel').innerHTML;
        // A caveat printed under a number is a footnote, and footnotes are not
        // read out loud. Source order is what makes it not a footnote.
        expect(html.indexOf('posture')).toBeGreaterThan(-1);
        expect(html.indexOf('posture')).toBeLessThan(html.indexOf('bigscore'));
    });

    it('leads with the advisory banner and SUPPRESSES the tier under it', async () => {
        const advisory = clone(SNAPSHOT);
        advisory.advisory = { on: true, reason: 'This pair is not one the accelerator can process.', note: 'No readiness tier is shown.' };
        delete advisory.readiness.tier;
        delete advisory.readiness.tierPhrase;
        delete advisory.readiness.bands;
        const el = await render({ data: advisory });
        const first = el.shadowRoot.querySelector('.panel');
        expect(first.querySelector('.advisory')).not.toBeNull();
        // The advisory comes before the score in source order...
        expect(first.innerHTML.indexOf('advisory')).toBeLessThan(first.innerHTML.indexOf('bigscore'));
        // ...and the tier is absent rather than dashed. A dash invites someone
        // to fill it back in.
        expect(first.querySelector('.stair')).toBeNull();
        expect(text(el)).not.toContain('Prep Required');
        expect(text(el)).not.toContain('Engagement tier: —');
        // The score itself still renders — it is still useful input.
        expect(text(el)).toContain('19 / 32');
    });

    it('keeps complexity on its own axis, with its basis, never blended with readiness', async () => {
        const el = await render();
        const labels = [...el.shadowRoot.querySelectorAll('.axis-lbl')].map((n) => n.textContent);
        expect(labels).toContain('MIGRATION READINESS');
        expect(labels).toContain('ESTATE COMPLEXITY');
        expect(text(el)).toContain('Basis: Self-Estimated');
        expect(text(el)).toContain('a higher score means a bigger job, not a worse client');
    });

    it('puts a provenance chip on every scorecard row', async () => {
        const el = await render();
        const rows = el.shadowRoot.querySelectorAll('table.scorecard tbody tr');
        expect(rows.length).toBe(SNAPSHOT.dimensions.length);
        rows.forEach((row) => {
            expect(row.querySelector('.prov')).not.toBeNull();
        });
    });

    it('drives the illustrative marker off posture rather than hardcoding it', async () => {
        const shown = await render();
        expect(shown.shadowRoot.querySelector('.util-meta.sample')).not.toBeNull();
        expect(text(shown)).toContain('ILLUSTRATIVE FIGURES');

        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);

        const instrumented = clone(SNAPSHOT);
        instrumented.posture.illustrative = false;
        delete instrumented.posture.illustrativeNote;
        instrumented.dimensions.forEach((d) => { d.chip = 'MEASURED'; });
        const measured = await render({ data: instrumented });
        expect(measured.shadowRoot.querySelector('.util-meta.sample')).toBeNull();
        expect(text(measured)).not.toContain('ILLUSTRATIVE FIGURES');
        expect(measured.shadowRoot.querySelector('.prov.meas')).not.toBeNull();
    });

    it('carries a callout hedge onto the row it belongs to', async () => {
        const el = await render();
        const hedges = el.shadowRoot.querySelectorAll('.hedge');
        expect(hedges.length).toBe(1);
        expect(hedges[0].textContent).toContain('working model, not as a platform guarantee');
    });

    it('groups what will not port by tier, heaviest first', async () => {
        const el = await render();
        const groups = [...el.shadowRoot.querySelectorAll('.rowgroup th')].map((n) => n.textContent);
        expect(groups[0]).toContain('D ·');
        expect(groups[1]).toContain('C ·');
        expect(text(el)).toContain('D no equivalent, rebuild required');
    });

    it('prints all six limits, in full, never truncated', async () => {
        const el = await render();
        const basis = el.shadowRoot.querySelector('[data-panel="basis"]');
        const limits = basis.querySelectorAll('.limits')[1].querySelectorAll('.lim');
        expect(limits.length).toBe(6);
        SNAPSHOT.limits.forEach((row) => {
            expect(basis.textContent).toContain(row.lead);
            expect(basis.textContent).toContain(row.text);
        });
    });

    // ─── the prose half ──────────────────────────────────────────────────

    it('routes each prose section into the panel that owns it', async () => {
        const el = await render();
        const proseIn = (id) => {
            const rich = el.shadowRoot.querySelector('[data-panel="' + id + '"] lightning-formatted-rich-text');
            return rich ? rich.value : '';
        };
        expect(proseIn('verdict')).toContain('the CRM decision has');
        expect(proseIn('findings')).toContain('critical path');
        expect(proseIn('gaps')).toContain('rebuild rather than move');
        expect(proseIn('context')).toContain('project-cycle nurture');
        expect(proseIn('next')).toContain('A named owner for the CRM decision');
    });

    it('sends every piece of prose through lightning-formatted-rich-text', async () => {
        // Prose reaches the DOM only through the sanitising component; nothing
        // below sets innerHTML from content a rep or a prospect supplied.
        const el = await render({
            content: '<h2>Verdict</h2><p>Fine.</p><script>alert(1)</script>'
        });
        expect(el.shadowRoot.querySelector('script')).toBeNull();
        const rich = el.shadowRoot.querySelectorAll('lightning-formatted-rich-text');
        expect(rich.length).toBeGreaterThan(0);
    });

    it('never drops a section it does not recognise', async () => {
        const el = await render({
            content: CONTENT + '\n<h2>Commercial terms</h2><p>Rate card attached.</p>'
        });
        expect(text(el)).toContain('Commercial terms');
        expect(prose(el)).toContain('Rate card attached.');
    });

    it('renders the prose alone when there is no snapshot at all', async () => {
        // The honest degradation: no designed panels, but nothing is lost and
        // no number is invented.
        const el = await render({ data: null });
        expect(el.shadowRoot.querySelector('.stair')).toBeNull();
        expect(el.shadowRoot.querySelector('table.scorecard')).toBeNull();
        expect(prose(el)).toContain('the CRM decision has');
        expect(text(el)).not.toContain('19 / 32');
    });

    it('renders the snapshot alone when there is no prose', async () => {
        const el = await render({ content: '' });
        expect(text(el)).toContain('19 / 32');
        expect(el.shadowRoot.querySelector('table.scorecard')).not.toBeNull();
    });

    it('ignores an unparseable snapshot rather than rendering half a page', async () => {
        delete window.location;
        window.location = { search: '?token=abc123', hash: '', pathname: '/s/readout' };
        getPublishedReadout.mockResolvedValue({ content: CONTENT, dataJson: '{not json' });
        const el = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        document.body.appendChild(el);
        await flushPromises();
        expect(el.shadowRoot.querySelector('.rv-notfound')).toBeNull();
        expect(prose(el)).toContain('the CRM decision has');
    });

    // ─── omission rather than invention ──────────────────────────────────

    it('omits a panel rather than inventing a value for it', async () => {
        const sparse = clone(SNAPSHOT);
        delete sparse.estate;
        delete sparse.gaps;
        delete sparse.horizon;
        const el = await render({ data: sparse, content: '<h2>Verdict</h2><p>Short.</p>' });
        expect(el.shadowRoot.querySelector('.inv')).toBeNull();
        expect(el.shadowRoot.querySelector('table.wontport')).toBeNull();
        expect(el.shadowRoot.querySelector('.lanes')).toBeNull();
        // And nothing plausible-looking has appeared in their place.
        expect(text(el)).not.toContain('undefined');
        expect(text(el)).not.toContain('NaN');
    });

    it('shows no contact block when the readout has no resolvable rep', async () => {
        const el = await render();
        expect(el.shadowRoot.querySelector('.close-grid')).toBeNull();
    });

    it('shows the rep as the close when there is one', async () => {
        const el = await render({
            rep: { name: 'Jordan Reyes', email: 'jordan.reyes@publicissapient.com', phone: '+1 (312) 555-0148' }
        });
        expect(el.shadowRoot.querySelector('.avatar').textContent).toBe('JR');
        const mail = el.shadowRoot.querySelector('.who a');
        expect(mail.getAttribute('href')).toContain('mailto:');
    });

    // ─── modes ───────────────────────────────────────────────────────────

    it('defaults to Read, and stays there where a pager would not work', async () => {
        // jsdom reports no matches for the pointer/width query, which is the
        // phone case: a pager form is never forced onto a screen with no room
        // to page.
        const el = await render();
        expect(el.shadowRoot.querySelector('.rv-root').dataset.mode).toBe('read');
        const [present] = el.shadowRoot.querySelectorAll('.viewtoggle button');
        present.click();
        await flushPromises();
        expect(el.shadowRoot.querySelector('.rv-root').dataset.mode).toBe('read');
    });

    it('offers Present, Read and Print, and Read is pressed by default', async () => {
        const el = await render();
        const buttons = [...el.shadowRoot.querySelectorAll('.viewtoggle button')];
        expect(buttons.map((b) => b.textContent)).toEqual(['PRESENT', 'READ', 'PRINT']);
        expect(buttons[1].className).toContain('on');
    });

    it('enters Present when the viewport genuinely suits one', async () => {
        const original = window.matchMedia;
        window.matchMedia = () => ({ matches: true, addEventListener() {}, removeEventListener() {} });
        try {
            const el = await render();
            expect(el.shadowRoot.querySelector('.rv-root').dataset.mode).toBe('present');
            expect(el.shadowRoot.querySelector('.counter').textContent).toBe('01 / 08');
        } finally {
            window.matchMedia = original;
        }
    });

    // ─── preview, for the rep and the approver ───────────────────────────

    it('previews an unsaved draft without calling the guest endpoint', async () => {
        const el = createElement('c-gtm-readout-view', { is: GtmReadoutView });
        el.previewMode = true;
        el.previewData = JSON.stringify(SNAPSHOT);
        el.previewContent = '<h2>Verdict</h2><p>Still being written.</p>';
        document.body.appendChild(el);
        await flushPromises();

        expect(getPublishedReadout).not.toHaveBeenCalled();
        expect(prose(el)).toContain('Still being written.');
        expect(text(el)).toContain('19 / 32');
        // No comment box and no view toggle inside the editor.
        expect(el.shadowRoot.querySelector('.rv-comment')).toBeNull();
        expect(el.shadowRoot.querySelector('.viewtoggle')).toBeNull();
    });
});

describe('splitSections', () => {
    it('splits on h2 and keeps h3 children inside their section', () => {
        const sections = splitSections(
            '<h2>Verdict</h2><p>a</p><h3>Sub</h3><p>b</p><h2>Findings</h2><p>c</p>'
        );
        expect(sections.map((s) => s.heading)).toEqual(['Verdict', 'Findings']);
        expect(sections[0].body).toContain('<h3>Sub</h3>');
        expect(sections[0].body).toContain('<p>b</p>');
        expect(sections[1].body).toBe('<p>c</p>');
    });

    it('keeps anything written above the first heading', () => {
        const sections = splitSections('<p>preamble</p><h2>Verdict</h2><p>a</p>');
        expect(sections[0].heading).toBe('');
        expect(sections[0].body).toBe('<p>preamble</p>');
    });

    it('matches headings the way the server does — case and whitespace insensitive', () => {
        const sections = splitSections('<h2>  the   PATH </h2><p>x</p>');
        expect(sections[0].heading).toBe('the PATH');
    });

    it('treats headingless content as one unnamed section', () => {
        const sections = splitSections('<p>just words</p>');
        expect(sections).toEqual([{ heading: '', body: '<p>just words</p>' }]);
    });

    it('returns nothing for nothing', () => {
        expect(splitSections('')).toEqual([]);
        expect(splitSections(null)).toEqual([]);
    });
});

describe('buildViewModel', () => {
    it('returns null when there is neither prose nor data', () => {
        expect(buildViewModel(null, [], null)).toBeNull();
    });

    it('numbers the panels it actually built, with no gaps', () => {
        const model = buildViewModel(SNAPSHOT, splitSections(CONTENT), null);
        const eyebrows = model.panels.map((p) => p.eyebrow.slice(0, 2));
        expect(eyebrows).toEqual(['01', '02', '03', '04', '05', '06', '07', '08']);
    });

    it('marks a dimension weak at or below half of its own maximum', () => {
        const model = buildViewModel(SNAPSHOT, [], null);
        const scorecard = model.panels.find((p) => p.isScorecard);
        expect(scorecard.rows.filter((r) => r.weak).length).toBe(5);
        expect(scorecard.scanNote).toContain('5 of 8 dimensions score at or below half');
    });

    it('counts nothing weak honestly rather than suppressing the sentence', () => {
        const strong = clone(SNAPSHOT);
        strong.dimensions.forEach((d) => { d.value = 4; });
        const model = buildViewModel(strong, [], null);
        const scorecard = model.panels.find((p) => p.isScorecard);
        expect(scorecard.scanNote).toContain('No dimension scores at or below half');
    });

    it('lights exactly the band the snapshot marked current', () => {
        const model = buildViewModel(SNAPSHOT, [], null);
        const verdict = model.panels[0];
        const lit = verdict.readiness.bands.filter((b) => b.cls.indexOf(' on') > -1);
        expect(lit.length).toBe(1);
        expect(lit[0].label).toBe('Prep Required');
    });

    it('abbreviates estate counts without losing their scale', () => {
        const model = buildViewModel(SNAPSHOT, [], null);
        const estate = model.panels.find((p) => p.isEstate);
        expect(estate.tiles.map((t) => t.n)).toEqual(['240k', '310k']);
    });
});
