@isTest
private class GtmInstrumentDefinitionControllerTest {

    private static GTM_Instrument_Definition__c newDefinition(String offeringKey, String status, Integer version) {
        GTM_Instrument_Definition__c definition = new GTM_Instrument_Definition__c(
            Offering_Key__c = offeringKey,
            Name            = 'Test Definition ' + offeringKey,
            Status__c       = status,
            Version__c      = version
        );
        insert definition;
        return definition;
    }

    @isTest
    static void getDefinitionForOfferingReturnsNullWhenNoneExists() {
        Test.startTest();
        GtmInstrumentDefinitionController.DefinitionDto dto =
            GtmInstrumentDefinitionController.getDefinitionForOffering('no-such-offering');
        Test.stopTest();

        Assert.isNull(dto, 'No GTM_Instrument_Definition__c row for this offering should return null');
    }

    @isTest
    static void createDefinitionInsertsDraftVersionOne() {
        Test.startTest();
        GtmInstrumentDefinitionController.DefinitionDto dto =
            GtmInstrumentDefinitionController.createDefinition('new-offering', 'New Offering Assessment');
        Test.stopTest();

        Assert.isNotNull(dto.id);
        Assert.areEqual('Draft', dto.status);
        Assert.areEqual(1, dto.version);

        GTM_Instrument_Definition__c stored = [
            SELECT Status__c, Version__c FROM GTM_Instrument_Definition__c WHERE Id = :dto.id
        ];
        Assert.areEqual('Draft', stored.Status__c);
        Assert.areEqual(1, stored.Version__c);
    }

    @isTest
    static void getDefinitionForOfferingReturnsOrderedQuestionsAndRanges() {
        GTM_Instrument_Definition__c definition = newDefinition('with-questions', 'Draft', 1);
        insert new List<GTM_Instrument_Question_Definition__c>{
            new GTM_Instrument_Question_Definition__c(
                GTM_Instrument_Definition__c = definition.Id, Slot_Order__c = 2,
                Question_Text__c = 'Second?', Question_Key__c = 'q2', Question_Type__c = 'Single_Select'
            ),
            new GTM_Instrument_Question_Definition__c(
                GTM_Instrument_Definition__c = definition.Id, Slot_Order__c = 1,
                Question_Text__c = 'First?', Question_Key__c = 'q1', Question_Type__c = 'Single_Select'
            )
        };
        insert new List<GTM_Instrument_Outcome_Range__c>{
            new GTM_Instrument_Outcome_Range__c(
                GTM_Instrument_Definition__c = definition.Id, Min_Score__c = 0, Max_Score__c = 10,
                Tier_Label__c = 'Low', Sort_Order__c = 1
            ),
            new GTM_Instrument_Outcome_Range__c(
                GTM_Instrument_Definition__c = definition.Id, Min_Score__c = 11, Max_Score__c = 20,
                Tier_Label__c = 'High', Sort_Order__c = 2
            )
        };

        Test.startTest();
        GtmInstrumentDefinitionController.DefinitionDto dto =
            GtmInstrumentDefinitionController.getDefinitionForOffering('with-questions');
        Test.stopTest();

        Assert.isNotNull(dto);
        Assert.areEqual(2, dto.questions.size());
        Assert.areEqual('q1', dto.questions[0].questionKey);
        Assert.areEqual('q2', dto.questions[1].questionKey);
        Assert.areEqual(2, dto.outcomeRanges.size());
        Assert.areEqual('Low', dto.outcomeRanges[0].tierLabel);
        Assert.areEqual('High', dto.outcomeRanges[1].tierLabel);
    }

    @isTest
    static void saveDefinitionUpdatesNameStatusAndTheme() {
        GTM_Instrument_Definition__c definition = newDefinition('save-offering', 'Draft', 1);

        Test.startTest();
        GtmInstrumentDefinitionController.saveDefinition(definition.Id, 'Renamed', 'Draft', 'my-theme');
        Test.stopTest();

        GTM_Instrument_Definition__c stored = [
            SELECT Name, Status__c, Theme_Key__c FROM GTM_Instrument_Definition__c WHERE Id = :definition.Id
        ];
        Assert.areEqual('Renamed', stored.Name);
        Assert.areEqual('Draft', stored.Status__c);
        Assert.areEqual('my-theme', stored.Theme_Key__c);
    }

