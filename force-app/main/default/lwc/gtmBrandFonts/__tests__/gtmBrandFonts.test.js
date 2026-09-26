import { loadBrandFonts } from 'c/gtmBrandFonts';

describe('c/gtmBrandFonts', () => {
    afterEach(() => {
        document
            .querySelectorAll('link[data-gtm-brand-fonts="1"]')
            .forEach((el) => el.remove());
    });

    it('injects the three-family Google Fonts stylesheet into the document head', () => {
        loadBrandFonts();
        const link = document.querySelector('link[data-gtm-brand-fonts="1"]');
        expect(link).not.toBeNull();
        expect(link.rel).toBe('stylesheet');
        expect(link.href).toContain('family=Lexend+Deca');
        expect(link.href).toContain('family=Roboto:');
        expect(link.href).toContain('family=Roboto+Mono');
    });

    it('is idempotent: a second call does not add a duplicate link', () => {
        loadBrandFonts();
        loadBrandFonts();
        expect(document.querySelectorAll('link[data-gtm-brand-fonts="1"]').length).toBe(1);
    });

    it('swallows errors so a failed injection never throws', () => {
        const spy = jest.spyOn(document.head, 'appendChild').mockImplementation(() => {
            throw new Error('boom');
        });
        expect(() => loadBrandFonts()).not.toThrow();
        spy.mockRestore();
    });
});
