// Seed MA_Page_Content__c records for migration-accelerator story template
// Run via: sf apex run --file scripts/seed-ma-page-content.apex
// Uses upsert on Content_Address__c external ID — safe to re-run any time.
// Records are created with Active__c=true so they immediately serve content.

String ofk = 'migration-accelerator';
String ts = 'story';

List<MA_Page_Content__c> recs = new List<MA_Page_Content__c>{

    // ── HERO ──────────────────────────────────────────────────────────────────
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'hero', Field_Key__c = 'eyebrow',
        Field_Type__c = 'text', Active__c = true, Sort_Order__c = 10,
        Text_Value__c = 'Internal positioning · GTM buy-in'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'hero', Field_Key__c = 'headline',
        Field_Type__c = 'text', Active__c = true, Sort_Order__c = 20,
        Text_Value__c = 'Every migration starts with a decade nobody documented. We read it in an afternoon.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'hero', Field_Key__c = 'subhead',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 30,
        Rich_Value__c = 'How Migration Accelerator turns an untrusted platform and a go-live date that won\'t move into a plan, and increasingly, a finished migration.'
    ),

    // ── PROBLEM ───────────────────────────────────────────────────────────────
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'problem', Field_Key__c = 'lede',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 10,
        Rich_Value__c = 'Every enterprise migration starts the same way.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'problem', Field_Key__c = 'chips',
        Field_Type__c = 'json', Active__c = true, Sort_Order__c = 20,
        JSON_Value__c = '["A platform nobody fully trusts","A decade of undocumented campaigns","A go-live date that won\'t move"]'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'problem', Field_Key__c = 'close',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 30,
        Rich_Value__c = 'Migration Accelerator starts working before the rebuild, before the plan, at the part everyone dreads: finding out what\'s actually there.'
    ),

    // ── MECHANISM ─────────────────────────────────────────────────────────────
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'mechanism', Field_Key__c = 'head',
        Field_Type__c = 'text', Active__c = true, Sort_Order__c = 10,
        Text_Value__c = 'Point it at the platform.\nGet a plan you can act on.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'mechanism', Field_Key__c = 'sub',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 20,
        Rich_Value__c = 'Point it at a client\'s email tool (ex: SFMC, Eloqua, etc) — get a build-ready plan out, and for the pieces it\'s confident about, a finished migration.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'mechanism', Field_Key__c = 'routeSteps',
        Field_Type__c = 'json', Active__c = true, Sort_Order__c = 30,
        JSON_Value__c = '[{"stepLabel":"Ingest","stepDesc":"Every asset, read directly"},{"stepLabel":"Audit","stepDesc":"A live health score"},{"stepLabel":"Decide","stepDesc":"Port, rework, retire, logged"},{"stepLabel":"Plan","stepDesc":"Dependencies pulled automatically"},{"stepLabel":"Execute","stepDesc":"Dry run, then live, rollback ready"}]'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'mechanism', Field_Key__c = 'proofCtaText',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 40,
        Rich_Value__c = 'A snapshot of what the platform reads from an environment, automatically, on day one.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'mechanism', Field_Key__c = 'proofDemoRoot',
        Field_Type__c = 'text', Active__c = true, Sort_Order__c = 50,
        Text_Value__c = 'APAC Onboarding'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'mechanism', Field_Key__c = 'proofDemoDeps',
        Field_Type__c = 'json', Active__c = true, Sort_Order__c = 60,
        JSON_Value__c = '["Welcome email","Shared data extension","Brand header"]'
    ),

    // ── CAPABILITIES ──────────────────────────────────────────────────────────
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'capabilities', Field_Key__c = 'cards',
        Field_Type__c = 'json', Active__c = true, Sort_Order__c = 10,
        JSON_Value__c = '[{"icon":"In","cardTitle":"Ingestion & inventory","cardDesc":"Automatic, for any major marketing automation platform.","isNew":false},{"icon":"Au","cardTitle":"Automated audit","cardDesc":"A health score plus an exportable report, generated on demand.","isNew":true},{"icon":"De","cardTitle":"Disposition & audit trail","cardDesc":"Port, rework, or retire, on every object, with full history.","isNew":false},{"icon":"Pl","cardTitle":"Dependency-aware planning","cardDesc":"Assigning one object pulls in everything it needs, automatically.","isNew":false},{"icon":"Sp","cardTitle":"AI-drafted build specs","cardDesc":"Human-reviewed requirements per object, down to Journey Builder specs.","isNew":false},{"icon":"Ex","cardTitle":"Live execution & rollback","cardDesc":"Dry run, then live, with a verification pass once it finishes.","isNew":true}]'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'capabilities', Field_Key__c = 'bonusCard',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 20,
        Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline. An approved Figma layout becomes a built, publishable email, no separate rebuild.'
    ),

    // ── CLIENT PROFILE ────────────────────────────────────────────────────────
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'clientProfile', Field_Key__c = 'statBig',
        Field_Type__c = 'text', Active__c = true, Sort_Order__c = 10,
        Text_Value__c = '500–2,000+'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'clientProfile', Field_Key__c = 'statDesc',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 20,
        Rich_Value__c = 'objects is where this offering\'s advantage is largest, enterprise accounts migrating between major marketing automation platforms, carrying a sizable, under-documented environment.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'clientProfile', Field_Key__c = 'note',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 30,
        Rich_Value__c = 'Today, this runs through us, in working sessions, not a self-serve portal, and that\'s exactly how it should work for now.'
    ),

    // ── BD / HOW TO RUN IT ────────────────────────────────────────────────────
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'bd', Field_Key__c = 'head',
        Field_Type__c = 'text', Active__c = true, Sort_Order__c = 10,
        Text_Value__c = 'One story. Here\'s how to run it.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'bd', Field_Key__c = 'lede',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 20,
        Rich_Value__c = 'This is the pitch, the same one a client hears. The job is fluency in it, plus the tools to make it specific to whoever\'s in the room.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'bd', Field_Key__c = 'useCases',
        Field_Type__c = 'json', Active__c = true, Sort_Order__c = 30,
        JSON_Value__c = '[{"caseTitle":"Presales","caseDesc":"Run a prospect\'s export before the SOW. Walk in with a real health score, not a guess."},{"caseTitle":"Delivery","caseDesc":"Run the full engagement through it, start to finish, and increasingly, the cutover itself."},{"caseTitle":"The pitch","caseDesc":"A real environment becoming a real plan, live, in the room, not described afterward."}]'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'bd', Field_Key__c = 'pitchOldChips',
        Field_Type__c = 'json', Active__c = true, Sort_Order__c = 40,
        JSON_Value__c = '["A promise to figure out scope after signature","An estimate built on intuition","A plan that ends in a manual handoff"]'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'bd', Field_Key__c = 'pitchNewChips',
        Field_Type__c = 'json', Active__c = true, Sort_Order__c = 50,
        JSON_Value__c = '["A real health score, produced live, in the room","Scope set from the actual environment","A dry run, and where it applies, a finished cutover"]'
    ),

    // ── CLOSING ───────────────────────────────────────────────────────────────
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'closing', Field_Key__c = 'head',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 10,
        Rich_Value__c = 'This is Migration Accelerator today: an offering built on evidence, moving toward a finished migration instead of a plan for one.'
    ),
    new MA_Page_Content__c(
        Offering_Key__c = ofk, Template_Type__c = ts,
        Section_Key__c = 'closing', Field_Key__c = 'sub',
        Field_Type__c = 'rich', Active__c = true, Sort_Order__c = 20,
        Rich_Value__c = 'The next step is putting a name and an industry behind it.'
    )

};

try {
    Database.UpsertResult[] results = Database.upsert(recs, MA_Page_Content__c.Content_Address__c, false);
    Integer ok = 0;
    Integer fail = 0;
    for (Database.UpsertResult r : results) {
        if (r.isSuccess()) ok++;
        else {
            fail++;
            for (Database.Error e : r.getErrors()) {
                System.debug('SEED ERROR: ' + e.getMessage() + ' | fields: ' + e.getFields());
            }
        }
    }
    System.debug('Seed complete — ' + ok + ' upserted, ' + fail + ' failed.');
} catch (Exception ex) {
    System.debug('Seed failed: ' + ex.getMessage());
    throw ex;
}
