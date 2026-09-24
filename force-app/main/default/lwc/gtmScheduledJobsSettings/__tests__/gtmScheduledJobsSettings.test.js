import { createElement } from 'lwc';
import getStatuses from '@salesforce/apex/GtmScheduledJobsController.getStatuses';
import scheduleJob from '@salesforce/apex/GtmScheduledJobsController.scheduleJob';
import GtmScheduledJobsSettings from 'c/gtmScheduledJobsSettings';

jest.mock(
    '@salesforce/apex/GtmScheduledJobsController.getStatuses',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/GtmScheduledJobsController.scheduleJob',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const UNSCHEDULED_STATUSES = [
    {
        jobKey: 'purgeRecordsBatch',
        label: 'GTM Purge Records Batch',
        isScheduled: false,
        nextRunDescription: 'Not scheduled.'
    },
    {
        jobKey: 'assessmentDraftPurge',
        label: 'MA Assessment Draft Purge',
        isScheduled: false,
        nextRunDescription: 'Not scheduled.'
    }
];

describe('c-gtm-scheduled-jobs-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a row for both jobs', async () => {
        getStatuses.mockResolvedValue(UNSCHEDULED_STATUSES);

        const element = createElement('c-gtm-scheduled-jobs-settings', { is: GtmScheduledJobsSettings });
        document.body.appendChild(element);
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('.scheduled-job-row');
        expect(rows).toHaveLength(2);
        expect(element.shadowRoot.textContent).toContain('GTM Purge Records Batch');
        expect(element.shadowRoot.textContent).toContain('Assessment Draft Purge');
        expect(element.shadowRoot.textContent).not.toContain('MA Assessment Draft Purge');
        expect(element.shadowRoot.textContent).toContain('Not scheduled.');
    });

    it('schedules a job independently when its Schedule Now button is clicked', async () => {
        getStatuses.mockResolvedValue(UNSCHEDULED_STATUSES);
        scheduleJob.mockResolvedValue({
            jobKey: 'purgeRecordsBatch',
            label: 'GTM Purge Records Batch',
            isScheduled: true,
            nextRunDescription: 'Next run: Sep 18, 2026 4:00 AM (org time zone).'
        });

        const element = createElement('c-gtm-scheduled-jobs-settings', { is: GtmScheduledJobsSettings });
        document.body.appendChild(element);
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        // First row's button corresponds to purgeRecordsBatch.
        buttons[0].click();
        await flushPromises();

        expect(scheduleJob).toHaveBeenCalledWith('purgeRecordsBatch');
        expect(scheduleJob).toHaveBeenCalledTimes(1);
    });

    it('still passes jobKey assessmentDraftPurge when the relabelled row is scheduled', async () => {
        getStatuses.mockResolvedValue(UNSCHEDULED_STATUSES);
        scheduleJob.mockResolvedValue({ ...UNSCHEDULED_STATUSES[1], isScheduled: true });

        const element = createElement('c-gtm-scheduled-jobs-settings', { is: GtmScheduledJobsSettings });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelectorAll('lightning-button')[1].click();
        await flushPromises();

        expect(scheduleJob).toHaveBeenCalledWith('assessmentDraftPurge');
    });

    it('refreshes status after scheduling, without needing a manual reload', async () => {
        getStatuses.mockResolvedValueOnce(UNSCHEDULED_STATUSES).mockResolvedValueOnce([
            {
                jobKey: 'purgeRecordsBatch',
                label: 'GTM Purge Records Batch',
                isScheduled: true,
                nextRunDescription: 'Next run: Sep 18, 2026 4:00 AM (org time zone).'
            },
            UNSCHEDULED_STATUSES[1]
        ]);
        scheduleJob.mockResolvedValue({
            jobKey: 'purgeRecordsBatch',
            label: 'GTM Purge Records Batch',
            isScheduled: true,
            nextRunDescription: 'Next run: Sep 18, 2026 4:00 AM (org time zone).'
        });

        const element = createElement('c-gtm-scheduled-jobs-settings', { is: GtmScheduledJobsSettings });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelectorAll('lightning-button')[0].click();
        await flushPromises();

        expect(getStatuses).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.textContent).toContain('Next run: Sep 18, 2026 4:00 AM (org time zone).');
    });

    it('surfaces an Apex error on load instead of failing silently', async () => {
        getStatuses.mockRejectedValue({ body: { message: 'boom' } });

        const element = createElement('c-gtm-scheduled-jobs-settings', { is: GtmScheduledJobsSettings });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-text-color_error').textContent).toBe('boom');
    });

    it('surfaces an Apex error on schedule instead of failing silently', async () => {
        getStatuses.mockResolvedValue(UNSCHEDULED_STATUSES);
        scheduleJob.mockRejectedValue({ body: { message: 'nope' } });

        const element = createElement('c-gtm-scheduled-jobs-settings', { is: GtmScheduledJobsSettings });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelectorAll('lightning-button')[0].click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-text-color_error').textContent).toBe('nope');
    });
});
