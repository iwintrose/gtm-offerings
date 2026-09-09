# D11 resolution — implementation plan

Companion to
`docs/architecture/adr/0008-the-guest-assessment-is-hosted-by-the-engagement-link-not-by-a-standalone-route.md`.
That ADR has the "why" and the evidence from git history; this file has the
file-by-file "how," in the order a Dev agent should do it, plus the QA
verification protocol. **Read the ADR first**, and ADR-0007 before that.

Same process as `docs/agent-artifacts/per-offering-instrument-plan.md`
(Architect → Dev → QA). This is the Architect output. Nothing here has been
implemented.

**Scope guardrails:**

- **No `force-app/main/default/experiences/` changes anywhere in this
  plan.** No route added, moved, or deleted; no `Network.Status` change on
  either site. That is the point of the chosen option (ADR-0008 §1) — the
  live site's route table is the one thing not being touched. If a step
  seems to need an `experiences/` edit, stop and escalate; it means the
  plan drifted.
- `GTM_Accelerator1` stays `DownForMaintenance`. Its `/assessment` route
  and view are left exactly as they are. Do **not** try to delete them —
  that is `docs/runbooks/experience-site-lifecycle.md`'s six-step
  unarchive/publish/destructive dance against a live org, and it buys
  nothing here.
- `gtm-dev` is production (CLAUDE.md §1). Nothing runs against it except
  through `./scripts/deploy.sh` or an explicit `--dry-run`.
- Every step touching `force-app/main/default/permissionsets/` is in the
  same commit as the thing it grants (ADR-0002 / CLAUDE.md §5.1).
- Do not hand-edit `force-app/main/default/customMetadata/GTM_Assessment_*`
  XML (CLAUDE.md §10). Nothing in this plan needs to.

---

## §0 — What the investigation actually found

Recorded here because several phases below only make sense against it, and
because two of these are corrections to what the backlog and the user's
recollection assume.

### 0.1 Intent: replacement, and the replacement was never wired up

Traced through `git log --follow` on
`force-app/main/default/lwc/gtmConfigBooking/` (renamed from
`maConfigBooking` in `d73b091`) and on the questionnaire bundle:

| Commit | What it did |
|---|---|
| `c3cde90` / `91481f2` | scaffolded `maConfigBooking` — a short "book a call" form |
| `14ba345` | wired `MA_Assessment_Request__c` into it |
| `d7b7cc7` | prefill + password-gated links |
| `6978c87` | link-event instrumentation |
| `29215f4` | HMAC submission-token gate |
| `552dfb1` | added the eleven qualitative BD fields — the "rich assessment" **as a long form** |
| `1c502d5` | draft save/resume for that form |
| `dc4ad5d` | built `maAssessmentQuestionnaire` — **a new component on a new route** |

`dc4ad5d`'s own commit message: *"The long form was never going to be
filled in. This is the same instrument in digestible steps."* So the
questionnaire was built as the **replacement** for the booking modal's long
form. It was routed onto `GTM_Accelerator1` and the swap on the live
surface was never performed. This is the user's "complete rebuild occurred
→ replace" branch, confirmed from history rather than assumed.

### 0.2 The resubmit guard: **degraded, not lost** — the durable half is wired to the unreachable path

Three separate things exist, and only the weakest one is on the live path:

1. **Durable, server-side, intact** — `GtmAssessmentRequestController.
   closeDraft` appends a terminal `GTM_Form_Draft__c` row carrying
   `Submitted_Request__c` in the same transaction as the request;
   `GtmAssessmentDraftController.latestOpenRowFor` (lines ~400-440) returns
   `null` for any resume token whose newest row has one. This revokes a
   **resume link**. It is intact and must not be disturbed.
   **But** `gtmConfigBooking` never sends `draftToken`, so on the live path
   `closeDraft` receives a blank token and does nothing.
2. **Client-side, live path, weak** —
   `gtmConfigurator.hasSubmittedAssessment` (getter at
   `gtmConfigurator.js:1412`), backed by `assessmentRequestId` persisted to
   `sessionStorage` under `ma-assessment-<savedRecordId>`
   (`persistAssessmentId` / `restoreAssessmentState`, lines ~1330-1360).
   Survives a refresh in the same tab. Does not survive a new tab, a second
   device, a cleared/blocked storage, or a private window.
3. **An explicit re-open path with no guard behind it** —
   `gtmConfigBooking.handleReopen()` sets `showForm = true` from the
   confirmation panel ("Didn't send? *Re-open the request*",
   `gtmConfigBooking.html:343`).

And `GtmAssessmentRequestController.submitRequest` has **no resubmit check
of any kind**. Nothing at any layer prevents N scored requests against one
engagement link.

Supporting fact for the invariant: in `gtm-dev` today, every
`GTM_Saved_Configuration__c` that has any assessment against it has exactly
one (`SELECT Saved_Configuration__c, COUNT(Id) FROM
GTM_Assessment_Request__c WHERE Saved_Configuration__c != null GROUP BY
Saved_Configuration__c` → five rows, all count 1). So enforcing
one-per-link retrofits nothing.

### 0.3 The button flip: **present and intact on the live path — its regression test was dropped in the port**

The three-state machine the user remembers is real and is live today, in
`gtmConfigurator`:

- top-bar CTA: `Get an environment assessment →` (`gtmConfigurator.html:19-22`)
  → when `hasSubmittedAssessment`, a disabled button reading
  `Your assessment is in review` (`topCtaLabel` / `topCtaDisabled`,
  `gtmConfigurator.js:1415-1418`) → when `showPublishedGate`,
  `View your assessment`;
- the closing card flips from the CTA pair to
  `Your request has been submitted.` (`gtmConfigurator.html:381-410`);
- when published, every prior section is replaced by the
  `readout-gate` section (`gtmConfigurator.html:55-68`).

Plus two in-flight two-state flips: `gtmConfigBooking.submitLabel`
(`Request my assessment →` / `Sending…`, button `disabled={submitting}`)
and `gtmAssessmentQuestionnaire.submitLabel` (`Send my assessment` /
`Sending…`, plus per-step `Continue` and a progress bar).

