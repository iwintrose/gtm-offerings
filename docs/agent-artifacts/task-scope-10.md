# TASK SCOPE — ISSUE #10

## 1. Requirements Breakdown

- **Target Objective:** Let a rep type a natural-language query into a filter bar (e.g. "TD Bank links from last month", "show me anything stuck in review") and have GUS translate it into the *existing* structured filter state (`gtmFilterBar` / `gtmFilterUrlState` config), instead of requiring manual dropdown/chip picking. This was raised by the owner on 2026-09-20 as a follow-up idea explicitly deferred out of the `compact-filters` scope (`docs/agent-artifacts/task-scope-compact-filters.md` — open question 4 there, "search box," was declined: "Neither tab has a text search in the bar today... Add one only if you name what it searches"; this issue is that naming, but the mechanism is GUS, not a raw text search).
- **System Component Impacted:** Apex (new `GtmAppTool` implementation) + LWC (`gtmFilterBar` affordance, `gtmGusUtility` allow-list) + architecture docs. No Experience Cloud, no YAML instrument, no new schema.

### Verified current state (read on `main`)

1. **`gtmFilterBar` has two consumers only** (confirmed in `docs/agent-artifacts/task-scope-compact-filters.md`, itself grep-verified): `gtmRepLinkFinder` (Pages tab, one filter — `stage`, 7 chip options) and `gtmReadoutsOverview` via `gtmAssessmentsTableModel.buildFilterConfig` (Assessments tab, six filters: `preset`, `status`, `tier`, `readout`, `range`, `offering`, plus `account`/`contact` search-type filters found live in code):

   ```
   force-app/main/default/lwc/gtmAssessmentsTableModel/gtmAssessmentsTableModel.js:96-126
   96: { key: 'preset', label: 'Ready to book', type: 'toggle', param: 'c__apreset', more: true },
   97: { key: 'status', label: 'Status', type: 'chips', multi: true, param: 'c__astatus', options: STATUS_OPTIONS },
   98: { key: 'tier', label: 'Readiness tier', type: 'chips', multi: true, param: 'c__atier', options: TIER_OPTIONS },
   99: { key: 'readout', label: 'Readout', type: 'chips', multi: true, param: 'c__areadout', options: READOUT_OPTIONS, more: true },
   100: { key: 'range', label: 'Submitted', type: 'date-range', param: 'c__arange' },
   102: key: 'offering', ... param: 'c__aoffering',
   111: key: 'account', ... param: 'c__aacct',
   122: key: 'contact', ... param: 'c__acontact',
   ```

2. **GUS already has one precedent app tool that drives a filter**, `GtmStageFilterAppTool` (`force-app/main/default/classes/GtmStageFilterAppTool.cls`), registered in `GtmAppAgentSurface.registeredTools()`:

   ```
   force-app/main/default/classes/GtmAppAgentSurface.cls:38-42
   private static List<GtmAppTool> registeredTools() {
       if (testTools != null) return testTools;
       List<GtmAppTool> registered = new List<GtmAppTool>();
       registered.add(new GtmStageFilterAppTool());
       return registered;
   }
   ```

   Its contract (`docs/architecture/gus-stage-filter-tool.md`) is: one required enum param `stage` mapped from `GtmLinkStageService.STAGE_KEYS`; zero DML, zero callouts, never throws; blank/unknown input returns `{"error":...}`, never a guess; on success returns a `changes.pageEffect` of shape `{type:'navigate', label, apiName:'GTM_Pages', state:{c__stage:'<key>'}}`; **the rep must click a button to actually navigate — GUS never navigates unprompted** (`GtmStageFilterAppTool.cls:76-77`, confirmed in source). This is the direct mechanical precedent for issue #10: a new `GtmAppTool` (e.g. `GtmFilterByQueryAppTool`) that maps free text to the *same* filter-key/value shape `gtmFilterBar`'s config already uses, returning a `pageEffect` the rep clicks to apply — not a tool that mutates page state directly.

