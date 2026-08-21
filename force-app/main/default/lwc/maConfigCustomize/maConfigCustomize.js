import { LightningElement, api, track } from 'lwc';
import saveConfiguration from '@salesforce/apex/MaSavedConfigurationController.saveConfiguration';
import deleteConfiguration from '@salesforce/apex/MaSavedConfigurationController.deleteConfiguration';
import {
    FIELDS,
    INDUSTRIES,
    IND_ORDER,
    SWATCHES,
    LINKS_KEY,
    initials,
    isHex6
} from 'c/maConfigData';

const OFFERING = 'migration-accelerator';

export default class MaConfigCustomize extends LightningElement {
    @api isOpen = false;
    @api company = '';
    @api industry = '';
    @api accent = '';

    _savedRecordId = '';
    /** Record Id of the saved config this page was opened from (via the
     * ?cfgId= param a saved-links click adds). Seeds knownRecordId below,
     * which also then evolves independently once a fresh save gets back
     * its own new id -- see saveInternal/persistToServer. */
    @api
    get savedRecordId() {
        return this._savedRecordId;
    }
    set savedRecordId(value) {
        this._savedRecordId = value || '';
        if (value) this.knownRecordId = value;
    }

    @track knownRecordId = '';
    @track expires = '';
    @track copyFeedback = 'Copy link';
    @track links = [];
    @track editingId = null;

    get saveLabel() {
        return this.canSaveAsNew ? 'Update this link' : 'Save link';
    }

    _state = {};

    /** Token values, owned by the parent. */
    @api
    get state() {
        return this._state;
    }
    set state(value) {
        this._state = value || {};
    }

    swatches = SWATCHES.map((s) => ({
        name: s.name,
        hex: s.hex,
        style: `background:#${s.hex}`
    }));

    connectedCallback() {
        // Drop local entries with no serverId: they predate server-side
        // tracking (or hit a save that silently failed before error
        // logging existed) and can never be resolved to a real record --
        // editing one always created a duplicate instead of updating,
        // which is the exact bug this one-time cleanup removes.
        const all = this.readLinks();
        this.links = all.filter((l) => !!l.serverId);
        if (this.links.length !== all.length) {
            this.writeLinks();
        }
    }

    // ---------------------------------------------------------------- display

    get scrimClass() {
        return this.isOpen ? 'cust-scrim open' : 'cust-scrim';
    }

    get panelClass() {
        return this.isOpen ? 'cust open' : 'cust';
    }

    get editing() {
        return this.editingId !== null;
    }

    get monogram() {
        return this.company ? initials(this.company) : '—';
    }

    get accentHex() {
        return isHex6(this.accent)
            ? `#${String(this.accent).replace(/^#/, '')}`
            : '#EE3D23';
    }

    get fields() {
        return FIELDS.map((f) => ({
            k: f.k,
            label: f.label,
            ph: f.ph,
            inputId: `fld_${f.k}`,
            value: this._state[f.k] || ''
        }));
    }

    get industryOptions() {
        const options = [
            {
                value: '',
                label: 'Generic (no industry)',
                selected: !this.industry
            }
        ];
        IND_ORDER.forEach((key) => {
            options.push({
                value: key,
                label: INDUSTRIES[key].label,
                selected: this.industry === key
            });
        });
        return options;
    }

    get recentLinks() {
        return this.links.slice(0, 8).map((l) => ({
            id: l.id,
            url: l.url,
            label: `${l.company || '(no company)'} · ${
                INDUSTRIES[l.industry]
                    ? INDUSTRIES[l.industry].label
                    : l.industry || 'generic'
            }`,
            date: new Date(l.ts).toLocaleDateString(),
            rowClass: this.editingId === l.id ? 'rl editing' : 'rl'
        }));
    }

    get linkUrl() {
        return this.buildUrl();
    }

    // ----------------------------------------------------------------- events

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleFieldInput(event) {
        this.emit('fieldchange', {
            key: event.currentTarget.dataset.key,
            value: event.currentTarget.value
        });
    }

    handleCompanyInput(event) {
        this.emit('companychange', { value: event.currentTarget.value });
    }

    handleIndustryChange(event) {
        this.emit('industrychange', { value: event.currentTarget.value });
    }

    handleAccentInput(event) {
        this.emit('accentchange', { value: event.currentTarget.value });
    }

    handleAccentPicker(event) {
        this.emit('accentchange', {
            value: event.currentTarget.value.replace('#', '')
        });
    }

    handleSwatch(event) {
        this.emit('accentchange', { value: event.currentTarget.dataset.hex });
    }

