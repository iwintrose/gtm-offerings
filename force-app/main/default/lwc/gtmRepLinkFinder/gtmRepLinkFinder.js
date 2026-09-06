import { LightningElement, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/Account.Name';
import getContactsWithLinks from '@salesforce/apex/GtmRepLinkFinderController.getContactsWithLinks';
import setActive from '@salesforce/apex/GtmSavedConfigurationController.setActive';

/**
 * A rep's own "find a link I already sent" flow (D7).
 *
 * Not a page picker: a rep here already knows the client. What they don't
 * always remember is which specific saved Configurator link they sent, so
 * this walks the CRM relationship they DO know -- Account, then Contact --
 * down to the one link, and renders it exactly the way gtmConfigurator
 * already renders it for a signed-in rep (isConfigManager) once that link's
 * id ends up in the page's own URL, the same "?cfgId=" gtmConfigurator has
 * always read for itself.
 *
 * Four steps, one at a time, each replacing the last:
 *   account -> contact -> link -> view
 * "Back" at any point clears everything from that step onward rather than
 * leaving stale state a later step could accidentally read.
 */
export default class GtmRepLinkFinder extends LightningElement {
    // undefined, not '' -- an empty string is still a value to the wire
    // service and would fire getRecord with an invalid Id on first render
    // and again after every "back to account". undefined is what tells the
    // wire service to skip the call entirely until a real Id is picked.
    @track accountId;
    @track accountName = '';
    @track loadingLinks = false;
    @track loadError = '';
    @track contactGroups = [];
    @track selectedContactId = '';
    @track selectedLink = null;
    @track togglingIds = [];

    @wire(getRecord, { recordId: '$accountId', fields: [ACCOUNT_NAME_FIELD] })
    wiredAccount({ data }) {
        if (data) {
            this.accountName = getFieldValue(data, ACCOUNT_NAME_FIELD) || '';
        }
    }

    // ------------------------------------------------------------- steps

    get step() {
        if (this.selectedLink) return 'view';
        if (this.selectedContactId) return 'link';
        if (this.accountId) return 'contact';
        return 'account';
    }

    get isAccountStep() { return this.step === 'account'; }
    get isContactStep() { return this.step === 'contact'; }
    get isLinkStep() { return this.step === 'link'; }
    get isViewStep() { return this.step === 'view'; }

    /** A small trail of what's been picked so far -- clicking an earlier
     *  crumb is the same as using that step's own Back button. */
    get crumbs() {
        const out = [{ key: 'account', label: 'Account', disabled: this.isAccountStep }];
        if (this.accountId) {
            out.push({
                key: 'contact',
                label: this.accountName || 'Contact',
                disabled: this.isAccountStep || this.isContactStep
            });
        }
        if (this.selectedContactId) {
            out.push({
                key: 'link',
                label: this.selectedContactName || 'Link',
                disabled: !this.isViewStep
            });
        }
        return out;
    }

    get hasCrumbTrail() {
        return this.crumbs.length > 1;
    }

    handleCrumbClick(event) {
        const key = event.currentTarget.dataset.key;
        if (key === 'account') this.handleBackToAccount();
        else if (key === 'contact') this.handleBackToContact();
        else if (key === 'link') this.handleBackToLinks();
    }

    // ------------------------------------------------------------ account

    handleAccountChange(event) {
        const id = event.detail && event.detail.recordId;
        this.accountId = id || undefined;
        this.accountName = '';
        this.contactGroups = [];
        this.selectedContactId = '';
        this.selectedLink = null;
        this.loadError = '';
        this.clearCfgIdParam();
        if (!this.accountId) return;

        this.loadingLinks = true;
        getContactsWithLinks({ accountId: this.accountId })
            .then((rows) => { this.contactGroups = rows || []; })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'Contacts could not be loaded.';
            })
            .finally(() => { this.loadingLinks = false; });
    }

    get hasContactGroups() {
        return this.contactGroups.length > 0;
    }

    /** Rows for the Contact step: name + how many links, so a rep with
     *  several links for one client sees that before picking. */
    get contactRows() {
        return this.contactGroups.map((g) => ({
            contactId: g.contactId,
            contactName: g.contactName,
            linkCount: g.links.length,
            linkCountLabel: g.links.length === 1 ? '1 saved link' : `${g.links.length} saved links`
        }));
    }

    // ------------------------------------------------------------ contact

    handleSelectContact(event) {
        this.selectedContactId = event.currentTarget.dataset.id;
        this.selectedLink = null;
        this.clearCfgIdParam();
    }

    get selectedGroup() {
        return this.contactGroups.find((g) => g.contactId === this.selectedContactId) || null;
    }

    get selectedContactName() {
        return this.selectedGroup ? this.selectedGroup.contactName : '';
    }

    /** Rows for the Link step: one saved Configurator link, described the
     *  way a rep would recognize it -- the deal it's for, when it was made,
     *  and whether it's still live for the client. */
    get linkRows() {
        const links = this.selectedGroup ? this.selectedGroup.links : [];
        return links.map((l) => ({
            recordId: l.recordId,
            company: l.company,
            offeringLabel: formatLabel(l.offering),
            industryLabel: l.industryLabel || 'General',
            dealName: l.dealName,
            hasDeal: !!l.dealName,
            dealStage: l.dealStage,
            createdLabel: l.createdDate ? new Date(l.createdDate).toLocaleDateString() : '',
            isActive: l.active !== false,
            isToggling: this.togglingIds.indexOf(l.recordId) !== -1,
            statusLabel: l.active === false ? 'Inactive' : 'Active',
            statusClass: l.active === false ? 'rlf-status rlf-status--off' : 'rlf-status',
            _raw: l
        }));
    }

    get hasLinkRows() {
        return this.linkRows.length > 0;
    }

    // --------------------------------------------------------------- link

    handleSelectLink(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.linkRows.find((l) => l.recordId === id);
        if (!row) return;
        this.setCfgIdParam(row.recordId);
        this.selectedLink = row._raw;
    }

    /** Whether a link still works for the client it was sent to, right from
     *  the row a rep is already looking at -- no need to open the link
     *  first just to find the switch that gates it (GtmSavedConfigurationController
     *  .setActive already exists and is what the Saved Links bar itself
     *  uses; this is the same one write path, not a new one). */
    handleToggleActive(event) {
        const id = event.currentTarget.dataset.id;
        const nextActive = event.detail.checked;
        if (this.togglingIds.indexOf(id) !== -1) return;
        this.togglingIds = [...this.togglingIds, id];

        setActive({ recordId: id, active: nextActive })
            .then(() => {
                this.contactGroups = this.contactGroups.map((g) => {
                    if (g.contactId !== this.selectedContactId) return g;
                    return {
                        ...g,
                        links: g.links.map((l) => (l.recordId === id ? { ...l, active: nextActive } : l))
                    };
                });
            })
            .catch((e) => {
                this.loadError = (e && e.body && e.body.message) || 'This link’s status could not be updated.';
            })
            .finally(() => {
                this.togglingIds = this.togglingIds.filter((existingId) => existingId !== id);
            });
    }

    get selectedLinkOfferingKey() {
        return this.selectedLink ? this.selectedLink.offering : '';
    }

    get selectedLinkCompany() {
        return this.selectedLink ? this.selectedLink.company : '';
    }

    // ------------------------------------------------------------ back nav

    handleBackToAccount() {
        this.accountId = undefined;
        this.accountName = '';
        this.contactGroups = [];
        this.selectedContactId = '';
        this.selectedLink = null;
        this.loadError = '';
        this.clearCfgIdParam();
    }

    handleBackToContact() {
        this.selectedContactId = '';
        this.selectedLink = null;
        this.clearCfgIdParam();
    }

    handleBackToLinks() {
        this.selectedLink = null;
        this.clearCfgIdParam();
    }

    // ---------------------------------------------------------------- url

    /**
     * gtmConfigurator has never had an @api way to be told which saved
     * record to render -- it reads "?cfgId=" off the real browser URL once,
     * in its own connectedCallback (see readUrlParams()). Setting that
     * query param here, before the element with a fresh `key` gets created,
     * is what lets it render this specific link instead of the generic
     * unfilled template. Best-effort: a sandbox that blocks History
     * mutation should still show the (unfilled) template rather than throw.
     */
    setCfgIdParam(recordId) {
        try {
            const url = new URL(window.location.href);
            url.searchParams.set('cfgId', recordId);
            window.history.replaceState(null, '', url.toString());
        } catch (e) {
            // best-effort -- see comment above
        }
    }

    clearCfgIdParam() {
        try {
            const url = new URL(window.location.href);
            url.searchParams.delete('cfgId');
            window.history.replaceState(null, '', url.toString());
        } catch (e) {
            // best-effort -- see comment above
        }
    }
}

/** "migration-accelerator" -> "Migration Accelerator". Same rule
 *  gtmSavedLinksBar uses for the same reason: works for any future
 *  offering slug without a lookup table to maintain. */
function formatLabel(slug) {
    if (!slug) return slug;
    return slug
        .split(/[-_]/)
        .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
        .join(' ');
}
