# TASK SCOPE — ISSUE #18

## 1. Requirements Breakdown

- **Target Objective:** Produce a **written decision plus (if the decision is
  "migrate") a plan** on whether to move authoring and storage of GTM Content
  Manager's page/story content out of the org's custom objects and into
  Contentful, a third-party headless CMS. The user is *not* asking for a
  Contentful integration in this pass — the issue's own acceptance line is "a
  written decision (migrate, don't migrate, or migrate a subset) plus, if
  migrating, a plan ... not a working Contentful integration." So the unit of
  work is one document, and the *only* code-adjacent obligation is that the
  document describes the **real** current system rather than the approximate
  one in the issue body.

  **What exists today, verified against source (not from the issue text):**
  content is three custom objects, not two —
  `GTM_Page_Content__c` (22 custom fields), `GTM_Page_Section__c` (12), and
  **`GTM_Page_Content_Version__c`** (`Change_Summary__c`, `Content__c`,
  `Snapshot__c`, `Version_Number__c`), which the issue omits entirely.
  `Content__c` on the version object is a **Master-Detail** to
  `GTM_Page_Content__c` — `docs/backlog.md`'s D6 rename notes record that this
  master-detail could not be repointed after creation and forced all three
  objects to move in one stage. Any Contentful plan inherits that same
  constraint in reverse: the version history cannot be left behind in the org
  pointing at content rows that no longer exist.

  Content is addressed by a **content address**, not by record Id:
  `offering::template::section::field` (`GtmContentAddress.forField`) and
  `offering::template::section` (`GtmContentAddress.forSection`), with
  `normaliseKey()` collapsing anything non-alphanumeric to a hyphen and
  capping keys at 80 chars. That address is the external Id and the
  section↔field join. It is the actual content model to map onto Contentful
  entries — a 1:1 field-for-field port of the SObject schema would throw it
  away, and the issue is right that the model deserves explicit design.

  Resolution is also **tiered, not flat**: `GtmPageContentReader.getPageContent`
  reads rows matching `Industry_Key__c = :industryKey OR Industry_Key__c = null`,
  orders `Industry_Key__c NULLS LAST`, and lets the first key win — i.e.
  industry-scoped content overrides an offering-wide default for the same
  address. There is a third tier above offering: the literal framework key
  `gtm` (`GtmPageContentController.FRAMEWORK_KEY`), which owns
  `industry-chooser`, `offerings-page`, `faq-bd` and `assistant`. So the shape
  is **framework → offering → industry**, not "one story + N pages + N sections
  per offering" as the issue describes it. Contentful modelling has to carry the
  override/fallback semantics, which is a resolution *algorithm*, not just a
  content type.

  **Draft/publish is a first-class in-org workflow that Contentful would
  replace, not merely host.** `GTM_Page_Content__c` carries `Status__c`,
  `Draft_Value__c`, `Pending_Delete__c`, `Version_Number__c`,
  `Last_Published_Date__c`; `GTM_Page_Section__c` carries `Status__c` and
  `Draft_State__c`. `GtmPageContentReader.getPageLayout` filters sections to
  `Status__c = 'Published'` and carries an explicit source comment that
  `Draft_State__c` is deliberately *not* read, so a pending reorder/hide/delete
  never leaks to a guest. `GtmPageContentController` exposes `saveDrafts`,
  `publishPage`, `discardDrafts`, `savePresentation`. Contentful's own
  draft/published model is close but not identical (no `Pending_Delete__c`
  equivalent, no per-field draft alongside a live value on the same entry), and
  the plan must state which semantics are preserved and which are dropped.

  **Genuine ambiguities — these are NOT for the Developer step to resolve, and
  the deliverable must record them as open gates rather than answering them:**

  1. **Vendor approval / cost (human-only).** Contentful is a new paid SaaS
     dependency and this repo has no external content dependency at read time
     today. Nobody in the agent chain can approve procurement, confirm a budget
     owner, or clear a third-party data-processing review for content that is
     shown to named prospects. The deliverable must carry this as a **blocking
     human decision gate stated up front**, with the technical plan explicitly
     conditional on it — not as a resolved assumption, and not buried in a
     "risks" list at the end.
  2. **The editing-UX fork (product-owner-only).** "`gtmContentManager` becomes
     a thin proxy into Contentful" versus "content editors leave Salesforce
     entirely" is a design fork with no technically-correct answer.
     `gtmContentManager.js` is 1,063 lines wired to **13 imperative Apex
     methods** across `GtmPageContentController` and `GtmPageSectionController`;
     the proxy option means reimplementing all 13 against a Contentful
     Management API, and the replace option means retiring most of that LWC plus
     `gtmContentHome`, `gtmFieldEditor` and the Content Manager app's nav. The
     deliverable must present both with their real costs and name the decision
     as the PO's, not pick one and present it as settled.
  3. **`gtm-dev` is production, and the content is live.** Per `CLAUDE.md` §1
     there is no staging org. `docs/backlog.md`'s D6 stage-3 record gives the
     real volumes at rename time: **206 page-content rows, 39 section rows, 16
     version rows**, and `docs/backlog.md`'s R1 flags **72 migrated industry
     rows "moved but never reviewed"** with the warning that "if the migration
     mangled any copy, every configurator inherits it," while R2 records content
     already destroyed by an earlier automated pass. A one-time export/import is
     therefore a destructive operation on live prospect-facing copy with a known
     prior incident. The deliverable must scope migration as a **separate,
     human-gated, reversible-with-export-first phase**, and this pass must not
     run any export, import or seed script against the org.

  **A load-bearing correction to the issue body.** The issue says GUS "is
  unrelated to page/story content" and puts it out of scope. That is false at
  the code level, and the exclusion cannot stand as written:

  - `GtmAgentTone.cls` resolves GUS's own persona/tone by calling
    `GtmPageContentReader.getPageContent(FRAMEWORK_KEY, 'assistant', null)` —
    GUS's personality is page content, living at `gtm::assistant::assistant::*`
    (which is exactly what `docs/backlog.md` D8 moved it to).
  - `GtmAgentGetConfigState.cls` — a **GUS tool implementation** — queries
    `GTM_Page_Content__c` directly for the framework's `industry-*` rows.
  - `GtmHomeSnapshotController.cls` queries `GTM_Page_Section__c`.

  This matters because `AGENTS.md` §1 states the `GtmAgentToolSurface`
  contract: **no DML *or callouts* inside a tool implementation.** If page
  content moves behind a Contentful HTTP API, then `GtmAgentGetConfigState`'s
  read either becomes a callout inside a tool (a direct contract violation) or
  needs a pre-tool-loop hydration step outside the tool. The deliverable must
  address this collision explicitly. It remains true that the *assessment
  instrument* (`migration-accelerator/`, CMDT) and the *readout drafting*
  surfaces are out of scope — only the "GUS never touches page content" premise
  is wrong.

  **Where the artifact goes — decided, because `CLAUDE.md` §2 makes it a real
  fork.** The Developer step writes **one new file**:
  `docs/agent-artifacts/contentful-content-model-decision.md`. It must **not**
  write into `docs/architecture/adr/`. `CLAUDE.md` §2 defines
  `docs/agent-artifacts/` as ephemeral agent output that "must be explicitly
  promoted to `architecture/` or `specs/` by a human to be deemed
  authoritative," while `docs/architecture/` is declared source of truth by §4
  ("Contract First"). An agent-authored decision whose two central questions are
  a procurement approval and a PO design fork cannot be source of truth. The
  file should nonetheless be **written in ADR shape** (Context / Decision /
  Consequences / Status, matching the eight existing files under
  `docs/architecture/adr/`) and should note that `0009-` is the next free ADR
  number, so a human can promote it verbatim once the two gates clear. This
  mirrors the precedent already in the tree: `per-offering-instrument-plan.md`
  sat in `docs/agent-artifacts/` and was promoted to
  `adr/0007-assessment-instrument-becomes-per-offering.md`.

  **Prior art the decision must engage with, or it is not a real decision.**
  `docs/backlog.md`'s "Done this session" list records **B4: "the retired CMS
  content (records deleted by Don, the 5 dead `managedContentType`
  definitions removed)"** — this project already adopted a CMS (Salesforce CMS
  managed content types), abandoned it, and consolidated onto these custom
  objects. A recommendation to adopt a *third* content home has to say what is
  different this time. Corroborating debris is still in the tree:
  `force-app/main/default/remoteSiteSettings/GTM_Offerings_Site_Public_CMS.remoteSite-meta.xml`
  is still active and its description names `MaStoryContentController` as its
  consumer — a class that **no longer exists** anywhere under
  `force-app/main/default/classes/` (killed by the `Ma`→`Gtm` rename, D6). That
  is a dangling artifact of the last CMS attempt and should be named in the
  deliverable as cleanup either way the decision goes.

