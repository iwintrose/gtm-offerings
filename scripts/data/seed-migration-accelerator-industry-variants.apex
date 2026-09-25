// Issue #industry-variants-content-load -- loads real, industry-tailored copy
// for Migration Accelerator's problem/capabilities/clientProfile/faq sections,
// across the 9 active industries seeded by
// scripts/data/seed-industry-chooser-industries.apex (slugs match verbatim).
//
// Mirrors that script's pattern: idempotent by construction, upserting on
// Section_Address__c / Content_Address__c (both externalId/unique), so a
// re-run leaves row counts unchanged. Uses GTM_Page_Section__c's
// Industry_Key__c / Base_Section_Key__c variant model added by the
// industry-variants-core issue (createSection's underlying data shape) --
// writes records directly rather than through the Content Manager's
// '+ Industry variant' Aura-enabled flow, because 36 UI round trips is
// impractical at this volume (per TASK_SCOPE.md's stated Developer discretion).
//
// Variant sections are written as Status__c='Published', Active__c=true,
// Draft_State__c left null, so GtmPageContentReader.getPageLayout picks them
// up immediately without a separate publish step -- the same 'live on write'
// posture as the industry-chooser seed script's records.
//
// Out of scope (per TASK_SCOPE.md): hero, mechanism, pivot, bd, closing,
// header, footer stay generic -- no variant rows are written for them.
//
// STAGING ONLY. Never run this against gtm-prod.
// Run via: sf apex run --file scripts/data/seed-migration-accelerator-industry-variants.apex --target-org gtm-staging
//
// Verify via:
//   SELECT COUNT() FROM GTM_Page_Section__c
//    WHERE Offering_Key__c = 'migration-accelerator' AND Base_Section_Key__c != null
//   -- expect 36 (9 industries x 4 base sections)
//   SELECT COUNT() FROM GTM_Page_Content__c
//    WHERE Offering_Key__c = 'migration-accelerator' AND Industry_Key__c != null
//   -- run the script a second time and confirm both counts are unchanged.

String OFK = 'migration-accelerator';
String TPL = 'story';

// Base section key -> { Layout_Type__c, Label__c } -- copied onto each
// variant so the variant substitutes cleanly per GtmPageContentReader's
// variantsByBase lookup (label/layout/width come from the variant row).
Map<String, String[]> BASE_META = new Map<String, String[]>{
    'problem' => new String[]{ 'lede-chips', 'The Problem' },
    'capabilities' => new String[]{ 'card-grid', 'Capabilities' },
    'clientProfile' => new String[]{ 'stat', 'Client Profile' },
    'faq' => new String[]{ 'faq', 'FAQ' },
};

// slug -> display label. Must match seed-industry-chooser-industries.apex's
// INDUSTRIES map keys verbatim -- diffed against that script before drafting
// (TASK_SCOPE.md requirement); no drift found as of this run.
Map<String, String> INDUSTRIES = new Map<String, String>{
    'consumer-products' => 'Consumer Products',
    'energy-commodities' => 'Energy & Commodities',
    'financial-services' => 'Financial Services',
    'health' => 'Health',
    'public-sector' => 'Public Sector',
    'retail' => 'Retail',
    'telecommunications-media-technology' => 'Telecom, Media & Tech',
    'transportation-mobility' => 'Transportation & Mobility',
    'travel-hospitality' => 'Travel & Hospitality',
};

List<GTM_Page_Section__c> sectionsToUpsert = new List<GTM_Page_Section__c>();
List<GTM_Page_Content__c> contentToUpsert = new List<GTM_Page_Content__c>();

