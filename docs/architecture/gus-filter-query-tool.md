# GUS tool `filter_by_query` (contract)

Status: architect/owner-finalized contract (binding), issue #10. Attaches to
the app-wide utility-bar GUS (`chatOnApp`); host contract:
`docs/architecture/gus-utility-bar-host.md`. Sibling tool, same pattern:
`docs/architecture/gus-stage-filter-tool.md` (`find_links_by_stage`). Filter
bar contract: `docs/architecture/gtm-filter-bar.md`.

This tool does not do open-ended NL date/name parsing itself: the model maps
the rep's sentence to a small set of structured fields (same division of
labour as `find_links_by_stage`'s `stage` param), and this tool validates and
resolves those fields server-side before proposing a `pageEffect`. **Option A**
(2026-09 architect decision): routes through the existing `gtmGusUtility`
chat / `GtmAppAgentSurface` tool pipeline. No new `gtmFilterBar` prop, no new
controller entry point, no inline apply — the rep always clicks a button.

## 1. Class and registration

- `GtmFilterByQueryAppTool` : `public with sharing class ... implements GtmAppTool`.
  Zero DML, zero callouts, never throws. Not in any permission set (called
  from Apex only).
- Registered with ONE line in `GtmAppAgentSurface.registeredTools()`, after
  `GtmStageFilterAppTool`.
- Reuses `GtmAccountContactSearchController.searchAccountsAndContacts` (SOSL,
  `with sharing`) for account/contact resolution — no new search code path.
- Reuses `GtmLinkStageService.STAGE_KEYS` (Pages) and two new read-only
  accessors, `GtmAssessmentListController.statusKeys()` /
  `.tierKeys()` (Assessments), so the tool's enum never hand-duplicates a
  vocabulary that already lives elsewhere. `tierKeys()` is exposed for
  parity/future use; v1 does not accept a `tier` field (see 2 below).

## 2. v1 query pattern coverage (owner-finalized, 2026-09-24)

Exactly: **a pipeline stage/status + an account/contact name + a date range
phrase**, any subset, on the two existing `gtmFilterBar` consumers.

| Tab | Understood fields |
|---|---|
| `GTM_Pages` | `stage` only (`GtmLinkStageService.STAGE_KEYS`) |
| `GTM_Assessments` | `status` (`GtmAssessmentListController.statusKeys()`, the closest Assessments analog to a Pages "stage"), `account_or_contact` (free text, resolved server-side), `date_phrase` |

Tier, readout and offering are explicitly **not** in v1's understood
vocabulary — the model is instructed (via `promptFragment()`) to omit them
rather than guess a value the rep didn't ask for. This caps v1's pattern
surface per the Architect's "not a general NL query language" boundary
(`docs/agent-artifacts/task-scope-10.md` §"Multiple simultaneous filters").

## 3. Tool schema

`filter_by_query`, one required parameter (`tab`) plus four optional ones the
model fills in only for what it understood:

| Param | Type | Applies to | Values |
|---|---|---|---|
| `tab` | string enum, required | both | `GTM_Pages`, `GTM_Assessments` |
| `stage` | string enum | Pages | `GtmLinkStageService.STAGE_KEYS` |
| `status` | string enum | Assessments | `GtmAssessmentListController.statusKeys()`: `new, contacted, scheduled, completed, no-show` |
| `account_or_contact` | string | Assessments | free text, verbatim from the query |
| `date_phrase` | string enum | Assessments | `today`, `this_week`, `this_month` — **no other date phrase is supported in v1**; the model omits the field for anything else (see §6) |

Server-side validation happens before any state is built. An optional field
that IS present but fails its enum check is a hard `{"error":...}` with no
`pageEffect` — same zero-guess rule as `find_links_by_stage`. A field that is
simply absent is treated as "not part of this query," not as an error.

## 4. Account/contact resolution (owner-finalized, 2026-09-24)

1. Call `GtmAccountContactSearchController.searchAccountsAndContacts(term)`
   (existing FIND ... RETURNING SOSL pattern, `Security.stripInaccessible`,
   sharing-scoped, up to 5 Accounts + 5 Contacts).
2. Case-insensitive exact match on `label` wins if there is **exactly one**.
3. Otherwise, fall back to the full fuzzy/partial result set from step 1.
4. Zero candidates (exact or fuzzy) → `{"error":"No account or contact found
   matching \"<term>\"."}`, no `pageEffect`.
5. Exactly one candidate (exact or fuzzy) → resolved: an Account candidate
   sets `c__aacct`, a Contact candidate sets `c__acontact`, to that record's
   Id.
6. Two or more candidates → `{"error":"Multiple accounts/contacts match
   \"<term>\": <names>. Which did you mean?", "candidates": [...]}`, no
   `pageEffect`. GUS's reply is text-only; the rep must re-ask more
   specifically. This tool **never** guesses among multiple matches.
7. A term under 2 characters is rejected before any search (mirrors the
   search controller's own client-side gate; the tool does not trust it
   alone).

## 5. Date-phrase vocabulary (owner-finalized, 2026-09-24)

