# Instrument Editor orientation panel — QA round 1 (independent re-verification)

QA agent, 2026-09-07. Verdict: **APPROVED**.

Scope confirmed: `git diff 7f73c75 6c75bae --stat` touches exactly the four
files under `force-app/main/default/lwc/gtmInstrumentAuthor/` the plan and
Dev's commit message describe (`.html`, `.js`, `.css`,
`__tests__/gtmInstrumentAuthor.test.js`) — nothing outside that directory,
no Apex, no custom metadata.

## What I independently re-verified (not just re-read Dev's report)

1. **Orientation panel, dismiss/persist, `resolutionChainLabel`,
   `pack.resolutionNote`** — read `gtmInstrumentAuthor.html`/`.js`/`.css` in
   full. All wired as the plan (`docs/agent-artifacts/
   instrument-editor-context-plan.md` §2.1–2.3) specifies: `orientationCollapsed`
   read from/written to `localStorage['gtmInstrumentAuthor.orientationCollapsed']`
   inside a try/catch, `resolutionChainLabel` derives from
   `pack.resolutionChain.join(' → ')`, `pack.resolutionNote` rendered verbatim.
   Not dead markup — traced every binding to a real getter/handler.

2. **Reachability caveat text vs. reality.** Queried `Network` in `gtm-dev`
   directly: `GTM` (live site) is `Live`, `GTM Accelerator` is
   `DownForMaintenance` — matches the caveat's claim. Grepped
   `gtmConfigBooking.js` for `answers` — the only hit is a comment; no
   `answers` field is sent in the live booking submit payload, matching
   backlog D11 exactly. The caveat is not softened — it states plainly that
   editing a pack here "does not change what a real prospect sees today."

3. **Resolution chain, called live against `gtm-dev` via `sf apex run`**
   (not trusted from Dev's report):
   ```
   getPack('Oracle Eloqua','Salesforce Marketing Cloud Engagement')
     -> pairKey=eloqua_to_sfmc, resolutionChain=(base, eloqua_to_sfmc),
        version=2026.09.1, note=null
   getPack(null, null)
     -> pairKey=base, resolutionChain=(base),
        note="No target platform was named, so this assessment used the
        base questions. The eight dimensions are the same either way; what
        changes once a target is chosen is how hard some of the top answers
        are to earn, and which platform-specific gaps get named."
   ```
   Non-empty chain confirmed, `pairKey != 'base'` confirmed for a real pair,
   and the undecided-target note text is an exact match, character for
   character, with `UNDECIDED_TARGET_NOTE` in
   `GtmAssessmentInstrument.cls:99-103` and with what `{pack.resolutionNote}`
   renders in the template.

4. **Jest suite** — ran directly (`sfdx-lwc-jest`, then plain `jest` scoped
   to the exact file path for a clean count). **The real count for the file
   in scope is 12 tests, 12 passing, 3 new** (orientation default-expanded +
   dismiss/reload persistence; resolution-chain label; undecided-target
   note) — not "21/21, 4 new" as reported. The 21 figure only appears
   because a *stray, unrelated worktree* — `.claude/worktrees/
   agent-a26c5231ddadc2b1d/`, a stale checkout of a different branch
   (`ma-deploy-work`, 20 commits behind, belonging to other concurrent
   agent work per this task's own framing) — happens to contain an older
   9-test copy of a same-named test file, and a broad `--testPathPattern`
   match picked up both. 9 (stale, no orientation tests) + 12 (real,
   current) = 21. This is an environment artifact, not a defect in Dev's
   code — every one of the 12 real tests passes and the 3 new ones assert
   real rendered DOM output driven by the component's own getters
   (`orientationCollapsed`, `resolutionChainLabel`, `pack.resolutionNote`),
   not tautologies against their own mocks. Flagging the miscount so it
   isn't repeated, not blocking on it — see ticket-style note below.
   Recommend someone clean up the stray `.claude/worktrees/*` dirs so this
   doesn't skew a future count again.

5. **`GtmAssessmentInstrumentTest` / `GtmMigrationPairsTest`** — ran directly
   against `gtm-dev`: **39/39 pass, 100%**, unmodified (consistent with this
   commit touching no Apex).

6. **`GTM_Migration_Pair__mdt` vs `GTM_Assessment_Pair__mdt` counts** —
   queried both directly: `GTM_Migration_Pair__mdt` = **7**,
   `GTM_Assessment_Pair__mdt` = **6**. Independent, as the two-table split
   requires.

7. **Permission-set / FLS claim** — checked specifically, not skipped.
   `resolutionChain`/`resolutionNote` are Apex-computed on `Pack`
   (`GtmAssessmentInstrument.cls:427,429`), not new CMDT fields — the
   underlying SOQL (`GtmAssessmentInstrument.cls:1290,1305`, querying
   `DeveloperName`, `Source_Key__c`, `Target_Key__c`, `Specificity__c`, etc.
   off `GTM_Assessment_Pair__mdt`/`GTM_Assessment_Dimension_Override__mdt`)
   is unchanged by this commit. `GTM_Assessment_Guest.permissionset-meta.xml`
   already grants `customMetadataTypeAccesses` on both types (lines 56-62);
   custom metadata type access in Salesforce is granted at the type level,
   not per-field, so no new grant is needed. No FLS gap.

## Non-blocking note

Dev's self-reported Jest count ("21/21, 4 new") does not hold up against a
clean, scoped test run — see item 4. Real count: 12/12, 3 new. Does not
change the verdict: the code is correct, the 3 new tests are meaningful, and
the inflated number traces to a leftover sibling worktree rather than
anything Dev added. Noting for the record rather than opening a ticket,
since nothing needs to change in `gtmInstrumentAuthor/` to fix it.

## Verdict

**APPROVED.** No functional, wiring, copy-accuracy, or permission gaps
found. Scope stayed inside `gtmInstrumentAuthor/` as instructed.
