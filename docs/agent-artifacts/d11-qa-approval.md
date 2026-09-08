# D11 / ADR-0008 — QA verification

**Verdict: APPROVED, with one part of the protocol left unverified for lack of
capability, not for lack of trying.** Every claim in the Dev's report that could
be tested was tested independently against live `gtm-dev`, and every one of them
held. Nothing was falsified. Two things in the plan's §6 could not be completed
here and need a human at a keyboard — they are listed under "Not verified" and
they are the only open items.

Companion to `docs/architecture/adr/0008-…` and
`docs/agent-artifacts/d11-resolution-plan.md` (QA verification protocol §1-9).
Same standard as `per-offering-instrument-qa-approval.md`: reproduce or falsify,
never accept a self-report.

---

## 0. The headline caveat: no real browser was available

The protocol's §3, §4, §5.2 and §6 are written as browser work, and the Dev
explicitly could not do them. **I could not either.** This is stated first
because it is the single most important qualification on everything below.

It was not skipped. It was attempted at length:

| Attempt | Result |
|---|---|
| Playwright Chromium (installed globally, `/opt/pw-browsers/chromium-1194`) direct to the site | `net::ERR_CONNECTION_RESET` |
| Same, with the session's egress proxy set via Playwright's `proxy` option and via `--proxy-server` | `net::ERR_CONNECTION_RESET` |
| `curl` to the identical URL | **`HTTP 200`** — so the host is reachable and not policy-blocked |
| Chromium netlog (`--log-net-log`, capture mode Everything) | `CONNECT` succeeds (`HTTP/1.1 200 Connection Established`, 39 B), Chromium sends a 1753-1817 B ClientHello, then `SSL_HANDSHAKE_ERROR net_error -101` with zero bytes back |
| Narrowing the ClientHello: `--disable-features=PostQuantumKyber,TLS13PostQuantumKeyAgreement,EncryptedClientHello`, `--ssl-version-max=tls1.2`, `--disable-http2` | ClientHello stayed 1817 B; identical reset every time |
| Firefox / WebKit | Not installed — `/opt/pw-browsers` has Chromium only |

So the egress proxy accepts `curl`'s and Node's TLS handshakes and resets
Chromium's, in every configuration. That is an environment limitation, not a
property of the change under test. A local TLS-terminating shim for the site's
hostname would have worked around it, but generating a certificate for a real
hostname was correctly refused by the permission layer, and I did not attempt to
circumvent that.

**Consequence:** where the protocol says "in a real browser", this report
substitutes either the real production Apex entry point or the real component
code running in JSDOM. Both are stated explicitly per item. Nothing below is
inferred from reading the diff alone.

---

## 1. A real submission scores for real — the headline test

**How proven:** driven through the real guest entry point,
`GtmAssessmentRequestController.submitRequest`, against a throwaway engagement
link created in production for this run. Company `Kestrel Vale Logistics
(Demo)` — wholly invented, `(Demo)`-suffixed (CLAUDE.md §5.5).

Answers were chosen to be **arithmetically unique**: `estate_scale=4`,
`source_access=2`, `orchestration_portability=3`, `content_portability=2`,
`data_model_readiness=4`, `integration_containment=1`, `consent_portability=3`,
`decision_readiness=4`. **Sum = 23, which is prime** — no uniform answer set
across eight dimensions can produce it. (Deliberately different from the Dev's
22, so the record could not be theirs.) `source_access` was kept off the floor
so the `GtmAssessmentScoring` access gate would not cap the tier and blur the
arithmetic.

Result on `AR-0047`:

| Field | Value | Verdict |
|---|---|---|
| `Section_Scores__c` | `{"decision_readiness":4,"consent_portability":3,"integration_containment":1,"data_model_readiness":4,"content_portability":2,"orchestration_portability":3,"source_access":2,"estate_scale":4}` | 8 keys, **every value the one chosen** |
| `Assessment_Score__c` | `23` | exactly the sum; prime |
| `Assessment_Tier__c` | `Accelerator-Ready` | correct band for 23 (edges 14/20/26) |
| `Estate_Complexity_Score__c` / `_Band__c` | `12` / `Moderate` | matches the 6 complexity answers (3+1+2+3+1+2) |
| `Instrument_Pair__c` | `eloqua_to_sfmc` | from the routing answers, not null |
| `Instrument_Max_Score__c` | `32` | — |
| `Offering_Key__c` | `migration-accelerator` | taken from the **link's** `Offering__c` |
| `Saved_Configuration__c` / `Opportunity__c` / `Contact__c` / `Account__c` | all populated | the engagement-link context ADR-0008 §2 exists for |

