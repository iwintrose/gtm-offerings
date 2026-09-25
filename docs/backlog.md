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

*Update (ADR-0007, per-offering instrument):* what "fixed" has to include has
changed slightly, though none of the above is invalidated.
`GtmAssessmentInstrument.getPack`, `GtmAssessmentScoring.score`,
`GtmEstateComplexity.score` and `GtmAssessmentQuestions.getQuestionnaire` now
all take a required `offeringKey`, and an offering that resolves to no
instrument scores **nothing** rather than falling back to Migration
Accelerator's eight dimensions — deliberately, since a confident score against
another offering's questions is worse than no score. So a D11 fix that wires
`gtmConfigBooking` to collect and send real answers must also thread an
offering key through. The good news is that it already has one available and
needs no new plumbing: `gtmConfigBooking` is reached from a saved,
offering-tagged engagement link, and `GtmAssessmentRequestController`'s
existing `resolveConfigContext` → `resolveOfferingKey` path already reads
`GTM_Saved_Configuration__c.Offering__c` and stamps
`GTM_Assessment_Request__c.Offering_Key__c` on every submission. This is an
assumption D11's implementer should **verify** rather than rediscover — not
new work D11 inherits. See
`docs/agent-artifacts/per-offering-instrument-plan.md` §6.

*Update (decided, planned, not yet implemented — ADR-0008):* the "needs a
real decision" above is closed. **The live surface adopts the questionnaire,
inside `gtmConfigurator`, on the existing `/configurator` route.**
`gtmConfigBooking` is retired; no route moves, no `Network.Status` changes,
`GTM_Accelerator1` stays down. Git history settles it: `dc4ad5d`'s own
commit message ("The long form was never going to be filled in. This is the
same instrument in digestible steps") shows `gtmAssessmentQuestionnaire` was
built as the **replacement** for the booking modal's long "rich assessment"
form (`552dfb1`) — the swap on the live surface was simply never done. The
other two options were rejected for a concrete reason, not a size one: both
put the questionnaire on a standalone page, whose `savedRecordId` /
`submissionToken` / `offeringKey` are `@api` properties absent from its
`targetConfigs` and unreachable from any URL param, so a submission from
there resolves an empty `ConfigContext` — no Opportunity, no Account, no rep
attribution, no `Link_Password__c` gate, and `resolveOfferingKey` falling to
the hardcoded default instead of reading the link's `Offering__c`. That
trades "scores nothing" for "scores something, attributed to nobody, against
a guessed offering," which ADR-0007's hard boundary already forbids.

Two things the same investigation found, both of which the fix has to carry:
the **resubmit guard** is degraded rather than lost — the durable half
(`closeDraft` appending a terminal `GTM_Form_Draft__c` row with
`Submitted_Request__c`, refused by `GtmAssessmentDraftController.
latestOpenRowFor`) is intact but only revokes a *resume link*, and
`gtmConfigBooking` never sends a `draftToken` so it never fires; the live
path has only `sessionStorage`, `gtmConfigBooking.handleReopen()` is an
unguarded re-open, and `submitRequest` has no duplicate check at all. And
the **button flip** (`hasSubmittedAssessment` → disabled "Your assessment is
in review" → "View your assessment", plus the closing-card flip) is present
and live — but its regression test,
`lwc/maConfigurator/__tests__/maConfigurator.readout.test.js` (`c8945b8`,
extended `b1e2e80`), was dropped when `a2fc262` ported the state machine
into this branch, so it is unprotected today. Restoring it is phase 1.

Full plan, file-by-file plus QA protocol:
`docs/agent-artifacts/d11-resolution-plan.md`. Decision record:
`docs/architecture/adr/0008-the-guest-assessment-is-hosted-by-the-engagement-link-not-by-a-standalone-route.md`.

***RESOLVED — implemented and unit-tested on `main`*** *(ADR-0008, all 7
phases of `docs/agent-artifacts/d11-resolution-plan.md`; independently
re-verified file-by-file against the current codebase for issue #7, see
`docs/agent-artifacts/task-scope-7.md`).* The `/configurator` overlay now
renders `gtmAssessmentQuestionnaire` instead of `gtmConfigBooking`, so a real
prospect submitting through the live engagement link answers the eight
scored questions, the six complexity questions and the pair's supplements,
and the request comes back with real `Section_Scores__c`. `gtmConfigBooking`
is deleted. Zero files under `force-app/main/default/experiences/` changed;
`GTM` is still `Live` and `GTM_Accelerator1` is still `DownForMaintenance`,
both unchanged. **Correction to an earlier draft of this note:** this had
briefly been logged here as "deployed to `gtm-prod`" — that was premature.
Per this repo's promotion flow (worktree → QA validate-only against
`gtm-staging` → merge → deploy `main` to `gtm-staging` for owner review →
`gtm-prod` only on the owner's explicit go-ahead), no agent runs a real
deploy, and there is no record of the owner's go-ahead for this change. The
accurate status is: implemented and unit-tested on `main`
(`gtmConfigurator.readout.test.js` + `gtmAssessmentQuestionnaire` suites, 71
passed / 1 skipped; `check-references.py` clean), **not yet deployed to
`gtm-staging` or `gtm-prod`**, and — critically — the plan's own "QA
verification protocol" section (real anonymous submission scoring, the
resubmit guard blocked all four ways, the button state machine walked live)
has not been run by anyone before issue #7. It is being executed live, for
the first time, as part of issue #7's QA step — not re-confirming a prior
validation.

What landed beyond the swap itself, each because leaving it out would have
turned a fix into a different bug:

- the recipient state-machine test lost in the `MA_`→`GTM_` port is restored
  (`lwc/gtmConfigurator/__tests__/gtmConfigurator.readout.test.js`); all eight
  recovered assertions passed against unmodified `gtmConfigurator`, so the port
  dropped the test and not the behaviour;
- the client now reads the **link's** `Offering__c` (`effectiveOfferingKey`)
  rather than the Experience Builder page property, which could disagree with
  what the server scores against and produce a confident-looking score that
  resolved no dimension keys at all;
- the eleven BD-context fields the readout depends on moved into the
  questionnaire as one optional, chunked, skippable step, with a test asserting
  no BD key ever reaches `answers` / `complexityAnswers` / `supplementAnswers`;
- **one submitted assessment per engagement link** is now enforced server-side
  in `submitRequest`, before any DML, with a guest-safe boolean mirror
  (`GtmConfigurationStatusController.hasSubmittedAssessment`) so the submitted
  state survives a new tab, a second device or a private window rather than
  living only in `sessionStorage`;
- the calendar CTA survives the retirement; the unguarded "Re-open the request"
  path does not.

Two things found while implementing, both fixed here and neither in the plan:

1. `GTM_Assessment_Config.Default.md-meta.xml` carried an explicit
   `<value xsi:nil="true"/>` for `Resume_Link_Base_URL__c` directly beneath a
   comment telling operators to set that value in the org. A custom-metadata
   deploy writes the fields it lists, so every `./scripts/deploy.sh` silently
   re-blanked it and resume emails stopped going out with no error anywhere.
   The field is now **absent** from the file rather than nil; verified against
   `gtm-prod` that a deploy with it omitted leaves the org's value intact.
   `Resume_Link_Base_URL__c` is set to
   `https://orgfarm-5c323065da-dev-ed.develop.my.site.com/gtm/s/configurator`.
2. `npm test` was collecting and running suites out of `.claude/worktrees/`,
   so an abandoned agent checkout's failures were reported as failures of HEAD.
   Jest now ignores that gitignored tree.

Still open, deliberately, and named here so it is not lost:
`GtmFormDraftController` and the existing `Draft_Type__c = 'Booking'` rows are
untouched. The controller is still granted in `GTM_Story_Guest` and the rows
are prospect data; it is now unused **by the configurator**, and retiring that
path is a separate decision (plan open call 2).

**D12 — Industry Chooser's generic "Add section" path is now closed, and there
is no purpose-built replacement.** Landed while implementing the Content
Manager IA plan (`docs/agent-artifacts/content-manager-ia-plan.md` §3.5):
`gtmPageLayouts.js`'s `TEMPLATE_LAYOUTS['industry-chooser']` is now `[]`, so
the generic "Add section" modal on that page (any heading text, any layout,
becomes the industry's `Section_Key__c` with none of a real "Add industry"
form's validation — duplicate-name check, a real key rather than a slugified
heading) is closed off, per the PO's own "I can click in, I can add — should
not be able to." That generic modal was, until this change, the *only* way a
new industry got created anywhere in the app. Existing `industry-tile`
sections are untouched — still fully renameable, reorderable, hideable and
deletable — only *creation* is blocked. **Not urgent** while Migration
Accelerator is the only offering in the org (no second industry has needed
adding), but this becomes a real, blocking gap the moment one does. Needs a
purpose-built "Add industry" flow before then: validated key, a duplicate
check against existing industries, and a seeded field set matching
`industry-tile`'s layout — not a re-opening of the generic modal.

**D13 — Per-offering "look and feel" (theming) — deferred, not decided
against.** Raised in the same IA plan (§5): a content author cannot change
the base visual system (`gtmStory.css`/`gtmConfigurator.css` — ~150-200 raw
colour/`var()` declarations each, shared by every offering that renders
through them) per offering today. The two levers that *do* exist —
`Css_Class__c`/`Inline_Style__c`/`Html_Id__c` on `GTM_Page_Content__c`
(per-field, already offering-scoped) and `swatches` under
`offering-defaults` (the rep's link-wizard colour choices, already
offering-scoped) — cover the specific "edit the accelerator one we've built
so far" case today, without waiting on anything below. **Deliberately not
built this pass:** a real per-offering theme/token layer is a cross-cutting
CSS architecture change to the two largest, most heavily-styled components in
the app — categorically bigger than an IA cleanup, and speculative while
Migration Accelerator is the only offering built out (nothing to validate a
theme system against yet). **The trigger, so this isn't silently dropped:**
build it the moment a *second* offering is being onboarded with a genuinely
different visual identity from Migration Accelerator's. The seam is already
known — CSS custom properties at the top of both stylesheets, sourced from a
new json field beside `swatches` in the customizer-settings surface (see
D8/§1 above), applied per-offering the same way `Inline_Style__c` already is.

**D16 — FAQ items editor's "Add item" lock is UI-only; no server-side
backstop.** Flagged in the same IA plan (`docs/agent-artifacts/content-manager-ia-plan.md`
§3.4): `gtmFieldEditor.js` (~lines 134-136) gates the "+ Add item" button on
`itemsLocked`, computed from `LOCKED_JSON_ITEMS` (`gtmPageLayouts.js` —
`faq::items`), so a user working through the Content Manager UI cannot add a
new FAQ array item. Nothing on the save path (`GtmPageContentController`'s
`saveDrafts` or equivalent) re-checks that same lock — a client bypassing the
UI (direct Apex/API call, or any other tooling that writes a `Page_Content__c`
JSON payload) can add a FAQ item the UI would have refused. **Known, accepted
gap, not urgent:** the same trust boundary already applies to every other
JSON-array field this editor manages, no exploit path exists for a guest/
prospect user (this editor is Content Manager-only, gated by the
`GTM_Content_Manager`/`GTM_Content_Admin` permission sets), and closing it
would mean duplicating the lock's validation logic server-side for a single
field. Revisit if `LOCKED_JSON_ITEMS` grows beyond this one entry, or if a
non-Content-Manager surface ever gets write access to the same field.

---

**D15 — `GtmAgentProxyControllerReadoutTest.readoutSurfaceExecuteToolIssuesNoCallout`
was asserting governor limits after `Test.stopTest()` (test-authoring bug, not
a production contract violation).** Originally logged by QA (2026-09-13) as a
suspected zero-DML contract violation in `GtmReadoutAgentSurface.executeTool`,
found while verifying an unrelated PR (`gtmRepLinkFinder` Miller-columns
layout, #132) via a full `sf apex run test` against `gtm-prod`. Root-caused by
Architect/Developer on issue-134: `executeTool`'s `get_readout_context` path
is zero-DML/zero-callout, exactly as required by AGENTS.md §1 — no production
code change was needed. The test itself was asserting
`Limits.getCallouts()`/`Limits.getDmlStatements()` *after* `Test.stopTest()`,
which closes the isolated inner governor-limit context; the assertions were
reading the outer/cumulative transaction counters, which wrongly included
`seedReadout()`'s 2 setup-phase `insert`s that ran before `Test.startTest()`.
Fixed by moving both assertions to run immediately after `executeTool()`
returns and before `Test.stopTest()`. See issue #134.

---

## Ready to build — no decision needed

| # | Item | Hurts | Sure |
|---|---|---|---|
| B2 | **Resend an engagement link** — a BD can set and clear a link password but there's no "send this again" action. Real gap found while answering the guest-account question. | daily | high |
| B3 | **Contact-side analytics** — link events now carry `Contact__c` after identity stitching, but nothing on the Contact record shows it. | daily | high |
| B6 | **Page names in the GTM Content Manager should be editable** by the Content/BA role (confirmed: the role that has access to that app, not a broader audience). Today `TEMPLATE_LABELS` (`Story`, `Configurator`, `Offerings Page`, `FAQ — BD App`, …) is a hardcoded JS constant in `gtmPageLayouts.js` — a Content Manager user can edit page *content* but not what the page is *called* in their own picker. Needs a content-model decision (own field on the page-content record? a new small addressable content key alongside each page's sections, following the same pattern B1 used?) — well-scoped, same shape as B1. **Unblocked** — D6 landed, `gtmPageLayouts.js` is stable again. | daily | high |
| B7 | ~~Dead CMS debris left over from the retired Contentful evaluation.~~ **Done — PR #122, merged.** | rare | high |
| B8 | ~~`GtmAgentTone.clause()` hoist.~~ **Done — PR #124, merged.** | rare | high |
| B15 | **Remaining Migration-Accelerator-flavored display fallbacks**, deliberately deferred out of the B11/B12 hardcoded-defaults cleanup since they're cosmetic fallbacks (shown only when CMS content is missing for an offering), not provisioning-time defaults that misroute data: (1) `gtmStory.js`'s `DEFAULTS`/`SECTION_FALLBACKS`/`DEFAULT_SECTIONS` constants — MA-flavored placeholder content/sections; (2) `gtmConfigWizard.js`'s S/M/L numeric size presets — MA's historical defaults; (3) `gtmReadoutView.html`'s "MIGRATION ACCELERATOR" badge, only reachable post-published-readout. None of these block adding a new offering — B11's routing fix and B12's unconfigured-notice gating already cover the paths that matter — but the user has been explicit ("we really don't want migration accelerator hard-coded anywhere") that these should eventually go too. | rare | medium |
| B16 | **Promote (or formally retire) `docs/agent-artifacts/contentful-content-model-decision.md`.** Kept in place (not archived with its siblings in the B7-adjacent agent-artifacts cleanup) because it contains unique analysis — a content-address/resolution-tier model, draft/publish semantics, a GUS callout-budget hazard — not captured elsewhere, and its original conclusion was "do not migrate to Contentful" — **superseded 2026-09-23 by §9 of that same doc**, which reverses the verdict under a narrower authoring-only scope (Contentful replaces `gtmContentManager` as the authoring surface only; guest/GUS reads stay on the live `GTM_Page_Content__c`/`GTM_Page_Section__c`/`GTM_Page_Content_Version__c` model via `GtmPageContentReader`, unchanged). Content-model mapping, draft/publish parity, sync mechanism, and the proxy-UI-vs-editors-in-Contentful fork are still open — see §9.3. Per `docs/agent-artifacts/`'s own rule (ephemeral until promoted by a human), this should become a real ADR (next free slot after 0009) or be explicitly marked historical — it's been sitting unpromoted since the original bloat audit surfaced it. | rare | medium |
| B17 | **PR #166** (`agent/issue-assessment-list-row-navigation`, "make Name column clickable to open submission" on `gtmAssessmentSubmissionView`) — CI gate passed, last commit 2026-09-14, no worktree currently provisioned for it (orphaned, not actively being worked). Small, low-risk fix; just needs human review and merge. | daily | high |

---

## Open PRs — status check (2026-09-14)

Snapshot taken at the end of this session so nothing dangles unnoticed:

- **#179** `agent/issue-gtm-readout-workspace` — CI gate passing but `mergeStateStatus: DIRTY` / `mergeable: CONFLICTING` (needs a rebase before merge). Has an active worktree (`worktrees/issue-gtm-readout-workspace-bugfix`) and its most recent commit is from today — treat as in-progress elsewhere, not abandoned.
- **#169** `agent/issue-settings-units-2-3`, "Claude / GUS settings section (Unit 2)" — implements Unit 2 of ADR-0010 (see `docs/architecture/adr/0010-gtm-offerings-settings-tab-is-one-tab-with-sections.md`, promoted this session). CI gate passing. Has an active worktree (`worktrees/issue-settings-units-2-3`) — in-progress, not abandoned. Unit 3 (notifications) per that ADR is explicitly blocked on a human answering the New-Assessment-Request auto-close trigger-moment question before it can even be scoped.
- **#166** — see B17 above; this is the one PR of the three with no active worktree, logged so it doesn't get lost.

---

## Needs Don's eyes before more is built on it

| # | Item | Why |
|---|---|---|
| R1 | **The 72 migrated industry rows** now on the framework's Industry Chooser. Moved but never reviewed. | Everything industry-related now reads from these. If the migration mangled any copy, every configurator inherits it. |
| R2 | **BOA / SC-0012** lost its payload during the `Generated_URL__c` backfill early in the session. Two of eight were recovered from URLs you'd pasted; this one had an empty payload and no field history. Needs re-entering by hand. | Data Claude destroyed. Not recoverable without you. |

---

## Guided Setup in the app (2026-09-20)

Post-install setup now lives in Settings > Setup (ADR-0010 section 0), a derive-only checklist that stores nothing and seeds no content. Install and fresh-org runbooks shrink to "open Setup"; `deploy-fresh-org.sh` closing message points there; API keys stay optional. Plan: `docs/architecture/guided-setup-implementation-plan.md`; contract: `docs/architecture/guided-setup.md` (deltas in its section 0). Remaining: QA browser pass on gtm-staging records spike outcomes in guided-setup.md section 10. Site publish and the `GTM_Guest` assignment stay human steps (v1).

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

**D14 — The Instrument Editor still previews Migration Accelerator's band
ladder for an offering that has no instrument.** The one residual from QA
round 1 on ADR-0007 deliberately left out of that round's fix list. Three
sibling leaks were closed (`Source__c` now resolves through the same
GTM_Offering__mdt → GTM_Page_Content__c → GTM_Page_Section__c tiers
`getOfferings()` uses; `GtmAssessmentScoring.frameMaxTotal()` and the new
`GtmEstateComplexity.maxTotalFor()` return `null` rather than 32/18 for an
offering the compiled constants don't apply to; `getQuestionnaire()` derives
both maxima per offering). This fourth one is a different site and was not in
the endorsed fix list: `GtmAssessmentInstrument.getFrame()` takes its bands
from `GtmAssessmentScoring.bands(offeringKey)`, whose no-frame-record
fail-open hands back Migration Accelerator's four-band ladder. Verified still
present against live `gtm-prod` after the round-1 fixes:

```
CHECK6 [migration-accelerator] slotCount=8 maxTotal=32 bands=[Discovery First 8-14]…[Fast-Track 27-32]
CHECK6 [my-test-offering]      slotCount=0 maxTotal=32 bands=[Discovery First 8-14]…[Fast-Track 27-32]
CHECK6 [data-cloud-accelorator] slotCount=0 maxTotal=32 bands=[Discovery First 8-14]…[Fast-Track 27-32]
```

So an author opening a brand-new offering in the Instrument Editor is shown
another offering's band edges next to a slot count of 0, as if they were
theirs. Lower stakes than the three that were fixed — this is an authoring
preview, not a persisted field or a guest endpoint, and nothing scores off it
— but it is the same borrowed-instrument shape, and the fail-open that
produces it is deliberate (a missing frame record is the path every
Migration Accelerator assessment takes today), so closing it means deciding
what an offering with no frame *should* preview rather than just removing the
fallback. Named here rather than fixed silently.

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

***RESOLVED — content parity, and the decommission effort is now CLOSED
(issue-TicketB-closeout).*** `GTM1` reached full content parity with what
`GTM_Accelerator1` used to carry, closing the original gap this item
tracked. That surfaced the standing question of what to do with
`GTM_Accelerator1` itself, so this session ran that down to ground instead
of leaving it open:

- A real `--dry-run` deploy against `gtm-prod` confirmed Salesforce has no
  deploy-pipeline mechanism to delete an Experience Cloud site at all — the
  platform's own error is explicit: *"You can't delete an Experience Cloud
  site, but you can deactivate it through the Administration settings in
  Experience Workspaces."* This is a Salesforce platform limitation, not a
  gap in this repo's scripts.
- `Network.Status` has exactly three values
  (`UnderConstruction`/`Live`/`DownForMaintenance`) and no further
  "inactive" or "deleted" state exists beyond `DownForMaintenance` — that
  is the platform's permanent maximum-inactive state for a site nobody
  wants reachable again.
- Two sites were found `DownForMaintenance` in `gtm-prod`: `GTM_Accelerator1`
  (`0DBgK000001qLFtWAM`, the bundle this repo tracked) and a second,
  org-only site (`0DBgK000001qFVRWA2`, site prefix `gtmframework`) that
  **never had a corresponding bundle in this repo's source tree** — it was
  never captured by `force-app/main/default/experiences/`, so its absence
  from source here is expected, not a gap to backfill. Both were renamed in
  `gtm-prod` with a `ZZ DELETE -` prefix this session, for visibility in the
  Setup UI as permanently retired; both remain `DownForMaintenance`.
- Because the site can never be promoted back to a reachable state (max
  org-side state is permanent `DownForMaintenance`) and `GTM1` already has
  full content parity, the `GTM_Accelerator1` ExperienceBundle and its
  `.site-meta.xml` were deleted outright from source
  (issue-TicketB-closeout) rather than retained for a rollback value that
  redeploying could never actually realize — a redeployed dark site is
  still unreachable by any guest user. The dead hardcoded CTA in
  `gtmStory.js`/`gtmStory.html` pointing at `GTM_Accelerator1`'s URL was
  removed in the same pass. `scripts/check-references.py` reports 0
  deploy-blocking references after the deletion.

No further action is pending on this item. The site-decommission effort
is closed.

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

**Add industry (issue add-industry) — server side built, LWC pending.** The
D12 follow-up: `GtmPageContentController.createIndustry(label, fields)` adds a
Draft, Active `industry-<slug>` section to the framework Industry Chooser page
with the 12 `industry-tile` rows empty (only `industryLabel` holds a value, as
a draft), so nothing is public until the page is published. Contract:
`docs/architecture/add-industry.md`. The Content Manager "Add industry" modal
is a separate part that waits for PR #240 to merge. **Behaviour change to the
public reader:** `GtmPageContentReader.getIndustryProfiles` now returns an
industry only while its section is Published and Active (the `getPageLayout`
rule), so hiding or deleting an industry now hides it publicly too, and a
Draft one never shows. An industry section that is Draft or hidden today would
disappear from the public chooser (and from any offering's per-offering
`industry-profile` list) once this ships. **Gate:** do not deploy to gtm-prod
until the read-only pre-check in `docs/architecture/add-industry.md` section 6
(Q1-Q3) is run there and passes; gtm-prod is Production and is not a deploy
`industry-profile` list) once this ships. **Gate:** do not deploy to gtm-dev
until the read-only pre-check in `docs/architecture/add-industry.md` section 6
(Q1-Q3) is run there and passes; gtm-dev is Production and is not a deploy
target. Validate on gtm-staging first. Open: `GtmAgentGetConfigState` also
lists `industry-%` sections (content rows only, no Draft filter), so a Draft
industry would appear in GUS's `availableIndustries`; it needs the same
Published/Active join and its own fixture change, not done here.

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

## Later: Ask GUS in the filter bar

- Ask GUS in the filter bar (natural-language filters), requested by the user 2026-09-20, later, not part of the compact-filters change.

## Later: backfill real Account lookups on typed-Company rows

- issue `pages-table-account-column-consistency` fixed the Account/Contact cell
  rendering and precedence (Account__r.Name now wins over Company__c) on both the
  Pages and Assessments tables, but rows with a typed `Company__c` and no linked
  `Account__c` still show plain, non-clickable text -- these are exactly the rows this
  fix makes newly visible as a *pattern*. Worth a follow-up: surface these to reps
  (or an admin report) as a nudge to backfill the real Account lookup. Out of scope
  for the rendering fix itself.

## Later: server-side guard against industry-variant creates on non-configurator templates

- issue `industry-variant-ui-scoping-fix` hid the "Industry view" toggle and
  "+ Industry variant" button on any template other than `configurator` (the
  only template carrying `industry-profile` in `TEMPLATE_LAYOUTS`). This was a
  pure UI-scoping fix -- `GtmPageSectionController.createSection`'s
  `isVariant` branch and `GtmPageContentController.createSection`'s
  pass-through still accept any `offeringKey`/`templateType` combination for a
  variant create, with no allow-list check against `configurator`. Nothing in
  the current UI can reach that path anymore, but a defensive server-side
  guard (reject a variant create when `templateType` isn't industry-aware)
  would be reasonable hardening against a future caller (a different LWC, an
  API client, or Agentforce/GUS tool call) reintroducing the same gap from a
  different angle. Small, separate PR; not folded into the UI fix per the
  task scope's explicit non-goal.
