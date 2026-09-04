import { LightningElement, api } from 'lwc';

/**
 * Gus — the GTM Offerings character.
 *
 * A stack of pages with a face: the framework manages pages, so the character
 * is made of what it manages. Kept as its own component because it appears in
 * more than one place (the assistant bubble, empty states, the overview) and
 * should be the same character in all of them.
 */
export default class GtmMascot extends LightningElement {
    /** 'sm' 28px · 'md' 44px · 'lg' 72px. */
    @api size = 'md';

    /** 'idle' · 'thinking' (the antenna pulses) · 'happy' (a wider smile). */
    @api mood = 'idle';

    get svgClass() {
        return `gus gus--${this.size} gus--${this.mood}`;
    }
}