Exactly three literal phrases, each a fixed `{from,to}` computation — **no
open-ended date parsing**:

| `date_phrase` | Range |
|---|---|
| `today` | `Date.today()` .. `Date.today()` |
| `this_week` | `Date.today().toStartOfWeek()` .. `Date.today()` |
| `this_month` | `Date.today().toStartOfMonth()` .. `Date.today()` |

Serialized as `c__arange = "<from>..<to>"` (ISO `YYYY-MM-DD`), the same
`{from,to}` shape `gtmFilterUrlState` already parses/serializes for a custom
date range (`docs/architecture/gtm-filter-bar.md` §4) — not a preset token,
since v1's phrases don't line up with the bar's `7`/`30`/`90` day presets.
Anything outside this set of three literal phrases (`"last month"`, `"last
30 days"`, a specific date) is unrecognized: the model must omit
`date_phrase` and say plainly it isn't supported in v1, while still applying
whatever status/account portion of the query WAS understood (see §6). If the
model passes an unrecognized string anyway, the tool still refuses it as an
error with no `pageEffect` (defense in depth; the enum-restricted schema
should prevent this in practice).

## 6. Partial understanding / graceful fallback

- If a query mixes an understood field with an unrecognized one (e.g. "TD
  Bank last quarter"), the model is instructed to still call the tool with
  only the fields it understood (`account_or_contact` only, in that
  example) and mention in its reply that the date portion wasn't applied.
  This is chat-level behaviour (`promptFragment()`), not Apex branching —
  the tool itself only ever sees the structured fields the model decided to
  pass.
- If NOTHING in the query maps to a supported field (Assessments: no status,
  no name, no date; Pages: no stage), the tool returns
  `{"error":"Could not understand that query..."}` and the model is
  instructed to ask a clarifying question rather than call the tool with an
  empty result.

## 7. Result (`execute` return, JSON)

Pages success:
```json
{ "tab": "GTM_Pages", "understood": { "stage": "quiet" } }
```
Assessments success (any subset of the three fields present):
```json
{ "tab": "GTM_Assessments", "understood": { "status": "contacted", "party": "TD Bank", "date": "this_month" } }
```
Error (invalid enum, no match, or ambiguous match) — same shape as
`find_links_by_stage`:
```json
{ "error": "..." }
```
An ambiguous account/contact match additionally carries `"candidates":
[...]` (display names only, no ids) so the model can list them without a
second tool call.

## 8. Page effect (success only)

```json
"changes": { "pageEffect": { "type": "navigate", "label": "Show these in Pages" | "Show these in Assessments",
             "apiName": "GTM_Pages" | "GTM_Assessments", "state": { ...one or more of: "c__stage",
             "c__astatus", "c__aacct", "c__acontact", "c__arange" } } }
```
Last successful call wins (same as the stage tool). Nothing navigates until
the rep clicks the button — `gtmGusUtility`'s `_validatedTarget` allow-list
check (§9) is the second gate.

## 9. Host allow-list change (required, not optional)

`force-app/main/default/lwc/gtmGusUtility/gtmGusUtility.js`'s
`ALLOWED_NAVIGATION` map:

```js
GTM_Assessments: ['c__astatus', 'c__aacct', 'c__acontact', 'c__arange'],
```

(was `[]`). `c__atier`, `c__areadout`, `c__aoffering`, `c__apreset` remain
disallowed — no tool sets them yet, and the allow-list is deliberately no
wider than what a registered tool actually emits. `_validatedTarget` rejects
the WHOLE navigation if ANY state key is not on the tab's list (see the LWC),
so a future tool adding a not-yet-allowed key must extend this list in the
same change, exactly like this one did.

## 10. Security

- `with sharing` tool; account/contact resolution only ever sees what the
  running rep's sharing already grants (same guarantee
  `GtmAccountContactSearchController` already provides to
  `gtmReadoutAccountFinder` / `gtmRepLinkFinder`). No new sharing gap: this
  tool adds no query the rep couldn't already run through those existing
  pickers.
- No DML, no callouts (SOSL counts against neither limit). Never throws —
  every branch returns `{"error":...}` on failure.

## 11. Tests

`GtmFilterByQueryAppToolTest`: tab validation, Pages stage success/failure,
enum parity with `GtmLinkStageService.STAGE_KEYS` and
`GtmAssessmentListController.statusKeys()`, Assessments status
success/failure, the three date-phrase ranges plus rejection of anything
else, exact-match / single-fuzzy-match / multi-match-ambiguous / no-match
account resolution, a too-short search term, combining status + account +
date into one `pageEffect`, zero DML/zero callouts via `Limits`, and
dispatch through `GtmAppAgentSurface` alongside `find_links_by_stage`.

`gtmGusUtility.test.js`: new fixtures proving each of `c__astatus`,
`c__aacct`, `c__acontact`, `c__arange`, and a combination, navigate for
`GTM_Assessments`; a negative case for a still-disallowed key (`c__atier`)
and for a mix of an allowed key with a still-disallowed one.
