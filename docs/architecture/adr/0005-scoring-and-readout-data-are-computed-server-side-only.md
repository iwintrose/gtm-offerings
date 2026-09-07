# ADR-0005 — Assessment and readout scores are always recomputed server-side

**Status:** Accepted

## Context

The assessment questionnaire is filled out by an anonymous, unauthenticated
guest — there is no session, no login, and no way to trust anything the
client sends beyond input validation. `GtmAssessmentRequestController`
already recomputes both scoring axes from the raw answers on submit and
discards any client-supplied score, tier, or basis, including a client claim
of `complexityBasis: "Measured"` (downgraded to `Self-Estimated"`, since
`Measured` is only ever written when a real extract has actually been
scanned server-side). See `docs/runbooks/assessment-instrument.md`, "Scoring
is server-side, always."

That rule has so far been documented as a fact about one controller. It is
really a standing constraint on the whole guest-facing surface, and nothing
currently states it as a rule that *future* scoring or banding features must
also follow.

## Decision

Any feature that scores, tiers, or bands an estate — now or in the future —
must recompute that result server-side from raw inputs and must never trust
a client-supplied score, tier, or basis value as authoritative. This applies
to any new guest-reachable Apex, not just `GtmAssessmentRequestController`,
because the trust boundary (anonymous, unauthenticated guest) is the same
for any surface built on the same pattern.

## Consequences

- A legitimate-looking, internally-consistent client payload claiming a
  pre-computed score is never accepted at face value, even if validating it
  fully would be more expensive than trusting it.
- New scoring/banding features carry the cost of a server-side
  recomputation path; there is no "trust the client, verify later" shortcut
  available to them.
- This does not forbid the client from *displaying* a locally-computed
  preview score to the user before submit — only from that preview being
  treated as authoritative once it reaches the server.
