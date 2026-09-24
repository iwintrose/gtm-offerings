import { LightningElement, api } from 'lwc';

// Every child tag under the dashboard that shows CMM-derived data. Order here
// doesn't matter — we just iterate and call refresh() on any that expose it.
const CMM_CONSUMER_TAGS = [
    'c-conduit-asset-explorer',
    'c-conduit-audience-view',
    'c-conduit-audit-panel',
    'c-conduit-audit-history',
    'c-conduit-migration-plan',
    'c-conduit-migration-runbook',
    'c-conduit-gap-detail',
    'c-conduit-rationalization',
];

export default class ConduitDashboard extends LightningElement {
    @api recordId;

    // When the audit panel finishes a new Estate Analysis run, ask the audit
    // history sibling to re-fetch so the new row appears without a page reload.
    handleAuditComplete() {
        const history = this.template.querySelector('c-conduit-audit-history');
        if (history?.refresh) history.refresh();
    }

    // When the Data Extract tab uploads a new zip or activates a different
    // version, the active CMM changes and every other tab is looking at stale
    // data. Ask each CMM consumer to re-fetch. Tabs that show FRESH-computed
    // data (Estate, Migration Plan main content) will fully re-render against
    // the new CMM. Tabs that show STORED analysis results (audit findings,
    // gap detail, rationalization) will refresh their wires but still display
    // the last saved run — user must click re-run to regenerate against the
    // new CMM. That's a UX gap worth flagging in the LWCs later.
    handleCmmActivated() {
        for (const tag of CMM_CONSUMER_TAGS) {
            const cmp = this.template.querySelector(tag);
            if (cmp?.refresh) cmp.refresh();
        }
    }
}