// ---- Consumer Products (consumer-products) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--consumer-products';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--consumer-products';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'consumer-products';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--consumer-products' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--consumer-products';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every DTC relaunch starts the same way: migrate the platform, lose the customer 360 view.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--consumer-products' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--consumer-products';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["A loyalty program nobody can re-target on day one", "Trade-promotion history nobody can trace back", "A go-live date that can\'t slip past peak season"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--consumer-products' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--consumer-products';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator keeps your DTC, loyalty and trade-promotion data unified through cutover, so customer 360 never blinks.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--consumer-products';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--consumer-products';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'consumer-products';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--consumer-products' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--consumer-products';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--consumer-products' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--consumer-products';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for DTC and loyalty.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--consumer-products' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--consumer-products';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "DT", "cardTitle": "DTC + loyalty continuity", "cardDesc": "Customer 360 profiles, loyalty tiers and trade-promotion history are mapped and validated before cutover, not rebuilt after.", "isNew": false}, {"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every DTC and loyalty journey, generated on demand, so nothing launches on guesswork.", "isNew": true}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Migrating a loyalty program pulls in every trade-promotion and segmentation dependency automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Always-on cutover", "cardDesc": "Dry run, then live, timed around your promotional calendar, with rollback ready if peak-season traffic doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--consumer-products' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--consumer-products';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline built for always-on DTC cadences. An approved Figma layout becomes a publishable campaign, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--consumer-products';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--consumer-products';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'consumer-products';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--consumer-products' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--consumer-products';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--consumer-products' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--consumer-products';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: DTC and loyalty.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--consumer-products' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--consumer-products';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--consumer-products' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--consumer-products';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where DTC and loyalty programs carrying trade-promotion history see the largest advantage, brands consolidating customer 360 across a fragmented martech stack.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--consumer-products' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--consumer-products';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions alongside your loyalty and DTC teams, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--consumer-products';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--consumer-products';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'consumer-products';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--consumer-products' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--consumer-products';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--consumer-products' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--consumer-products';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions DTC and loyalty teams ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--consumer-products' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--consumer-products';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'consumer-products';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Will our loyalty tiers and trade-promotion history survive the cutover intact?", "verdict": "Yes", "answer": "Loyalty tiers, points balances and trade-promotion history are inventoried, mapped and validated in a dry run before anything goes live, so customer 360 doesn\'t reset at cutover."}, {"question": "Can we migrate without pausing always-on DTC campaigns?", "verdict": "Yes", "answer": "Execution runs against a live cutover plan timed to your promotional calendar, so always-on journeys keep firing through the transition."}]';
    contentToUpsert.add(row);
}

// ---- Energy & Commodities (energy-commodities) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--energy-commodities';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--energy-commodities';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'energy-commodities';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--energy-commodities' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--energy-commodities';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every regulated migration starts the same way: a notice pipeline nobody\'s willing to risk.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--energy-commodities' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--energy-commodities';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["A rate-case notice that can\'t miss its filing window", "Demand-response alerts nobody can afford to drop", "A go-live date compliance won\'t move for anyone"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--energy-commodities' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--energy-commodities';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator treats every C&I and regulated-notice workflow as a compliance boundary, not a nice-to-have, so nothing goes dark during cutover.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--energy-commodities';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--energy-commodities';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'energy-commodities';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--energy-commodities' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--energy-commodities';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--energy-commodities' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--energy-commodities';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for regulated notice delivery.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--energy-commodities' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--energy-commodities';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every regulated notice and demand-response workflow, generated on demand, before anyone commits to a date.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every NERC/FERC-relevant object, with full history preserved for the record.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Assigning a rate-case notice pulls in every C&I account and demand-response trigger it depends on, automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready if a regulated alert doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--energy-commodities' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--energy-commodities';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline for regulated notices. An approved template becomes a compliant, publishable alert, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--energy-commodities';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--energy-commodities';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'energy-commodities';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--energy-commodities' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--energy-commodities';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--energy-commodities' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--energy-commodities';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: regulated C&I programs.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--energy-commodities' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--energy-commodities';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--energy-commodities' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--energy-commodities';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where regulated C&I and demand-response programs see the largest advantage, utilities and commodities firms carrying under-documented compliance workflows.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--energy-commodities' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--energy-commodities';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions with your compliance and regulatory-affairs stakeholders in the room, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--energy-commodities';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--energy-commodities';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'energy-commodities';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--energy-commodities' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--energy-commodities';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--energy-commodities' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--energy-commodities';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions compliance teams ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--energy-commodities' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--energy-commodities';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'energy-commodities';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Does migration risk a gap in regulated notice delivery?", "verdict": "No", "answer": "Every rate-case and demand-response notice workflow is inventoried and dry-run before go-live, with rollback ready, so there is no gap risk to filing windows or C&I alerts."}, {"question": "Can it preserve the audit trail regulators expect?", "verdict": "Yes", "answer": "Disposition and history are kept on every object ported, reworked or retired, so the record survives cutover exactly as filed."}]';
    contentToUpsert.add(row);
}