3. **The GUS host has a client-side allow-list gating which state keys any tool's `pageEffect` may write**, in `gtmGusUtility.js`:

   ```
   force-app/main/default/lwc/gtmGusUtility/gtmGusUtility.js:13-14
   GTM_Pages: ['c__stage'],
   GTM_Assessments: [],
   ```

   `GTM_Assessments` is present but its permitted-param list is **empty** — confirmed by the Jest fixture list (`gtmGusUtility.test.js:129`, `['state on a tab that takes none', { apiName: 'GTM_Analytics', state: {...} }]` and the `GTM_Assessments: []` line itself). Today NO GUS tool can push any Assessments filter param through this host, even if an Apex tool computed one. This is the single largest gap between "GUS already does something adjacent" and "GUS can drive the Assessments filters," and it lives in `gtmGusUtility.js`, not in Apex.

4. **The chat surface itself.** `gtmGusUtility` is a **Utility Bar item scoped to the GTM Offerings app** (`docs/architecture/gus-utility-bar-host.md` §1/§2), a persistent chat panel via `c-gtm-agent-chat mode="app"`, wired to `CurrentPageReference` for page context, calling `GtmAgentProxyController.chatOnApp`. It is NOT inside `gtmFilterBar` and is NOT the same component as the configurator's floating `gtmAgentBubble` (explicitly a separate, untouched conversation per that doc). There is currently no natural-language input control living inside `gtmFilterBar` itself — the closest existing NL entry point is the utility-bar chat.

### Open UX fork (real tradeoff — flag, do not silently pick)

**Option A — route through the existing `gtmGusUtility` utility-bar chat (recommended default).**
Rep already has this panel open/available on every app tab; "Ask GUS" becomes: type "TD Bank links from last month" into the existing chat, GUS calls the new tool, replies with a summary + one button ("Show these in Pages" / "Show these in Assessments") whose click both navigates and applies the URL filter state via the existing `pageEffect`/`agentaction`/`buildNavigateArgs` pipeline (identical to `find_links_by_stage` today). Zero new UI surface on `gtmFilterBar`; only the Apex tool + the `GTM_Assessments` allow-list entries are new. Matches the "propose vs commit" grain — nothing changes until the rep clicks.

