# Unified Account/Contact search (issue-gtm-assessments-account-contact-trail follow-up)

## Problem

`gtmReadoutAccountFinder` (Assessments tab trail) and `gtmRepLinkFinder`
(Pages tab trail) each start their Miller-columns trail with an
Account-only `lightning-record-picker`. A rep who only remembers the
*contact's* name (not the account) has no way to jump in — they have to
guess the account first. Confirmed against the approved mockup
(https://claude.ai/code/artifact/66dc64c4-8f45-4df3-a067-86e0d4949537):
replace that first-screen Account-only field with a single search box that
returns both Accounts and Contacts, so either identifier gets a rep to the
right place.

## Contract: Apex

New class, shared by both LWCs (kept separate from `GtmReadoutController`/
`GtmRepLinkFinderController` since neither owns this search — it is a
generic Account/Contact typeahead, not scoped to Requests or Saved
Configurations):

```apex
public with sharing class GtmAccountContactSearchController {

    public class SearchResult {
        @AuraEnabled public String recordId;   // Account.Id or Contact.Id
        @AuraEnabled public String type;        // 'Account' | 'Contact'
        @AuraEnabled public String label;       // Account.Name, or "First Last"
        @AuraEnabled public String subLabel;    // '' for Account; parent Account.Name for Contact
        @AuraEnabled public String accountId;   // Account.Id for both types (self for Account, parent for Contact)
    }

    @AuraEnabled(cacheable=false)
    public static List<SearchResult> searchAccountsAndContacts(String searchTerm)
}
```

- `@AuraEnabled(cacheable=false)`: results are keyed on a live, freshly
  typed search term on every keystroke (post-debounce) — there is no
  stable cache key a rep would ever hit twice in the same way a
  `cacheable=true` wire benefits from, and Lightning Data Service cannot
  usefully de-dupe a moving search string. Every other read method on
  the two existing trail controllers that get called with a stable
  argument once per drill-down step (`getContactsWithRequests`,
  `getContactsWithLinks`) stays `cacheable=true`; this one does not fit
  that shape.
- Returns `[]` for `null`/blank/`<2`-char input rather than throwing —
  the LWC already gates the call at 2+ chars client-side (see below), but
  the server does not trust that gate alone.
- SOSL, not two SOQL queries: `FIND :term IN ALL FIELDS RETURNING
  Account(Id, Name LIMIT 5), Contact(Id, FirstName, LastName, AccountId,
  Account.Name LIMIT 5)`, wildcarded (`'*' + term + '*'`) for partial
  matching. `Security.stripInaccessible(AccessType.READABLE, ...)` is
  applied to each returned list before it is mapped into `SearchResult`
  — SOSL has no `WITH SECURITY_ENFORCED`, `stripInaccessible` is the
  documented FLS-safe substitute (Apex Developer Guide,
  "Security.stripInaccessible").
- `with sharing`: a rep never sees an Account/Contact their own sharing
  rules would otherwise hide, matching every other read path in this
  area of the app.
- No DML anywhere in this class.

## Contract: LWC (both components, same shape)

- `gtmReadoutAccountFinder` (`raf-` prefix) and `gtmRepLinkFinder`
  (`rlf-` prefix) each replace their first-screen Account-only
  `lightning-record-picker` with a plain `lightning-input` (type
  `search`) backed by `searchAccountsAndContacts`, plus a results
  dropdown rendered from `@track` state — `lightning-record-picker` only
  supports one `object-api-name`, so it cannot itself return mixed
  Account/Contact results.
- Debounce: 300ms `setTimeout`/`clearTimeout` per keystroke
  (`handleSearchInput`), matching the "keystrokes settle before firing"
  convention already used elsewhere in this codebase for typeahead
  inputs.
- Minimum 2 characters: the debounced handler checks
  `term.trim().length < 2` and clears results / skips the Apex call
  without ever invoking it — avoids a flood of near-empty-term SOSL
  calls per keystroke on a 1-character input.
- Selecting an **Account** result: identical to today's
  `handleAccountChange` — sets `accountId`, loads
  `getContactsWithRequests`/`getContactsWithLinks`, proceeds into the
  existing Contact-picking step.
- Selecting a **Contact** result: sets `accountId` (from the result's
  `accountId`) AND `selectedContactId` (from the result's `recordId`) in
  one go, then loads the same `getContactsWithRequests`/
  `getContactsWithLinks` call as the Account path (needed regardless, to
  populate the sibling Contacts under that Account for the crumb/back
  nav) and immediately advances the `step` getter straight to
  `'request'`/`'link'` once that call resolves and finds the matching
  group — skipping the intermediate Contact-picking screen entirely,
  since a Contact result already resolves both levels.
- Picked-state display: the search input is replaced with a read-only
  summary (`raf-summary`/`rlf-summary`-style crumb, matching the existing
  Contact/Link "summary + change" pattern already in both components)
  showing the picked Account or Contact name, with a "Search again"
  link that clears `accountId`/`selectedContactId` and returns to the
  empty search state — reusing the existing `handleBackToAccount`
  reset logic, just re-triggered from the new search summary instead of
  only from deeper "choose a different account" links.
- URL-state: unchanged contract (`c__rafAccountId`/`c__rafContactId` and
  `c__rlfAccountId`/`c__rlfContactId`/`c__rlfLinkId`) — a Contact pick
  just writes both ids to the URL in the same call that an Account pick
  already writes one, so refresh-restore keeps working unmodified.

## Explicitly unchanged

- Everything downstream of the initial pick (Contact-picking step when
  an Account was chosen, the final Request/Link list, crumbs, refresh
  persistence) is untouched.
- `gtmReadoutWorkspace`, the "All Assessments"/"All Pages" tile-grid
  modes, and the mode toggle itself are untouched — this only changes
  the account-step markup/logic inside the "By Account or Contact" mode
  of each component.
