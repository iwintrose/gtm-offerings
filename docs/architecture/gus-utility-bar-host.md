# GUS utility-bar host and `chatOnApp` (contract)

Status: architect contract (binding). Issue `gus-utility-bar-host`. Sibling that
attaches to it: `gus-stage-filter-tool`. Contract First (CLAUDE.md sec 4): the
Developer's FIRST commit keeps this file in sync with any deviation.

## 1. Surface and audience

- Host = native Lightning App **Utility Bar** item in the **GTM Offerings** app
  only. Internal reps (GTM_Offering_User / GTM_Offering_Admin). Experience Cloud
  is out of scope.
- **GTM Content Manager app is EXCLUDED (owner decision F4, pending).** Content
  Manager users have no `GtmAgentProxyController` grant, and granting one lets
  editors spend the org-wide API key in `GTM_Agent_Settings__c`. To include it
  later: add the same flexipage to that app AND grant the class in
  `GTM_Content_Manager` / `GTM_Content_Admin`. Human decision, not made here.
- Known, accepted overlap: on the configurator page the existing floating
  `gtmAgentBubble` and the utility GUS both show. They are separate
  conversations. Not changed here (bubble untouched); owner may later decide to
  retire the bubble.

## 2. LWC contract

### `gtmGusUtility` (new, thin host)
- `js-meta.xml`: apiVersion 62.0, `isExposed` true, `masterLabel` "GUS",
  description, ONLY `<target>lightning__UtilityBar</target>`.
- Renders a header (mascot, "GUS", "New chat" button) and
  `<c-gtm-agent-chat mode="app" page-context={pageContext} greeting=... placeholder-text=...>`.
- `@wire(CurrentPageReference)` -> `pageContext` (F2 below). Never subscribes
  to empApi. Does not use `lightning/platformUtilityBarApi` (not needed; no
  Jest stub exists in sfdx-lwc-jest; do not add one).
- Handles `onagentaction` (page effects, sec 5) with `NavigationMixin`.
- Ignores `agentdelta`.
- "New chat" calls `this.template.querySelector('c-gtm-agent-chat').reset()`.

### `gtmAgentChat` (extended, one component, F1)
- New `MODE_APP = 'app'`. New `@api pageContext` (object, default `{}`) and
  `@api reset()` (clears `messages`, `historyJson`, `draft`, `thinking=false`).
- `_send()` in app mode calls
  `chatOnApp({ pageContextJson: JSON.stringify(this.pageContext || {}), userMessage, historyJson })`
  read at SEND time (component is kept alive across navigation).
- Existing `chat` / `chatOnReadout` paths, `agentdelta` dispatch and every
  existing test stay unchanged and green.
- Error mapping (app mode only): if the error message contains
  `access to the Apex class`, show "You do not have access to GUS. Ask an admin
  to assign the GTM Offering User permission set." Otherwise existing fallback.
- Page effect rendering: when `parsed.changes.pageEffect` is a valid object
  (sec 5), attach `{label}` to that assistant message and render one button
  under it. Click dispatches `agentaction`
  (`bubbles:false, composed:false`, `detail:{type:'navigate', label, apiName, state}`),
  once per click. `agentdelta` is still dispatched for non-empty `changes`
  (unchanged contract); hosts that do not care ignore it.
- `gtmAgentBubble`: UNTOUCHED. (It has no Jest spec; if a Developer edits it
  for any reason, a regression spec is mandatory. Default: do not touch.)

### F2 page-context behaviour (owed LIVE check)
`CurrentPageReference` emitting inside a utility item cannot be verified
offline. Build so that an empty/undefined page reference yields `pageContext = {}`
and the chat still works (Apex treats `{}` as unknown page). QA owes a live
check on every app tab; record the result in the QA report. If it never
emits, GUS still works without page awareness (degraded, not broken).

Host mapping from the page reference (allow-list, never copy `state`):

| Field | Source |
|---|---|
| `pageType` | `ref.type` (e.g. `standard__navItemPage`, `standard__recordPage`, `standard__objectPage`) |
| `tabApiName` | `ref.attributes.apiName` when type is `standard__navItemPage` |
| `objectApiName` | `ref.attributes.objectApiName` |
| `recordId` | `ref.attributes.recordId` |