- **System Component Impacted:**
  - **Apex (read/write paths, analysed — not modified):**
    `GtmPageContentReader.cls` (354 lines, `without sharing`, the guest read
    path: `getPageContent`, `getPageLayout`, `getOfferingTiles`,
    `getIndustryProfiles`, `getSiteInfo`), `GtmPageContentController.cls`
    (1,181 lines, the authoring write path), `GtmPageSectionController.cls`,
    `GtmContentAddress.cls` (the address contract), plus the incidental
    readers `GtmAgentTone.cls`, `GtmAgentGetConfigState.cls`,
    `GtmHomeSnapshotController.cls`.
  - **LWC (analysed — not modified):** `gtmContentManager` (authoring, 13 Apex
    imports), `gtmContentHome`, `gtmFieldEditor`, and the six consumers of
    `GtmPageContentReader.getPageLayout`: `gtmStory`, `gtmConfigurator`,
    `gtmConfigWizard`, `chooseIndustry`, `offeringChooser`, `gtmFaqPanel`.
  - **Experience Cloud route (the real guest read path, corrected):** the only
    `Live` site is `GTM1` at `gtm/s`, whose only route is `/configurator`
    rendering `c:gtmConfigurator` (`docs/architecture/overview.md`; ADR-0006).
    That component calls `GtmPageContentReader.getPageLayout` via
    `@salesforce/apex/...`, i.e. **Apex-side, not a client-side fetch** — and
    class access is granted to the guest by
    `GTM_Story_Guest.permissionset-meta.xml` (`GtmPageContentReader` only; the
    write-bearing `GtmPageContentController` is granted solely in
    `GTM_Config_Manager`). `GTM_Assessment_Guest` grants **no** page-content
    class at all. The reader's own header comment explains that split: class
    access is per class, so the read-only class exists specifically to keep
    `saveContentRecord`/`deleteContentRecord` off anonymous traffic. Any
    Contentful read path must preserve that "guests get one read-only class,
    never a token and never a write verb" property. `gtmStory` and
    `chooseIndustry` live on `GTM_Accelerator1`, which is
    `DownForMaintenance` — per ADR-0006 the plan must state reachability from
    `Network.Status`, not from the source tree.
  - **Secret storage (new, and unsolved in this repo):** there is **no**
    `force-app/main/default/namedCredentials/` directory. The only outbound-auth
    precedent is an API key in a **Public Hierarchy** custom setting
    (`GTM_Agent_Settings__c.Claude_API_Key__c`, `<visibility>Public</visibility>`)
    plus a `remoteSiteSettings` entry (`Anthropic_API`). A Public custom setting
    is readable from any Apex context including a guest's, so reusing that
    pattern for a Contentful token is a downgrade the plan must reject in favour
    of a Named Credential (a metadata type this repo has never deployed) — and
    it must state that the guest's browser must never receive the token, only
    Apex-rendered content.
  - **YAML instrument:** **not impacted.** `migration-accelerator/` and the
    `GTM_Assessment_*` CMDT pipeline are untouched (issue #16 territory).
  - **This pass's own filesystem footprint:** `TASK_SCOPE.md` (this file) and,
    at the Developer step, `docs/agent-artifacts/contentful-content-model-decision.md`.
    **No `force-app/` change, no `migration-accelerator/` change, no script
    change, no org operation.**

## 2. Code Dependency Checklist

> Every box below is checked to mean **assessed**; the determination follows
> the dash. None is left unevaluated.

- [x] Modifying GUS Tool Surface? — **NO for this pass** (documentation only,
      no class is edited), **but the deliverable must analyse it.** Verified
      against `AGENTS.md` §1: `GtmAgentToolSurface` forbids DML *and callouts*
      inside a tool implementation, and `GtmAgentGetConfigState.cls` (a live
      configurator tool implementation) reads `GTM_Page_Content__c` today with a
      plain SOQL query, while `GtmAgentTone.cls` sources GUS's persona from
      `GtmPageContentReader.getPageContent`. A Contentful backend converts both
      reads into HTTP callouts, which the contract does not permit inside a
      tool. The plan must therefore either (a) hydrate content before
      `runLoop()` and pass it in, or (b) keep an in-org cache/projection that
      tools read with SOQL. Also relevant: `runLoop()`'s 5-round tool cap means
      extra round-trips are not a free workaround. QA should treat any *code*
      change to a GUS tool surface on this branch as out of scope and a fail.
- [x] Altering Custom Metadata? — **NO.** Page/story content is stored in
      custom **objects** (`GTM_Page_Content__c`, `GTM_Page_Section__c`,
      `GTM_Page_Content_Version__c`), not custom metadata types. No
      `force-app/main/default/customMetadata/GTM_Assessment_*` XML is touched
      (`CLAUDE.md` §2's "do not hand-edit" rule is respected by not going near
      it), and no `migration-accelerator/` YAML is authored, because the
      assessment instrument is explicitly out of scope for this issue. The one
      CMDT that page content *reads* is `GTM_Offering__mdt` (via
      `getOfferings()`/`getOfferingTiles()` for the offering list) — the
      deliverable must note that Contentful entries would still need to
      reconcile against `GTM_Offering__mdt.Offering_Key__c` as the authoritative
      offering registry, but it changes nothing there.
- [x] Introducing database fields? — **NO in this pass.** No object, field or
      tab is created, so no permission-set work is due now. The deliverable must
      nonetheless record the future obligation: per `CLAUDE.md` §6 and ADR-0002,
      any field a real implementation adds (e.g. a `Contentful_Entry_Id__c`
      correlation field, or a cache/projection object) is invisible until mapped
      across the five permission sets in `force-app/main/default/permissionsets/`
      — `GTM_Config_Manager`, `GTM_Config_View_All`, `GTM_Assessment_Guest`,
      `GTM_Story_Guest`, `GTM_Platform_Visibility` — with the standing caveat
      that guest sets grant **class access only** and must not be given object
      or field permissions on content read through Apex.

## 3. Plan Acceptance Criteria

- **Success Metric:** QA passes this build when **all** of the following hold:
  1. Exactly one new file exists,
     `docs/agent-artifacts/contentful-content-model-decision.md`, and **zero
     files under `force-app/`, `migration-accelerator/`, `scripts/` or
     `data/` are added, modified or deleted** (`git diff --stat main` proves
     it). The only other permitted diff is this `TASK_SCOPE.md`.
  2. The document states a **clear verdict** — migrate / don't migrate /
     migrate a subset — in its first section, not a menu of options deferred to
     the reader.
  3. It answers all six of the issue's open questions, each grounded in a named
     file or symbol from this repo: guest read path (must name
     `GtmPageContentReader`, `GTM_Story_Guest`, and where a Contentful token
     lives given there is no `namedCredentials/` directory yet); per-offering
     modelling (must use the real **framework `gtm` → offering → industry**
     tiering and the `offering::template::section::field` address, not the
     issue's flatter "one story + N pages + N sections"); editing UX (both
     options costed against `gtmContentManager`'s 13 Apex imports); migration
     (must cite the 206/39/16 row volumes, the `GTM_Page_Content_Version__c`
     master-detail, and reference `scripts/data/migrate-page-content-to-gtm.apex`
     as the in-repo precedent for a content move); caching/outage behaviour
     (must state what a guest sees on `GTM1`'s `/configurator` when Contentful
     is slow or down, versus today's zero-external-dependency read); cost/vendor
     approval.
  4. The two human gates — **procurement/vendor approval** and the
     **editing-UX fork** — plus the **`gtm-dev`-is-production data risk** are
     each recorded as unresolved and owner-attributed, not silently decided by
     the agent.
  5. The GUS/page-content coupling correction is present: `GtmAgentTone` and
     `GtmAgentGetConfigState` are named, and the `GtmAgentToolSurface`
     no-callout collision is addressed with a proposed resolution.
  6. Draft/publish semantics (`Status__c`, `Draft_Value__c`,
     `Draft_State__c`, `Pending_Delete__c`, `publishPage`/`discardDrafts`) are
     mapped onto, or explicitly declared lost against, Contentful's own
     draft/publish model.
  7. The document is marked non-authoritative pending human promotion, names
     `0009-` as the next free ADR slot, and does not itself claim ADR status.
  8. No org operation was performed: no `sf` command that writes, no seed or
     data script run, no `sf community publish`.

- **Target Test Target:** No Apex or LWC behaviour changes, so the runnable
  gate for *this* change is the repo's own static audit, which really does
  inspect root-level and `docs/` markdown:

  1. **`python3 scripts/check-references.py`** — the primary, change-specific
     check. Its section 12 ("ORG-SPECIFIC VALUES AND SECRETS") scans every
     `.md` under `docs/` **and** every `.md` at the repo root, and fails on a
     live-looking API key/token, on a hardcoded Salesforce record Id, and warns
     on an org-specific `my.site.com`/`my.salesforce.com` URL. That is exactly
     the failure mode a Contentful document invites — a pasted space Id, CDA/CMA
     token, or a live site URL. **Baseline on `main`, measured now: exit code
     1, "1 deploy-blocking, 96 needing a manual step," and the single
     deploy-blocking item is pre-existing and unrelated — `CLAUDE.md` contains
     the `gtm-dev` org Id.** QA must diff against that baseline: the pass
     condition is **"still exactly 1 deploy-blocking item, still `CLAUDE.md`,
     and no new entry naming
     `docs/agent-artifacts/contentful-content-model-decision.md` or
     `TASK_SCOPE.md`,"** not a green exit — a green exit is not currently
     achievable on this repo and must not be used as the bar.
  2. **`npm ci && npm test`** (`@salesforce/sfdx-lwc-jest`) — the
     no-regression proof required by `agent-ci-gate.yml`. All **10** existing
     Jest specs must pass unchanged (`gtmAssessmentQuestionnaire`,
     `gtmConfigurator.readout`, `gtmInstrumentAuthor`, `gtmPredicate`,
     `gtmReadoutAssist`, `gtmReadoutReview`, `gtmReadoutDesign`,
     `gtmReadoutView`, `preview`, `gtmReadoutsOverview`). Note for QA: `npm ci`
     is mandatory first — `sfdx-lwc-jest` is not installed in a bare checkout.
     Note for the Architect: **there is no Jest spec for `gtmContentManager`,
     `gtmContentHome` or `gtmStory`** — the content surfaces are untested at the
     LWC layer, which is a real pre-existing gap and one more input to the
     "migrate" decision, but it means no content-specific Jest target can be
     named.
  3. **`python3 scripts/build-instrument.py --check`** — must be **byte-for-byte
     unchanged in outcome**, proving the instrument pipeline was not touched.
     **Baseline on `main`, measured now: exit code 1**, failing only on
     `cannot verify cited path ... no ma-migrator working copy found` for
     `migration-accelerator/gates.yaml` and
     `migration-accelerator/pairs/sfmc_to_mcn.yaml` (no `MA_MIGRATOR_ROOT` set
     in this environment). Pass condition: the identical set of citation errors
     and **no new class of failure**.
  4. **Apex regression target, if the Architect wants a named Apex class run**
     (optional here, since no Apex changes and CI runs only a metadata
     `--dry-run`): `sf apex run test --class-names GtmPageContentReaderTest
     --class-names GtmPageContentControllerTest --class-names
     GtmPageSectionControllerTest` — three real, existing classes (~20+ test
     methods each) covering the exact read/write paths this issue reasons
     about. They must remain **untouched and passing**; a diff to any of them on
     this branch is a scope violation, not a fix.
  5. **Gate self-check:** this branch must satisfy `agent-ci-gate.yml`'s
     "Require TASK_SCOPE.md" step — `TASK_SCOPE.md` present at root, none of
     the two placeholder strings that step greps for (the bracketed issue-id
     token and the bracketed target-objective prompt, both quoted verbatim in
     the workflow) appearing anywhere in this file, and the literal string
     `ISSUE #18` in the header so the branch-name cross-check
     (`agent/issue-18`) passes. Note for the Developer and QA steps: do **not**
     quote those two placeholder strings verbatim in any root-level file — the
     grep is a plain `grep -qE` over the whole of `TASK_SCOPE.md` and does not
     care that the quote was explanatory.
