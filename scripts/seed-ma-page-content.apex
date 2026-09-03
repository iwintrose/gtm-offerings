// Seed MA_Page_Content__c records for migration-accelerator story template.
// Run via: sf apex run --file scripts/seed-ma-page-content.apex
// Uses MaPageContentController.saveContentRecords() to work around the
// anonymous-Apex schema cache not yet reflecting newly-deployed custom fields.

String ofk = 'migration-accelerator';
String ts  = 'story';

List<MaPageContentController.ContentRecord> recs = new List<MaPageContentController.ContentRecord>();

// ── HERO ──────────────────────────────────────────────────────────────────
MaPageContentController.ContentRecord r;

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'hero'; r.fieldKey = 'eyebrow'; r.fieldType = 'text';
r.active = true; r.sortOrder = 10;
r.textValue = 'Internal positioning · GTM buy-in';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'hero'; r.fieldKey = 'headline'; r.fieldType = 'text';
r.active = true; r.sortOrder = 20;
r.textValue = 'Every migration starts with a decade nobody documented. We read it in an afternoon.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'hero'; r.fieldKey = 'subhead'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 30;
r.richValue = 'How Migration Accelerator turns an untrusted platform and a go-live date that won\'t move into a plan, and increasingly, a finished migration.';
recs.add(r);

// ── PROBLEM ───────────────────────────────────────────────────────────────

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'problem'; r.fieldKey = 'lede'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 10;
r.richValue = 'Every enterprise migration starts the same way.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'problem'; r.fieldKey = 'chips'; r.fieldType = 'json';
r.active = true; r.sortOrder = 20;
r.jsonValue = '["A platform nobody fully trusts","A decade of undocumented campaigns","A go-live date that won\'t move"]';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'problem'; r.fieldKey = 'close'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 30;
r.richValue = 'Migration Accelerator starts working before the rebuild, before the plan, at the part everyone dreads: finding out what\'s actually there.';
recs.add(r);

// ── MECHANISM ─────────────────────────────────────────────────────────────

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'mechanism'; r.fieldKey = 'head'; r.fieldType = 'text';
r.active = true; r.sortOrder = 10;
r.textValue = 'Point it at the platform.\nGet a plan you can act on.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'mechanism'; r.fieldKey = 'sub'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 20;
r.richValue = 'Point it at a client\'s email tool (ex: SFMC, Eloqua, etc) — get a build-ready plan out, and for the pieces it\'s confident about, a finished migration.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'mechanism'; r.fieldKey = 'routeSteps'; r.fieldType = 'json';
r.active = true; r.sortOrder = 30;
r.jsonValue = '[{"stepLabel":"Ingest","stepDesc":"Every asset, read directly"},{"stepLabel":"Audit","stepDesc":"A live health score"},{"stepLabel":"Decide","stepDesc":"Port, rework, retire, logged"},{"stepLabel":"Plan","stepDesc":"Dependencies pulled automatically"},{"stepLabel":"Execute","stepDesc":"Dry run, then live, rollback ready"}]';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'mechanism'; r.fieldKey = 'proofCtaText'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 40;
r.richValue = 'A snapshot of what the platform reads from an environment, automatically, on day one.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'mechanism'; r.fieldKey = 'proofDemoRoot'; r.fieldType = 'text';
r.active = true; r.sortOrder = 50;
r.textValue = 'APAC Onboarding';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'mechanism'; r.fieldKey = 'proofDemoDeps'; r.fieldType = 'json';
r.active = true; r.sortOrder = 60;
r.jsonValue = '["Welcome email","Shared data extension","Brand header"]';
recs.add(r);

