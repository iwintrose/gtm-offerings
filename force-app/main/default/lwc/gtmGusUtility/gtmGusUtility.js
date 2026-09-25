import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';

/**
 * Where GUS may send the rep, and which `state` keys each destination accepts.
 * Follow-up tools extend this map in their own change. State keys must be
 * c__-prefixed (platform rule); values are short strings. Anything not listed
 * here is dropped and no navigation happens. Contract:
 * docs/architecture/gus-utility-bar-host.md section 5.
 */
export const ALLOWED_NAVIGATION = {
    home: [],
    GTM_Pages: ['c__stage'],
    // filter_by_query (issue-10): status, account, contact and date-range
    // params the Assessments tab's filter bar already reads (c__astatus /
    // c__aacct / c__acontact / c__arange). Tier, readout and offering are
    // not in v1's understood vocabulary and stay off this list.
    GTM_Assessments: ['c__astatus', 'c__aacct', 'c__acontact', 'c__arange'],
    GTM_Analytics: []
};

const MAX_STATE_VALUE = 200;
const GREETING =
    'Hi, I am GUS. Ask me how to use GTM Offerings or about the page you are on.';
const PLACEHOLDER = 'Ask GUS a question…';

/**
 * Thin utility-bar host for the app-wide GUS chat. The chat does the work
 * (mode="app" calls GtmAgentProxyController.chatOnApp); this component supplies
 * the page context and performs the one page effect the chat can propose,
 * navigation. No empApi subscription: app mode has no config session, and
 * `agentdelta` is deliberately ignored here.
 */
export default class GtmGusUtility extends NavigationMixin(LightningElement) {
    pageContext = {};

    /**
     * Allow-list only: raw `state`, URLs and free text are never forwarded.
     * An empty/undefined reference yields {} and GUS still works.
     */
    @wire(CurrentPageReference)
    wiredPageReference(ref) {
        const attrs = (ref && ref.attributes) || {};
        const ctx = {};
        if (ref && typeof ref.type === 'string') ctx.pageType = ref.type;
        if (ref && ref.type === 'standard__navItemPage' && typeof attrs.apiName === 'string') {
            ctx.tabApiName = attrs.apiName;
        }
        if (typeof attrs.objectApiName === 'string') ctx.objectApiName = attrs.objectApiName;
        if (typeof attrs.recordId === 'string') ctx.recordId = attrs.recordId;
        this.pageContext = ctx;
    }

    get greeting() {
        return GREETING;
    }

    get placeholder() {
        return PLACEHOLDER;
    }

    handleNewChat() {
        const chat = this.template.querySelector('c-gtm-agent-chat');
        if (chat) chat.reset();
    }

    handleAgentAction(event) {
        const target = this._validatedTarget(event && event.detail);
        if (!target) return;
        // `home` is the standard Home page (app-home-pages.md sec 4); every
        // other key is a custom tab.
        const reference = target.apiName === 'home'
            ? { type: 'standard__namedPage', attributes: { pageName: 'home' } }
            : {
                type: 'standard__navItemPage',
                attributes: { apiName: target.apiName },
                state: target.state
            };
        this[NavigationMixin.Navigate](reference);
    }

    /** Defence in depth: the chat checked the shape, this checks the policy. */
    _validatedTarget(detail) {
        if (!detail || detail.type !== 'navigate' || typeof detail.apiName !== 'string') return null;
        if (!Object.prototype.hasOwnProperty.call(ALLOWED_NAVIGATION, detail.apiName)) return null;
        const permitted = ALLOWED_NAVIGATION[detail.apiName];
        const rawState = detail.state && typeof detail.state === 'object' && !Array.isArray(detail.state)
            ? detail.state : {};
        const state = {};
        for (const key of Object.keys(rawState)) {
            const value = rawState[key];
            if (!key.startsWith('c__') || !permitted.includes(key)) return null;
            if (typeof value !== 'string' || value.length > MAX_STATE_VALUE) return null;
            state[key] = value;
        }
        return { apiName: detail.apiName, state };
    }
}
