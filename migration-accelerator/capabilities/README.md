# Platform capability manifests

Structured, machine-readable descriptions of what a marketing platform *does*, held
as data rather than prose so that assessment questions, readout callouts, and
adapter specs can all be generated from one source of truth.

```
capabilities/
  README.md              <- this file
  platforms/
    hubspot.yaml         <- HubSpot Marketing Hub, as a migration SOURCE
```

## Which schema these follow

`ma-migrator/capabilities/schema/capability.schema.json` — JSON Schema Draft-07,
loaded and validated by `ma-migrator/capabilities/loader.py`
(`load_capability()` → jsonschema validation → the `CapabilityManifest` Pydantic
envelope).

The two manifests already in that repo are the structural precedent:

| File | Role | What we borrowed |
|---|---|---|
| `ma-migrator/capabilities/platforms/eloqua.yaml` | source platform | overall shape — a source manifest describes what the estate *has* |
| `ma-migrator/capabilities/platforms/sfmc.yaml` | target platform | `gap_patterns[]` shape: `pattern` / `status` / `severity` / `category` / `issue` / `gloss` / `workaround` / `manual_steps` |
| `ma-migrator/docs/specs/tier-2/sfmc-next-target-adapter.md` §5 | target (MC Next) | the `verification_required: true` convention for facts that may have moved |

`hubspot.yaml` validates clean against the schema (0 errors, Draft-07).

## Why these live in this repo, for now

The product owner wants HubSpot platform knowledge captured here while the
`gtm-offerings` assessment work is live. **These files are intended to move to
`ma-migrator/capabilities/platforms/` once the two teams align.** They are written
to drop into that directory unchanged — same schema, same file naming, same
gap-pattern vocabulary, and internal path references written relative to the
`ma-migrator` repo root so they read correctly after the move.

Nothing here is loaded by any running code today.

## Reading `hubspot.yaml`

- **`adapter_status` is `none`.** There is no HubSpot source adapter in `ma-migrator`
  or in this repo; the MVP source matrix is Eloqua + SFMC. The manifest describes
  the *platform*, not a shipped connector. It is stated in the top-level
  `description` and again under `infrastructure.manifest_status`, and it is itself
  filed as a blocker gap pattern (`no_hubspot_source_adapter`) so it cannot be
  quietly dropped from a readout.
- **`verification_required: true` means "working assumption".** HubSpot's tier
  gating, rate limits, and product names change frequently. Flagged entries must be
  confirmed against a live tenant or current docs before they drive anything
  client-facing. `infrastructure.verification_policy.highest_risk_unverified` lists
  the ones most likely to bite.
- **Gap-pattern severity is stated per target where it differs.** `severity` carries
  the worst case for schema conformance; a non-schema `severity_by_target` field
  narrates the split between classic SFMC Engagement and Marketing Cloud Next.
  Several gaps are materially harder on MC Next (no scripting language, no Data
  Extensions), and a couple are easier (native Activation Limits).
- **`infrastructure.sources_consulted`** separates what was web-verified on
  2026-09-06 from what is unverified secondary-source recall.

## Schema fit notes — feedback for the schema owners

Working through HubSpot surfaced four places where
`capability.schema.json` did not fit cleanly. None blocked authoring; all four
produced compromises worth knowing about.

1. **`additionalProperties: false` at the top level leaves nowhere for an object
   catalog, an extraction posture, or manifest provenance.** The schema's only
   extensible slots are `capabilities` (`additionalProperties: true`) and
   `infrastructure`. So `hubspot.yaml` puts the object catalog and the extraction
   posture under `capabilities.object_catalog` / `capabilities.extraction`, and
   manifest metadata (`adapter_status`, verification policy, sources consulted)
   under `infrastructure`. Both are semantic stretches. **Suggested change:**
   promote `object_catalog`, `extraction`, and `adapter_status` to first-class
   top-level properties.

