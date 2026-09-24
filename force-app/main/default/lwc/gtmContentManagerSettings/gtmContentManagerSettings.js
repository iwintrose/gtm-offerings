import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

/**
 * Net-new shell tab (GTM_Content_Manager_Settings) hosting GTM Content
 * Manager admin-configuration concerns behind a single internal nav rail of
 * sections, mirroring gtmOfferingsSettings's structure per ADR-0010's
 * one-tab-many-sections pattern (issue #184).
 *
 * This is the Content Manager app's first settings surface -- there was no
 * existing shell to extend, so this is genuinely new tab/metadata scope,
 * not an extension of a pre-existing one. "Recycle Bin" is its only
 * section today, hosting the same shared gtmRecycleBin component embedded
 * by gtmOfferingsSettings, so restore/purge/list logic isn't duplicated
 * across apps.
 */
const SECTIONS = [
    { id: 'recycle-bin', label: 'Recycle Bin' }
];

export default class GtmContentManagerSettings extends LightningElement {
    @track selectedSectionId = SECTIONS[0].id;

    // Deep-link support, e.g. gtmContentHome navigating with
    // state: { c__section: 'recycle-bin' }.
    @wire(CurrentPageReference)
    onPageRef(pageRef) {
        const sectionId = pageRef && pageRef.state && pageRef.state.c__section;
        if (sectionId && SECTIONS.some((section) => section.id === sectionId)) {
            this.selectedSectionId = sectionId;
        }
    }

    get sections() {
        return SECTIONS.map((section) => ({
            ...section,
            isSelected: section.id === this.selectedSectionId,
            navClass: section.id === this.selectedSectionId
                ? 'slds-nav-vertical__item slds-is-active'
                : 'slds-nav-vertical__item'
        }));
    }

    get sectionsMeta() {
        return `${SECTIONS.length} section${SECTIONS.length === 1 ? '' : 's'}`;
    }

    get isRecycleBinSelected() {
        return this.selectedSectionId === 'recycle-bin';
    }

    handleSectionSelect(event) {
        event.preventDefault();
        const sectionId = event.currentTarget.dataset.sectionId;
        if (sectionId) {
            this.selectedSectionId = sectionId;
        }
    }
}
