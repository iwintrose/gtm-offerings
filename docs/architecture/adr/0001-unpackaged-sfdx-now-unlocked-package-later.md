# ADR-0001 — Unpackaged SFDX now, unlocked package later

**Status:** Accepted

## Context

Everything under `force-app/` is standard Salesforce DX source format, and
has been developed and deployed that way from the start via `scripts/deploy.sh`
and the `sf` CLI directly against the org — there has never been a separate
"export" or "package" step. The question of whether to move to a real
package (for reuse across multiple client orgs) has come up more than once
as the solution has matured.

Packaging this codebase — specifically an **unlocked** package, not a
managed one, since this is an internal accelerator and not ISV/AppExchange
IP that needs hiding — would qualify with no restructuring: the code is
already namespace-clean and organized under one `force-app/` tree. But it
needs a Dev Hub-enabled org and a namespace decision, and a namespace is not
free and not reversible once picked. More importantly, a package cannot
carry everything this solution depends on: `ExperienceBundle` (the two
Experience Cloud sites), standard profiles, and the org-specific state
covered in `docs/runbooks/fresh-org-deploy.md` (site membership, guest user
assignment, My Domain, the Claude API key) are all outside a package's
boundary. Packaging today would move roughly 80% of the solution and still
leave the hard 20% as manual steps — the same manual steps a package was
supposed to save.

## Decision

Stay on unpackaged SFDX + `scripts/deploy.sh` (or `scripts/deploy-fresh-org.sh`
for a from-zero org) as the only deploy path, until there is a real second or
third org to install this into. Revisit packaging only when the cost of
re-running the manual org-state steps by hand, repeatedly, exceeds the cost
of committing to a namespace. If and when that happens, it is an **unlocked**
package — this is an internal tool, not something that needs its
implementation hidden from the orgs it's installed into.

## Consequences

- Every new org this solution goes into pays the full manual-steps cost in
  `DEPLOYMENT.md` / `docs/runbooks/fresh-org-deploy.md` — there is no
  version history or upgrade path today, just re-running the deploy script.
- No namespace decision has to be made prematurely, and no namespace cost is
  paid for a single Developer Edition org.
- The `force-app/` tree, the `sf` CLI, and this same deploy workflow remain
  the on-ramp to packaging later — nothing about staying unpackaged today
  forecloses that option.

## References

- `DEPLOYMENT.md` — "If this needs to go to *many* orgs, not just one"
- `docs/runbooks/fresh-org-deploy.md` §2 — "Packaging strategy — and why"
  (the fuller version of this reasoning, including the coexistence-with-a-
  shared-org caveats)
