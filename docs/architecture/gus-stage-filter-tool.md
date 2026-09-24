# GUS tool `find_links_by_stage` (contract)

Status: architect contract (binding). Issue `gus-stage-filter-tool`. Attaches to
the app-wide utility-bar GUS (`chatOnApp`); host contract:
`docs/architecture/gus-utility-bar-host.md`. Stage definitions:
`docs/architecture/gtm-link-stage-filter.md`. This file is short by design:
the tool is a thin wrapper, all funnel logic stays in `GtmLinkStageService`.

## 1. Class and registration

- `GtmStageFilterAppTool` : `public with sharing class ... implements GtmAppTool`.
  Zero DML, zero callouts, never throws. Not in any permission set (called from
  Apex only, like `GtmReadoutAgentSurface`).
- Registered with ONE line in `GtmAppAgentSurface.registeredTools()`.
- No `chatOnPages`, no LWC, no bubble, no flexipage. Host allow-list already
  contains `GTM_Pages: ['c__stage']`.

## 2. Tool schema

`find_links_by_stage`, one required parameter:

| Param | Type | Values |
|---|---|---|
| `stage` | string enum | `GtmLinkStageService.STAGE_KEYS` (built from the constant): `sent, engaged, started, submitted, quiet, hot, not_opened` |

Server-side validation happens BEFORE the service call. Blank, null, non-String
or unknown stage returns `{"error":"..."}` (never a throw, no `pageEffect`).
Any other input key (including `owner_id`, `user_id`) is ignored; the tool never
reads an owner or user id from the model or the host. There are no name filters.

## 3. Result (`execute` return, JSON)

```json
{ "stage": "quiet", "count": 31, "truncated": true,
  "rows": [ { "id": "a0X...", "company": "...", "account": "...", "contact": "...",
              "offering": "migration-accelerator", "presentationStage": "Sent" } ] }
```

- Membership and order come ONLY from `GtmLinkStageService.getLinkIdsForStage(stage)`
  (CreatedDate DESC). `count` = full id count. Rows = first 25 ids; `truncated = count > 25`.
- Rows come from one display-only projection query (`WHERE Id IN :cappedIds`, `with sharing`),
  re-ordered in Apex to the service order. Fields: `Id, Company__c, Account__r.Name,
  Contact__r.Name, Offering__c, Presentation_Stage__c`. NEVER `Link_Password__c`,
  `Generated_URL__c`, `Config_Payload__c`, `Notify_Email__c`.
- Row text is user-controlled data; the prompt says so.

## 4. Page effect (success only)

```json
"changes": { "pageEffect": { "type": "navigate", "label": "Show these in Pages",
             "apiName": "GTM_Pages", "state": { "c__stage": "<validated key>" } } }
```
Last successful call wins. Nothing navigates until the rep clicks the button.

## 5. Prompt fragment (phrase mapping)

- `sent`: "links I sent", "all my links". `not_opened`: "haven't opened", "unopened".
- `engaged`: "opened", "looked at", "viewed" (superset: includes those who started or submitted).
- `started`: "began the assessment" (superset of submitted). `submitted`: "completed", "finished".
- `quiet` = started AND NOT submitted: "went quiet", "opened the form but never submitted",
  "started but didn't finish", "stalled", "gone cold".
- `hot`: "came back", "returned", "revisited", "active again". The reply must state the
  definition: at least two visits AND the last visit within the past 48 hours.
- "opened but didn't start": no exact key exists. Use `engaged` and say explicitly that
  people who only viewed the page cannot be isolated, and the list includes those who
  started or submitted. Do not invent a key.
- Name filtering is not supported here (suggest the Pages tab filters).
- Always call the tool rather than guess counts; state count and truncation; results are as
  of now; to re-list, call the tool again; mention "Show these in Pages".

## 6. `compactHistory`

`public static String GtmStageFilterAppTool.compactHistory(String historyJson)`: pure, no
SOQL, never throws (unparseable or nothing to change returns the input unchanged). For every
`tool_result` block whose `content` parses to a JSON object containing `rows`, removes `rows`
and adds `rowsOmitted:true` (keeps stage, count, truncated). Message count, order, roles and
`tool_use_id`s are untouched, so a tool_use/tool_result pair can never be orphaned.
Called once in `GtmAgentProxyController.chatOnApp` on the `historyJson` field of the
`runLoop` result, after `runLoop`, before return. `runLoop`, adapters and `trimHistory` are
untouched. Rows remain visible to the model for the rest of the current turn only.

## 7. Security

- `with sharing` tool and `with sharing` service: sharing is per executing class, so the
  `without sharing` proxy does not bypass scoping. The service scopes by
  `UserInfo.getUserId()` unless the user holds viewAllRecords.
- Known limitation: the service's internal 50,000-link universe cap flag is not surfaced by
  this tool. Open item carried from the service contract: guest-generated event/request rows
  under Private OWD may be hidden from a non-admin rep; a test records the observed behaviour.

## 8. Tests

`GtmStageFilterAppToolTest`: two reps + admin under `System.runAs`, ignored owner input,
seven-key parity with the service, zero DML/callouts via `Limits`, enum validation,
truncation, no secrets, `compactHistory`, dispatch through `GtmAppAgentSurface`, and a
`chatOnApp` mocked-callout test.
