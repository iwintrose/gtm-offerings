# GtmLinkOwnerStamp contract (rep-ownership-lockdown, piece 1)

Owner rule: a rep may view/edit/delete only their own links and everything tied to them; admins see all.
Guest-created records (events, drafts, access Tasks) are stamped with the link owner so Private OWD scopes them per rep.

## Class

`public without sharing class GtmLinkOwnerStamp` - no DML, no `@AuraEnabled`, never throws, private constructor (Apex classes are final by default; `final` is not valid on a class).

| Method | Behaviour |
|---|---|
| `public static Id ownerForLink(Id savedConfigurationId)` | Null input, non-`GTM_Saved_Configuration__c` id, no row, inactive/guest owner, or any exception returns `null`. Two queries at most per call (never per row): dynamic `SELECT OwnerId FROM GTM_Saved_Configuration__c WHERE Id = :id LIMIT 1`, then, only if the owner id is a User, `SELECT Id FROM User WHERE Id = :ownerId AND IsActive = true AND UserType != 'Guest' LIMIT 1`. (Owner is polymorphic, so a `Owner.IsActive` relationship filter is unusable; the single-query form was ratified but failed in the org.) A `@TestVisible lastError` holds the exception type name of any swallowed failure. |
`public static void stamp(List<SObject> rows, Id ownerId)` | Sets `OwnerId` on each non-null row only when `ownerId != null`. No-op otherwise. |

## Usage rules

- One `ownerForLink` call per entry point (not per row); then `stamp` before the insert.
- Stamp sits inside the existing try/catch of each entry point; no new throw path.
- No resolvable owner: the row stays unowned (site/guest owned). No queue fallback (F1). Contact engagement shows each rep only their own links (F2).
- `GtmLinkAuthController.logAccess` stamps its Task only when `recordId.getSObjectType() == GTM_Saved_Configuration__c.SObjectType`.

## Stamped entry points

`GtmLinkEventController.logEvent/logEvents`, `GtmFormDraftController.saveDraft/clearDraft`, `GtmAssessmentDraftController` mint/append/emailResumeLink budget row (null configId leaves unowned), `GtmAssessmentRequestController.closeDraft` closing row (now also copies `Saved_Configuration__c`), `GtmLinkAuthController.logAccess`.

No schema, permission-set or reader changes in this piece. Residual risk: guest-context insert with a non-guest `OwnerId` cannot be proven in test; verify after deploy with a real page view and a read-only SOQL.
