// Offering wizard config — seeds Migration Accelerator's own
// migration-accelerator::configurator::defaults::sizePresets row so the
// cutover to CMS-driven Environment-step presets changes nothing observable:
// this carries gtmConfigWizard.js's historical hardcoded S/M/L numbers,
// verbatim, as this offering's own authored content.
//
// Reuses the existing 'offering-defaults' JSON vocabulary and the same
// generic repeatable-item JSON editor already used for 'swatches' on this
// same section (Configurator defaults) — no new section, layout type or
// object. Idempotent: upserts by Content_Address__c external ID.
//
// Run via: sf apex run --file scripts/data/seed-config-wizard-size-presets.apex --target-org gtm-prod

String sizePresetsJson = JSON.serialize(new List<Map<String, Object>>{
    new Map<String, Object>{ 'key' => 'S', 'label' => 'Small',  'sub' => 'Under 1,000 assets', 'assetCount' => 800,   'dependencyCount' => 1400,  'healthScore' => 78 },
    new Map<String, Object>{ 'key' => 'M', 'label' => 'Medium', 'sub' => '~4,000 assets',       'assetCount' => 4128,  'dependencyCount' => 9640,  'healthScore' => 62 },
    new Map<String, Object>{ 'key' => 'L', 'label' => 'Large',  'sub' => '10,000+ assets',      'assetCount' => 12400, 'dependencyCount' => 26800, 'healthScore' => 45 }
});

GtmPageContentController.ContentRecord r = new GtmPageContentController.ContentRecord();
r.offeringKey  = 'migration-accelerator';
r.templateType = 'configurator';
r.sectionKey   = 'defaults';
r.fieldKey     = 'sizePresets';
r.fieldType    = 'json';
r.jsonValue    = sizePresetsJson;
r.active       = true;
r.status       = 'Published';
r.sortOrder    = 40; // after genericDemoDeps/genericChips/swatches on this section

List<String> ids = GtmPageContentController.saveContentRecords(
    new List<GtmPageContentController.ContentRecord>{ r }
);
System.debug('Seeded sizePresets content row, id=' + ids[0]);

System.debug('=== verify ===');
Map<String, String> content = GtmPageContentReader.getPageContent('migration-accelerator', 'configurator', null);
System.debug('defaults::sizePresets => ' + content.get('defaults::sizePresets'));
