// Removes the content left behind by the retired story CMS.
//
// The story used to be authored as Salesforce CMS managed content: a story
// page, a story body, story defaults, seven industry stories and six FAQ items.
// That whole path was replaced by MA_Page_Content__c, and nothing has read
// these since -- no Apex, no LWC, no site page. They stayed because deleting a
// managed content type fails while any content still uses it, so the content
// has to go first.
//
// Scoped by content type, not by space: it removes exactly the five retired
// types and never touches Salesforce's own language or asset-provider records
// that live alongside them.
List<String> retired = new List<String>{
    'ma_story_body', 'ma_faq_item', 'ma_industry_story', 'ma_story_setting', 'ma_story_page'
};
// THIS SCRIPT CANNOT RUN. ManagedContent is not deletable by Apex DML, and no
// ConnectApi delete exists in this API version -- both were tried. It is kept
// as the record of exactly what has to go and how to find it.
//
// To actually remove them, in the org:
//   Setup -> Digital Experiences -> All Sites -> the "GTM Offerings" CMS
//   workspace -> Content, filter by the five types below (each now labelled
//   "RETIRED — ..."), select all, Delete. Then deploy the destructive change
//   for the ManagedContentType records, which will succeed once no content
//   uses them.
//
// The 17 records, as of the audit:
//   ma_story_page     Migration Accelerator — Story Page, and ... v2
//   ma_story_body     Migration Accelerator — Story Body
//   ma_story_setting  Migration Accelerator — Story Defaults
//   ma_industry_story 7 industry stories (Financial Services ... Municipal & Civic)
//   ma_faq_item       6 FAQ items
//
// Run this first to confirm the list still matches before deleting anything.
List<ManagedContent> doomed = [
    SELECT Id, Name, ContentTypeFullyQualifiedName
    FROM   ManagedContent
    WHERE  ContentTypeFullyQualifiedName IN :retired
];
System.debug('=== removing ' + doomed.size() + ' retired CMS records ===');
for (ManagedContent c : doomed) {
    System.debug('  ' + c.ContentTypeFullyQualifiedName + '  |  ' + c.Name);
}
// delete doomed;   <- rejected: "DML operation Delete not allowed on List<ManagedContent>"
System.debug('remaining managed content: ' + [SELECT COUNT() FROM ManagedContent]);
