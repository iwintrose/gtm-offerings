# Runbook — the public readout link (`/readout`)

> This describes the `GTM_Accelerator1` site, which is not the currently-live
> site (`GTM1`) — see ADR-0006 and `docs/backlog.md` D9.

How a published `GTM_Readout__c` becomes a working link a BD rep can send a
prospect, and what a human has to do in the org that source metadata cannot do
for them.

## The link shape

```
https://<site-domain>/gtmaccelerator/s/readout?token=<Public_Link_Token__c>
```

The token is the value `GtmReadoutController.publishReadout` mints on the
Draft → Approved → Published transition, and clears again on
`unpublishReadout`. Nothing else in the URL identifies the customer.

**Why a query param and not `/readout/<token>`.** `GTM_Accelerator1` is an Aura
Experience Builder site (`ChatterNetworkPicasso`). Custom pages there route on a
fixed `urlPrefix` only — path parameters exist for object pages
(`recordDetail`, `recordList`), not for a standalone custom page. A
`/readout/<token>` URL would 404 at the site router before any component
rendered. `c/gtmReadoutView` still parses that shape as a fallback (see
`readTokenFromPath`), so a rewrite rule or an old hand-built link keeps working,
but the canonical, supported form is `?token=`.

## What is in source control

Deployable, no clicking required:

| File | What it is |
|---|---|
| `force-app/main/default/experiences/GTM_Accelerator1/routes/readout.json` | The route: `urlPrefix: "readout"`, `routeType: "custom-readout"`, `pageAccess: "UseParent"` (the site is `isAvailableToGuests: true`, so this inherits public access — same as `configurator` and `choose-industry`). |
| `force-app/main/default/experiences/GTM_Accelerator1/views/readout.json` | The page body: a `forceCommunity:section` wrapping `c:gtmReadoutView`, plus a `forceCommunity:seoAssistant` in `sfdcHiddenRegion` carrying `<meta name="robots" content="noindex, nofollow, noarchive">` so readouts never land in a search index. |
| `force-app/main/default/permissionsets/GTM_Assessment_Guest.permissionset-meta.xml` | Grants the guest `GtmReadoutPublicController` Apex class access — the single permission the page needs. |
| `force-app/main/default/queues/GTM_Readout_Triage.queue-meta.xml` | The **Unassigned Readouts** queue. Owns readouts *and their review cases* when a submission has no resolvable rep — see below. |
| `force-app/main/default/objects/Case/fields/Readout__c.field-meta.xml` | The Case → readout lookup. The review case and the recipient comment thread hang off this. |
| `force-app/main/default/objects/Case/listViews/GTM_Readout_Reviews.listView-meta.xml` | The **Readout Reviews** Case list view — the native counterpart to the custom card list. |
| `force-app/main/default/approvalProcesses/GTM_Readout__c.GTM_Readout_Approval.approvalProcess-meta.xml` | The approval process. Draft → Pending Approval → Approved. |
| `force-app/main/default/workflows/GTM_Readout__c.workflow-meta.xml` | Its three `Status__c` field updates, and nothing else. |
| `force-app/main/default/triggers/GtmReadoutApprovalSync.trigger` | Copies the draft into `Approved_Content__c` and snapshots it on approval — the bit a field update cannot do. |

Deploy with the rest of the bundle:

```bash
sf project deploy start \
  -d force-app/main/default/experiences/GTM_Accelerator1 \
  -d force-app/main/default/experiences/GTM_Accelerator1.site-meta.xml \
  -d force-app/main/default/lwc/gtmReadoutView \
  -d force-app/main/default/permissionsets/GTM_Assessment_Guest.permissionset-meta.xml
```

`ExperienceBundle` deploys as a whole bundle — deploying the two new JSON files
alone is not supported. The target org must already have the `GTM Accelerator`
site; this metadata adds a page to it, it does not create it.

## What a human still has to do