    @isTest
    static void saveQuestionsBatchUpsertsNewAndExisting() {
        GTM_Instrument_Definition__c definition = newDefinition('save-questions-offering', 'Draft', 1);
        GTM_Instrument_Question_Definition__c existing = new GTM_Instrument_Question_Definition__c(
            GTM_Instrument_Definition__c = definition.Id, Slot_Order__c = 1,
            Question_Text__c = 'Old text', Question_Key__c = 'q1', Question_Type__c = 'Single_Select'
        );
        insert existing;

        GtmInstrumentDefinitionController.QuestionDto updateDto =
            new GtmInstrumentDefinitionController.QuestionDto();
        updateDto.id = existing.Id;
        updateDto.slotOrder = 1;
        updateDto.questionText = 'Updated text';
        updateDto.questionKey = 'q1';
        updateDto.questionType = 'Single_Select';
        updateDto.required = true;

        GtmInstrumentDefinitionController.QuestionDto newDto =
            new GtmInstrumentDefinitionController.QuestionDto();
        newDto.slotOrder = 2;
        newDto.questionText = 'Brand new question';
        newDto.questionKey = 'q2';
        newDto.questionType = 'Single_Select';
        newDto.optionsJson = '[{"label":"Yes","value":"yes","points":10}]';

        Test.startTest();
        GtmInstrumentDefinitionController.saveQuestions(
            definition.Id,
            JSON.serialize(
                new List<GtmInstrumentDefinitionController.QuestionDto>{ updateDto, newDto }
            )
        );
        Test.stopTest();

        List<GTM_Instrument_Question_Definition__c> stored = [
            SELECT Question_Text__c, Question_Key__c, Required__c
            FROM GTM_Instrument_Question_Definition__c
            WHERE GTM_Instrument_Definition__c = :definition.Id
            ORDER BY Slot_Order__c
        ];
        Assert.areEqual(2, stored.size());
        Assert.areEqual('Updated text', stored[0].Question_Text__c);
        Assert.isTrue(stored[0].Required__c);
        Assert.areEqual('Brand new question', stored[1].Question_Text__c);
    }

    /**
     * Regression test for the real, live-confirmed root cause (gtm-staging
     * debug log 07LgK00000Sj1uHUAR, 2026-09-23T19:56:30Z): Aura's automatic
     * `List<QuestionDto>` parameter binder silently dropped `questionText`
     * before saveQuestions's body ran, even though the exact same JSON
     * string, run through `JSON.deserialize` directly, decoded correctly
     * (confirmed live on gtm-staging via anonymous Apex against this exact
     * class). This test proves the fix closes that gap the same way: it
     * builds the JSON as a raw string literal exactly as the LWC's
     * `JSON.stringify(this.questions.map(toQuestionDto))` would produce
     * it -- not by round-tripping an Apex-constructed DTO through
     * `JSON.serialize` -- so it exercises string-in, not object-in, the
     * same shape of input Aura's binder was proven to mishandle.
     */
    @isTest
    static void saveQuestionsPersistsQuestionTextFromARawJsonStringPayload() {
        GTM_Instrument_Definition__c definition = newDefinition('raw-json-offering', 'Draft', 1);
        String questionsJson =
            '[{"id":null,"slotOrder":1,"questionText":"Trace log test question",' +
            '"questionType":"Single_Select","optionsJson":"[]","rulesJson":"[]",' +
            '"required":false,"questionKey":"q1","minValue":null,"maxValue":null,' +
            '"pointsPerUnit":null}]';

        Test.startTest();
        GtmInstrumentDefinitionController.saveQuestions(definition.Id, questionsJson);
        Test.stopTest();

        GTM_Instrument_Question_Definition__c stored = [
            SELECT Question_Text__c FROM GTM_Instrument_Question_Definition__c
            WHERE GTM_Instrument_Definition__c = :definition.Id
            LIMIT 1
        ];
        Assert.areEqual('Trace log test question', stored.Question_Text__c,
            'JSON-string input must decode questionText correctly -- this is the exact ' +
            'payload shape that Aura\'s automatic List<QuestionDto> binder was proven to drop.');
    }

