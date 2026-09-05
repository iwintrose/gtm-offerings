import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getHomeSummary from '@salesforce/apex/MaPageContentController.getHomeSummary';
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';

/**
 * An offering's story, read inside Lightning.
 *
 * The story was only ever reachable on the public site, which made a BD wanting
 * to learn an offering leave the app for a domain where they are a guest —
 * that is the whole of the login problem they kept hitting. Nobody outside the
 * firm ever sees this page, so hosting it publicly bought nothing and cost the
 * rep their identity at the door.
 *
 * It renders through c/maStory, the same component the public site uses, so
 * there is one story renderer and no second copy to drift.
 */
export default class GtmStoryViewer extends NavigationMixin(LightningElement) {
    @track offerings = [];
    @track selected = '';
    @track loading = true;
    @track error = '';

    _asked = '';

    /** Arriving from an offering card carries which story was asked for. */
    @wire(CurrentPageReference)
    capturePageRef(ref) {
        const asked = ref && ref.state ? ref.state.c__offering : '';
        if (!asked || asked === this._asked) return;
        this._asked = asked;
        if (this.offerings.length) this.selected = asked;
    }

    connectedCallback() {
        if (super.connectedCallback) super.connectedCallback();
        this.load();
    }

    load() {
        return getHomeSummary()
            .then((data) => {
                // Only offerings with a story worth opening: the framework has
                // none, and an offering whose story has no sections would draw
                // an empty page.
                this.offerings = ((data && data.offerings) || [])
                    .filter((o) => o.offeringKey !== FRAMEWORK_KEY && o.isFramework !== true)
                    .filter((o) => (o.pages || []).some(
                        (p) => p.templateType === 'story' && (p.sectionCount || 0) > 0))
                    .map((o) => ({ label: o.label, value: o.offeringKey }));

                const asked = this.offerings.find((o) => o.value === this._asked);
                this.selected = asked ? asked.value
                    : (this.offerings.length ? this.offerings[0].value : '');
                this.error = '';
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Offerings could not be loaded.';
            })
            .finally(() => { this.loading = false; });
    }

    handlePick(event) { this.selected = event.detail.value; }

    get hasStory() { return !!this.selected; }
    get showEmpty() { return !this.loading && !this.error && !this.offerings.length; }
    get showPicker() { return this.offerings.length > 1; }

    get currentLabel() {
        const hit = this.offerings.find((o) => o.value === this.selected);
        return hit ? hit.label : '';
    }

    /** Back to where the offering was being read about. */
    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'GTM_Offerings_Overview' }
        });
    }
}