**Option B — a dedicated "Ask GUS" input embedded inside `gtmFilterBar` itself.**
Puts the NL box exactly where reps already look for filters (Jira/compact-filters ethos), and could apply the filter inline (no navigate/click step) since the bar already owns `values`/`filterchange`. But it requires: a new `gtmFilterBar` prop/slot (contract change to a component the `compact-filters` work just finished, see B.2 "frozen contract" language in `docs/architecture/gtm-filter-bar.md` — anything beyond the additive `more` field there was explicitly out of scope for that issue), a second Apex-calling code path independent of `chatOnApp`/`GtmAppAgentSurface` (or plumbing that surface's response back into `filterchange` events), and duplicates the chat UI GUS already has (loading states, error text, "not set up yet" messaging) instead of reusing it.

**Recommendation: Option A.** It reuses the proven `find_links_by_stage` -> `pageEffect` -> click-to-navigate pattern end to end, requires no `gtmFilterBar` contract change, and keeps the "never silently apply a filter" acceptance bar (below) easy to satisfy because the existing UI already forces a click before anything happens. Option B is a legitimate future enhancement (inline apply, no click) but is a materially bigger and riskier change to a component that was just stabilized; call this out to the owner as an explicit fork rather than assuming B.

### Mechanism (given Option A)

- **New Apex tool**, tentatively `GtmFilterByQueryAppTool implements GtmAppTool`, registered as a second line in `GtmAppAgentSurface.registeredTools()` (alongside `GtmStageFilterAppTool`; `toolDefinitions()` already dedupes by name, first-registration-wins, so name collisions are self-guarding).
- It does **not** call `GtmAgentProxyController` directly and does **not** invent a new controller entry point — it plugs into the *existing* `chatOnApp` -> `GtmAppAgentSurface.executeTool` dispatch, exactly like the stage tool. `gtmFilterBar` never calls Apex or GUS directly; the flow is chat -> tool -> `pageEffect` -> `gtmGusUtility` allow-list check -> `NavigationMixin.Navigate` with state built via `buildFilterUrlState`/`buildNavigateArgs`-shaped `c__` keys -> `gtmFilterBar`'s consumer reads `values` back off the URL, unchanged from how a manual chip click works today.
- The tool's LLM-facing definition should describe the target tab (`GTM_Pages` vs `GTM_Assessments`) and the *known* vocabulary for that tab's filter keys (below) so the model maps text to keys/values, not free-form strings, mirroring how `find_links_by_stage`'s prompt fragment (§5 of its doc) hand-maps phrases like "went quiet" to the `quiet` enum.

### Pages/tabs in scope for v1

`gtmFilterBar` serves exactly two consumers today (verified above): **Pages** (`gtmRepLinkFinder`, single `stage` filter) and **Assessments** (`gtmReadoutsOverview`, six filters). Recommend v1 covers **both**, since:
- Pages/`stage` is nearly free — `find_links_by_stage` already does the hard part (stage vocabulary + `pageEffect` + allow-list entry); a query tool could simply reuse/wrap it for stage-shaped queries, or the new tool could special-case `apiName: 'GTM_Pages'` and directly emit `{c__stage: <key>}`.
- Assessments is where the actual owner ask lives ("TD Bank links from last month" implies account + date; "stuck in review" implies `status`/`tier`) but requires the net-new `GTM_Assessments` allow-list entries (currently `[]`) for whichever param keys v1 supports (`c__astatus`, `c__atier`, `c__arange`, `c__aoffering`, `c__aacct`, `c__acontact` as applicable) — this is a required, not optional, part of implementing Assessments NL filtering, and is itself a small, additive, well-scoped change to `gtmGusUtility.js`'s `ALLOWED_NAVIGATION` map plus its Jest fixtures.
- Overview/Home, Analytics and GTM Content Manager are **not** `gtmFilterBar` consumers (confirmed by the `compact-filters` scope's consumer grep and by `gus-utility-bar-host.md`'s explicit Content Manager exclusion) and are out of scope for v1.

### Filter vocabulary GUS's tool needs, and graceful failure

- **Pages (`stage`):** `GtmLinkStageService.STAGE_KEYS` — `sent, engaged, started, submitted, quiet, hot, not_opened` — already documented with phrase mappings in `gus-stage-filter-tool.md` §5. Reuse verbatim.
- **Assessments:** `STATUS_OPTIONS`, `TIER_OPTIONS`, `READOUT_OPTIONS` constants and the `offering`/`account`/`contact` option shapes live in `gtmAssessmentsTableModel.js` (lines 96-126, read above) — the tool's Apex-side enum validation must be built against these same option `value`s, not re-derived or guessed, exactly as the stage tool validates against `GtmLinkStageService.STAGE_KEYS` rather than a hand-typed list (parity test precedent: `GtmStageFilterAppToolTest`'s "seven-key parity with the service" test). Date phrases ("last month," "this week") need an explicit, tested mapping to the `range` filter's preset tokens or `{from,to}` ISO shape (`docs/architecture/gtm-filter-bar.md` §4) — do not let the LLM emit an arbitrary date string.
- **Account/contact/company name matching** ("TD Bank") is free text against `account`/`contact`/`company` fields — the Apex tool should resolve/validate a best-effort match server-side (e.g. against existing accessible records under sharing) rather than passing the LLM's guess straight into a URL param unchecked; if there's no confident match, the tool must return `{"error":...}` (or an "ambiguous, did you mean X/Y" text-only reply) and NOT emit a `pageEffect` — same zero-guess discipline as `find_links_by_stage`'s handling of blank/unknown stage.
- **Ambiguous/unrecognized queries never silently apply a wrong filter**: mirror the stage tool's rule exactly — invalid/ambiguous input returns an error payload with no `pageEffect`; GUS's reply is text-only; nothing navigates until a `pageEffect` exists AND the rep clicks its button. This double gate (tool refuses to guess; rep must click) is the acceptance bar for "never silently wrong."
- **Multiple simultaneous filters in one query** ("TD Bank + last month" implies both `account` and `range` on Assessments): v1 may support composing 2-3 well-understood filter keys in one `pageEffect.state`, but this needs an explicit test matrix, not open-ended combination — cap v1's understood patterns rather than promising a general NL query language.

### GUS tool-surface rules checked (AGENTS.md §1)

Zero-DML rule applies and is satisfiable: like `GtmStageFilterAppTool`, the new tool only *reads* (matching against known option lists / light SOQL lookups for account/contact resolution, `with sharing`) and returns a `pageEffect` describing URL state — it performs no DML, no callout, never throws. Filtering is a read-side UI/URL state change, not a persisted write, so the "propose vs commit" pattern for mutating tools doesn't strictly apply, but the analogous "nothing happens until the rep clicks" behavior already built into the `pageEffect`/`agentaction` pipeline provides the same safety property and should be preserved unchanged.

