import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getHomeSummary from '@salesforce/apex/MaPageContentController.getHomeSummary';
import { TEMPLATE_LABELS } from 'c/gtmPageLayouts';

/**
 * Every page the firm reads about itself, inside Lightning.
 *
 * The model, in one place:
 *
 *   GTM (framework)    Offerings Page, Industry Chooser
 *   an offering        Story, Configurator (the internal view of it)
 *
 * All of it is internal — the Offerings Page's own footer says
 * "Publicis Sapient · internal" — so all of it belongs here rather than on a
 * public site where the reader is a guest by architecture. The one page a
 * prospect ever sees is the configurator, served from /gtm with a link
 * password; this is the same configurator, read by someone already signed in.
 *
 * Every page renders through the component that actually draws it, so there is
 * one renderer per page and no second copy to drift from it.
 */
export default class GtmPageBrowser extends NavigationMixin(LightningElement) {
    @track entities = [];
    @track entityKey = '';
    @track template = '';
    @track loading = true;
    @track error = '';

    _askedEntity = '';
    _askedTemplate = '';

    @wire(CurrentPageReference)
    capturePageRef(ref) {
        if (!ref || !ref.state) return;
        const e = ref.state.c__offering || '';
        const t = ref.state.c__template || '';
        if (e === this._askedEntity && t === this._askedTemplate) return;
        this._askedEntity = e;
        this._askedTemplate = t;
        if (this.entities.length) this.applyAsked();
    }

    connectedCallback() {
        if (super.connectedCallback) super.connectedCallback();
        this.load();
    }

    load() {
        this.loading = true;
        return getHomeSummary()
            .then((data) => {
                this.entities = ((data && data.offerings) || []).map((o) => ({
                    key: o.offeringKey,
                    label: o.isFramework ? 'GTM (framework)' : o.label,
                    isFramework: o.isFramework === true,
                    // Only pages that have actually been built: a page with no
                    // sections draws an empty shell and teaches nobody anything.
                    pages: (o.pages || [])
                        .filter((p) => (p.sectionCount || 0) > 0)
                        .map((p) => p.templateType)
                }));
                this.applyAsked();
                this.error = '';
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Pages could not be loaded.';
            })
            .finally(() => { this.loading = false; });
    }

    applyAsked() {
        const wanted = this.entities.find((e) => e.key === this._askedEntity);
        const entity = wanted || this.entities.find((e) => !e.isFramework) || this.entities[0];
        if (!entity) return;
        this.entityKey = entity.key;
        this.template = entity.pages.includes(this._askedTemplate)
            ? this._askedTemplate
            : this.firstPageOf(entity);
    }

    /** What to open on when nothing was asked for: an offering opens on its
     *  story, the framework on its offerings page. */
    firstPageOf(entity) {
        const order = entity.isFramework
            ? ['offerings-page', 'industry-chooser']
            : ['story', 'configurator'];
        return order.find((t) => entity.pages.includes(t)) || entity.pages[0] || '';
    }

    get entityOptions() {
        return this.entities.map((e) => ({ label: e.label, value: e.key }));
    }

    get pageOptions() {
        const entity = this.entities.find((e) => e.key === this.entityKey);
        if (!entity) return [];
        // Offerings Listing is one tile drawn inside the offerings page, not a
        // page anyone reads on its own.
        return entity.pages
            .filter((t) => t !== 'offerings-listing')
            .map((t) => ({ label: TEMPLATE_LABELS[t] || t, value: t }));
    }

    handleEntity(event) {
        this.entityKey = event.detail.value;
        const entity = this.entities.find((e) => e.key === this.entityKey);
        this.template = entity ? this.firstPageOf(entity) : '';
    }

    handlePage(event) { this.template = event.detail.value; }

    // ─── which renderer draws it ──────────────────────────────────────────────
    get isStory()        { return this.template === 'story'; }
    get isOfferings()    { return this.template === 'offerings-page'; }
    get isIndustry()     { return this.template === 'industry-chooser'; }
    get isConfigurator() { return this.template === 'configurator'; }
    get hasPage()        { return !!this.entityKey && !!this.template; }
    get showEmpty()      { return !this.loading && !this.error && !this.hasPage; }

    get currentLabel() {
        const e = this.entities.find((x) => x.key === this.entityKey);
        return e ? e.label : '';
    }

    get pageLabel() { return TEMPLATE_LABELS[this.template] || this.template; }

    /** Said plainly, because the configurator exists in two versions and
     *  confusing them is how a rep sends the wrong thing. */
    get audienceNote() {
        return this.isConfigurator
            ? 'The internal view. A prospect sees this on the public link, behind its password.'
            : 'Internal. This is not what a prospect is sent.';
    }

    handleEdit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__app',
            attributes: { appTarget: 'c__GTM_Content_Manager' },
            state: {
                pageRef: JSON.stringify({
                    type: 'standard__navItemPage',
                    attributes: { apiName: 'GTM_Content_Manager' },
                    state: { c__offering: this.entityKey, c__template: this.template }
                })
            }
        });
    }
}
