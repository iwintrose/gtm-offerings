import { LightningElement, api } from 'lwc';

/**
 * Gus — the GTM Utility Sidekick.
 *
 * Chibi proportions, holding a page: the framework makes pages, so the
 * character carries one rather than being a mascot that could belong to any
 * product. Kept as its own component because he appears in more than one
 * place -- the top bar, the assistant bubble, empty states -- and has to be
 * the same character in all of them.
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
