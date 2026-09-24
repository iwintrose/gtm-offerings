# ADR-0002 — Permission-set grants are part of a field/object/tab's definition of done

**Status:** Accepted

## Context

A new custom field, object, or tab is invisible to anything that respects
field-level security and CRUD until it is explicitly granted in a permission
set — Salesforce does not grant it by default just because the metadata
deployed cleanly. This gap has been found and fixed repeatedly on this
project, not once:

- `GTM_Config_Manager` — the permission set reps actually use — had never
  been granted access to `GTM_Page_Content__c`/`GTM_Page_Section__c` at all;
  an earlier rename pass cloned grants into every other permission set but
  missed this one, and it was also the *only* permission set holding grants
  for the objects it was replacing (see `docs/backlog.md`, the D6 cutover
  entry).
- Object and tab access on `GTM_Saved_Configuration__c`, `GTM_Readout__c`,
  `GTM_Readout_Version__c`, and the `GTM_Content_Home` tab (historical: that tab was retired in `app-landing-page`, replaced by a Home FlexiPage) have each, at
  points during this build, needed an explicit grant added after the
  underlying metadata already existed and looked deployed.

Every one of these was a deploy that reported success while quietly leaving
a feature unusable for the people meant to use it — the failure mode
doesn't surface as an error, it surfaces as a rep or a component silently
seeing nothing.

## Decision

Granting the relevant permission set(s) is part of the **definition of
done** for any change that adds a field, object, or tab — not a follow-up
task, not something to notice only when someone reports it broken. A change
that adds schema without touching `force-app/main/default/permissionsets/`
in the same commit should be treated as incomplete. Whoever reviews the
change — a human, since this repo has no dedicated review agent — checks
for the matching grant the same way they'd check for a missing test.

## Consequences

- Permission-set files see more diff noise per change, since a grant has to
  be added deliberately rather than left implicit.
- The alternative — discovering the gap by live-testing after deploy, which
  is how every instance above was actually found — costs real time against
  a real org and is worse.
- The five permission sets to check against are
  `force-app/main/default/permissionsets/GTM_Config_Manager`,
  `GTM_Config_View_All`, `GTM_Assessment_Guest`, `GTM_Story_Guest`, and
  `GTM_Platform_Visibility`.