These steps are org state, not source metadata. Skip any one of the first four
and the link returns a login screen or an empty page; skip a later one and the
review case, its notifications, or the approval routing will not work.

1. **Publish the site.** Setup → Digital Experiences → All Sites → **GTM
   Accelerator** → *Builder* → **Publish**. An ExperienceBundle deploy updates
   the site's draft; guests see nothing until it is published. Do this after
   every deploy that touches `experiences/GTM_Accelerator1`.

2. **Confirm the page is public.** In Builder, ⚙ *Settings* → *Pages* →
   **Readout** → *Page Access*. It should read **"Public — inherited from site"**
   (that is what `pageAccess: "UseParent"` deploys as). If it shows *Requires
   Login*, switch it back to inherit and republish.

3. **Verify the old `GTM_Readout__c` grant is gone.** A previous version of
   `GTM_Assessment_Guest` granted the guest Read **and Create** on
   `GTM_Readout__c`; this branch removes it. A permission-set deploy replaces the
   set, so the grant should disappear on its own — but confirm once per org:
   Setup → Permission Sets → **MA Assessment Guest** → *Object Settings* →
   `GTM Readouts` should list **no** permissions. Remove it by hand if it
   survived.

4. **Assign `MA Assessment Guest` to the site's guest user.** Builder → ⚙
   *Settings* → *General* → *Guest User Profile* → *Guest User* → **Permission
   Set Assignments** → add **MA Assessment Guest**. Guest profiles are not in
   this repo's source, so a fresh org or scratch org needs this by hand once.
   If the assignment already exists, the redeployed permission set picks up
   `GtmReadoutPublicController` automatically — nothing to re-click.

## Unassigned readouts (the triage queue)

`GtmReadoutController.Generator` resolves an owner in order: Opportunity owner →
assessment request owner → running user → `GTM_Assessment_Config.Default.
Default_Readout_Owner__c` → the **Unassigned Readouts** queue
(`GTM_Readout_Triage`). A direct booking — no Engagement Link, no Opportunity,
submitted by the site guest user — resolves none of the first four, so it lands
on the queue. It used to produce no readout at all.

`GTM_Readout__c` is Private, so ownership is the access grant: **a rep sees
queue-owned readouts only if they are a member of the queue.** Queue membership
is org state, not source metadata, so it needs doing by hand once:

5. **Add members to Unassigned Readouts.** Setup → Queues → **Unassigned
   Readouts** → *Queue Members*. Add the public group, role or users who triage
   incoming assessments. With no members, orphan readouts are created and
   nobody can see them.

A rep claims one by changing its Owner to themselves from the record page — the
standard queue-claim action. That is all it takes; no extra step.

**No rep contact block on a queue-owned readout.** `GtmReadoutPublicController`
derives `repName` / `repEmail` / `repPhone` from `OwnerId`, and only accepts an
active non-Guest `User`. A Queue is a `Group`, so the guard rejects it and the
published page renders the readout content with the contact section **absent** —
not a placeholder, not the queue's name, not the approver. This is intentional:
there is no person to name yet. The contact block starts working the moment a
rep claims the record. Covered by
`GtmReadoutPublicControllerTest.aQueueOwnedReadoutRendersWithNoContactBlockAtAll`.

**Queue-owned review cases.** `fileReviewCase` files the readout's Case against
the same owner, queue included, and the queue declares `Case` as a supported
object. This is the concrete reason the review **Task** was replaced by a review
**Case**: queue-owned Tasks additionally need Setup → Activity Settings → *"Let
users assign tasks to queues"*, which is org state this repo cannot deploy, so
the old Task silently failed to be created in exactly the situation (nobody
assigned) where somebody most needed telling. Queue-owned Cases need no such
preference.

## The review case and the recipient's comments

Every generated readout gets one **Case**, owned by the same rep (or the same
queue) and pointing at the readout through `Case.Readout__c`. It is the rep's
work item — status, ownership, reporting, notifications — and it is the
conversation.

