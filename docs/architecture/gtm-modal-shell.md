# `gtmModalShell` — Shared Side-Sheet Modal Shell

Status: Accepted (issue `shared-modal-shell`)

## Problem

Side-sheet overlay LWCs (`gtmConfigWizard`, `gtmRepDirectPicker`) each
independently reimplement scrim/sheet CSS, open/close transitions, and
close-dismiss wiring. This duplicates ~60 lines of CSS per consumer and has
already caused one incident (`gtmConfigWizard`'s chrome-offset mount-order
fragility). `gtmModalShell` is a new, presentation-only LWC that owns the
scrim, sheet positioning/transition, close affordance, and title rendering,
leaving all body content and domain events owned by the consumer.

This issue migrates only `gtmRepDirectPicker` onto the shell.
`gtmConfigWizard`'s migration (including its `chrome-offset` opt-in) is a
separate, not-yet-started follow-up issue
(`shared-modal-shell-config-wizard`).

## Public API

### Props (`@api`)

| Prop | Type | Default | Notes |
|---|---|---|---|
| `is-open` | Boolean | `false` | Toggles the `open` state class on the scrim/sheet (CSS-class toggle, not mount/unmount — matches both existing consumers' behavior). |
| `title` | String | `''` | Rendered in the shell's header and wired to `aria-labelledby` on the sheet for accessibility. |
| `chrome-offset` | Boolean | `false` | Opt-in only. When `true`, the shell performs the deferred `setTimeout(() => this._measureChromeOffset(), 0)` positioning currently inline in `gtmConfigWizard.js` (lines ~319–406), measuring the host's offset from page top and pinning the scrim/sheet's `top` to it. When `false` (the default), the shell is plain `position: fixed`, full viewport — no measurement, no timer. Not used by this issue's only consumer (`gtmRepDirectPicker`); documented here as a no-op path reserved for the `gtmConfigWizard` follow-up. |

### Slots

| Slot | Purpose |
|---|---|
| default (unnamed) | Body content — the consumer's own step/form/search UI. |
| `header-extras` | Supplementary header content, rendered alongside the title/close button. Unused by `gtmRepDirectPicker`; reserved for a future `gtmConfigWizard` migration's step-dot rail. |

### Events

| Event | Payload | Fired when |
|---|---|---|
| `close` | none | Scrim click, or the shell's own explicit close (`×`) control. |

The shell dispatches **only** `close`. It has no knowledge of and never
dispatches domain events (`created`, `done`, `configsaved`, etc.) — those
remain entirely owned by whatever content is slotted in, dispatched from the
consumer component itself.

## Visual/behavioral contract migrated from `gtmRepDirectPicker`

The shell's default (non-`chrome-offset`) CSS treatment is
`gtmRepDirectPicker`'s current `.rdp-scrim`/`.rdp-sheet` rules, moved
verbatim in spirit:

- Scrim: `position: fixed; inset: 0;` `display: none` → `display: block`
  toggle on `.open` (no transition on the scrim itself).
- Sheet: `position: fixed; top: 0; right: 0; bottom: 0; width: 420px;`
  `transform: translateX(100%)` → `translateX(0)` on `.open`,
  `transition: transform .2s ease`.
- z-index scheme: scrim `9000`, sheet `9001` (the `gtmRepDirectPicker`
  scheme — kept as the shell's default since `gtmConfigWizard`'s `89/90`
  scheme is not migrated in this issue).

## Consumer migration: `gtmRepDirectPicker`

`gtmRepDirectPicker` no longer owns any scrim/sheet markup or CSS. It wraps
its existing search/select/confirm body markup in
`<c-gtm-modal-shell is-open={isOpen} title="New assessment (no page)"
onclose={handleClose}>` (default slot), and does not set `chrome-offset` —
this migration is a visual/behavioral no-op for the picker per the
Architect's acceptance criterion. All of `gtmRepDirectPicker`'s existing
state (`_searchTerm`/`_results`/`_selected`/`_searching`/`_saving`/`_error`),
handlers, Apex calls, and the `created` event are unchanged. The picker's
existing `handleClose` (state reset + redispatch of its own `close` event)
still runs, now triggered by the shell's `close` event via `onclose`.

## Out of scope

`gtmConfigWizard` (separate follow-up issue), `gtmContentHome`/
`gtmFieldEditor`/`gtmContentManager` (centered-dialog family, different UX
shape), `gtmFaqPanel`/`gtmAgentBubble` (no scrim, non-modal FAB panels).
