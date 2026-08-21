import { LightningElement, api } from 'lwc';
import getMyConfigurations from '@salesforce/apex/MaSavedConfigurationController.getMyConfigurations';
import deleteConfiguration from '@salesforce/apex/MaSavedConfigurationController.deleteConfiguration';

export default class MaSavedLinksBar extends LightningElement {
    hasAccess = false;
    isOpen = false;
    groups = [];

    connectedCallback() {
        this.loadConfigurations();
    }

    /** Called by a parent (e.g. maConfigurator, after a save) so a new or
     * edited link shows up here without the rep navigating away and back. */
    @api
    refresh() {
        this.loadConfigurations();
    }

    /**
     * Deliberately imperative, not @wire(cacheable=true): the wire cache
     * was serving a stale (often empty) result across page navigations --
     * a page freshly saved on Configurator would still show "no saved
     * links" on Choose Industry moments later. Every fresh page load (this
     * is a multi-page site, not an SPA) should hit the server, not a
     * cached response from before the save happened.
     */
    async loadConfigurations() {
        try {
            const data = await getMyConfigurations();
            this.hasAccess = true;
            this.groups = this.groupRecords(data);
        } catch (error) {
            this.hasAccess = false;
            this.groups = [];
            // Guests (and anyone else without the MA Config Manager
            // permission set) hit this path as INSUFFICIENT_ACCESS -- that
            // one is expected and the bar just stays hidden. Anything else
            // is a real bug, not an access check, so it's worth a console
            // trace: a permission-shaped failure looks identical to a
            // genuine one from the UI alone.
            const code = error?.body?.exceptionType || error?.body?.message || '';
            const isAccessError = /insufficient|no such column|not invocable/i.test(
                String(code)
            );
            if (!isAccessError) {
                // eslint-disable-next-line no-console
                console.error('maSavedLinksBar: unexpected error loading configurations', error);
            }
        }
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get toggleLabel() {
        return this.isOpen ? 'Saved ▲' : 'Saved ▾';
    }

    get panelClass() {
        return this.isOpen ? 'sl-panel open' : 'sl-panel';
    }

    handleToggle() {
        this.isOpen = !this.isOpen;
    }

    async handleDelete(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        try {
            await deleteConfiguration({ recordId });
            await this.loadConfigurations();
        } catch (e) {
            // Deletion failing (e.g. someone else's record, no delete
            // access) just leaves the row in place — nothing to recover.
        }
    }

    groupRecords(records) {
        const byOffering = new Map();

        records.forEach((rec) => {
            const offeringKey = rec.Offering__c || 'Other';
            if (!byOffering.has(offeringKey)) {
                byOffering.set(offeringKey, new Map());
            }
            const byIndustry = byOffering.get(offeringKey);
            const industryKey = rec.Industry__c || 'Generic';
            if (!byIndustry.has(industryKey)) {
                byIndustry.set(industryKey, []);
            }
            byIndustry.get(industryKey).push({
                id: rec.Id,
                label: rec.Company__c || rec.Name,
                url: appendCfgId(rec.Generated_URL__c, rec.Id),
                owner: rec.Owner ? rec.Owner.Name : '',
                date: rec.CreatedDate
                    ? new Date(rec.CreatedDate).toLocaleDateString()
                    : ''
            });
        });

        const groups = [];
        byOffering.forEach((byIndustry, offeringKey) => {
            const industries = [];
            byIndustry.forEach((links, industryKey) => {
                industries.push({
                    key: `${offeringKey}-${industryKey}`,
                    name: formatLabel(industryKey),
                    links
                });
            });
            groups.push({
                key: offeringKey,
                name: formatLabel(offeringKey),
                industries
            });
        });
        return groups;
    }
}

/** Tags a saved link with its record Id so opening it (as its owning rep)
 * lands back in an editable state tied to that same record, instead of
 * creating a duplicate on next save. The shared, client-facing copy of
 * this URL never carries this param -- it's only added here, for the
 * rep's own click from this bar. */
function appendCfgId(url, id) {
    if (!url) return url;
    const joiner = url.indexOf('?') === -1 ? '?' : '&';
    return `${url}${joiner}cfgId=${encodeURIComponent(id)}`;
}

/** "migration-accelerator" -> "Migration Accelerator". Works for any
 * future offering/industry slug without a lookup table to maintain. */
function formatLabel(slug) {
    if (!slug) return slug;
    return slug
        .split(/[-_]/)
        .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
        .join(' ');
}
