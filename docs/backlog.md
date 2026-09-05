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

## Decisions needed before Claude builds

These are the ones where guessing has already cost us once.

| # | The question | Why it matters |
|---|---|---|
| D1 | **Gus** — one assistant with per-offering *persona*, or per-offering *capability* too? You said tone and personality vary, function is consistent, and the customizer experience is per offering page. Does Gus's list of things-he-can-change differ between offerings, or is it always "the fields on this page"? | Decides whether Gus's config is one record per offering or one per offering-page. Wrong guess = rebuild. |
| D2 | **Feedback visibility** — `getFeedbackFor` returns *everyone's* notes on an offering, not just yours. Deliberate: a BD about to raise "the proof number is stale" should see it was raised last week. With one user you can't tell. Right call before more people are in? | Cheap to change now, awkward later. |
| D3 | **Site split** — Offerings page + Industry Chooser are framework; Configurator belongs to the offering. Today all three serve from one Experience site. Split them, or accept one site and drop the URL ambition? | The `/gtm/maaccelerator/` URL you wanted needs this. Salesforce URL prefixes are a single path segment, so the URL alone can't be done. |
| D4 | **Requests vs submissions** (#16) — Claude's read: they're the same act recorded twice, and the Assessment Request is the one worth a screen. Submissions are funnel events and already show on the link's own page. Agree, or do you want a submissions list too? | You've asked three times and said you still don't understand the difference. Claude answering again in prose clearly isn't working. |

---

## Ready to build — no decision needed

| # | Item | Hurts | Sure |
|---|---|---|---|
| B1 | **FAQ / help widget** for both apps (#18). Static panel per app, content in the CMS so it's editable. | polish | high |
| B2 | **Resend an engagement link** — a BD can set and clear a link password but there's no "send this again" action. Real gap found while answering the guest-account question. | daily | high |
| B3 | **Contact-side analytics** — link events now carry `Contact__c` after identity stitching, but nothing on the Contact record shows it. | daily | high |
| B4 | **Delete the retired CMS content** — 17 records, all labelled `RETIRED —`. Select-all → Manage → Delete in the CMS workspace, then the destructive deploy for the five types. Claude cannot do this from here (no Apex delete, no ConnectApi delete, CLI redacts the token). | polish | high |

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
pages · industries moved to the framework · offering feedback loop (#25).

---

## Known and accepted

- Experience site URL prefixes are immutable and single-segment. Site *display*
  names can only be changed in Setup.
- Guest User licences allow insert and read on a custom object — never update or
  delete. The form-draft design is shaped around this.
- Chromium in the dev container cannot reach the org through the proxy, so
  visual verification is by mockup and by querying the org, not by screenshot.
