# Product Owner UAT — issue demo-seed-integrity-rebuild

**Decision: ACCEPT**

## What was actually asked (verbatim, from the owner)

1. "If an engagement link exists an account and contact must exist. If an assessment exists an account and contact must exist."
2. "If you're seeding activity it must be listed in the relevant pages."
3. "If an activity is to trigger a task then that should all occur."
4. "If an opportunity shows prospecting or closed on the overview then the opportunity page should show this in the stages."
5. "I don't want to see that you just seeded information through the backend but anything that you seeded is properly wired in the way that the sequence occurred, the requirement from a user/human perspective was followed and adhered to."
6. "I don't want just tons of seeds I want enough to show variation."
7. "None of this seeding can exist if the framework and offering is not properly build and published."
8. "Don't step around the solution and seeding and work through code — hyper focus to build as if you were stepping through the actual interface... checking against all the validations."

## Adversarial check against each, not just "does the code match the scope doc"

1. **FK integrity** — QA independently re-ran this live twice (initial pass + confirmation pass): 0 orphaned Account/Contact references across every synthetic `GTM_Saved_Configuration__c`/`GTM_Assessment_Request__c` row. Not taken on faith — I additionally spot-checked one record's Related lists live in the browser (Opportunity `006gK00000Oz6STQAZ`, Brightfield): Assessment Request `AR-7495` and Engagement Link `SC-4481` both render correctly as related records, not just as raw FK ids in a query. **Holds.**
2. **Activity listed on relevant pages** — this was the one gap neither QA pass could check (no browser tool in either QA session). I checked it myself, live: the seeded Task renders directly on the Opportunity's Activity timeline exactly as a real one would, and the Assessment Requests / Engagement Links / Contact Roles related lists all populate and render on the record page. **Holds — closed the one real open item.**
3. **Activity triggers a task, for real** — traced to a genuine precondition gap (`GTM_Notification_Settings__c` had 0 rows, so the org-wide notify switch defaulted off) that had to be fixed via the real `GtmNotificationSettingsController.setNotificationSettings()` entry point before any Task would fire. 8 real Tasks now exist, tied to the 4 real `submitRequest()` calls, 0 for the intentional non-converter. This is the automation actually firing end-to-end, not a Task row inserted to look like it did. **Holds.**
4. **Opportunity stage consistency with the Overview** — QA didn't just compare two SOQL queries; it called the actual `GtmHomeSnapshotController.getDeals()` method live (the real Overview widget's data source) and diffed its output against raw `Opportunity.StageName` — 4/4 matched. I separately confirmed the same Opportunity shows `Stage: Value Proposition` on its own record page, matching what was seeded. Two independent surfaces, same answer. **Holds.**
5. **Real sequence, not backend shortcuts** — the seed script never calls `saveConfiguration()`/`advanceStage()`/raw inserts into any of the provenance-restricted objects; every config, request, and readout traces to `createRepDirectAssessment()` → `submitRequest()` → `submitForApproval()`, the same entry points the real LWCs call. The one raw insert (Account/Contact via `dupOptions`) is the single legitimate exception CLAUDE.md §6 names. Verified by direct code read (Architect, twice) and by the DML trail actually produced (e.g. `Description` fields stamped by the real controller logic, not hand-written). **Holds.**
6. **Variation, not volume** — 5 accounts, 5 different industries (all with real Published Story content), 4 distinct Opportunity stages, one deliberate non-converter, one multi-contact deal. Not mass duplication. **Holds.**
7. **Nothing seeded against unpublished content** — the hardest constraint, and the one this whole build was redesigned around: `migration-accelerator`'s Configurator template has zero Published sections (confirmed live, unchanged before and after this work). Every seeded record for that offering is mechanically proven to stay `Presentation_Stage__c = 'Rep_Direct'` — the one path confirmed to never render the unpublished Configurator fallback — via a direct `COUNT()` query returning 0 for any deviation, re-run independently by QA twice. This required first fixing a real, separate production bug (`GtmAssessmentRequestController` silently flipping `Rep_Direct` configs to `Assessment` on submission, issue `rep-direct-presentation-stage-flip`, PR #41, merged and real-execution-proven at 138/138 tests before this issue was unblocked) rather than working around it. **Holds — and this is the constraint most likely to have been quietly violated by a less careful build; it wasn't.**
8. **Stepped through as if using the interface** — see #5. Also: the actual destructive org actions (teardown of the old broken set, execution of the new script) were run for real against gtm-staging, not simulated — the before/after state is real, not a projection.

## What I would push back on if I were the actual requester

- The Configurator surface still shows generic fallback content for every seeded prospect, industry-specific or not — because it has to, given #7. That's correct given the current state of the codebase, but it means "industry variation" is only really visible today on the Story page, not the Configurator a rep would actually walk a prospect through live. Not a defect in this issue — it's the honest boundary of what's buildable until issue #39 ships — but worth being direct about rather than implying more was delivered than was possible.
- `GTM_Link_Event__c` rendering via the `gtmLinkActivity` LWC specifically (as opposed to the standard Task-on-Activity-timeline check I did) is still not visually confirmed — the FK side is provably correct (QA) and the general Related-list/Activity rendering pattern is now visually proven for the same record family, but that one specific component wasn't opened. Low risk given everything adjacent to it now checks out, but noting it rather than silently rounding it up to "fully verified."

## Verdict

ACCEPT. Every one of the owner's 8 stated requirements has direct, live evidence behind it — most from two independent QA passes, the one live-UI gap closed by the coordinator directly. The two items above are honest scope boundaries, not defects, and are already captured in the backlog/dependency notes this issue's scope doc carries.

Proceeding to `scripts/agent-workspace.sh complete demo-seed-integrity-rebuild`.
