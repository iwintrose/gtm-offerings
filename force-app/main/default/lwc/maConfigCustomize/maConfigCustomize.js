import { LightningElement, api, track } from 'lwc';
import {
    FIELDS,
    INDUSTRIES,
    IND_ORDER,
    SWATCHES,
    LINKS_KEY,
    initials,
    isHex6
} from 'c/maConfigData';

export default class MaConfigCustomize extends LightningElement {
    @api isOpen = false;
    @api company = '';
    @api industry = '';
    @api accent = '';

    @track expires = '';
    @track copyLabel = 'Save & copy';
    @track links = [];
    @track editingId = null;

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
        this.links = this.readLinks();
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
        this.copyLabel = 'Save & copy';
    }

    handleEditLink(event) {
        const id = event.currentTarget.dataset.id;
        const entry = this.links.find((l) => l.id === id);
        if (!entry) return;

        this.editingId = id;
        this.copyLabel = 'Save changes';
        this.expires = entry.exp
            ? new Date(entry.exp).toISOString().slice(0, 10)
            : '';
        this.emit('companychange', { value: entry.company || '' });
        this.emit('industrychange', { value: entry.industry || '' });
        this.emit('accentchange', { value: entry.accent || '' });
    }

    handleDeleteLink(event) {
        const id = event.currentTarget.dataset.id;
        this.links = this.links.filter((l) => l.id !== id);
        this.writeLinks();
        if (this.editingId === id) {
            this.editingId = null;
            this.copyLabel = 'Save & copy';
        }
    }

    handleCopy() {
        const url = this.buildUrl();
        const entry = {
            id: this.editingId || `l${Date.now()}`,
            url,
            company: (this.company || '').trim(),
            industry: this.industry || '',
            accent: isHex6(this.accent)
                ? String(this.accent).trim().replace(/^#/, '')
                : '',
            exp: this.expires ? Date.parse(`${this.expires}T23:59:59`) : null,
            ts: Date.now()
        };

        if (this.editingId) {
            this.links = this.links.map((l) => (l.id === entry.id ? entry : l));
        } else {
            this.links = [entry, ...this.links].slice(0, 20);
        }
        this.writeLinks();
        this.editingId = null;

        this.copyToClipboard(url);
    }

    // ---------------------------------------------------------------- helpers

    emit(name, detail) {
        this.dispatchEvent(new CustomEvent(name, { detail }));
    }

    buildUrl() {
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

        return params.length ? `${base}?${params.join('&')}` : base;
    }

    copyToClipboard(url) {
        const done = (ok) => {
            this.copyLabel = ok ? 'Copied' : 'Press ⌘/Ctrl-C';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => {
                this.copyLabel = 'Save & copy';
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
