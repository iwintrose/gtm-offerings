# Backlog

The jot pad. One place the outstanding work lives so neither of us is
re-typing it, and so "what did we decide about X" has an answer.

**How this works.** Don brain-dumps freely — that stays easy, and structuring
the dump is Claude's job, not his. Claude splits it into items here, groups
them, and marks each with two things: how much it hurts, and how sure Claude is
what to build. Anything low-certainty waits for a decision rather than being
guessed at. Updated at the end of every working session.

**Certainty is the axis that has been costing us.** Impact tells us what order
to work in; certainty tells us whether to talk first. High impact + low
certainty is the quadrant where this session lost the most time — the framework
lock got built from a one-line item and had to be undone, and the industry
sections were built onto the configurator, moved, restored twice, and finally
deleted.

Legend — **Hurts:** `blocks` a demo · `daily` friction · `polish`
&nbsp;&nbsp;**Sure:** `high` = go and build it · `low` = needs a decision first

---

## Decisions

Answered decisions stay here with their answer, so neither of us re-litigates
them. An answer that contradicts something already built says so.

### Answered

**D1 — Gus.** *Framework persona and tone; per-offering capability.*
One Gus everywhere: same name, same voice, one place to edit him. What differs
per offering is what he can **do** on that offering's pages.

> ⚠️ **This inverts what is built.** The `assistant` section currently sits on
> `migration-accelerator::configurator` and holds name, role, button label,
> greeting and input prompt — persona, at the offering level, which is exactly
> backwards. Rework: move persona to the framework, and replace the
> per-offering section with a *capability* declaration (which fields Gus may
> change on that page) rather than copy. See #21.

**D2 — Feedback visibility.** *BD sees their own; the Content Manager sees all.*
`getFeedbackFor` currently returns everyone's notes to everyone. It gets a
`Submitted_By__c = :UserInfo.getUserId()` filter; `getOpenFeedback` stays
unfiltered, because anyone with the Content Manager is a writer.
Also raised: **the feedback card's padding and margins are unfinished** — text
sits too close to the card edge. Folded in as B5.

### Open

**D3 — ANSWERED: A2.** One public site at `/gtm` hosting the configurator and
nothing else; the offerings list and the story live in Lightning, where the BD
is already authenticated. The industry chooser is redundant as a *page* — the
wizard already asks the same question — but stays as the *authoring surface*
where the industry copy lives. Content home is not the same as a rendered page.

Sequence: story viewer (done) → deploy pages to GTM (done) → **Don publishes
and activates GTM** (done — confirmed Live) → guest permissions, Apex repoint,
rewrite the four links (done) → verify (done at the code/record level;
browser screenshot blocked — see Known and accepted) → **Don deactivates GTM
Accelerator** → reseed with permutations.

> Correction: only *activation* (Inactive → Live, one-time) needed Setup UI.
> Routine publish does not — `sf community publish -n <name>` works fine and
> is now the standard step after any ExperienceBundle metadata deploy. A
> metadata deploy only writes the site's draft; nothing is live until
> published. Learned the hard way when the Home redirect deployed clean but
> the real browser still showed blank until publish ran.

One Don action is left: deactivating GTM Accelerator, then reseeding.

*(superseded)* **D3 — the old framing.** Not yet answered. Offerings page + Industry Chooser are
framework; the Configurator belongs to the offering; all three serve from one
Experience site today. Splitting them is the only route to the URL shape you
wanted, because a Salesforce site prefix is a single path segment and cannot be
`/gtm/maaccelerator/`.

**D4 — Requests vs submissions.** Not a decision yet: *"I still need a
walkthrough with you."* Claude explaining it again in prose has failed three
times, so the next attempt is a walkthrough against the real records — one
engagement link, and every row both concepts produced from it. Then decide
whether a submissions list earns a screen. Blocks #16.

**D5 — Self-service link recovery on the bare `/gtm/s/configurator`.** Not a
decision yet. Today a guest with no `?cfgId=` gets a static "this page needs a
link, reach out to your rep" screen (built and live). You floated something
richer: enter your email + the password your rep gave you, resolve to the
right link, and — you weren't sure — maybe a "resend my password" if it's been
forgotten.

The email + password lookup is straightforward and safe to build: no new abuse
surface, since the password is a credential they already hold. The "email me
my password" piece is a materially different feature — a guest-facing form
that sends email based on typed input is a live enumeration and open-relay
target (type any exec's email, learn whether they have an active link; hammer
the endpoint as free outbound mail) and needs its own security pass before it
exists at all, not a quick add.