    @isTest
    static void saveQuestionsWithBlankJsonIsANoOp() {
        GTM_Instrument_Definition__c definition = newDefinition('blank-json-offering', 'Draft', 1);

        Test.startTest();
        GtmInstrumentDefinitionController.saveQuestions(definition.Id, null);
        GtmInstrumentDefinitionController.saveQuestions(definition.Id, '');
        GtmInstrumentDefinitionController.saveQuestions(definition.Id, '[]');
        Test.stopTest();

        Assert.areEqual(0, [
            SELECT COUNT() FROM GTM_Instrument_Question_Definition__c
            WHERE GTM_Instrument_Definition__c = :definition.Id
        ]);
    }

    @isTest
    static void saveOutcomeRangesPersistsTierLabelFromARawJsonStringPayload() {
        GTM_Instrument_Definition__c definition = newDefinition('raw-json-ranges-offering', 'Draft', 1);
        String rangesJson =
            '[{"id":null,"minScore":0,"maxScore":10,"tierLabel":"Low Readiness",' +
            '"readoutTemplateKey":"low-readiness","sortOrder":1}]';

        Test.startTest();
        GtmInstrumentDefinitionController.saveOutcomeRanges(definition.Id, rangesJson);
        Test.stopTest();

        GTM_Instrument_Outcome_Range__c stored = [
            SELECT Tier_Label__c, Readout_Template_Key__c FROM GTM_Instrument_Outcome_Range__c
            WHERE GTM_Instrument_Definition__c = :definition.Id
            LIMIT 1
        ];
        Assert.areEqual('Low Readiness', stored.Tier_Label__c);
        Assert.areEqual('low-readiness', stored.Readout_Template_Key__c);
    }

    @isTest
    static void deleteQuestionsRemovesRows() {
        GTM_Instrument_Definition__c definition = newDefinition('delete-questions-offering', 'Draft', 1);
        GTM_Instrument_Question_Definition__c existing = new GTM_Instrument_Question_Definition__c(
            GTM_Instrument_Definition__c = definition.Id, Slot_Order__c = 1,
            Question_Text__c = 'Gone soon', Question_Key__c = 'q1', Question_Type__c = 'Single_Select'
        );
        insert existing;

        Test.startTest();
        GtmInstrumentDefinitionController.deleteQuestions(new List<Id>{ existing.Id });
        Test.stopTest();

        Assert.areEqual(0, [
            SELECT COUNT() FROM GTM_Instrument_Question_Definition__c WHERE Id = :existing.Id
        ]);
    }

