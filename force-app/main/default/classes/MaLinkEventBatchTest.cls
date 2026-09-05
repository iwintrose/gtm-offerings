/**
 * The batched interaction trail, and the identity stitching that turns an
 * anonymous read into a named one.
 */
@IsTest
private class MaLinkEventBatchTest {

    private static MA_Saved_Configuration__c link() {
        MA_Saved_Configuration__c c = new MA_Saved_Configuration__c(
            Offering__c = 'migration-accelerator', Company__c = 'Acme Bank',
            Generated_URL__c = 'https://example.com/a', Active__c = true
        );
        insert c;
        return c;
    }

    private static MaLinkEventController.EventInput evt(String type, String step, Integer seq, Decimal dwell) {
        MaLinkEventController.EventInput e = new MaLinkEventController.EventInput();
        e.eventType = type; e.step = step; e.sequence = seq; e.dwellSeconds = dwell;
        return e;
    }

    @IsTest
    static void aVisitsTrailArrivesInOneCall() {
        MA_Saved_Configuration__c c = link();
        List<MaLinkEventController.EventInput> batch = new List<MaLinkEventController.EventInput>{
            evt('Section Viewed', 'header',    1, 2.44),
            evt('Section Viewed', 'challenge', 2, 9.06),
            evt('Session End',    null,        3, null)
        };

        Test.startTest();
        MaLinkEventController.logEvents(c.Id, 'sess-1', batch);
        Test.stopTest();

        List<MA_Link_Event__c> rows = [
            SELECT Event_Type__c, Step__c, Dwell_Seconds__c, Sequence__c
            FROM MA_Link_Event__c WHERE Session_Id__c = 'sess-1'
            ORDER BY Sequence__c ASC
        ];
        Assert.areEqual(3, rows.size());
        Assert.areEqual('header', rows[0].Step__c);
        // Tenths is all a dwell measurement means; storing more invites reading
        // it as precision it does not have.
        Assert.areEqual(2.4, rows[0].Dwell_Seconds__c);
        Assert.areEqual(9.1, rows[1].Dwell_Seconds__c);
        Assert.areEqual('Session End', rows[2].Event_Type__c);
    }

    @IsTest
    static void aRunawayBatchIsCapped() {
        MA_Saved_Configuration__c c = link();
        List<MaLinkEventController.EventInput> batch = new List<MaLinkEventController.EventInput>();
        for (Integer i = 0; i < 200; i++) batch.add(evt('Section Viewed', 'header', i, 1.0));

        Test.startTest();
        MaLinkEventController.logEvents(c.Id, 'sess-2', batch);
        Test.stopTest();

        Assert.areEqual(60, [SELECT COUNT() FROM MA_Link_Event__c WHERE Session_Id__c = 'sess-2'],
            'A visit producing this much is a bot or a bug; the tail is not worth the rows');
    }

    @IsTest
    static void aBadLinkOrEmptyBatchWritesNothing() {
        Test.startTest();
        MaLinkEventController.logEvents('not-an-id', 'sess-3', new List<MaLinkEventController.EventInput>{
            evt('Section Viewed', 'header', 1, 1.0)
        });
        MaLinkEventController.logEvents(link().Id, 'sess-3', null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM MA_Link_Event__c WHERE Session_Id__c = 'sess-3']);
    }

    /**
     * The reading that led to a request becomes attributable to the person who
     * did it, retroactively — the whole point of stitching an anonymous session
     * to a known contact.
     */
    @IsTest
    static void submittingNamesTheWholeSessionRetroactively() {
        MA_Saved_Configuration__c c = link();
        Contact who = new Contact(FirstName = 'Ann', LastName = 'Reyes', Email = 'ann@example.com');
        insert who;
        MaLinkEventController.logEvents(c.Id, 'sess-4', new List<MaLinkEventController.EventInput>{
            evt('Section Viewed', 'header', 1, 2.0),
            evt('Section Viewed', 'proof',  2, 8.0)
        });

        Test.startTest();
        MaLinkEventController.identifySession(c.Id, 'sess-4', who.Id);
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM MA_Link_Event__c
                            WHERE Session_Id__c = 'sess-4' AND Contact__c = :who.Id],
            'Everything read before they said who they are becomes theirs');
    }

    @IsTest
    static void anotherSessionIsNeverStitchedByMistake() {
        MA_Saved_Configuration__c c = link();
        Contact who = new Contact(FirstName = 'Ann', LastName = 'Reyes', Email = 'ann@example.com');
        insert who;
        MaLinkEventController.logEvents(c.Id, 'mine',      new List<MaLinkEventController.EventInput>{ evt('Page View', null, 1, null) });
        MaLinkEventController.logEvents(c.Id, 'somebody-else', new List<MaLinkEventController.EventInput>{ evt('Page View', null, 1, null) });

        Test.startTest();
        MaLinkEventController.identifySession(c.Id, 'mine', who.Id);
        MaLinkEventController.identifySession(c.Id, 'mine', 'not-a-contact-id');
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM MA_Link_Event__c WHERE Contact__c = :who.Id]);
        Assert.areEqual(null, [SELECT Contact__c FROM MA_Link_Event__c
                               WHERE Session_Id__c = 'somebody-else' LIMIT 1].Contact__c);
    }
}
