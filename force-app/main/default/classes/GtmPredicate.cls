/**
 * The instrument's ONE predicate language, in one place.
 *
 * It was born inside GtmAssessmentReadout, where a gate is a boolean predicate
 * over the answers. Answer-driven branching (GTM_Assessment_Dimension_Override__mdt
 * .Show_When_JSON__c) needs exactly the same thing: a small, data-authored
 * boolean over answers plus source/target. Giving branching its own dialect
 * would have meant two grammars for one job, two evaluators to keep in step,
 * and a consultant who has to remember which file wants `in` and which wants
 * `oneOf`. So the evaluator moved here and both callers use it.
 *
 *     {"all": [clause, ...]}     every child must match
 *     {"any": [clause, ...]}     at least one child must match
 *     {"field": k, "op": o, "value": v}
 *
 *     op  ::  eq | ne | lt | lte | gt | gte | in | not_in
 *
 * TWO RULES THAT LOOK LIKE DETAILS AND ARE NOT:
 *
 *   A field with no value in the context makes its clause FALSE, always. For a
 *   gate that is because a gate firing on data nobody supplied reads to a
 *   prospect as the tool guessing. For a branch it is the same property wearing
 *   different clothes: a variant whose predicate references an unanswered slot
 *   does not fire, so the slot keeps its default question and stays answered.
 *   Unknown data can never empty a slot.
 *
 *   Numbers compare as numbers and everything else as trimmed, case-insensitive
 *   text, so a predicate authored as {"value": "3"} and an answer of 3 agree.
 *   Consultants author YAML; YAML quoting is not a thing they should have to
 *   think about to get a gate to fire.
 *
 * Pure: no SOQL, no DML, no statics. It is reached from a guest-facing,
 * without-sharing submit path, so it reads nothing and writes nothing.
 */
public with sharing class GtmPredicate {

    /** Operators the language accepts. Kept in step with scripts/build-instrument.py. */
    public static final Set<String> OPERATORS = new Set<String>{
        'eq', 'ne', 'lt', 'lte', 'gt', 'gte', 'in', 'not_in'
    };

    /**
     * True when `node` (a parsed predicate) holds against `context`.
     *
     * Never throws: a malformed node is FALSE, not an exception. Both callers
     * run inside a path that must not fail because someone typed bad JSON into
     * a metadata row -- a gate that cannot be parsed stays inert, and a branch
     * that cannot be parsed leaves the default question in place.
     */
    public static Boolean matches(Object node, Map<String, Object> context) {
        try {
            return evaluate(node, context == null ? new Map<String, Object>() : context);
        } catch (Exception e) {
            return false;
        }
    }

    /** Parses a predicate string, or null when it is blank or unusable. */
    public static Object parse(String jsonStr) {
        if (String.isBlank(jsonStr)) {
            return null;
        }
        try {
            return JSON.deserializeUntyped(jsonStr);
        } catch (Exception e) {
            return null;
        }
    }

    // --------------------------------------------------------------- private

    private static Boolean evaluate(Object node, Map<String, Object> context) {
        if (!(node instanceof Map<String, Object>)) {
            return false;
        }
        Map<String, Object> m = (Map<String, Object>) node;

        if (m.containsKey('all')) {
            for (Object child : childList(m.get('all'))) {
                if (!evaluate(child, context)) {
                    return false;
                }
            }
            return true;
        }
        if (m.containsKey('any')) {
            for (Object child : childList(m.get('any'))) {
                if (evaluate(child, context)) {
                    return true;
                }
            }
            return false;
        }

        Object actual = context.get(String.valueOf(m.get('field')));
        if (actual == null) {
            return false;
        }
        String op       = String.valueOf(m.get('op'));
        Object expected = m.get('value');

        if (op == 'in' || op == 'not_in') {
            Boolean found = false;
            for (Object candidate : childList(expected)) {
                if (equalish(actual, candidate)) {
                    found = true;
                    break;
                }
            }
            return op == 'in' ? found : !found;
        }
        if (op == 'eq') { return equalish(actual, expected); }
        if (op == 'ne') { return !equalish(actual, expected); }

        Decimal a = asDecimal(actual);
        Decimal b = asDecimal(expected);
        if (a == null || b == null) {
            return false;
        }
        if (op == 'lt')  { return a <  b; }
        if (op == 'lte') { return a <= b; }
        if (op == 'gt')  { return a >  b; }
        if (op == 'gte') { return a >= b; }
        return false;
    }

    private static List<Object> childList(Object value) {
        return value instanceof List<Object>
            ? (List<Object>) value
            : new List<Object>();
    }

    /** Numbers compare as numbers, everything else compares as trimmed text. */
    private static Boolean equalish(Object a, Object b) {
        Decimal da = asDecimal(a);
        Decimal db = asDecimal(b);
        if (da != null && db != null) {
            return da == db;
        }
        return a != null && b != null &&
            String.valueOf(a).trim().equalsIgnoreCase(String.valueOf(b).trim());
    }

    private static Decimal asDecimal(Object value) {
        if (value instanceof Integer) { return Decimal.valueOf((Integer) value); }
        if (value instanceof Decimal) { return (Decimal) value; }
        if (value instanceof Double)  { return Decimal.valueOf((Double) value); }
        if (value instanceof Long)    { return Decimal.valueOf((Long) value); }
        return null;
    }
}