**The recipient can comment.** On the published page the prospect picks one of
the readout's seven sections (Verdict, Context, Scorecard, Capability gaps,
Findings, The path, Next steps) and writes a comment. It is posted through
`GtmReadoutCommentController.submitComment(token, section, body)` and lands on the
review case as a native **`CaseComment`**, bodied like this:

```
[Recipient comment — Scorecard]
The integration score looks generous to us.
```

The section travels as a prefix because `CaseComment` accepts no custom fields
at all, and a field on `Case` could not carry it either — one case holds many
comments across different sections, so there is nowhere for a case-level field to
vary. The alternative was a custom object, which is the net-new build this design
exists to avoid.

**The rep replies natively**, from the Case Comments related list on the case.
There is no rep-side comment UI in this repo, and `gtmReadoutReview` only links
out to the case.

**The thread is one-way.** The guest page can write to it and can never read it
back, and comments are stored with `IsPublished = false`. That is deliberate: the
same thread is where reps write internal notes to each other, and there is no
reliable native way to tell an internal note from a reply meant for the prospect.
A rep who wants the prospect to have their answer sends it to them — which is
what `SuppliedEmail` on the case is for.

**What a human has to do in the org for reps to get told:**

6. **Turn on case comment notifications.** Setup → Service → Support Settings →
   **Notify Case Owner of New Case Comments** (and *Notification on new case
   comments to case owner*). Without it a recipient comment lands silently and a
   rep only sees it when they open the case. Support Settings is org state, not
   source metadata.

7. **Put the new relationship on the layouts.** Neither `Case` nor
   `GTM_Readout__c` has a page layout in this repo's source, so the org's own
   layouts govern and this cannot be deployed: add **GTM Readout**
   (`Case.Readout__c`) and the **Case Comments** related list to the Case layout,
   and the **Cases** related list to the GTM Readout layout. Without the first
   two a rep can reach the case from the editor's link but cannot see what it
   relates to or read the thread. In Lightning, Case Comments is available as a
   related list; the Feed-based experience does not replace it here, because
   recipient comments are written as `CaseComment` records.

8. **Optional — add a "GTM Readout" Case Origin value** and set it on the case.
   `fileReviewCase` deliberately leaves `Origin`, `Status`, `Priority`, `Type` and
   `RecordTypeId` at the org's own defaults, because writing a picklist value an
   org does not have throws on insert, inside a guest submit transaction. Adding
   the value and then setting it is a supported follow-up.

### Guest security posture for the comment write

Same contract as the read path, deliberately:

| | |
|---|---|
| Guest object permissions on `Case` / `CaseComment` | **None**, and there is a "do not re-add" comment in the permission set saying so. `GtmReadoutCommentController` is `without sharing`, so its SOQL/DML runs in system mode and needs none. Object permissions would open an LDS/`uiRecordApi` path onto client conversations. |
| Token check | The identical SOQL `WHERE Status__c = 'Published' AND Public_Link_Token__c = :token`, in the WHERE clause, never fetch-then-check. A Draft/Pending/Approved readout's token, a revoked token and a token that never existed are all refused. |
| Existence leak | Every failure from the token lookup onward — bad token, unpublished, no review case, throttled, DML error — returns the **byte-identical** refusal string. Only input-shape failures (empty comment, over-length, unknown section) get a specific message, and they are evaluated **before** the token is looked at, so no specific message can depend on whether a token resolves. |
| Sanitising | HTML tags stripped, control characters removed, blank-line runs collapsed, a leading `=`/`+`/`@` quoted out (a case exported to CSV is a real path for this text), body capped at 3 000 characters. |
| Throttle | Max 5 recipient comments per readout per 10 minutes, 100 lifetime, counted by `CreatedById` on the case's comments so rep replies never throttle the prospect. Refusals are silent — a "too fast" message is only reachable with a valid token, so it would be an oracle. |

