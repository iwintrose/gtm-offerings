# Runbook — deleting a component referenced by an Experience Cloud site

Salesforce **never** deletes an Experience Cloud site: `destructiveChanges`
on the site bundle itself returns *"You can't delete an Experience Cloud
site."* Archiving is not enough either — an archived site keeps a
**published snapshot**, and a component referenced by that snapshot cannot
be deleted even though the site is archived.

This runbook is for the narrower, real case: a component (a page, an LWC, a
FlexiPage) needs to go, and it's still referenced by a live or archived
site's published snapshot.

## The procedure

1. **Unarchive the site.** UI only — there is no API path. `Network` is not
   updatable from Apex, and `PATCH /connect/communities/{id}` returns
   `METHOD_NOT_ALLOWED`.
2. **Deploy the site's `Network` metadata with `<status>UnderConstruction</status>`.**
   Deploying `<status>Live</status>` directly is rejected with a misleading
   *"still active … before you archive"* error; `UnderConstruction` is
   accepted.
3. **Deploy the edited `ExperienceBundle`** so the site no longer references
   the component you're removing.
4. **Publish.** `sf community publish -n "<site name>"` replaces the
   published snapshot with the current, edited one. This step fails with
   `INSUFFICIENT_ACCESS` while the site is inactive — it only works once the
   site is at least `UnderConstruction`, not archived.
5. **Run the destructive deploy.** With the snapshot no longer referencing
   the component, it now succeeds.
6. **Put the site back** with `<status>DownForMaintenance</status>` (or
   `Live`, if it should stay serving traffic) — do not leave it sitting at
   `UnderConstruction`.

## Before deleting any component, confirm against the org

`scripts/check-references.py` scans this branch's source only. Experience
Builder keeps page layouts in the org, and they do not reliably round-trip
through the site bundles in source — a component can read as an orphan here
while the org still has it wired into a live page. Confirm against the org
first (the script prints the query to run), or let the destructive deploy
itself refuse: it names the exact pages still referencing the component,
which is the authoritative answer either way.

## Source

Extracted from `HANDOVER.md`'s "Delete the GTM Framework site" note (resolved
— the *method* used there is what's captured here), written when this
exact sequence was worked out against the org.
