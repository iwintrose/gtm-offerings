// Issue #104 -- replaces the six placeholder industries in the framework's
// Industry Chooser with the nine real Publicis Sapient industries, seeded
// verbatim from https://www.publicissapient.com/industries/{slug} (see the
// issue body for the source table and stakeholder rulings).
//
// Per determination (1) in TASK_SCOPE.md: idempotent by construction, using
// upsert on Content_Address__c / Section_Address__c (both externalId/unique)
// rather than a bare insert -- re-running this script leaves row counts for
// gtm/industry-chooser unchanged.
//
// Per determination (2): only industryLabel (sort 10) and pickerBlurb (sort
// 40) are seeded with real copy -- the two fields the picker card actually
// reads. The other ten industry-tile field rows (whyHead, demoRoot, coverSub,
// problem, useCase, solution, proofLine, whyLine, uniquePoints, demoDeps) are
// created empty at their established sort orders so the full field set is
// editable in the Content Manager. `headline` has no rendering home on this
// card (see TASK_SCOPE.md finding 6) and is deliberately NOT written to
// coverSub or anywhere else -- the nine headlines are recorded in this
// commit's message body instead so they are not lost.
//
// Per determination (4): the six retired industries are deactivated
// (Active__c = false), never deleted, on both GTM_Page_Content__c and
// GTM_Page_Section__c.
//
// Run via: sf apex run --file scripts/data/seed-industry-chooser-industries.apex --target-org gtm-prod
//
// Verify via:
//   SELECT Section_Key__c, Active__c FROM GTM_Page_Section__c
//    WHERE Offering_Key__c = 'gtm' AND Template_Type__c = 'industry-chooser'
//    ORDER BY Section_Key__c
//   SELECT COUNT() FROM GTM_Page_Content__c
//    WHERE Offering_Key__c = 'gtm' AND Template_Type__c = 'industry-chooser'
// -- run the script a second time and confirm both counts are unchanged.

String OFK = 'gtm';
String TPL = 'industry-chooser';
String LAYOUT = 'industry-tile';

// Field key -> { sortOrder, fieldType }. Field_Type__c values follow the
// existing six rows' convention: 'text' for plain strings, 'rich' for the
// blurb/paragraph fields, 'json' for list-valued fields.
Map<String, Object[]> FIELD_DEFS = new Map<String, Object[]>{
    'industryLabel' => new Object[]{ 10,  'text' },
    'whyHead'       => new Object[]{ 20,  'text' },
    'demoRoot'      => new Object[]{ 30,  'text' },
    'pickerBlurb'   => new Object[]{ 40,  'rich' },
    'coverSub'      => new Object[]{ 50,  'rich' },
    'problem'       => new Object[]{ 60,  'rich' },
    'useCase'       => new Object[]{ 70,  'rich' },
    'solution'      => new Object[]{ 80,  'rich' },
    'proofLine'     => new Object[]{ 90,  'rich' },
    'whyLine'       => new Object[]{ 100, 'rich' },
    'uniquePoints'  => new Object[]{ 110, 'json' },
    'demoDeps'      => new Object[]{ 120, 'json' }
};

// slug -> { displayName, blurb }. headline is intentionally not part of
// this map (see determination (2) above) -- recorded in the commit body.
Map<String, String[]> INDUSTRIES = new Map<String, String[]>{
    'consumer-products' => new String[]{
        'Consumer Products',
        'Consumer products companies are under pressure to launch more products, in more markets, with greater speed and consistency while managing fragmented systems, complex supply chains and rising expectations for personalization and compliance.'
    },
    'energy-commodities' => new String[]{
        'Energy & Commodities',
        'Energy and commodities companies are navigating volatile markets, decarbonization goals and complex supply chains while relying on legacy systems that limit visibility, speed and operational resilience.'
    },
    'financial-services' => new String[]{
        'Financial Services',
        'Financial services organizations operate under constant pressure to modernize legacy systems, meet regulatory requirements and deliver better customer experiences while managing risk at scale.'
    },
    'health' => new String[]{
        'Health',
        'Health care organizations are under pressure to improve patient outcomes, reduce costs and provide connected digital experiences while navigating legacy systems, data silos and strict regulatory requirements.'
    },
    'public-sector' => new String[]{
        'Public Sector',
        'Public sector agencies are under pressure to deliver modern, equitable digital services that meet rising citizen expectations while overcoming legacy systems, budget constraints and complex regulatory environments.'
    },
    'retail' => new String[]{
        'Retail',
        'Retailers are expected to deliver consistent, personalized experiences while managing complex legacy systems, seasonal demand shifts and growing pressure on reliability across every channel.'
    },
    'telecommunications-media-technology' => new String[]{
        // Nav wording, not the page H1's "Telco, Media & Technology" -- see
        // the issue's slug-correction note.
        'Telecom, Media & Tech',
        'Telco, media and technology organizations face constant pressure to move faster, scale reliably and stay relevant while managing legacy platforms, fragmented data and rising infrastructure costs.'
    },
    'transportation-mobility' => new String[]{
        'Transportation & Mobility',
        'Transportation and mobility organizations face rising cost pressure, shifting customer expectations and increasing ecosystem complexity while relying on legacy systems that limit visibility, speed and innovation.'
    },
    'travel-hospitality' => new String[]{
        'Travel & Hospitality',
        'Travel and hospitality brands face rising traveler expectations for connected experiences while managing legacy platforms, operational complexity and constant pressure to modernize across digital and physical touchpoints.'
    }
};