// ── CAPABILITIES ──────────────────────────────────────────────────────────

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'capabilities'; r.fieldKey = 'cards'; r.fieldType = 'json';
r.active = true; r.sortOrder = 10;
r.jsonValue = '[{"icon":"In","cardTitle":"Ingestion & inventory","cardDesc":"Automatic, for any major marketing automation platform.","isNew":false},{"icon":"Au","cardTitle":"Automated audit","cardDesc":"A health score plus an exportable report, generated on demand.","isNew":true},{"icon":"De","cardTitle":"Disposition & audit trail","cardDesc":"Port, rework, or retire, on every object, with full history.","isNew":false},{"icon":"Pl","cardTitle":"Dependency-aware planning","cardDesc":"Assigning one object pulls in everything it needs, automatically.","isNew":false},{"icon":"Sp","cardTitle":"AI-drafted build specs","cardDesc":"Human-reviewed requirements per object, down to Journey Builder specs.","isNew":false},{"icon":"Ex","cardTitle":"Live execution & rollback","cardDesc":"Dry run, then live, with a verification pass once it finishes.","isNew":true}]';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'capabilities'; r.fieldKey = 'bonusCard'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 20;
r.richValue = '<strong>Also in the toolkit:</strong> a design-to-email pipeline. An approved Figma layout becomes a built, publishable email, no separate rebuild.';
recs.add(r);

// ── CLIENT PROFILE ────────────────────────────────────────────────────────

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'clientProfile'; r.fieldKey = 'statBig'; r.fieldType = 'text';
r.active = true; r.sortOrder = 10;
r.textValue = '500–2,000+';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'clientProfile'; r.fieldKey = 'statDesc'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 20;
r.richValue = 'objects is where this offering\'s advantage is largest, enterprise accounts migrating between major marketing automation platforms, carrying a sizable, under-documented environment.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'clientProfile'; r.fieldKey = 'note'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 30;
r.richValue = 'Today, this runs through us, in working sessions, not a self-serve portal, and that\'s exactly how it should work for now.';
recs.add(r);

// ── BD / HOW TO RUN IT ────────────────────────────────────────────────────

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'bd'; r.fieldKey = 'head'; r.fieldType = 'text';
r.active = true; r.sortOrder = 10;
r.textValue = 'One story. Here\'s how to run it.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'bd'; r.fieldKey = 'lede'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 20;
r.richValue = 'This is the pitch, the same one a client hears. The job is fluency in it, plus the tools to make it specific to whoever\'s in the room.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'bd'; r.fieldKey = 'useCases'; r.fieldType = 'json';
r.active = true; r.sortOrder = 30;
r.jsonValue = '[{"caseTitle":"Presales","caseDesc":"Run a prospect\'s export before the SOW. Walk in with a real health score, not a guess."},{"caseTitle":"Delivery","caseDesc":"Run the full engagement through it, start to finish, and increasingly, the cutover itself."},{"caseTitle":"The pitch","caseDesc":"A real environment becoming a real plan, live, in the room, not described afterward."}]';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'bd'; r.fieldKey = 'pitchOldChips'; r.fieldType = 'json';
r.active = true; r.sortOrder = 40;
r.jsonValue = '["A promise to figure out scope after signature","An estimate built on intuition","A plan that ends in a manual handoff"]';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'bd'; r.fieldKey = 'pitchNewChips'; r.fieldType = 'json';
r.active = true; r.sortOrder = 50;
r.jsonValue = '["A real health score, produced live, in the room","Scope set from the actual environment","A dry run, and where it applies, a finished cutover"]';
recs.add(r);

// ── CLOSING ───────────────────────────────────────────────────────────────

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'closing'; r.fieldKey = 'head'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 10;
r.richValue = 'This is Migration Accelerator today: an offering built on evidence, moving toward a finished migration instead of a plan for one.';
recs.add(r);

r = new MaPageContentController.ContentRecord();
r.offeringKey = ofk; r.templateType = ts;
r.sectionKey = 'closing'; r.fieldKey = 'sub'; r.fieldType = 'rich';
r.active = true; r.sortOrder = 20;
r.richValue = 'The next step is putting a name and an industry behind it.';
recs.add(r);

// ── Upsert via controller ─────────────────────────────────────────────────
try {
    List<String> ids = MaPageContentController.saveContentRecords(recs);
    Integer ok = 0;
    for (String id : ids) {
        if (String.isNotBlank(id)) ok++;
    }
    System.debug('Seed complete — ' + ok + ' of ' + ids.size() + ' upserted.');
} catch (Exception ex) {
    System.debug('Seed failed: ' + ex.getMessage());
    throw ex;
}