    handleExpires(event) {
        this.expires = event.currentTarget.value;
    }

    handleLoadExample() {
        this.emit('loadexample', {});
    }

    handleClearAll() {
        this.emit('clearall', {});
    }

    handleCancelEdit(event) {
        event.preventDefault();
        this.editingId = null;
    }

    handleEditLink(event) {
        const id = event.currentTarget.dataset.id;
        const entry = this.links.find((l) => l.id === id);
        if (!entry) return;

        this.editingId = id;
        this.expires = entry.exp
            ? new Date(entry.exp).toISOString().slice(0, 10)
            : '';
        this.emit('companychange', { value: entry.company || '' });
        this.emit('industrychange', { value: entry.industry || '' });
        this.emit('accentchange', { value: entry.accent || '' });
    }

    handleDeleteLink(event) {
        const id = event.currentTarget.dataset.id;
        const entry = this.links.find((l) => l.id === id);
        this.links = this.links.filter((l) => l.id !== id);
        this.writeLinks();
        if (this.editingId === id) {
            this.editingId = null;
        }
        if (entry && entry.serverId) {
            deleteConfiguration({ recordId: entry.serverId }).catch(() => {
                // No access, or already gone — the local list is already
                // updated, which is what the rep sees.
            });
        }
    }

    handleSave() {
        this.saveInternal({ asNew: false });
    }

    /** Always inserts a new record + fresh URL, even if this page was
     * opened from an existing saved link. Lets a rep branch a client's
     * config into a second version without touching the original. */
    handleSaveAsNew() {
        this.saveInternal({ asNew: true });
    }

    /** Pure clipboard copy of the current link -- independent of whether
     * it's been saved. Saving and copying used to be one action, which
     * made it unclear whether a click had actually written anything. */
    handleCopyLink() {
        // Same reasoning as saveInternal: this is the link handed to the
        // client, so it must never carry cfgId.
        this.copyToClipboard(this.buildUrl(true));
    }

    get canSaveAsNew() {
        return !!(this.knownRecordId || (this.editingId && this.findServerId(this.editingId)));
    }

    findServerId(id) {
        const entry = this.links.find((l) => l.id === id);
        return entry ? entry.serverId : null;
    }

