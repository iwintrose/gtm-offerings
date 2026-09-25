import { LightningElement, api } from 'lwc';

/**
 * Shared card shell: bordered/shadowed `.gcard` chrome, a colored top rail,
 * an optional icon-circle + title header row (or a fully custom `header`
 * slot for layouts the title prop can't express), and a default slot for
 * body content. Extracted from the hand-duplicated `.ov-card`/`.ov-card-h`/
 * `.ov-card-b` family (issue 14; contract: docs/architecture/gtm-card-contract.md).
 *
 * `variant` is a named enum, not a free color value (same pattern as
 * gtmPageHeader's own prop naming) -- it drives BOTH the rail color and the
 * icon-circle background/foreground together, since every existing consumer
 * always paired them one-to-one (e.g. `.ov-heat` + `.ov-ic--heat`). An
 * unknown/omitted variant falls back to the neutral gray rail with no icon
 * circle color override.
 */
const VARIANTS = new Set(['deals', 'heat', 'tasks', 'readouts', 'offerings']);

export default class GtmCard extends LightningElement {
    @api iconName = '';
    @api title = '';

    _variant = '';
    @api
    get variant() {
        return this._variant;
    }
    set variant(value) {
        this._variant = VARIANTS.has(value) ? value : '';
    }

    /** 'center' (default, single-line headers) or 'start' (two-line/stacked
     * headers projected into the `header` slot, e.g. gtmOverview's
     * Assessment results card -- see contract §2). */
    @api headerAlign = 'center';

    /** Set true when the consumer is projecting its own markup into the
     * `header` slot, so the icon/title fallback content is suppressed.
     * An explicit flag rather than runtime slot-introspection
     * (`assignedElements()`/light-DOM children) because LWC's
     * synthetic-shadow engine (used both by this test suite and by
     * non-native-shadow orgs) does not reliably expose either -- see
     * contract §2.2. */
    @api customHeader = false;

    get cardClass() {
        const rail = this._variant ? ` gcard--${this._variant}` : '';
        return `slds-card gcard${rail}`;
    }

    get headerClass() {
        return this.headerAlign === 'start' ? 'slds-card__header gcard-h gcard-h--start' : 'slds-card__header gcard-h';
    }

    /** Zeroes gcard-b's top padding, for a consumer whose body content is
     * its own scroll container with a sticky header row that must sit flush
     * against the card header (e.g. gtmOverview's deals table/assessment
     * results, ported from `.ov-deals-body`/`.ov-results-body`'s
     * `padding-top: 0`). */
    @api flushTop = false;

    get bodyClass() {
        return this.flushTop ? 'slds-card__body gcard-b gcard-b--flush-top' : 'slds-card__body gcard-b';
    }

    get iconClass() {
        return this._variant ? `gcard-ic gcard-ic--${this._variant}` : 'gcard-ic';
    }

    get hasIcon() {
        return !!this.iconName;
    }

    get hasTitle() {
        return !!this.title;
    }

    get showFallbackHeader() {
        return !this.customHeader;
    }
}