## 3. Page-context JSON allow-list (`pageContextJson`)

Keys, all optional strings: `pageType`, `tabApiName`, `objectApiName`, `recordId`.
Server sanitiser (`GtmAppAgentSurface.sanitizeContext(String json)`, static,
`@TestVisible`, never throws): parse defensively (blank/invalid/non-object ->
empty map); keep only the four keys; value must be a String matching
`^[A-Za-z0-9_]{1,80}$` (`recordId`: `^[A-Za-z0-9]{15}$|^[A-Za-z0-9]{18}$`);
anything else dropped silently. Unknown keys dropped. Raw `state`, URLs and
free text never reach the prompt. The sanitised values are rendered into the
system prompt as a fixed "Current page:" line. `recordId` is context only; no
tool in this issue uses it, and later tools must re-verify sharing (never trust
the client-supplied id).

## 4. Apex contract

```apex
// GtmAgentProxyController (existing, without sharing) - new entry point
@AuraEnabled
public static String chatOnApp(String pageContextJson, String userMessage, String historyJson)
// returns JSON { text, historyJson, changes }; never throws for: blank/invalid
// context, blank message, or no provider key configured (F5).
```
Order inside `chatOnApp`:
1. `ctx = GtmAppAgentSurface.sanitizeContext(pageContextJson)`.
2. Blank `userMessage` -> return reply `{text:'Please type a message.', historyJson: <input or ''>, changes:{}}`.
3. F5: `String key = getApiKey(getProvider())`; if blank return
   `{text:'GUS is not set up yet. Ask an admin to add an API key on the GTM Offerings Settings tab.', historyJson:<input or ''>, changes:{}}`
   WITHOUT any callout. `runLoop` and its stale "Setup -> Custom Settings" text
   are UNCHANGED (config/readout tests depend on them); only the new path uses
   the new wording.
4. `trimmed = GtmAppAgentSurface.trimHistory(historyJson, 20)`.
5. `return runLoop(new GtmAppAgentSurface(ctx), userMessage, trimmed);`
   (the returned `historyJson` is therefore also bounded).

### `GtmAppAgentSurface` (new, top-level, `public with sharing`, F3)
`implements GtmAgentToolSurface`. Mirrors `GtmReadoutAgentSurface`: not
listed in permission sets (called only from Apex; confirm
`GtmReadoutAgentSurface` is absent from permsets and mirror).
- Ctor `GtmAppAgentSurface(Map<String,Object> ctx)` uses
  `registeredTools()`; ctor `GtmAppAgentSurface(Map<String,Object> ctx, List<GtmAppTool> tools)`
  is `@TestVisible` for tests.
- `private static List<GtmAppTool> registeredTools()` returns the EMPTY list in
  this issue. Follow-ups add one line each here (sec 6). Test hook:
  `@TestVisible private static List<GtmAppTool> testTools;` (if non-null,
  returned instead).
- `toolDefinitions()` = concatenation of every tool's `definitions()`; tool
  names must be unique (first registration wins; later duplicates skipped).
- `executeTool(name, input, acc)`: find the tool whose `handles(name)`; call
  `execute`; wrap in try/catch returning `{"error":"..."}`. No tool matches ->
  `{"error":"no tools available"}` (zero-tool case) or
  `{"error":"unknown tool"}`. NEVER throws, NO DML, NO callout.
- `maxTokens()` = 1024.
- `systemPrompt(toneClause)`: you are GUS, the Go-To-Market Utility Sidekick
  for the Publicis Sapient GTM Offerings Salesforce app, used by internal reps;
  answer questions about how to use the app and about the current page
  (rendered "Current page: type=..., tab=..., object=..., record=..." only for
  keys present, else "Current page: unknown"); concise; if asked to do
  something you cannot, say so plainly and suggest the manual path. Tool
  sentence: with zero tools, "You currently have NO tools: you cannot read data,
  change anything, or take any action, and must not claim to." With tools,
  "You may only take the actions your tools provide", followed by each tool's
  `promptFragment()`. Then `'TONE: ' + toneClause` as the other surfaces do.
