@isTest
private class GtmInstrumentControllerTest {

    private static GTM_Instrument__c newInstrument(String offeringKey, String status, Integer version) {
        GTM_Instrument__c instrument = new GTM_Instrument__c(
            Offering_Key__c = offeringKey,
            Name            = 'Test Instrument ' + offeringKey,
            Status__c       = status,
            Version__c      = version
        );
        insert instrument;
        return instrument;
    }

    @isTest
    static void getInstrumentForOfferingReturnsNullWhenNoneExists() {
        Test.startTest();
        GtmInstrumentController.InstrumentDto dto =
            GtmInstrumentController.getInstrumentForOffering('no-such-offering');
        Test.stopTest();

        Assert.isNull(dto, 'No GTM_Instrument__c row for this offering should return null');
    }

    @isTest
    static void createInstrumentInsertsDraftVersionOne() {
        Test.startTest();
        GtmInstrumentController.InstrumentDto dto =
            GtmInstrumentController.createInstrument('new-offering', 'New Offering Assessment');
        Test.stopTest();

        Assert.isNotNull(dto.id);
        Assert.areEqual('Draft', dto.status);
        Assert.areEqual(1, dto.version);

        GTM_Instrument__c stored = [SELECT Status__c, Version__c FROM GTM_Instrument__c WHERE Id = :dto.id];
        Assert.areEqual('Draft', stored.Status__c);
        Assert.areEqual(1, stored.Version__c);
    }

    @isTest
    static void getInstrumentForOfferingReturnsOrderedQuestions() {
        GTM_Instrument__c instrument = newInstrument('with-questions', 'Draft', 1);
        insert new List<GTM_Instrument_Question__c>{
            new GTM_Instrument_Question__c(
                GTM_Instrument__c = instrument.Id, Slot_Order__c = 2,
                Question_Text__c = 'Second?', Question_Key__c = 'q2'
            ),
            new GTM_Instrument_Question__c(
                GTM_Instrument__c = instrument.Id, Slot_Order__c = 1,
                Question_Text__c = 'First?', Question_Key__c = 'q1'
            )
        };

        Test.startTest();
        GtmInstrumentController.InstrumentDto dto =
            GtmInstrumentController.getInstrumentForOffering('with-questions');
        Test.stopTest();

        Assert.isNotNull(dto);
        Assert.areEqual(2, dto.questions.size());
        Assert.areEqual('q1', dto.questions[0].questionKey);
        Assert.areEqual('q2', dto.questions[1].questionKey);
    }

