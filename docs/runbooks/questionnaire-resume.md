# Runbook — saving and resuming a part-finished questionnaire

How a respondent who walks away from `c/gtmAssessmentQuestionnaire` gets back to
where they were, on this device or another one, and what a human has to do in
the org that source metadata cannot do for them.

## The requirement

> "the recipient entering information, the form submission and where they are in
> the form submission must persist for them so they can always pick back up from
> where they left off"

Two layers, doing two different jobs.

| | Where | Written | Survives | Does not survive |
|---|---|---|---|---|
| **Fast path** | `localStorage`, keyed `ma-assessment-progress-v2:<savedRecordId or 'direct'>` | every change | refresh, browser restart, closed tab, flat battery | another device, another browser, cleared site data, private windows |
| **Durable path** | `GTM_Form_Draft__c`, addressed by a 256-bit `Resume_Token__c` | each step transition, and on "Save my place" | everything above, plus another device from a link | its own 30-day expiry, and submission |

Both restore **position in the flow**, not only the answer map. A form that hands
back the answers but drops the respondent at step 1 has not resumed anything.

## The link shape

```
https://<site-domain>/gtmaccelerator/s/configurator?resume=<Resume_Token__c>
```

The component also reads `?resume=` straight off `location.search`, so the page
does not have to forward it into a component attribute.

## When the link exists, and why it is not gated on an email address

The respondent gives an email address on the **contact step, which is last**. A
resume mechanism that only switches on once an address exists is a resume
mechanism for people who have already finished.

So the draft is minted **on leaving the routing step** — the first moment
anything worth carrying has been said — and the link is surfaced as something to
copy. Emailing it is offered on top, optional, and the address is used to
address one message and is **never stored**: not on the draft, not in the
respondent's `contact` block, nowhere. Asking someone where to send a link is
not the same as asking for their details, and the copy on screen says so.

The on-screen wording is state-dependent and deliberately never runs ahead of
the facts:

- **routing step, no draft yet** — "Saved on this device only. Your answers are
  kept in this browser… They are not anywhere else yet", next to a **Save my
  place** button.
- **draft exists** — "Your place is saved", the link in a selectable field, the
  expiry date, and "Anyone with this link can see and change these answers, so
  keep it to yourself."
- **arriving on a dead link** — one sentence covering all four reasons it might
  be dead, and an explicit reassurance that nothing on this device was lost.

## Security properties

| Property | How |
|---|---|
| Token is unguessable | `Crypto.getRandomBlob(32)`, base64url, padding stripped — 43 chars, the same generator as `GTM_Readout__c.Public_Link_Token__c` |
| A token reaches only its own draft | every query filters `Resume_Token__c` **in the SOQL WHERE clause**, together with `Status__c = 'Open' AND Expires_At__c > now`. No method on `GtmAssessmentDraftController` accepts a record Id |
| No existence leak | never-issued, expired, submitted and over-cap are **one** response: `resumeDraft` returns null, `saveDraft` throws one fixed message, `emailResumeLink` returns one fixed result |
| Drafts cannot be mistaken for submissions | `GTM_Form_Draft__c` is a different object from `GTM_Assessment_Request__c`, so no list view, report or query over assessment requests can pick one up |
| Exactly one guest write path onto a submission | unchanged: `GtmAssessmentRequestController.submitRequest`. The draft controller cannot create, read or touch an `GTM_Assessment_Request__c` |
| Invalidation on submit | `GtmAssessmentRequestController.closeDraft`, **in the submit transaction** — status to `Submitted` and `Resume_Token__c` nulled. If the submit rolls back so does the revocation |
| Expiry | 30 days from creation, **not extended by saves**. Enforced in the WHERE clause, so a link dies on time whether or not a job ran |
| Data actually goes away | `GtmAssessmentDraftPurge` deletes expired drafts and submitted ones past a 7-day grace. Object has search, feeds, history and reports **off** so no second copy outlives it |
| No guest object permissions | `GTM_Assessment_Guest` grants **class access only**. `GTM_Form_Draft__c` object permissions are deliberately absent, like `GTM_Readout__c` and `Case` |
| Answers are not logged | no `System.debug` of the payload anywhere, no payload in an exception message, nothing but a URL in the email |
| Not an open mail relay | fixed body, no caller-supplied content in it, base URL from configuration (never the browser), 2 sends per draft, address never stored, and minting itself throttled |

