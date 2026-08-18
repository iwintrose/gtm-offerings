# gtm-offerings

GTM and sales-enablement material for Publicis Sapient Salesforce offerings — positioning docs, pitch decks, and client-facing configurable leave-behinds. This is a build repo, not a hosting target: the client-facing output eventually gets deployed to its own hosted site (Phase 2, not started).

## Structure

Each offering gets its own folder, named for the offering (renameable — the name is a variable, not a fixed identity):

```
gtm-offerings/
  [offering]/
    story.html        "[Offering] — The Story": internal positioning notes —
                       what the offering does, why it matters, who wants it,
                       how to use it, and the GTM story underneath all four.
                       Not for external distribution.
    ...                (industry content + client-facing configurator land here
                       once built — see Phase 1 plan below)
  index.html           Root "Choose your offering" chooser — shared across every
                       offering, shown once more than one exists. (not built yet)
```

First offering: `migration-accelerator/`.

## Phase 1 vs. Phase 2

**Phase 1 (current):** static, reviewable pages — the offering's Story doc, a root
offering chooser, an industry chooser scoped to the offering, and a client-facing
configurable output page. Personalization runs client-side (the same pattern used
in the existing Migration Blueprint prototype); shareable via Claude artifacts for
internal review.

**Phase 2 (next, once Phase 1 is shown functionally to leadership and the team):**
a real hosted backend — a rep's configuration publishes to an actual site with a
database, version history, and rollback, so a client link stays live and updates
without the rep re-sending it. This is the link-service already scoped separately;
Phase 2 is that spec, actually built.

## Content grounding

Offering content is written from the actual codebase(s) behind it, not aspirational
copy — for Migration Accelerator, that means `ps-salesforce/ma-migrator` (the
spec-governed core: ingestion, planning, drafted build specs) blended with
`ps-salesforce/project-conduit` (audit scoring, live execution with rollback, the
Figma-to-email pipeline). Where the two disagree on maturity, the more honest,
more conservative claim wins — see the caveats inside each `story.html`.