Origin: `c8945b8` ("readout rep review + recipient state machine (Dev B,
lwc/ only)") on `origin/claude/salesforce-marketing-maturity-bsxmxs`,
refined by `b1e2e80`. Ported into this branch by `a2fc262` — which brought
`gtmConfigurator.html` / `.js` / `.css` across and **left the test file
behind**. `force-app/main/default/lwc/maConfigurator/__tests__/
maConfigurator.readout.test.js` (added in `c8945b8`, extended in `b1e2e80`)
exists on no branch that is an ancestor of HEAD, and there is no
`force-app/main/default/lwc/gtmConfigurator/__tests__/` directory in HEAD
at all. **The state machine is unprotected by any automated test today.**
Phase 1 restores it before anything else moves.

### 0.4 Two things a naive swap would silently lose

- **The eleven BD fields.** `targetPlatform` aside, `budgetRange`,
  `contactCount`, `monthlySendVolume`, `painPoints`, `migrationGoals`,
  `keyIntegrations`, `successCriteria`, `internalTeamSize`,
  `executiveSponsorship`, `decisionMakers`, `urgencyDriver` are collected
  only by `gtmConfigBooking` and are read by
  `GtmReadoutController.buildDraftHtml` (Pain points → "Where it hurts",
  Goals, Success criteria, Urgency) and `GtmReadoutAgentContext` (lines
  173-236). Swap without carrying them and every future readout loses
  those sections. Phase 3.
- **The calendar CTA.** `gtmConfigBooking`'s confirmation panel renders
  `Pick a time in our calendar →` from `bookingUrl` (the `?book=` URL
  param). That is the "book an assessment" half of the CTA's promise.
  Phase 5.

### 0.5 The offering-key assumption in `per-offering-instrument-plan.md` §6 — **verified true, with one caveat this plan must fix**

Verified: `GtmAssessmentRequestController.resolveConfigContext` selects
`Offering__c` into `ctx.offering`
(`GtmAssessmentRequestController.cls:339-369`), `resolveOfferingKey(ctx)`
returns it or falls back to `GtmAssessmentFrames.MIGRATION_ACCELERATOR`
(lines 1321-1325), and `submitRequest` threads that one value into
`loadConfig`, the pack resolution and the scoring calls. Every
`GTM_Saved_Configuration__c` in `gtm-dev` has `Offering__c` populated
(`migration-accelerator`, 7/7). So the server side needs **no new plumbing**
for a D11 fix, exactly as the per-offering plan predicted.

**The caveat, which that plan could not have seen:** the *client's*
offering key is a different value from a different source.
`gtmConfigurator.@api offeringKey` (`gtmConfigurator.js:54`) is an
Experience Builder page property with a `migration-accelerator` default —
not the link's `Offering__c`. Today that mismatch is invisible because the
client sends no answers. The moment it does, a page property that disagrees
with the link means the client renders offering A's questions and the
server scores them against offering B's pack — resolving none of the
submitted dimension keys, and scoring nothing while appearing to have
scored. Phase 2.3 closes it, at low cost:
`gtmConfigurator.loadSavedConfiguration()` already calls
`GtmConfigurationReader.getPublicConfiguration` and that response already
carries `offering` (`GtmConfigurationReader.cls:41,60`) — it is simply
never read.

### 0.6 Org facts verified by query (do not re-derive; do re-verify before deploy)

| Fact | Value | How checked |
|---|---|---|
| `GTM` site (`urlPathPrefix: gtm`, bundle `GTM1`) | `Status = Live` | `SELECT Name, Status, UrlPathPrefix FROM Network` |
| `GTM Accelerator` (`gtmaccelerator`, bundle `GTM_Accelerator1`) | `DownForMaintenance` | same |
| `ZZ RETIRED - do not use` (`gtmframework`) | `DownForMaintenance` | same |
| Both site guest users hold `GTM_Assessment_Guest` **and** `GTM_Story_Guest` | yes, 4 assignments | `SELECT Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.UserType='Guest'` |
| `GTM_Assessment_Config.Default.Resume_Link_Base_URL__c` | **blank** | `SELECT DeveloperName, Resume_Link_Base_URL__c FROM GTM_Assessment_Config__mdt` |
| Assessment requests per saved config | 1, for all 5 that have any | grouped count, §0.2 |

The guest-permission finding matters: `GtmAssessmentInstrument`,
`GtmAssessmentQuestions` and `GtmAssessmentDraftController` are **already
granted to the live GTM site's guest user**, so hosting the questionnaire
on `/configurator` needs no new Apex-class grant. Phase 7 verifies rather
than assumes.

---

## §1 — Decision, restated for the Dev agent

Of D11's three options:

- ~~promote `GTM_Accelerator1` to Live~~ — rejected. Flips the live front
  door to a site that has never served traffic, and puts the questionnaire
  on a standalone page with no engagement-link context (ADR-0008 Context).
- ~~port `gtmAssessmentQuestionnaire`'s route onto `GTM1`~~ — rejected, same
  standalone-context problem, plus an `experiences/` change and a publish
  on the live site.
- **wire the live surface to collect and send real answers — by
  *replacing* the booking modal with the questionnaire inside
  `gtmConfigurator`.** Chosen. Matches the rebuild's original intent
  (§0.1), inherits all the link plumbing that already works, and touches
  no route on either site.

---

## Phase 1 — Restore the lost regression test, before changing anything

Nothing else in this plan is safe until the state machine described in
§0.3 has a test again. Do this as its own commit.

### 1.1 Recover the file

```bash
git show c8945b8:force-app/main/default/lwc/maConfigurator/__tests__/maConfigurator.readout.test.js \
  > /tmp/maConfigurator.readout.test.js
git show b1e2e80:force-app/main/default/lwc/maConfigurator/__tests__/maConfigurator.readout.test.js \
  > /tmp/maConfigurator.readout.test.b1e2e80.js
```

Use the `b1e2e80` version (it is the later of the two — `c8945b8` added it,
`b1e2e80` extended it by ~35 lines closing QA findings). Write it to
`force-app/main/default/lwc/gtmConfigurator/__tests__/gtmConfigurator.readout.test.js`.

### 1.2 Rename it into the `GTM_` world

