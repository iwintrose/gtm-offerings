import { LightningElement, api, track } from 'lwc';
import submitRequest from '@salesforce/apex/MaAssessmentRequestController.submitRequest';

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

export default class MaConfigBooking extends LightningElement {
    @api isOpen = false;
    @api bookingUrl = '';
    @api prospect = '';
    @api industryLabel = '';

    @track form = {
        name: '',
        email: '',
        company: '',
        role: '',
        currentPlatform: '',
        environmentSize: '',
        timeline: '',
        context: ''
    };

    @track showForm = true;
    @track submitting = false;
    @track errorMessage = '';
    @track nameInvalid = false;
    @track emailInvalid = false;

    platformOptions = PLATFORMS;
    sizeOptions = SIZES;
    timelineOptions = TIMELINES;

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
            company: this.form.company,
            role: this.form.role,
            currentPlatform: this.form.currentPlatform,
            environmentSize: this.form.environmentSize,
            timeline: this.form.timeline,
            context: this.form.context,
            prospect: this.prospect,
            industry: this.industryLabel
        };

        try {
            await submitRequest({ input: payload });
            this.showForm = false;
            this.dispatchEvent(
                new CustomEvent('submitted', { detail: { email } })
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
