# Prospect Page Setup Wizard

**Status:** Draft for review
**Offering:** Migration Accelerator
**Relationship:** New guided front door alongside the existing Customize side
panel (`maConfigCustomize`) — additive, not a replacement. The v1 form and
the AI chat assistant (see `agentforce-customizer-v2.md`) both stay reachable
from the wizard for a rep who prefers them.
**Design reference:** [Prospect Page Setup Wizard — artifact mockup](https://claude.ai/code/artifact/52d8f87a-4fb7-429c-965f-8309b07c183c)

> **Stale:** written before the `MA_`→`GTM_` rename (see `docs/backlog.md` D6);
> verify current object/component names in code before treating this as
> ground truth. This wizard shipped under the name `gtmConfigWizard`, not
> `MaConfigWizard` as referenced below.

---

## 1. Problem statement

The Customize side panel assumes a level of technical fluency a BD rep or
Industry Leader may not have: a hex color field, raw proof-number inputs
(an "objects mapped" count, a 0–100 health score), and — in its v2 form — a
conversational AI panel that itself requires knowing how to prompt an
assistant. None of that is a natural fit for a rep whose job is selling, not
configuring software, especially one building a link live on a call with a
prospect.

The wizard replaces none of the underlying data model or persistence — it's
a new, guided, one-question-at-a-time front end over the exact same
`MA_Saved_Configuration__c` / URL-param contract the panel already writes
to. Every field it collects maps directly onto an existing token (see §5).

---

## 2. Scope

**In scope:**
- A new `MaConfigWizard` LWC: one-question-per-screen flow, back/skip
  navigation, live autosave (reuses the existing 1.5s-debounced
  `saveConfiguration()` path)
- Two entry points (§4) and three paths through the wizard: Quick Link,
  Full walkthrough, Continue a saved link (§4)
- A duplicate-account warning and "start from a similar link" suggestions
  on the first screen (§6.1, §6.2)
- A password-by-default policy, replacing the panel's current opt-in
  toggle (§6.3)
- A post-send "we'll notify you when they open it" confirmation, tied to
  existing link-activity tracking (§6.4)
- A Publicis Sapient red/black fallback for the Quick Link path's brand
  color when no prospect website is given (§6.5)

**Out of scope:**
- Any change to `MA_Saved_Configuration__c`, `Config_Payload__c`, or the
  URL-param contract itself — the wizard is a new writer, not a new schema
- Retiring the v1 form or the AI chat assistant — both stay reachable via
  "Continue a saved link → Edit answers"
- Section reordering, multi-offering support (same exclusions as
  `agentforce-customizer-v2.md`)
- Localization / multi-language

---

## 3. Why not just fix the panel?

The panel's problem isn't its fields, it's its shape: everything is visible
at once, defaults are implicit, and there's no path for a rep who just
wants to move fast. A single form can't comfortably serve both "I need a
link in the next 30 seconds" and "I want to dial in every detail" — hence
two explicit paths (§4) rather than one denser form.

---

## 4. Entry points

### 4.1 Primary — GTM Offerings Overview (Salesforce tab)

A rep opens Salesforce, not the public site, and starts from the tool they
already work in. A new **"+ New Prospect Page"** action sits on the
existing `gtmOfferingsSnapshot` component (on the `GTM_Offerings_Overview`
flexipage), alongside the rep's existing "needs attention" and activity
widgets (`gtmOfferingsNeedsAttention`, backed by `MA_Link_Event__c` — both
reused unchanged). The wizard opens as a modal, landing on the path choice
(§4.3).

### 4.2 Secondary — Customize button on a live/shared link

Unchanged trigger (`showCustomizeButton` / `isConfigManager`) on
`maConfigurator`. For a rep already looking at a specific link — on a call,
reviewing what the client sees — this still opens the wizard, but lands on
**Step 8 (Preview & send)** with "Edit an answer" to step back into any
earlier screen, rather than starting the rep over at Step 1.

### 4.3 Path choice

Whichever entry point is used, the rep picks one of three paths:

| Path | What it asks | When |
|---|---|---|
| **Quick link** | Company + industry only; everything else defaulted | Live on a call, needs a link now |
| **Full walkthrough** | All 8 steps | A few minutes to prepare before a meeting |
| **Continue a saved link** | Pulled from `getMyConfigurations()` | Editing or resending an existing link |

---

## 5. Full walkthrough — step contract

Each step maps onto fields the panel already reads/writes; nothing here is
a new field.

| # | Screen | Rep sees | Required? | Maps to |
|---|---|---|---|---|
| 1 | Who's this for? | Live Salesforce contact/company search | Required | `Company__c`, `Account__c`, `Contact__c` (`searchContacts`) |
| 2 | Their industry | Large tappable cards (CMS-driven), not a dropdown | Required | `Industry__c` / `industryKey` |
| 3 | Brand colour | Paste website → auto-detected logo colour; swatch fallback | Optional, automatic | `accent` (`MaBrandLookupController.fetchLogoDataUri`) |
| 4 | Their environment | Small / Medium / Large presets, not raw numbers | Optional, defaults if skipped | `ASSET_COUNT`, `DEPENDENCY_COUNT`, `HEALTH_SCORE` |
| 5 | Personal note | One box, example placeholder, visible Skip | Optional | `CUSTOM_NOTE` |
| 6 | Your details | Prefilled from the rep's own User record | Required, prefilled | `CONTACT_NAME`, `CONTACT_EMAIL`, `BOOKING_URL` |
| 7 | Protect the link | Password-protected by default (§6.3) | Default on, can turn off | `Link_Password__c` (`MaLinkAuthController`) |
| 8 | Preview & send | The actual live page; Copy / Send to client / Save & finish later | — | `Presentation_Stage__c = 'Sent'` → `MA_Config_Send_To_Client` flow |

Autosave is unchanged: every answer writes via the same debounced
`saveConfiguration()` call the panel uses today, so closing the tab
mid-flow and reopening the same saved link restores every earlier answer.

---

## 6. New capabilities

### 6.1 Duplicate-account warning (Step 1)

If another rep already has an active link for the selected Account, Step 1
shows a warning naming them and the date, with "View their link" / "Continue
anyway."

**Why not `getMyConfigurations()`:** that method is `with sharing` — a rep
without `MA_Config_View_All` can't see another rep's records through it, so
the duplicate check needs a new, narrow `without sharing` lookup (same
pattern as `MaConfigurationStatusController`) that returns **only** the
owner's name and the date — never the other rep's full config data.

### 6.2 Similar-link suggestions (Step 1)

"Or start from a similar link" surfaces the rep's own recent links in the
same industry, via `getMyConfigurations()` filtered by `Industry__c` —
no new Apex needed here.

### 6.3 Password-protected by default (Step 7)

Today's panel defaults `Link_Password__c` to unset (opt-in). The wizard
flips this: every link gets an auto-generated password on creation
(`clearLinkPassword = false` by default), shown to the rep with options to
keep it, set their own, or explicitly turn protection off. This is a
behavior change from the current panel, not just a new UI — confirm with
product/security whether this should also become the panel's default, or
stay wizard-only.

### 6.4 Post-send open notification (Step 8)

After "Send to client," the rep sees a confirmation that they'll be
notified the moment the prospect opens the link. Backed by the existing
`MA_Link_Event__c` log (`Event_Type__c = 'Page View'`); needs a **new**
notify-owner trigger or flow that fires on the first view per link only
(not every subsequent view).

### 6.5 Quick Link brand-colour fallback

On the Quick Link path, if no website is given for the automatic brand
lookup, the accent defaults to Publicis Sapient's own red/black
(`#E4002B` / `#000000`) rather than the panel's neutral generic swatch —
a Quick Link should never look unbranded by default.

---

## 7. Acceptance criteria

- [ ] `MaConfigWizard` LWC covers all 8 full-walkthrough steps plus the
      Quick Link path, embeddable both in a Lightning modal (Overview tab)
      and on the public Experience Cloud site (Customize button)
- [ ] Every wizard field write round-trips through the existing
      `saveConfiguration()` contract — no new fields on
      `MA_Saved_Configuration__c`
- [ ] Quick Link path completes in 2 questions (company, industry) and
      produces a fully valid, sendable link
- [ ] Duplicate-account check never exposes another rep's config data,
      only owner name + date, and respects the existing sharing model for
      everything else
- [ ] Password defaults on for every new link; existing links are
      unaffected (no retroactive password added to already-saved
      configurations)
- [ ] Post-send notification fires exactly once per link, on first view
- [ ] "Continue a saved link" opens on Step 8 with full prior state
      restored, not a blank wizard
- [ ] v1 form and AI chat assistant remain reachable via "Edit answers"
- [ ] Mobile-usable end to end (one-question-per-screen was chosen partly
      for this)

---

## 8. Developer checklist

- [ ] Build `MaConfigWizard` LWC (screens, navigation, autosave wiring)
- [ ] Add "+ New Prospect Page" action to `gtmOfferingsSnapshot` /
      `GTM_Offerings_Overview` flexipage, opening the wizard in a modal
- [ ] Repoint the live-page Customize button to open the wizard on Step 8
      instead of the panel directly
- [ ] New Apex: narrow `without sharing` duplicate-account lookup
      (owner name + date only)
- [ ] New: auto-generate a password on link creation; add the
      keep/change/turn-off controls to Step 7
- [ ] New: notify-owner trigger/flow on `MA_Link_Event__c` first-view
- [ ] Quick Link path: implement the PS red/black fallback when brand
      lookup has no website to work from
- [ ] QA on both surfaces: Lightning modal (internal) and Experience
      Cloud site (Customize button)
- [ ] Confirm with product whether §6.3's password-by-default should also
      become the v1 panel's default, or stay wizard-only