- `public static String trimHistory(String historyJson, Integer maxTurns)`:
  parse; a "turn" starts at a `role='user'` message whose `content` is a
  String (plain rep text; NOT a tool_result list). If there are more than
  `maxTurns` turns, keep only the last `maxTurns`, cutting ONLY at a turn
  start so tool_use/tool_result pairs are never split. Blank or unparseable
  input is returned unchanged. Never throws.

### `GtmAppTool` (new public interface; the attachment point)
```apex
public interface GtmAppTool {
    List<Object> definitions();     // Anthropic-format tool defs (Map<String,Object>)
    Boolean handles(String toolName);
    // Same contract as GtmAgentToolSurface.executeTool: never throw, no DML,
    // no callout, return JSON string ({"error":...} for failures).
    String execute(String toolName, Map<String,Object> input, Map<String,Object> accumulatedChanges);
    String promptFragment();        // appended to the system prompt; '' allowed
}
```
A tool class is itself `with sharing`, receives NO owner/user id and no client
record id from the surface, and may set `accumulatedChanges.put('pageEffect', ...)`
(sec 5).

### F6: omit empty tools in ALL THREE adapters (REQUIRED)
Read of `GtmAgentProxyController` at origin/main:
- `callOpenAi` and `callGemini` ALREADY omit `tools` / `functionDeclarations`
  when the converted list is empty (`if (!tools.isEmpty())`,
  `if (!declarations.isEmpty())`).
- `callClaude` does NOT: it always puts `'tools' => surface.toolDefinitions()`
  in the body. An empty array is rejected by the Anthropic API. FIX: build the
  body map, and `put('tools', defs)` only when `defs` is non-empty. Behaviour
  for config/readout surfaces (non-empty) is byte-identical apart from key
  order (Apex Map JSON; existing tests must stay green unmodified).
- Tests (one per provider, new test class `GtmAppAgentSurfaceTest`, or in
  `GtmAgentProxyControllerTest` if it fits): set settings (org defaults) for the
  provider + a dummy key, `Test.setMock(HttpCalloutMock.class, ...)` capturing
  the request body, call `chatOnApp('{}', 'hi', '')`, assert the body does NOT
  contain the substring `"tools"` (Anthropic, OpenAI) and does NOT contain
  `"functionDeclarations"` nor `"tools"` (Gemini). Also one positive test:
  with `testTools` set to a stub tool, the Anthropic body DOES contain
  `"tools"` and the stub's tool name. Use a real Anthropic-shaped mock reply
  (`stop_reason` `end_turn` etc.; OpenAI/Gemini mocks in their native shapes as
  the existing tests do).

## 5. Page-effect contract (navigation, not LMS)

A tool asks the host to move the rep by putting ONE object in the delta bag:

```json
"changes": { "pageEffect": { "type": "navigate", "label": "Show these in Pages",
             "apiName": "GTM_Pages", "state": { "c__stage": "quiet" } } }
```
- Server (tool) responsibilities: validate its own enum values; label <= 60
  chars; last successful call wins; never set it on error.
- The rep sees a button (human in the loop; no surprise navigation while
  typing). Click -> chat `agentaction` -> host validates AGAIN (defence in
  depth) then `this[NavigationMixin.Navigate]({ type: 'standard__navItemPage',
  attributes: { apiName }, state })`.
