import { LightningElement, api, track } from 'lwc';
import saveConfiguration from '@salesforce/apex/MaSavedConfigurationController.saveConfiguration';
import deleteConfiguration from '@salesforce/apex/MaSavedConfigurationController.deleteConfiguration';
import searchContacts from '@salesforce/apex/MaSavedConfigurationController.searchContacts';
import fetchLogoDataUri from '@salesforce/apex/MaBrandLookupController.fetchLogoDataUri';
import getStoryContent from '@salesforce/apex/MaStoryContentController.getStoryContent';
import { FIELDS, LINKS_KEY, initials, isHex6 } from 'c/maConfigData';

const OFFERING = 'migration-accelerator';

export default class MaConfigCustomize extends LightningElement {
    @api isOpen = false;
    @api company = '';
    @api industry = '';
    @api accent = '';

    /** Not company-page tokens like company/industry/accent above -- these
     * only ever feed Sales Cloud (Account/Contact/Opportunity linkage),
     * never the shared client URL, so they're not read from or written to
     * the URL and don't round-trip when reopening an existing link for
     * edit (see MaSavedConfigurationController's blank-input handling,
     * which is what keeps a resave from wiping out what a prior save
     * already resolved). */
    @track clientContactName = '';
    @track clientContactEmail = '';
    @track estimatedValue = '';

    /** Set once a rep picks a result from searchContacts() -- carries the
     * real Contact/Account Ids straight through to save, instead of
     * saveConfiguration having to fuzzy-match freehand text back to a
     * record. Cleared (and manual entry shown instead) whenever there's
     * no selection, whether because the rep hasn't searched yet, is
     * mid-search, or explicitly chose "Add as a new contact". */
    @track _selectedContact = null;
    @track _contactSearchTerm = '';
    @track _contactResults = [];
    @track _contactSearchBusy = false;
    @track _showManualContact = false;
    _contactSearchToken = 0;
    _contactSearchTimer = null;

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
    @track companyInvalid = false;
    @track saveError = '';
    @track brandDomain = '';
    @track brandLookupBusy = false;
    @track brandLookupError = '';
    @track _saveStatus = ''; // '' | 'saving' | 'saved'
    _autoSaveTimer = null;

    get saveLabel() {
        return this.canSaveAsNew ? 'Update this link' : 'Save link';
    }

    get saveStatusText() {
        if (this._saveStatus === 'saving') return 'Saving…';
        if (this._saveStatus === 'saved') return 'Saved ✓';
        return 'Changes save automatically';
    }