The port commit `d73b091` renamed every `Ma*`/`ma*` symbol. Apply the same
mapping to the recovered test: `maConfigurator` → `gtmConfigurator`,
`c/maConfigurator` → `c/gtmConfigurator`, `MaReadoutPublicController` →
`GtmReadoutPublicController`, `ma-assessment-`/`ma-readout-token-`
sessionStorage keys — **check these against `gtmConfigurator.js`'s
`_assessmentSessionKey()` / `_readoutTokenSessionKey()`, which still use the
`ma-` prefix; do not "fix" the prefix, it is live state on real browsers.**

Run `npm test` and make it pass **against unmodified `gtmConfigurator`**.
If an assertion fails, the port dropped or altered behaviour — record which,
do not weaken the assertion to make it green.

### 1.3 Add the assertions the original could not have

Extend the same file with the states this plan is about to depend on:

- CTA reads `Get an environment assessment →` with no
  `assessmentRequestId`;
- after a `submitted` event carrying an `assessmentRequestId`, the CTA is
  the **disabled** `Your assessment is in review` and the closing card
  reads `Your request has been submitted.`;
- with a `readout` URL param that resolves, the CTA is the **enabled**
  `View your assessment` and the `readout-gate` section replaces the story.

**Commit:** `test(configurator): restore the recipient state-machine test lost in the MA→GTM port`

---

## Phase 2 — The questionnaire becomes embeddable and link-aware

No behaviour change to the live page yet; this phase only makes the
questionnaire capable of being hosted.

### 2.1 `force-app/main/default/lwc/gtmAssessmentQuestionnaire/gtmAssessmentQuestionnaire.js`

Add one public property:

```js
/**
 * Rendered inside the configurator's overlay rather than as a page of its
 * own. Only affects chrome: no step, question, branch or score differs.
 * See ADR-0008 -- the overlay is the only host that has the engagement
 * link's context, so `embedded` is the normal case and standalone is the
 * exception.
 */
@api embedded = false;

get rootClass() {
    return this.embedded ? 'q-root q-root--embedded' : 'q-root';
}
```

Add `@api bookingUrl = '';` (carried through to the confirmation panel —
Phase 5.3) and `@api sessionId = '';` (so the configurator's interaction
trail keeps working — Phase 6.3).

### 2.2 `.../gtmAssessmentQuestionnaire.html` and `.css`

- `<div class="q-root">` → `<div class={rootClass}>`.
- In the CSS, add **after** the existing `.q-root` block (do not edit the
  block itself — the standalone page must render byte-identically):

```css
/* Hosted inside gtmConfigurator's overlay: the card supplies the frame,
   the scroll and the padding, so the full-page assumptions come off. */
.q-root--embedded {
    min-height: 0;
    max-width: none;
    margin: 0;
    padding: 0;
    background: transparent;
}
```

`.q-root` currently sets `min-height: 100vh`, `max-width: 44rem`,
`margin: 0 auto`, `padding: 1.5rem 1.15rem 3rem` and `background:
var(--paper)`. All five are wrong inside a modal card; none may change for
the standalone case.

**Note the `color-scheme: light` on `.q-root`.** It is deliberate (native
selects). The configurator has a dark-theme toggle, so in dark mode the
overlay card will contain a light-schemed form. Leave it — a half-styled
native `<select>` is the failure it was added to prevent. Flag it in the
Dev report so QA looks at it in dark mode and a human decides if it needs
more than leaving alone.

### 2.3 `force-app/main/default/lwc/gtmConfigurator/gtmConfigurator.js` — the link's offering key

In `loadSavedConfiguration()` (around line 655, next to
`if (rec.company) this.company = rec.company;`):

```js
// ADR-0008 section 3. The SERVER resolves the offering from this same
// record's Offering__c (GtmAssessmentRequestController.resolveOfferingKey).
// The page property below is an Experience Builder default and can
// disagree with it; if it does, the questionnaire renders one offering's
// questions and the server scores them against another's pack, resolving
// none of the submitted dimension keys and scoring nothing while looking
// like it scored (ADR-0007's hard boundary).
if (rec.offering) this.linkOfferingKey = rec.offering;
```

Add `@track linkOfferingKey = '';` and:

```js
/** What the questionnaire is actually answering. The link wins; the page
 *  property is only the answer for a direct visit with no link. */
get effectiveOfferingKey() {
    return this.linkOfferingKey || this.offeringKey;
}
```

Do **not** change `this.offeringKey` itself — `getIndustryProfiles` and the
page-content calls at lines 293/326 key off the page property and must keep
doing so; only the assessment path uses `effectiveOfferingKey`.

**Ordering hazard:** `loadSavedConfiguration()` is async. The overlay must
not open with a stale key. Phase 6.2 handles this by not rendering the
questionnaire until `bookingOpen` is true, and `handleOpenBooking` is a user
gesture that necessarily follows page load — but assert it in a test rather
than reasoning about it.

### 2.4 `.../gtmAssessmentQuestionnaire.js-meta.xml`

Add `offeringKey` to `targetConfigs` so the standalone `/assessment` page on
`GTM_Accelerator1` can at least be set correctly by an author (today it is
an `@api` with a comment claiming it is settable from the page builder, and
it is not):

```xml
<property name="offeringKey" type="String" label="Offering key"
          description="Matches GTM_Offering__mdt.Offering_Key__c. Only used when the component is hosted standalone; inside gtmConfigurator the engagement link's own Offering__c wins (ADR-0008)."
          default="migration-accelerator"/>
```

`embedded`, `bookingUrl`, `sessionId`, `savedRecordId`, `submissionToken`
and `resumeToken` stay **out** of `targetConfigs` on purpose — they are
parent-passed, and exposing `savedRecordId` as an author-typed page property
is precisely the standalone-context mistake ADR-0008 §2 forbids.

### 2.5 Tests

`force-app/main/default/lwc/gtmAssessmentQuestionnaire/__tests__/gtmAssessmentQuestionnaire.test.js`
— add cases for `embedded` true/false producing the two root classes, and
for `offeringKey` being passed through to `getQuestionnaire` / `getPack`.

**Commit:** `feat(assessment): the questionnaire can be hosted, and reads the link's offering`

---

## Phase 3 — The eleven BD fields move into the questionnaire

Per ADR-0008 §5. They are BD context, **not** instrument answers: they must
not enter `answers`, `complexityAnswers` or `supplementAnswers`, and nothing
about them may reach a score.