// ---- Financial Services (financial-services) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--financial-services';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--financial-services';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'financial-services';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--financial-services' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--financial-services';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every regulated migration starts the same way: a record nobody wants to be the one that broke it.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--financial-services' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--financial-services';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["A retention window that can\'t have a gap", "A book of record nobody can fully reconcile", "A go-live date the exam calendar won\'t move for"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--financial-services' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--financial-services';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator preserves the full audit trail and record-retention chain through cutover, so nothing in the book of record goes missing.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--financial-services';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--financial-services';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'financial-services';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--financial-services' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--financial-services';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--financial-services' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--financial-services';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for regulated records.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--financial-services' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--financial-services';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across suitability, KYC/AML and book-of-record data, generated on demand, before anything is scheduled.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every FINRA/SEC/GLBA-relevant object, with full history, so the retention chain never breaks.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Migrating a book-of-record object pulls in every suitability and KYC/AML dependency it needs, automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready if a retention record doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--financial-services' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--financial-services';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline reviewed against your compliance templates. An approved layout becomes a publishable, auditable email, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--financial-services';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--financial-services';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'financial-services';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--financial-services' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--financial-services';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--financial-services' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--financial-services';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: regulated book-of-record data.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--financial-services' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--financial-services';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--financial-services' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--financial-services';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where suitability, KYC/AML and book-of-record data see the largest advantage, regulated firms carrying a sizable, audit-sensitive environment.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--financial-services' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--financial-services';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions with compliance and risk in the room, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--financial-services';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--financial-services';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'financial-services';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--financial-services' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--financial-services';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--financial-services' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--financial-services';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions compliance and risk ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--financial-services' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--financial-services';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'financial-services';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Does the audit trail survive the migration?", "verdict": "Yes", "answer": "Every object carries its full disposition history, port, rework or retire, so the retention chain regulators expect is intact through cutover."}, {"question": "Does this reduce exam risk?", "verdict": "Qualified yes", "answer": "The health score comes from an automated audit of the real book of record, not self-reported counts, which is usually where exam-time scoping risk starts. Compliance should still review and sign off."}]';
    contentToUpsert.add(row);
}

// ---- Health (health) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--health';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--health';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'health';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--health' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--health';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every migration in health starts the same way: PHI nobody\'s confident is still where it should be.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--health' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--health';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["A BAA nobody\'s validated for the new platform", "Patient-journey data nobody can fully trace", "A go-live date that can\'t create a consent gap"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--health' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--health';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator treats every PHI object as a minimum-necessary boundary, not a bulk export, so patient trust never blinks.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--health';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--health';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'health';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--health' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--health';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--health' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--health';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for PHI-safe migration.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--health' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--health';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every PHI and consent workflow in the patient journey, generated on demand, before a BAA is even signed.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every PHI object under a validated BAA, with full history, minimum-necessary by default.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Migrating a patient-journey object pulls in every consent and PHI dependency it needs, automatically, so nothing ships incomplete.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready if a consent record doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--health' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--health';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline reviewed for PHI exposure. An approved layout becomes a publishable, compliant email, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--health';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--health';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'health';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--health' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--health';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--health' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--health';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: PHI-bearing patient journeys.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--health' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--health';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--health' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--health';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where PHI-bearing patient-journey data sees the largest advantage, health organizations carrying a sizable, consent-sensitive environment.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--health' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--health';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions with your privacy and compliance leads in the room, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--health';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--health';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'health';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--health' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--health';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--health' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--health';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions privacy and compliance ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--health' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--health';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'health';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Is our BAA validated before anything touches PHI?", "verdict": "Yes", "answer": "The BAA is validated against the destination platform before the dry run touches a single PHI object, not after."}, {"question": "Does migration risk a consent gap?", "verdict": "No", "answer": "Consent and PHI dependencies are inventoried together, so a patient-journey object never ships without the consent record it depends on."}]';
    contentToUpsert.add(row);
}