All eleven BD-context fields stored with their sentinels: `Pain_Points__c`,
`Migration_Goals__c`, `Success_Criteria__c`, `Key_Integrations__c`,
`Decision_Makers__c`, `Urgency_Driver__c` carried
`QA-D11-*-77xx`; `Budget_Range__c = $2.5M+`, `Executive_Sponsorship__c`,
`Internal_Team_Size__c`, `Contact_Count__c`, `Monthly_Send_Volume__c` all set.

**Extra check the plan did not ask for:** the input carried
`assessmentScore = 999`. The stored score is 23. A prospect still cannot author
their own score.

**Not done in a browser** (see §0), so the parts of §3 that are purely visual —
the routing step rendering first, the progress bar, the modal scrolling inside
its card rather than the page behind it — are **not** confirmed by this report.

---

## 2. Answers survive closing the overlay (protocol §4)

The overlay is `<template if:true={bookingOpen}>` in `gtmConfigurator.html`, so
closing it with the `×` **destroys** the questionnaire component and re-opening
**mounts a fresh one**. Closing the whole tab is the same code path with
`sessionStorage` additionally gone. Both therefore reduce to one question: does a
fresh mount, same `savedRecordId`, `localStorage` intact and **no server draft
available**, come back with the answers?

**How proven:** a throwaway JSDOM test driving the real
`gtmAssessmentQuestionnaire` component (created, run, deleted — not committed).
It answered the routing step and two readiness steps with deliberately
non-uniform values (2 then 4), captured the step label and every selected
option, removed the element from the DOM, and mounted a brand-new one.

- step position restored identically;
- **every selected option restored**, in order;
- `resumeDraft` was **never called** — restoration came from `localStorage`
  alone, which is what a closed overlay actually leaves behind;
- a different `savedRecordId` gets nothing, and the first link's progress is
  still intact afterwards.

