# Readout fixtures

`hubspot-to-mce.json` is a whole `Readout_Data__c` snapshot — the exact shape
`GtmReadoutModel.buildJson` produces — for one illustrative assessment. It is
used by the component tests and by `scripts/readout-preview.js`, which renders
the real component into a static page so the design can be looked at.

**The scenario.** Commercial Metals Company (CMC) — a real, publicly listed
steel and metals business, HQ Irving TX, selling to contractors, distributors
and construction projects across the Americas, Europe and Asia. Only that
public business profile is real. **Every estate figure, score, integration,
gap and finding below is illustrative** and the snapshot marks itself as such:
`posture.illustrative` is `true`, which is what turns the ILLUSTRATIVE FIGURES
badge on. Nothing here is a measurement of a real tenant.

**The migration.** HubSpot Marketing Hub Enterprise → **Salesforce Marketing
Cloud Engagement**. A handful of named use cases point at Marketing Cloud Next
and are recorded as forward-looking; MC Next is *not* the target. There is no
working MC Next target adapter in either repo, so presenting it as the
destination would be a promise nothing can keep.

**The gaps are not invented.** Every row in `gaps` is lifted from
`reference/ma-migrator-capabilities/platforms/hubspot.yaml` — its `pattern`,
`status`, `severity`, `issue` and `workaround` — read against the classic-SFMC
half of each pattern's `severity_by_target`. If that manifest changes, this
fixture is stale and should be re-derived from it rather than edited to taste.

**What this fixture is for.** It is the test of the architecture as much as of
the rendering: the component contains no scenario literals, so switching this
file to a different source, target or client has to be enough to change what
the readout says. If it ever isn't, the split between the prose half and the
measurement half has not gone far enough.