    saveInternal({ asNew }) {
        // Always excludeId: this URL is what gets persisted as
        // Generated_URL__c and handed to the client -- it must never carry
        // cfgId, which is only meaningful for the rep's own "reopen this
        // for editing" round trip. Passing asNew through here used to let
        // "Update this link" bake cfgId into the record's own stored URL
        // whenever knownRecordId was already set, silently leaking an
        // internal record id into the link shared with the client.
        const url = this.buildUrl(true);
        const existing = this.editingId
            ? this.links.find((l) => l.id === this.editingId)
            : null;
        const knownServerId = existing ? existing.serverId : this.knownRecordId || null;
        const targetServerId = asNew ? null : knownServerId;

        // A local entry can already represent this exact server record
        // even without editingId set -- e.g. this page was opened from a
        // Saved Links bar click (knownRecordId came from the URL, not
        // from clicking Edit on a local row). Without this lookup, every
        // "Update this link" from a bar-opened page added a second local
        // row for a record that only ever existed once on the server.
        const existingByServerId = targetServerId
            ? this.links.find((l) => l.serverId === targetServerId)
            : null;
        const targetLocalId = (this.editingId && !asNew ? this.editingId : null) ||
            existingByServerId?.id ||
            null;

        const entry = {
            id: targetLocalId || `l${Date.now()}`,
            serverId: targetServerId,
            url,
            company: (this.company || '').trim(),
            industry: this.industry || '',
            accent: isHex6(this.accent)
                ? String(this.accent).trim().replace(/^#/, '')
                : '',
            exp: this.expires ? Date.parse(`${this.expires}T23:59:59`) : null,
            ts: Date.now()
        };

        if (targetLocalId) {
            this.links = this.links.map((l) => (l.id === targetLocalId ? entry : l));
        } else {
            this.links = [entry, ...this.links].slice(0, 20);
        }
        this.writeLinks();
        this.editingId = null;

        this.persistToServer(entry);
    }

    /**
     * Best-effort save to MA_Saved_Configuration__c so a rep can find this
     * link again later (localStorage above is per-browser only). Guests —
     * and anyone without the MA Config Manager permission set — have no
     * access to this class at all, so this fails for them; that specific
     * failure is expected and silent. Anything else is a real bug, worth
     * a console trace since the UI gives no other sign a save failed.
     */
    async persistToServer(entry) {
        try {
            const wasNewRecord = !entry.serverId;
            const recordId = await saveConfiguration({
                input: {
                    recordId: entry.serverId,
                    offering: OFFERING,
                    industry: entry.industry,
                    company: entry.company,
                    generatedUrl: entry.url,
                    configPayload: JSON.stringify(this._state)
                }
            });
            entry.serverId = recordId;
            this.knownRecordId = recordId;

            if (wasNewRecord) {
                // The url sent above couldn't include this record's own id
                // -- it didn't exist yet. Rebuild it now that it does, and
                // correct the stored copy to match what's actually shared,
                // so the active/inactive gate has something to key off.
                const correctedUrl = this.buildUrl();
                if (correctedUrl !== entry.url) {
                    entry.url = correctedUrl;
                    await saveConfiguration({
                        input: {
                            recordId,
                            offering: OFFERING,
                            industry: entry.industry,
                            company: entry.company,
                            generatedUrl: correctedUrl,
                            configPayload: JSON.stringify(this._state)
                        }
                    });
                }
            }

            this.links = this.links.map((l) => (l.id === entry.id ? entry : l));
            this.writeLinks();
            // Lets maConfigurator refresh its embedded Saved bar without a
            // page reload -- otherwise a rep has no way to see a new/edited
            // link show up except by navigating away and back.
            this.emit('configsaved', {});
        } catch (e) {
            const message = e?.body?.message || '';
            const isAccessError = /do not have access|insufficient/i.test(message);
            if (!isAccessError) {
                // eslint-disable-next-line no-console
                console.error('maConfigCustomize: save to MA_Saved_Configuration__c failed', e);
            }
        }
    }

    // ---------------------------------------------------------------- helpers

    emit(name, detail) {
        this.dispatchEvent(new CustomEvent(name, { detail }));
    }

    /** excludeId forces a clean, un-tagged link (used for "Save as new
     * version") even when a record is already known. Otherwise, once a
     * record exists, its id rides along as ?cfgId= -- this is what lets
     * MaConfigurationStatusController gate the link if it's later switched
     * to inactive, and what lets a resave find the same record instead of
     * creating a duplicate. */
    buildUrl(excludeId) {
        let base = '';
        try {
            base = window.location.origin + window.location.pathname;
        } catch (e) {
            base = '';
        }
        const params = [];
        const push = (k, v) => {
            if (v) params.push(`${k}=${encodeURIComponent(v)}`);
        };

        push('company', (this.company || '').trim());
        push('industry', this.industry);
        if (isHex6(this.accent)) {
            push('accent', String(this.accent).trim().replace(/^#/, ''));
        }
        if (this.expires) {
            const t = Date.parse(`${this.expires}T23:59:59`);
            if (t) push('exp', String(t));
        }
        push('rep', this._state.CONTACT_EMAIL);
        push('repname', this._state.CONTACT_NAME);
        push('book', this._state.BOOKING_URL);
        // These five were previously only ever written to a single
        // localStorage key shared by every config on the same browser --
        // editing one client's proof numbers/platform silently changed
        // what every other saved link on that machine showed, since none
        // of them carried their own values. Round-tripping them through
        // the URL, same as rep/repname/book above, makes each saved link
        // fully self-contained.
        push('src', this._state.SOURCE_PLATFORM);
        push('tgt', this._state.TARGET_PLATFORM);
        push('assets', this._state.ASSET_COUNT);
        push('deps', this._state.DEPENDENCY_COUNT);
        push('health', this._state.HEALTH_SCORE);
        if (!excludeId && this.knownRecordId) {
            push('cfgId', this.knownRecordId);
        }

        return params.length ? `${base}?${params.join('&')}` : base;
    }

    copyToClipboard(url) {
        const done = (ok) => {
            this.copyFeedback = ok ? 'Copied' : 'Press ⌘/Ctrl-C';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => {
                this.copyFeedback = 'Copy link';
            }, 1600);
        };
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(url).then(
                    () => done(true),
                    () => done(false)
                );
                return;
            }
        } catch (e) {
            // fall through to the manual-copy hint
        }
        const input = this.template.querySelector('.lb-url');
        if (input) {
            input.removeAttribute('readonly');
            input.focus();
            input.select();
            input.setAttribute('readonly', '');
        }
        done(false);
    }

    readLinks() {
        try {
            const raw = window.localStorage.getItem(LINKS_KEY);
            const parsed = raw ? JSON.parse(raw) : [];
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }

    writeLinks() {
        try {
            window.localStorage.setItem(LINKS_KEY, JSON.stringify(this.links));
        } catch (e) {
            // Private browsing / storage disabled — links just aren't remembered.
        }
    }
}