### Caps

| Cap | Value | Field |
|---|---|---|
| Payload size | 60,000 chars | — |
| Saves per draft | 200 | `Save_Count__c` |
| Resolves per draft | 50 | `Resolve_Count__c` |
| Emails per draft | 2 | `Resume_Email_Sends__c` |
| New drafts org-wide | 300 per 10 minutes | — |

### Rate limiting: what Apex can and cannot do

**It can** cap volume per draft (the three counters above) and cap new drafts
org-wide over a rolling window.

**It cannot do per-IP throttling, and this implementation does not pretend to.**
The guest user's source IP is not reliably readable from a guest Apex context,
and anything taken from a request header is attacker-supplied. The org-wide mint
ceiling is therefore blunt: a determined script degrades the feature for
everyone rather than being singled out.

The per-caller control has to sit in front of Apex, and it is org/edge
configuration:

1. **Setup → Security → Guest User Rate Limits** — Experience Cloud's own
   per-IP throttle for guest requests. This is the intended control for exactly
   this shape of endpoint and **must be enabled** before the resume endpoints go
   live.
2. Whatever CDN/WAF fronts the site, with a rate rule on the Aura/Apex endpoint.

Token *enumeration* is not what any of this defends against — 256 bits of
`Crypto.getRandomBlob` is. These defend against volume.

## What a human still has to do

1. **Deploy** the object, the two classes and the permission set:

   ```bash
   sf project deploy start \
     -d force-app/main/default/objects/GTM_Form_Draft__c \
     -d force-app/main/default/classes/GtmAssessmentDraftController.cls \
     -d force-app/main/default/classes/GtmAssessmentDraftPurge.cls \
     -d force-app/main/default/lwc/gtmAssessmentQuestionnaire \
     -d force-app/main/default/permissionsets/GTM_Assessment_Guest.permissionset-meta.xml
   ```

2. **Set `GTM_Assessment_Config.Default.Resume_Link_Base_URL__c`** to the
   questionnaire page's URL, e.g.
   `https://<site-domain>/gtmaccelerator/s/configurator`. It is blank in source
   on purpose — a site URL is org state, not source. Until it is set the class
   falls back to `Site.getBaseSecureUrl()`; if that is also blank it **declines
   to send** rather than emailing a broken link.

3. **Enable Guest User Rate Limits** (see above). Not optional.

4. **Check organisation-wide email deliverability** is `All email`. Without it
   `emailResumeLink` returns its generic failure and nobody finds out why.

5. **Schedule the purge**, daily, off-peak:

   ```apex
   System.schedule('MA Assessment Draft Purge', '0 0 3 * * ?', new GtmAssessmentDraftPurge());
   ```

   Skipping this does not make links live longer — expiry is enforced in the
   query — but it does mean unsubmitted prospect answers accumulate indefinitely.

6. **Decide who, internally, can read a draft.** Nobody is granted the object in
   source, including admins-by-permission-set. If support needs to look at one,
   grant it deliberately and temporarily; `Last_Saved_At__c` and `Pair_Key__c`
   answer most operational questions ("how far do people get, on which pair")
   without anyone opening `Answers__c`.

## Known limits

- **A leaked link is a leaked draft.** Anyone holding it can read and overwrite
  the answers behind it until it expires or is submitted. This is the same trade
  the readout link makes, stated plainly on screen, and it is why the resolve
  cap exists. There is no second factor; adding one would mean asking an
  anonymous respondent for a credential they do not have.
- **The org-wide mint ceiling is a shared resource.** See above.
- **No Apex here has been compiled or run.** There is no org and no `sf` CLI in
  the environment this was written in. `GtmAssessmentDraftControllerTest` is
  written but **unverified** — it needs `sf apex run test` against a scratch org
  before anyone relies on it.
