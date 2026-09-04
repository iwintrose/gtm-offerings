@IsTest
private class MaAgentConfigActionsTest {

    // ─── MaAgentGetConfigState ───────────────────────────────────────────────

    @IsTest
    static void getState_blankConfigId_returnsDefaults() {
        MaAgentGetConfigState.Input inp = new MaAgentGetConfigState.Input();
        inp.configId = '';

        Test.startTest();
        List<MaAgentGetConfigState.Output> results =
            MaAgentGetConfigState.execute(
                new List<MaAgentGetConfigState.Input>{ inp }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        MaAgentGetConfigState.Output out = results[0];
        System.assertEquals('', out.company,  'blank configId → empty company');
        System.assertEquals('', out.industry, 'blank configId → empty industry');
        System.assertEquals(0,  out.objectsCount, 'blank configId → 0 objectsCount');
        System.assertNotEquals(null, out.availableIndustries, 'availableIndustries list returned');
    }

    @IsTest
    static void getState_withSavedConfig_returnsPayloadValues() {
        MA_Saved_Configuration__c cfg = new MA_Saved_Configuration__c(
            Config_Payload__c = '{"company":"Acme","industry":"tech","accent":"#FF5733","objectsCount":800,"depsCount":120,"healthScore":72,"note":"Test note"}'
        );
        insert cfg;

        MaAgentGetConfigState.Input inp = new MaAgentGetConfigState.Input();
        inp.configId = cfg.Id;

        Test.startTest();
        List<MaAgentGetConfigState.Output> results =
            MaAgentGetConfigState.execute(
                new List<MaAgentGetConfigState.Input>{ inp }
            );
        Test.stopTest();

        MaAgentGetConfigState.Output out = results[0];
        System.assertEquals('Acme',    out.company,      'company from payload');
        System.assertEquals('tech',    out.industry,     'industry from payload');
        System.assertEquals('#FF5733', out.accent,       'accent from payload');
        System.assertEquals(800, out.objectsCount,       'objectsCount from payload');
        System.assertEquals(120, out.depsCount,          'depsCount from payload');
        System.assertEquals(72,  out.healthScore,        'healthScore from payload');
        System.assertEquals('Test note', out.note,       'note from payload');
    }

    @IsTest
    static void getState_malformedPayload_returnsDefaults() {
        MA_Saved_Configuration__c cfg = new MA_Saved_Configuration__c(
            Config_Payload__c = 'NOT VALID JSON {'
        );
        insert cfg;

        MaAgentGetConfigState.Input inp = new MaAgentGetConfigState.Input();
        inp.configId = cfg.Id;

        Test.startTest();
        List<MaAgentGetConfigState.Output> results =
            MaAgentGetConfigState.execute(
                new List<MaAgentGetConfigState.Input>{ inp }
            );
        Test.stopTest();

        MaAgentGetConfigState.Output out = results[0];
        System.assertEquals('', out.company,      'malformed payload → default company');
        System.assertEquals(0,  out.objectsCount, 'malformed payload → 0 objectsCount');
    }

    // ─── MaAgentApplyConfigUpdate ────────────────────────────────────────────

    @IsTest
    static void applyUpdate_validDelta_publishesEvent() {
        MaAgentApplyConfigUpdate.Input inp = new MaAgentApplyConfigUpdate.Input();
        inp.sessionToken = 'test-session-uuid-1234';
        inp.updatesJson  = '{"company":"Metrolinx","industry":"public-sector","objectsCount":900}';

        Test.startTest();
        List<MaAgentApplyConfigUpdate.Output> results =
            MaAgentApplyConfigUpdate.execute(
                new List<MaAgentApplyConfigUpdate.Input>{ inp }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        MaAgentApplyConfigUpdate.Output out = results[0];
        System.assertEquals(true, out.success, 'valid delta → success');
        System.assertNotEquals(null, out.appliedJson, 'appliedJson returned');
        System.assert(out.appliedJson.contains('Metrolinx'), 'company in appliedJson');
    }

    @IsTest
    static void applyUpdate_partialDelta_stripsUnknownKeys() {
        MaAgentApplyConfigUpdate.Input inp = new MaAgentApplyConfigUpdate.Input();
        inp.sessionToken = 'test-session-uuid-5678';
        inp.updatesJson  = '{"company":"Acme","unknownField":"ignored","note":"hello"}';

        Test.startTest();
        List<MaAgentApplyConfigUpdate.Output> results =
            MaAgentApplyConfigUpdate.execute(
                new List<MaAgentApplyConfigUpdate.Input>{ inp }
            );
        Test.stopTest();

        MaAgentApplyConfigUpdate.Output out = results[0];
        System.assertEquals(true, out.success, 'unknown keys stripped, still succeeds');
        System.assert(!out.appliedJson.contains('unknownField'), 'unknownField not in applied JSON');
    }

    @IsTest
    static void applyUpdate_invalidAccent_returnsError() {
        MaAgentApplyConfigUpdate.Input inp = new MaAgentApplyConfigUpdate.Input();
        inp.sessionToken = 'test-session-uuid-9999';
        inp.updatesJson  = '{"accent":"not-a-hex-color"}';

        Test.startTest();
        List<MaAgentApplyConfigUpdate.Output> results =
            MaAgentApplyConfigUpdate.execute(
                new List<MaAgentApplyConfigUpdate.Input>{ inp }
            );
        Test.stopTest();

        MaAgentApplyConfigUpdate.Output out = results[0];
        System.assertEquals(false, out.success, 'invalid accent → failure');
        System.assert(out.errorMessage.contains('hex'), 'error mentions hex');
    }

    @IsTest
    static void applyUpdate_invalidHealthScore_returnsError() {
        MaAgentApplyConfigUpdate.Input inp = new MaAgentApplyConfigUpdate.Input();
        inp.sessionToken = 'test-session-uuid-aaaa';
        inp.updatesJson  = '{"healthScore":150}';

        Test.startTest();
        List<MaAgentApplyConfigUpdate.Output> results =
            MaAgentApplyConfigUpdate.execute(
                new List<MaAgentApplyConfigUpdate.Input>{ inp }
            );
        Test.stopTest();

        MaAgentApplyConfigUpdate.Output out = results[0];
        System.assertEquals(false, out.success, 'healthScore > 100 → failure');
    }

    @IsTest
    static void applyUpdate_blankSessionToken_returnsError() {
        MaAgentApplyConfigUpdate.Input inp = new MaAgentApplyConfigUpdate.Input();
        inp.sessionToken = '';
        inp.updatesJson  = '{"company":"Test"}';

        Test.startTest();
        List<MaAgentApplyConfigUpdate.Output> results =
            MaAgentApplyConfigUpdate.execute(
                new List<MaAgentApplyConfigUpdate.Input>{ inp }
            );
        Test.stopTest();

        MaAgentApplyConfigUpdate.Output out = results[0];
        System.assertEquals(false, out.success, 'blank sessionToken → failure');
    }

    @IsTest
    static void applyUpdate_invalidJson_returnsError() {
        MaAgentApplyConfigUpdate.Input inp = new MaAgentApplyConfigUpdate.Input();
        inp.sessionToken = 'test-session-uuid-bbbb';
        inp.updatesJson  = 'not json at all {{{';

        Test.startTest();
        List<MaAgentApplyConfigUpdate.Output> results =
            MaAgentApplyConfigUpdate.execute(
                new List<MaAgentApplyConfigUpdate.Input>{ inp }
            );
        Test.stopTest();

        MaAgentApplyConfigUpdate.Output out = results[0];
        System.assertEquals(false, out.success, 'invalid JSON → failure');
        System.assert(out.errorMessage.contains('JSON'), 'error mentions JSON');
    }

    @IsTest
    static void applyUpdate_allUnknownKeys_returnsError() {
        MaAgentApplyConfigUpdate.Input inp = new MaAgentApplyConfigUpdate.Input();
        inp.sessionToken = 'test-session-uuid-cccc';
        inp.updatesJson  = '{"notAField":"ignored","alsoUnknown":42}';

        Test.startTest();
        List<MaAgentApplyConfigUpdate.Output> results =
            MaAgentApplyConfigUpdate.execute(
                new List<MaAgentApplyConfigUpdate.Input>{ inp }
            );
        Test.stopTest();

        MaAgentApplyConfigUpdate.Output out = results[0];
        System.assertEquals(false, out.success, 'all-unknown keys → failure');
        System.assert(String.isNotBlank(out.errorMessage), 'error message provided');
    }
}