2. **There is no first-class `adapter_status`.** A capability manifest and a shipped
   adapter are different things, and the schema cannot distinguish "the platform
   can do this" from "we can extract this". For Eloqua and SFMC they happen to
   coincide; for HubSpot they do not, and the distinction is the single most
   important thing to keep straight in a readout. An enum
   (`none` / `spec` / `alpha` / `ga`) at the top level would make it structural
   rather than a comment.

3. **`gap_pattern.severity` is a single value, but severity is target-dependent.**
   A source-platform gap has a severity *per target*. HubL is major against classic
   SFMC (AMPscript is a comparable rewrite target) and closer to a blocker against
   MC Next (no scripting at all). We encoded the worst case in `severity` and added
   a free-text `severity_by_target` alongside — `additionalProperties: true` on
   `gap_pattern` allowed it, but it is invisible to any consumer. **Suggested
   change:** `severity_by_target: {<platform_id>: <severity enum>}`.

4. **`verification_required` is a convention, not a schema property.** The MC Next
   manifest established it in prose and comments; nothing enforces or types it.
   Given how much of a source manifest is recalled product knowledge, it deserves
   to be a declared boolean on capability nodes and gap patterns, so a validator can
   count unverified entries and a readout can refuse to assert them.

## What project-conduit models that this schema does not

`project-conduit/packages/profiles/src/types.ts` holds the same idea in TypeScript —
platform knowledge as declarative data — with a `PlatformProfile` of `objectCatalog`,
`capabilities`, `extractionRecipe`, `defaults`, `migrationWaves`, and `auditRules`.
Per the brief, this is recorded here rather than folded into a hybrid schema.

Four Conduit concepts are genuinely missing from `capability.schema.json` and are
worth considering:

- **`objectCatalog[]` with a `cmmGroup` classifier.** Conduit types each native
  object into `dataModel` / `contentAssets` / `audiences`. That classification is
  what lets a generic engine plan work for any platform. `hubspot.yaml` groups the
  catalog by hand (`crm_data_model`, `audiences`, `automation`, `content`,
  `consent_and_identity`, `campaigns_and_measurement`) with no shared vocabulary,
  so nothing can consume the grouping. Note the accelerator has a natural
  counterpart already: ADR-0015/0017's three capability lanes.

- **`extractionRecipe[]`.** An ordered, named list of extraction steps, each tied to
  a `sourceType`. `hubspot.yaml` describes the API surface as a flat map under
  `capabilities.extraction.apis`, which says what is *reachable* but not in what
  order or with what dependencies. An ordered recipe would be directly useful as
  adapter spec input — which is one of this file's two stated jobs.

- **`defaults` (out-of-box objects to skip).** HubSpot ships a large set of
  HubSpot-defined contact properties, default lifecycle stages, and default
  pipelines that a migration should *not* re-create. There is no schema slot to
  declare them, so a naive inventory over-counts the estate — the number that ends
  up in a scoping conversation. This is the Conduit concept with the most immediate
  practical value.

- **`migrationWaves` with explicit gates.** Ordered phases with exit criteria. The
  accelerator carries sequencing in the Assess → Blueprint → Plan → Execute lifecycle
  and in per-engagement plans, not in the platform manifest — arguably the right
  place for it, but the *platform-specific* sequencing constraints (HubSpot examples:
  extract property history before decommissioning; get private-app scopes approved
  before the extraction window; run the site form scan before scoping forms) currently
  have nowhere to live except prose inside `manual_steps`.

`auditRules` is the one Conduit concept that does not obviously transfer — the
accelerator's equivalent lives in the flow runtime and the assessment instrument,
not in the manifest.

## Related files

- `migration-accelerator/instrument/supplements/hubspot_context.yaml` — the two
  unscored HubSpot scope probes in the assessment instrument (`sequences_ownership`,
  `reporting_signoff`). Both map to gap patterns in `hubspot.yaml`
  (`sequences_out_of_scope`, `reporting_no_port_path`) and are cross-referenced from
  them.
- `ma-migrator/docs/specs/tier-2/site-form-scanning.md` §C.4.2 — the HubSpot form-embed
  detection signatures. The only place HubSpot is instrumented in the accelerator
  today, and the reason the site form scan is the first move on a HubSpot engagement.
