/**
 * Coverage for the read-only, unread paths of GtmReadoutAgentFiles: the
 * extension classification extractAll() already relies on, and the new
 * cacheable getFileList() the LWC uses to persist the attachment list
 * across a panel toggle/reload.
 *
 * getFileList() deliberately does not read VersionData (no text budget to
 * spend), so these tests assert on title/extension/size/readable rather than
 * on any extracted text.
 */
@isTest
private class GtmReadoutAgentFilesTest {

    private static GTM_Assessment_Request__c seedRequest() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c  = 'Alex Rivera',
            Requester_Email__c = 'alex.rivera@example.com',
            Company__c         = 'Northwind Retail'
        );
        insert req;
        return req;
    }

    private static GTM_Readout__c seedReadout(Id requestId) {
        GTM_Readout__c r = new GTM_Readout__c(
            Assessment_Request__c = requestId,
            Offering_Key__c       = 'migration-accelerator',
            Status__c             = 'Draft',
            Draft_Content__c      = '<h3>What we found</h3><p>x</p>'
        );
        insert r;
        return r;
    }

    private static User createRep(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com',
            EmailEncodingKey = 'UTF-8', LastName = 'Rep ' + alias,
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/New_York',
            Username = alias + System.currentTimeMillis() + '@gtm-offerings.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) { insert u; }
        return u;
    }

    /** Attaches a ContentVersion to the readout the same way lightning-file-upload does. */
    private static void attach(Id readoutId, String title, String ext, String body) {
        ContentVersion cv = new ContentVersion(
            Title               = title,
            PathOnClient        = title + '.' + ext,
            VersionData         = Blob.valueOf(body),
            FirstPublishLocationId = readoutId
        );
        insert cv;
    }

    // ------------------------------------------------------------- getFileList

    @isTest
    static void getFileListReturnsOneEntryPerAttachedFile() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        attach(r.Id, 'discovery-notes', 'txt', 'Procurement is the blocker.');
        attach(r.Id, 'rfp', 'pdf', 'not really a pdf, just bytes');

        Test.startTest();
        List<Map<String, Object>> files = GtmReadoutAgentFiles.getFileList(r.Id);
        Test.stopTest();

        System.assertEquals(2, files.size());
    }

    @isTest
    static void getFileListMarksTextExtensionsReadableAndBinaryOnesNot() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        attach(r.Id, 'discovery-notes', 'txt', 'Procurement is the blocker.');
        attach(r.Id, 'rfp', 'pdf', 'not really a pdf, just bytes');

        Map<String, Object> textRow;
        Map<String, Object> pdfRow;
        for (Map<String, Object> row : GtmReadoutAgentFiles.getFileList(r.Id)) {
            if ('txt'.equals(row.get('extension'))) textRow = row;
            if ('pdf'.equals(row.get('extension'))) pdfRow = row;
        }

        System.assertNotEquals(null, textRow);
        System.assertNotEquals(null, pdfRow);
        System.assertEquals(true, textRow.get('readable'));
        System.assertEquals(false, pdfRow.get('readable'));
    }

    @isTest
    static void getFileListCarriesNameSizeAndExtension() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        attach(r.Id, 'discovery-notes', 'txt', 'Procurement is the blocker.');

        Map<String, Object> row = GtmReadoutAgentFiles.getFileList(r.Id)[0];

        System.assertEquals('discovery-notes', row.get('title'));
        System.assertEquals('txt', row.get('extension'));
        System.assertNotEquals(null, row.get('sizeBytes'));
        System.assertNotEquals(null, row.get('createdDate'));
    }

    @isTest
    static void getFileListIsEmptyWhenNoFilesAreAttached() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        System.assertEquals(0, GtmReadoutAgentFiles.getFileList(r.Id).size());
    }

    @isTest
    static void getFileListRejectsANullReadoutId() {
        Boolean threw = false;
        try {
            GtmReadoutAgentFiles.getFileList(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void getFileListRefusesARepWithoutAccess() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        attach(r.Id, 'discovery-notes', 'txt', 'Procurement is the blocker.');
        User stranger = createRep('gtmff1');

        Boolean threw = false;
        System.runAs(stranger) {
            try {
                GtmReadoutAgentFiles.getFileList(r.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw,
            'a rep who cannot read the readout must not be able to list its files');
    }

    // ----------------------------------------------------------- extractAll

    @isTest
    static void extractAllReadsPlainTextFiles() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        attach(r.Id, 'discovery-notes', 'txt', 'Procurement is the blocker.');

        List<Object> rows = GtmReadoutAgentFiles.extractAll(r.Id);
        System.assertEquals(1, rows.size());
        Map<String, Object> row = (Map<String, Object>) rows[0];
        System.assertEquals(true, row.get('readable'));
        System.assertEquals('Procurement is the blocker.', row.get('text'));
    }

    @isTest
    static void extractAllReportsPdfAsPresentButUnreadable() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        attach(r.Id, 'rfp', 'pdf', 'not really a pdf, just bytes');

        List<Object> rows = GtmReadoutAgentFiles.extractAll(r.Id);
        System.assertEquals(1, rows.size());
        Map<String, Object> row = (Map<String, Object>) rows[0];
        System.assertEquals(false, row.get('readable'));
        System.assert(String.valueOf(row.get('reason')).contains('external extraction service'),
            'the refusal text must still name the missing extraction service -- extraction itself is unchanged');
    }

    @isTest
    static void extractAllReturnsEmptyForANullReadoutId() {
        System.assertEquals(0, GtmReadoutAgentFiles.extractAll(null).size());
    }
}
