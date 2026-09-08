# ADR-0008 — The guest assessment is hosted by the engagement link, not by a standalone route

**Status:** Accepted — not yet implemented. Companion implementation plan:
`docs/agent-artifacts/d11-resolution-plan.md`.

Relates to ADR-0005 (scoring is server-side only), ADR-0006 (route
reachability is a property of the live site), ADR-0007 (the instrument is
per-offering). Supersedes nothing.

## Context

`docs/backlog.md` D11: the live `GTM1` site's booking modal
(`gtmConfigBooking`, reached from `gtmConfigurator` on the only live route,
`/configurator`) sends **no `answers` array**. Every real prospect
submission through the live link produces a `GTM_Assessment_Request__c`
with no scored dimensions, a meaningless `Assessment_Score__c` /
`Assessment_Tier__c`, and a readout auto-generated from nothing. The
component that does ask the eight scored questions,
`gtmAssessmentQuestionnaire`, has its only route on `GTM_Accelerator1`,
which is `DownForMaintenance`.

Git history settles what was intended, rather than leaving it to be guessed:

- `c3cde90` / `91481f2` scaffolded `maConfigBooking` as a short "book a
  call" form.
- `14ba345`, `d7b7cc7`, `6978c87`, `29215f4`, `1c502d5` extended it
  incrementally — assessment-request write, prefill, link-event tracking,
  the HMAC submission-token gate, and draft save/resume.