// The six retired industries (issue body + ruling 1: lifesci and medtech
// collapse into the new 'health' key and are retired, not migrated).
List<String> RETIRED_KEYS = new List<String>{
    'fintech', 'government', 'lifesci', 'media', 'medtech', 'transport'
};

// ---- 1. Upsert the nine GTM_Page_Section__c rows (industry-tile layout) ----

List<GTM_Page_Section__c> sectionsToUpsert = new List<GTM_Page_Section__c>();
Integer sortOrder = 10;
for (String slug : INDUSTRIES.keySet()) {
    String sectionKey = 'industry-' + slug;
    GTM_Page_Section__c sec = new GTM_Page_Section__c();
    sec.Section_Address__c = OFK + '::' + TPL + '::' + sectionKey;
    sec.Offering_Key__c = OFK;
    sec.Template_Type__c = TPL;
    sec.Section_Key__c = sectionKey;
    sec.Layout_Type__c = LAYOUT;
    sec.Label__c = INDUSTRIES.get(slug)[0];
    sec.Sort_Order__c = sortOrder;
    sec.Active__c = true;
    sectionsToUpsert.add(sec);
    sortOrder += 10;
}
upsert sectionsToUpsert Section_Address__c;
System.debug('=== Sections upserted: ' + sectionsToUpsert.size() + ' ===');

// ---- 2. Upsert the twelve GTM_Page_Content__c field rows per industry ----

List<GTM_Page_Content__c> contentToUpsert = new List<GTM_Page_Content__c>();
for (String slug : INDUSTRIES.keySet()) {
    String sectionKey = 'industry-' + slug;
    String displayName = INDUSTRIES.get(slug)[0];
    String blurb = INDUSTRIES.get(slug)[1];

    for (String fieldKey : FIELD_DEFS.keySet()) {
        Object[] def = FIELD_DEFS.get(fieldKey);
        Integer fieldSort = (Integer) def[0];
        String fieldType = (String) def[1];

        GTM_Page_Content__c rec = new GTM_Page_Content__c();
        rec.Content_Address__c = OFK + '::' + TPL + '::' + sectionKey + '::' + fieldKey;
        rec.Offering_Key__c = OFK;
        rec.Template_Type__c = TPL;
        rec.Section_Key__c = sectionKey;
        rec.Field_Key__c = fieldKey;
        rec.Field_Type__c = fieldType;
        rec.Sort_Order__c = fieldSort;
        rec.Active__c = true;

        String value = null;
        if (fieldKey == 'industryLabel') value = displayName;
        if (fieldKey == 'pickerBlurb') value = blurb;

        if (fieldType == 'rich') {
            rec.Rich_Value__c = value;
        } else if (fieldType == 'json') {
            rec.JSON_Value__c = value;
        } else {
            rec.Text_Value__c = value;
        }

        contentToUpsert.add(rec);
    }
}
upsert contentToUpsert Content_Address__c;
System.debug('=== Content rows upserted: ' + contentToUpsert.size() + ' ===');

// ---- 3. Deactivate the six retired industries (both objects) ----

List<String> retiredSectionKeys = new List<String>();
for (String k : RETIRED_KEYS) retiredSectionKeys.add('industry-' + k);

List<GTM_Page_Section__c> retiredSections = [
    SELECT Id, Active__c
    FROM   GTM_Page_Section__c
    WHERE  Offering_Key__c = :OFK
    AND    Template_Type__c = :TPL
    AND    Section_Key__c IN :retiredSectionKeys
];
for (GTM_Page_Section__c sec : retiredSections) sec.Active__c = false;
if (!retiredSections.isEmpty()) update retiredSections;
System.debug('=== Retired sections deactivated: ' + retiredSections.size() + ' ===');

List<GTM_Page_Content__c> retiredContent = [
    SELECT Id, Active__c
    FROM   GTM_Page_Content__c
    WHERE  Offering_Key__c = :OFK
    AND    Template_Type__c = :TPL
    AND    Section_Key__c IN :retiredSectionKeys
];
for (GTM_Page_Content__c rec : retiredContent) rec.Active__c = false;
if (!retiredContent.isEmpty()) update retiredContent;
System.debug('=== Retired content rows deactivated: ' + retiredContent.size() + ' ===');

// ---- Verification counts ----

Integer newSectionCount = Database.countQuery(
    'SELECT COUNT() FROM GTM_Page_Section__c WHERE Offering_Key__c = \'' + OFK
    + '\' AND Template_Type__c = \'' + TPL + '\''
);
Integer newContentCount = Database.countQuery(
    'SELECT COUNT() FROM GTM_Page_Content__c WHERE Offering_Key__c = \'' + OFK
    + '\' AND Template_Type__c = \'' + TPL + '\''
);
System.debug('=== VERIFY: Section rows=' + newSectionCount + ' Content rows=' + newContentCount + ' ===');
