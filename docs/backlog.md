# Backlog

The jot pad. One place the outstanding work lives so neither of us is
re-typing it, and so "what did we decide about X" has an answer.

**How this works.** Don brain-dumps freely — that stays easy, and structuring
the dump is Claude's job, not his. Claude splits it into items here, groups
them, and marks each with two things: how much it hurts, and how sure Claude is
what to build. Anything low-certainty waits for a decision rather than being
guessed at. Updated at the end of every working session.

**Certainty is the axis that has been costing us.** Impact tells us what order
to work in; certainty tells us whether to talk first. High impact + low
certainty is the quadrant where this session lost the most time — the framework
lock got built from a one-line item and had to be undone, and the industry
sections were built onto the configurator, moved, restored twice, and finally
deleted.

Legend — **Hurts:** `blocks` a demo · `daily` friction · `polish`
&nbsp;&nbsp;**Sure:** `high` = go and build it · `low` = needs a decision first

---

## Decisions

Answered decisions stay here with their answer, so neither of us re-litigates
them. An answer that contradicts something already built says so.

### Answered

**D1 — Gus.** *Framework persona and tone; per-offering capability.*
One Gus everywhere: same name, same voice, one place to edit him. What differs
per offering is what he can **do** on that offering's pages.

> ⚠️ **This inverts what is built.** The `assistant` section currently sits on
> `migration-accelerator::configurator` and holds name, role, button label,
> greeting and input prompt — persona, at the offering level, which is exactly
> backwards. Rework: move persona to the framework, and replace the
> per-offering section with a *capability* declaration (which fields Gus may
> change on that page) rather than copy. See #21.

**D2 — Feedback visibility.** *BD sees their own; the Content Manager sees all.*
`getFeedbackFor` currently returns everyone's notes to everyone. It gets a
`Submitted_By__c = :UserInfo.getUserId()` filter; `getOpenFeedback` stays
unfiltered, because anyone with the Content Manager is a writer.
Also raised: **the feedback card's padding and margins are unfinished** — text
sits too close to the card edge. Folded in as B5.

### Open

**D3 — ANSWERED: A2.** One public site at `/gtm` hosting the configurator and
nothing else; the offerings list and the story live in Lightning, where the BD
is already authenticated. The industry chooser is redundant as a *page* — the
wizard already asks the same question — but stays as the *authoring surface*
where the industry copy lives. Content home is not the same as a rendered page.

Sequence: story viewer (done) → deploy pages to GTM (done) → **Don publishes
and activates GTM** (done — confirmed Live) → guest permissions, Apex repoint,
rewrite the four links (done) → verify (done at the code/record level;
browser screenshot blocked — see Known and accepted) → **Don deactivates GTM
Accelerator** → reseed with permutations.

> Correction: only *activation* (Inactive → Live, one-time) needed Setup UI.
> Routine publish does not — `sf community publish -n <name>` works fine and
> is now the standard step after any ExperienceBundle metadata deploy. A
> metadata deploy only writes the site's draft; nothing is live until
> published. Learned the hard way when the Home redirect deployed clean but
> the real browser still showed blank until publish ran.

One Don action is left: deactivating GTM Accelerator, then reseeding.

*(superseded)* **D3 — the old framing.** Not yet answered. Offerings page + Industry Chooser are
framework; the Configurator belongs to the offering; all three serve from one
Experience site today. Splitting them is the only route to the URL shape you
wanted, because a Salesforce site prefix is a single path segment and cannot be
`/gtm/maaccelerator/`.

**D4 — Requests vs submissions.** Walked against one real engagement link
instead of more prose — **MUCH Music**, `MA_Saved_Configuration__c`
`a00gK00001JtV7lQAF`, Contact Marcus Rivera. Every row it produced:

- **The request** — exactly one `MA_Assessment_Request__c` row, **AR-0017**:
  Company, Requester Name/Email, `Status__c` (New → Contacted → Scheduled →
  Completed → No Show — a sales pipeline), `Submitted_At__c`, linked to the
  Opportunity/Account/Contact. This is the durable BD record a rep works —
  `GtmStageActionsController` drives the whole proposal flow off its
  `Status__c`.
- **The submission** — one row (`Form Submitted`) inside this link's full
  `MA_Link_Event__c` trail, alongside 3 lighter breadcrumbs (`Page View` x2,
  `Form Opened`). It carries a lookup *forward* to the request it produced
  (`Assessment_Request__c = AR-0017`).