    /** value is the just-typed text (direct from the input event) when
     * available — the @api company prop may not have propagated back from
     * the parent yet at the moment a field handler calls this. */
    scheduleAutoSave(typedCompany) {
        const company = typedCompany !== undefined ? typedCompany : this.company;
        if (!(company || '').trim()) return;
        if (this._autoSaveTimer) window.clearTimeout(this._autoSaveTimer);
        this._saveStatus = '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._autoSaveTimer = window.setTimeout(() => {
            this._autoSaveTimer = null;
            this._saveStatus = 'saving';
            this.companyInvalid = false;
            this.saveError = '';
            this.saveInternal({ asNew: false });
        }, 1500);
    }

    cancelAutoSave() {
        if (this._autoSaveTimer) {
            window.clearTimeout(this._autoSaveTimer);
            this._autoSaveTimer = null;
        }
    }

    get companyFieldClass() {
        return this.companyInvalid ? 'fld field-invalid' : 'fld';
    }

    get brandLookupLabel() {
        return this.brandLookupBusy ? 'Looking up…' : 'Look up →';
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

    @track swatches = [];
    @track _industries = [];

    connectedCallback() {
        getStoryContent({ offeringKey: OFFERING })
            .then((data) => {
                if (!data) return;
                this.swatches = data.setting
                    ? data.setting.swatches.map((s) => ({ name: s.name, hex: s.hex, style: `background:#${s.hex}` }))
                    : [];
                this._industries = data.industries;
            })
            // eslint-disable-next-line no-console
            .catch((err) => { console.error('[maConfigCustomize] getStoryContent:', JSON.stringify(err)); });
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

    /* Warn when the chosen brand colour is too light to be legible on a
       white page background. Contrast ratio against white < 2.5 : 1 means
       buttons and text accents will be near-invisible. Returns null when
       the colour is fine, or { altHex, altLabel } with a suggested fix. */
    get accentWarning() {
        if (!isHex6(this.accent)) return null;
        const hex = String(this.accent).trim().replace(/^#/, '');
        const rv = parseInt(hex.slice(0, 2), 16);
        const gv = parseInt(hex.slice(2, 4), 16);
        const bv = parseInt(hex.slice(4, 6), 16);
        const lin = (c) => { const s = c / 255; return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
        const lum = 0.2126 * lin(rv) + 0.7152 * lin(gv) + 0.0722 * lin(bv);
        // Contrast ratio against white = (1 + 0.05) / (lum + 0.05)
        const contrastVsWhite = 1.05 / (lum + 0.05);
        if (contrastVsWhite >= 2.5) return null;
        // Darken each channel by halving until contrast >= 3 : 1 or 8 iterations
        let dr = rv, dg = gv, db = bv;
        for (let i = 0; i < 8; i++) {
            dr = Math.round(dr * 0.7);
            dg = Math.round(dg * 0.7);
            db = Math.round(db * 0.7);
            const dl = 0.2126 * lin(dr) + 0.7152 * lin(dg) + 0.0722 * lin(db);
            if (1.05 / (dl + 0.05) >= 3) break;
        }
        const altHex = [dr, dg, db].map((c) => c.toString(16).padStart(2, '0')).join('').toUpperCase();
        return { altHex, altLabel: `#${altHex}` };
    }

    get fields() {
        return FIELDS.map((f) => ({
            k: f.k,
            label: f.label,
            ph: f.ph,
            inputId: `fld_${f.k}`,
            value: this._state[f.k] || '',
            isTextarea: !!f.textarea
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
        this._industries.forEach((ind) => {
            options.push({
                value: ind.industryKey,
                label: ind.industryLabel,
                selected: this.industry === ind.industryKey
            });
        });
        return options;
    }

    get recentLinks() {
        const labelFor = (key) => {
            const match = this._industries.find((ind) => ind.industryKey === key);
            return match ? match.industryLabel : key || 'generic';
        };
        return this.links.slice(0, 8).map((l) => ({
            id: l.id,
            url: l.url,
            label: `${l.company || '(no company)'} · ${labelFor(l.industry)}`,
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
        this.scheduleAutoSave();
    }

    handleCompanyInput(event) {
        const value = event.currentTarget.value;
        if (this.companyInvalid && value.trim()) {
            this.companyInvalid = false;
            this.saveError = '';
        }
        this.emit('companychange', { value });
        // Pass the just-typed value directly: the @api company prop hasn't
        // propagated back from the parent yet at this point in the event cycle.
        this.scheduleAutoSave(value);
    }

    handleIndustryChange(event) {
        this.emit('industrychange', { value: event.currentTarget.value });
        this.scheduleAutoSave();
    }

    handleClientContactNameInput(event) {
        this.clientContactName = event.currentTarget.value;
    }

    handleClientContactEmailInput(event) {
        this.clientContactEmail = event.currentTarget.value;
    }

    // ------------------------------------------------------- contact search

    get showContactSearch() {
        return !this._selectedContact && !this._showManualContact;
    }

    get hasContactResults() {
        return this._contactResults.length > 0;
    }

    get contactResults() {
        return this._contactResults.map((c) => ({
            id: c.contactId,
            name: c.name,
            email: c.email,
            accountName: c.accountName,
            summary: c.accountName ? `${c.name} · ${c.accountName}` : c.name
        }));
    }

    get showNoContactResults() {
        return (
            this.showContactSearch &&
            !this._contactSearchBusy &&
            this._contactSearchTerm.trim().length >= 2 &&
            !this.hasContactResults
        );
    }

    get selectedContactSummary() {
        if (!this._selectedContact) return '';
        return this._selectedContact.accountName
            ? `${this._selectedContact.name} · ${this._selectedContact.accountName}`
            : this._selectedContact.name;
    }

    /** Debounced -- searching on every keystroke would fire a server call
     * per character typed. 300ms is long enough to skip mid-word calls,
     * short enough that the results still feel live. */
    handleContactSearchInput(event) {
        this._contactSearchTerm = event.currentTarget.value;
        if (this._contactSearchTimer) {
            window.clearTimeout(this._contactSearchTimer);
        }
        const term = this._contactSearchTerm.trim();
        if (term.length < 2) {
            this._contactResults = [];
            this._contactSearchBusy = false;
            return;
        }
        this._contactSearchBusy = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._contactSearchTimer = window.setTimeout(() => {
            this.runContactSearch(term);
        }, 300);
    }

    /** Guards against an earlier, slower search response landing after a
     * newer one and overwriting fresher results with stale ones -- each
     * call gets its own token, and only the most recently issued token's
     * response is allowed to update state. */
    async runContactSearch(term) {
        const token = ++this._contactSearchToken;
        try {
            const results = await searchContacts({ searchTerm: term });
            if (token !== this._contactSearchToken) return;
            this._contactResults = results;
        } catch (e) {
            if (token !== this._contactSearchToken) return;
            this._contactResults = [];
        } finally {
            if (token === this._contactSearchToken) {
                this._contactSearchBusy = false;
            }
        }
    }

    handleSelectContact(event) {
        const id = event.currentTarget.dataset.id;
        const match = this._contactResults.find((c) => c.contactId === id);
        if (!match) return;

        this._selectedContact = {
            id: match.contactId,
            name: match.name,
            email: match.email,
            accountId: match.accountId,
            accountName: match.accountName
        };
        this.clientContactName = match.name || '';
        this.clientContactEmail = match.email || '';
        this._contactSearchTerm = '';
        this._contactResults = [];

        // The Company field is owned by the parent (maConfigurator) --
        // this mirrors how handleEditLink already updates it, so picking a
        // contact that already has an Account shows that real Account,
        // not whatever (possibly different, possibly not-yet-typed) text
        // happens to be sitting in Company right now.
        if (match.accountName) {
            this.emit('companychange', { value: match.accountName });
        }
    }

    handleChangeContact() {
        this._selectedContact = null;
        this.clientContactName = '';
        this.clientContactEmail = '';
    }

    handleCreateNewContact() {
        this._showManualContact = true;
        this._contactSearchTerm = '';
        this._contactResults = [];
    }

    handleBackToContactSearch() {
        this._showManualContact = false;
        this.clientContactName = '';
        this.clientContactEmail = '';
    }

    handleEstimatedValueInput(event) {
        this.estimatedValue = event.currentTarget.value;
    }

    handleAccentInput(event) {
        this.emit('accentchange', { value: event.currentTarget.value });
        this.scheduleAutoSave();
    }

    handleAccentPicker(event) {
        this.emit('accentchange', {
            value: event.currentTarget.value.replace('#', '')
        });
        this.scheduleAutoSave();
    }

    handleSwatch(event) {
        this.emit('accentchange', { value: event.currentTarget.dataset.hex });
        this.scheduleAutoSave();
    }

    handleUseAltAccent(event) {
        this.emit('accentchange', { value: event.currentTarget.dataset.hex });
        this.scheduleAutoSave();
    }

    handleBrandDomainInput(event) {
        this.brandDomain = event.currentTarget.value;
        this.brandLookupError = '';
    }

    /**
     * Looks up a company's real brand color instead of the generic swatch
     * list -- entirely client-side, no server callout: fetches the
     * company's logo/favicon as an image, samples it on an offscreen
     * canvas, and sets the accent to the most common non-neutral color
     * found. The picker and swatches stay available regardless -- this
     * only ever pre-fills them, it never replaces manual control.
     *
     * The actual fetch happens server-side (MaBrandLookupController), not
     * from the browser: reading pixel data from a cross-origin image
     * requires that image's server to send an Access-Control-Allow-Origin
     * header, and none of the free logo sources tried do -- confirmed
     * directly (unavatar.io loads and displays fine in a browser tab, but
     * still fails a canvas pixel read). Apex callouts aren't subject to
     * CORS at all, so fetching there and handing back the bytes as a
     * data: URI sidesteps the problem structurally instead of hoping a
     * vendor adds the header.
     */
    async handleBrandLookup() {
        const domain = normalizeDomain(this.brandDomain);
        if (!domain) {
            this.brandLookupError = 'Enter a domain, e.g. acme.com.';
            return;
        }
        this.brandLookupBusy = true;
        this.brandLookupError = '';

        let dataUri;
        try {
            dataUri = await fetchLogoDataUri({ domain });
        } catch (e) {
            this.brandLookupBusy = false;
            const message = e?.body?.message;
            this.brandLookupError = message || 'That lookup failed. Please try again.';
            return;
        }

        if (!dataUri) {
            this.brandLookupBusy = false;
            this.brandLookupError =
                "Couldn't find a logo for that domain — check it's right, or set the color manually below.";
            return;
        }

        const img = new Image();
        img.onload = () => {
            this.brandLookupBusy = false;
            // A data: URI is same-origin by definition -- no CORS
            // question applies, so this should always succeed now. The
            // try/catch in dominantColorFromImage stays as a defensive
            // backstop, not because tainting is expected here.
            const outcome = dominantColorFromImage(img);
            if (outcome.hex) {
                this.emit('accentchange', { value: outcome.hex });
            } else {
                this.brandLookupError =
                    "Found a logo, but couldn't find a usable color in it — try setting it manually below.";
            }
        };
        img.onerror = () => {
            this.brandLookupBusy = false;
            this.brandLookupError =
                'Found a logo but could not display it. Please try again, or set the color manually below.';
        };
        img.src = dataUri;
    }

    handleExpires(event) {
        this.expires = event.currentTarget.value;
        this.scheduleAutoSave();
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
        // Restore the full token state (contact fields, proof numbers, etc.)
        // stored at save time, so the panel shows the exact values the rep
        // last saved — not a blank form over a link that was already filled.
        if (entry.state && typeof entry.state === 'object') {
            Object.keys(entry.state).forEach((key) => {
                this.emit('fieldchange', { key, value: entry.state[key] || '' });
            });
        }
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
            deleteConfiguration({ recordId: entry.serverId }).catch((e) => {
                const message = e?.body?.message || '';
                const isAccessError = /do not have access|insufficient/i.test(message);
                if (isAccessError) {
                    return;
                }
                // The local row is already gone at this point (optimistic
                // removal above), but if the server delete failed for a
                // real reason, the record still exists and will reappear
                // in the Saved Links bar -- silently accepting that here
                // was actively misleading, not just unhelpful.
                // eslint-disable-next-line no-console
                console.error('maConfigCustomize: server-side delete failed', e);
                this.saveError =
                    'That link may not have been deleted on the server -- check the Saved list.';
            });
        }
    }

    handleSave() {
        if (!this.validate()) return;
        this.cancelAutoSave();
        this._saveStatus = 'saving';
        this.saveInternal({ asNew: false });
    }

    /** Always inserts a new record + fresh URL, even if this page was
     * opened from an existing saved link. Lets a rep branch a client's
     * config into a second version without touching the original. */
    handleSaveAsNew() {
        if (!this.validate()) return;
        this.cancelAutoSave();
        this._saveStatus = 'saving';
        this.saveInternal({ asNew: true });
    }

    /**
     * Required-field check before a real Save/Update -- catches an
     * incomplete customization instead of silently persisting it, without
     * discarding anything the rep already typed. Company is the only hard
     * requirement: a client link with no client name isn't meaningfully
     * usable. Focuses the offending field so the rep isn't left guessing
     * what's missing.
     */
    validate() {
        const companyMissing = !(this.company || '').trim();
        this.companyInvalid = companyMissing;
        this.saveError = companyMissing
            ? 'Add a company name before saving — or use Save draft to hold your place.'
            : '';
        if (companyMissing) {
            const field = this.template.querySelector('#lbCompany');
            if (field) field.focus();
            return false;
        }
        return true;
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
            ts: Date.now(),
            state: this._state ? JSON.parse(JSON.stringify(this._state)) : {}
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
                    configPayload: JSON.stringify(this._state),
                    clientContactName: this.clientContactName,
                    clientContactEmail: this.clientContactEmail,
                    estimatedValue: this.estimatedValue,
                    contactId: this._selectedContact?.id || null,
                    accountId: this._selectedContact?.accountId || null
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
            this._saveStatus = 'saved';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => { this._saveStatus = ''; }, 3000);

            // Update the browser address bar so the page URL reflects the
            // saved state. Without this, reloading or sharing the current URL
            // loads the pre-save values. buildUrl() (no excludeId) includes
            // the cfgId, making the URL self-contained for the rep's editing
            // round-trip; the client copy (excludeId=true) is separate.
            try {
                const liveUrl = this.buildUrl();
                if (window.history && window.history.replaceState) {
                    window.history.replaceState(null, '', liveUrl);
                }
            } catch (e) {
                // replaceState unavailable (e.g. sandboxed iframe) -- non-fatal.
            }

            // Lets maConfigurator refresh its embedded Saved bar without a
            // page reload -- otherwise a rep has no way to see a new/edited
            // link show up except by navigating away and back.
            this.emit('configsaved', {});
        } catch (e) {
            const message = e?.body?.message || '';
            const isAccessError = /do not have access|insufficient/i.test(message);
            if (isAccessError) {
                this._saveStatus = '';
                return;
            }
            // eslint-disable-next-line no-console
            console.error('maConfigCustomize: save to MA_Saved_Configuration__c failed', e);
            this._saveStatus = '';
            // A failed save used to be entirely silent from here -- the
            // local list still updated (optimistically, before this call),
            // so the panel looked like it worked even when nothing reached
            // the server. Surface it the same way validation errors show.
            this.saveError =
                message || 'That link did not save. Please try again.';
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
        // The client's page has no DB round trip to read from -- everything
        // it renders comes from this URL, custom note included, same as
        // src/tgt/assets/deps/health above.
        push('note', this._state.CUSTOM_NOTE);
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

/** "https://www.acme.com/about" -> "acme.com". Lets a rep paste whatever
 * they have (a full URL, www-prefixed, with a path) instead of requiring
 * an exact bare domain. */
function normalizeDomain(value) {
    let v = String(value || '').trim().toLowerCase();
    if (!v) return '';
    v = v.replace(/^https?:\/\//, '');
    v = v.replace(/^www\./, '');
    v = v.split('/')[0];
    v = v.split('?')[0];
    return /^[a-z0-9.-]+\.[a-z]{2,}$/.test(v) ? v : '';
}

/**
 * Samples a loaded, same-canvas-drawable image and returns the most common
 * non-neutral color as a 6-char hex string (no #), or null if nothing
 * usable was found (e.g. a logo that's entirely black/white/gray, or a
 * canvas read blocked by CORS). Deliberately simple -- a mode over a
 * coarse color bucket, not a proper clustering algorithm -- this only
 * needs to beat "generic default swatch," not be exact.
 */
function dominantColorFromImage(img) {
    try {
        const canvas = document.createElement('canvas');
        const size = 48;
        canvas.width = size;
        canvas.height = size;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, size, size);
        // Throws SecurityError here (not before) if the image loaded but
        // came from a source with no CORS support -- a "tainted" canvas
        // can be drawn to and displayed, just never read back pixel by
        // pixel. That's a different, later failure point than the image
        // never loading at all, and worth telling the rep apart.
        const { data } = ctx.getImageData(0, 0, size, size);

        // Two passes over the same pixels, not one: many real logos are
        // mostly or entirely black/white/gray (a wordmark, a monochrome
        // icon), and rejecting every neutral pixel outright used to mean
        // those logos found nothing at all -- a hard dead end for a
        // meaningfully common case, not a rare edge case. Pass 1 looks
        // for a real, non-neutral brand color first (unchanged from
        // before); pass 2 only runs if that came up empty, and falls
        // back to the most common color overall, neutral or not, so a
        // rep always gets *something* to start from rather than being
        // sent to the manual picker for something as ordinary as a
        // black-on-white logo.
        const colorBuckets = new Map();
        const anyBuckets = new Map();
        const bucketKey = (r, g, b) =>
            [r, g, b].map((c) => Math.round(c / 16) * 16).join(',');
        const addTo = (map, key, r, g, b) => {
            const bucket = map.get(key) || { r: 0, g: 0, b: 0, n: 0 };
            bucket.r += r;
            bucket.g += g;
            bucket.b += b;
            bucket.n += 1;
            map.set(key, bucket);
        };

        for (let i = 0; i < data.length; i += 4) {
            const r = data[i];
            const g = data[i + 1];
            const b = data[i + 2];
            const a = data[i + 3];
            if (a < 128) continue; // transparent background

            const key = bucketKey(r, g, b);
            addTo(anyBuckets, key, r, g, b);

            const max = Math.max(r, g, b);
            const min = Math.min(r, g, b);
            const isNeutral = max < 30 || min > 225 || max - min < 18;
            if (isNeutral) continue; // near-black, near-white, or gray

            addTo(colorBuckets, key, r, g, b);
        }

        const pickWinner = (map) => {
            let best = null;
            map.forEach((bucket) => {
                if (!best || bucket.n > best.n) best = bucket;
            });
            return best;
        };
        const winner = pickWinner(colorBuckets) || pickWinner(anyBuckets);
        if (!winner) return { hex: null, tainted: false };

        const toHex = (v) =>
            Math.max(0, Math.min(255, Math.round(v)))
                .toString(16)
                .padStart(2, '0');
        return {
            hex:
                toHex(winner.r / winner.n) +
                toHex(winner.g / winner.n) +
                toHex(winner.b / winner.n),
            tainted: false
        };
    } catch (e) {
        // SecurityError: canvas read blocked because the image source
        // sent no CORS headers. The image itself loaded fine -- only the
        // pixel read failed.
        return { hex: null, tainted: true };
    }
}
