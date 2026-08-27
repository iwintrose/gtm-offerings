import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getMyConfigurations from '@salesforce/apex/MaSavedConfigurationController.getMyConfigurations';
import deleteConfiguration from '@salesforce/apex/MaSavedConfigurationController.deleteConfiguration';
import setActive from '@salesforce/apex/MaSavedConfigurationController.setActive';
import getOrgBaseUrl from '@salesforce/apex/MaSavedConfigurationController.getOrgBaseUrl';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';

const OFFERING = 'migration-accelerator';

export default class MaSavedLinksBar extends LightningElement {
    _industryLabels = {};

    hasAccess = false;
    isOpen = false;
    groups = [];
    actionError = '';
    _orgBaseUrl = '';

    async connectedCallback() {
        if (isGuest) {
            return;
        }
        try {
            this._orgBaseUrl = await getOrgBaseUrl();
        } catch (e) {
            // No "View in Salesforce" links for this session -- the
            // config link itself still works fine without it.
        }
        this.loadConfigurations();
        // Best-effort: load industry labels for display; falls back to formatLabel(key).
        getStoryContent({ offeringKey: OFFERING })
            .then((data) => {
                if (!data) return;
                const map = {};
                data.industries.forEach((ind) => { map[ind.industryKey] = ind.industryLabel; });
                this._industryLabels = map;
            })
            .catch(() => { /* industry labels are display-only; safe to skip */ });
    }

    recordUrl(id) {
        return this._orgBaseUrl
            ? `${this._orgBaseUrl}/lightning/r/MA_Saved_Configuration__c/${id}/view`
            : '';
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
            this.actionError = '';
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
            const isAccessError = /insufficient|no such column|not invocable|do not have access/i.test(
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

    get panelClass() {
        return this.isOpen ? 'sl-panel open' : 'sl-panel';
    }

    get chevronClass() {
        return this.isOpen ? 'sl-chevron open' : 'sl-chevron';
    }

    handleToggle() {
        this.isOpen ? this.close() : this.open();
    }

    open() {
        this.isOpen = true;
        // Deferred, not attached synchronously: attaching right here would
        // let the very click that opened the panel -- still bubbling up
        // toward document -- reach this same listener and close the panel
        // back in the same tick. Two earlier attempts tried to solve that
        // by comparing event.target / composedPath() against
        // this.template.host, but under Lightning Web Security the DOM is
        // membrane-wrapped, so the "same" element can surface as different
        // wrapper objects on either side of that comparison and the check
        // silently always fails. Queuing the listener for the next tick
        // sidesteps identity comparison entirely: nothing is listening yet
        // while the opening click is still in flight.
        this._outsideClickTimer = setTimeout(() => {
            document.addEventListener('click', this.handleDocumentClick);
        }, 0);
        document.addEventListener('keydown', this.handleDocumentKeydown);
    }

    close() {
        this.isOpen = false;
        clearTimeout(this._outsideClickTimer);
        document.removeEventListener('click', this.handleDocumentClick);
        document.removeEventListener('keydown', this.handleDocumentKeydown);
    }

    disconnectedCallback() {
        clearTimeout(this._outsideClickTimer);
        document.removeEventListener('click', this.handleDocumentClick);
        document.removeEventListener('keydown', this.handleDocumentKeydown);
    }

    // No inside/outside identity check needed: by the time this can fire,
    // the opening click is long finished (see open()). Row actions
    // (Disable/Delete) call stopPropagation() so they never reach here and
    // the panel stays open through them; any other click reaching
    // document -- inside the panel or out -- closes it, same as a normal
    // dropdown.
    handleDocumentClick = () => {
        this.close();
    };

    handleDocumentKeydown = (event) => {
        if (event.key === 'Escape') {
            this.close();
        }
    };

    async handleDelete(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this.actionError = '';
        try {
            await deleteConfiguration({ recordId });
            await this.loadConfigurations();
        } catch (e) {
            // Deletion failing (e.g. someone else's record, no delete
            // access) leaves the row in place -- that part's correct and
            // safe. What was missing is telling the rep why nothing
            // happened instead of leaving them to click it again.
            this.actionError = this.readErrorMessage(e, 'delete that link');
        }
    }

    /** Does not delete or hide the record -- only gates what the client
     * sees when they open the shared link (MaConfigurationStatusController). */
    async handleToggleActive(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        const nextActive = event.currentTarget.dataset.active !== 'true';
        if (!recordId) return;
        this.actionError = '';
        try {
            await setActive({ recordId, active: nextActive });
            await this.loadConfigurations();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('maSavedLinksBar: failed to toggle active state', e);
            this.actionError = this.readErrorMessage(e, 'update that link\'s status');
        }
    }

    readErrorMessage(error, action) {
        const message = error?.body?.message;
        return message || `We could not ${action}. Please try again.`;
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
            const active = rec.Active__c !== false;
            byIndustry.get(industryKey).push({
                id: rec.Id,
                label: rec.Company__c || rec.Name,
                recordNumber: rec.Name,
                url: appendCfgId(rec.Generated_URL__c, rec.Id),
                owner: rec.Owner ? rec.Owner.Name : '',
                date: rec.CreatedDate
                    ? new Date(rec.CreatedDate).toLocaleDateString()
                    : '',
                active,
                activeAttr: String(active),
                rowClass: active ? 'sl-link' : 'sl-link inactive',
                statusDotClass: active ? 'sl-dot' : 'sl-dot off',
                statusLabel: active ? 'Active' : 'Inactive',
                toggleLabel: active ? 'Disable' : 'Enable',
                toggleTitle: active
                    ? 'Disable this link for the client'
                    : 'Re-enable this link for the client',
                recordUrl: this.recordUrl(rec.Id)
            });
        });

        const groups = [];
        byOffering.forEach((byIndustry, offeringKey) => {
            const industries = [];
            byIndustry.forEach((links, industryKey) => {
                industries.push({
                    key: `${offeringKey}-${industryKey}`,
                    name: this._industryLabels[industryKey]
                        ? this._industryLabels[industryKey]
                        : formatLabel(industryKey),
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
