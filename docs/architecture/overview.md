# Architecture overview

GTM Offerings is a single Salesforce DX application: two internal Lightning
apps for the reps and content authors who run engagements, and one guest-
facing Experience Cloud site for the prospects on the other end of a link.
The whole build lives in `force-app/`, deploys with the `sf` CLI, and runs in
one org — there is no separate service tier, database, or hosting layer
outside Salesforce. See `CLAUDE.md` for the org, stack, and deploy
conventions; this file is the "what talks to what" map for a reader who
wants the shape before the detail.

## Containers

```mermaid
graph TB
    subgraph guest["Unauthenticated"]
        browser["Prospect browser"]
    end
    subgraph internal["Salesforce-authenticated"]
        rep["BD rep / Content author"]
    end

    subgraph liveSite["GTM1 — LIVE site (Network.Status = Live, gtm/s)"]
        cfgRoute["/configurator route\n(the ONLY route on this site\nbeyond Experience Cloud boilerplate)"]
        cfgComponent["c:gtmConfigurator"]
        inlineBooking["gtmAssessmentQuestionnaire\nembedded modal — the FULL branching,\nscored instrument (ADR-0008 / D11)"]
        inlineReadout["inline readout view\nembedded modal, calls getPublishedReadout directly"]
    end

    subgraph darkSite["GTM_Accelerator1 — NOT LIVE (DownForMaintenance, gtmaccelerator/s)"]
        story["/story route"]
        industry["/industry route"]
        darkCfgRoute["/configurator route"]
        assessmentRoute["/assessment route\ngtmAssessmentQuestionnaire\n(full branching instrument)"]
        readoutRoute["/readout route\ngtmReadoutView"]
    end

    subgraph apps["Lightning apps (internal)"]
        offerings["GTM Offerings app\n(links, readouts, approvals)"]
        contentMgr["GTM Content Manager app\n(instrument + page content authoring)"]
    end

    subgraph guestApex["Guest-reachable Apex"]
        reqCtrl["GtmAssessmentRequestController"]
        draftCtrl["GtmAssessmentDraftController"]
        pubCtrl["GtmReadoutPublicController"]
        commentCtrl["GtmReadoutCommentController"]
    end

    subgraph repApex["Rep-facing Apex (with sharing)"]
        readoutCtrl["GtmReadoutController"]
        savedCfgCtrl["GtmSavedConfigurationController"]
        scoring["GtmAssessmentScoring / GtmEstateComplexity"]
    end

    subgraph automation["Automation"]
        approval["GTM_Readout_Approval\n(Approval Process)"]
        queue["GTM_Readout_Triage queue"]
    end

    subgraph data["Core objects"]
        savedCfg[("GTM_Saved_Configuration__c")]
        assessReq[("GTM_Assessment_Request__c")]
        formDraft[("GTM_Form_Draft__c")]
        readout[("GTM_Readout__c /\nGTM_Readout_Version__c")]
    end

    browser --> cfgRoute
    cfgRoute --> cfgComponent
    cfgComponent --> inlineBooking
    cfgComponent --> inlineReadout
    inlineBooking --> reqCtrl
    inlineReadout --> pubCtrl

    browser -.->|not reachable today\nsite is DownForMaintenance| story
    story --> assessmentRoute
    story --> readoutRoute
    assessmentRoute --> reqCtrl
    assessmentRoute --> draftCtrl
    readoutRoute --> pubCtrl
    readoutRoute --> commentCtrl

    reqCtrl --> assessReq
    reqCtrl --> readout
    draftCtrl --> formDraft
    pubCtrl --> readout
    commentCtrl -.->|creates a Case comment| queue

    rep --> offerings
    rep --> contentMgr
    offerings --> readoutCtrl
    offerings --> savedCfgCtrl
    readoutCtrl --> readout
    readoutCtrl --> approval
    savedCfgCtrl --> savedCfg

    assessReq --> scoring
    scoring --> readout
    approval --> queue
    queue -.->|unclaimed readouts land here| readout

    classDef notLive stroke-dasharray: 5 5,opacity:0.6
    class darkSite,story,industry,darkCfgRoute,assessmentRoute,readoutRoute notLive
```

**Reading the two site boxes.** `GTM1` is the only currently-`Live` guest
site, and its only route is `/configurator`, rendering `c:gtmConfigurator`.
That one component embeds, inline, both the guest assessment
(`c:gtmAssessmentQuestionnaire`, in an overlay, calling
`GtmAssessmentRequestController.submitRequest` directly) and a
published-readout modal (calling
`GtmReadoutPublicController.getPublishedReadout` directly) — there is no
separate `/assessment` or `/readout` page on this site to navigate to.

