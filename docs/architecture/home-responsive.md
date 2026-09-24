# Home pages: responsive behaviour (issue home-responsive)

## Finding
On GTM Offerings Home and GTM Content Home (HomePage flexipages, template
`home:desktopTemplateHeaderThreeColumns`, component in region `top`), below
about 1050px the document scrolls horizontally. Browser diagnosis on gtm-staging
(844px window): Salesforce's standard `div.slds-grid.slds-grid_vertical.homeDesktop`
has `min-width: 1050px` and `flexipage-record-home-template-desktop2` has
`min-width: 968px`, giving 222px of horizontal scroll. Nav tabs overflowing into
"More" is Salesforce's own navigation behaviour and is unchanged. At >=1144px
the nav fits and nothing scrolls.

## Options considered
- (a) A different template without the min-width. UNVERIFIED: no web or docs
  fetch tool was available in this session, so the Salesforce docs (Lightning
  page templates, "Lightning App Builder Page Templates", developer.salesforce.com
  FlexiPage / FlexiPageTemplate metadata reference) could not be cited. Known
  from this repo: `flexipage:defaultAppHomeTemplate` was rejected for a
  `HomePage` (app-home-pages.md), and `home:desktopTemplate` puts `top` in a
  left column only. `flexipage:defaultAppHomeTemplate` is valid for `AppPage`
  (used by GTM_Readouts_Overview), but the app's `standard-home` actionOverride
  expects a HomePage. Switching type/template would change app wiring and was not
  attempted without a browser check.
- (b) Neutralise the min-width via CSS. Rejected: the element is inside Salesforce's
  template shadow/light DOM; there is no supported styling hook, and piercing it
  is fragile.
- (c) CHOSEN: keep the template and flexipages unchanged; make our components
  reflow inside the available width. The Salesforce-imposed 1050px minimum on the
  template wrapper cannot be removed from our metadata, so a horizontal scroll
  below ~1050px viewport width (less nav/sidebar) REMAINS. Stated plainly: this
  change does not eliminate it; it ensures our content does not add further
  overflow and reads correctly when the wrapper is scrolled.

## Changes
CSS only: gtmPageHeader (<=768px actions go full-row; <=480px smaller title, tighter
padding, min-width:0, no fixed widths), gtmOverview (tiles 2-up at <=768, 1-up
at <=480; tighter gaps), gtmContentHome (single column, tighter gaps, controls at
`var(--gtm-control-h, 32px)`). Follow-up if the scroll must go: open a Salesforce
support question or move Home to an AppPage flexipage (defaultAppHomeTemplate,
no min-width known) after proving the standard-home override accepts it on staging.

## How to verify (gtm-staging, browser)
1. Open each Home, set window width to 1144, 1024 and 844 (DevTools device toolbar).
2. 1144: no horizontal scroll, all tabs visible.
3. 1024 / 844: nav collapses to "More"; expected residual horizontal scroll from
   `homeDesktop` min-width 1050px; page header, cards and tiles must fit the
   1050px wrapper and stack (<=768 via device toolbar / <=480).
4. Confirm document.documentElement.scrollWidth - innerWidth equals only the
   Salesforce wrapper overflow (about 1050 - innerWidth), nothing from our components.

## Experiment: candidate templates on gtm-staging (dry-runs, verbatim)
Test pages are throwaway copies of GTM_Offerings_Home hosting `gtmOverview`. The real
app overrides were NOT changed (temporary edits for dry-run only, reverted).

| Template | Page type | Accepted? | Dry-run / deploy id | Min-width behaviour |
|---|---|---|---|---|
| `flexipage:defaultAppHomeTemplate` (page `GTM_Offerings_Home_TestApp`, region `main`) | AppPage | Page: YES. dry-run 0AfgK00000TxuIPSAZ `Status: Succeeded`; deployed 0AfgK00000Txn0rSAB `Status: Succeeded` | see left | unknown until browser check |
| App `GTM_Offerings` standard-home override -> `GTM_Offerings_Home_TestApp` | (override) | NO. 0AfgK00000TxQ5vSAF `Status: Failed`: "0M0gK000008sYJR does not exist or is not a valid override for action Tab[url='/']." | | n/a: an AppPage cannot be the Home override, so (a) via AppPage is dead |
| `home:desktopTemplateThreeColumns` | HomePage | NO. 0AfgK00000TxbKgSAJ `Status: Failed`: "Template home:desktopTemplateThreeColumns doesn't exist." | | n/a |
| `home:desktopTemplate` (page `GTM_Offerings_Home_TestDT`, regions top, bottomLeft, bottomRight, sidebar) | HomePage | YES. dry-run 0AfgK00000TxowDSAR `Status: Succeeded` (first attempt with regions top/right failed: "The 'right' region (type Region) doesn't exist."); deployed 0AfgK00000Txn0rSAB `Status: Succeeded` | | unknown until browser check |
| App `GTM_Offerings` standard-home override -> `GTM_Offerings_Home_TestDT` | (override) | YES. dry-run 0AfgK00000TxcvBSAR `Status: Succeeded` (not deployed) | | rollback = original `GTM_Offerings_Home` (in git) |
| `home:desktopTemplateHeaderThreeColumns` (current pages) | HomePage | YES (already live) | | measured 1050px min-width on `homeDesktop` |

The Content Manager app was not dry-run separately (same override shape); the Offerings
result applies. Test pages on staging (delete afterwards):
`GTM_Offerings_Home_TestApp`, `GTM_Offerings_Home_TestDT`. Note `home:desktopTemplate`
was earlier rejected on layout grounds (top is a left column only).
