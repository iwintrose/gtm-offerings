# TASK SCOPE — ISSUE #102-e-gus-file-extraction

## 1. Requirements Breakdown

- **Target Objective:** Issue #102 deliverable E asks that GUS (the readout-editor
  assistant) be able to read the *contents* of pdf/docx/pptx/xlsx files a BD rep
  attaches to a readout via `lightning-file-upload`, instead of only reporting
  "I can see this file but cannot read it." Today `GtmReadoutAgentFiles.cls`
  already extracts text from plain-text formats (txt/md/csv/tsv/json/xml/html/log/
  yaml/rtf) via `Blob.toString()`, and has a documented `Extractor` interface /
  `EXTRACTORS` map / `register()` seam at lines 71-83 specifically left empty for
  this purpose. The issue's own "cheap interim if extraction is out of budget"
  fallback is: keep the honest refusal, persist the file list via a cacheable
  Apex method over the existing query at `GtmReadoutAgentFiles.cls:97-115` wired
  into `gtmReadoutAssist.js`'s `connectedCallback()`, and default the GUS panel
  open (`isOpen = true`) when the readout's Draft has rep notes or attachments.

  **⚠️ Contested premise — this is NOT actually decision-free for the full
  extraction path, contrary to how #102 frames it.** The issue text itself
  says implementing real pdf/docx/pptx/xlsx parsing requires "an external
  endpoint and a RemoteSiteSetting" because Apex has no native binary-document
  parser (`GtmReadoutAgentFiles.cls:1-25` documents this explicitly: "Apex has
  no document parsers... There is no way to extract their text in Apex without
  an external service"). I verified this against the repo: `force-app/main/
  default/remoteSiteSettings/` has exactly four entries (Anthropic_API, two
  logo hosts, one avatar host) and there is no `namedCredentials/` directory
  at all — no extraction vendor, library, or endpoint is wired up anywhere in
  this codebase. **Choosing and provisioning a third-party document-extraction
  service is a vendor/cost/security decision** (which service, what it costs,
  and — because these are BD-uploaded prospect/deal files — whether sending
  binary attachments to an external processor is acceptable) that only a
  human stakeholder can make; it is exactly the kind of decision the other
  nine gated #102 deliverables are blocked on, even though #102 labels E
  "narrow, independent." I am not guessing an answer to that question.

  Additionally, even once a service is chosen, wiring it in is **not just a
  new `Extractor` implementation** — `GtmReadoutAgentFiles.cls:23-25` documents
  that `extractAll()` runs *inside* the Claude tool-use loop
  (`GtmAgentProxyController.runLoop`, `cls:155`), between callouts, and Apex
  forbids nested callouts in that position. A callout-based extractor must
  therefore run **before** `runLoop` starts and have its result passed in —
  i.e. a change to `GtmAgentProxyController`'s call shape (its public method
  signatures at `cls:113` and `cls:145`, and how `runLoop` receives
  pre-extracted text), not merely registering a class. That is real
  engineering work but it is gated behind the vendor decision above, so it is
  out of scope for what can ship today.

  **What genuinely is narrow, independent, and decision-free** is the "cheap
  interim" the issue itself names: (1) a cacheable Apex method that returns
  the readout's attached-file list (name/extension/readable-or-not) without
  re-running `extractAll()`'s full describe-and-truncate pass, (2) wiring that
  into `gtmReadoutAssist.js`'s `connectedCallback()` so the file list persists
  across a panel toggle/reload instead of only reflecting the current
  session's `uploadedFiles` array, and (3) defaulting `isOpen = true` when the
  Draft already has `Rep_Context_Notes__c` or existing attachments. **This
  scope covers only that interim — not pdf/docx/pptx/xlsx text extraction
  itself**, which remains blocked pending a stakeholder decision on an
  external extraction vendor.

- **System Component Impacted:** Apex (`GtmReadoutAgentFiles.cls` — new
  read-only cacheable method; no change to `EXTRACTORS`/`Extractor`/
  `register()`, which stay exactly as documented placeholders) and LWC
  (`force-app/main/default/lwc/gtmReadoutAssist/gtmReadoutAssist.js` /
  `.html` — call the new method from `connectedCallback()` and drive
  `isOpen`'s default from notes/attachment presence).

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? **NO** — this scope does not touch
      `GtmAgentToolSurface.cls`, `GtmAgentProxyController.cls`, or the
      `EXTRACTORS` map/`Extractor` interface. It only adds a read-only file-list
      query method to `GtmReadoutAgentFiles.cls` and a UI default-state change.
      If a later task tackles real extraction, it *will* modify the tool
      surface's call shape and must verify the zero-DML rule in AGENTS.md §1
      at that time — flagged here for the Architect's awareness, not actioned.
- [ ] Altering Custom Metadata? **NO** — no `GTM_Assessment_*` or other custom
      metadata is touched by this scope.
- [ ] Introducing database fields? **NO** — no new fields, objects, or schema.
      The new Apex method reads existing `ContentDocumentLink`/`ContentVersion`
      data already covered by the readout's own sharing model (per
      `GtmReadoutAgentFiles.cls`'s `with sharing` + `LinkedEntityId` gating).
      No permission-set changes are required.

## 3. Plan Acceptance Criteria

- **Success Metric:** Reopening (or toggling) the GUS panel on a readout with
  prior file attachments shows the persisted file list (name, extension,
  readable/unreadable) without requiring the rep to re-upload in the current
  session; the panel defaults open (`isOpen = true`) on load when the Draft
  has non-empty `Rep_Context_Notes__c` or at least one existing
  `ContentDocumentLink`, and defaults closed otherwise, matching current
  behavior for readouts with no rep context. Behavior for extraction of
  pdf/docx/pptx/xlsx is explicitly unchanged — those formats continue to
  report the existing `UNREADABLE_REASONS` refusal text, and this task must
  not claim or imply extraction was added.
- **Target Test Target:** New/updated Apex test coverage in
  `GtmReadoutAgentFilesTest.cls` (or equivalent existing test class for this
  file — verify actual class name in the worktree) for the new cacheable
  list-only method, plus updated Jest coverage in
  `force-app/main/default/lwc/gtmReadoutAssist/__tests__/gtmReadoutAssist.test.js`
  for the `connectedCallback()` file-list load and the new `isOpen` default
  logic.
