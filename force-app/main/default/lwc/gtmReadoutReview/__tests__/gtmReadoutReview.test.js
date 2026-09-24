import { createElement } from 'lwc';
import GtmReadoutReview from 'c/gtmReadoutReview';
import { CurrentPageReference } from 'lightning/navigation';
import getReadout from '@salesforce/apex/GtmReadoutController.getReadout';
import getReadoutByRequest from '@salesforce/apex/GtmReadoutController.getReadoutByRequest';
import saveDraftContent from '@salesforce/apex/GtmReadoutController.saveDraftContent';
import submitForApproval from '@salesforce/apex/GtmReadoutController.submitForApproval';
import recallApproval from '@salesforce/apex/GtmReadoutController.recallApproval';
import publishReadout from '@salesforce/apex/GtmReadoutController.publishReadout';
import unpublishReadout from '@salesforce/apex/GtmReadoutController.unpublishReadout';
import returnToDraft from '@salesforce/apex/GtmReadoutController.returnToDraft';
import selfApproveReadout from '@salesforce/apex/GtmReadoutController.selfApproveReadout';
import getReadoutBaseUrl from '@salesforce/apex/GtmSavedConfigurationController.getReadoutBaseUrl';

jest.mock(
    '@salesforce/apex/GtmReadoutController.getReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.getReadoutByRequest',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.saveDraftContent',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.submitForApproval',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.recallApproval',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.publishReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.unpublishReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.returnToDraft',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmReadoutController.selfApproveReadout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmSavedConfigurationController.getReadoutBaseUrl',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function setPageRef(element, readoutId) {
    CurrentPageReference.emit({ state: { c__readout: readoutId } });
    await flushPromises();
}

// What GtmSavedConfigurationController.getReadoutBaseUrl actually returns:
// the bare community siteUrl + '/s' (no page path appended). The public
// readout link is built from this, so the test uses the real shape
// rather than a bare domain.
const SITE_HOME = 'https://example.my.site.com/gtm/s';