### 3.1 A new, explicitly optional step

In `gtmAssessmentQuestionnaire.js`, `get steps()` (line 301) currently
returns `routing → readiness ×3 → complexity → supplements → contact`.
Insert **one** step immediately before `contact`:

```js
steps.push({ kind: 'context', title: 'Anything else worth knowing' });
```

Back it with `@track bdContext = { targetPlatform: '', budgetRange: '',
contactCount: '', monthlySendVolume: '', painPoints: '', migrationGoals: '',
keyIntegrations: '', successCriteria: '', internalTeamSize: '',
executiveSponsorship: '', decisionMakers: '', urgencyDriver: '' }`.

**`targetPlatform` is already collected** by the routing step
(`this.routing.target`) and already sent. Do not collect it twice — keep the
routing value and leave it out of `bdContext`; the list above includes it
only so the count matches the eleven fields §0.4 names.

Rules for this step, which exist to keep it from re-creating the wall
`dc4ad5d` set out to remove:

- **Every field optional.** `Next` is never blocked here.
- The file's own stated rule is **never more than four questions on a
  screen** (`gtmAssessmentQuestionnaire.js:15`, and it says outright that
  the rule was asserted-then-broken once already). Ten fields is not one
  step. Use the same mechanism the supplements already use —
  `supplementPages()` chunks them — and page this step into three, or make
  it one short step plus a disclosure. **Do not hand-roll a second chunking
  scheme**; extend or reuse `supplementPages()`'s approach so there is one
  implementation of "chunk a list of questions into screens."
