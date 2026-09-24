import { createElement } from 'lwc';
import GtmLinkRecovery from 'c/gtmLinkRecovery';
import recoverLink from '@salesforce/apex/GtmLinkRecoveryController.recoverLink';

jest.mock(
    '@salesforce/apex/GtmLinkRecoveryController.recoverLink',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createElement_() {
    const el = createElement('c-gtm-link-recovery', { is: GtmLinkRecovery });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

describe('gtmLinkRecovery', () => {
    it('renders input form by default', () => {
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        const btn = el.shadowRoot.querySelector('lightning-button');
        expect(input).not.toBeNull();
        expect(btn).not.toBeNull();
        const confirmation = el.shadowRoot.querySelector('p');
        expect(confirmation).toBeNull();
    });

    it('invalid email blocks Apex call', async () => {
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.value = 'notanemail';
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'notanemail' } }));
        await Promise.resolve();

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(recoverLink).not.toHaveBeenCalled();
        const errP = el.shadowRoot.querySelector('p.error');
        expect(errP).not.toBeNull();
    });

    it('valid email calls recoverLink and shows confirmation', async () => {
        recoverLink.mockResolvedValue('OK');
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.value = 'test@example.com';
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'test@example.com' } }));
        await Promise.resolve();

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(recoverLink).toHaveBeenCalledTimes(1);
        expect(recoverLink).toHaveBeenCalledWith({ email: 'test@example.com' });
        await Promise.resolve();
        const p = el.shadowRoot.querySelector('p');
        expect(p).not.toBeNull();
        expect(p.textContent).toContain("If that email matches an engagement link");
    });

    it('shows generic error message on reject (not Apex message)', async () => {
        recoverLink.mockRejectedValue(new Error('Apex internal error'));
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.value = 'test@example.com';
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'test@example.com' } }));
        await Promise.resolve();

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();
        await Promise.resolve();

        const errP = el.shadowRoot.querySelector('p.error');
        expect(errP).not.toBeNull();
        expect(errP.textContent).not.toContain('Apex internal error');
        expect(errP.textContent).toContain('Something went wrong');
    });
});
