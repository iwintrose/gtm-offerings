import { createElement } from 'lwc';
import GtmInstrumentAuthor from 'c/gtmInstrumentAuthor';
import getPlatforms from '@salesforce/apex/GtmAssessmentInstrument.getPlatforms';
import getPack from '@salesforce/apex/GtmAssessmentInstrument.getPack';
import getFrame from '@salesforce/apex/GtmAssessmentInstrument.getFrame';
import getOfferings from '@salesforce/apex/GtmPageContentController.getOfferings';

jest.mock(
    '@salesforce/apex/GtmPageContentController.getOfferings',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentInstrument.getPlatforms',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentInstrument.getPack',
    () => ({ default: jest.fn() }), { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmAssessmentInstrument.getFrame',
    () => ({ default: jest.fn() }), { virtual: true }
);

const flush = () => new Promise((r) => setTimeout(r, 0));

const FRAME = {
    slotCount: 8,
    minAnswerValue: 1,
    maxAnswerValue: 4,
    minTotal: 8,
    maxTotal: 32,
    bands: [
        { tier: 'Discovery First', lowest: 8, highest: 14 },
        { tier: 'Prep Required', lowest: 15, highest: 20 },
        { tier: 'Accelerator-Ready', lowest: 21, highest: 26 },
        { tier: 'Fast-Track', lowest: 27, highest: 32 }
    ]
};

function opts(points) {
    return [1, 2, 3, 4].map((v) => ({
        value: v,
        label: `option ${v}`,
        points: points ? points[v - 1] : v,
        available: true
    }));
}

function slot(position, key, extra = {}) {
    return {
        position,
        key,
        baseKey: key,
        label: `Slot ${position}`,
        question: `Question ${position}?`,
        variantKey: 'default',
        substitutable: position !== 1 && position !== 8,
        options: opts(),
        variants: [],
        ...extra
    };
}

function pack() {
    const branched = slot(7, 'consent_portability');
    branched.variants = [
        {
            ...slot(7, 'consent_ownership_outside_platform'),
            baseKey: 'consent_portability',
            variantKey: 'consent_owned_elsewhere',
            question: 'Who masters consent?',
            options: opts([1, 1, 3, 4]),
            showWhenJson: '{"all":[{"field":"estate_scale","op":"lte","value":2}]}'
        }
    ];
    return {
        pairKey: 'sfmc__mcn',
        version: '2026.09.1',
        sourceKey: 'sfmc',
        targetKey: 'sfmc_next',
        supplements: [],
        slots: [
            slot(1, 'estate_scale'),
            slot(2, 'source_access'),
            slot(3, 'orchestration_portability'),
            slot(4, 'content_portability'),
            slot(5, 'data_model_readiness'),
            slot(6, 'integration_containment'),
            branched,
            slot(8, 'decision_readiness')
        ]
    };
}

async function mount() {
    const el = createElement('c-gtm-instrument-author', { is: GtmInstrumentAuthor });
    document.body.appendChild(el);
    // connectedCallback now awaits getOfferings, then getPlatforms, then the
    // per-offering frame and pack -- a longer promise chain than before the
    // offering selector existed, so it needs more microtask turns to settle.
    await flush();
    await flush();
    await flush();
    await flush();
    return el;
}

const q = (el, sel) => el.shadowRoot.querySelectorAll(sel);
const one = (el, sel) => el.shadowRoot.querySelector(sel);

function selectSlot(el, key) {
    Array.from(q(el, '.ia-slot')).find((b) => b.dataset.key === key).click();
}

describe('c-gtm-instrument-author', () => {
    beforeEach(() => {
        getPlatforms.mockResolvedValue([{ key: 'sfmc', label: 'SFMC' }]);
        getOfferings.mockResolvedValue([
            { offeringKey: 'migration-accelerator', label: 'Migration Accelerator' }
        ]);
        getFrame.mockResolvedValue(FRAME);
        getPack.mockResolvedValue(pack());
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
        window.localStorage.clear();
    });

    it('lists all eight slots and marks the pinned ones', async () => {
        const el = await mount();
        expect(q(el, '.ia-slot').length).toBe(8);
        const metas = Array.from(q(el, '.ia-slot-meta')).map((m) => m.textContent);
        expect(metas[0]).toContain('pinned');
        expect(metas[7]).toContain('pinned');
        expect(metas[6]).toContain('1 branch');
    });

    it('shows a slot as a default plus its branches, default first', async () => {
        const el = await mount();
        selectSlot(el, 'consent_portability');
        await flush();
        const heads = Array.from(q(el, '.ia-card-head')).map((h) => h.textContent.trim());
        expect(heads[0]).toBe('Default — always applies');
        expect(heads[1]).toBe('Branch: consent_owned_elsewhere');
    });

    it('exposes a points box per option and reports what the question is worth', async () => {
        const el = await mount();
        selectSlot(el, 'consent_portability');
        await flush();
        const boxes = q(el, '.ia-td-p input');
        expect(boxes.length).toBe(8); // four options on the default, four on the branch
        const ranges = Array.from(q(el, '.ia-range')).map((r) => r.textContent.trim());
        expect(ranges[0]).toContain('1–4');
        expect(ranges[1]).toContain('1–4'); // 1/1/3/4 still bottoms at 1 and tops at 4
    });

    it('warns the moment an edit stops the question being worth 1-4', async () => {
        const el = await mount();
        selectSlot(el, 'estate_scale');
        await flush();
        const top = Array.from(q(el, '.ia-td-p input')).find((i) => i.dataset.index === '3');
        top.value = '3';
        top.dispatchEvent(new CustomEvent('change'));
        await flush();
        const warn = one(el, '.ia-warn');
        expect(warn).not.toBeNull();
        expect(warn.textContent).toContain('worth 1–3');
        expect(warn.textContent).toContain('32');
    });

    it('flags a branch predicate that is not valid JSON, because an inert branch looks like no branch', async () => {
        const el = await mount();
        selectSlot(el, 'consent_portability');
        await flush();
        const box = one(el, '.ia-code');
        box.value = '{not json';
        box.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(one(el, '.ia-warn').textContent).toContain('inert');
    });

    it('emits the edit as YAML for the pair file rather than writing metadata', async () => {
        const el = await mount();
        selectSlot(el, 'estate_scale');
        await flush();
        const box = q(el, '.ia-td-p input')[1];
        box.value = '1';
        box.dispatchEvent(new CustomEvent('change'));
        await flush();
        const yaml = one(el, '.ia-yaml').textContent;
        expect(yaml).toContain('- dimension: estate_scale');
        expect(yaml).toContain('points: 1');
        expect(yaml).toContain('build-instrument.py');
    });

    it('preview walks the branch and always shows eight questions', async () => {
        const el = await mount();
        one(el, '.ia-tabs .ia-tab:last-child').click();
        await flush();
        expect(q(el, '.ia-popts').length).toBe(8);

        // Answering slot 1 low fires the branch on slot 7.
        one(el, '.ia-popt[data-key="estate_scale"][data-value="1"]').click();
        await flush();
        expect(q(el, '.ia-popts').length).toBe(8);
        expect(one(el, '.ia-badge').textContent).toContain('consent_owned_elsewhere');

        // And answering it high puts the default back.
        one(el, '.ia-popt[data-key="estate_scale"][data-value="4"]').click();
        await flush();
        expect(q(el, '.ia-popts').length).toBe(8);
        expect(one(el, '.ia-badge')).toBeNull();
    });

    it('shows the band only once every slot is answered, and reads its edges from the server', async () => {
        const el = await mount();
        one(el, '.ia-tabs .ia-tab:last-child').click();
        await flush();
        one(el, '.ia-popt[data-key="estate_scale"][data-value="4"]').click();
        await flush();
        expect(one(el, '.ia-score-band')).toBeNull();

        // Answer every slot at 4 -> 32 -> Fast-Track.
        for (let i = 0; i < 10; i++) {
            const next = Array.from(q(el, '.ia-popt[data-value="4"]')).find(
                (b) => !b.classList.contains('ia-popt--on')
            );
            if (!next) break;
            next.click();
            // eslint-disable-next-line no-await-in-loop
            await flush();
        }
        expect(one(el, '.ia-score-n').textContent).toBe('32 of 32');
        expect(one(el, '.ia-score-band').textContent).toBe('Fast-Track');
    });

    it('shows the branch path the answers took, keyed by base slot', async () => {
        const el = await mount();
        one(el, '.ia-tabs .ia-tab:last-child').click();
        await flush();
        one(el, '.ia-popt[data-key="estate_scale"][data-value="1"]').click();
        await flush();
        const rows = Array.from(q(el, '.ia-path tr')).map((r) => r.textContent);
        expect(rows.length).toBe(8);
        expect(rows[6]).toContain('consent_owned_elsewhere');
        expect(rows[6]).toContain('consent_ownership_outside_platform');
    });

    it('shows the orientation panel expanded on first visit, and it persists dismissal via localStorage', async () => {
        const el = await mount();
        expect(one(el, '.ia-orient')).not.toBeNull();
        expect(one(el, '.ia-orient-reopen')).toBeNull();
        expect(one(el, '.ia-orient').textContent).toContain('What this is');
        // The reachability caveat ("the live GTM1 site's booking form does not
        // yet ask these questions, so editing a pack here does not change what
        // a real prospect sees today") is deliberately GONE as of ADR-0008 /
        // backlog D11: the live /configurator route now hosts the real
        // questionnaire, so a pack edited here DOES change what a real prospect
        // is asked. Asserted as an absence so the banner cannot come back
        // untruthfully by accident.
        expect(one(el, '.ia-orient').textContent).not.toContain('down for');
        expect(one(el, '.ia-orient').textContent).not.toContain('Heads up');
        expect(one(el, '.ia-orient-warn')).toBeNull();

        one(el, '.ia-orient-dismiss').click();
        await flush();
        expect(one(el, '.ia-orient')).toBeNull();
        expect(one(el, '.ia-orient-reopen')).not.toBeNull();
        expect(window.localStorage.getItem('gtmInstrumentAuthor.orientationCollapsed')).toBe('1');

        // Reload picks up the persisted dismissal.
        document.body.removeChild(el);
        const el2 = await mount();
        expect(one(el2, '.ia-orient')).toBeNull();
        expect(one(el2, '.ia-orient-reopen').textContent).toContain('Any source → Any target');
    });

    it('surfaces the resolution chain and note the pack response already carries', async () => {
        getPack.mockResolvedValue({ ...pack(), resolutionChain: ['base', 'sfmc__mcn'], resolutionNote: null });
        const el = await mount();
        expect(one(el, '.ia-chain').textContent).toContain('base → sfmc__mcn');
    });

    it('shows the undecided-target note when the server returns one and no chain to render', async () => {
        getPack.mockResolvedValue({ ...pack(), resolutionChain: [], resolutionNote: 'Target platform not yet chosen.' });
        const el = await mount();
        expect(one(el, '.ia-chain')).not.toBeNull();
        expect(one(el, '.ia-chain--note').textContent).toBe('Target platform not yet chosen.');
    });
});

describe('c-gtm-instrument-author offering selection', () => {
    beforeEach(() => {
        getPlatforms.mockResolvedValue([{ key: 'sfmc', label: 'SFMC' }]);
        getFrame.mockResolvedValue(FRAME);
        getPack.mockResolvedValue(pack());
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
        window.localStorage.clear();
    });

    it('keys the frame and pack on the chosen offering, not on a hardcoded default', async () => {
        getOfferings.mockResolvedValue([
            { offeringKey: 'migration-accelerator', label: 'Migration Accelerator' }
        ]);
        await mount();
        expect(getFrame).toHaveBeenCalledWith({ offeringKey: 'migration-accelerator' });
        expect(getPack).toHaveBeenCalledWith({
            offeringKey: 'migration-accelerator',
            sourceName: '',
            targetName: ''
        });
    });

    it('drops the framework pseudo-offering, which owns page content and not an instrument', async () => {
        getOfferings.mockResolvedValue([
            { offeringKey: 'gtm', label: 'Framework' },
            { offeringKey: 'migration-accelerator', label: 'Migration Accelerator' }
        ]);
        const el = await mount();
        // Two rows in, one instrument-bearing offering out -- so it presets to
        // that one and the picker stays hidden, exactly as for a single row.
        const picker = el.shadowRoot.querySelector('lightning-combobox');
        expect(picker).toBeNull();
        expect(getFrame).toHaveBeenCalledWith({ offeringKey: 'migration-accelerator' });
    });

    it('shows a picker for 2+ offerings and re-resolves both frame and pack on switch', async () => {
        getOfferings.mockResolvedValue([
            { offeringKey: 'migration-accelerator', label: 'Migration Accelerator' },
            { offeringKey: 'second-offering', label: 'Second Offering' }
        ]);
        const el = await mount();
        const picker = el.shadowRoot.querySelector('lightning-combobox');
        expect(picker).not.toBeNull();
        // Neither is preset with two to choose from, so nothing is resolved yet:
        // showing one offering's instrument before the author picked would be a
        // guess, and guessing wrong is the leak this screen now prevents.
        expect(getFrame).not.toHaveBeenCalled();
        expect(getPack).not.toHaveBeenCalled();

        picker.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'second-offering' } })
        );
        await flush();
        await flush();
        expect(getFrame).toHaveBeenCalledWith({ offeringKey: 'second-offering' });
        expect(getPack).toHaveBeenCalledWith({
            offeringKey: 'second-offering',
            sourceName: '',
            targetName: ''
        });
    });
});
