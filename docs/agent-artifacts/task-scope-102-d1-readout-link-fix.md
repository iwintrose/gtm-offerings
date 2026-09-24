# TASK SCOPE — ISSUE #102-d1-readout-link-fix

## 1. Requirements Breakdown

- **Target Objective:** Fix the public readout link a BD rep copies from
  `gtmReadoutReview` (`c/gtmReadoutReview.js`, `publicUrl` getter) so it
  resolves to a real page on the live Experience Cloud site instead of
  404ing. This is deliverable **D1** carved out of GitHub issue #102 (BD
  Workflow Intake epic) — explicitly called out there as a live production
  bug that ships regardless of the epic's ten open stakeholder decisions.
  Scope here is strictly the URL-generation bug; it does not include
  minting/sending the return URL to a prospect, reconciling the return
  experience, or any of #102's other deliverables (A–C, D2–D5, E, F).

- **System Component Impacted:** LWC (`gtmReadoutReview`) + Apex
  (`GtmSavedConfigurationController`) + Experience Cloud site metadata
  (`force-app/main/default/experiences/GTM1/`) + one Jest spec
  (`gtmReadoutReview.test.js`).

### Root cause, verified against current code (issue #102's own text is partially stale — flagged explicitly below)

1. **Confirmed, unambiguous string-building bug.** `gtmReadoutReview.js`
   (`publicUrl` getter, ~line 344–349) builds
   `` `${base}/readout?token=${token}` `` where `base` is `_siteBaseUrl`,
   populated in `connectedCallback()` (~line 137) from
   `GtmSavedConfigurationController.getSiteHomePageUrl()`. That Apex method
   (`cls:543-546`) returns `getSiteBaseUrl() + '/choose-offering'` — a URL
   that already has a page path appended, documented by its own doc-comment
   as being for the "Choose your industry" launcher, not as a bare site
   root. Reusing it as `_siteBaseUrl` produces `<domain>/gtm/s/choose-offering/readout?token=…`
   — a URL with two page segments concatenated, which cannot resolve
   regardless of which site is live. `getSiteBaseUrl()` itself
   (`cls:548-561`, private) already returns the correct bare
   `<site.siteUrl>/s` shape and is not exposed to this caller.

2. **Issue #102's site-identity claim is now stale relative to `main`.**
   Issue #102 states "only `GTM_Accelerator1` has [a `/readout` route]" and
   that `getSiteBaseUrl()` matching `urlPathPrefix == 'gtm'` (GTM1) sends
   the rep to the wrong site. That was true when the issue was written, but
   `docs/backlog.md` (site-decommission closeout, commit `75ab657`, PR #161)
   records that `GTM_Accelerator1`'s entire ExperienceBundle — including its
   `routes/readout.json` and `views/readout.json` — was deleted from source
   outright after `GTM1` reached full content parity. Confirmed by directory
   listing: `force-app/main/default/experiences/` now contains only `GTM1`,
   and `GTM1/routes/` and `GTM1/views/` have no `readout.json` in either.
   **So the "wrong site" framing is obsolete — there is now only one site,
   and it is definitively the live one — but the underlying problem is
   worse than a wrong prefix: the live `GTM1` site has no `/readout` route
   at all.** `docs/runbooks/readout-public-link.md` still describes the
   deleted `GTM_Accelerator1` bundle as the source of truth for what needs
   to be deployed and is itself out of date.

3. **The Jest spec certifies a value production cannot emit.**
   `gtmReadoutReview.test.js` mocks `getSiteHomePageUrl` as
   `https://example.my.site.com/gtmaccelerator/s/` (the old
   `gtmaccelerator` prefix, wrong path shape, and missing `/choose-offering`
   suffix the real Apex method appends) and asserts the built link against
   that same wrong value, so the suite currently green-lights the broken
   behavior and would also green-light a naive fix that still points at the
   nonexistent `GTM_Accelerator1` prefix.

### What this means for scope (read before starting Architect/Developer work)

A pure string-concatenation fix (stop double-appending `/choose-offering`,
call something that returns a bare site base) removes the one clearly
unambiguous defect, but it is **necessary, not sufficient**: `GTM1` has no
`readout` route/view in source at all right now, so even a correctly-built
`<domain>/gtm/s/readout?token=…` URL would still 404 today. Making the link
actually resolve requires adding a new route (`urlPrefix: "readout"`) and
view to `force-app/main/default/experiences/GTM1/`, wrapping
`c:gtmReadoutView` (which already exists, is already exposed for
`lightningCommunity__Page`, and per issue #102 §6 is explicitly **not** to
be rebuilt) — mirroring the shape the old `GTM_Accelerator1/routes/readout.json`
and `GTM_Accelerator1/views/readout.json` used before deletion (a
`forceCommunity:section` region around `c:gtmReadoutView`, `pageAccess:
"UseParent"` so it inherits the site's public/guest access, plus a
`forceCommunity:seoAssistant` `noindex` region — see
`docs/runbooks/readout-public-link.md` for the exact shape those files had).
This route/page addition is standard Experience Builder metadata, requires
no stakeholder decision (the "which site is live" question this used to
depend on — backlog D9/D11 — was independently resolved by the
`GTM_Accelerator1` deletion), and stays inside D1's "fix the 404" objective
rather than pulling in D2–D5 (minting/sending the link, reconciling the
return experience). **This is larger than issue #102's text implies** (it
believed the target route already existed on another site and only the
pointer was wrong); flagging this drift explicitly per BA instructions
rather than silently narrowing scope to match the stale issue text.

