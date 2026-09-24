# Header Bar Consistency — Assessment & Build Plan

Status: DRAFT for review — not yet promoted to `docs/architecture/`. Nothing has been built yet.

## Reference pattern (from screenshot)

A white, rounded, bordered card at the top of a page containing:
- icon circle (brand color)
- eyebrow label (small gray text, e.g. "Content")
- bold title (e.g. "GTM Offerings")
- subtitle/meta line (e.g. "Framework · 3 offerings · 11 pages")
- right-aligned action button(s)

## Finding: no shared component exists

`gtmOverview` and `gtmContentHome` each hand-roll this exact pattern independently (duplicated HTML/CSS with different class prefixes — `ov-*` vs `home-*`). `gtmPageBrowser` partially matches (missing meta line and actions). Every other tab uses a different, lighter header or none at all. A code comment in `gtmOverview.css` already flags the two sibling pages as intentionally matching, but there's no enforcing component — so any manual edit to one won't propagate to the other.

**Recommended first step:** extract a shared `c-gtm-page-header` LWC (props: `icon-name`, `eyebrow`, `title`, `meta`; slot for action buttons) and migrate the two existing matches onto it before extending the look to new pages. This removes the duplication and makes every future page consistent by construction.

## Per-page plan

| Page (component) | App | Current state | Proposed change |
|---|---|---|---|
| `gtmOverview` | GTM Offerings — Overview | Full match (hand-rolled) | Migrate onto new shared `c-gtm-page-header`; no visual change |
| `gtmContentHome` | GTM Content Manager — Home | Full match (hand-rolled) | Migrate onto shared component; no visual change |
| `gtmPageBrowser` | GTM Offerings — Pages | Partial (eyebrow/title/icon only; no meta, no actions, has a "back" link instead) | Adopt shared component; add meta line (e.g. page/offering count); keep back-link as a left-of-actions element or fold into eyebrow area |
| `gtmAnalytics` | GTM Offerings — Analytics | No header bar — plain `<h1>` + range dropdown + refresh icon-button | Add header bar: eyebrow "Analytics", title "Your engagement analytics", meta = selected range, actions = range dropdown + Refresh |
| `gtmAssessmentSubmissionView` (list mode) | GTM Offerings — Assessment | No header bar — plain `<h2>` | Add header bar: eyebrow "Assessment", title "Assessment Submissions", meta = submission count, actions = TBD (e.g. Refresh) |
| `gtmReadoutApprovalSettings` | GTM Offerings — Readout Approval Settings | No header bar — plain `<h1>` + description paragraph | Add header bar: eyebrow "Settings", title "Readout Approval Settings"; move description paragraph below the bar as page intro text |
| `gtmContentManager` | GTM Content Manager — Content Manager | No header bar — slim toolbar (brand label + offering picker + breadcrumb) | Add header bar above the existing toolbar: eyebrow "Content", title "Content Manager", meta = current offering/page path; keep picker toolbar below as a secondary row (it's functionally a nav control, not a title) |
| `gtmInstrumentAuthor` | GTM Content Manager — Instrument Editor | No header bar — slim toolbar (brand label + pickers) | Add header bar: eyebrow "Content", title "Instrument Editor", meta = offering + version range; keep picker toolbar below |
| `gtmReadoutsOverview` | GTM Offerings — Assessment Submissions | No header bar — plain `<h1>` + refresh icon-button; **also not wired into `GTM_Offerings.app-meta.xml`'s tab list** | Add header bar: eyebrow "Readouts", title "Assessment Submissions", actions = Refresh. Also add the tab to `GTM_Offerings.app-meta.xml` so it's reachable (confirmed by user: all aspects of the app should be wired in) |

## Explicitly out of scope

- **Experience Cloud / prospect-facing pages** (`gtmReadoutView`, `gtmLinkRecovery`, `gtmAssessmentQuestionnaire`, `gtmStory`) — these intentionally use different, client-branded chrome (confirmed by existing code comments). Leaving as-is.
- **Object-backed native tabs** (Assessment Requests, All Readouts, Engagement Links) — standard Salesforce list-view headers, not custom LWC; not a fit for this component.
- **Sub-widgets embedded within a page** (`gtmFeedbackQueue`, `gtmLinkSitemap`, `gtmRepLinkFinder`) — these aren't page-level entry points; their parent page owns the header.
- `gtmAssessmentDetail` — lives inside a standard record page layout, not an app tab; no page-level header applicable there.

## Sequencing proposal

1. Extract `c-gtm-page-header` shared component; migrate `gtmOverview` + `gtmContentHome` onto it (refactor only, zero visual/behavior change) — establishes the contract other pages build against.
2. Add the header bar to the 6 pages currently missing it, one at a time, confirming meta-line content and action buttons per page with you before building.
3. FLS/permission set pass isn't needed here (UI-only change, no new fields/objects).

Let me know which pages' meta line / action button choices above look right, and whether the sequencing is what you want, before this gets scoped into `TASK_SCOPE.md` and handed to the Architect/Developer/QA chain.
