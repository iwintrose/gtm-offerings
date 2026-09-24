import { LightningElement, track } from 'lwc';
import getSummary from '@salesforce/apex/GtmAnalyticsController.getSummary';
import getOfferingBreakdown from '@salesforce/apex/GtmAnalyticsController.getOfferingBreakdown';
import hasTeamAccess from '@salesforce/apex/GtmAnalyticsTeamController.hasTeamAccess';

const RANGE_PRESETS = {
    '30': 30,
    '90': 90,
    '180': 180
};
const DEFAULT_RANGE = '90';

function isoDate(d) {
    return d.toISOString().slice(0, 10);
}

/**
 * Rep-scoped Analytics tab (issue #110, v1; funnel/tier semantics fixed in
 * #138). KPI row with period-over-period deltas, a weekly engagement trend,
 * the opened -> submitted -> published funnel, readiness-tier mix, a rep
 * follow-up pipeline breakdown, and a by-offering table -- all read from
 * GtmAnalyticsController, which does the actual rollup work.
 *
 * Issue #138: there is no "started" vs. "completed" distinction on the
 * prospect side of an assessment -- GTM_Assessment_Request__c is only ever
 * created, already scored and tiered, once a prospect finishes the
 * questionnaire. What used to be two funnel steps is now one honest step,
 * "Submitted." Status__c (New/Contacted/Scheduled/Completed/No Show) is a
 * REP's own follow-up pipeline stage, shown as its own panel rather than
 * conflated into assessment completion.
 *
 * State lives here (date range + offering) and is passed as imperative-call
 * params rather than @wire, so changing the range filter doesn't need a
 * second reactive-property indirection layer for a single consumer -- same
 * imperative-call convention gtmReadoutsOverview uses.
 *
 * Issue #177: the cross-rep "Team" leaderboard (GtmAnalyticsTeamController,
 * originally its own standalone tab) is a view toggle here, not a second
 * tab -- it's the same Analytics concept at a wider data scope. The toggle
 * itself is hidden from a rep via hasTeamAccess(), a real permission check,
 * rather than shown and left to fail on click.
 */
export default class GtmAnalytics extends LightningElement {
    @track summary = null;
    @track rows = [];
    @track isLoading = true;
    @track loadError = '';
    @track canViewTeam = false;
    @track viewMode = 'my';
    rangeKey = DEFAULT_RANGE;

    get rangeOptions() {
        return [
            { label: 'Last 30 days', value: '30' },
            { label: 'Last 90 days', value: '90' },
            { label: 'Last 180 days', value: '180' }
        ];
    }

    get rangeMeta() {
        const selected = this.rangeOptions.find((o) => o.value === this.rangeKey);
        return selected ? selected.label : '';
    }

    connectedCallback() {
        this.load();
        hasTeamAccess()
            .then((access) => { this.canViewTeam = access === true; })
            .catch(() => { this.canViewTeam = false; });
    }

    handleViewModeChange(event) {
        this.viewMode = event.currentTarget.dataset.mode;
    }

    get isMyViewActive() { return this.viewMode === 'my'; }
    get isTeamViewActive() { return this.viewMode === 'team'; }
    get myViewVariant() { return this.isMyViewActive ? 'brand' : 'neutral'; }
    get teamViewVariant() { return this.isTeamViewActive ? 'brand' : 'neutral'; }

    handleRangeChange(event) {
        this.rangeKey = event.detail.value;
        this.load();
    }

    handleRefresh() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.loadError = '';
        const { rangeStart, rangeEnd } = this.currentRange();

