# UNIT_SCOPE_NOTE.md — Architect narrowing of TASK_SCOPE.md for this worktree

This worktree's `TASK_SCOPE.md` is the full BA v1 scope (both Initiative A
and Initiative B, plus open design questions). Per
`docs/architecture/adr/0010-gtm-offerings-settings-tab-is-one-tab-with-sections.md`
(read this first), this worktree is **Unit 1 only**:

- New `GTM_Offerings_Settings` tab shell (`gtmOfferingsSettings` LWC,
  internal nav rail, no settings logic of its own).
- Migrate the existing `GTM_Readout_Approval_Settings` tab/LWC in as
  Section 1. Retire (delete) `GTM_Readout_Approval_Settings.tab-meta.xml`
  and its `GTM_Offering_Admin` tabSettings entry; add the new tab's entry
  in its place. `GtmReadoutApprovalSettingsController` and
  `GTM_Readout_Approval_Settings__c` are unchanged.

**Out of scope for this worktree** (sequenced as separate future
worktrees per ADR-0010's Sequencing section — do not build them here):
- Unit 2: Claude/GUS settings section (`GTM_Agent_Settings__c` wrap).
- Unit 3: `GTM_Notification_Settings__c` + six lifecycle wiring points +
  `CustomNotificationType`. Blocked on a human decision (New Assessment
  Request auto-close trigger moment) not yet made.

Do not implement Section 2/3 content here even though the container is
built to hold them — leave clearly-labeled placeholder/empty sections at
most, if the nav rail needs to visually demonstrate extensibility, per
Developer's judgment; do not invent Section 2/3 behavior.