## 2. Code Dependency Checklist

- [x] Modifying GUS Tool Surface? YES — new `GtmAppTool` implementation registered in `GtmAppAgentSurface`. Verified zero-DML/zero-callout rule (AGENTS.md §1): satisfiable following the `GtmStageFilterAppTool` pattern (read-only lookups only, `with sharing`, never throws, no `pageEffect` on invalid/ambiguous input).
- [ ] Altering Custom Metadata? NO. No YAML/`GTM_Assessment_*` metadata touched; this is filter UI state, not instrument content.
- [ ] Introducing database fields? NO. No new objects/fields; the tool reads existing Assessment/Link/Account/Contact data already covered by existing sharing rules and permission sets. (The `GTM_Assessments` allow-list change in `gtmGusUtility.js` is a client-side JS map edit, not a schema or permission-set change.)

## 3. Plan Acceptance Criteria

- **Success Metric:**
  1. A rep on the Pages tab can type a stage-shaped query (e.g. "show me links that went quiet") into the existing `gtmGusUtility` chat and get a reply with a "Show these in Pages" button that, when clicked, navigates and sets `c__stage` exactly as `find_links_by_stage` does today (regression: existing stage tool and its tests remain green and unmodified in behavior).
  2. A rep on the Assessments tab can type at least the two named v1 query patterns — (a) an account/company name plus a relative date range (e.g. "TD Bank links from last month"), and (b) a status/tier phrase (e.g. "anything stuck in review") — and get a reply with a "Show these in Assessments" button that, when clicked, sets the corresponding `c__a*` param(s) and the Assessments table filters/reloads accordingly.
  3. Ambiguous or unrecognized queries produce a text-only GUS reply with no `pageEffect` and no navigation — verified by an explicit negative test case per pattern (unknown company name, unrecognized status phrase, garbage input).
  4. `GTM_Assessments` entry in `gtmGusUtility.js`'s `ALLOWED_NAVIGATION` map is extended from `[]` to the specific `c__a*` keys v1 supports, with new Jest fixtures paralleling the existing `GTM_Pages`/`c__stage` allow-list tests (including a negative case for a still-disallowed key).
  5. Zero DML/zero callouts verified via `Limits` in the new tool's test class (parity with `GtmStageFilterAppToolTest`'s pattern), plus enum/option-value parity tests against the *same* `STATUS_OPTIONS`/`TIER_OPTIONS`/`READOUT_OPTIONS`/`STAGE_KEYS` source constants (no hand-duplicated vocabulary).
  6. No new object/field/permission-set change required (tool reads only); if account/contact resolution surfaces any sharing gap for a rep vs. admin, it must be called out, not silently widened.
  7. QA validates live in the browser on `gtm-staging`, on both the Pages tab and the Assessments tab, including the negative/ambiguous-query cases, per the "QA must always validate live in the browser" project rule.
- **Target Test Target:** New Apex test class mirroring `GtmStageFilterAppToolTest` (e.g. `GtmFilterByQueryAppToolTest`), plus extended `force-app/main/default/lwc/gtmGusUtility/__tests__/gtmGusUtility.test.js` (new `GTM_Assessments` allow-list fixtures). No `gtmFilterBar` or `gtmFilterUrlState` Jest changes expected under Option A (their contracts are unchanged) — Architect to confirm this holds once the tool's actual output shape is finalized.

### Open questions / decisions for the owner or Architect (not guessed here)

1. **Option A vs B (UX entry point)** — recommended A above; needs an explicit owner/Architect sign-off since B is a real, materially different-cost alternative.
2. **Exact v1 query pattern list** — this scope names two illustrative Assessments patterns (account+date, status/tier phrase) plus the Pages stage reuse; the Architect should fix the exact, testable pattern set before implementation rather than leaving it open-ended, per the "not a full NL query language" boundary.
3. **Account/contact name resolution strategy** — exact/fuzzy match, case sensitivity, and behavior on multiple matches (e.g. two "TD Bank" accounts) needs a concrete rule; not resolved here.
4. **Date-phrase vocabulary** ("last month", "this week", "last 30 days") mapping to the `range` filter's preset tokens vs. `{from,to}` — needs an explicit table before implementation, analogous to `gus-stage-filter-tool.md` §5's phrase-to-enum table.
