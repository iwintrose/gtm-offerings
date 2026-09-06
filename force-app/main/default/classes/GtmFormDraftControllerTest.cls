/**
 * The resume path, including the two things that make it safe rather than just
 * working: a draft is reachable only with the key that wrote it, and a
 * submitted form stops offering its own answers back.
 */
@IsTest
private class GtmFormDraftControllerTest {

    private static final String KEY  = 'a1b2c3d4e5f60718293a';
    private static final String KEY2 = 'ffffffffffffffffffff';

    private static MA_Saved_Configuration__c link(Boolean active) {
        MA_Saved_Configuration__c c = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator',
            Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a',
            Active__c = active
        );
        insert c;
        return c;
    }

    @IsTest
    static void aDraftComesBackToTheBrowserThatWroteIt() {
        MA_Saved_Configuration__c c = link(true);

        Test.startTest();
        Assert.isNull(GtmFormDraftController.getDraft(c.Id, KEY), 'Nothing typed yet');
        GtmFormDraftController.saveDraft(c.Id, KEY, '{"name":"Ann"}', 'name', 'sess-1');
        GtmFormDraftController.DraftView back = GtmFormDraftController.getDraft(c.Id, KEY);
        Test.stopTest();

        Assert.isNotNull(back);
        Assert.areEqual('{"name":"Ann"}', back.draftJson);
        Assert.areEqual('name', back.furthestField);
    }

    /**
     * The newest save wins even when both land in the same second.
     *
     * CreatedDate is second-resolution and a test writes both rows inside one
     * transaction, so this is the tie that made a resume serve the draft from
     * before the visitor's last edit.
     */
    @IsTest
    static void theLatestSaveWinsOnATiedTimestamp() {
        MA_Saved_Configuration__c c = link(true);

        Test.startTest();
        GtmFormDraftController.saveDraft(c.Id, KEY, '{"name":"Ann"}', 'name', 'sess-1');
        GtmFormDraftController.saveDraft(c.Id, KEY, '{"name":"Ann","timeline":"Q1"}', 'timeline', 'sess-1');
        GtmFormDraftController.DraftView back = GtmFormDraftController.getDraft(c.Id, KEY);
        Test.stopTest();

        Assert.areEqual('{"name":"Ann","timeline":"Q1"}', back.draftJson);
        Assert.areEqual('timeline', back.furthestField);
    }

    @IsTest
    static void anotherBrowsersKeyGetsNothing() {
        MA_Saved_Configuration__c c = link(true);
        GtmFormDraftController.saveDraft(c.Id, KEY, '{"name":"Ann"}', 'name', 'sess-1');

        Test.startTest();
        Assert.isNull(GtmFormDraftController.getDraft(c.Id, KEY2),
            'A draft is readable only by the browser holding its key');
        Assert.isNull(GtmFormDraftController.getDraft(c.Id, 'short'),
            'A key too short to be random is refused outright');
        Assert.isNull(GtmFormDraftController.getDraft(c.Id, 'has spaces and punctuation!!'),
            'Only the character set the browser generates is accepted');
        Assert.isNull(GtmFormDraftController.getDraft('not-an-id', KEY));
        Test.stopTest();
    }

    @IsTest
    static void submittingStopsTheFormOfferingItsAnswersBack() {
        MA_Saved_Configuration__c c = link(true);
        GtmFormDraftController.saveDraft(c.Id, KEY, '{"name":"Ann"}', 'name', 'sess-1');

        Test.startTest();
        GtmFormDraftController.clearDraft(c.Id, KEY);
        Test.stopTest();

        Assert.isNull(GtmFormDraftController.getDraft(c.Id, KEY),
            'A finished form must not hand the visitor their own draft on the next visit');
    }

    @IsTest
    static void adisabledLinkIsNotAWritableEndpoint() {
        MA_Saved_Configuration__c c = link(false);

        Test.startTest();
        GtmFormDraftController.saveDraft(c.Id, KEY, '{"name":"Ann"}', 'name', 'sess-1');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Form_Draft__c],
            'A link that has been turned off cannot be written to');
    }

    @IsTest
    static void anOversizeDraftIsRefused() {
        MA_Saved_Configuration__c c = link(true);

        Test.startTest();
        GtmFormDraftController.saveDraft(c.Id, KEY, 'x'.repeat(9000), 'name', 'sess-1');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM GTM_Form_Draft__c],
            'The cap is what stops a write surface becoming a bucket');
    }
}