So they were never duplicates of each other or two names for the same
thing: **submissions are analytics/audit-trail entries** (what a visitor
did, and when — page views, form opens, the submit moment, drop-offs),
**requests are the one canonical BD record** a submission produces. A
link can rack up many submission-adjacent events; it produces at most one
request.

**Resolved — no new screen.** Found `lwc/gtmLinkActivity` already fully
built (timeline of `Page View`/`Form Opened`/`Form Submitted`/`Drop-off`,
reads the Request's own `Saved_Configuration__c` lookup, queries that
config's `Link_Events__r` related list) — `js-meta.xml` already scoped to
`MA_Assessment_Request__c` record pages — but never placed on any page
(confirmed via `check-all.sh`'s orphaned-components list and a grep across
every flexipage: nothing referenced it). Retrieved
`Assessment_Request_Record_Page2` into source for the first time (it was
live in the org, untracked — same gap noted during D6), added an
"Activity" sidebar tab wired to it, next to Collaborate. Dry-run + real
deploy clean. A submissions *list* would just be a filtered view of
`MA_Link_Event__c` with no BD-workable content beyond what the request
already has — the actual gap was this one already-built component sitting
unused, not a missing screen. Closes #16.

> **Refinement, same day:** the walkthrough placed the raw event trail on
> the *request* — wrong home. The full "who did what, reading, submitting"
> story belongs to the *link* (it's what was sent to a person; a request
> is one possible outcome of it), matching the existing `gtmLinkSitemap`
> "how far they read" map that already lives on the Engagement Link page.
> Made `gtmLinkActivity` work on both record types and moved its primary
> placement there, next to that map, on an "Activity" tab. Also relabeled
> `MA_Link_Event__c` → **Activity Log** (`AL-{0000}` going forward; API
> name and existing `EVT-` numbers untouched — a label/autonumber-format
> change carries none of the D6 object-rename risk below).

**D5 — Self-service link recovery on the bare `/gtm/s/configurator`.** Not a
decision yet. Today a guest with no `?cfgId=` gets a static "this page needs a
link, reach out to your rep" screen (built and live). You floated something
richer: enter your email + the password your rep gave you, resolve to the
right link, and — you weren't sure — maybe a "resend my password" if it's been
forgotten.

The email + password lookup is straightforward and safe to build: no new abuse
surface, since the password is a credential they already hold. The "email me
my password" piece is a materially different feature — a guest-facing form
that sends email based on typed input is a live enumeration and open-relay
target (type any exec's email, learn whether they have an active link; hammer
the endpoint as free outbound mail) and needs its own security pass before it
exists at all, not a quick add.

> **Claude's proposed default:** build the email + password lookup now
> (v1) — matches an existing MA_Saved_Configuration__c by contact email *and*
> its own password together, one guest Apex method, no email sending. Not
> found and expired both render the same existing "reach out to your Rep"
> screen, exactly as you suggested — no separate wrong-password oracle to
> enumerate against. Park "resend to email" as its own item, flagged for
> `security-review` before it's built, not folded into this one.
>
> Needs a yes before it's built — this is guest-facing and auth-adjacent.

**D6 — `MA_`/`Ma` prefix leaks the single-offering assumption.** Raised again
while granting `MA_Assessment_Guest`: it and the Apex classes it grants
(`MaLinkAuthController`, `MaConfigurationStatusController`,
`MaAssessmentRequestController`) are named for Migration Accelerator
specifically, but the mechanism is framework-level — link auth, password
gating, and request submission work identically for any offering, not just
this one. Same pattern likely holds across most `MA_`-prefixed permission
sets, custom objects/fields, and Apex classes in the org.

**Done.** 36 Apex classes, 13 LWC bundles, 4 permission sets (metadata),
1 flow, 2 genAiPlugins, profiles, layout label, and supporting scripts
renamed `Ma`/`MA_` → `Gtm`/`GTM_`. Sequenced as the plan required: new
permission sets deployed and assigned to every real guest/human user
*before* removing old assignments; new flow deployed Active with the old
one set Obsolete in the same pass to avoid a double-send; old Apex
classes/LWC bundles only destructively removed from the org after both
sites were republished and confirmed live on the new names. Found and
fixed along the way: the org's actual live Assessment Request record page
(`Assessment_Request_Record_Page2`, never tracked in source) still pointed
at the old `maAssessmentDetail` — would have broken for every CRM user;
`chooseIndustry`'s Experience Builder label was still "MA Choose Industry";
two `scripts/data/*.apex` seed scripts still called deleted classes.

**Resolved.** `MA_Config_Manager`, `MA_Story_Guest`, `MA_Assessment_Guest`
refused deletion ("used in an experience") even with zero
`PermissionSetAssignment` rows left. Actual cause, found by querying
`NetworkMemberGroup` directly: all three were still registered as
authenticated-member permission sets on *both* sites (`GTM` and
`GTM Accelerator`) — a leftover from before the D6 rename, unrelated to
`PermissionSetAssignment` or any CMS Workspace. Isiah removed them from
both sites' Administration → Members lists in Setup; destructive deploy
then succeeded cleanly (dry-run and real, 0 errors). Local source files
removed to match. `check-all.sh` dangling-references check: none.

**Phase 2 authorized — full `MA_` → `GTM_` custom object/field rename.**
Confirmed `orgfarm-5c323065da-dev-ed` *is*
production — no separate prod org exists. (Its org Id is recorded in the
deploy log for that run, not repeated here — a Salesforce org Id is
org-specific and does not belong in source.) Full scope run against it: 11
objects/mdt/settings/events, 108 fields, 34 Apex classes, 14 LWC bundles,
2 flows, 6 permission sets, 2 profiles, 8 confirmed hardcoded
API-name-in-string-literal spots a type-reference-only sweep would miss
(incl. the `/event/MA_Config_Update__e` EMP API channel string — misses
there fail silently, no compile error), 287 real records. Only
`MA_Saved_Configuration__c`'s 4 Active rows carry externally-distributed
Ids (`?cfgId=`); everything else is internal-only. Plan: a small legacy-Id
redirect lookup for those 4 rows (Salesforce Ids are permanently bound to
their originating object, so old Ids can never resolve against a new one
directly) lets `MA_Saved_Configuration__c` actually get renamed too,
instead of frozen forever — cheap given only 4 rows. Staged: safest
objects (mdt/setting types) → `Page_Content`/`Page_Section` (internal
CMS, no external exposure) → `Assessment_Request`/`Link_Event`/`Form_Draft`
→ `Saved_Configuration` last (needs the redirect). Regression pass after
each stage, not just at the end.

**Stage 1 — done.** Full backup of all 287 records across the 10
data-bearing objects (`MA_Page_Content__c` needed an explicit field list,
not `FIELDS(ALL)` — that shortcut silently caps at 200 rows and was
truncating its 206), verified against live `COUNT()` per object, zero
query errors. Delivered directly to Isiah as a zip (not committed — it's
unscrubbed real prospect data: MUCH Music/TD Bank/Medtronic/LA Metro
contact names and emails). `MA_Config_Update__e` (platform event) has no
persisted rows — nothing to back up, not a gap.

**Stage 2 — done.** The three safest objects first: `GTM_Offering__mdt`,
`GTM_Assessment_Config__mdt`, `GTM_Agent_Settings__c` (mirroring their `MA_`
originals field-for-field), plus `GTM_Config_Update__e` — an 11th object
that had been missing from the original stage breakdown (a platform event
with zero persisted rows, so it slots in with the other no-data/no-external-
exposure objects rather than needing its own stage). Object/field metadata
for all four deployed clean. Data:

- `GTM_Offering.Migration_Accelerator` — deployed and verified live.
- `GTM_Agent_Settings__c` org defaults — migrated via a one-time Apex
  script (`GTM_Agent_Settings__c.getOrgDefaults()` upserted from the `MA_`
  one) rather than a metadata deploy, specifically so the Claude API key
  value never had to pass through anything I could read or print — verified
  live by field presence, not by value.
- `GTM_Config_Update__e` — no data (platform events don't persist), nothing
  to migrate.
- `GTM_Assessment_Config.Default` — **was blocked, now resolved.** Every
  standard `sf project deploy` attempt against this one customMetadata
  record failed identically with an opaque org-side `UNKNOWN_EXCEPTION`
  (error code `-315522575`) across 8 attempts over two sessions, isolated
  definitively as an org-wide Metadata-API fault (reproduced even on a
  throwaway diagnostic object) rather than anything wrong with our
  metadata. **Worked around** by routing the same record through a
  different platform entry point: an Apex script using
  `Metadata.Operations.enqueueDeployment` instead of the CLI's Metadata API
  deploy path. That succeeded on the first attempt — the record is live,
  verified by direct query field-for-field against the `MA_` original.
  Whatever is broken is specific to the CLI/REST Metadata API deploy
  pipeline, not to CustomMetadata records generally; worth keeping this
  workaround in mind if another record deploy hits the same wall.
- Permission set grants (`GTM_Story_Guest`/`GTM_Assessment_Guest` →
  `customMetadataTypeAccesses` on the new types, old `MA_` grants left in
  place alongside) deployed clean.

Rewired: `GtmAssessmentRequestController`/`GtmAssessmentRequestControllerTest`
(the `GTM_Assessment_Config__mdt`/`GTM_Offering__mdt` lines — its
`GTM_Assessment_Request__c` lines were Stage 4's), `GtmDealNaming`,
`GtmAgentProxyController` (`GTM_Agent_Settings__c`), and
`GtmAgentApplyConfigUpdate`/`gtmAgentBubble.js` (`GTM_Config_Update__e`,
including the empApi channel string literal — a type-reference sweep alone
would have missed it). `GtmPageContentController`/`GtmPageContentReader`
were already rewired in Stage 3 (they touch `GTM_Offering__mdt` too, no
reason to touch twice). Also updated five now-stale comment/description
references to `MA_Offering__mdt.Offering_Key__c` across field metadata and
LWC `js-meta.xml` property descriptions, for accuracy — cosmetic, not
functional. No dedicated test class exists for `GtmAgentProxyController` or
`GtmAgentApplyConfigUpdate` (pre-existing gap, not introduced here); ran a
one-off Apex sanity check instead (`getOrgDefaults()` resolves, `EventBus.publish`
on `GTM_Config_Update__e` succeeds) since regression tests couldn't cover it.
`GtmAssessmentRequestControllerTest` (24) and `GtmDealNamingTest` (4) pass.

**Stage 3 — done.** `MA_Page_Content__c` (206 rows), `MA_Page_Section__c`
(39 rows), and `MA_Page_Content_Version__c` (16 rows, discovered mid-stage —
its `Content__c` is a **Master-Detail** to Page_Content, which can't point
at two object types or be repointed after creation, so it had to move in
the same stage, not later). All three have zero external URL exposure —
purely internal CMS data — so this was a straightforward hard cutover, no
redirect logic needed. Rewired: `GtmPageContentController`,
`GtmPageSectionController`, `GtmPageContentReader`, `GtmAgentGetConfigState`,
`GtmOfferingCreationTest`, `GtmContentAddress`, their test classes, one real
hardcoded LWC literal (`gtmConfigurator.js`'s Setup-list URL builder), and
three dev-tool scripts (`check-live-page-contract.mjs`, `check-page-order.mjs`,
`fix-field-order.mjs`) that would otherwise have started validating stale,
frozen data instead of what the app actually reads. `GtmHomeSnapshotController`
and `GtmAgentGetConfigState` also touch Stage 4/5 objects — only their
Page_Content/Page_Section lines were touched, confirmed by grep before and
after each edit. All 58 tests across the four touched test classes pass.

Hit a **third instance of today's platform-side metadata-propagation lag**,
different shape from the first two: the new fields work fine through Apex
(proven by the passing tests, which query them directly) but the plain REST
Data API — what `sf data query` and `check-all.sh`'s node scripts use —
still returns "No such column" for the same fields well after Apex's own
view of them is current. A split-brain between two Salesforce API surfaces'
metadata caches, not a real defect; `check-all.sh`'s live-contract check is
blocked until that clears, but the application itself is already proven
correct independent of it. Re-run `check-all.sh` before final cutover.

**Stage 4 — done.** `MA_Assessment_Request__c` (3 rows), `MA_Link_Event__c`
(16 rows), `MA_Form_Draft__c` (0 rows). No external URL exposure on any of
the three, so — like Stage 3 — a straightforward hard cutover. All three
objects' own `Saved_Configuration__c` lookups deliberately still point at
the OLD `MA_Saved_Configuration__c` (a plain Lookup, repointable later
without recreating the field, so this is deferred cleanly to Stage 5);
`GTM_Link_Event__c.Assessment_Request__c` was repointed to the NEW
`GTM_Assessment_Request__c` since both migrate together in this stage. Hit
and fixed a real **relationship-name collision**: copied lookup fields kept
their original `relationshipName` values, which collided with the
still-live old objects' relationships to the same shared parents (Account/
Contact/Lead/Opportunity/Engagement Link) — renamed to `GTM_Assessment_Requests`
/`GTM_Link_Events`/`GTM_Form_Drafts`.

Rewired: `GtmAssessmentRequestController`, `GtmLinkEventController`,
`GtmFormDraftController`, `GtmStageActionsController` (missed on the first
pass — caught by a repo-wide grep for the old object names after the
first batch, not by the original file list), `GtmHomeSnapshotController`
(second pass — its Page_Content/Section lines were already done in Stage
3), and all matching test classes. `GtmDealNaming`/`GtmAgentGetConfigState`
left untouched (Stage 2/5 objects only). LWC: `gtmAssessmentDetail.js` (20
schema imports), `gtmStageActions.js`/`gtmOverview.js` (hardcoded record
URLs), and `gtmLinkActivity.js` — the last one needed more than a
find/replace: its `getRelatedListRecords` call reads via the parent
(`MA_Saved_Configuration__c`, still Stage 5) child relationship, and that
relationship's name is now `GTM_Link_Events__r`, not `Link_Events__r`,
because of the collision rename above — missing this would have silently
broken the live Engagement Link activity feed. All 44 tests across the five
touched test classes pass.

Found a real UI gap while rewiring: `GtmAssessmentRequestController` now
inserts new prospect submissions into `GTM_Assessment_Request__c`, but the
only native Lightning Record Page/Tab for this object family
(`Assessment_Request_Record_Page2.flexipage-meta.xml`, the `Assessment
Requests` tab, both still bound to the OLD object) would have made every
new submission invisible to a rep browsing natively. Closed the gap:
cloned a `GTM_Assessment_Request_Record_Page` record page and a
`GTM_Assessment_Request__c` tab, added the tab to the `GTM_Offerings` app
and to `GTM_Platform_Visibility`'s tab settings, and cloned the matching
object/field/tab grants onto the `Standard`/`StandardAul` profiles (these
two hadn't been touched in Stages 2-3 — first time profile-level access
needed cloning, not just permission sets). The OLD record page's two
custom-component facets (`gtmAssessmentDetail`, `gtmLinkActivity`) were
swapped for static `flexipage:richText` notes rather than left in place,
since both components' internals now assume the NEW object's schema and
would error against the 3 legacy records' old-object Ids. **Not verified:**
whether the new record page auto-activated as the org default for
`GTM_Assessment_Request__c` — Salesforce sometimes requires a manual
"Activation" step (Setup → Object Manager → GTM Assessment Request →
Lightning Record Pages) that isn't reliably driven by a metadata-only
deploy. Check this in the org before relying on it.

**Cutover — Stages 2/3/4's old `MA_` schema deleted.** With all three
stages' rewiring regression-tested, retired the 10 old objects those
stages replaced: `MA_Offering__mdt`, `MA_Assessment_Config__mdt`,
`MA_Agent_Settings__c`, `MA_Config_Update__e` (Stage 2); `MA_Page_Content__c`,
`MA_Page_Section__c`, `MA_Page_Content_Version__c` (Stage 3);
`MA_Assessment_Request__c`, `MA_Link_Event__c`, `MA_Form_Draft__c` (Stage 4)
— schema, remaining records, and the two now-orphaned `MA_Assessment_Request__c`/
`MA_Page_Content__c` tabs. `MA_Saved_Configuration__c` (Stage 5) and its
tab are untouched — still the live object.

Found and fixed two real pre-existing gaps while scoping the cutover,
both of which would otherwise have left something broken or dangling:

- `GTM_Config_Manager` — the permission set reps actually use — had
  **never** been granted access to `GTM_Page_Content__c`/`GTM_Page_Section__c`
  at all; Stage 3 cloned grants into every other permission set but missed
  this one. Since it was also the *only* permission set holding grants for
  the old objects, deleting those grants without first adding the GTM_
  equivalents would have left reps with zero object/field access to Page
  Content/Section. Renamed rather than duplicated, since the old objects
  were being deleted in the same pass anyway.
- Three LWC templates (`gtmContentHome`, `gtmOverview`, `gtmContentManager`)
  had user-visible empty-state copy naming `MA_Offering__mdt` directly
  ("Add an MA_Offering__mdt record..."). Harmless while the old object
  still existed; would have been flatly wrong advice once it didn't.
  Updated to `GTM_Offering__mdt`. One comment-only mention in `gtmStory.html`
  fixed for the same reason.

Also removed the old `customMetadataTypeAccesses` grants
(`GTM_Story_Guest`/`GTM_Assessment_Guest`), the old-object `tabSettings`/
`objectPermissions`/`fieldPermissions` blocks across `GTM_Config_Manager`,
`GTM_Platform_Visibility`, `GTM_Assessment_Guest`, `GTM_Story_Guest`,
`Standard`, and `StandardAul` (the two profiles hadn't been touched before
this pass), and the orphaned tab entries from the `GTM_Offerings`/
`GTM_Content_Manager` apps — all deployed and verified deployed clean
before the destructive step, since Salesforce refuses to delete an object
that a permission set/profile still grants access to.

Deletion itself used `sf project delete source`, check-only first (110
components validated, 0 failures) then for real (110 deleted, 0 failures).
Verified independently after the fact — not just trusting the deploy's own
report — via a live `SELECT COUNT()` against each of the 10 old API names,
all returning `INVALID_TYPE`. Full regression pass across all 9 touched
test classes (102 tests) still green post-deletion.

**One known leftover, not blocking anything:** `Assessment_Request_Record_Page2`
(the old Lightning Record Page for the now-deleted `MA_Assessment_Request__c`)
could not be deleted via metadata API — Salesforce refuses to delete an
*active* Lightning page, and deactivating one is a Lightning App Builder UI
action, not something a deploy can do. It's inert now (its `sobjectType`
points at a deleted object) and harmless, but it'll sit as an orphaned file
in both the repo and the org until someone deactivates it in Setup and it's
deleted in a follow-up pass.

**D7 — `gtmPageBrowser` ("Pages" tab) has the wrong shape.** A rep should
not be able to freely browse every offering × every template — that's the
Content Manager's job, not the BD app's. What a rep actually needs, from
inside GTM Offerings:

- **The Story**, for context — already right: Overview's "Read the story"
  button, no change needed.
- **The rep's own view of a Configurator link they already sent** — not a
  blank/generic preview, the *actual* rendering of that specific saved
  configuration, reached by clicking through from the record it belongs
  to (the Assessment Request, or wherever "somewhere within the GTM
  Offering app" ends up being the right anchor) rather than picking
  offering + template from two comboboxes.
- The path there is **Account → Contact → Link** — browsing the CRM
  relationship to find whose link it is, not a page picker.
- Once you're looking at that link, it should be **a view, not the
  editor** — no Customize/Gus chrome, none of what Claude called "the
  editor things on the left two columns." Just what was sent.

**Done.** `frontend-engineer` rebuilt `gtmPageBrowser`'s non-Story path as
`gtmRepLinkFinder` — Account → Contact → Link, backed by
`GtmRepLinkFinderController.getContactsWithLinks` (`with sharing`, not
guest-reachable, 4 passing tests). The orchestrating session finished the
piece `frontend-engineer` deferred back: `@api viewOnly` on
`gtmConfigurator` (gates `showCustomizeButton`, `showAssistant`, the
saved-links bar) and on `gtmStageActions` (gates `showRail` — the whole
action rail hides rather than repurposing client-facing status copy for a
rep's own view), wired `view-only` into `gtmRepLinkFinder`'s rendered
`<c-gtm-configurator>`. Dry-run + real deploy clean, both sites (`GTM` and
the still-live legacy `GTM Accelerator`) published, `check-all.sh` and the
`GtmRepLinkFinderControllerTest` suite green, pushed (`b445e29`, `b3d2804`).

**D8 — Gus's persona and the Configurator's defaults are both stuck inside
a page, when neither really belongs to one.** Two things, same shape:

- **Gus.** D1 already decided this — "one Gus everywhere; what differs per
  offering is what he can do" — but it was never built. Confirmed: the
  `assistant` section (name, role, greeting, fab label, input placeholder)
  still lives at `migration-accelerator::configurator::assistant`, exactly
  where D1 said it wrongly was. It's read by nothing else — `gtmConfigurator`
  is the only reader, hardcoded to that one offering's page — and it's
  invisible on the Framework's own card in the Content Manager home;
  finding it means opening Migration Accelerator's Configurator page
  specifically and knowing to look in its section rail. `git log` confirms
  this was the original design, not a regression — nobody ever built the
  move.
- **Configurator defaults** (the swatch list, default source/target
  platform, generic demo numbers — `defaults::*` under
  `migration-accelerator::configurator`) — same shape: only reachable by
  opening that one page, and `gtmConfigWizard.js` hardcodes
  `OFFERING = 'migration-accelerator'` when reading them, so a second
  offering would silently keep reading the first one's swatches and
  defaults rather than its own.

**Done.** Named the category **Settings** (default call, made to keep
moving rather than block on it — easy to rename later, it's one label).
Mechanism: reused the existing `offeringKey::templateType::sectionKey::
fieldKey` address scheme rather than inventing a parallel one — Gus moved
to `gtm::assistant::assistant::*` (the framework-level address `gtm` was
already a real precedent, used by `industry-chooser`/`offerings-page`/
`faq-bd`; `assistant` is now a real, if page-list-hidden, templateType
registered in `gtmPageLayouts`); the Configurator's defaults stayed under
`<offeringKey>::configurator::defaults::*` (already offering-scoped in
principle) with the actual bug fixed — `gtmConfigWizard.js` no longer
hardcodes `migration-accelerator`, it reads `@api offeringKey` from
`gtmConfigurator`. Both surfaced via a "Settings" link on the Content
Manager home's cards (Framework → Gus, each Offering → its own defaults),
kept out of the pages list and "New page" pickers via `SETTINGS_TEMPLATES`.
Migrated Gus's 5 fields + section to the new address with an idempotent
data script (old rows left in place, a second cleanup pass); code-reviewer
caught a real promise-race in the shared `_cms` merge (one of two
concurrent `getPageLayout` calls could silently wipe the other's fields
depending on resolution order) — fixed before deploy. Dry-run + real
deploy clean, `GTM` site republished, migration re-run confirmed
idempotent, `check-all.sh` green, pushed (`78206c2`, `a4c4ab8`).

**D11 — The live site's booking modal never sends real assessment answers, so a
real submission today scores nothing.** Found while adding orientation copy to
the Instrument Editor and tracing whether source/target platform selection
actually reaches instrument-pack resolution. It does, correctly — server-side
resolution in `GtmAssessmentInstrument.getPack()`/`GtmAssessmentRequestController`
never trusts the client and re-resolves independently, and there's no bug in
that path. The real problem is upstream: `gtmAssessmentQuestionnaire` — the
only component that asks any of the eight scored questions — has its sole
route on `GTM_Accelerator1`, which is `DownForMaintenance` (same site as D9).
The live `GTM1` site's actual booking flow (`gtmConfigBooking`) is a simpler,
different component: it has a hardcoded platform list and sends **no
`answers` array at all**. So a real prospect submitting through the live site
today produces a request with no scored dimensions — `Assessment_Score__c`
and `Assessment_Tier__c` come back meaningless, and the readout that
auto-generates from it has nothing real to narrate. This wasn't caught by
tonight's earlier "the core prospect journey likely still works" read (ADR-0006)
because that read confirmed `gtmConfigurator` doesn't *navigate* anywhere
missing — it didn't check whether the component it *does* render actually
sends what scoring needs. Same underlying class of gap as D9, more
consequential: D9 is a missing page; this is the core product's central value
prop (a real score, a real readout) silently not happening for anyone who
uses the live link today. **Not fixed. Needs a real decision** — promote
`GTM_Accelerator1` to live, port `gtmAssessmentQuestionnaire`'s route onto
`GTM1`, or wire `gtmConfigBooking` to actually collect and send scored
answers — each a different size of change, not this session's to pick
unilaterally.

---

## Ready to build — no decision needed

| # | Item | Hurts | Sure |
|---|---|---|---|
| B2 | **Resend an engagement link** — a BD can set and clear a link password but there's no "send this again" action. Real gap found while answering the guest-account question. | daily | high |
| B3 | **Contact-side analytics** — link events now carry `Contact__c` after identity stitching, but nothing on the Contact record shows it. | daily | high |
| B6 | **Page names in the GTM Content Manager should be editable** by the Content/BA role (confirmed: the role that has access to that app, not a broader audience). Today `TEMPLATE_LABELS` (`Story`, `Configurator`, `Offerings Page`, `FAQ — BD App`, …) is a hardcoded JS constant in `gtmPageLayouts.js` — a Content Manager user can edit page *content* but not what the page is *called* in their own picker. Needs a content-model decision (own field on the page-content record? a new small addressable content key alongside each page's sections, following the same pattern B1 used?) — well-scoped, same shape as B1. **Unblocked** — D6 landed, `gtmPageLayouts.js` is stable again. | daily | high |

---

## Needs Don's eyes before more is built on it

| # | Item | Why |
|---|---|---|
| R1 | **The 72 migrated industry rows** now on the framework's Industry Chooser. Moved but never reviewed. | Everything industry-related now reads from these. If the migration mangled any copy, every configurator inherits it. |
| R2 | **BOA / SC-0012** lost its payload during the `Generated_URL__c` backfill early in the session. Two of eight were recovered from URLs you'd pasted; this one had an empty payload and no field history. Needs re-entering by hand. | Data Claude destroyed. Not recoverable without you. |

---

## Done this session

Chapters as sections · Gus editable per offering · deals + funnel on the
overview · requests/submissions untangled in the data · container-query preview
fix · deal picker default · interaction sitemap + dwell + identity stitching ·
form resume with partial save · page + field order aligned across all five
pages · industries moved to the framework · offering feedback loop (#25) ·
gtmPageBrowser replacing the story viewer · Configurator's external route
deployed to `/gtm` · `getSiteBaseUrl()` repointed onto `urlPathPrefix`
instead of the site label · guest permission-set parity between the GTM and
GTM Accelerator guest users · the four saved links rewritten to `/gtm` ·
bare `/gtm/s/configurator` (no `?cfgId=`) blocked from guests, visible only
to a signed-in Salesforce user · configurable Home redirect (Custom Label,
editable in Setup without a deploy) · two more dead-code removals
(`OfferingSummary.storyUrl`, the unused `getSiteHomePageUrl` import) ·
B5, feedback card padding · B1, the CMS-editable FAQ widget on both apps ·
B4, the retired CMS content (records deleted by Don, the 5 dead
managedContentType definitions removed).

**D9 — The Industry Chooser isn't reachable anywhere live.** Found while
trying to screenshot it: `chooseIndustry` (LWC, `gtm::industry-chooser`
content) only exists as a page/route inside `GTM_Accelerator1` — the
legacy site, now `DownForMaintenance` — confirmed by searching every
`force-app/main/default/experiences/*` bundle. `GTM1` (the live `/gtm`
site) has no `industry.json` view or route at all. The `gtm::industry-chooser`
content itself is fully authored and valid (`check-all.sh`: 9 sections, 79
fields, live contract holds — same as `offerings-page`), and the LWC is a
real, targetable Experience Builder component (D6 already fixed its label
from "MA Choose Industry" → "GTM Choose Industry"), so this isn't a
content gap or a leftover-naming gap — it's a page that was never rebuilt
onto the new site when everything else moved off `GTM Accelerator`. Likely
what "industry listings in the editor does have icons" was pointing at:
content and icons exist and are editable, there's just nowhere live to see
them render. Not started — needs the page/route built onto `GTM1`'s
Experience Builder bundle (copy `GTM_Accelerator1`'s `industry` view/route,
retarget component properties at the live site's own offerings/configurator
URLs, deploy, publish).

**D10 — Every link requires a password now, no exceptions.** Found while
adding the copy-link/regenerate-password controls to the link card
(Pages tab, D7 follow-up): 3 of the 4 real production links (TD Bank,
Medtronic, LA Metro) had no password at all — only MUCH Music did. Two
bugs, both fixed: `gtmConfigWizard`'s "Turn off protection" chip let a
rep explicitly clear it (removed); more importantly,
`_ensureGeneratedPassword()` only ran when a rep reached step 7, but
autosave creates/updates the real record from step 1 onward — a rep who
never reached step 7 got a real record with a blank password regardless
of that chip. `_save()` now calls it unconditionally, before every save.
`GtmSavedConfigurationController.saveConfiguration`'s `clearLinkPassword`
input removed too (no caller sends it, dead code that left the same door
open a different way). Isiah backfilled TD Bank/Medtronic/LA Metro with
generated passwords himself and is notifying each contact directly —
deliberately not done silently, since it changes what a prospect who
already has the link needs to open it.

---

## Known and accepted

- Experience site URL prefixes are immutable and single-segment. Site *display*
  names can only be changed in Setup.
- Guest User licences allow insert and read on a custom object — never update or
  delete. The form-draft design is shaped around this.
- Custom object and custom field **API names** lock permanently after first
  save — no metadata deploy or Setup UI path renames one in place. The only
  route is delete-and-recreate: new object, migrate every record (new record
  Ids), rewire every reference, delete the old one. This is why D6's rename
  stopped at Apex/LWC/permission-set/flow names and explicitly left custom
  object/field API names (`MA_Saved_Configuration__c`, `MA_Assessment_Request__c`,
  `MA_Link_Event__c`, etc.) alone — a hard cutover invalidates every
  already-distributed prospect URL that embeds one of these records' old Id.
  Labels, plural labels, and autonumber display formats carry none of this
  risk and are freely renamable (see D4's Activity Log relabel).
- Screenshotting the live app is real now (Cloudflare Browser Rendering,
  connected this session) — confirmed working for the guest-facing
  Configurator with no auth needed. Internal, authenticated Lightning pages
  need a Salesforce frontdoor.jsp one-time login token, which is single-use
  and short-lived: it has to be generated and handed to the renderer back to
  back, with nothing else running in between, or it's already spent by the
  time the screenshot call fires. Getting this reliable is a sequencing
  problem, not a capability gap.
