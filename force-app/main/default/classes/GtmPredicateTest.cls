/**
 * UNVERIFIED — there is no Salesforce CLI and no org in the environment this was
 * written in, so nothing here has been compiled or executed. Run it before merge.
 *
 * This class pins the ONE predicate grammar the instrument has. There are three
 * implementations of it -- this one, the browser copy in
 * force-app/main/default/lwc/gtmPredicate, and the Python mirror in
 * scripts/build-instrument.py that proves branches are reachable at build time.
 * Three copies only stay one grammar if the same cases are asserted against all
 * three, so every case here has a named counterpart in gtmPredicate.test.js.
 */
@IsTest
private class GtmPredicateTest {

    private static Object p(String jsonStr) {
        return GtmPredicate.parse(jsonStr);
    }

    @IsTest
    static void aFieldWithNoValueIsAlwaysFalse() {
        // The rule branching leans on: a variant whose predicate names an
        // unanswered slot does not fire, so the slot keeps its default question
        // and stays answered. Note that even `ne` is false -- "not equal to
        // something you never told us" is not a fact about the respondent.
        Map<String, Object> empty = new Map<String, Object>();
        System.assertEquals(false,
            GtmPredicate.matches(p('{"field":"estate_scale","op":"eq","value":1}'), empty));
        System.assertEquals(false,
            GtmPredicate.matches(p('{"field":"estate_scale","op":"ne","value":99}'), empty));
        System.assertEquals(false,
            GtmPredicate.matches(p('{"field":"estate_scale","op":"lte","value":4}'), empty));
    }

    @IsTest
    static void numbersCompareAsNumbersAndTextAsTrimmedCaseInsensitive() {
        Map<String, Object> ctx = new Map<String, Object>{
            'a' => 3, 't' => ' sfmc_next '
        };
        System.assertEquals(true,
            GtmPredicate.matches(p('{"field":"a","op":"eq","value":"3"}'), ctx),
            'A consultant writing YAML should not have to think about quoting');
        System.assertEquals(true,
            GtmPredicate.matches(p('{"field":"t","op":"eq","value":"SFMC_Next"}'), ctx));
    }

    @IsTest
    static void everyDocumentedOperatorWorks() {
        Map<String, Object> ctx = new Map<String, Object>{ 'a' => 3, 't' => 'sfmc_next' };
        System.assertEquals(true,  GtmPredicate.matches(p('{"field":"a","op":"lt","value":4}'), ctx));
        System.assertEquals(true,  GtmPredicate.matches(p('{"field":"a","op":"lte","value":3}'), ctx));
        System.assertEquals(true,  GtmPredicate.matches(p('{"field":"a","op":"gt","value":2}'), ctx));
        System.assertEquals(true,  GtmPredicate.matches(p('{"field":"a","op":"gte","value":3}'), ctx));
        System.assertEquals(true,  GtmPredicate.matches(p('{"field":"a","op":"ne","value":4}'), ctx));
        System.assertEquals(true,
            GtmPredicate.matches(p('{"field":"t","op":"in","value":["sfmc","sfmc_next"]}'), ctx));
        System.assertEquals(true,
            GtmPredicate.matches(p('{"field":"t","op":"not_in","value":["sfmc"]}'), ctx));
        System.assertEquals(false,
            GtmPredicate.matches(p('{"field":"a","op":"not_an_op","value":3}'), ctx),
            'An operator the language does not have must be false, not an exception');
    }

    @IsTest
    static void allAndAnyNest() {
        Map<String, Object> ctx = new Map<String, Object>{ 'a' => 1, 'b' => 4 };
        System.assertEquals(true, GtmPredicate.matches(
            p('{"all":[{"field":"a","op":"eq","value":1},{"field":"b","op":"gte","value":4}]}'), ctx));
        System.assertEquals(true, GtmPredicate.matches(
            p('{"any":[{"field":"a","op":"eq","value":9},{"field":"b","op":"eq","value":4}]}'), ctx));
        System.assertEquals(false, GtmPredicate.matches(
            p('{"all":[{"field":"a","op":"eq","value":9}]}'), ctx));
        System.assertEquals(true, GtmPredicate.matches(
            p('{"all":[{"any":[{"field":"a","op":"eq","value":1}]}]}'), ctx),
            'Groups nest inside groups');
    }

    @IsTest
    static void rubbishIsFalseRatherThanAnException() {
        Map<String, Object> ctx = new Map<String, Object>{ 'a' => 1 };
        System.assertEquals(false, GtmPredicate.matches(null, ctx));
        System.assertEquals(false, GtmPredicate.matches('not a node', ctx));
        System.assertEquals(false, GtmPredicate.matches(p('{"field":"a","op":"eq","value":1}'), null));
        System.assertEquals(null, GtmPredicate.parse('{oh no'),
            'Unparseable JSON leaves a gate inert and a branch not taken');
        System.assertEquals(null, GtmPredicate.parse(''));
        System.assertEquals(null, GtmPredicate.parse(null));
    }

    @IsTest
    static void theOperatorSetIsTheOneTheBuildScriptEnforces() {
        // scripts/build-instrument.py has its own copy of this list (OPS). If
        // the two drift, an author can write a predicate the build accepts and
        // the runtime silently never matches.
        System.assertEquals(
            new Set<String>{ 'eq', 'ne', 'lt', 'lte', 'gt', 'gte', 'in', 'not_in' },
            GtmPredicate.OPERATORS
        );
    }
}
