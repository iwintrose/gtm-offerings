import { LightningElement, api, track } from 'lwc';
import submitRequest from '@salesforce/apex/GtmAssessmentRequestController.submitRequest';
import getDraft from '@salesforce/apex/GtmFormDraftController.getDraft';
import saveDraft from '@salesforce/apex/GtmFormDraftController.saveDraft';
import clearDraft from '@salesforce/apex/GtmFormDraftController.clearDraft';

// How long typing has to stop before a draft is written. Short enough that
// closing the tab mid-thought keeps the answer, long enough that filling in a
// sentence is one save rather than forty.
const DRAFT_IDLE_MS = 1500;

// Where the browser keeps its own copy and its identity.
const LOCAL_PREFIX = 'ma-draft:';
const VISITOR_KEY = 'ma-visitor';

/**
 * A value this browser keeps, and the only thing that can reach its draft.
 *
 * Random rather than derived: a key made from the link id or the email would be
 * guessable, and a guessable key would make one visitor's half-typed answers
 * readable by anyone who could guess it.
 */
function visitorKey() {
    try {
        let k = window.localStorage.getItem(VISITOR_KEY);
        if (k && k.length >= 16) return k;
        const bytes = new Uint8Array(18);
        window.crypto.getRandomValues(bytes);
        k = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
        window.localStorage.setItem(VISITOR_KEY, k);
        return k;
    } catch (e) {
        // Private browsing, or storage switched off. Resume simply does not
        // happen; the form still works, which is the part that matters.
        return '';
    }
}

const PLATFORMS = [
    'Select…',
    'Oracle Eloqua',
    'Salesforce Marketing Cloud',
    'Marketo',
    'HubSpot',
    'Adobe / Pardot',
    'Other',
    'Not sure'
];
const SIZES = [
    'Select…',
    'Under 500 assets',
    '500–2,000',
    '2,000–10,000',
    '10,000+',
    'Not sure yet'
];
const TIMELINES = [
    'Select…',
    'Active — next 3 months',
    '3–6 months',
    '6–12 months',
    'Just exploring'
];

export default class GtmConfigBooking extends LightningElement {
    @api isOpen = false;
    @api bookingUrl = '';
    @api prospect = '';
    @api industryLabel = '';
    @api savedRecordId = '';
    /** HMAC token from verifyAndIssueToken(); required by submitRequest() when the
     *  engagement link has a password set. Passed down from gtmConfigurator. */
    @api submissionToken = '';
    /** Pre-filled from the configurator's company param so the guest doesn't retype it. */
    @api prefillCompany = '';
    /** Pre-filled from the configurator's SOURCE_PLATFORM token. Matched
     *  case-insensitively against the platform options list; no-match leaves blank. */
    @api prefillPlatform = '';

    @track form = {
        name: '',
        email: '',
        company: '',
        role: '',
        currentPlatform: '',
        environmentSize: '',
        timeline: '',
        context: '',
        // Rich assessment fields
        targetPlatform: '',
        budgetRange: '',
        contactCount: '',
        monthlySendVolume: '',
        painPoints: '',
        migrationGoals: '',
        keyIntegrations: '',
        successCriteria: '',
        internalTeamSize: '',
        executiveSponsorship: '',
        decisionMakers: '',
        urgencyDriver: ''
    };

    /** The session this visit belongs to, so a resume can be tied back to the
     *  interaction trail that led to it. Passed down from the configurator. */
    @api sessionId = '';

    @track resumed = false;
    @track showForm = true;
    @track submitting = false;
    @track errorMessage = '';
    @track nameInvalid = false;
    @track emailInvalid = false;

    sizeOptions = SIZES;
    timelineOptions = TIMELINES;

    connectedCallback() {
        this.applyPrefill();
    }

    applyPrefill() {
        const company = this.prefillCompany || '';
        const raw = (this.prefillPlatform || '').toLowerCase().trim();
        const matchedPlatform = raw
            ? (PLATFORMS.find((p) => p.toLowerCase() === raw) || '')
            : '';
        this.form = {
            ...this.form,
            company: company || this.form.company,
            currentPlatform: matchedPlatform || this.form.currentPlatform
        };
    }