// ---- Public Sector (public-sector) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--public-sector';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--public-sector';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'public-sector';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--public-sector' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--public-sector';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every constituent-facing migration starts the same way: an accessible notice nobody\'s sure will still be accessible.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--public-sector' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--public-sector';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["A multilingual alert nobody can afford to drop", "A records-retention rule nobody\'s mapped to the new platform", "A go-live date constituents shouldn\'t notice"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--public-sector' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--public-sector';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator keeps accessible, multilingual constituent communications live through cutover, so the public never sees the seam.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--public-sector';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--public-sector';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'public-sector';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--public-sector' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--public-sector';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--public-sector' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--public-sector';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for constituent trust.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--public-sector' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--public-sector';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every constituent-engagement and accessibility workflow, generated on demand, before a date is set.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every records-retention object under Section 508/ADA, with full history preserved.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Migrating a constituent notice pulls in every language variant and accessibility dependency it needs, automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready if an accessible or multilingual notice doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--public-sector' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--public-sector';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline checked for accessibility compliance. An approved layout becomes a publishable, compliant notice, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--public-sector';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--public-sector';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'public-sector';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--public-sector' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--public-sector';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--public-sector' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--public-sector';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: constituent engagement at scale.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--public-sector' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--public-sector';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--public-sector' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--public-sector';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where accessible, multilingual constituent-engagement programs see the largest advantage, agencies carrying a sizable, records-retention-bound environment.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--public-sector' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--public-sector';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions with your records-management and accessibility leads in the room, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--public-sector';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--public-sector';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'public-sector';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--public-sector' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--public-sector';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--public-sector' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--public-sector';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions records and accessibility teams ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--public-sector' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--public-sector';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'public-sector';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Does migration create a gap in constituent communications?", "verdict": "No", "answer": "Every constituent notice workflow, and its language variants, is dry-run before go-live, so there is no disruption to accessible or multilingual delivery."}, {"question": "Does it preserve our records-retention obligations?", "verdict": "Yes", "answer": "Disposition and history are kept on every object ported, reworked or retired, so records-retention schedules carry through cutover unchanged."}]';
    contentToUpsert.add(row);
}

// ---- Retail (retail) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--retail';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--retail';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'retail';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--retail' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--retail';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every retail migration starts the same way: a personalization engine nobody wants to slow down mid-peak.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--retail' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--retail';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["An omnichannel journey nobody can afford to pause", "A peak-season date that absolutely cannot move", "Real-time activation nobody\'s confident will survive cutover"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--retail' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--retail';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator is built to cut over without a personalization-latency regression, even into peak season.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--retail';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--retail';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'retail';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--retail' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--retail';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--retail' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--retail';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for peak readiness.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--retail' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--retail';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every omnichannel and real-time activation workflow, generated on demand, whenever you need it.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every personalization object, with full history, so nothing silently drops.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Assigning one omnichannel journey pulls in every segment and real-time trigger it depends on, automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready right up against peak readiness.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--retail' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--retail';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline built for retail speed. An approved Figma layout becomes a publishable campaign, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--retail';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--retail';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'retail';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--retail' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--retail';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--retail' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--retail';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: omnichannel personalization.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--retail' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--retail';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--retail' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--retail';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where omnichannel personalization programs see the largest advantage, retailers carrying a sizable, always-on activation environment.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--retail' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--retail';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions timed around your peak calendar, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--retail';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--retail';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'retail';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--retail' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--retail';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--retail' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--retail';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions retail marketing teams ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--retail' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--retail';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'retail';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Will personalization latency regress during cutover?", "verdict": "No", "answer": "Real-time activation triggers are dependency-mapped and dry-run before go-live, so response times don\'t regress even during peak traffic."}, {"question": "Can we migrate without touching our peak-season calendar?", "verdict": "Yes", "answer": "Execution is timed to your peak readiness window, with rollback ready, so cutover never collides with your highest-traffic dates."}]';
    contentToUpsert.add(row);
}

