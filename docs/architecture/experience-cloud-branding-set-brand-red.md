# Experience Cloud branding set — Publicis Sapient brand red

Reference for correcting the deprecated brand red (`#E90024`) to the current,
independently-verified value (`#E90130`) in any Experience Cloud site's
`brandingSets/*.json`. Written as part of `gus-chat-branding-refresh`
(2026-09-26) after fixing `force-app/main/default/experiences/GTM1/
brandingSets/buildYourOwn.json`, per Open Fork F6.

## Scope

Only the fields listed below — every other key in a branding set (fonts, nav
bar grays, login background, `_Neutral*`/`_Text*`/`_Background*` colors) is
independent of the brand red and must NOT be touched by this pattern. In
particular, do not change `PrimaryFont`/`HeaderFonts` alongside this table —
Experience Builder chrome is Aura-rendered with no LWC-style JS hook to inject
a font `<link>` the way `c/gtmStory`/`c/gtmBrandFonts` do for LWC surfaces, so
a font change here is separate, unverified work, not a copy-paste.

## Field/value table

| Field | Old value (`#E90024`) | New value (`#E90130`) |
|---|---|---|
| `ActionColor` | `#E90024` | `#E90130` |
| `LinkColor` | `#E90024` | `#E90130` |
| `_ActionColorDarker` | `#BA001D` | `#BE0128` |
| `_LinkColorDarker` | `#BA001D` | `#BE0128` |
| `_ActionColorTrans` | `rgba(233, 0, 36, 0.9)` | `rgba(233, 1, 48, 0.9)` |
| `_HoverColor` | `rgba(233, 0, 36, 0.05)` | `rgba(233, 1, 48, 0.05)` |
| `_PrimaryAccentColor1` | `rgb(233, 0, 36)` | `rgb(233, 1, 48)` |
| `_PrimaryAccentColor2` | `rgb(139, 0, 22)` | `rgb(140, 1, 29)` |

## Where the darker/derived values came from

- `#BE0128` is not a fresh derivation — it is `gtmStory.css`'s own
  `--ps-red-hover` / `--ps-red-on-grey` token (`force-app/main/default/lwc/
  gtmStory/gtmStory.css`), already computed and already documented there as
  6.03:1 contrast on a tinted surface. Reused by value rather than
  re-derived, same as every other GUS surface in this task.
- `_PrimaryAccentColor2` had no equivalent existing token, so it was scaled
  proportionally from the old value: the old pair (`#E90024` →
  `rgb(139,0,22)`) is roughly a 0.6x per-channel darkening; applying that
  same ~0.6 factor to the new red (`233,1,48`) gives `rgb(140,1,29)`. Treat
  this one value as a reasonable approximation, not a Tier-A verified brand
  constant — if a future pass finds an official darker/2nd-accent shade,
  prefer that over this scaled value.
- `_ActionColorTrans` and `_HoverColor` keep their original alpha channel and
  only swap the RGB triplet.

## How to apply to a new/future site

1. Open that site's `brandingSets/<name>.json`.
2. Confirm it is the site's *active* branding set (cross-check
   `activeBrandingSetId` in the sibling `themes/<name>.json`) before editing —
   editing an inactive/unused branding set has no visible effect and can be
   mistaken for "the fix didn't work."
3. Apply the table above verbatim; leave every other key untouched.
4. Do not touch `PrimaryFont`/`HeaderFonts` in the same pass (see Scope
   above) unless that is explicitly a separate, scoped task.