**Known limit, stated plainly:** the throttle bucket is per *readout*, not per
visitor, because a token is the only identity an anonymous caller has. It bounds
storage growth and stops a flood; it does not stop a determined holder of a valid
token from spending that readout's own quota, and it cannot distinguish two
people sharing one link. Per-IP throttling needs an edge/WAF or Platform Cache,
neither of which is deployable from this repo.

## Approval

Approving is a real **Approval Process** (`GTM_Readout_Approval`), not a button in
our UI.

```
Draft ──submit──▶ Pending Approval ──approve──▶ Approved ──publish──▶ Published
  ▲                      │                          │                     │
  └──── reject/recall ───┘                          └── return to draft ──┘
                                                         (after unpublish)
```

* A rep clicks **Send for approval** in `gtmReadoutReview`
  (`GtmReadoutController.submitForApproval`, which calls `Approval.process`).
* The request routes to **the record owner's manager**. That is the only
  assignment that needs no org-specific metadata, so it deploys the same way
  into every org. An org that wants a review queue or a named approver changes
  the step's `assignedApprover`; no Apex depends on who the approver is.
* Submitting **locks the record** (`recordEditability: AdminOnly`), which is the
  point — the content a manager is reading cannot change under them.
  `saveDraftContent` refuses with that explanation rather than letting the DML
  fail with a platform lock error.
* Approving, rejecting and recalling are platform operations.
  `ProcessInstance` / `ProcessInstanceStep` are the audit trail;
  `gtmReadoutReview` reads them rather than trusting `Status__c`, so a field
  update that failed to fire leaves a stale label, not a wrong state machine.
* Both final actions **unlock** the record — an approved readout that stayed
  locked could not be published, unpublished or returned to draft.

**Approve and Publish stay separate, and that is a product requirement.**
Approval marks the readout approved and stops. `publishReadout` is what mints
`Public_Link_Token__c`, and it is still a deliberate rep action. A manager
approving must never, by itself, put a live link in a prospect's inbox. There is
no publish action anywhere in the approval process; do not add one.

**What a human has to do in the org:**

9. **Give reps a Manager.** Setup → Users → each rep → *Manager*. With no manager
   the submission fails and the platform says so; the readout stays a Draft.
10. **Claim unassigned readouts before submitting them.** Approval routes to the
   owner's manager and a queue does not have one, so `submitForApproval` refuses
   a queue-owned readout with "claim it first".

### Are `GTM_Readout_Version__c` snapshots still needed?

**Yes — keep them.** `ProcessInstance` proves *who* approved and *when*, and
field history (now on, for `Status__c`, `Approved_By__c`, `Approved_Date__c`,
`Published_Date__c`) proves when each state change happened. Neither preserves
the approved *content*: field history does not retain values for Long Text /
Rich Text Area fields, and `Approved_Content__c` is overwritten by the next
approval cycle. The version snapshot is the only thing that answers "prove what
was approved on the 3rd".

`Public_Link_Token__c` is deliberately **not** history-tracked: field history
retains old values, and a revoked token surviving in a history table would
resurrect the link `unpublishReadout` exists to kill.

## Recovering from a mis-approval

`GtmReadoutController.returnToDraft` sends an **Approved** readout back to
**Draft** so a rep can edit it again — surfaced as *Return to draft* in
`gtmReadoutReview`, behind a confirmation because it discards the approved lock.
While a readout is **Pending Approval** the way back is *Recall request*, not
*Return to draft*; the platform's recall action is what returns it to Draft.

It **refuses a Published readout outright.** A published readout's token is live
in a prospect's inbox; it has to be unpublished first, which is what revokes the
token. So the route back from Published is *Unpublish* → *Return to draft*, and
there is no state in which a Draft readout still has a resolvable public link.

The approval is snapshotted to `GTM_Readout_Version__c` (with
`Status_At_Snapshot__c = 'Approved'`) *before* `Approved_By__c` /
`Approved_Date__c` are cleared, so what was approved and when stays provable
after the revert.

## Smoke test

Run in a private/incognito window so you are genuinely unauthenticated.

