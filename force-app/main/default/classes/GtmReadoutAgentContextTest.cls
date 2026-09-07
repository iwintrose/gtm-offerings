/**
 * Access enforcement and context assembly for the readout assistant.
 *
 * The tests that matter most here are the negative ones: a rep who does not own
 * a readout, and is not in the triage queue, must not be able to read it or
 * write notes on it through GUS — regardless of the fact that the tool loop
 * that calls this runs in a `without sharing` class.
 *
 * NOT RUN. No Salesforce CLI or org was available where this was written, so no
 * Apex in this change has been compiled or executed. Unverified.
 */
@isTest
private class GtmReadoutAgentContextTest {

    private static GTM_Assessment_Request__c seedRequest() {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = 'alex.rivera@example.com',
            Company__c          = 'Northwind Retail',
            Assessment_Score__c = 18,
            Assessment_Tier__c  = 'Prep Required',
            Section_Scores__c   = '{"estate_scale":3,"source_access":2}',
            Estate_Complexity_Score__c = 15,
            Estate_Complexity_Band__c  = 'Heavy',
            Estate_Complexity_Dimensions__c = '{"journey_footprint":3}',
            Assessment_Flags__c = '[{"code":"rebuild_ratio","message":"High rebuild ratio."}]',
            Pain_Points__c      = 'Manual list hygiene.',
            Context__c          = 'Contract renewal in March.'
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

    // --------------------------------------------------------------- context

    @isTest
    static void readoutContextCarriesScoresTierAndBothAxes() {
        GTM_Assessment_Request__c req = seedRequest();
        GTM_Readout__c r = seedReadout(req.Id);

        Map<String, Object> ctx = GtmReadoutAgentContext.readoutContext(r.Id);

        System.assertEquals('Draft', ctx.get('status'));
        System.assertEquals(true, ctx.get('editable'));
        Map<String, Object> a = (Map<String, Object>) ctx.get('assessment');
        System.assertEquals(true, a.get('present'));
        System.assertEquals(18, a.get('readinessScore'));
        System.assertEquals(GtmAssessmentScoring.MAX_TOTAL_SCORE, a.get('readinessMaxScore'));
        System.assertEquals('Prep Required', a.get('tier'));
        System.assertEquals('Heavy', a.get('complexityBand'));
        System.assert(String.valueOf(a.get('scoreMeaning')).contains('HIGHER'),
            'the score direction must travel with the score');
        System.assertEquals(2, ((List<Object>) a.get('readinessDimensions')).size());
        System.assertEquals(1, ((List<Object>) a.get('annotations')).size());
    }

    @isTest
    static void advisoryAssessmentReportsNoTier() {
        GTM_Assessment_Request__c req = seedRequest();
        req.Assessment_Advisory__c = true;
        req.Advisory_Reason__c = 'Pair not supported.';
        update req;
        GTM_Readout__c r = seedReadout(req.Id);

        Map<String, Object> a =
            (Map<String, Object>) GtmReadoutAgentContext.readoutContext(r.Id).get('assessment');

        System.assertEquals(true, a.get('advisoryOnly'));
        System.assertEquals(null, a.get('tier'),
            'an advisory readout must not carry a tier the model could quote');
    }

    @isTest
    static void aReadoutWithNoAssessmentSaysSoRatherThanFailing() {
        GTM_Readout__c r = new GTM_Readout__c(
            Status__c       = 'Draft',
            Offering_Key__c = 'migration-accelerator'
        );
        insert r;
        Map<String, Object> a =
            (Map<String, Object>) GtmReadoutAgentContext.readoutContext(r.Id).get('assessment');
        System.assertEquals(false, a.get('present'));
    }

    @isTest
    static void malformedScoreBlobsDegradeToEmptyRatherThanThrowing() {
        GTM_Assessment_Request__c req = seedRequest();
        req.Section_Scores__c = 'not json at all';
        req.Assessment_Flags__c = '{{{';
        update req;
        GTM_Readout__c r = seedReadout(req.Id);

        Map<String, Object> a =
            (Map<String, Object>) GtmReadoutAgentContext.readoutContext(r.Id).get('assessment');
        System.assertEquals(0, ((List<Object>) a.get('readinessDimensions')).size());
        System.assertEquals(0, ((List<Object>) a.get('annotations')).size());
    }

    // ------------------------------------------------------------ rep context

    @isTest
    static void repContextReturnsSavedNotes() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        GtmReadoutAgentContext.saveRepNotes(r.Id, 'Procurement is the blocker.');

        Map<String, Object> ctx = GtmReadoutAgentContext.repContext(r.Id);
        System.assertEquals('Procurement is the blocker.', ctx.get('repNotes'));
    }

    @isTest
    static void notesLongerThanTheCapAreRefused() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        Boolean threw = false;
        try {
            GtmReadoutAgentContext.saveRepNotes(
                r.Id, 'x'.repeat(GtmReadoutAgentContext.MAX_NOTES_CHARS + 1));
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'oversized notes should be refused, not silently clipped');
    }

    @isTest
    static void notesCanBeSavedOnAnApprovedReadout() {
        // Deliberate: notes are internal and never published, so writing down
        // what a client just said is not gated on the approval state of the
        // client-facing content.
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        update new GTM_Readout__c(Id = r.Id, Status__c = 'Approved');

        GtmReadoutAgentContext.saveRepNotes(r.Id, 'They pushed the date.');
        System.assertEquals('They pushed the date.',
            [SELECT Rep_Context_Notes__c FROM GTM_Readout__c WHERE Id = :r.Id].Rep_Context_Notes__c);
    }

    // ----------------------------------------------------------------- access

    @isTest
    static void aRepWithoutAccessCannotReadTheReadout() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        User stranger = createRep('gtmst1');

        Boolean threw = false;
        System.runAs(stranger) {
            System.assertEquals(false, GtmReadoutAgentContext.hasAccess(r.Id, false),
                'a rep who does not own the readout must not have read access');
            try {
                GtmReadoutAgentContext.assertReadable(r.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void readoutContextRefusesRatherThanThrowsForAStranger() {
        // The tool-call path needs a JSON error, not an exception.
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        User stranger = createRep('gtmst2');
        System.runAs(stranger) {
            System.assert(GtmReadoutAgentContext.readoutContext(r.Id).containsKey('error'));
            System.assert(GtmReadoutAgentContext.repContext(r.Id).containsKey('error'));
        }
    }

    @isTest
    static void aRepWithoutAccessCannotWriteNotes() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        User stranger = createRep('gtmst3');

        Boolean threw = false;
        System.runAs(stranger) {
            try {
                GtmReadoutAgentContext.saveRepNotes(r.Id, 'should never land');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw);
        System.assertEquals(null,
            [SELECT Rep_Context_Notes__c FROM GTM_Readout__c WHERE Id = :r.Id].Rep_Context_Notes__c);
    }

    @isTest
    static void aNullReadoutIdIsRejected() {
        Boolean threw = false;
        try {
            GtmReadoutAgentContext.assertReadable(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
        System.assertEquals(false, GtmReadoutAgentContext.hasAccess(null, false));
    }

    @isTest
    static void getRepNotesReturnsWhatWasSaved() {
        GTM_Readout__c r = seedReadout(seedRequest().Id);
        GtmReadoutAgentContext.saveRepNotes(r.Id, 'Notes.');
        System.assertEquals('Notes.', GtmReadoutAgentContext.getRepNotes(r.Id));
    }
}
