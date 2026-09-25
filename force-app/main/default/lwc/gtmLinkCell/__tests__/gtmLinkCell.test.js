import { createElement } from 'lwc';
import GtmLinkCell from 'c/gtmLinkCell';

function mount(typeAttributes) {
    const el = createElement('c-gtm-link-cell', { is: GtmLinkCell });
    el.typeAttributes = typeAttributes;
    document.body.appendChild(el);
    return el;
}

describe('gtmLinkCell', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('lookup present: renders a link-styled, focusable, clickable element and keeps the title tooltip', async () => {
        const el = mount({
            label: 'Acme Corp',
            name: 'openAccount',
            disabled: false,
            title: 'Open account',
            targetId: '001000000000001AAA',
            idField: 'accountId'
        });
        await Promise.resolve();
        const link = el.shadowRoot.querySelector('a.gtm-link-cell_interactive');
        expect(link).not.toBeNull();
        expect(link.textContent).toBe('Acme Corp');
        expect(link.title).toBe('Open account');
        expect(link.tabIndex).toBe(0);
        expect(el.shadowRoot.querySelector('span')).toBeNull();
    });

    it('lookup present: click dispatches a rowaction-shaped event handleRowAction can consume', async () => {
        const el = mount({
            label: 'Acme Corp',
            name: 'openAccount',
            disabled: false,
            title: 'Open account',
            targetId: '001000000000001AAA',
            idField: 'accountId'
        });
        await Promise.resolve();
        const handler = jest.fn();
        el.addEventListener('rowaction', handler);
        el.shadowRoot.querySelector('a').click();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            action: { name: 'openAccount' },
            row: { accountId: '001000000000001AAA' }
        });
    });

    it('lookup present: Enter/Space also activates (keyboard accessibility)', async () => {
        const el = mount({
            label: 'Jane', name: 'openContact', disabled: false,
            title: 'Open contact', targetId: '003000000000001AAA', idField: 'contactId'
        });
        await Promise.resolve();
        const handler = jest.fn();
        el.addEventListener('rowaction', handler);
        const link = el.shadowRoot.querySelector('a');
        link.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.row).toEqual({ contactId: '003000000000001AAA' });
    });

    it('no lookup: renders non-interactive plain text but keeps the "no account" title, and never dispatches', async () => {
        const el = mount({
            label: 'Acme Co',
            name: 'openAccount',
            disabled: true,
            title: 'No account on this link',
            targetId: null,
            idField: 'accountId'
        });
        await Promise.resolve();
        const span = el.shadowRoot.querySelector('span.gtm-link-cell_static');
        expect(span).not.toBeNull();
        expect(span.textContent).toBe('Acme Co');
        expect(span.title).toBe('No account on this link');
        expect(el.shadowRoot.querySelector('a')).toBeNull();

        const handler = jest.fn();
        el.addEventListener('rowaction', handler);
        span.dispatchEvent(new MouseEvent('click'));
        expect(handler).not.toHaveBeenCalled();
    });

    it('renders the same alignment/left-aligned block class whether interactive or not', async () => {
        const interactive = mount({ label: 'A', disabled: false, name: 'openAccount', idField: 'accountId' });
        const staticEl = mount({ label: 'B', disabled: true, name: 'openAccount', idField: 'accountId' });
        await Promise.resolve();
        const a = interactive.shadowRoot.querySelector('a');
        const s = staticEl.shadowRoot.querySelector('span');
        expect(a.className).toContain('gtm-link-cell');
        expect(s.className).toContain('gtm-link-cell');
    });

    it('long value: interactive link carries truncation classes/styling so it clips instead of overlapping the next column', async () => {
        const longLabel = 'A Very Long Account Name That Should Truncate Instead Of Overlapping The Offering Column';
        const el = mount({
            label: longLabel,
            name: 'openAccount',
            disabled: false,
            title: longLabel,
            targetId: '001000000000001AAA',
            idField: 'accountId'
        });
        await Promise.resolve();
        const link = el.shadowRoot.querySelector('a.gtm-link-cell_interactive');
        expect(link.textContent).toBe(longLabel);
        // slds-truncate (SLDS convention) plus the component's own gtm-link-cell
        // class, which independently sets overflow/text-overflow/white-space/
        // max-width so clipping doesn't depend solely on SLDS CSS being loaded.
        expect(link.className).toContain('slds-truncate');
        expect(link.className).toContain('gtm-link-cell');
    });

    it('long value: static (non-interactive) span carries the same truncation classes', async () => {
        const longLabel = 'Another Very Long Company Name That Must Not Overlap The Offering Column Text';
        const el = mount({
            label: longLabel,
            name: 'openAccount',
            disabled: true,
            title: 'No account on this link',
            targetId: null,
            idField: 'accountId'
        });
        await Promise.resolve();
        const span = el.shadowRoot.querySelector('span.gtm-link-cell_static');
        expect(span.textContent).toBe(longLabel);
        expect(span.className).toContain('slds-truncate');
        expect(span.className).toContain('gtm-link-cell');
    });

    it('Company__c-but-no-Account__c fallback case: the upstream-resolved label still renders normally', async () => {
        // The precedence/fallback logic lives in gtmRepLinkTableModel.buildRows /
        // GtmAssessmentListController.toRow, not here -- this cell only renders
        // whatever label it is handed, interactively when a lookup id exists.
        const el = mount({
            label: 'Typed Company Only',
            name: 'openAccount',
            disabled: true, // no Account__c, so still not clickable
            title: 'No account on this link',
            targetId: null,
            idField: 'accountId'
        });
        await Promise.resolve();
        const span = el.shadowRoot.querySelector('span');
        expect(span.textContent).toBe('Typed Company Only');
        expect(span.title).toBe('No account on this link');
    });

    it('showBackfillHint + disabled: renders the backfill nudge icon', async () => {
        const el = mount({
            label: 'Typed Company Only',
            name: 'openAccount',
            disabled: true,
            title: 'No account on this link',
            targetId: null,
            idField: 'accountId',
            showBackfillHint: true
        });
        await Promise.resolve();
        const icon = el.shadowRoot.querySelector('lightning-icon');
        expect(icon).not.toBeNull();
        expect(icon.title).toBeTruthy();
    });

    it('showBackfillHint true but interactive (real Account lookup): icon never renders', async () => {
        const el = mount({
            label: 'Acme Corp',
            name: 'openAccount',
            disabled: false,
            title: 'Open account',
            targetId: '001000000000001AAA',
            idField: 'accountId',
            showBackfillHint: true
        });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('lightning-icon')).toBeNull();
    });

    it('disabled but showBackfillHint not set: no icon renders (plain gap, not a backfill-eligible row)', async () => {
        const el = mount({
            label: 'Acme Co',
            name: 'openAccount',
            disabled: true,
            title: 'No account on this link',
            targetId: null,
            idField: 'accountId'
        });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('lightning-icon')).toBeNull();
    });
});