- Host allow-list constant `ALLOWED_NAVIGATION` in `gtmGusUtility.js`:
  `{ home: [], GTM_Pages: ['c__stage'], GTM_Assessments: ['c__astatus', 'c__aacct',
  'c__acontact', 'c__arange'], GTM_Analytics: [] }`
  (apiName -> permitted `state` keys). CHANGE (issue #10, `filter_by_query`):
  `GTM_Assessments` grew from `[]` to the four keys that tool emits; tier,
  readout, offering and preset stay disallowed until a tool sets them. See
  `docs/architecture/gus-filter-query-tool.md` sec 9.
  CHANGE (app-landing-page, implemented in step 1): key `home` replaces `GTM_Offerings_Overview`; the host maps
  `home` to `{ type: 'standard__namedPage', attributes: { pageName: 'home' } }`.
  See `docs/architecture/app-home-pages.md` sec 4. State keys must be `c__`-prefixed
  (platform rule), values strings <= 200 chars. Anything else is dropped and
  no navigation happens. Later tools extend this map in their own change.
  `c__stage` semantics and reserved params: `docs/architecture/gtm-link-stage-filter.md`
  and `docs/architecture/gtm-filter-bar.md` (the target page reads `c__` state
  via the shared filter bar; already deployed on Pages via #224/#226).
- NavigationMixin from a utility item is a supported Salesforce pattern; QA
  confirms live on navigation to `GTM_Pages` with state.

### Salesforce-native evaluation (standing rule)
- Utility Bar: NATIVE choice, used (persistent bottom launcher, survives tab
  navigation, no custom FAB per page).
- Page effects: `lightning/navigation` (standard, deep-linkable, works even if
  the target page LWC is not mounted) versus Lightning Message Service.
  DECISION: navigation; NO message channel metadata in this issue. LMS is
  publish/subscribe between components that are alive at the same time; a tab
  the rep is not on is not mounted, so a message published to it is lost, and
  it would need a `LightningMessageChannel` metadata file plus subscribers on
  every page. URL state has neither problem and the shared filter bar already
  reads it, including on same-page state change. If a later need is an
  in-page live update with no URL meaning, add LMS then and document the
  channel here first.
- Custom parts that remain, and why: the chat LWC and the Apex tool loop (no
  native equivalent short of Agentforce; deferred by AGENTS.md sec 1; tool
  logic is kept in surface/tool classes so it can later sit behind
  invocable actions).

## 6. How `gus-stage-filter-tool` attaches (binding for the sibling)

1. Create `GtmStageFilterAgentSurface` (or a nested/separate class) that
   `implements GtmAppTool` (`with sharing`), wrapping
   `GtmLinkStageService.getLinkIdsForStage`. `definitions()` returns
   `find_links_by_stage`; `promptFragment()` returns the A3 phrase-mapping text;
   `execute` does the A4 logic and, on success, sets
   `accumulatedChanges.put('pageEffect', {type:'navigate', label:'Show these in Pages', apiName:'GTM_Pages', state:{c__stage:key}})`
   (REPLACES the `navigateToPages` key and the sibling's `agentaction`
   `navigateToPages` shape).
2. Register with one line in `GtmAppAgentSurface.registeredTools()`.
3. `GTM_Pages: ['c__stage']` is already in the host allow-list; no LWC,
   `chatOnPages`, mode, or bubble work is needed in the sibling.

## 7. How `filter_by_query` attaches (issue #10, second tool on this surface)

Full contract: `docs/architecture/gus-filter-query-tool.md`. Summary: a
second `GtmAppTool` (`GtmFilterByQueryAppTool`), registered as a second line
in `GtmAppAgentSurface.registeredTools()` alongside `GtmStageFilterAppTool`
(`toolDefinitions()` dedupes by name, so the two tools cannot collide). Same
propose-then-click `pageEffect` shape as `find_links_by_stage`; the ONLY host
change this issue required was widening `GTM_Assessments`'s allow-list entry
from `[]` to the four `c__a*` keys the new tool can set (sec 5 above) — no
`gtmFilterBar` prop, no new LWC, no new controller entry point.
4. There is no `compactHistory` in the repo at origin/main; if the sibling
   needs it, it owns it (apply inside `GtmAppAgentSurface`/`chatOnApp`, after
   `runLoop`, before returning). Note `trimHistory` (20 turns) already bounds
   growth.
5. The host passes NO owner/user scope; the tool runs with sharing in its own
   class regardless of `GtmAgentProxyController` being `without sharing`.

## 7. Metadata

Source-deployable (in the change set):
- `lwc/gtmGusUtility/*`, edits to `lwc/gtmAgentChat/*`
- `classes/GtmAppAgentSurface.cls(+meta)`, `GtmAppTool.cls(+meta)`,
  `GtmAgentProxyController.cls` edits, tests
- NOT in this change (coordinator decision): the UtilityBar flexipage and the
  app's `<utilityBar>` reference. The org's validator rejected every utility
  item syntax tried offline (see "Validate-only findings"), so the item is
  created by hand after deploy and then retrieved into source (steps below).
- Permission sets: NO change (class access for `GtmAgentProxyController` already
  on User/Admin; new classes are called from Apex only). No fields/objects.
- `GTM_Content_Manager` app: UNCHANGED.

Needs an org-side step / cannot be proven offline (record in QA report):
1. MANUAL STEP after the real deploy (owner, not agents): Setup -> App Manager
   -> GTM Offerings -> Edit -> Utility Items -> Add Utility Item -> Custom ->
   Lightning Component `gtmGusUtility`; label `GUS`, icon `chat` (or
   `einstein`), panel width 420, panel height 560, Start Automatically OFF;
   Save. Hard refresh and confirm GUS is in the bottom bar. The Content
   Manager app is not touched.
   FOLLOW-UP (coordinator): RETRIEVE the resulting FlexiPage (UtilityBar type)
   and the GTM_Offerings CustomApplication from the org into source so they are
   version-controlled and the accepted item syntax is captured. Until then a
   deploy of the app file from source will not carry the utility bar, and
   deploying the app file can overwrite the manual edit: do not deploy
   `GTM_Offerings.app-meta.xml` from source before that retrieve is committed.
2. An admin must have a provider key saved on the Settings tab (existing
   prerequisite).
3. `CurrentPageReference` inside a utility item (F2) and NavigationMixin from
   a utility item: live checks only.
No Experience Cloud publish step.

## 8. Tests and validation (no live deploy)

- Jest: `gtmGusUtility.test.js` (renders chat mode app; page-context mapping
  from mocked `CurrentPageReference` via `createTestWireAdapter`/emit; empty ref
  -> `{}`; unknown fields not forwarded; no empApi import; ignores
  `agentdelta`; `agentaction` -> Navigate with exact args for `GTM_Pages` +
  `c__stage`, and NO navigation for non-allow-listed apiName/key; New chat calls
  reset). `gtmAgentChat.test.js` additions: app mode calls `chatOnApp` with
  `pageContextJson` (not `chat`/`chatOnReadout`), reads context at send time,
  pageEffect button dispatches one `agentaction`, access-error mapping, reset().
  Existing cases untouched. Bubble: no changes, no spec required.
  Run `npx sfdx-lwc-jest -- gtmGusUtility gtmAgentChat` then `npm test`.
- Apex (`GtmAppAgentSurfaceTest`): `sanitizeContext` (blank, invalid,
  array, unknown keys, bad recordId, oversize, injection text dropped);
  `trimHistory` (blank, under cap, over cap cuts on a plain-user turn start
  and never leaves an orphaned tool_result); prompt contains the no-tools
  sentence + tone clause + current-page line; `executeTool` returns error JSON
  and never throws; registered-tool dispatch and duplicate-name skip;
  `chatOnApp` no key -> friendly reply and NO callout; the three F6 tests;
  `chatOnApp` blank message.
- Validate-only check (the ONLY permitted org interaction):
  `sf project deploy start --dry-run --test-level RunSpecifiedTests --tests GtmAppAgentSurfaceTest --tests GtmAgentProxyControllerTest --tests GtmAgentProxyControllerReadoutTest -o gtm-prod`
  plus the new/changed source paths (never `-c`). It executes tests and rolls
  back. Apex tests use mocks only; no anonymous Apex or real calls.

## 9. Developer implementation notes (binding clarifications)

Recorded before code (Contract First). None changes the contract above; each
pins a detail the contract left open.

- Confirmed at build time: `GtmReadoutAgentSurface` is absent from every
  permission set, so `GtmAppAgentSurface` / `GtmAppTool` get no entries either.
- `chatOnApp` blank-message and no-key replies echo the INPUT `historyJson`
  (or `''`); they perform no callout and touch no history.
- Key check uses the same private `getProvider()` / `getApiKey()` that
  `runLoop` uses, so the friendly reply and the loop can never disagree about
  whether a key is configured.
- `chatOnApp` returns `changes: {}` unless a registered tool set something;
  with zero registered tools the reply always has empty `changes`.
- `agentaction` is dispatched by `gtmAgentChat` only from the button click, and
  the chat validates only SHAPE (`type==='navigate'`, string `apiName`, string
  `label` <= 60, plain-object `state`); the allow-list decision belongs to the
  host (`ALLOWED_NAVIGATION`), which re-validates every key and value.
- `reset()` also clears the message counter-independent state only (messages,
  history, draft, thinking); the greeting is not a stored message so it stays.
- `trimHistory` returns the input string byte-for-byte when no trimming is
  needed; it re-serialises only when it actually cuts.

### Validate-only findings (Developer, `sf project deploy start --dry-run`, gtm-prod)

- Apex + LWC + the 3 named test classes: 60/60 pass (run without flexipage/app
  from that run, see below).
- Component name: bare `gtmGusUtility` and `c:gtmGusUtility` both resolve (the
  error text names `c:gtmGusUtility` either way); the file uses `c:gtmGusUtility`.
- `<utilityBar>` in the app file: element placement after `<uiType>` parses
  (the only app error seen was "no FlexiPage named ... found" while the
  flexipage itself failed).
- OPEN, UNRESOLVED: the FlexiPage fails validation on the utility item
  properties. With `icon`/`label`/`panelBodyHeight`/`panelWidth`/`startAutomatically`
  as `componentInstanceProperties` the org answers `Invalid property [icon] in
  component [c:gtmGusUtility]` (each of the five names is rejected alone, and
  the same for standard components such as `notes:utilityBarNoteList`); with no
  properties it answers `missing required decorator property [label]`. Declaring
  `@api label` / a `targetConfig` property on the LWC does not satisfy it.
  Whichever way the item is written, this org's validator rejects it, so the
  exact accepted syntax for a custom LWC utility item must be settled by a
  human (App Manager > Utility Items, then retrieve, or Salesforce docs)
  before a real deploy. The flexipage and the app `<utilityBar>` line were REMOVED from this issue for
  this reason (see section 7 manual step and retrieve follow-up). Exact org
  error texts, all from validate-only runs with component `c:gtmGusUtility`
  unless noted:
  - five properties: `Invalid property [icon] in component [c:gtmGusUtility]`
  - alone: `Invalid property [panelWidth]`, `[startAutomatically]`,
    `[panelBodyHeight]`, `[label]`, `[title]`, `[decorator]`, `[decorators]`,
    `[utilityLabel]`, `[utilityBarLabel]`, `[itemLabel]`, `[utilityItemLabel]`,
    `[Label]`, `[lightning__label]` (all same message form)
  - standard `notes:utilityBarNoteList` / `flexipage:filterListCard` with
    `icon` or `label`: `Invalid property [icon|label] in component [...]`
  - no properties: `Invalid component [c:gtmGusUtility]: missing required
    decorator property [label]`
  - `@api label` on the LWC + `label` property: property accepted, decorator
    error unchanged
  - js-meta `targetConfig` with `supportedFormFactors`: `The 'supportedFormFactors'
    tag isn't supported for lightning__UtilityBar`; empty `targetConfig`: `The
    'targetConfig' tag doesn't contain any design information.` (plus `We
    couldn't retrieve the design time component information`); a `label`
    property in `targetConfig` without `@api label`: `The 'label' property
    doesn't exist on the component.`
  - unknown element under ItemInstance: `Error parsing file: Element ...
    invalid at this location in type ItemInstance`; `fieldInstance`: `The null
    field isn't allowed in the utilityItems region.`
  - app file: `<utilityBar>` after `<uiType>` parsed; only error was `In field:
    utilityBar - no FlexiPage named GTM_Offerings_UtilityBar found` while the
    flexipage failed.