describe('c-gtm-readout-review', () => {
    beforeEach(() => {
        getReadoutBaseUrl.mockResolvedValue(SITE_HOME);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders an editable rich text field and Save/Send for approval in Draft', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>hello</p>',
            approvedContent: '',
            publicLinkToken: '',
            assessmentRequestName: 'Acme Assessment',
            company: 'Acme'
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).not.toBeNull();
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const labels = Array.from(buttons).map((b) => b.label);
        expect(labels).toContain('Save Draft');
        expect(labels).toContain('Send for approval');
    });

    // Approving is the platform's job in manager mode (the default —
    // selfApprovalEnabled falsy/absent on the DTO). The button must not exist
    // in any state unless the org has turned self-approval on; that toggle-on
    // behavior is covered in the "self-approval mode" describe block below.
    it('never offers an Approve button in any state when self-approval is off', async () => {
        for (const status of ['Draft', 'Pending Approval', 'Approved', 'Published']) {
            getReadout.mockResolvedValue({
                id: 'r1',
                status,
                draftContent: '<p>hello</p>',
                approvedContent: '<p>approved copy</p>',
                publicLinkToken: status === 'Published' ? 'tok123' : '',
                selfApprovalEnabled: false,
                isOwner: true
            });
            const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
            document.body.appendChild(element);
            // eslint-disable-next-line no-await-in-loop
            await setPageRef(element, 'r1');

            const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
                .map((b) => b.label);
            expect(labels).not.toContain('Approve');
            document.body.removeChild(element);
        }
    });

    it('saves the draft, then submits for approval, and reloads', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>hello</p>',
            approvedContent: '',
            publicLinkToken: ''
        });
        saveDraftContent.mockResolvedValue();
        submitForApproval.mockResolvedValue();

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        const submitButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Send for approval');
        submitButton.click();
        await flushPromises();

        // The save has to go first: submitting locks the record, so an edit
        // sent afterwards would be refused.
        expect(saveDraftContent).toHaveBeenCalledWith({ readoutId: 'r1', content: '<p>hello</p>' });
        expect(submitForApproval).toHaveBeenCalledWith({ readoutId: 'r1' });
        expect(getReadout).toHaveBeenCalledTimes(2);
    });

    it('shows the pending banner and only a Recall action while awaiting approval', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Pending Approval',
            draftContent: '<p>waiting</p>',
            approvedContent: '',
            publicLinkToken: '',
            approvalState: 'Pending',
            pendingApprover: 'Dana Manager',
            isLocked: true
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('.rr-pending').textContent).toContain('Dana Manager');
        // Locked by the approval process — the content an approver is reading
        // must not be editable.
        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).toBeNull();
        const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .map((b) => b.label);
        expect(labels).toContain('Recall request');
        expect(labels).not.toContain('Save Draft');
        expect(labels).not.toContain('Send for approval');
        expect(labels).not.toContain('Publish');
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Pending Approval');
    });

    // The field update that sets Status__c is a consequence of the approval,
    // not the approval itself. If it never fired, the record still has to
    // behave as locked — ProcessInstance is the authority.
    it('treats a locked record as pending even when the status label is stale', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>waiting</p>',
            approvedContent: '',
            publicLinkToken: '',
            approvalState: 'Pending',
            isLocked: true
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).toBeNull();
        const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .map((b) => b.label);
        expect(labels).toContain('Recall request');
        expect(labels).not.toContain('Save Draft');
    });

    it('recalls the request and reloads into the editable Draft state', async () => {
        const pending = {
            id: 'r1',
            status: 'Pending Approval',
            draftContent: '<p>waiting</p>',
            approvedContent: '',
            publicLinkToken: '',
            approvalState: 'Pending',
            isLocked: true
        };
        getReadout
            .mockResolvedValueOnce(pending)
            .mockResolvedValue({
                ...pending,
                status: 'Draft',
                approvalState: 'Recalled',
                isLocked: false
            });
        recallApproval.mockResolvedValue();

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Recall request')
            .click();
        await flushPromises();

        expect(recallApproval).toHaveBeenCalledWith({ readoutId: 'r1' });
        expect(getReadout).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Draft');
    });

    // Approval says "fit to send". Publish is what actually sends it, and it is
    // still a separate, deliberate rep action — a manager approving must never
    // put a live link in a prospect's inbox by itself.
    it('does not offer Publish until after approval, and never mints a link on approval', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Pending Approval',
            draftContent: '<p>waiting</p>',
            approvedContent: '',
            publicLinkToken: '',
            approvalState: 'Pending',
            isLocked: true
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(Array.from(element.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label))
            .not.toContain('Publish');
        expect(element.shadowRoot.querySelector('.rr-live-link')).toBeNull();
    });

    it('links out to the review case, and shows no comment UI of its own', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>hello</p>',
            approvedContent: '',
            publicLinkToken: '',
            caseId: '500000000000001AAA',
            caseNumber: '00001234'
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        const link = element.shadowRoot.querySelector('.rr-case-link');
        expect(link).not.toBeNull();
        expect(link.textContent).toContain('00001234');
        expect(link.getAttribute('href')).toBe('/lightning/r/Case/500000000000001AAA/view');
        // The rep replies natively on the Case — there is deliberately no
        // comment thread rendered in this component.
        expect(element.shadowRoot.querySelector('lightning-textarea')).toBeNull();
    });

    it('shows read-only content and a Publish button when Approved', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Approved',
            draftContent: '',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: ''
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-formatted-rich-text')).not.toBeNull();
        const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label);
        expect(labels).toContain('Publish');
    });

    it('shows the live public link and an Unpublish button when Published', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Published',
            draftContent: '',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: 'tok123'
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        const link = element.shadowRoot.querySelector('.rr-live-link');
        expect(link).not.toBeNull();
        expect(link.getAttribute('href')).toContain('tok123');
        const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label);
        expect(labels).toContain('Unpublish');
    });

    // The rep copies this link out of the UI and sends it to a prospect, so it
    // has to be the canonical Experience Cloud route — `/readout?token=`, per
    // experiences/GTM_Accelerator1/routes/readout.json and
    // docs/runbooks/readout-public-link.md. The `/readout/<token>` path form
    // 404s at the Aura site router; gtmReadoutView parses it only as an
    // explicitly-labelled last-resort fallback, which is not something to
    // hand a prospect.
    it('copies the public link in the canonical ?token= query-param form', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Published',
            draftContent: '',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: 'tok123'
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        const href = element.shadowRoot.querySelector('.rr-live-link').getAttribute('href');
        expect(href).toBe('https://example.my.site.com/gtm/s/readout?token=tok123');
        expect(href).not.toContain('/readout/tok123');
        // The visible text is the link itself, so a rep copying either the
        // href or the label gets the same working URL.
        expect(element.shadowRoot.querySelector('.rr-live-link').textContent).toBe(href);
    });

    it('url-encodes the token rather than interpolating it raw', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Published',
            draftContent: '',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: 'a+b/c=d'
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('.rr-live-link').getAttribute('href'))
            .toBe('https://example.my.site.com/gtm/s/readout?token=a%2Bb%2Fc%3Dd');
    });

    // The server state machine (GtmReadoutController) is the real guard, but
    // the editor must not offer an action the server will reject, and must
    // not surface the public token before there is one.
    async function renderAt(status, extra = {}) {
        getReadout.mockResolvedValue({
            id: 'r1',
            status,
            draftContent: '<p>draft</p>',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: '',
            ...extra
        });
        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');
        return element;
    }

    function labelsOf(element) {
        return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label);
    }

    it('offers no Publish or Unpublish while still a Draft', async () => {
        const element = await renderAt('Draft');
        const labels = labelsOf(element);
        expect(labels).not.toContain('Publish');
        expect(labels).not.toContain('Unpublish');
    });

    it('never shows a public link before the readout is published', async () => {
        // A token on a Draft/Approved record would be a leak of a link that
        // does not yet resolve — and a rep could distribute it early.
        const draft = await renderAt('Draft', { publicLinkToken: 'tok-should-not-show' });
        expect(draft.shadowRoot.querySelector('.rr-live-link')).toBeNull();
        expect(draft.shadowRoot.textContent).not.toContain('tok-should-not-show');

        const approved = await renderAt('Approved', { publicLinkToken: 'tok-should-not-show' });
        expect(approved.shadowRoot.querySelector('.rr-live-link')).toBeNull();
        expect(approved.shadowRoot.textContent).not.toContain('tok-should-not-show');
    });

    it('offers no re-approve or re-edit once Approved', async () => {
        const element = await renderAt('Approved');
        const labels = labelsOf(element);
        expect(labels).not.toContain('Approve');
        expect(labels).not.toContain('Save Draft');
        expect(labels).not.toContain('Unpublish');
        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).toBeNull();
    });

    it('offers no re-publish or re-edit once Published, and shows the approved snapshot', async () => {
        const element = await renderAt('Published', { publicLinkToken: 'tok123' });
        const labels = labelsOf(element);
        expect(labels).not.toContain('Publish');
        expect(labels).not.toContain('Approve');
        expect(labels).not.toContain('Save Draft');
        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).toBeNull();
        // The prospect sees Approved_Content__c, so that is what the rep
        // must be reviewing here — never the still-editable draft.
        expect(element.shadowRoot.querySelector('lightning-formatted-rich-text').value)
            .toBe('<p>approved copy</p>');
    });

    it('leaves the readout on its current status when publish fails', async () => {
        const element = await renderAt('Approved');
        publishReadout.mockRejectedValue({ body: { message: 'Only an Approved readout can be published' } });

        Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Publish')
            .click();
        await flushPromises();

        expect(publishReadout).toHaveBeenCalledWith({ readoutId: 'r1' });
        // A rejected publish must not optimistically flip the UI to Published.
        expect(labelsOf(element)).toContain('Publish');
        expect(element.shadowRoot.querySelector('.rr-live-link')).toBeNull();
    });

    // Every action in this editor ends in loadReadout(), which is the *only*
    // thing that moves the UI onto the new status. getReadout is therefore
    // deliberately not cacheable on the Apex side: a client-cached, pre-DML
    // response served to this refetch is exactly how a rep ends up publishing
    // and then seeing neither the Published badge nor the live link until they
    // hard-reload the page. These two cover both directions of that refetch.
    it('shows the Published badge and live link straight after publishing', async () => {
        const approved = {
            id: 'r1',
            status: 'Approved',
            draftContent: '',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: ''
        };
        getReadout
            .mockResolvedValueOnce(approved)
            .mockResolvedValue({ ...approved, status: 'Published', publicLinkToken: 'tok999' });
        publishReadout.mockResolvedValue();

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');
        expect(element.shadowRoot.querySelector('.rr-live-link')).toBeNull();
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Approved');

        Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Publish')
            .click();
        await flushPromises();

        expect(getReadout).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Published');
        expect(element.shadowRoot.querySelector('.rr-live-link').getAttribute('href'))
            .toBe('https://example.my.site.com/gtm/s/readout?token=tok999');
        expect(labelsOf(element)).toContain('Unpublish');
    });

    it('drops the live link straight after unpublishing', async () => {
        const published = {
            id: 'r1',
            status: 'Published',
            draftContent: '',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: 'tok999'
        };
        getReadout
            .mockResolvedValueOnce(published)
            .mockResolvedValue({ ...published, status: 'Approved', publicLinkToken: '' });
        unpublishReadout.mockResolvedValue();

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');
        expect(element.shadowRoot.querySelector('.rr-live-link')).not.toBeNull();

        Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Unpublish')
            .click();
        await flushPromises();

        expect(getReadout).toHaveBeenCalledTimes(2);
        // A revoked link must stop being displayed immediately — a rep must not
        // keep copying a URL that no longer resolves.
        expect(element.shadowRoot.querySelector('.rr-live-link')).toBeNull();
        expect(element.shadowRoot.textContent).not.toContain('tok999');
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Approved');
    });

    // ── return to draft ──────────────────────────────────────────────────────
    //
    // Recovering from a mis-approval. The Apex state machine is the real guard;
    // these cover what the editor is responsible for — offering the action only
    // where the server will accept it, asking before discarding the approval,
    // and not sending anything until the rep says yes.

    function buttonNamed(element, label) {
        return Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === label);
    }

    it('offers Return to draft while Approved', async () => {
        const element = await renderAt('Approved');
        expect(labelsOf(element)).toContain('Return to draft');
    });

    it('offers no Return to draft while Draft', async () => {
        const element = await renderAt('Draft');
        expect(labelsOf(element)).not.toContain('Return to draft');
    });

    it('offers no Return to draft while Published, because the link is live', async () => {
        // The server refuses Published -> Draft outright: the token is in a
        // prospect's inbox and has to be revoked by unpublishing first. Showing
        // the action here would only ever produce an error toast.
        const element = await renderAt('Published', { publicLinkToken: 'tok123' });
        expect(labelsOf(element)).not.toContain('Return to draft');
        expect(labelsOf(element)).toContain('Unpublish');
    });

    it('offers Return to draft again once a published readout has been unpublished', async () => {
        const published = {
            id: 'r1',
            status: 'Published',
            draftContent: '',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: 'tok999'
        };
        getReadout
            .mockResolvedValueOnce(published)
            .mockResolvedValue({ ...published, status: 'Approved', publicLinkToken: '' });
        unpublishReadout.mockResolvedValue();

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');
        expect(labelsOf(element)).not.toContain('Return to draft');

        buttonNamed(element, 'Unpublish').click();
        await flushPromises();

        expect(labelsOf(element)).toContain('Return to draft');
    });

    it('asks before discarding the approval, and sends nothing on the first click', async () => {
        const element = await renderAt('Approved');
        expect(element.shadowRoot.querySelector('.rr-confirm')).toBeNull();

        buttonNamed(element, 'Return to draft').click();
        await flushPromises();

        const confirm = element.shadowRoot.querySelector('.rr-confirm');
        expect(confirm).not.toBeNull();
        expect(confirm.textContent).toContain('discarded');
        // The consequential half of the action has not happened yet.
        expect(returnToDraft).not.toHaveBeenCalled();
    });

    it('cancelling the confirmation leaves the readout approved and calls nothing', async () => {
        const element = await renderAt('Approved');
        buttonNamed(element, 'Return to draft').click();
        await flushPromises();

        buttonNamed(element, 'Cancel').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.rr-confirm')).toBeNull();
        expect(returnToDraft).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Approved');
    });

    it('reverts and reloads into the editable Draft state on confirmation', async () => {
        const approved = {
            id: 'r1',
            status: 'Approved',
            draftContent: '<p>approved copy</p>',
            approvedContent: '<p>approved copy</p>',
            publicLinkToken: ''
        };
        getReadout
            .mockResolvedValueOnce(approved)
            .mockResolvedValue({ ...approved, status: 'Draft' });
        returnToDraft.mockResolvedValue();

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        buttonNamed(element, 'Return to draft').click();
        await flushPromises();
        buttonNamed(element, 'Discard approval').click();
        await flushPromises();

        expect(returnToDraft).toHaveBeenCalledWith({ readoutId: 'r1' });
        expect(getReadout).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Draft');
        // Editable again — that is the whole point of the action.
        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).not.toBeNull();
        expect(labelsOf(element)).toContain('Save Draft');
        expect(element.shadowRoot.querySelector('.rr-confirm')).toBeNull();
    });

    it('leaves the readout approved when the revert is rejected', async () => {
        const element = await renderAt('Approved');
        returnToDraft.mockRejectedValue({
            body: { message: 'This readout is published, so its link is live with the prospect.' }
        });

        buttonNamed(element, 'Return to draft').click();
        await flushPromises();
        buttonNamed(element, 'Discard approval').click();
        await flushPromises();

        expect(returnToDraft).toHaveBeenCalledWith({ readoutId: 'r1' });
        // No optimistic flip to Draft, and no editable field appearing on a
        // readout the server still considers approved.
        expect(element.shadowRoot.querySelector('.status-badge').textContent).toBe('Approved');
        expect(element.shadowRoot.querySelector('lightning-input-rich-text')).toBeNull();
        expect(labelsOf(element)).toContain('Publish');
    });

    it('surfaces a load failure via the error banner, not a silent failure', async () => {
        getReadout.mockRejectedValue({ body: { message: 'nope' } });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('.rr-error').textContent).toContain('nope');
    });
    // ─── GUS ────────────────────────────────────────────────────────────────

    function assistOf(element) {
        return element.shadowRoot.querySelector('c-gtm-readout-assist');
    }

    it('puts GUS on the editor in every state', async () => {
        for (const status of ['Draft', 'Pending Approval', 'Approved', 'Published']) {
            // eslint-disable-next-line no-await-in-loop
            const element = await renderAt(status);
            expect(assistOf(element)).not.toBeNull();
        }
    });

    it('hands GUS the readout, its status and the unsaved editor content', async () => {
        const element = await renderAt('Draft');
        const editor = element.shadowRoot.querySelector('lightning-input-rich-text');
        editor.value = '<p>typed but not saved</p>';
        editor.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const assist = assistOf(element);
        expect(assist.readoutId).toBe('r1');
        expect(assist.status).toBe('Draft');
        // Not the saved value: proposing an edit against the last save would
        // silently revert whatever the rep just typed.
        expect(assist.workingDraft).toBe('<p>typed but not saved</p>');
    });

    it('puts a GUS proposal in the editor without saving it', async () => {
        const element = await renderAt('Draft');
        assistOf(element).dispatchEvent(
            new CustomEvent('draftproposed', { detail: { draftContent: '<p>proposed</p>' } })
        );
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-input-rich-text').value)
            .toBe('<p>proposed</p>');
        expect(saveDraftContent).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.rr-proposal')).not.toBeNull();
    });

    it('clears the unsaved-proposal notice once the draft is saved', async () => {
        const element = await renderAt('Draft');
        assistOf(element).dispatchEvent(
            new CustomEvent('draftproposed', { detail: { draftContent: '<p>proposed</p>' } })
        );
        await flushPromises();

        saveDraftContent.mockResolvedValue();
        buttonNamed(element, 'Save Draft').click();
        await flushPromises();

        expect(saveDraftContent).toHaveBeenCalledWith({
            readoutId: 'r1',
            content: '<p>proposed</p>'
        });
        expect(element.shadowRoot.querySelector('.rr-proposal')).toBeNull();
    });

    it('ignores a proposal that arrives for a readout that is no longer a draft', async () => {
        // Belt and braces: the server refuses this too. Neither check is the
        // only one, because approved content must not change behind the
        // approver's back by any route.
        const element = await renderAt('Approved');
        assistOf(element).dispatchEvent(
            new CustomEvent('draftproposed', { detail: { draftContent: '<p>sneaky</p>' } })
        );
        await flushPromises();

        expect(element.shadowRoot.textContent).not.toContain('sneaky');
        expect(element.shadowRoot.querySelector('.rr-proposal')).toBeNull();
    });

    it('ignores an empty proposal', async () => {
        const element = await renderAt('Draft');
        assistOf(element).dispatchEvent(
            new CustomEvent('draftproposed', { detail: { draftContent: '' } })
        );
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-input-rich-text').value).toBe('<p>draft</p>');
        expect(element.shadowRoot.querySelector('.rr-proposal')).toBeNull();
    });

    // ─── record-page context: getReadoutByRequest resolution ────────────────

    it('calls getReadoutByRequest when recordId is set and no c__readout URL state is present', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>hello</p>',
            approvedContent: '',
            publicLinkToken: ''
        });
        getReadoutByRequest.mockResolvedValue({ id: 'r1' });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        element.recordId = 'a001000000000001AAA';
        document.body.appendChild(element);

        // Emit a page ref with NO c__readout state (record page context).
        CurrentPageReference.emit({ state: {} });
        await flushPromises();

        expect(getReadoutByRequest).toHaveBeenCalledWith({ requestId: 'a001000000000001AAA' });
        expect(getReadout).toHaveBeenCalledWith({ readoutId: 'r1' });
    });

    it('does NOT call getReadoutByRequest when c__readout URL state is present', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>hello</p>',
            approvedContent: '',
            publicLinkToken: ''
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        element.recordId = 'a001000000000001AAA';
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(getReadoutByRequest).not.toHaveBeenCalled();
        expect(getReadout).toHaveBeenCalledWith({ readoutId: 'r1' });
    });

    // ─── hideCaseLink ────────────────────────────────────────────────────────

    it('hides the case link element when hideCaseLink is true', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>hello</p>',
            approvedContent: '',
            publicLinkToken: '',
            caseId: '500000000000001AAA',
            caseNumber: '00001234'
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        element.hideCaseLink = true;
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('.rr-case-link')).toBeNull();
        expect(element.shadowRoot.querySelector('.rr-case')).toBeNull();
    });

    it('shows the case link element when hideCaseLink is false (default)', async () => {
        getReadout.mockResolvedValue({
            id: 'r1',
            status: 'Draft',
            draftContent: '<p>hello</p>',
            approvedContent: '',
            publicLinkToken: '',
            caseId: '500000000000001AAA',
            caseNumber: '00001234'
        });

        const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
        // hideCaseLink defaults to false
        document.body.appendChild(element);
        await setPageRef(element, 'r1');

        expect(element.shadowRoot.querySelector('.rr-case-link')).not.toBeNull();
    });

    // ─── the recipient preview ───────────────────────────────────────────
    //
    // The numbers, band ladders and provenance chips a prospect reads come
    // from Readout_Data__c, not from the prose in the editor. An approver who
    // can only see the prose is approving half a document.

    describe('preview as recipient', () => {
        async function renderAt2(status, extra = {}) {
            getReadout.mockResolvedValue({
                id: 'r1',
                status,
                draftContent: '<h2>Verdict</h2><p>working words</p>',
                approvedContent: '<h2>Verdict</h2><p>approved words</p>',
                dataJson: '{"v":1,"company":"Acme"}',
                approvedDataJson: '{"v":1,"company":"Acme Approved"}',
                publicLinkToken: '',
                ...extra
            });
            const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
            document.body.appendChild(element);
            await setPageRef(element, 'r1');
            return element;
        }

        function previewOf(element) {
            return element.shadowRoot.querySelector('c-gtm-readout-view');
        }

        it('is offered in every state and starts closed, because editing is the default', async () => {
            for (const status of ['Draft', 'Approved', 'Published']) {
                const element = await renderAt2(status);
                expect(labelsOf(element)).toContain('Preview as recipient');
                expect(previewOf(element)).toBeNull();
                document.body.removeChild(element);
                jest.clearAllMocks();
                getReadoutBaseUrl.mockResolvedValue(SITE_HOME);
            }
        });

        it('shows the WORKING draft while editing, so unsaved words appear in place', async () => {
            const element = await renderAt2('Draft');
            element.shadowRoot.querySelector('lightning-input-rich-text').value =
                '<h2>Verdict</h2><p>just typed</p>';
            element.shadowRoot.querySelector('lightning-input-rich-text')
                .dispatchEvent(new CustomEvent('change'));
            await flushPromises();

            const [previewBtn] = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
                .filter((b) => b.label === 'Preview as recipient');
            previewBtn.click();
            await flushPromises();

            const view = previewOf(element);
            expect(view).not.toBeNull();
            expect(view.previewContent).toContain('just typed');
            expect(view.previewMode).toBe(true);
        });

        it('hides the editor while previewing, and brings it back', async () => {
            const element = await renderAt2('Draft');
            const toggle = () => Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
                .filter((b) => b.label.indexOf('Preview') > -1 || b.label.indexOf('Back to') > -1)[0];

            toggle().click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('lightning-input-rich-text')).toBeNull();
            expect(toggle().label).toBe('Back to editing');

            toggle().click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('lightning-input-rich-text')).not.toBeNull();
        });

        it('previews the APPROVED halves once approved — both of them', async () => {
            // What publishes is Approved_Content__c plus Approved_Data__c. A
            // preview that showed the generation-time snapshot could show
            // numbers the published page will not.
            const element = await renderAt2('Approved');
            Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
                .filter((b) => b.label === 'Preview as recipient')[0].click();
            await flushPromises();

            const view = previewOf(element);
            expect(view.previewContent).toContain('approved words');
            expect(view.previewData).toContain('Acme Approved');
        });
    });

    // Self-approval mode: GTM_Readout_Approval_Settings__c.Self_Approval_Enabled__c
    // on, surfaced to this component as ReadoutDetail.selfApprovalEnabled.
    // Manager mode (selfApprovalEnabled false/absent) is covered by every test
    // above and is untouched by this block.
    describe('self-approval mode', () => {
        it('replaces Send for approval with an inline Approve action for the owner', async () => {
            getReadout.mockResolvedValue({
                id: 'r1',
                status: 'Draft',
                draftContent: '<p>hello</p>',
                approvedContent: '',
                publicLinkToken: '',
                selfApprovalEnabled: true,
                isOwner: true
            });

            const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
            document.body.appendChild(element);
            await setPageRef(element, 'r1');

            const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
                .map((b) => b.label);
            expect(labels).toContain('Approve');
            expect(labels).toContain('Save Draft');
            expect(labels).not.toContain('Send for approval');
        });

        it('saves the draft, then self-approves, and reloads', async () => {
            getReadout.mockResolvedValue({
                id: 'r1',
                status: 'Draft',
                draftContent: '<p>hello</p>',
                approvedContent: '',
                publicLinkToken: '',
                selfApprovalEnabled: true,
                isOwner: true
            });
            saveDraftContent.mockResolvedValue();
            selfApproveReadout.mockResolvedValue();

            const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
            document.body.appendChild(element);
            await setPageRef(element, 'r1');

            const approveButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
                .find((b) => b.label === 'Approve');
            approveButton.click();
            await flushPromises();

            // Same reasoning as Send for approval: the working edit has to be
            // saved first, since it becomes Approved_Content__c the instant
            // selfApproveReadout succeeds.
            expect(saveDraftContent).toHaveBeenCalledWith({ readoutId: 'r1', content: '<p>hello</p>' });
            expect(selfApproveReadout).toHaveBeenCalledWith({ readoutId: 'r1' });
            expect(submitForApproval).not.toHaveBeenCalled();
            expect(getReadout).toHaveBeenCalledTimes(2);
        });

        it('does not offer Approve when self-approval is on but the viewer is not the owner', async () => {
            getReadout.mockResolvedValue({
                id: 'r1',
                status: 'Draft',
                draftContent: '<p>hello</p>',
                approvedContent: '',
                publicLinkToken: '',
                selfApprovalEnabled: true,
                isOwner: false
            });

            const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
            document.body.appendChild(element);
            await setPageRef(element, 'r1');

            const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button'))
                .map((b) => b.label);
            expect(labels).not.toContain('Approve');
            // Manager-mode submission is not offered either — the org's routing
            // mode is self-approve, this readout is just not this viewer's own.
            expect(labels).not.toContain('Send for approval');
        });

        it('never mentions email, a notification bell, or Approval History anywhere', async () => {
            getReadout.mockResolvedValue({
                id: 'r1',
                status: 'Pending Approval',
                draftContent: '<p>waiting</p>',
                approvedContent: '',
                publicLinkToken: '',
                approvalState: 'Pending',
                pendingApprover: 'Dana Manager',
                isLocked: true,
                selfApprovalEnabled: false,
                isOwner: true
            });

            const element = createElement('c-gtm-readout-review', { is: GtmReadoutReview });
            document.body.appendChild(element);
            await setPageRef(element, 'r1');

            const text = element.shadowRoot.querySelector('.rr-pending').textContent.toLowerCase();
            expect(text).not.toContain('email');
            expect(text).not.toContain('bell');
            expect(text).not.toContain('approval history');
            expect(text).toContain('dana manager');
        });
    });
});