| # | Do this | Expect |
|---|---|---|
| 1 | Publish a readout as a rep, copy `Public_Link_Token__c` | a token exists |
| 2 | Open `/gtmaccelerator/s/readout?token=<token>` | the readout content and the rep's name/email/phone |
| 3 | Open `/gtmaccelerator/s/readout` with no token | the generic "not found" panel, **no Apex call** |
| 4 | Open the same URL with one character of the token changed | the *identical* "not found" panel |
| 5 | Unpublish the readout, reload step 2's URL | the *identical* "not found" panel |
| 6 | Take a Draft or Approved readout's token (rep view) and open it | the *identical* "not found" panel |
| 7 | Unpublish, *Return to draft*, then reopen step 2's URL | the *identical* "not found" panel |
| 8 | Publish a readout still owned by **Unassigned Readouts** and open its link | the readout content, and **no** contact block at all |
| 9 | Claim that readout as a rep, reload | the same content, now with that rep's name/email/phone |
| 10 | On step 2's page, pick a section and send a comment | "Thanks — your comment has been sent…", and the comment on the readout's review case, prefixed with the section |
| 11 | Send six comments inside ten minutes | the sixth is refused with the **same** wording as step 4's failure — no mention of a limit |
| 12 | Unpublish, then try to comment on step 2's URL again | the generic refusal, and no new case comment |
| 13 | Reply to the comment from the Case in Salesforce, then reload the prospect page | your reply is **not** visible to the prospect |
| 14 | Send a comment containing `<script>alert(1)</script>` and `=HYPERLINK(...)` | stored with the markup stripped and the formula quoted out |

Steps 3–7 must be visually indistinguishable, and so must steps 11 and 12's
refusals against a plain bad-token refusal. Anything that tells the visitor
*why* a token failed leaks that a readout is being prepared for a given deal —
see the class comment on `GtmReadoutPublicController`.

## Guest security posture

The one guest-reachable path onto `GTM_Readout__c` is
`GtmReadoutPublicController.getPublishedReadout(token)`. It is `without sharing`
and filters `Status__c = 'Published' AND Public_Link_Token__c = :token` in the
SOQL `WHERE` clause, and it returns a wrapper class rather than an SObject.

That is why `GTM_Assessment_Guest` grants **no** object or field permission on
`GTM_Readout__c`: Apex SOQL runs in system mode for CRUD/FLS, so the read needs
none, and granting object read would open a second, token-free path (LDS /
`uiRecordApi`, list views, record pages) onto the same data. The permission set
carries an inline comment saying not to re-add it. `GTM_Link_Event__c` follows
the same pattern — Apex class access, no object permission.

`GtmReadoutController` (the rep-facing `with sharing` class holding submit,
publish, unpublish) is deliberately **not** in the guest permission set. Apex
access is per class, so adding it would hand anonymous callers the whole state
machine.

The guest's second class grant, `GtmReadoutCommentController`, is the write-side
twin of the same contract — see *Guest security posture for the comment write*
above. `Case` and `CaseComment` object permissions are absent for exactly the
same reason `GTM_Readout__c`'s are, and the permission set carries a "do not
re-add" comment saying so.

## Should `gtmReadoutsOverview` be dropped?

**No — but it is no longer the only option, and that is the point.** Now that
every readout has a Case, the shipped **Readout Reviews** Case list view
(`objects/Case/listViews`) gives filtering, sorting, inline edit, mass owner
change and the standard *Accept* from the queue, for free — none of which the
custom card list has, and none of which it should grow. Reps who want a working
list should use it.

The custom list stays because it is doing something the list view is not: it
carries the offering's visual identity and it deep-links into `gtmReadoutReview`,
which is where a readout is actually written and published. Deleting it would
cost the offering its look and its entry point to save a component that is
already paid for. Revisit if it ever starts accumulating filter/bulk features —
that is the signal it is being asked to be a list view, and it should lose the
argument at that point.
