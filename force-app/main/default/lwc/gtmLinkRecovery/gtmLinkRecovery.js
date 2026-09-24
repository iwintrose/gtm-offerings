import { LightningElement, track } from 'lwc';
import recoverLink from '@salesforce/apex/GtmLinkRecoveryController.recoverLink';

const EMAIL_RE = /^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/;

export default class GtmLinkRecovery extends LightningElement {
    @track email = '';
    @track submitted = false;
    @track loading = false;
    @track errorMessage = '';

    handleEmailChange(event) {
        this.email = event.target.value;
        this.errorMessage = '';
    }

    async handleSubmit() {
        this.errorMessage = '';

        if (!this.email || !EMAIL_RE.test(this.email.trim())) {
            this.errorMessage = 'Please enter a valid email address.';
            return;
        }

        this.loading = true;
        try {
            await recoverLink({ email: this.email.trim() });
            this.submitted = true;
        } catch (e) {
            this.errorMessage = 'Something went wrong. Please try again later.';
        } finally {
            this.loading = false;
        }
    }
}