// ---- Telecom, Media & Tech (telecommunications-media-technology) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--telecommunications-media-technology';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--telecommunications-media-technology';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'telecommunications-media-technology';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--telecommunications-media-technology' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--telecommunications-media-technology';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every migration here starts the same way: a churn model nobody\'s willing to run blind for even a week.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--telecommunications-media-technology' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--telecommunications-media-technology';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["A subscriber-lifecycle trigger nobody can afford to miss", "ARPU reporting nobody can reconcile mid-migration", "A go-live date the retention team won\'t move for"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--telecommunications-media-technology' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--telecommunications-media-technology';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator migrates churn-prediction and retention automation without opening a data gap.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--telecommunications-media-technology';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--telecommunications-media-technology';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'telecommunications-media-technology';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--telecommunications-media-technology' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--telecommunications-media-technology';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--telecommunications-media-technology' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--telecommunications-media-technology';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for churn and retention.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--telecommunications-media-technology' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--telecommunications-media-technology';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every churn-prediction and subscriber-lifecycle workflow, generated on demand.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every ARPU and retention object, with full history, so reporting doesn\'t drift.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Migrating a churn-prediction trigger pulls in every subscriber-lifecycle stage it depends on, automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready if a retention trigger doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--telecommunications-media-technology' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--telecommunications-media-technology';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline for lifecycle and retention sends. An approved layout becomes a publishable email, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--telecommunications-media-technology';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--telecommunications-media-technology';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'telecommunications-media-technology';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--telecommunications-media-technology' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--telecommunications-media-technology';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--telecommunications-media-technology' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--telecommunications-media-technology';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: churn and subscriber lifecycle.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--telecommunications-media-technology' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--telecommunications-media-technology';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--telecommunications-media-technology' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--telecommunications-media-technology';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where churn-prediction and subscriber-lifecycle automation sees the largest advantage, telco, media and tech companies carrying a sizable, data-dense retention stack.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--telecommunications-media-technology' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--telecommunications-media-technology';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions with your data and retention teams in the room, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--telecommunications-media-technology';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--telecommunications-media-technology';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'telecommunications-media-technology';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--telecommunications-media-technology' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--telecommunications-media-technology';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--telecommunications-media-technology' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--telecommunications-media-technology';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions data and retention teams ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--telecommunications-media-technology' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--telecommunications-media-technology';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'telecommunications-media-technology';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Does churn-prediction automation stay live during migration?", "verdict": "Yes", "answer": "Churn and retention triggers are dependency-mapped and dry-run before cutover, so scoring doesn\'t run blind for even a day."}, {"question": "Does ARPU reporting stay reconciled through the migration?", "verdict": "Yes", "answer": "ARPU-linked objects carry full disposition history, port, rework or retire, so reporting doesn\'t drift mid-migration."}]';
    contentToUpsert.add(row);
}

// ---- Transportation & Mobility (transportation-mobility) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--transportation-mobility';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--transportation-mobility';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'transportation-mobility';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--transportation-mobility' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--transportation-mobility';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every migration here starts the same way: a year-long ABM nurture nobody wants to reset.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--transportation-mobility' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--transportation-mobility';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["An RFP-cycle nurture nobody can afford to interrupt", "Shipper and carrier attribution nobody can fully trace", "A go-live date that can\'t land mid-procurement-cycle"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--transportation-mobility' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--transportation-mobility';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator preserves long-cycle ABM nurture and attribution through cutover, so a year of pipeline doesn\'t reset to zero.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--transportation-mobility';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--transportation-mobility';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'transportation-mobility';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--transportation-mobility' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--transportation-mobility';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--transportation-mobility' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--transportation-mobility';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for long-cycle ABM.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--transportation-mobility' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--transportation-mobility';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every ABM nurture and attribution workflow, generated on demand, before a date is committed.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every shipper/carrier and procurement-cycle object, with full attribution history preserved.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Migrating an ABM nurture track pulls in every shipper/carrier account and touchpoint it depends on, automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready if an attribution record doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--transportation-mobility' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--transportation-mobility';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline built for long-cycle ABM sends. An approved layout becomes a publishable email, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--transportation-mobility';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--transportation-mobility';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'transportation-mobility';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--transportation-mobility' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--transportation-mobility';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--transportation-mobility' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--transportation-mobility';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: long-cycle ABM pipeline.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--transportation-mobility' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--transportation-mobility';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--transportation-mobility' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--transportation-mobility';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where long-cycle ABM nurture and attribution sees the largest advantage, transportation and mobility organizations carrying a sizable, procurement-cycle-bound pipeline.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--transportation-mobility' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--transportation-mobility';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions with your ABM and demand-gen teams in the room, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--transportation-mobility';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--transportation-mobility';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'transportation-mobility';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--transportation-mobility' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--transportation-mobility';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--transportation-mobility' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--transportation-mobility';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions ABM and demand-gen teams ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--transportation-mobility' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--transportation-mobility';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'transportation-mobility';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Does a year of ABM nurture survive the migration?", "verdict": "Yes", "answer": "Nurture tracks and their attribution history are inventoried and dry-run before cutover, so a long RFP cycle doesn\'t reset mid-nurture."}, {"question": "Can shippers and carriers stay correctly attributed?", "verdict": "Yes", "answer": "Account and touchpoint dependencies are mapped together, so attribution doesn\'t fragment across the cutover."}]';
    contentToUpsert.add(row);
}

