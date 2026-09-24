import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getMyConfigurations from '@salesforce/apex/GtmSavedConfigurationController.getMyConfigurations';
import getConfiguratorPageUrl from '@salesforce/apex/GtmSavedConfigurationController.getConfiguratorPageUrl';
import deleteConfiguration from '@salesforce/apex/GtmSavedConfigurationController.deleteConfiguration';
import setActive from '@salesforce/apex/GtmSavedConfigurationController.setActive';
import resendEngagementLink from '@salesforce/apex/GtmSavedConfigurationController.resendEngagementLink';
import getOrgBaseUrl from '@salesforce/apex/GtmSavedConfigurationController.getOrgBaseUrl';
import getIndustryProfiles from '@salesforce/apex/GtmPageContentReader.getIndustryProfiles';
import { FRAMEWORK_KEY } from 'c/gtmPageLayouts';


export default class GtmSavedLinksBar extends LightningElement {
    _industryLabels = {};
    /** Where the configurator lives, so a short link can be built for any row. */
    _configuratorBase = '';

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
        // The list is the framework's shared taxonomy, not this offering's.
        getIndustryProfiles({ offeringKey: FRAMEWORK_KEY, templateType: 'industry-chooser' })
            .then((rows) => {
                const map = {};
                (rows || []).forEach((ind) => { map[ind.industryKey] = ind.industryLabel; });
                this._industryLabels = map;
            })
            .catch(() => { /* industry labels are display-only; safe to skip */ });
    }

    recordUrl(id) {
        return this._orgBaseUrl
            // The Pages tab link detail (c__template=link), never the SC record page.
            ? `${this._orgBaseUrl}/lightning/n/GTM_Pages?c__template=link&c__recordId=${id}`
            : '';
    }

    /** Called by a parent (e.g. gtmConfigurator, after a save) so a new or
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
            if (!this._configuratorBase) {
                try { this._configuratorBase = await getConfiguratorPageUrl(); }
                catch (e) { this._configuratorBase = ''; }
            }
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
                console.error('gtmSavedLinksBar: unexpected error loading configurations', error);
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
     * sees when they open the shared link (GtmConfigurationStatusController). */
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
            console.error('gtmSavedLinksBar: failed to toggle active state', e);
            this.actionError = this.readErrorMessage(e, 'update that link\'s status');
        }
    }

    async handleResend(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this.actionError = '';
        try {
            await resendEngagementLink({ recordId });
            // Show a transient success toast. The component runs inside an
            // Experience Cloud Aura page, but dispatching ShowToastEvent still
            // works from LWC inside Aura as long as the event bubbles to the
            // Aura container. Use a data attribute rather than a full toast
            // import for simplicity -- raise a custom success notification
            // via the standard LWC ShowToastEvent path.
            const toast = new CustomEvent('showtoast', {
                bubbles: true,
                composed: true,
                detail: {
                    title: 'Link sent',
                    message: 'The engagement link has been resent to the contact.',
                    variant: 'success'
                }
            });
            this.dispatchEvent(toast);
        } catch (e) {
            this.actionError = this.readErrorMessage(e, 'resend that link');
        }
    }

    readErrorMessage(error, action) {
        const message = error?.body?.message;
        return message || `We could not ${action}. Please try again.`;
    }

    groupRecords(records) {
        const byOffering = new Map();

        // Two links for one client is normal and is NOT what to flag: a
        // client can have several deals at once, different parts of the
        // business buying separately, or a deal that closed and restarted
        // months later. Salesforce already models that as one account with
        // many opportunities, and the link carries the opportunity -- so the
        // deal is what tells two links apart, and naming it is what saves the
        // reader from guessing.
        //
        // Two links on the SAME opportunity is the case that is probably a
        // mistake, so that is the one that gets flagged.
        const linksPerOpportunity = new Map();
        records.forEach((rec) => {
            const opp = rec.Opportunity__c;
            if (!opp) return;
            linksPerOpportunity.set(opp, (linksPerOpportunity.get(opp) || 0) + 1);
        });

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
            const sameDeal = rec.Opportunity__c ? (linksPerOpportunity.get(rec.Opportunity__c) || 1) : 1;
            byIndustry.get(industryKey).push({
                id: rec.Id,
                label: rec.Company__c || rec.Name,
                accountName: rec.Account__r ? rec.Account__r.Name : '',
                contactName: rec.Contact__r ? rec.Contact__r.Name : '',
                contactEmail: rec.Contact__r ? rec.Contact__r.Email : '',
                // The deal this link is for. Naming it is the whole point:
                // two links under one client stop being ambiguous the moment
                // you can see they belong to different deals.
                dealName: rec.Opportunity__r ? rec.Opportunity__r.Name : '',
                dealStage: rec.Opportunity__r ? rec.Opportunity__r.StageName : '',
                // Colour by how far along the deal is, so the list can be
                // read at a glance instead of word by word. Decoration that
                // carries no information is just noise.
                dealStageClass: stageClass(rec.Opportunity__r ? rec.Opportunity__r.StageName : ''),
                noDeal: !rec.Opportunity__c,
                shared: sameDeal > 1,
                sharedLabel: sameDeal > 1
                    ? `${sameDeal} links on this same deal`
                    : '',
                recordNumber: rec.Name,
                // The link to send. The record holds every value now, so the
                // link only has to say which record -- the long form is kept
                // for continuity but it is not the thing to copy.
                url: this._configuratorBase
                    ? `${this._configuratorBase}?cfgId=${rec.Id}`
                    : appendCfgId(rec.Generated_URL__c, rec.Id),
                fullUrl: appendCfgId(rec.Generated_URL__c, rec.Id),
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
/**
 * Where a deal sits, as a class rather than a literal stage name.
 *
 * Stage names are configurable per org, so this reads the shape of the word
 * rather than matching an exact list -- an org that renames "Qualification"
 * still lands somewhere sensible instead of falling off the end.
 */
function stageClass(stage) {
    const s = (stage || '').toLowerCase();
    if (!s) return 'sl-stage';
    if (s.indexOf('closed') === 0 || s.indexOf('won') >= 0) {
        return s.indexOf('lost') >= 0 ? 'sl-stage sl-stage--lost' : 'sl-stage sl-stage--won';
    }
    if (s.indexOf('negoti') >= 0 || s.indexOf('propos') >= 0 || s.indexOf('contract') >= 0) {
        return 'sl-stage sl-stage--late';
    }
    if (s.indexOf('value') >= 0 || s.indexOf('decision') >= 0 || s.indexOf('percept') >= 0) {
        return 'sl-stage sl-stage--mid';
    }
    return 'sl-stage sl-stage--early';
}

function formatLabel(slug) {
    if (!slug) return slug;
    return slug
        .split(/[-_]/)
        .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
        .join(' ');
}