No genuine stakeholder-decision ambiguity remains for D1 itself: the live
site is settled (`GTM1`, confirmed by the closeout in `docs/backlog.md`),
and the fix (Apex return-value correction + LWC URL construction + new
route/view metadata + a corrected Jest mock) is fully mechanical. The
Architect should size this as "add one small ExperienceBundle route/view +
one Apex signature fix + one LWC getter fix + one test fix," not as a
one-line string patch.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO** — no GUS/tool-use code touched.
- [x] Altering Custom Metadata? **NO change to `GTM_Assessment_*` metadata
      or any YAML instrument.** The only metadata change is a new
      `ExperienceBundle` route + view under
      `force-app/main/default/experiences/GTM1/` (Experience Builder page
      metadata, not Custom Metadata Type records, and not an
      `instrument/<offering-key>/` YAML file) — CLAUDE.md's
      "update migration-accelerator/ YAML, do not touch XML" rule does not
      apply here; this is standard hand-authored Experience Cloud source
      the same way `GTM1/routes/configurator.json` already is.
- [ ] Introducing database fields? **NO** — no new `GTM_Readout__c` (or
      any object) fields. `Public_Link_Token__c` already exists and is
      unchanged; this task only fixes how its URL is assembled and where
      it resolves.

## 3. Plan Acceptance Criteria

- **Success Metric:** A rep who publishes a `GTM_Readout__c` and copies the
  link shown in `gtmReadoutReview` gets a URL of the shape
  `<site-domain>/gtm/s/readout?token=<Public_Link_Token__c>` (bare site
  base + `/readout` + query param — no `/choose-offering` segment, no
  reference to the deleted `gtmaccelerator` prefix), and that URL, when
  visited as a guest after the Experience Builder draft is published
  (`sf community publish`, per CLAUDE.md §5), renders `c:gtmReadoutView`
  for the correct token instead of 404ing. `getSiteHomePageUrl()`'s
  existing `/choose-offering` behavior must remain unchanged for its
  existing callers (the standalone launcher / "New engagement link"
  button) — this fix must not regress that flow, e.g. by adding a new Apex
  method for the bare base rather than mutating the existing one's return
  value.
- **Target Test Target:**
  - `force-app/main/default/lwc/gtmReadoutReview/__tests__/gtmReadoutReview.test.js`
    — update the `SITE_HOME`/mocked base value and the `publicUrl`
    assertions (~line 69-72, ~line 356) to match the corrected, real URL
    shape rather than the current stale `gtmaccelerator` mock.
  - Manual/QA verification in `gtm-dev` (production, no staging — per
    CLAUDE.md §1) of the published link resolving live, since Experience
    Builder route/page additions only take effect after an explicit
    `sf community publish` and cannot be proven by Jest alone.