**That overlay used to hold `gtmConfigBooking`, and that was D11.** The
booking modal sent no `answers` array at all, so every real submission through
the live link produced a request with no scored dimensions and a readout
generated from nothing. ADR-0008 replaced it with the questionnaire in place,
on this same route — deliberately *not* by promoting `GTM_Accelerator1` or
porting the `/assessment` route across, because a standalone page cannot see
the engagement link's `savedRecordId`, and a submission without it is
un-attributable and scored against a guessed offering. `gtmConfigBooking` is
deleted. No route on either site changed.
This is confirmed from source: `gtmConfigurator.js` has no navigation call
to any other route, and no `/story`, `/industry`, `/assessment`, or
`/readout` view exists under `GTM1`'s `ExperienceBundle`. It is **not**
confirmed by actually loading the live page in a browser — browser
automation is blocked in this environment, so treat "embedded and
reachable in principle" as a source-level finding, not an end-to-end one.
`GTM_Accelerator1` (dashed, above) is `DownForMaintenance` — its fuller,
separately-routed story/industry/questionnaire/readout build exists in
source and is deployed, but a real prospect cannot reach it today.

**Known gap, already tracked — and now narrower than it was.** This split —
a fuller build sitting on a site that isn't live, versus a minimal live site —
is the same gap `docs/backlog.md` **D9** ("The Industry Chooser isn't
reachable anywhere live... Not started") tracks for the industry chooser,
generalized to the rest of `GTM_Accelerator1`'s routes. The **assessment** half
of it is closed: the live site now runs the real instrument (ADR-0008), so
what remains stranded on the dark site is the story, industry and readout
routes, not the thing that scores. See
**ADR-0006** for the standing rule this gap motivated: route reachability
has to be verified against the live site's `Network.Status`, not assumed
from source or a passing static check.

Guest traffic never reaches the rep-facing controllers (`GtmReadoutController`,
`GtmSavedConfigurationController`) — Apex class access is granted per class in
the guest permission sets, and only the four guest-reachable controllers above
are in them. Internal users reach the same underlying objects through the two
Lightning apps, `GTM Offerings` (links, readouts overview/manager, approvals)
and `GTM Content Manager` (Content Home, Content Manager, Instrument Author).

## The readout's status lifecycle

`GTM_Readout__c.Status__c` moves through a fixed set of states, gated partly
by Apex (`GtmReadoutController`) and partly by Salesforce's own native
Approval Process — approving a readout never happens inside the rep's editor,
deliberately, so a rep cannot approve their own readout.

```mermaid
stateDiagram-v2
    state "Pending Approval" as PendingApproval
    [*] --> Draft
    Draft --> PendingApproval: submit
    PendingApproval --> Approved: approve
    PendingApproval --> Draft: reject / recall
    Approved --> Published: publish
    Approved --> Draft: return to draft
    Published --> Approved: unpublish
```

`approve` happens off-platform, in Salesforce's own Approval Process UI (email,
bell notification, mobile) — no Apex method drives that edge. Every other edge
is a named method on `GtmReadoutController` (`submitForApproval`,
`recallApproval`, `publishReadout`, `unpublishReadout`, `returnToDraft`).
Published never goes straight back to Draft — the token is live in a
prospect's inbox, so the only way back is Unpublish (which revokes the token
and lands on Approved) followed by Return to draft. Full detail, including
the review-Case and triage-queue mechanics, lives in
`docs/runbooks/readout-public-link.md`.

## The instrument build pipeline

The assessment questionnaire's content — questions, scoring weights, gates,
and branching pairs — is authored as YAML under
`migration-accelerator/instrument/*.yaml`, not hand-edited as metadata.
`scripts/build-instrument.py` compiles that YAML into the custom metadata
records under `force-app/main/default/customMetadata/GTM_Assessment_*`, which
then deploy like any other metadata. Run `python3 scripts/build-instrument.py
--check` to validate the YAML and catch drift between it and the generated
XML before deploying. The full authoring model — the L0–L4 layer system and
`show_when` branching — is documented in
`docs/runbooks/assessment-instrument.md`; this file states only the pipeline
shape.

## The two guest surfaces, and their security posture

**The assessment questionnaire.** The one guest write path onto a submission
is `GtmAssessmentRequestController.submitRequest` — no other guest-reachable
method can create a `GTM_Assessment_Request__c`. A respondent who leaves
mid-form is carried by `GtmAssessmentDraftController` against a separate
`GTM_Form_Draft__c` object, addressed only by an unguessable
`Resume_Token__c` filtered in the SOQL `WHERE` clause — no method on that
controller accepts a record Id. Neither guest-reachable object grants guest
object or field permissions in `GTM_Assessment_Guest`; Apex runs the actual
reads and writes in system mode, and granting object access on top would open
a second, token-free path onto the same data via LDS or list views.

**The published readout.** `GtmReadoutPublicController.getPublishedReadout`
is the only guest-reachable path onto `GTM_Readout__c`, runs `without
sharing`, and filters `Status__c = 'Published' AND Public_Link_Token__c =
:token` in the query itself, returning a wrapper class rather than an
SObject. `GtmReadoutCommentController` is the matching write path, landing
a guest's comment on the readout's review Case. As with the questionnaire,
`GTM_Assessment_Guest`/`GTM_Story_Guest` grant no object or field permission
on `GTM_Readout__c` or `Case` — access is class-level only, and the
permission sets carry inline comments not to re-add it. Full detail,
including the 14-step smoke test, lives in
`docs/runbooks/readout-public-link.md`.
