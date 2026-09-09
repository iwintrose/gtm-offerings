# TASK SCOPE — ISSUE #offering-instrument-construct-integrity

## 1. Requirements Breakdown

- **Target Objective:** Close the gap between "an offering exists in the
  GTM Offering App" and "an offering has a scored assessment instrument."
  Today these are two disconnected constructs: an offering is a real record
  (`GTM_Offering__mdt`) created only through the app's own UI
  (`gtmContentHome` / `gtmContentManager`), but an instrument is just a
  filesystem directory under `migration-accelerator/instrument/<offering-key>/`
  that `scripts/build-instrument.py` will happily compile and deploy for
  **any** directory name containing a `dimensions.yaml` — confirmed in
  `offering_dirs()`, which derives the offering list purely from the
  filesystem, with no cross-check against `GTM_Offering__mdt`. That means an
  instrument (and therefore a scored assessment) can exist for an "offering"
  that was never created through the app — a rogue offering, in the user's
  words. The fix must make the instrument a construct *of* the GTM Offering
  App (tied to a real Offering record), not an independent file tree that
  happens to share naming conventions with one.
  Separately: `migration-accelerator/capabilities/` is **not** offering or
  instrument data — its own README states it's reference material for
  authoring conversations (platform capability knowledge to inform building
  an instrument), staged temporarily before moving to a different repo
  (`ma-migrator`) entirely. It must be clearly represented as non-authoritative
  context, not left where it can be mistaken for part of the offering/
  instrument construct.
- **System Component Impacted:**
  - `scripts/build-instrument.py` (`offering_dirs()`, `build_offering()`) —
    the compile step that currently trusts any directory name.
  - `migration-accelerator/instrument/<offering-key>/` — the YAML source
    tree itself; per ADR-0007 this is deliberately one directory per
    offering, so the fix is about *validating* that structure against the
    app, not necessarily relocating it.
  - `GTM_Offering__mdt` / the offering-creation flow (`gtmContentHome`,
    `gtmContentManager`, `GtmPageContentController`,
    `GtmOfferingCreationTest.cls`) — the real, in-app source of truth for
    "this offering exists."
  - `gtmInstrumentAuthor` (the Instrument Editor LWC) — per ADR-0007 this
    already carries a dead `@api offeringKey` stub; whether the Architect's
    fix runs through this UI or through a build-time check touches it.
  - `migration-accelerator/capabilities/` — needs a decision on where
    reference-only authoring material like this belongs so it stops looking
    like part of the deployable offering/instrument structure.

## 2. Code Dependency Checklist

- [ ] Modifying GUS Tool Surface? Not directly — flag as an open question
      for the Architect only if `capabilities/`-style reference material was
      ever intended to feed a GUS authoring tool rather than a human author.
- [x] Altering Custom Metadata? Likely — the fix probably adds a
      cross-check (build-time, deploy-time, or in-app) so `Offering_Key__c`
      values stamped by `build_offering()` can't reference an offering that
      doesn't exist in `GTM_Offering__mdt`. Author any such rule in the YAML/
      build script per existing convention — do not hand-edit generated
      `GTM_Assessment_*` XML.
- [ ] Introducing database fields? Possibly not — `GTM_Offering__mdt`
      already exists as the real offering registry; this looks like a
      missing *validation*, not missing schema. Architect to confirm.

## 3. Plan Acceptance Criteria

- **Success Metric:** It is no longer possible for
  `scripts/build-instrument.py` to compile and deploy a scored instrument
  for an offering-key directory that has no corresponding
  `GTM_Offering__mdt` record — either the build fails loudly, or offering
  creation and instrument authoring become the same in-app action so the
  disconnect can't occur. `migration-accelerator/capabilities/` is moved or
  clearly marked so it can't be read as offering/instrument data.
- **Target Test Target:** `python3 scripts/build-instrument.py --check`
  (extended with the new cross-check), `GtmOfferingCreationTest.cls`, and
  `python3 scripts/check-references.py` (repo-layout/inventory audit) as the
  regression baseline.
