import { createElement } from 'lwc';
import GtmModalShell from 'c/gtmModalShell';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-gtm-modal-shell', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('reflects isOpen=false as the closed state (no open class) by default', () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        document.body.appendChild(element);

        const scrim = element.shadowRoot.querySelector('.gms-scrim');
        const sheet = element.shadowRoot.querySelector('.gms-sheet');
        expect(scrim.classList.contains('open')).toBe(false);
        expect(sheet.classList.contains('open')).toBe(false);
    });

    it('reflects isOpen=true as the open state', () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        element.isOpen = true;
        document.body.appendChild(element);

        const scrim = element.shadowRoot.querySelector('.gms-scrim');
        const sheet = element.shadowRoot.querySelector('.gms-sheet');
        expect(scrim.classList.contains('open')).toBe(true);
        expect(sheet.classList.contains('open')).toBe(true);
    });

    it('renders the title', () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        element.title = 'My Title';
        document.body.appendChild(element);

        const title = element.shadowRoot.querySelector('.gms-title');
        expect(title.textContent).toBe('My Title');
    });

    it('fires close on scrim click', () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        element.isOpen = true;
        document.body.appendChild(element);

        const handler = jest.fn();
        element.addEventListener('close', handler);

        element.shadowRoot.querySelector('.gms-scrim').click();

        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('fires close on the explicit close control', () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        element.isOpen = true;
        document.body.appendChild(element);

        const handler = jest.fn();
        element.addEventListener('close', handler);

        element.shadowRoot.querySelector('.gms-x').click();

        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('projects default slot content', () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        const body = document.createElement('div');
        body.className = 'my-body-content';
        body.textContent = 'body';
        element.appendChild(body);
        document.body.appendChild(element);

        expect(element.shadowRoot.querySelector('slot:not([name])')).not.toBeNull();
        const projected = document.body.querySelector('.my-body-content');
        expect(projected).not.toBeNull();
        expect(projected.textContent).toBe('body');
    });

    it('projects header-extras slot content', () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        const extra = document.createElement('div');
        extra.className = 'my-header-extra';
        extra.setAttribute('slot', 'header-extras');
        element.appendChild(extra);
        document.body.appendChild(element);

        expect(element.shadowRoot.querySelector('slot[name="header-extras"]')).not.toBeNull();
        const projected = document.body.querySelector('.my-header-extra');
        expect(projected).not.toBeNull();
    });

    it('does not apply a top offset style when chrome-offset is absent (default false)', async () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        document.body.appendChild(element);
        await flushPromises();

        const sheet = element.shadowRoot.querySelector('.gms-sheet');
        expect(sheet.getAttribute('style') || '').toBe('');
    });

    it('applies a measured top offset style when chrome-offset is true', async () => {
        const element = createElement('c-gtm-modal-shell', { is: GtmModalShell });
        element.chromeOffset = true;
        document.body.appendChild(element);
        await flushPromises();

        const sheet = element.shadowRoot.querySelector('.gms-sheet');
        expect(sheet.getAttribute('style')).toMatch(/top:\d+px;/);
    });
});