        return Promise.all([
            getSummary({ rangeStart, rangeEnd, offering: null }),
            getOfferingBreakdown({ rangeStart, rangeEnd })
        ])
            .then(([summary, rows]) => {
                this.summary = summary;
                this.rows = (rows || []).map((r, i) => ({
                    key: r.offering || `row-${i}`,
                    offering: r.offering,
                    links: r.links,
                    submitted: r.submitted,
                    avgScore: r.avgScore != null ? r.avgScore.toFixed(0) : '—',
                    published: r.published,
                    topTier: r.topTier || '—',
                    tierClass: this.tierClass(r.topTier)
                }));
            })
            .catch((err) => {
                this.loadError = this.messageFrom(err) || 'Analytics could not be loaded.';
            })
            .finally(() => { this.isLoading = false; });
    }

    currentRange() {
        const days = RANGE_PRESETS[this.rangeKey] || RANGE_PRESETS[DEFAULT_RANGE];
        const end = new Date();
        const start = new Date();
        start.setDate(end.getDate() - (days - 1));
        return { rangeStart: isoDate(start), rangeEnd: isoDate(end) };
    }

    tierClass(tier) {
        const base = 'tier-pill';
        if (tier === 'Fast-Track' || tier === 'Accelerator-Ready') return `${base} tier-pill--high`;
        if (tier === 'Prep Required') return `${base} tier-pill--mid`;
        if (tier === 'Discovery First') return `${base} tier-pill--low`;
        return base;
    }

    messageFrom(err) {
        if (!err) return '';
        if (err.body && err.body.message) return err.body.message;
        return err.message || '';
    }

    // ---------------------------------------------------------- KPI getters

    get hasData() { return !this.isLoading && !this.loadError && this.summary != null; }
    get showEmpty() { return this.hasData && this.summary.linksCreated === 0; }
    get hasContent() { return this.hasData && !this.showEmpty; }

    get linksCreated() { return this.summary ? this.summary.linksCreated : 0; }
    get assessmentsSubmitted() { return this.summary ? this.summary.assessmentsSubmitted : 0; }
    get readoutsPublished() { return this.summary ? this.summary.readoutsPublished : 0; }
    get avgDaysToPublish() {
        return this.summary && this.summary.avgDaysToPublish != null
            ? this.summary.avgDaysToPublish.toFixed(1) : '—';
    }

    get linksDelta() { return this.delta(this.summary?.linksCreated, this.summary?.linksCreatedPrior); }
    get submittedDelta() { return this.delta(this.summary?.assessmentsSubmitted, this.summary?.assessmentsSubmittedPrior); }
    get publishedDelta() { return this.delta(this.summary?.readoutsPublished, this.summary?.readoutsPublishedPrior); }
    get publishSpeedDelta() {
        // Faster (lower) is the "up"/good direction for time-to-publish, unlike the other three KPIs.
        return this.delta(this.summary?.avgDaysToPublishPrior, this.summary?.avgDaysToPublish, true);
    }

    delta(current, prior, invert) {
        if (current == null || prior == null || prior === 0) return null;
        const pct = Math.round(((current - prior) / prior) * 100);
        const up = invert ? pct < 0 : pct >= 0;
        return { pct: Math.abs(pct), up, cssClass: up ? 'delta delta--up' : 'delta delta--down' };
    }

    // -------------------------------------------------------------- funnel

    get funnelSteps() {
        if (!this.summary) return [];
        const opened = this.summary.linksOpened || 0;
        const submitted = this.summary.assessmentsSubmitted || 0;
        const published = this.summary.readoutsPublished || 0;
        const max = Math.max(opened, submitted, 1);
        const widthStyle = (pct) => `width:${pct}%`;
        return [
            { key: 'opened', label: 'Opened', value: opened, pct: widthStyle(Math.round((opened / max) * 100)) },
            { key: 'submitted', label: 'Submitted', value: submitted, pct: widthStyle(Math.round((submitted / max) * 100)) },
            { key: 'published', label: 'Published', value: published, pct: widthStyle(Math.round((published / max) * 100)) }
        ];
    }

    // --------------------------------------------------------- follow-up

    get followUpRows() {
        if (!this.summary) return [];
        const total = (this.summary.followUpStatusCounts || []).reduce((sum, s) => sum + s.count, 0) || 1;
        return (this.summary.followUpStatusCounts || []).map((s) => ({
            key: s.status,
            status: s.status,
            count: s.count,
            pct: `width:${Math.round((s.count / total) * 100)}%`
        }));
    }

    // -------------------------------------------------------------- tiers

    get tierRows() {
        if (!this.summary) return [];
        return this.summary.tierMix.map((t) => ({
            key: t.tier,
            tier: t.tier,
            pct: `width:${t.pct}%`,
            pctLabel: t.pct,
            count: t.count,
            barClass: this.tierBarClass(t.tier)
        }));
    }

    tierBarClass(tier) {
        if (tier === 'Fast-Track' || tier === 'Accelerator-Ready') return 'tier-bar tier-bar--high';
        if (tier === 'Prep Required') return 'tier-bar tier-bar--mid';
        return 'tier-bar tier-bar--low';
    }

    // -------------------------------------------------------------- trend

    get trendPolylines() {
        if (!this.summary || !this.summary.trend || this.summary.trend.length === 0) {
            return null;
        }
        const points = this.summary.trend;
        const maxVal = Math.max(1, ...points.map((p) => Math.max(p.opens, p.submitted)));
        const w = 560;
        const h = 150;
        const stepX = points.length > 1 ? w / (points.length - 1) : 0;
        const toY = (v) => h - 10 - (v / maxVal) * (h - 20);

        const opensXY = points.map((p, i) => [i * stepX, toY(p.opens)]);
        const submittedXY = points.map((p, i) => [i * stepX, toY(p.submitted)]);
        const toPointsAttr = (xy) => xy.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ');

        // A 1-point polyline has zero length and SVG renders it as nothing --
        // real case, not hypothetical: a brand-new offering or a short date
        // range commonly has all its activity in a single calendar week.
        // Markers at every point (not just when there's only one) give the
        // line's endpoints the same care as the line itself.
        const toMarkers = (xy) => xy.map(([cx, cy], i) => ({ key: `p${i}`, cx: cx.toFixed(1), cy: cy.toFixed(1) }));

        return {
            opens: toPointsAttr(opensXY),
            submitted: toPointsAttr(submittedXY),
            opensMarkers: toMarkers(opensXY),
            submittedMarkers: toMarkers(submittedXY)
        };
    }

    get hasTrend() { return this.trendPolylines != null; }
}
