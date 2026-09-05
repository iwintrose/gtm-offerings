// D8 — copies Gus the assistant's CMS content off Migration Accelerator's own
// configurator page and onto the framework-level address every offering's
// configurator now also reads from.
//
// Gus is meant to be one assistant shared by every offering, not copy that
// belongs to migration-accelerator specifically. gtmConfigurator.js already
// fetches getPageLayout({ offeringKey: FRAMEWORK_KEY, templateType:
// 'assistant', industryKey: null }) and merges its .content into the same
// _cms bag the assistant getters read from, so once real rows exist at
// gtm::assistant::assistant::*, the page picks them up with no further JS
// change.
//
// This COPIES the five fields; it does not delete the old
// migration-accelerator::configurator::assistant::* rows. Those stay in place
// until the new address is verified live in the running app — a second
// cleanup pass, intentionally out of scope here.
//
// Idempotent: both the section and the content rows are upserted by their
// address external ID, so running this more than once does not duplicate
// anything or clobber a value someone has already edited at the new address
// (a content row already there is left alone rather than overwritten, so a
// re-run after a BA has started customising it can't stomp their edit).
//
// Run via: sf apex run --file scripts/data/migrate-assistant-to-framework.apex -o gtm-dev

String OLD_OFK = 'migration-accelerator';
String OLD_TT  = 'configurator';
String NEW_OFK = 'gtm';       // GtmContentAddress / c/gtmPageLayouts FRAMEWORK_KEY
String NEW_TT  = 'assistant';
String SECTION = 'assistant';

List<String> fieldKeys = new List<String>{
    'assistantName', 'assistantRole', 'fabLabel', 'greeting', 'inputPlaceholder'
};

// ── 1. The section record ───────────────────────────────────────────────────
// getPageLayout only draws sections it can find Active + Published; content
// rows alone are not enough for the generic Content Manager editor (or the
// public reader's section list) to know this page exists.
String newSectionAddress = GtmContentAddress.forSection(NEW_OFK, NEW_TT, SECTION);
List<MA_Page_Section__c> existingSection = [
    SELECT Id FROM MA_Page_Section__c WHERE Section_Address__c = :newSectionAddress LIMIT 1
];
if (existingSection.isEmpty()) {
    MA_Page_Section__c sec = new MA_Page_Section__c();
    sec.Section_Address__c = newSectionAddress;
    sec.Offering_Key__c    = NEW_OFK;
    sec.Template_Type__c   = NEW_TT;
    sec.Section_Key__c     = SECTION;
    sec.Label__c           = 'Assistant';
    sec.Help_Text__c       = 'The one assistant character every offering’s configurator shows: name, role, greeting, button label and input prompt.';
    sec.Layout_Type__c     = 'assistant';
    sec.Width__c           = 'standard';
    sec.Active__c          = true;
    sec.Sort_Order__c      = 10;
    sec.Status__c          = 'Published';
    insert sec;
    System.debug('created section ' + newSectionAddress);
} else {
    System.debug('section already exists, left alone: ' + newSectionAddress);
}

// ── 2. The five content rows ────────────────────────────────────────────────
// Read the old rows by their address, keyed by field so a missing one is
// reported by name rather than silently producing four rows instead of five.
Map<String, String> oldAddressByField = new Map<String, String>();
for (String fieldKey : fieldKeys) {
    oldAddressByField.put(fieldKey, GtmContentAddress.forField(OLD_OFK, OLD_TT, SECTION, fieldKey));
}

Map<String, MA_Page_Content__c> oldByAddress = new Map<String, MA_Page_Content__c>();
for (MA_Page_Content__c rec : [
    SELECT Content_Address__c, Field_Key__c, Field_Type__c, Label__c, Help_Text__c,
           Text_Value__c, Rich_Value__c, JSON_Value__c, Sort_Order__c
    FROM   MA_Page_Content__c
    WHERE  Content_Address__c IN :oldAddressByField.values()
]) {
    oldByAddress.put(rec.Content_Address__c, rec);
}

// Only touch a row whose new address does not already carry a real value —
// this is what makes a re-run safe once a BA has started editing at the new
// address: their edit is a value the copy source never produced, so it wins.
Set<String> newAddresses = new Set<String>();
for (String fieldKey : fieldKeys) {
    newAddresses.add(GtmContentAddress.forField(NEW_OFK, NEW_TT, SECTION, fieldKey));
}
Set<String> newAddressesAlreadyPresent = new Set<String>();
for (MA_Page_Content__c rec : [
    SELECT Content_Address__c FROM MA_Page_Content__c WHERE Content_Address__c IN :newAddresses
]) {
    newAddressesAlreadyPresent.add(rec.Content_Address__c);
}

List<MA_Page_Content__c> toUpsert = new List<MA_Page_Content__c>();
Integer order = 10;
for (String fieldKey : fieldKeys) {
    String oldAddress = oldAddressByField.get(fieldKey);
    String newAddress = GtmContentAddress.forField(NEW_OFK, NEW_TT, SECTION, fieldKey);
    MA_Page_Content__c src = oldByAddress.get(oldAddress);
    if (src == null) {
        System.debug('WARNING: no source row at ' + oldAddress + ' — skipping ' + fieldKey);
        order += 10;
        continue;
    }
    if (newAddressesAlreadyPresent.contains(newAddress)) {
        System.debug('new row already exists, left alone: ' + newAddress);
        order += 10;
        continue;
    }

    MA_Page_Content__c row = new MA_Page_Content__c();
    row.Content_Address__c = newAddress;
    row.Offering_Key__c    = NEW_OFK;
    row.Template_Type__c   = NEW_TT;
    row.Section_Key__c     = SECTION;
    row.Field_Key__c       = fieldKey;
    row.Field_Type__c      = src.Field_Type__c;
    row.Label__c           = src.Label__c;
    row.Help_Text__c       = src.Help_Text__c;
    row.Text_Value__c      = src.Text_Value__c;
    row.Rich_Value__c      = src.Rich_Value__c;
    row.JSON_Value__c      = src.JSON_Value__c;
    row.Sort_Order__c      = order;
    row.Active__c          = true;
    // These are already-live values being given a new address, not a fresh
    // draft awaiting a publish — the editor should show them as published,
    // and the public reader ignores Status__c for content rows anyway.
    row.Status__c          = 'Published';
    toUpsert.add(row);
    order += 10;
}

if (toUpsert.isEmpty()) {
    System.debug('Nothing to write — every field was either already migrated or had no source row.');
} else {
    upsert toUpsert Content_Address__c;
    System.debug('Migrated ' + toUpsert.size() + ' of ' + fieldKeys.size() + ' assistant field(s) to '
        + NEW_OFK + '::' + NEW_TT + '::' + SECTION + '::*');
}

System.debug('=== verify ===');
for (MA_Page_Content__c rec : [
    SELECT Content_Address__c, Field_Key__c, Text_Value__c
    FROM   MA_Page_Content__c
    WHERE  Content_Address__c IN :newAddresses
    ORDER BY Sort_Order__c
]) {
    System.debug('  ' + rec.Content_Address__c + ' = ' + rec.Text_Value__c);
}
