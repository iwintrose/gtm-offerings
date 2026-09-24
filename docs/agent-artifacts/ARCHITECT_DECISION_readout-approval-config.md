# Architect Decision — issue-readout-approval-config

## Decision: Option B (fully custom self-approve path + new audit-log object)

The Approval Process metadata (`GTM_Readout__c.GTM_Readout_Approval.approvalProcess-meta.xml`)
was inspected directly. Findings:

- `assignedApprover`/`nextAutomatedApprover` are fixed at deploy time; there is
  no mechanism for an approval step to read an org-configurable value (e.g. a
  Hierarchy Custom Setting) at submit time and choose "manager" vs. "owner" as
  the approver in a single step. The only way to make Option A's routing data
  a driven quantity is to add a second approval step/process gated by entry
  criteria on a formula field that surfaces the Custom Setting via
  `$Setup.GTM_Readout_Approval_Settings__c.Self_Approval_Enabled__c`, with the
  new step's `assignedApprover` type `relatedUserField` pointing at `OwnerId`
  (this part is metadata-feasible).
- The genuinely open question under Option A — whether the platform actually
  permits a user to action a `ProcessInstanceWorkitem` assigned to themselves
  (self-approval of one's own submitted request) — is **not verifiable by
  inspection**; it requires a live functional test. This org (`gtm-dev`) is
  treated as Production per `CLAUDE.md` §"Environment Configuration" with **no
  staging environment**, so validating that unknown means experimenting with
  the real Approval Process metadata against live prospect-adjacent data, with
  a non-trivial chance of needing to unwind a second ApprovalProcess/step if
  self-assignment turns out to be blocked or behaves unexpectedly (e.g.
  auto-reassignment to the next hierarchy approver instead of stopping).

Given that risk profile, Option B is the sound choice:

1. **Zero regression risk to the existing (working, audited) manager path.**
   The current `GTM_Readout_Approval` ApprovalProcess is left completely
   untouched. Manager-mode behavior, `GtmReadoutApprovalHandler`'s
   `Status__c`-transition-keyed logic, and `ProcessInstance`/
   `ProcessInstanceStep` all continue exactly as documented in the existing
   header comments.
2. **No dependency on unverified platform behavior in a no-staging,
   production-only org.** Self-approve mode is new, isolated Apex that never
   touches `Approval.process()`; there is nothing to discover the hard way
   about self-assigned work items.
3. **Audit trail is explicit and equally strong in both modes**, satisfying
   the user's non-negotiable requirement without relying on platform
   behavior that hasn't been confirmed to even support this configuration:
   - Manager mode: `ProcessInstance`/`ProcessInstanceStep` (unchanged).
   - Self-approve mode: new `GTM_Readout_Approval_Log__c` (actor, timestamp,
     readout lookup, at minimum), inserted by the new self-approve Apex path
     — mirroring `GtmReadoutApprovalHandler.snapshotApprovals`'s
     best-effort-insert pattern (log failure via `System.debug`, never roll
     back the approval itself for a logging failure).
4. **`GtmReadoutApprovalHandler.isApprovalTransition`/`stampApproval`/
   `snapshotApprovals` are Status__c-transition-keyed, not
   trigger-source-keyed** (see its own header: "an admin who sets Status__c
   by hand... gets the identical behaviour"). This means the new self-approve
   Apex path can safely set `Status__c = 'Approved'` directly and get
   `Approved_Content__c`/`Approved_Data__c`/`Approved_By__c`/`Approved_Date__c`
   stamping and `GTM_Readout_Version__c` snapshotting for free, with no
   changes needed to that handler or its trigger. Developer should rely on
   this rather than duplicating that stamping logic in the new self-approve
   method.

## What Developer builds

- `GTM_Readout_Approval_Settings__c` — Hierarchy Custom Setting (mirrors
  `GTM_Agent_Settings__c`'s shape), field `Self_Approval_Enabled__c` (Checkbox).
- `GTM_Readout_Approval_Log__c` — new Custom Object: `Readout__c` (Lookup to
  `GTM_Readout__c`), `Approved_By__c` (Lookup to User or the running user's
  Id captured directly — Developer to pick the simpler of the two, consistent
  with `Approved_By__c` on `GTM_Readout__c` itself), `Approved_Date__c`
  (Datetime).
- New Apex path (e.g. `GtmReadoutController.selfApproveReadout` or similar,
  restoring the shape of the removed `approveReadout()` but this time paired
  with the log insert) — used only when
  `GTM_Readout_Approval_Settings__c.getInstance().Self_Approval_Enabled__c`
  is true, and only for the record's owner. When the setting is false, the
  existing `submitForApproval` platform path is unchanged and self-approve is
  not offered.
- New tab: `GTM_Readout_Approval_Settings` (or Architect/Developer-agreed
  name) as a plain `<CustomTab>` + `lwcComponent`, following
  `GTM_Analytics.tab-meta.xml` / `GTM_Content_Manager.tab-meta.xml` exactly
  (no Visualforce, no `startsWith`).
- Permission-set grants across all 5 sets per `CLAUDE.md` §6.1 and the BA's
  checklist in `TASK_SCOPE.md` §2 — in the same change, not a follow-up:
  - `GTM_Offering_Admin`: full CRUD/FLS on both new objects; tab visibility
    Visible.
  - `GTM_Offering_User`: no direct object grant needed for the toggle read
    (goes through the `ReadoutDetail` Apex DTO); tab visibility Hidden
    (routing config is an admin action per the user's own framing — "GTM
    Offering Admin" holds this kind of setting today, per
    `GTM_Agent_Settings__c` precedent).
  - `GTM_Content_Manager`/`GTM_Content_Admin`/`GTM_Guest`: no grant, tab
    visibility Hidden (not in the `GTM_Content_Manager` app / not
    guest-facing).
- `gtmReadoutReview.js` ~line 236-237: replace the
  "check the email/bell/Approval History" copy with toggle-aware inline
  status (who/what mode it's waiting on) and, when self-approve is enabled
  and the viewing rep is the owner, an inline action to approve from that
  screen.
