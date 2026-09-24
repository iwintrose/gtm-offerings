/**
 * Unit tests for GtmAgentApplyConfigUpdate — the dormant Agentforce invocable path.
 *
 * The class validates its inputs, filters to known delta keys, and publishes a
 * platform event via EventBus.publish. These tests drive it through the public
 * @InvocableMethod entry point and assert on the Output fields without relying on
 * the platform event being consumed (EventBus.publish is expected behavior here).
 */
@IsTest
private class GtmAgentApplyConfigUpdateTest {

    private static GtmAgentApplyConfigUpdate.Input input(String sessionToken, String updatesJson) {
        GtmAgentApplyConfigUpdate.Input inp = new GtmAgentApplyConfigUpdate.Input();
        inp.sessionToken = sessionToken;
        inp.updatesJson  = updatesJson;
        return inp;
    }

    private static GtmAgentApplyConfigUpdate.Output run(String sessionToken, String updatesJson) {
        List<GtmAgentApplyConfigUpdate.Output> results =
            GtmAgentApplyConfigUpdate.execute(
                new List<GtmAgentApplyConfigUpdate.Input>{ input(sessionToken, updatesJson) }
            );
        System.assertEquals(1, results.size(), 'execute() should return one output per input');
        return results[0];
    }

    @IsTest
    static void blankSessionToken_returnsFailureWithRequiredMessage() {
        Test.startTest();
        GtmAgentApplyConfigUpdate.Output out = run('', '{"company":"Acme"}');
        Test.stopTest();

        System.assertEquals(false, out.success,
            'A blank sessionToken should result in success == false');
        System.assert(out.errorMessage.containsIgnoreCase('sessionToken is required'),
            'Error should name the missing field; got: ' + out.errorMessage);
    }

    @IsTest
    static void blankUpdatesJson_returnsFailureWithRequiredMessage() {
        Test.startTest();
        GtmAgentApplyConfigUpdate.Output out = run('tok-abc', '');
        Test.stopTest();

        System.assertEquals(false, out.success,
            'A blank updatesJson should result in success == false');
        System.assert(out.errorMessage.containsIgnoreCase('updatesJson is required'),
            'Error should name the missing field; got: ' + out.errorMessage);
    }

    @IsTest
    static void malformedJson_returnsFailureWithParseMessage() {
        Test.startTest();
        GtmAgentApplyConfigUpdate.Output out = run('tok-abc', 'not { valid json }');
        Test.stopTest();

        System.assertEquals(false, out.success,
            'Malformed JSON should result in success == false');
        System.assert(out.errorMessage.containsIgnoreCase('not valid JSON'),
            'Error should indicate the JSON could not be parsed; got: ' + out.errorMessage);
    }

    @IsTest
    static void allUnknownKeys_returnsFailureWithNoRecognisedMessage() {
        Test.startTest();
        GtmAgentApplyConfigUpdate.Output out =
            run('tok-abc', JSON.serialize(new Map<String, Object>{ 'bogusField' => 'x', 'anotherFake' => 1 }));
        Test.stopTest();

        System.assertEquals(false, out.success,
            'All-unknown keys should result in success == false');
        System.assert(out.errorMessage.containsIgnoreCase('No recognised'),
            'Error should state that no recognised fields were found; got: ' + out.errorMessage);
    }

    @IsTest
    static void validDelta_returnsSuccessAndAppliedJsonContainsKey() {
        Test.startTest();
        GtmAgentApplyConfigUpdate.Output out =
            run('tok-abc', JSON.serialize(new Map<String, Object>{ 'company' => 'Acme' }));
        Test.stopTest();

        System.assertEquals(true, out.success,
            'A valid delta with a recognised key should succeed');
        System.assert(out.appliedJson.containsIgnoreCase('company'),
            'appliedJson should contain the applied key; got: ' + out.appliedJson);
        System.assert(String.isBlank(out.errorMessage),
            'No error message should be present on success; got: ' + out.errorMessage);
    }
}
