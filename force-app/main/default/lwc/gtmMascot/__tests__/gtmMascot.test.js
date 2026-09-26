import { createElement } from 'lwc';
import GtmMascot from 'c/gtmMascot';

function mount(props = {}) {
    const el = createElement('c-gtm-mascot', { is: GtmMascot });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c/gtmMascot', () => {
    afterEach(() => {
        document.body.innerHTML = '';
    });

    it('defaults to the md/idle svg class', () => {
        const el = mount();
        const svg = el.shadowRoot.querySelector('svg');
        expect(svg.getAttribute('class')).toBe('gus gus--md gus--idle');
    });

    it('composes the svg class from size and mood', () => {
        const el = mount({ size: 'lg', mood: 'happy' });
        const svg = el.shadowRoot.querySelector('svg');
        expect(svg.getAttribute('class')).toBe('gus gus--lg gus--happy');
    });

    it('reflects a thinking mood into the svg class', () => {
        const el = mount({ size: 'sm', mood: 'thinking' });
        const svg = el.shadowRoot.querySelector('svg');
        expect(svg.getAttribute('class')).toBe('gus gus--sm gus--thinking');
    });
});