This gap was worth closing: the shipped suite proves the *negative* ("link B
does not inherit link A's answers") and never the *positive*.

**Live, in production:** a real `GtmAssessmentDraftController.saveDraft` call
produced a `GTM_Form_Draft__c` row with `Draft_Type__c = Assessment`,
`Saved_Configuration__c` = the link, `Session_Id__c` set, `Pair_Key__c =
eloqua_to_sfmc`, non-empty `Draft_JSON__c`. Protocol §4.5 satisfied.

**Not done in a browser:** that the story page behind the overlay is visually
intact after the `×`.

---

## 3. Resubmission after a completed submit is blocked (protocol §5)

Run independently, not read from the Dev's log.

**Server enforcement.** A second `submitRequest` against the same link, carrying
a *full and differently-scored* answer set (sum 8, so it would have been
distinguishable had it landed):

- refused — the throw was reached (it surfaces from anonymous Apex as
  `System.LimitException: Can only throw this exception type from VisualForce or
  Aura context`, which is what an `AuraHandledException` does outside an Aura
  context);
- request count for the link stayed at **exactly 1**;
- **no `Contact` was written** by the refused attempt (`COUNT = 0` for its
  email). This confirms the guard really does sit before all DML, as its comment
  claims — a refused duplicate writes nothing at all.

**The durable half** (the case a new private window depends on, and the half
that did not exist before): `GtmConfigurationStatusController.hasSubmittedAssessment`
returned **`true`** for the link, called live. This is the server-side fact the
page reads on load — `gtmConfigurator.checkSubmittedStatus()` calls it from
three sites and sets `assessmentRequestId = 'linked'`, which drives the disabled
CTA. It is `cacheable=false`, so a stale `false` cannot be served after a submit.

**The resume link is revoked.** Tested end to end on a second throwaway link:
saved a draft, confirmed the token resumed (`true`), submitted with that
`draftToken`, then re-tried the same token — **`false`**, and a terminal
`GTM_Form_Draft__c` row carrying `Submitted_Request__c` was written. This is
notable: pre-fix, `gtmConfigBooking` never sent a `draftToken`, so `closeDraft`
received a blank token and did nothing. The revocation half of §0.2 item 1 is now
actually reachable on the live path.

**The re-open path is gone.** The only occurrence of "Re-open" anywhere in
`gtmAssessmentQuestionnaire` is a comment recording that it was deliberately
*not* carried across.

**Not done in a browser:** that a genuinely new private window renders the
disabled CTA. The server fact it reads is verified; the rendering is not.

---

## 4. The button reflects progress (protocol §6)

**Partially verified — and this is the weakest item in the report.**

Verified from the restored regression suite (`gtmConfigurator.readout.test.js`,
19 cases, all passing) plus the component source: the three-state machine exists
and is now protected by a test again — `Get an environment assessment →`
(enabled) → `Your assessment is in review` (disabled) → `View your assessment`,
the closing card flipping to `Your request has been submitted.`, the durable
check turning the flag on for a fresh browser, failing **open** on error, and the
locally-known id winning over the bare boolean. Restoring this file was Phase 1
of the plan and it is genuinely restored and genuinely green.

Verified live in production: the chain up to the readout is real. My submission
auto-generated readout `RDO-0039`, `Status__c = Draft`, `Offering_Key__c =
migration-accelerator`, with **1875 characters of `Draft_Content__c` derived from
my actual answers**.

**Not verified — the last row of the table.** Approving and publishing that
readout, and seeing the CTA flip to `View your assessment` with the
`readout-gate` section replacing the story, was **not** completed:
`submitForApproval` refuses because the QA user has **no `ManagerId`**, and
`GTM_Readout_Approval` routes to the owner's manager. Setting a manager on a
production `User` record was refused by the permission layer, and I did not work
around it.

What was done instead: the pre-existing published readout `RDO-0008` still
renders through the real guest entry point,
`GtmReadoutPublicController.getPublishedReadout`, returning 6490 characters — so
the published-gate code path is alive. But the specific transition
*for a readout generated by this fix* is unproven.

**This is the one item that needs a human**: a rep with a manager set should
approve and publish one readout end to end and confirm the CTA flips.

---

## 5. The `Resume_Link_Base_URL__c` bug claim — independently confirmed

All three parts of the Dev's claim check out.

**The field is absent, not blank.** Current source for
`GTM_Assessment_Config.Default.md-meta.xml` has no `<values>` block for
`Resume_Link_Base_URL__c` at all, only a comment explaining why.

**It was a genuine pre-existing bug.** `git log -S` on that file shows the
`<value xsi:nil="true"/>` was introduced by **`a2fc262`** — well before the ADR
commit `ab4dbb5` and before any of the Dev's seven commits. `git show
ab4dbb5:…` confirms the nil was present at baseline. The old comment made the
contradiction self-evident: it told operators to *"Set it in the target org"*
while the file itself blanked it on every deploy.

**The fix actually works — tested, not assumed.** Rather than take "verified
empirically" on faith:

1. queried the org: value was
   `https://…/gtm/s/configurator`;
2. **deployed that one CustomMetadata record for real** (`Changed`);
3. re-queried: value **still intact**.

A deploy no longer re-blanks an operator-set value.

---

## 6. The security-sensitive change (Phase 7.1(2)) — confirmed, with one note

Read the current `GtmAssessmentDraftController.cls` rather than its comments,
and probed for leak paths.

**`resumeDraft` does not return the config id.** `DraftPayload` declares only
`payload`, `expiresAt`, `lastSavedAt`. Confirmed **live in production** by
calling `resumeDraft` on a real draft that *did* carry a link and session, and
serializing the whole response:

```
{"payload":"…","lastSavedAt":"…","expiresAt":"…"}
leaksConfigId=false   leaksSession=false
```

Serialized, so a field added later would be caught, not just the properties
declared today. The shipped test
`resumeDraftNeverHandsBackTheEngagementLink` asserts the same thing the same way.

**Other paths checked, all clean:**

- `saveDraft` returns `DraftHandle` — `resumeToken`, `expiresAt`, `created`. No id.
- `emailResumeLink` returns `SendResult` — `sent` plus a **fixed** string; the
  success message is `'Sent. Check your inbox — the link works on any device.'`
  and does not echo the URL or the address.
- Failure messages are the single `GENERIC_FAILURE` constant for every cause.
- **`GtmFormDraftController`** is the one other guest-granted class
  (`GTM_Story_Guest`) that reads `GTM_Form_Draft__c`, and it uses dynamic SOQL —
  the obvious candidate. Its `getDraft` is hard-filtered to
  `Draft_Type__c = 'Booking'` and is keyed *by* `configId`, so it can neither
  read an Assessment row nor map a draft back to a link. No leak.
- **Validation:** passing a well-formed Id of the *wrong* type (an Account Id)
  stored `null` — degraded, did not throw, did not persist. Confirmed live.
- **No new field** was introduced — `Saved_Configuration__c` on
  `GTM_Form_Draft__c` already existed and only its `description` changed, so
  there is no ADR-0002 permission-set obligation outstanding.

**One note, not a blocker.** `DraftPayload`'s comment justifies withholding the
id on the grounds that returning it *"would turn a resume token into a way to
learn which link a draft belongs to."* `emailResumeLink` does let a token holder
learn exactly that — it mails the URL, now containing `?cfgId=`, to an address
**the caller chooses**. In practice this discloses nothing: every realistic way
to hold a resume token (being the respondent, or intercepting their resume
email) already carries the `cfgId` — it is in the URL bar, and in the email
itself. So the security property that matters holds and I am not treating this
as a finding; the stated rationale is just slightly wider than the code
delivers. Worth a sentence in that comment if anyone touches it.

---

## 7. Guardrails — independently confirmed

- **Zero `experiences/` changes.** `git diff --name-only ab4dbb5..HEAD --
  force-app/main/default/experiences/` → **0 files**.
- **Site status** (queried, not inferred — ADR-0006): `GTM` = **`Live`**,
  `GTM Accelerator` = **`DownForMaintenance`**. Re-checked at the end of the run;
  unchanged.
- **`gtmConfigBooking` is genuinely gone.** Absent from
  `force-app/main/default/lwc/`; a Tooling API query for
  `LightningComponentBundle` returns **0** rows for it while returning the
  expected 4 `gtmConfig*` siblings, so the query is sound and the deletion real.
- **Referrers re-checked myself, not taken from the dry-run log.** Every
  remaining mention of `gtmConfigBooking` in `force-app/` is a **comment**; there
  is no `<c-gtm-config-booking>` tag anywhere. `grep` over
  `force-app/main/default/experiences/` finds nothing. **`gtmConfiguratorCopy`**
  — which exists in both the org and the source tree and is the one plausible
  second referrer the Dev's report did not name — never referenced it.
- `allowInternalUserLogin` retrieved from the org: **`true`** on `GTM`
  (CLAUDE.md §5.6), so the rep experience is still served to internal users.

---

## 8. The test and check numbers — re-run, not quoted

| Check | Result | Against the Dev's claim |
|---|---|---|
| `sf apex run test` (RunLocalTests) | **578 passed, 0 failed, 100%** | Dev said 577 — trivially off, and green either way |
| `npm test` | **199 passed, 1 skipped, 200 total** | Dev said "200 passing"; it is 199 passing + 1 skipped. The skip is `preview.test.js`, pre-existing and env-gated (`OUT`) |
| `check-references.py` | **7 deploy-blocking, 96 manual** | matches |
| `build-instrument.py --check` | **no drift** — 55 records, 1 offering, 14 rules hold | matches |
| `check-configurator-bindings.mjs` | exit 0 | matches |
| 5 live page contracts | all hold | matches |

**"7 pre-existing, all markdown" — verified properly.** Rather than trusting a
`git stash`, I created a git worktree at the ADR commit `ab4dbb5` and ran
`check-references.py` there: **the same 7, the same files**. All 7 are the same
finding — the org Id appearing in `AGENTS.md`, `CLAUDE.md` and five
`docs/agent-artifacts/*.md` files. No source file is implicated. (This report
deliberately does not reproduce that literal id, which would make it an eighth.)

**The stale-worktree fix is real and was worth making.** `.claude/worktrees/`
holds an abandoned pre-fix checkout with **9 test suites**; running jest against
it deliberately shows **17 failing tests**. Before the `jest.config.js`
`testPathIgnorePatterns` change those were being reported as failures of HEAD.
Claim substantiated.

**Two small corrections to the Dev's summary**, neither a defect:

1. **`./scripts/check-all.sh` exits 1, printing `FAILED: 1 check(s)`.** The Dev
   reported its sub-checks as holding (they do) without mentioning the non-zero
   exit. Isolated: it is `check-references.py` exiting 1 on the 7 pre-existing
   markdown findings — `check-content-contract.py` and the bindings check both
   exit 0. **Identical at the baseline commit**, so it is not a regression.
2. `check-references.py`'s "needs a manual step" count went **94 → 96**. The two
   additions are `docs/backlog.md` and `docs/runbooks/questionnaire-resume.md`,
   both now documenting the org-specific resume URL. Documentation, not
   deployable metadata. Benign, but it is a real delta the report did not mention.

---

## 9. Nothing regressed

- **Historical readouts still resolve through `Instrument_Pair__c`.** Every
  pre-existing request with an engagement link was re-rendered through
  `GtmReadoutModel.buildJson` with a fully hydrated record: `AR-0003`
  (`pair = null`, the pre-fix scoreless symptom — renders, 1853 chars, degrades
  rather than throwing), `AR-0017` and `AR-0021` (`eloqua_to_sfmc`, 5802 / 5681),
  `AR-0022` and `AR-0023` (`base`, 3429 / 3408). All render, and the pair-
  specific ones render differently from the base ones — resolution is still
  discriminating, not collapsed.
- **The published readout still renders for a guest.** `RDO-0008`
  (`Status__c = Published`) returns 6490 characters through
  `GtmReadoutPublicController.getPublishedReadout`, and is untouched by this run.
- **Every pre-existing link correctly reports the submitted state.**
  `hasSubmittedAssessment` returned `true` for all five. This is the intended
  reading of ADR-0008 §4's "EXISTENCE, NOT SCORE" — the pre-fix scoreless
  bookings count as submitted, so those links are not left permanently
  re-submittable.
- **Rep surfaces are untouched.** The diff changes no rep component except
  `gtmInstrumentAuthor`, and that change is only the removal of the
  `reachabilityCaveat` banner. Reading the old code, its own comment said to
  delete it *"the day `gtmConfigBooking` is rewired onto the real
  questionnaire"* — which is this change. The banner told authors their pack
  edits do not reach real prospects; that is now false, so removing it is
  correct. Gus, the saved-links bar, stage actions and the readout review
  surfaces have no diff at all.

---

## Not verified — the open items

1. **The §6 last row.** Approve + publish a readout for a fresh submission and
   watch the CTA flip to `View your assessment` with the `readout-gate` section
   replacing the story. Blocked by the QA user having no `ManagerId`, which
   `GTM_Readout_Approval` requires; setting one on a production `User` was
   refused by the permission layer. **Needs a rep.**
2. **Everything purely visual.** The questionnaire rendering in the overlay, the
   progress bar advancing, `Back` preserving answers on screen, the modal
   scrolling inside its card, the `Sending…` disabled state, the story page
   intact behind a closed overlay, and the dark-mode seam the Dev flagged as a
   known issue. The *state* behind each of these is verified (JSDOM + the
   restored suite); the *pixels* are not.

Both are browser work, and §0 explains why no browser was available.

## Cleanup (protocol §8)

Everything this run created in production was deleted and the deletion verified:
2 engagement links, 2 assessment requests, 2 readouts, 3 form drafts, 2 cases,
4 tasks, 2 contacts, 1 opportunity, 1 account. A re-query for
`%Kestrel Vale%` / `qa-d11%` across all eight object types returns **0 rows**.
The org's assessment-request total is back to its pre-QA baseline and `RDO-0008`
is still `Published`. The throwaway JSDOM test file was deleted; `git status` is
clean and `npm test` is green without it. The temporary baseline git worktree was
removed.

The one **intentional** production change left in place is the
`GTM_Assessment_Config.Default` CustomMetadata deploy from §5 — it re-deployed
the record already in source and left the org's `Resume_Link_Base_URL__c` value
intact, which was the point of the test.