> **Claude's proposed default:** build the email + password lookup now
> (v1) — matches an existing MA_Saved_Configuration__c by contact email *and*
> its own password together, one guest Apex method, no email sending. Not
> found and expired both render the same existing "reach out to your Rep"
> screen, exactly as you suggested — no separate wrong-password oracle to
> enumerate against. Park "resend to email" as its own item, flagged for
> `security-review` before it's built, not folded into this one.
>
> Needs a yes before it's built — this is guest-facing and auth-adjacent.

**D6 — `MA_`/`Ma` prefix leaks the single-offering assumption.** Raised again
while granting `MA_Assessment_Guest`: it and the Apex classes it grants
(`MaLinkAuthController`, `MaConfigurationStatusController`,
`MaAssessmentRequestController`) are named for Migration Accelerator
specifically, but the mechanism is framework-level — link auth, password
gating, and request submission work identically for any offering, not just
this one. Same pattern likely holds across most `MA_`-prefixed permission
sets, custom objects/fields, and Apex classes in the org.

**Done.** 36 Apex classes, 13 LWC bundles, 4 permission sets (metadata),
1 flow, 2 genAiPlugins, profiles, layout label, and supporting scripts
renamed `Ma`/`MA_` → `Gtm`/`GTM_`. Sequenced as the plan required: new
permission sets deployed and assigned to every real guest/human user
*before* removing old assignments; new flow deployed Active with the old
one set Obsolete in the same pass to avoid a double-send; old Apex
classes/LWC bundles only destructively removed from the org after both
sites were republished and confirmed live on the new names. Found and
fixed along the way: the org's actual live Assessment Request record page
(`Assessment_Request_Record_Page2`, never tracked in source) still pointed
at the old `maAssessmentDetail` — would have broken for every CRM user;
`chooseIndustry`'s Experience Builder label was still "MA Choose Industry";
two `scripts/data/*.apex` seed scripts still called deleted classes.

**Resolved.** `MA_Config_Manager`, `MA_Story_Guest`, `MA_Assessment_Guest`
refused deletion ("used in an experience") even with zero
`PermissionSetAssignment` rows left. Actual cause, found by querying
`NetworkMemberGroup` directly: all three were still registered as
authenticated-member permission sets on *both* sites (`GTM` and
`GTM Accelerator`) — a leftover from before the D6 rename, unrelated to
`PermissionSetAssignment` or any CMS Workspace. Isiah removed them from
both sites' Administration → Members lists in Setup; destructive deploy
then succeeded cleanly (dry-run and real, 0 errors). Local source files
removed to match. `check-all.sh` dangling-references check: none.


**D7 — `gtmPageBrowser` ("Pages" tab) has the wrong shape.** A rep should
not be able to freely browse every offering × every template — that's the
Content Manager's job, not the BD app's. What a rep actually needs, from
inside GTM Offerings:

- **The Story**, for context — already right: Overview's "Read the story"
  button, no change needed.
