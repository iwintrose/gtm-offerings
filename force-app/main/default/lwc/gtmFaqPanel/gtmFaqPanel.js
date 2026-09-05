import { LightningElement, api, track } from 'lwc';
import getPageContent from '@salesforce/apex/MaPageContentReader.getPageContent';

const FRAMEWORK_KEY = 'gtm';
const SECTION_KEY = 'faq';

/**
 * B1 — the static, CMS-editable help panel each app carries.
 *
 * Collapsed by default, a corner toggle rather than a chunk of the page: this
 * is a drawer someone opens when they have a question, not something every
 * visitor pays vertical space for on every load. Content is fetched only on
 * first open, for the same reason — a panel nobody opens should cost nothing.
 *
 * The content itself is not hardcoded here. It reads through
 * MaPageContentReader.getPageContent — the same read path every other CMS-
 * backed component on these pages already uses — addressed at
 * gtm::<templateType>::faq::*, using the 'faq' layout the story page's own
 * FAQ section already renders from (c/gtmPageLayouts LAYOUT_FIELDS.faq): an
 * eyebrow, a heading, and a JSON list of {question, answer} pairs. A BA edits
 * it in the Content Manager app exactly like any other page — no separate
 * admin screen exists or is needed for it.
 */
export default class GtmFaqPanel extends LightningElement {
    /** 'faq-bd' | 'faq-content-manager' — which app's content to read. */
    @api templateType = '';
    /** Framework-owned by default: the panel is chrome for the app, not copy
     *  about any one offering. */
    @api offeringKey = FRAMEWORK_KEY;
    /** Shown on the collapsed toggle before content has ever loaded. */
    @api fabLabel = 'Help';

    @track open = false;
    @track loading = false;
    @track loaded = false;
    @track errorMessage = '';
    @track eyebrow = '';
    @track heading = 'Help & FAQ';
    @track rawItems = [];
    @track openItemId = null;

    handleToggle() {
        this.open = !this.open;
        if (this.open && !this.loaded && !this.loading) {
            this.load();
        }
    }

    handleClose() {
        this.open = false;
    }

    load() {
        this.loading = true;
        this.errorMessage = '';
        getPageContent({
            offeringKey: this.offeringKey,
            templateType: this.templateType,
            industryKey: null
        })
            .then((content) => {
                const map = content || {};
                this.eyebrow = map[`${SECTION_KEY}::eyebrow`] || '';
                this.heading = map[`${SECTION_KEY}::head`] || 'Help & FAQ';
                this.rawItems = this.parseItems(map[`${SECTION_KEY}::items`]);
            })
            .catch((err) => {
                this.errorMessage = this.messageFrom(err) || 'This panel could not load its content.';
            })
            .finally(() => {
                this.loading = false;
                this.loaded = true;
            });
    }

    parseItems(raw) {
        if (!raw) return [];
        try {
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            // A malformed row should not take the whole panel down with it.
            return [];
        }
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    handleItemToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openItemId = this.openItemId === id ? null : id;
    }

    // ─── template getters ─────────────────────────────────────────────────────

    get panelLabel() {
        return this.heading || 'Help & FAQ';
    }

    get hasEyebrow() { return !!this.eyebrow; }

    get items() {
        return this.rawItems.map((entry, index) => {
            const id = `faq-${index}`;
            const isOpen = this.openItemId === id;
            return {
                id,
                question: entry && entry.question,
                answer: entry && entry.answer,
                itemClass: isOpen ? 'fp-item fp-item--open' : 'fp-item',
                plusClass: isOpen ? 'fp-plus fp-plus--open' : 'fp-plus',
                ariaExpanded: isOpen ? 'true' : 'false'
            };
        }).filter((item) => item.question && item.answer);
    }

    get hasItems() { return this.items.length > 0; }
    get showEmpty() { return this.loaded && !this.loading && !this.errorMessage && !this.hasItems; }
    get showError() { return !!this.errorMessage; }

    get rootClass() {
        return this.open ? 'fp-root fp-root--open' : 'fp-root';
    }

    get fabAriaExpanded() { return this.open ? 'true' : 'false'; }
    get fabTitle() { return this.open ? 'Close help' : this.fabLabel; }
}
