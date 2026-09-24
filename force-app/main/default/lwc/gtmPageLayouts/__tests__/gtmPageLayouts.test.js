import { addableLayouts, TEMPLATE_LAYOUTS, LAYOUT_FIELDS, LAYOUT_LABELS } from 'c/gtmPageLayouts';

// Issue #26, item (a): the Configurator's own "Add section" modal never
// offered Industry angle (industry-profile) as a layout choice at all,
// because TEMPLATE_LAYOUTS.configurator's whitelist was missing that one
// entry -- LAYOUT_FIELDS/LAYOUT_LABELS/LAYOUT_HINTS/SECTION_ICONS for
// industry-profile were already fully defined and unaffected. This guards the
// whitelist entry so the gap cannot silently reopen.
describe('gtmPageLayouts addableLayouts(configurator)', () => {
    it('includes industry-profile in the configurator whitelist', () => {
        expect(TEMPLATE_LAYOUTS.configurator).toContain('industry-profile');
    });

    it('offers Industry angle as an addable layout on the configurator template', () => {
        const options = addableLayouts('configurator');
        const hit = options.find((o) => o.value === 'industry-profile');
        expect(hit).toBeDefined();
        expect(hit.label).toBe(LAYOUT_LABELS['industry-profile']);
        expect(hit.fieldCount).toBeGreaterThan(0);
    });

    it('still offers every previously-whitelisted configurator layout', () => {
        const values = addableLayouts('configurator').map((o) => o.value);
        [
            'chapter-cards',
            'chapter-lede',
            'chapter-proof',
            'chapter-phases',
            'chapter-close',
            'offering-defaults'
        ].forEach((k) => expect(values).toContain(k));
    });

    it('does not offer industry-profile on templates that do not whitelist it', () => {
        // 'story' has its own whitelist that never included industry-profile.
        const values = addableLayouts('story').map((o) => o.value);
        expect(values).not.toContain('industry-profile');
    });

    it('LAYOUT_FIELDS already fully models industry-profile (unaffected by this fix)', () => {
        const spec = LAYOUT_FIELDS['industry-profile'];
        expect(spec).toBeDefined();
        expect(spec.rich).toEqual(
            expect.arrayContaining(['problem', 'useCase', 'solution', 'proofLine', 'whyLine'])
        );
    });
});

// add-industry: createIndustry seeds fieldsFor('industry-tile') and the public reader
// (GtmPageContentReader.getIndustryProfiles) consumes exactly these 12 keys. Apex
// does not hard-code them, so this list and the Apex drift-alarm test guard each side.
describe('gtmPageLayouts industry-tile field vocabulary', () => {
    it('models exactly the 12 keys the industry reader consumes', () => {
        const spec = LAYOUT_FIELDS['industry-tile'];
        const keys = [].concat(spec.text || [], spec.rich || [], spec.json || [], spec.icontext || []);
        expect(keys.sort()).toEqual([
            'coverSub', 'demoDeps', 'demoRoot', 'industryLabel', 'pickerBlurb', 'problem',
            'proofLine', 'solution', 'uniquePoints', 'useCase', 'whyHead', 'whyLine'
        ]);
    });
});