    @isTest
    static void saveInstrumentUpdatesNameAndStatus() {
        GTM_Instrument__c instrument = newInstrument('save-offering', 'Draft', 1);

        Test.startTest();
        GtmInstrumentController.saveInstrument(instrument.Id, 'Renamed', 'Draft');
        Test.stopTest();

        GTM_Instrument__c stored = [SELECT Name, Status__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Renamed', stored.Name);
        Assert.areEqual('Draft', stored.Status__c);
    }

    @isTest
    static void saveQuestionsBatchUpsertsNewAndExisting() {
        GTM_Instrument__c instrument = newInstrument('save-questions-offering', 'Draft', 1);
        GTM_Instrument_Question__c existing = new GTM_Instrument_Question__c(
            GTM_Instrument__c = instrument.Id, Slot_Order__c = 1,
            Question_Text__c = 'Old text', Question_Key__c = 'q1'
        );
        insert existing;

        GtmInstrumentController.QuestionDto updateDto = new GtmInstrumentController.QuestionDto();
        updateDto.id = existing.Id;
        updateDto.slotOrder = 1;
        updateDto.questionText = 'Updated text';
        updateDto.questionKey = 'q1';
        updateDto.required = true;

        GtmInstrumentController.QuestionDto newDto = new GtmInstrumentController.QuestionDto();
        newDto.slotOrder = 2;
        newDto.questionText = 'Brand new question';
        newDto.questionKey = 'q2';
        newDto.optionsJson = '[{"label":"Yes","value":"yes","points":10}]';

        Test.startTest();
        GtmInstrumentController.saveQuestions(
            instrument.Id, new List<GtmInstrumentController.QuestionDto>{ updateDto, newDto }
        );
        Test.stopTest();

        List<GTM_Instrument_Question__c> stored = [
            SELECT Question_Text__c, Question_Key__c, Required__c
            FROM GTM_Instrument_Question__c
            WHERE GTM_Instrument__c = :instrument.Id
            ORDER BY Slot_Order__c
        ];
        Assert.areEqual(2, stored.size());
        Assert.areEqual('Updated text', stored[0].Question_Text__c);
        Assert.isTrue(stored[0].Required__c);
        Assert.areEqual('Brand new question', stored[1].Question_Text__c);
    }

    @isTest
    static void publishInstrumentActivatesAndIncrementsVersion() {
        GTM_Instrument__c instrument = newInstrument('publish-offering', 'Draft', 1);

        Test.startTest();
        GtmInstrumentController.publishInstrument(instrument.Id);
        Test.stopTest();

        GTM_Instrument__c stored = [SELECT Status__c, Version__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Active', stored.Status__c);
        Assert.areEqual(2, stored.Version__c);
    }

    /**
     * "Only one Active instrument per Offering_Key__c" (architecture doc
     * §4.1) is guaranteed by Offering_Key__c's unique constraint (§2.1), not
     * by publishInstrument's own logic: a second GTM_Instrument__c row for
     * an offering that already has one cannot be inserted at all, so there
     * is never a sibling "other Active instrument" for publishInstrument to
     * demote. This test proves the schema-level guarantee publishInstrument
     * relies on.
     */
    @isTest
    static void offeringKeyUniquenessPreventsASecondInstrumentForTheSameOffering() {
        newInstrument('supersede-offering', 'Active', 1);

        Test.startTest();
        Boolean threw = false;
        try {
            newInstrument('supersede-offering', 'Draft', 1);
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw,
            'Offering_Key__c is unique, so a second instrument row for the same offering must be rejected');
        Assert.areEqual(1, [
            SELECT COUNT() FROM GTM_Instrument__c WHERE Offering_Key__c = 'supersede-offering'
        ], 'Only one Active instrument per Offering_Key__c, enforced by the schema');
    }

    @isTest
    static void publishInstrumentIsIdempotentWhenAlreadyActive() {
        GTM_Instrument__c instrument = newInstrument('republish-offering', 'Active', 1);

        Test.startTest();
        GtmInstrumentController.publishInstrument(instrument.Id);
        Test.stopTest();

        GTM_Instrument__c stored = [SELECT Status__c, Version__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Active', stored.Status__c);
        Assert.areEqual(2, stored.Version__c, 'Re-publishing still bumps the version');
    }

    @isTest
    static void archiveInstrumentSetsArchivedFromDraft() {
        GTM_Instrument__c instrument = newInstrument('archive-offering', 'Draft', 1);

        Test.startTest();
        GtmInstrumentController.archiveInstrument(instrument.Id);
        Test.stopTest();

        GTM_Instrument__c stored = [SELECT Status__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Archived', stored.Status__c);
    }

    @isTest
    static void archiveInstrumentBlockedWhileActive() {
        GTM_Instrument__c instrument = newInstrument('archive-active-offering', 'Active', 1);

        Test.startTest();
        Boolean threw = false;
        try {
            GtmInstrumentController.archiveInstrument(instrument.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Archiving directly from Active must be blocked by GTM_InstrumentTrigger');
        GTM_Instrument__c stored = [SELECT Status__c FROM GTM_Instrument__c WHERE Id = :instrument.Id];
        Assert.areEqual('Active', stored.Status__c);
    }
}
