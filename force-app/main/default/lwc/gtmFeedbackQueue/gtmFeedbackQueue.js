import { LightningElement, track } from 'lwc';
import getOpenFeedback from '@salesforce/apex/GtmFeedbackController.getOpenFeedback';
import respond from '@salesforce/apex/GtmFeedbackController.respond';
import getPageTitles from '@salesforce/apex/GtmPageContentController.getPageTitles';
import { TEMPLATE_LABELS } from 'c/gtmPageLayouts';

/**
 * What the people selling the offerings have said, and what the writers did.
 *
 * The other half of the card on the GTM Offerings overview. Feedback with no
 * reply is a suggestion box nobody empties, so this exists to be emptied: every
 * note carries the two things a writer can do about it — say something back,
 * and say where it now stands.
 */
const STATUSES = [
    { value: 'In Progress',     label: 'Being worked on' },
    { value: 'Needs More Info', label: 'Ask them something' },
    { value: 'Resolved',        label: 'Resolved' },
    { value: 'Declined',        label: 'Not changing this' }
];

export default class GtmFeedbackQueue extends LightningElement {
    @track notes = [];
    @track loading = true;
    @track error = '';
    @track openId = '';
    @track reply = '';
    @track nextStatus = 'Resolved';
    @track saving = false;
    // Page-title overrides from renamePage(), keyed "<offeringKey>::<templateType>".
    _pageTitles = {};

    statusOptions = STATUSES;

    connectedCallback() { this.load(); }

    load() {
        this.loading = true;
        return Promise.all([
            getOpenFeedback(),
            getPageTitles()
        ])
            .then(([rows, titles]) => {
                this._pageTitles = titles || {};
                const pt = this._pageTitles;
                this.notes = (rows || []).map((r) => ({
                    key: r.recordId,
                    name: r.name,
                    body: r.body,
                    who: r.submittedBy || 'Someone',
                    when: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : '',
                    offering: r.offeringKey,
                    page: r.templateType
                        ? (pt[r.offeringKey + '::' + r.templateType]
                            || TEMPLATE_LABELS[r.templateType]
                            || r.templateType)
                        : '',
                    status: r.status,
                    statusClass: `q-pill q-pill--${(r.status || 'New').toLowerCase().replace(/\s+/g, '-')}`,
                    response: r.response,
                    hasResponse: !!r.response,
                    // Already asked and still waiting: nothing for the writer to
                    // do until they answer, so it does not read as a to-do.
                    waitingOnThem: r.status === 'Needs More Info',
                    rowClass: r.status === 'Needs More Info' ? 'q-note q-note--waiting' : 'q-note',
                    isOpen: false
                }));
                this.error = '';
            })
            .catch((e) => { this.error = (e && e.body && e.body.message) || 'Feedback could not be loaded.'; })
            .finally(() => { this.loading = false; });
    }

    get rows() {
        return this.notes.map((n) => ({
            ...n,
            isOpen: n.key === this.openId,
            replyLabel: n.key === this.openId ? 'Cancel' : (n.hasResponse ? 'Update reply' : 'Reply')
        }));
    }

    get hasNotes() { return this.notes.length > 0; }
    get showEmpty() { return !this.loading && !this.error && !this.hasNotes; }
    get countLabel() {
        const n = this.notes.length;
        return n === 1 ? '1 note waiting' : `${n} notes waiting`;
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this.openId === id) { this.openId = ''; return; }
        const note = this.notes.find((n) => n.key === id);
        this.openId = id;
        this.reply = note && note.response ? note.response : '';
        this.nextStatus = 'Resolved';
    }

    handleReplyChange(event) { this.reply = event.target.value; }
    handleStatusChange(event) { this.nextStatus = event.detail.value; }

    get saveDisabled() { return this.saving; }

    handleSave() {
        if (!this.openId) return;
        this.saving = true;
        respond({ recordId: this.openId, status: this.nextStatus, response: this.reply })
            .then(() => { this.openId = ''; this.reply = ''; return this.load(); })
            .catch((e) => { this.error = (e && e.body && e.body.message) || 'The reply could not be saved.'; })
            .finally(() => { this.saving = false; });
    }
}
