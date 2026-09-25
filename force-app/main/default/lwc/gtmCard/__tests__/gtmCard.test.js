import { createElement } from 'lwc';
import GtmCard from 'c/gtmCard';

describe('c-gtm-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createCard(props = {}) {
        const element = createElement('c-gtm-card', { is: GtmCard });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders the fallback icon + title header when no header slot content is projected', async () => {
        const element = createCard({ iconName: 'standard:high_velocity_sales', title: "Who's hot right now" });
        await Promise.resolve();

        const icon = element.shadowRoot.querySelector('lightning-icon');
        expect(icon.iconName).toBe('standard:high_velocity_sales');

        const title = element.shadowRoot.querySelector('.gcard-title');
        expect(title.textContent).toBe("Who's hot right now");
        expect(title.classList.contains('slds-truncate')).toBe(true);
    });

    it('renders no icon circle and no title element when neither prop is supplied', async () => {
        const element = createCard();
        await Promise.resolve();
        expect(element.shadowRoot.querySelector('lightning-icon')).toBeNull();
        expect(element.shadowRoot.querySelector('.gcard-title')).toBeNull();
    });

    it.each([
        ['deals', '#fe9339'],
        ['heat', '#c23934'],
        ['tasks', '#0b5cab'],
        ['readouts', '#2e844a'],
        ['offerings', '#9050e9']
    ])('maps variant %s to its rail and icon-circle classes', async (variant) => {
        const element = createCard({ variant, iconName: 'standard:task' });
        await Promise.resolve();

        const card = element.shadowRoot.querySelector('.gcard');
        expect(card.classList.contains(`gcard--${variant}`)).toBe(true);

        const icon = element.shadowRoot.querySelector('.gcard-ic');
        expect(icon.classList.contains(`gcard-ic--${variant}`)).toBe(true);
    });

    it('falls back to the neutral rail with no icon-circle color modifier for an unknown or omitted variant', async () => {
        const element = createCard({ variant: 'not-a-real-variant', iconName: 'standard:task' });
        await Promise.resolve();

        const card = element.shadowRoot.querySelector('.gcard');
        expect(card.className).toBe('slds-card gcard');

        const icon = element.shadowRoot.querySelector('.gcard-ic');
        expect(icon.className).toBe('gcard-ic');
    });

    it('defaults headerAlign to center (3rem min-height header row, no gcard-h--start modifier)', async () => {
        const element = createCard({ title: 'Assessment results' });
        await Promise.resolve();
        const header = element.shadowRoot.querySelector('.gcard-h');
        expect(header.classList.contains('gcard-h--start')).toBe(false);
    });

    it('applies gcard-h--start for a two-line/stacked header', async () => {
        const element = createCard({ title: 'Assessment results', headerAlign: 'start' });
        await Promise.resolve();
        const header = element.shadowRoot.querySelector('.gcard-h');
        expect(header.classList.contains('gcard-h--start')).toBe(true);
    });

    it('lets a projected header slot fully replace the icon/title fallback content when customHeader is set', async () => {
        const element = createElement('c-gtm-card', { is: GtmCard });
        element.iconName = 'standard:task';
        element.title = 'Assessment results';
        element.customHeader = true;

        const custom = document.createElement('div');
        custom.setAttribute('slot', 'header');
        custom.className = 'my-custom-header';
        custom.textContent = 'Custom stacked header';
        element.appendChild(custom);

        document.body.appendChild(element);
        await Promise.resolve();

        // Fallback content (icon/title) must not render once customHeader
        // suppresses it (see contract §2.2 for why this is an explicit flag
        // rather than slot introspection).
        expect(element.shadowRoot.querySelector('lightning-icon')).toBeNull();
        expect(element.shadowRoot.querySelector('.gcard-title')).toBeNull();

        const projected = document.body.querySelector('.my-custom-header');
        expect(projected).not.toBeNull();
        expect(projected.textContent).toBe('Custom stacked header');
    });

    it('renders the icon/title fallback content by default even when a header slot child happens to be present, until customHeader is set', async () => {
        const element = createElement('c-gtm-card', { is: GtmCard });
        element.iconName = 'standard:task';
        element.title = 'Assessment results';
        document.body.appendChild(element);
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('lightning-icon')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.gcard-title').textContent).toBe('Assessment results');
    });

    it('defaults flushTop to false (no gcard-b--flush-top modifier)', async () => {
        const element = createCard();
        await Promise.resolve();
        const body = element.shadowRoot.querySelector('.gcard-b');
        expect(body.classList.contains('gcard-b--flush-top')).toBe(false);
    });

    it('applies gcard-b--flush-top when flushTop is set, for a scrollable body with its own sticky header', async () => {
        const element = createCard({ flushTop: true });
        await Promise.resolve();
        const body = element.shadowRoot.querySelector('.gcard-b');
        expect(body.classList.contains('gcard-b--flush-top')).toBe(true);
    });

    it('projects default-slot body content', async () => {
        const element = createElement('c-gtm-card', { is: GtmCard });
        const body = document.createElement('p');
        body.className = 'my-body';
        body.textContent = 'Body content owned by the consumer';
        element.appendChild(body);

        document.body.appendChild(element);
        await Promise.resolve();

        const slot = element.shadowRoot.querySelector('.gcard-b slot:not([name])');
        expect(slot).not.toBeNull();
        expect(document.body.querySelector('.my-body').textContent).toBe('Body content owned by the consumer');
    });
});