    get platformOptionsForSelect() {
        return PLATFORMS.map((p) => {
            const value = p === 'Select…' ? '' : p;
            return { value, label: p, selected: value === this.form.currentPlatform };
        });
    }

    // ---------------------------------------------------------------- display

    get overlayClass() {
        return this.isOpen ? 'bk open' : 'bk';
    }

    get nameFieldClass() {
        return this.nameInvalid ? 'bk-field invalid' : 'bk-field';
    }

    get emailFieldClass() {
        return this.emailInvalid ? 'bk-field invalid' : 'bk-field';
    }

    get submitLabel() {
        return this.submitting ? 'Sending…' : 'Request my assessment →';
    }

    get hasBookingUrl() {
        return !!(this.bookingUrl && this.bookingUrl.trim());
    }

    get firstName() {
        const first = (this.form.name || '').trim().split(/\s+/)[0];
        return first || 'there';
    }

    get confirmMessage() {
        if (this.hasBookingUrl) {
            return 'We’ve sent your request to our team. Now pick a time that works and we’ll be ready for you.';
        }
        return `We’ve sent your request to our team, we’ll follow up at ${this.form.email} to find a time.`;
    }

    // ----------------------------------------------------------------- events

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        let value = event.currentTarget.value;
        if (value === 'Select…') {
            value = '';
        }
        this.form = { ...this.form, [field]: value };