- **The rep's own view of a Configurator link they already sent** — not a
  blank/generic preview, the *actual* rendering of that specific saved
  configuration, reached by clicking through from the record it belongs
  to (the Assessment Request, or wherever "somewhere within the GTM
  Offering app" ends up being the right anchor) rather than picking
  offering + template from two comboboxes.
- The path there is **Account → Contact → Link** — browsing the CRM
  relationship to find whose link it is, not a page picker.
- Once you're looking at that link, it should be **a view, not the
  editor** — no Customize/Gus chrome, none of what Claude called "the
  editor things on the left two columns." Just what was sent.

**Done.** `frontend-engineer` rebuilt `gtmPageBrowser`'s non-Story path as
`gtmRepLinkFinder` — Account → Contact → Link, backed by
`GtmRepLinkFinderController.getContactsWithLinks` (`with sharing`, not
guest-reachable, 4 passing tests). The orchestrating session finished the
piece `frontend-engineer` deferred back: `@api viewOnly` on
`gtmConfigurator` (gates `showCustomizeButton`, `showAssistant`, the
saved-links bar) and on `gtmStageActions` (gates `showRail` — the whole
action rail hides rather than repurposing client-facing status copy for a
rep's own view), wired `view-only` into `gtmRepLinkFinder`'s rendered
`<c-gtm-configurator>`. Dry-run + real deploy clean, both sites (`GTM` and
the still-live legacy `GTM Accelerator`) published, `check-all.sh` and the
`GtmRepLinkFinderControllerTest` suite green, pushed (`b445e29`, `b3d2804`).

**D8 — Gus's persona and the Configurator's defaults are both stuck inside
a page, when neither really belongs to one.** Two things, same shape:

- **Gus.** D1 already decided this — "one Gus everywhere; what differs per
  offering is what he can do" — but it was never built. Confirmed: the
  `assistant` section (name, role, greeting, fab label, input placeholder)
  still lives at `migration-accelerator::configurator::assistant`, exactly
  where D1 said it wrongly was. It's read by nothing else — `gtmConfigurator`
  is the only reader, hardcoded to that one offering's page — and it's
  invisible on the Framework's own card in the Content Manager home;
  finding it means opening Migration Accelerator's Configurator page
  specifically and knowing to look in its section rail. `git log` confirms
  this was the original design, not a regression — nobody ever built the
  move.
- **Configurator defaults** (the swatch list, default source/target
  platform, generic demo numbers — `defaults::*` under
  `migration-accelerator::configurator`) — same shape: only reachable by
  opening that one page, and `gtmConfigWizard.js` hardcodes
  `OFFERING = 'migration-accelerator'` when reading them, so a second
  offering would silently keep reading the first one's swatches and
  defaults rather than its own.

Your framing: these aren't really *pages* — nobody visits "Gus's settings"
or "the defaults" as a page a prospect or rep reads — they're closer to
**assets**, and belong on the Framework's card and each Offering's own card
on the Content Manager home, not buried inside one specific page's editor.
Agreed on the shape; still need a name for the category (you said "let's
find a name" — candidates to react to: **Assets**, **Settings**, **Config**)
and a decision on the mechanism: a new, non-page-scoped content record type
addressed by `offeringKey::assetKey` (parallel to how pages are addressed
today, just without a `templateType`), versus something else. Not started —
logging for a decision pass, not guessing at the model.

---

## Ready to build — no decision needed

| # | Item | Hurts | Sure |
|---|---|---|---|
| B2 | **Resend an engagement link** — a BD can set and clear a link password but there's no "send this again" action. Real gap found while answering the guest-account question. | daily | high |
| B3 | **Contact-side analytics** — link events now carry `Contact__c` after identity stitching, but nothing on the Contact record shows it. | daily | high |
| B6 | **Page names in the GTM Content Manager should be editable** by the Content/BA role (confirmed: the role that has access to that app, not a broader audience). Today `TEMPLATE_LABELS` (`Story`, `Configurator`, `Offerings Page`, `FAQ — BD App`, …) is a hardcoded JS constant in `gtmPageLayouts.js` — a Content Manager user can edit page *content* but not what the page is *called* in their own picker. Needs a content-model decision (own field on the page-content record? a new small addressable content key alongside each page's sections, following the same pattern B1 used?) — well-scoped, same shape as B1. **Unblocked** — D6 landed, `gtmPageLayouts.js` is stable again. | daily | high |

---

## Needs Don's eyes before more is built on it

| # | Item | Why |
|---|---|---|
| R1 | **The 72 migrated industry rows** now on the framework's Industry Chooser. Moved but never reviewed. | Everything industry-related now reads from these. If the migration mangled any copy, every configurator inherits it. |
| R2 | **BOA / SC-0012** lost its payload during the `Generated_URL__c` backfill early in the session. Two of eight were recovered from URLs you'd pasted; this one had an empty payload and no field history. Needs re-entering by hand. | Data Claude destroyed. Not recoverable without you. |

---

## Done this session

Chapters as sections · Gus editable per offering · deals + funnel on the
overview · requests/submissions untangled in the data · container-query preview
fix · deal picker default · interaction sitemap + dwell + identity stitching ·
form resume with partial save · page + field order aligned across all five
pages · industries moved to the framework · offering feedback loop (#25) ·
gtmPageBrowser replacing the story viewer · Configurator's external route
deployed to `/gtm` · `getSiteBaseUrl()` repointed onto `urlPathPrefix`
instead of the site label · guest permission-set parity between the GTM and
GTM Accelerator guest users · the four saved links rewritten to `/gtm` ·
bare `/gtm/s/configurator` (no `?cfgId=`) blocked from guests, visible only
to a signed-in Salesforce user · configurable Home redirect (Custom Label,
editable in Setup without a deploy) · two more dead-code removals
(`OfferingSummary.storyUrl`, the unused `getSiteHomePageUrl` import) ·
B5, feedback card padding · B1, the CMS-editable FAQ widget on both apps ·
B4, the retired CMS content (records deleted by Don, the 5 dead
managedContentType definitions removed).

---

## Known and accepted

- Experience site URL prefixes are immutable and single-segment. Site *display*
  names can only be changed in Setup.
- Guest User licences allow insert and read on a custom object — never update or
  delete. The form-draft design is shaped around this.
- Chromium in the dev container cannot reach the org through the proxy, so
  visual verification is by mockup and by querying the org, not by screenshot.