// ---- Travel & Hospitality (travel-hospitality) ----
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'problem--travel-hospitality';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'problem--travel-hospitality';
    sec.Base_Section_Key__c = 'problem';
    sec.Industry_Key__c = 'travel-hospitality';
    sec.Layout_Type__c = 'lede-chips';
    sec.Label__c = 'The Problem';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--travel-hospitality' + '::' + 'lede';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--travel-hospitality';
    row.Field_Key__c = 'lede';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Opening line';
    row.Sort_Order__c = 40;
    row.Active__c = true;
    row.Rich_Value__c = 'Every migration here starts the same way: a loyalty balance nobody wants to risk near peak season.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--travel-hospitality' + '::' + 'chips';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--travel-hospitality';
    row.Field_Key__c = 'chips';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Pain points';
    row.Sort_Order__c = 50;
    row.Active__c = true;
    row.JSON_Value__c = '["A guest-journey trigger nobody can afford to miss", "Loyalty-tier points nobody can fully reconcile", "A go-live date that can\'t land near peak booking season"]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'problem--travel-hospitality' + '::' + 'close';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'problem--travel-hospitality';
    row.Field_Key__c = 'close';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Closing line';
    row.Sort_Order__c = 60;
    row.Active__c = true;
    row.Rich_Value__c = 'Migration Accelerator migrates loyalty-tier and points data without integrity loss, timed away from your peak season.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'capabilities--travel-hospitality';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'capabilities--travel-hospitality';
    sec.Base_Section_Key__c = 'capabilities';
    sec.Industry_Key__c = 'travel-hospitality';
    sec.Layout_Type__c = 'card-grid';
    sec.Label__c = 'Capabilities';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--travel-hospitality' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--travel-hospitality';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 270;
    row.Active__c = true;
    row.Text_Value__c = 'The capabilities';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--travel-hospitality' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--travel-hospitality';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 280;
    row.Active__c = true;
    row.Text_Value__c = 'What\'s actually built for the guest journey.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--travel-hospitality' + '::' + 'cards';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--travel-hospitality';
    row.Field_Key__c = 'cards';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Capability cards';
    row.Sort_Order__c = 130;
    row.Active__c = true;
    row.JSON_Value__c = '[{"icon": "Au", "cardTitle": "Automated audit", "cardDesc": "A health score across every guest-journey and loyalty-tier workflow, generated on demand, before a date is set.", "isNew": true}, {"icon": "De", "cardTitle": "Disposition & audit trail", "cardDesc": "Port, rework or retire every PMS-linked and loyalty object, with full points-history preserved.", "isNew": false}, {"icon": "Pl", "cardTitle": "Dependency-aware planning", "cardDesc": "Migrating a guest-journey trigger pulls in every loyalty-tier and direct-booking dependency it needs, automatically.", "isNew": false}, {"icon": "Ex", "cardTitle": "Live execution & rollback", "cardDesc": "Dry run, then live, with a verification pass and rollback ready if a loyalty-points record doesn\'t land clean.", "isNew": true}]';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'capabilities--travel-hospitality' + '::' + 'bonusCard';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'capabilities--travel-hospitality';
    row.Field_Key__c = 'bonusCard';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Bonus card';
    row.Sort_Order__c = 140;
    row.Active__c = true;
    row.Rich_Value__c = '<strong>Also in the toolkit:</strong> a design-to-email pipeline for guest-journey and direct-booking sends. An approved layout becomes a publishable email, no separate rebuild.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--travel-hospitality';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'clientProfile--travel-hospitality';
    sec.Base_Section_Key__c = 'clientProfile';
    sec.Industry_Key__c = 'travel-hospitality';
    sec.Layout_Type__c = 'stat';
    sec.Label__c = 'Client Profile';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--travel-hospitality' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--travel-hospitality';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 290;
    row.Active__c = true;
    row.Text_Value__c = 'The client profile';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--travel-hospitality' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--travel-hospitality';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 300;
    row.Active__c = true;
    row.Text_Value__c = 'Who this fits: guest journey and loyalty.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--travel-hospitality' + '::' + 'statBig';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--travel-hospitality';
    row.Field_Key__c = 'statBig';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Big stat';
    row.Sort_Order__c = 150;
    row.Active__c = true;
    row.Text_Value__c = '500–2,000+';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--travel-hospitality' + '::' + 'statDesc';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--travel-hospitality';
    row.Field_Key__c = 'statDesc';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Stat description';
    row.Sort_Order__c = 160;
    row.Active__c = true;
    row.Rich_Value__c = 'objects is where guest-journey and loyalty-tier programs see the largest advantage, travel and hospitality brands carrying a sizable, PMS-linked environment.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'clientProfile--travel-hospitality' + '::' + 'note';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'clientProfile--travel-hospitality';
    row.Field_Key__c = 'note';
    row.Field_Type__c = 'rich';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Client note';
    row.Sort_Order__c = 170;
    row.Active__c = true;
    row.Rich_Value__c = 'Today, this runs through us, in working sessions timed around your peak season, not a self-serve portal, and that\'s exactly how it should work for now.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + 'faq--travel-hospitality';
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = 'faq--travel-hospitality';
    sec.Base_Section_Key__c = 'faq';
    sec.Industry_Key__c = 'travel-hospitality';
    sec.Layout_Type__c = 'faq';
    sec.Label__c = 'FAQ';
    sec.Width__c = 'standard';
    sec.Active__c = true;
    sec.Status__c = 'Published';
    sec.Sort_Order__c = 10;
    sectionsToUpsert.add(sec);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--travel-hospitality' + '::' + 'eyebrow';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--travel-hospitality';
    row.Field_Key__c = 'eyebrow';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Eyebrow';
    row.Sort_Order__c = 320;
    row.Active__c = true;
    row.Text_Value__c = 'FAQ';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--travel-hospitality' + '::' + 'head';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--travel-hospitality';
    row.Field_Key__c = 'head';
    row.Field_Type__c = 'text';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Section heading';
    row.Sort_Order__c = 330;
    row.Active__c = true;
    row.Text_Value__c = 'The questions guest-experience teams ask.';
    contentToUpsert.add(row);
}
{
    GTM_Page_Content__c row = new GTM_Page_Content__c();
    row.Content_Address__c = OFK + '::' + TPL + '::' + 'faq--travel-hospitality' + '::' + 'items';
    row.Offering_Key__c = OFK;
    row.Template_Type__c = TPL;
    row.Section_Key__c = 'faq--travel-hospitality';
    row.Field_Key__c = 'items';
    row.Field_Type__c = 'json';
    row.Industry_Key__c = 'travel-hospitality';
    row.Label__c = 'Questions';
    row.Sort_Order__c = 230;
    row.Active__c = true;
    row.JSON_Value__c = '[{"question": "Will loyalty-tier points survive the migration intact?", "verdict": "Yes", "answer": "Points balances and tier history are inventoried and dry-run before go-live, so loyalty integrity doesn\'t slip during cutover."}, {"question": "Can we avoid migrating during peak booking season?", "verdict": "Yes", "answer": "Execution is scheduled around your peak calendar, with rollback ready, so cutover never collides with your highest-demand dates."}]';
    contentToUpsert.add(row);
}

upsert sectionsToUpsert Section_Address__c;
System.debug('=== Variant sections upserted: ' + sectionsToUpsert.size() + ' ===');
upsert contentToUpsert Content_Address__c;
System.debug('=== Variant content rows upserted: ' + contentToUpsert.size() + ' ===');