- `552dfb1` ("BD/Sales proposal workflow — stage machine, rich assessment,
  email send") added eleven qualitative BD fields to that same modal —
  budget, pain points, goals, sponsorship, urgency and so on. This is the
  "rich assessment" as a **long form**.
- `dc4ad5d` then built `maAssessmentQuestionnaire` as a **new component on
  a new route**. Its own commit message states the intent without
  ambiguity: *"The long form was never going to be filled in. This is the
  same instrument in digestible steps."* It was a replacement for the
  booking modal's long form, not a second product.
- The swap on the live surface was never done. The replacement was routed
  onto `GTM_Accelerator1` and left there; `GTM1` kept the component it was
  meant to replace.

So this is the "a complete rebuild occurred" case, and the resolution the
rebuild always implied is: the live surface adopts the replacement.

The remaining question was *where* the replacement is hosted. Three
candidates were on the table (D11's own three options). Two of them —
porting `/assessment` onto `GTM1`, or promoting `GTM_Accelerator1` to
`Live` — put the questionnaire on a **standalone page**, and a standalone
page has no way to receive the engagement link's context:

- `gtmAssessmentQuestionnaire`'s `savedRecordId`, `submissionToken`,
  `prospect`, `industryLabel`, `prefillCompany` and `offeringKey` are all
  `@api` properties that are **absent from its `targetConfigs`**, so they
  cannot be set from Experience Builder; and the only URL parameter the
  component reads is `?resume=`.
- A submission with a blank `savedRecordId` makes
  `GtmAssessmentRequestController.resolveConfigContext` return an empty
  `ConfigContext`. That costs the Opportunity link, the Account, the rep
  attribution (`Notify_Email__c`), the `Link_Password__c` gate that
  `validateTokenIfRequired` enforces — and, since ADR-0007,
  `resolveOfferingKey(ctx)` falls through to the hardcoded
  `migration-accelerator` default instead of reading the link's
  `GTM_Saved_Configuration__c.Offering__c`.

That trade is worse than the bug it fixes. Today a real submission scores
nothing, which is at least visibly empty. A standalone-route fix would
score *something*, attributed to nobody, against a guessed offering —
exactly the class of failure ADR-0007 §"hard boundary" was written to
forbid ("a confident score against questions the respondent was never asked
is worse than no score").

Everything the standalone page lacks, `gtmConfigurator` already has and
already passes to `gtmConfigBooking` today: `cfgId` → `savedRecordId`,
`verifyAndIssueToken` → `submissionToken`, `visitSessionId`, `company`,
`industryLabel`, and — via the `getPublicConfiguration` call it already
makes — the link's own `offering`.

## Decision

### 1. The guest assessment is rendered inside `gtmConfigurator`, on the existing `/configurator` route

`gtmConfigurator` replaces its `<c-gtm-config-booking>` child with
`<c-gtm-assessment-questionnaire>`, inside the same overlay, on the same
CTA. `gtmConfigBooking` is retired.

No `force-app/main/default/experiences/` file changes. No new route, no
route moved between sites, no `Network.Status` change on either site.
`GTM_Accelerator1` stays `DownForMaintenance`; its `/assessment` route is
left in place as-is (it is not reachable, and removing it is a separate,
riskier operation governed by `docs/runbooks/experience-site-lifecycle.md`).

### 2. A guest assessment surface must not be reachable without engagement-link context

This is the generalizable rule, and the reason this ADR exists rather than
being a line in a plan file: **any guest-facing surface that writes a
scored `GTM_Assessment_Request__c` must be hosted where the engagement
link's `savedRecordId` is resolvable.** A route that renders the
questionnaire standalone is not a smaller version of the feature; it is a
different, un-attributable one, and it silently defeats the password gate,
the Opportunity linkage and the per-offering instrument resolution at once.

If a standalone assessment route is ever genuinely wanted, it must first
carry `cfgId` as a URL parameter and thread it into `savedRecordId` the
same way `gtmConfigurator` does — and that is a change to make
deliberately, with the token gate re-verified, not a page an author wires
up in Experience Builder.

### 3. The client's offering key comes from the link, not from the page property

`gtmConfigurator.@api offeringKey` is an Experience Builder page property
defaulting to `migration-accelerator`. `GtmAssessmentRequestController`
resolves the offering from `GTM_Saved_Configuration__c.Offering__c`. These
are two independent derivations of the same fact and they can disagree —
and under ADR-0007 a disagreement is not a cosmetic mismatch: the client
would render offering A's questions and the server would score them against
offering B's pack, resolving none of the submitted dimension keys, and
scoring nothing while looking like it scored.

So the effective offering key for the questionnaire is
`getPublicConfiguration(cfgId).offering` when a link is present — the exact
field the server reads — and the page property only for a link-less direct
visit. `gtmConfigurator.loadSavedConfiguration()` already fetches that
record and already has `offering` on the response; it simply does not read
it today.

### 4. One submitted assessment per engagement link, enforced server-side

The existing "cannot resubmit" guard is real but is wired to the path
nobody can reach: `GtmAssessmentRequestController.closeDraft` appends a
terminal `GTM_Form_Draft__c` row carrying `Submitted_Request__c`, and
`GtmAssessmentDraftController.latestOpenRowFor` refuses any resume token
whose newest row has one. That revokes a **resume link**. It does not stop
a second submission, and `gtmConfigBooking` never sends a `draftToken` at
all, so on the live path it never fires.

On the live path the only guard is `gtmConfigurator.hasSubmittedAssessment`,
persisted in `sessionStorage` under `ma-assessment-<cfgId>` — which
survives a refresh in the same tab and nothing else.

`submitRequest` therefore gains a server-side check: a submission naming a
`savedRecordId` that already has a scored `GTM_Assessment_Request__c` is
refused with a plain message, not silently duplicated. This is consistent
with the data that exists today — every `GTM_Saved_Configuration__c` in
`gtm-dev` with any assessment against it has exactly one — so nothing is
being retrofitted onto a shape the org contradicts.

The guard is a **server** rule with a client mirror, not the reverse. The
client mirror stops the prospect wasting fifteen minutes re-answering; the
server rule is what makes the invariant true.

### 5. The eleven BD fields survive the replacement

`painPoints`, `migrationGoals`, `successCriteria`, `budgetRange`,
`contactCount`, `monthlySendVolume`, `internalTeamSize`, `keyIntegrations`,
`decisionMakers`, `executiveSponsorship`, `urgencyDriver` are collected
**only** by `gtmConfigBooking` and are read by
`GtmReadoutController.buildDraftHtml` and `GtmReadoutAgentContext`. A
straight component swap would quietly empty several sections of every
future readout. They move into the questionnaire as one explicitly optional
step, kept out of the scored path — they are BD context, not instrument
answers, and nothing about them may reach a score.

## Consequences

- The live prospect journey becomes: `/configurator` story → CTA → the
  chunked, branching, scored questionnaire in an overlay → server-scored
  request → readout. One surface, one submit path
  (`GtmAssessmentRequestController.submitRequest` remains the single
  guest write path).
- `gtmConfigBooking` is deleted. Its accumulated behaviour is not: the
  overlay chrome, the calendar CTA (`bookingUrl` → "Pick a time in our
  calendar"), the prefill, and the confirmation panel are carried across.
  Its `GtmFormDraftController` "Booking" draft path becomes unused for the
  configurator (the questionnaire uses `GtmAssessmentDraftController`
  instead); the class and its `Draft_Type__c = 'Booking'` rows stay, since
  other callers and existing rows exist — see the plan.
- `GTM_Assessment_Config.Default.Resume_Link_Base_URL__c` is **blank in
  `gtm-dev`** today (verified by query). Once the questionnaire is behind
  `/gtm/s/configurator`, an emailed resume link must carry the link id as
  well as the token, or resuming loses the engagement context this ADR
  exists to preserve. Setting it correctly is a required operational step,
  not a nicety.
- `docs/architecture/overview.md`'s container diagram, and D11 in
  `docs/backlog.md`, both describe the pre-fix topology and need updating
  when this lands.
- ADR-0006 still holds and is not weakened: this decision deliberately
  avoids depending on any route change precisely because reachability is
  org state. The verification step is unchanged — check `Network.Status`,
  don't infer from source.