    @isTest
    static void saveOutcomeRangesBatchUpsertsNewAndExisting() {
        GTM_Instrument_Definition__c definition = newDefinition('save-ranges-offering', 'Draft', 1);
        GTM_Instrument_Outcome_Range__c existing = new GTM_Instrument_Outcome_Range__c(
            GTM_Instrument_Definition__c = definition.Id, Min_Score__c = 0, Max_Score__c = 10,
            Tier_Label__c = 'Old Tier', Sort_Order__c = 1
        );
        insert existing;

        GtmInstrumentDefinitionController.OutcomeRangeDto updateDto =
            new GtmInstrumentDefinitionController.OutcomeRangeDto();
        updateDto.id = existing.Id;
        updateDto.minScore = 0;
        updateDto.maxScore = 10;
        updateDto.tierLabel = 'Updated Tier';
        updateDto.sortOrder = 1;

        GtmInstrumentDefinitionController.OutcomeRangeDto newDto =
            new GtmInstrumentDefinitionController.OutcomeRangeDto();
        newDto.minScore = 11;
        newDto.maxScore = 20;
        newDto.tierLabel = 'New Tier';
        newDto.readoutTemplateKey = 'high-readiness';
        newDto.sortOrder = 2;

        Test.startTest();
        GtmInstrumentDefinitionController.saveOutcomeRanges(
            definition.Id,
            JSON.serialize(
                new List<GtmInstrumentDefinitionController.OutcomeRangeDto>{ updateDto, newDto }
            )
        );
        Test.stopTest();

        List<GTM_Instrument_Outcome_Range__c> stored = [
            SELECT Tier_Label__c, Readout_Template_Key__c
            FROM GTM_Instrument_Outcome_Range__c
            WHERE GTM_Instrument_Definition__c = :definition.Id
            ORDER BY Sort_Order__c
        ];
        Assert.areEqual(2, stored.size());
        Assert.areEqual('Updated Tier', stored[0].Tier_Label__c);
        Assert.areEqual('New Tier', stored[1].Tier_Label__c);
        Assert.areEqual('high-readiness', stored[1].Readout_Template_Key__c);
    }

    @isTest
    static void deleteOutcomeRangesRemovesRows() {
        GTM_Instrument_Definition__c definition = newDefinition('delete-ranges-offering', 'Draft', 1);
        GTM_Instrument_Outcome_Range__c existing = new GTM_Instrument_Outcome_Range__c(
            GTM_Instrument_Definition__c = definition.Id, Min_Score__c = 0, Max_Score__c = 10,
            Tier_Label__c = 'Gone soon', Sort_Order__c = 1
        );
        insert existing;

        Test.startTest();
        GtmInstrumentDefinitionController.deleteOutcomeRanges(new List<Id>{ existing.Id });
        Test.stopTest();

        Assert.areEqual(0, [
            SELECT COUNT() FROM GTM_Instrument_Outcome_Range__c WHERE Id = :existing.Id
        ]);
    }

    @isTest
    static void publishDefinitionActivatesAndIncrementsVersion() {
        GTM_Instrument_Definition__c definition = newDefinition('publish-offering', 'Draft', 1);

        Test.startTest();
        GtmInstrumentDefinitionController.publishDefinition(definition.Id);
        Test.stopTest();

        GTM_Instrument_Definition__c stored = [
            SELECT Status__c, Version__c FROM GTM_Instrument_Definition__c WHERE Id = :definition.Id
        ];
        Assert.areEqual('Active', stored.Status__c);
        Assert.areEqual(2, stored.Version__c);
    }

    @isTest
    static void archiveDefinitionSetsArchivedFromDraft() {
        GTM_Instrument_Definition__c definition = newDefinition('archive-offering', 'Draft', 1);

        Test.startTest();
        GtmInstrumentDefinitionController.archiveDefinition(definition.Id);
        Test.stopTest();

        GTM_Instrument_Definition__c stored = [
            SELECT Status__c FROM GTM_Instrument_Definition__c WHERE Id = :definition.Id
        ];
        Assert.areEqual('Archived', stored.Status__c);
    }

    /**
     * "Only one Active instrument per Offering_Key__c" (schema doc §2.1) is
     * guaranteed by Offering_Key__c's unique constraint, mirroring
     * GtmInstrumentControllerTest's equivalent proof for the legacy schema.
     */
    @isTest
    static void offeringKeyUniquenessPreventsASecondDefinitionForTheSameOffering() {
        newDefinition('supersede-offering', 'Active', 1);

        Test.startTest();
        Boolean threw = false;
        try {
            newDefinition('supersede-offering', 'Draft', 1);
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw,
            'Offering_Key__c is unique, so a second definition row for the same offering must be rejected');
        Assert.areEqual(1, [
            SELECT COUNT() FROM GTM_Instrument_Definition__c WHERE Offering_Key__c = 'supersede-offering'
        ]);
    }
}