- Label it honestly, in the same register the supplements use ("these do
  not affect your score"). These do not affect the score either.
- Skippable in one click: a `Skip this` control that advances to `contact`.

### 3.2 Payload

In `buildPayload()` (~line 925), add the ten `bdContext` keys alongside the
existing `context`/`role` fields. `GtmAssessmentRequestController.
RequestInput` already declares all of them (`@AuraEnabled` properties at
lines 72-83) and `recordAssessmentRequest` already writes them — **no Apex
change is needed for this phase**. Verify that by reading
`recordAssessmentRequest`'s field list before writing the client half; if a
field is declared on `RequestInput` but not written to the record, that is a
separate pre-existing bug to report, not to fix inline.

### 3.3 Draft round-trip

`snapshot()` / `restore()` must carry `bdContext`, or a respondent who
resumes loses this step. Add it to both, and to the localStorage copy.
Confirm the resume test in the existing Jest suite covers a round-trip
including the new key.

### 3.4 Tests

- the context step renders, is skippable, and blocks nothing;
- `buildPayload()` carries all ten keys;
- **an isolation test**: no `bdContext` key ever appears inside `answers`,
  `complexityAnswers` or `supplementAnswers`.

**Commit:** `feat(assessment): carry the BD context fields the readout depends on`

---

## Phase 4 — The resubmit guard, server first

### 4.1 `force-app/main/default/classes/GtmAssessmentRequestController.cls`

In `submitRequest`, **after** `resolveConfigContext` and
`validateTokenIfRequired` and **before** any DML:

```apex
// ONE SUBMITTED ASSESSMENT PER ENGAGEMENT LINK (ADR-0008 section 4).
// The client mirrors this so a respondent is not invited to re-answer
// fifteen minutes of questions, but the client is a courtesy: this is
// where the invariant is true. Scoped to links only -- a direct booking
// with no savedRecordId has nothing to be a duplicate of, and refusing
// those would silently close the one path that has no link at all.
if (String.isNotBlank(input.savedRecordId)) {
    Id linkId = GtmLegacyConfigId.resolve(input.savedRecordId);
    if (linkId != null) {
        List<GTM_Assessment_Request__c> already = [
            SELECT Id FROM GTM_Assessment_Request__c
            WHERE  Saved_Configuration__c = :linkId
            LIMIT  1
        ];
        if (!already.isEmpty()) {
            throw new AuraHandledException(
                'An assessment has already been submitted for this link. ' +
                'Your rep can send a new one if you need to start again.'
            );
        }
    }
}
```

Decisions baked into that, which a Dev agent should not silently reverse:

- **Existence, not score.** Gate on a request existing at all, not on
  `Assessment_Score__c != null`. Otherwise every one of the pre-fix,
  scoreless bookings in the org leaves its link permanently re-submittable,
  which is the bug wearing a hat.
- **Fail closed, and say so.** Unlike `resolveConfigContext` (which fails
  open by design), a failure to determine duplicate-ness must not admit a
  second scored request. If `GtmLegacyConfigId.resolve` returns null the
  link id was unusable and the submission proceeds unlinked — that is the
  existing, deliberate behaviour and is not a bypass, since an unlinked
  request has no link to be a duplicate against.
- **The message names the recovery.** A prospect who genuinely needs to
  redo it has a route (their rep, a new link) rather than a dead end.
- **`AuraHandledException`, not silent success.** The client must be able
  to distinguish this and render §5.2's state.

`closeDraft(input.draftToken, ...)` stays exactly as it is. It solves a
different problem (revoking a resume link) and is intact — §0.2.

### 4.2 `force-app/main/default/classes/GtmAssessmentRequestControllerTest.cls`

- a second `submitRequest` against the same `savedRecordId` throws, and
  inserts no second `GTM_Assessment_Request__c`;
- a second submission with a **blank** `savedRecordId` still succeeds;
- a submission against a *different* link on the same Account still
  succeeds (the invariant is per-link, not per-Account);
- the first submission still succeeds unchanged (guard adds no regression).

### 4.3 Client mirror — `gtmConfigurator.js`

`hasSubmittedAssessment` (sessionStorage) stays as the fast path, and gains
a durable one. In `handleOpenBooking()`, and on page load when `cfgId` is
present, the state must be known without `sessionStorage`.

**A "no new Apex" shortcut was considered and does not work.**
`gtmConfigurator.loadOverviewCrmData()` fetches CRM state for the link, but
it opens with `if (!this.isConfigManager || !this.savedRecordId) return;` —
it is **rep-only**, deliberately, and its controller
(`GtmSavedConfigurationController`) is never granted to the guest
permission set. A guest can never reach it. Do not try to widen it; that is
exactly the surface `GtmConfigurationStatusController`'s header describes
itself as existing to avoid.

So: add one method to `GtmConfigurationStatusController` — the class that
exists precisely to be the tiny, guest-safe status surface, and whose own
header warns against scope creep, so keep it to a boolean:

```apex
/**
 * Whether this link has already had an assessment submitted against it.
 * A boolean and nothing else -- no id, no score, no date. The caller
 * already holds the link; this tells them the form is done, which is the
 * one thing the page needs in order not to invite a second submission
 * (ADR-0008 section 4). Not cacheable: a stale "false" immediately after a
 * submit is the exact case this exists to prevent.
 */
@AuraEnabled(cacheable=false)
public static Boolean hasSubmittedAssessment(String recordId) { ... }
```

`GtmConfigurationStatusController` is **already granted** in
`GTM_Assessment_Guest` (the `<apexClass>` entry near line 14), and Apex
class access is per-class, not per-method — so a new method on it needs no
permission-set change. Confirm that by reading the permission set rather
than trusting this line; if any grant does turn out to be needed it goes in
this same commit (ADR-0002).

The class runs `without sharing`, and `GTM_Assessment_Guest` grants the
guest `allowRead` + `allowCreate` on `GTM_Assessment_Request__c` (and
`allowRead` on `GTM_Saved_Configuration__c`) already, with
`viewAllRecords=false` — so the `without sharing` context is what makes the
query resolve, exactly as it is for `isActive`. Return only the boolean.
No id, no score, no date: the disclosure is "this link's form is done,"
which the holder of the link is entitled to and which is strictly less than
`isActive` already tells them.

Fail **open** on the client (an errored check leaves the CTA available) —
the server is the enforcement point, and a status-check blip must not lock
a prospect out of a form they have not yet filled in. This is the same
reasoning `checkActiveStatus()` states for itself.

**Commit:** `feat(assessment): one submitted assessment per engagement link`

---

## Phase 5 — The button/state machine, preserved and extended

Nothing in §0.3 is removed. This phase carries it onto the new host and
adds the states the new host introduces.

### 5.1 Keep, unchanged

- `hasSubmittedAssessment` → disabled `Your assessment is in review`;
- `showPublishedGate` → enabled `View your assessment` + the `readout-gate`
  section;
- the closing card flipping to `Your request has been submitted.`;
- `_logEvent('Form Opened')` / `_logEvent('Form Submitted')` and
  `identifySession` in `handleBookingSubmitted` — Phase 6.3.

**Constraint:** `scripts/check-configurator-bindings.mjs` parses
`gtmConfigurator.html` for `{chClosing.*}` bindings and fails if the
template reads a field the layout does not declare, or vice versa. Any edit
to the closing card must keep `chClosing.cardHead`, `chClosing.body`,
`chClosing.ctaLabel`, `chClosing.altCtaUrl`, `chClosing.altCtaLabel` used
exactly as they are now. Run that check after touching the file.

### 5.2 Add: the "already submitted" state

If Phase 4.3's durable check says the link is done, the page must land in
the submitted state on **first load in a fresh browser**, not only after a
same-tab refresh. That is the user-visible half of the fix: the CTA reads
`Your assessment is in review` for a prospect who submitted yesterday on a
different device.

If a submit nonetheless races and the server throws Phase 4.1's message,
the questionnaire renders that message in its existing `q-error` slot and
the configurator advances to the submitted state anyway — the request
exists, so the honest state is "submitted", not "failed".

### 5.3 Add: the in-flow states the overlay now has

Inside the overlay, the questionnaire's own machine takes over and already
covers it: per-step `Continue`, `progressLabel` + `progressStyle`,
`Send my assessment` → `Sending…` with `disabled={submitting}` on the last
step, then the `q-done` panel. Keep all of it.

Carry across the one thing `gtmConfigBooking`'s confirmation panel has and
the questionnaire's does not — the calendar CTA. In the `q-done` section:

```html
<template if:true={hasBookingUrl}>
    <a class="q-cta" href={bookingUrl} target="_blank" rel="noopener">
        Pick a time in our calendar →
    </a>
</template>
```

with `get hasBookingUrl() { return !!(this.bookingUrl || '').trim(); }`.

Do **not** carry across `gtmConfigBooking.handleReopen()` ("Re-open the
request"). It is the un-guarded resubmit path §0.2 item 3 identified, and
after Phase 4 it would offer a prospect a form the server will refuse.

### 5.4 Tests

Extend Phase 1's `gtmConfigurator.readout.test.js` with 5.2, and the
questionnaire suite with 5.3.

**Commit:** `feat(configurator): the submitted state survives a new browser`

---

## Phase 6 — The swap

Only now does live behaviour change.

### 6.1 `gtmConfigurator.html`

Replace the `<c-gtm-config-booking>` element (currently lines ~490-503)
with an overlay wrapping the questionnaire. Keep the scrim/card/close
chrome — lift it from `gtmConfigBooking.html` lines 1-5 (`overlayClass`,
`bk-card`, `bk-x`, `handleOverlayClick`, `handleClose`) into
`gtmConfigurator.html` and `gtmConfigurator.css` (the `.bk`/`.bk-card`/
`.bk-x` rules from `gtmConfigBooking.css`), so the modal frame survives the
component that used to own it:

```html
<template if:true={bookingOpen}>
  <div class="bk open" onclick={handleOverlayClick}>
    <div class="bk-card bk-card--assessment">
      <button class="bk-x" aria-label="Close" onclick={handleCloseBooking}>×</button>
      <c-gtm-assessment-questionnaire
        embedded={alwaysTrue}
        offering-key={effectiveOfferingKey}
        saved-record-id={savedRecordId}
        submission-token={submissionToken}
        prospect={company}
        industry-label={industryLabel}
        prefill-company={company}
        booking-url={bookingUrl}
        session-id={visitSessionId}
        onsubmitted={handleBookingSubmitted}
      ></c-gtm-assessment-questionnaire>
    </div>
  </div>
</template>
```

- `alwaysTrue` already exists on `gtmConfigurator` (used for
  `c-gtm-agent-bubble docked=`). Reuse it.
- Rendering behind `if:true={bookingOpen}` rather than the old
  always-rendered/`isOpen`-styled pattern is deliberate: the questionnaire
  does real work in `connectedCallback` (`getPlatforms`, `getQuestionnaire`,
  draft restore) and must not do it on every page load for every prospect
  who never opens the form. It also removes the Phase 2.3 ordering hazard.
- **Close-while-in-progress:** because the component now unmounts on close,
  in-progress answers must survive. They do — localStorage on every change
  plus the server draft — but this is the single highest-risk behaviour
  change in the plan and QA §4 tests it explicitly.
- `bk-card--assessment` is a new CSS class: the assessment card is much
  taller than the booking card, so give it a `max-height`, an
  `overflow-y: auto` and a mobile full-bleed breakpoint rather than letting
  a fourteen-question form overflow the viewport.

### 6.2 `gtmConfigurator.js`

- `handleOpenBooking()`: drop the
  `this.template.querySelector('c-gtm-config-booking').reset()` call —
  there is no longer a component to reset, and a fresh mount is the reset.
  Keep `bookingOpen = true`, `_formOpened` / `_logEvent('Form Opened')` and
  `_track('CTA Clicked', 'closing', …)`.
- `handleBookingSubmitted(event)`: unchanged. The questionnaire's
  `submitted` event detail carries `email` and `assessmentRequestId`;
  **it does not carry `contactId`**, which `gtmConfigBooking`'s did and
  which drives `identifySession` (attributing the whole anonymous reading
  trail to the person). Add `contactId: result ? result.contactId : null`
  to the questionnaire's `submitted` event detail in Phase 2 —
  `RequestResult.contactId` is already returned by `submitRequest`. Losing
  session identification would be exactly the kind of quiet regression this
  plan exists to prevent.
- Rename nothing else: `bookingOpen`, `handleCloseBooking`,
  `handleBookingSubmitted` and the `Form Opened`/`Form Submitted` event
  types are all referenced elsewhere (`gtmLinkSitemap`, `gtmLinkActivity`,
  reporting). A rename here breaks the interaction trail silently. Leave
  the names; the ADR explains why they say "booking".

### 6.3 Retire `gtmConfigBooking`

- Delete `force-app/main/default/lwc/gtmConfigBooking/` (4 files).
- Run `python3 scripts/check-references.py` — expect it to confirm no
  remaining reference. `isExposed` is `false` on the bundle and
  `gtmConfigurator` was its only consumer, so no `experiences/` page can be
  referencing it; **confirm that against the org anyway** per
  `docs/runbooks/experience-site-lifecycle.md`'s "before deleting any
  component" section — the destructive deploy names any page that still
  references it, and that is the authoritative answer.
- **Do not delete `GtmFormDraftController` or `GTM_Form_Draft__c` rows with
  `Draft_Type__c = 'Booking'`.** The controller is still granted in
  `GTM_Story_Guest` and existing rows are prospect data. Retiring the
  Booking draft path is a separate decision for a separate session; note it
  in the Dev report as newly-unused-by-the-configurator, and leave it.

**Commit:** `feat(configurator): the live assessment is the real questionnaire (D11)`

---

## Phase 7 — Resume links, config, permissions, deploy

### 7.1 The resume link must carry the engagement link

`GtmAssessmentDraftController.emailResumeLink` builds the emailed URL from
`GTM_Assessment_Config.Default.Resume_Link_Base_URL__c`, falling back to
`Site.getBaseSecureUrl()`, and appends `?resume=<token>`. That value is
**blank in `gtm-dev` today** (§0.6).

Once the questionnaire lives behind `/configurator`, a link of the form
`…/s/configurator?resume=<token>` lands on the configurator with **no
`cfgId`** — so `savedRecordId` is blank, the overlay does not auto-open, and
if the respondent re-opens the form manually the submission is unlinked.
That reintroduces exactly the context loss ADR-0008 exists to prevent.

Required, in this order:

1. `gtmConfigurator.js` `readUrlParams()`: read a `resume` param alongside
   the existing `readout`/`cfgId` handling, store it, and auto-open the
   overlay (`bookingOpen = true`) when present, passing it down as
   `resume-token` to the questionnaire. Log a `Form Opened` link event for
   it the same way `handleOpenBooking` does — a resumed open is an open.
2. `GtmAssessmentDraftController`: the emailed URL must carry the link id
   as well as the token. The cleanest form is for `saveDraft` to persist
   the config id on the draft row (`GTM_Form_Draft__c.Saved_Configuration__c`
   already exists) and for `emailResumeLink` to append
   `?cfgId=<id>&resume=<token>` when the draft has one.
   **This is a change to a SECURITY-SENSITIVE, guest-writable class** whose
   own header says any change needs security review before merge. Treat it
   as such: the id is read from the stored row, never from the caller;
   nothing else about the class's "one failure, one response" contract
   changes; and `resumeDraft` must not start returning the config id to the
   caller. If the reviewer is not comfortable, the fallback is to ship
   Phase 7.1(1) only and accept that an emailed resume lands unlinked —
   worse, but not a regression, since resume-by-email has never worked on
   the live site at all.
3. **Human/ops step, not a deploy step:** set
   `GTM_Assessment_Config.Default.Resume_Link_Base_URL__c` to the GTM
   site's configurator URL (`https://<gtm-dev domain>/gtm/s/configurator`).
   Confirm the domain by query, do not guess it. Record the value set in
   the Dev report.

### 7.2 Permission sets

Verified in §0.6 that both site guest users already hold
`GTM_Assessment_Guest` and `GTM_Story_Guest`, and that
`GtmAssessmentInstrument`, `GtmAssessmentQuestions` and
`GtmAssessmentDraftController` are granted there. So **no new class grant is
expected**. Re-run the check before deploying; if Phase 4.3 or 7.1 adds a
field or class that is not granted, the grant goes in the same commit
(ADR-0002 / CLAUDE.md §5.1).

Specifically re-verify, because they are what the live guest user will now
exercise for the first time:

- `GTM_Assessment_Guest` → `GtmAssessmentInstrument`,
  `GtmAssessmentQuestions`, `GtmAssessmentDraftController`,
  `GtmAssessmentRequestController`;
- `GTM_Assessment_Guest` → `GTM_Assessment_Request__c` create + every field
  Phase 3 now writes (the eleven BD fields **and** `Section_Scores__c`,
  `Supplement_Scores__c`, `Estate_Complexity_*`, `Instrument_*`,
  `Offering_Key__c`). A field the guest cannot write is written as null with
  no error — the exact FLS failure mode CLAUDE.md §5.1 describes, and the
  one most likely to make this whole fix look like it worked while scoring
  nothing.
- `GTM_Story_Guest` → `GTM_Form_Draft__c` object + fields (already there for
  the Booking path; the Assessment path reaches the object through
  `GtmAssessmentDraftController`'s own class grant, deliberately **not**
  through an object grant on `GTM_Assessment_Guest` — do not "fix" that,
  it is documented in that class's header).

### 7.3 Deploy

```bash
python3 scripts/check-references.py
python3 scripts/build-instrument.py --check   # expect no drift; nothing here touches the instrument
npm test
./scripts/check-all.sh --static
sf project deploy start --source-dir force-app/main/default --target-org gtm-dev --dry-run
./scripts/deploy.sh gtm-dev --run-tests
```

Then, even though **no `experiences/` file changed**:

```bash
sf community publish -n "GTM"
```

LWC bundle changes are served from the org and generally take effect without
a publish, but a publish is cheap, is this repo's convention (CLAUDE.md §4),
and removes any doubt about a cached snapshot. Publish `GTM` only — do not
publish or touch `GTM Accelerator`.

Finally `./scripts/check-all.sh` (live checks included) and record the
output.

### 7.4 Docs

- `docs/backlog.md` D11: mark resolved, pointing at ADR-0008 and this file.
- `docs/architecture/overview.md`: the container diagram shows the booking
  modal on the live route; update it and the "Known gap" callout.
- `docs/runbooks/questionnaire-resume.md`: the "What a human still has to
  do" section names
  `https://<site-domain>/gtmaccelerator/s/configurator` as the resume base
  URL. That is the wrong site now — update it to the GTM site and add the
  `cfgId` requirement from §7.1.
- `CLAUDE.md` §5.7 and §7 both describe the pre-fix topology
  (`GTM1` "has only a `/configurator` route" served by a booking component).
  The route sentence stays true; the implication that the live site cannot
  assess does not. Update.

**Commit:** `docs: D11 resolved -- the live assessment is real (ADR-0008)`

---

## Open calls, flagged rather than decided

1. **Where the BD-context step sits.** This plan puts it before `contact`
   as one optional, chunked step. An equally defensible answer is to move
   the fields into `supplements` (the existing "these do not affect your
   score" mechanism) and delete the new step kind entirely. Chosen the new
   step because supplements are pack-resolved metadata and these eleven are
   fixed schema fields — mixing them would put non-instrument content into
   the instrument's own resolution chain. If the Dev agent finds that
   cheaper and can keep them out of `supplementAnswers`, that is an
   acceptable substitution; say so in the report.
2. **Retiring the `Draft_Type__c = 'Booking'` path.** Left alone (§6.3).
   Someone should decide, later, whether `GtmFormDraftController` still has
   a caller.
3. **Dark mode inside the overlay** (§2.2). Left as-is; needs a human eye.

---

## QA verification protocol

Independent, after Phases 1-7 land. Do not re-read the diff. The standard
this session has used all night: call the real production Apex, and drive
the real live site in a real browser. `gtm-dev` is production — every
submission below creates a real record, so use an obviously-fake company
and clean up in §7.

### 1. Establish the baseline the fix is measured against

Before touching anything, record what a pre-fix submission looked like:

```bash
sf data query --target-org gtm-dev -q "SELECT Id, Name, Offering_Key__c, Assessment_Score__c, Assessment_Tier__c, Section_Scores__c, Instrument_Pair__c, Pain_Points__c, Saved_Configuration__c, CreatedDate FROM GTM_Assessment_Request__c ORDER BY CreatedDate DESC LIMIT 20"
```

Note the rows with `Section_Scores__c = null` — those are the D11 symptom.
Note also which rows already have full eight-key section scores (the
seeded/scripted ones from the per-offering work); do not mistake those for
evidence the live path works.

### 2. Confirm the live route and site are what the fix assumes

```bash
sf data query --target-org gtm-dev -q "SELECT Name, Status, UrlPathPrefix FROM Network"
```

`GTM` must still be `Live`, `GTM Accelerator` still `DownForMaintenance`.
**If either changed, stop** — someone did something this plan explicitly
did not, and every conclusion below is void (ADR-0006).

Confirm `git diff` touched **zero** files under
`force-app/main/default/experiences/`. Any file there is a plan violation.

### 3. A real submission now scores for real — the headline test

In a real browser, as an **anonymous** visitor (private window, and confirm
you are not logged into the org — CLAUDE.md §5.6: with
`allowInternalUserLogin = true` an internal user is served the rep
experience, which is not what a prospect sees):

1. Create a fresh engagement link as a rep, with a fictional company
   (`Northlight Media Group (Demo)` style — CLAUDE.md §5.5; do **not** use a
   real company name). Note its `cfgId` and its `Offering__c`.
2. Open `https://<domain>/gtm/s/configurator?cfgId=<id>&company=…` in the
   private window. Confirm the top CTA reads
   `Get an environment assessment →`.
3. Click it. Confirm the **questionnaire** opens — routing step first
   ("What are you moving from?"), a progress bar, `Continue` — not the old
   single-page booking form. Confirm the modal scrolls inside its card and
   the page behind it does not.
4. Answer every step honestly and distinctly — **do not give the same
   value to every question**; a uniform answer set cannot distinguish "the
   answers were scored" from "a constant was scored." Vary them so the
   expected total is arithmetically unique.
5. Fill in at least `painPoints`, `migrationGoals` and `budgetRange` on the
   context step with recognizable sentinel strings.
6. Submit.

Then, from the org:

```bash
sf data query --target-org gtm-dev -q "SELECT Id, Name, Offering_Key__c, Assessment_Score__c, Assessment_Tier__c, Section_Scores__c, Estate_Complexity_Score__c, Estate_Complexity_Band__c, Instrument_Pair__c, Instrument_Max_Score__c, Pain_Points__c, Migration_Goals__c, Budget_Range__c, Saved_Configuration__c, Opportunity__c, Contact__c, Account__c FROM GTM_Assessment_Request__c ORDER BY CreatedDate DESC LIMIT 1"
```

**All of these must hold:**

- `Section_Scores__c` is populated with **eight** keys, and the values are
  the ones you actually chose — check two of them against what you clicked;
- `Assessment_Score__c` equals the sum of those eight, and is **not** a
  round number that would also result from a uniform answer set;
- `Assessment_Tier__c` is the band that score falls in (14/20/26 edges for
  `migration-accelerator`);
- `Estate_Complexity_Score__c` / `_Band__c` are populated;
- `Offering_Key__c` equals the **link's** `Offering__c`, not necessarily
  the Experience Builder page property;
- `Instrument_Pair__c` names the pair your routing answers imply
  (`eloqua_to_sfmc`, `base`, etc.) — not `null`;
- `Pain_Points__c` / `Migration_Goals__c` / `Budget_Range__c` contain your
  sentinel strings;
- `Saved_Configuration__c`, `Opportunity__c`, `Contact__c`, `Account__c`
  are all populated — this is the engagement-link context ADR-0008 §2 is
  about, and it is the thing the rejected options would have lost.

### 4. Answers survive closing the overlay

The single riskiest behaviour change (§6.1):

1. Fresh link, fresh private window. Open the form, answer through the
   routing step and two readiness steps.
2. Close the overlay with the `×`. Confirm the story page is intact behind
   it.
3. Re-open the CTA. **Every answer must still be there**, and the step
   position restored or clearly resumable.
4. Now close the **whole tab**, re-open the same URL, re-open the form.
   Answers must still be there (localStorage).
5. Confirm a `GTM_Form_Draft__c` row exists with
   `Draft_Type__c = 'Assessment'` for this session, and that
   `Draft_JSON__c` is non-empty.

### 5. Resubmission after a completed submit is blocked — all four ways

Using the link from §3, which now has a submitted assessment:

1. **Same tab, refresh.** CTA must read `Your assessment is in review` and
   be **disabled**. Closing card must read
   `Your request has been submitted.`
2. **New private window, same URL** (no `sessionStorage`). Same result —
   this is the durable guard from Phase 4.3 and the half that did not exist
   before. If this shows the open CTA, the fix is incomplete.
3. **Server enforcement, directly.** Anonymous Apex, bypassing the UI
   entirely:

   ```apex
   GtmAssessmentRequestController.RequestInput in = new GtmAssessmentRequestController.RequestInput();
   in.name = 'QA Duplicate'; in.email = 'qa+dup@example.com';
   in.savedRecordId = '<the same cfgId>';
   try {
       GtmAssessmentRequestController.submitRequest(in);
       System.debug('FAIL: a second submission was accepted');
   } catch (Exception e) {
       System.debug('PASS: ' + e.getMessage());
   }
   ```

   Then re-run the grouped count from §0.2 and confirm the link still has
   **exactly one** request. A UI that hides the button while the server
   accepts a duplicate is not the guard.
4. **The re-open path is gone.** Confirm no "Re-open the request" link
   exists anywhere in the confirmation panel.

Also confirm the **resume link** for that draft is dead: take the
`Resume_Token__c` from the draft row, open
`…/s/configurator?cfgId=<id>&resume=<token>`, and confirm it does not
restore a form (the terminal `Submitted_Request__c` row revokes it —
§0.2 item 1, which must still work).

### 6. The button genuinely reflects progress — not just at the ends

Walk one submission and confirm each transition **in the browser**, not in
the code:

| Point in flow | Expected |
|---|---|
| page load, never submitted | `Get an environment assessment →`, enabled |
| overlay open, step 1 of N | progress bar at 1/N, primary button `Continue` |
| mid-flow | progress bar advances; `Back` returns without losing an answer |
| last step, before click | `Send my assessment`, enabled |
| during submit | `Sending…`, button **disabled** (throttle the network in devtools to actually see this — if it flickers past, the state is still what matters, confirm via the DOM) |
| after submit | `q-done` panel; `Pick a time in our calendar →` present iff the link carried `?book=` |
| behind the overlay, after close | top CTA `Your assessment is in review`, **disabled**; closing card flipped |
| after the rep publishes the readout | top CTA `View your assessment`, **enabled**; the `readout-gate` section replaces the story |

The last row needs a rep to actually generate, approve and publish a
readout for that request — do it, because it is the one transition that
proves the whole chain (§3's real score → readout → approval → publish)
still connects.

### 7. Nothing already working regressed

- `npm test` green, including Phase 1's restored test.
- `sf apex run test --target-org gtm-dev` green.
- `python3 scripts/check-references.py` — 0 deploy-blocking, and no
  dangling reference to `gtmConfigBooking`.
- `python3 scripts/build-instrument.py --check` — no drift (this plan does
  not touch the instrument; drift means something unrelated leaked in).
- `./scripts/check-all.sh` including the live page-contract checks — the
  configurator's story content, chapters and field order must be unchanged.
  `check-configurator-bindings.mjs` in particular must pass, given §5.1's
  closing-card constraint.
- Open an **existing** engagement link from before the change (one of the
  five with a request already against it). Confirm the story renders, the
  submitted state shows, and — critically — that its **existing readout**
  still renders identically. `GtmReadoutModel.buildJson` re-resolves
  historical readouts through `Instrument_Pair__c`; a regression here would
  rewrite history.
- Confirm as a **rep** (logged in, `allowInternalUserLogin = true`) that
  Gus, the saved-links bar, the Customize/stage actions and the readout
  review surfaces are all unchanged.
- Confirm `GTM Accelerator`'s `/assessment` page is untouched and the site
  is still `DownForMaintenance`.

### 8. Clean up

Delete the QA-created `GTM_Saved_Configuration__c`, its
`GTM_Assessment_Request__c`, any `GTM_Form_Draft__c` rows, the Opportunity,
Contact and Account created by the run — or, if any are kept deliberately as
a reference example, say which and why in the QA report. Do not leave a
half-cleaned fixture in production.

### 9. Report

State plainly, for each of the four things the user asked to be proven:
a real submission scores for real; resubmission is blocked; the button
reflects progress; nothing regressed. For each, say **how it was proven** —
which query, which browser step — not that it was.