        if (field === 'name' && value.trim()) this.nameInvalid = false;
        if (field === 'email' && this.isValidEmail(value)) {
            this.emailInvalid = false;
        }
        this.queueDraft(field);
    }

    // ─── resume ───────────────────────────────────────────────────────────────

    _visitor = '';
    _draftTimer = null;
    _lastSaved = '';

    /**
     * What the visitor has typed, and nothing else.
     *
     * Built from the form's own state rather than read off the DOM, so a field
     * the page pre-filled from the link is never written into a draft: the
     * draft is theirs, not ours.
     */
    draftPayload() {
        const out = {};
        Object.keys(this.form).forEach((k) => {
            const v = (this.form[k] || '').trim ? this.form[k].trim() : this.form[k];
            if (v) out[k] = v;
        });
        return out;
    }

    localKey() { return `${LOCAL_PREFIX}${this.savedRecordId}`; }

    /**
     * Save after typing stops.
     *
     * The browser's own copy is written immediately and is what a resume
     * actually reads: it is instant, it works with no connection, and it cannot
     * fail. The server copy is written on the same beat and is what lets the
     * team see that someone got two thirds of the way through and stopped --
     * so if it fails, resume is unaffected.
     */
    queueDraft(field) {
        const payload = this.draftPayload();
        const json = JSON.stringify(payload);
        if (json === '{}' || json === this._lastSaved) return;

        try { window.localStorage.setItem(this.localKey(), json); } catch (e) { /* not fatal */ }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._draftTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._draftTimer = setTimeout(() => {
            this._lastSaved = json;
            if (!this.savedRecordId || !this._visitor) return;
            saveDraft({
                configId: this.savedRecordId,
                visitorKey: this._visitor,
                draftJson: json,
                furthestField: field || '',
                sessionId: this.sessionId
            }).catch(() => { /* resume still works from the local copy */ });
        }, DRAFT_IDLE_MS);
    }

    /**
     * Put back what they had.
     *
     * The browser's copy wins when both exist: it is never older, because the
     * server copy is written on a delay behind it.
     */
    async restoreDraft() {
        if (!this.savedRecordId) return;
        this._visitor = visitorKey();

        let saved = null;
        try {
            const local = window.localStorage.getItem(this.localKey());
            if (local) saved = JSON.parse(local);
        } catch (e) { saved = null; }

        if (!saved && this._visitor) {
            try {
                const remote = await getDraft({
                    configId: this.savedRecordId, visitorKey: this._visitor
                });
                if (remote && remote.draftJson) saved = JSON.parse(remote.draftJson);
            } catch (e) { saved = null; }
        }

        if (!saved || !Object.keys(saved).length) return;

        // Merged over the current form rather than replacing it, so a field the
        // page pre-filled survives where the draft has nothing to say.
        const merged = { ...this.form };
        Object.keys(saved).forEach((k) => {
            if (k in merged && saved[k]) merged[k] = saved[k];
        });
        this.form = merged;
        this.resumed = true;
        this.dispatchEvent(new CustomEvent('formresumed'));
    }

    /** Once it is submitted, offering it back reads as "we lost it". */
    forgetDraft() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._draftTimer);
        this._lastSaved = '';
        try { window.localStorage.removeItem(this.localKey()); } catch (e) { /* fine */ }
        if (!this.savedRecordId || !this._visitor) return;
        clearDraft({ configId: this.savedRecordId, visitorKey: this._visitor })
            .catch(() => { /* the submission already succeeded */ });
    }

    get resumeNote() {
        return 'We kept what you had already filled in. Change anything you like.';
    }

    disconnectedCallback() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._draftTimer);
    }

    handleOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleReopen(event) {
        event.preventDefault();
        this.showForm = true;
    }

    /** Parent calls this when re-opening so the modal starts on the form. */
    @api
    reset() {
        this.showForm = true;
        this.errorMessage = '';
        this.submitting = false;
        this.restoreDraft();
    }

    async handleSubmit(event) {
        event.preventDefault();
        if (this.submitting) return;

        const name = (this.form.name || '').trim();
        const email = (this.form.email || '').trim();
        this.nameInvalid = name.length === 0;
        this.emailInvalid = !this.isValidEmail(email);

        if (this.nameInvalid || this.emailInvalid) {
            this.errorMessage = 'Please add your name and a valid work email.';
            return;
        }

        this.errorMessage = '';
        this.submitting = true;

        const payload = {
            name,
            email,
            company            : this.form.company,
            role               : this.form.role,
            currentPlatform    : this.form.currentPlatform,
            environmentSize    : this.form.environmentSize,
            timeline           : this.form.timeline,
            context            : this.form.context,
            // Rich assessment fields
            targetPlatform     : this.form.targetPlatform,
            budgetRange        : this.form.budgetRange,
            contactCount       : this.form.contactCount,
            monthlySendVolume  : this.form.monthlySendVolume,
            painPoints         : this.form.painPoints,
            migrationGoals     : this.form.migrationGoals,
            keyIntegrations    : this.form.keyIntegrations,
            successCriteria    : this.form.successCriteria,
            internalTeamSize   : this.form.internalTeamSize,
            executiveSponsorship: this.form.executiveSponsorship,
            decisionMakers     : this.form.decisionMakers,
            urgencyDriver      : this.form.urgencyDriver,
            prospect           : this.prospect,
            industry           : this.industryLabel,
            savedRecordId      : this.savedRecordId,
            submissionToken    : this.submissionToken || ''
        };

        try {
            const result = await submitRequest({ input: payload });
            this.showForm = false;
            this.resumed = false;
            this.forgetDraft();
            this.dispatchEvent(
                new CustomEvent('submitted', {
                    detail: {
                        email,
                        assessmentRequestId: result ? result.assessmentRequestId : null,
                        // Who the anonymous reading turns out to have been.
                        contactId: result ? result.contactId : null
                    }
                })
            );
        } catch (error) {
            this.errorMessage = this.readError(error);
        } finally {
            this.submitting = false;
        }
    }

    // ---------------------------------------------------------------- helpers

    isValidEmail(value) {
        return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(value || '').trim());
    }

    readError(error) {
        const body = error && error.body;
        if (body && body.message) return body.message;
        if (Array.isArray(body) && body.length && body[0].message) {
            return body[0].message;
        }
        return 'We could not send that just now. Please try again in a moment.';
    }
}
