/**
 * Where an offering's SCORING FRAME comes from, once the frame stopped being a
 * compiled singleton.
 *
 * GtmAssessmentScoring and GtmEstateComplexity used to hardcode the whole frame
 * -- how many dimensions, what an answer may be worth, where the band edges sit
 * -- as `static final` constants. That was correct while Migration Accelerator
 * was the only offering and wrong the moment a second one existed, because a
 * second offering's instrument does not have to resemble Migration
 * Accelerator's in shape, dimension count, or answer scale (ADR-0007 section 6).
 *
 * GTM_Assessment_Frame__mdt holds one record per offering. This class is the
 * one place that reads it, so the query, the per-transaction cache and -- most
 * importantly -- the fail-open rule are written once rather than twice.
 *
 * FAIL OPEN, ALWAYS. Every method here returns null rather than throwing, on
 * every failure: no record for this offering, no records at all, no read
 * access, malformed JSON, bands that do not hold together. A null frame means
 * "use the caller's compiled Migration Accelerator constants", which is exactly
 * what every caller did before this class existed. That is the same discipline
 * GtmAssessmentInstrument.resolve already applies one layer up: a missing or
 * half-deployed configuration table is a DEPLOYMENT STATE, not a product
 * judgement, and an assessment that refuses to score because a config row is
 * absent is strictly worse than one scored against the base frame.
 *
 * A CONSEQUENCE WORTH SAYING OUT LOUD: because `migration-accelerator` has no
 * GTM_Assessment_Frame__mdt record deployed and is not meant to get one, the
 * fallback path is not a rarely-exercised error branch -- it is the path every
 * production assessment takes today. Its absence is deliberate and is what
 * proves the fallback works (ADR-0007 section 6, and the QA protocol's
 * isolation proof).
 */
public with sharing class GtmAssessmentFrames {

    /** The offering whose frame is the compiled fallback in both scorers. */
    public static final String MIGRATION_ACCELERATOR = 'migration-accelerator';

    /** Test seam: supply rows without deploying custom metadata. */
    @TestVisible
    private static List<GTM_Assessment_Frame__mdt> rowOverride;

    /**
     * offering key (lowercased) -> that offering's frame record.
     *
     * Keyed by offering rather than held as a flat list for the same reason
     * GtmAssessmentInstrument's caches became offering-keyed: a single guest or
     * admin transaction should never need two offerings' frames, but keying by
     * offering costs nothing and removes any chance of one offering's score
     * being computed against another's cached frame inside a batched preview.
     */
    private static Map<String, GTM_Assessment_Frame__mdt> cached;

    /**
     * This offering's frame record, or null to mean "fall back to the compiled
     * Migration Accelerator constants".
     */
    public static GTM_Assessment_Frame__mdt frameFor(String offeringKey) {
        if (String.isBlank(offeringKey)) {
            return null;
        }
        try {
            return rows().get(offeringKey.trim().toLowerCase());
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Parses a Bands_JSON__c value into the band list the scorer bands with, or
     * null when it cannot be trusted.
     *
     * REFUSED WHOLESALE RATHER THAN PATCHED. A band set that is empty, has a
     * gap, overlaps, descends, or is missing an edge is not a slightly-wrong
     * band set -- it is one that will put some totals in no band at all, or in
     * two. Falling back to the caller's compiled bands is the only reading that
     * does not invent a tier nobody authored. It is the same instinct
     * GtmAssessmentScoring.pointsAreTrustworthy already applies to authored
     * option points: fail to the frame, never to a private scale.
     */
    public static List<GtmAssessmentScoring.Band> parseBands(String jsonStr) {
        if (String.isBlank(jsonStr)) {
            return null;
        }
        try {
            Object raw = JSON.deserializeUntyped(jsonStr);
            if (!(raw instanceof List<Object>)) {
                return null;
            }
            List<GtmAssessmentScoring.Band> out = new List<GtmAssessmentScoring.Band>();
            Integer previousHighest = null;
            for (Object entry : (List<Object>) raw) {
                if (!(entry instanceof Map<String, Object>)) {
                    return null;
                }
                Map<String, Object> m = (Map<String, Object>) entry;
                String tier    = m.get('tier') == null ? null : String.valueOf(m.get('tier'));
                Integer lowest  = asInt(m.get('lowest'));
                Integer highest = asInt(m.get('highest'));
                if (String.isBlank(tier) || lowest == null || highest == null) {
                    return null;
                }
                if (lowest > highest) {
                    return null;
                }
                // Contiguous and ascending: each band starts exactly where the
                // previous one stopped. A gap is a total with no tier; an
                // overlap is a total with two.
                if (previousHighest != null && lowest != previousHighest + 1) {
                    return null;
                }
                previousHighest = highest;
                out.add(new GtmAssessmentScoring.Band(tier, lowest, highest));
            }
            return out.isEmpty() ? null : out;
        } catch (Exception e) {
            return null;
        }
    }

    /** The band a total falls in, from an already-parsed band list. */
    public static String tierFor(List<GtmAssessmentScoring.Band> bands, Decimal total) {
        if (bands == null || bands.isEmpty() || total == null) {
            return null;
        }
        for (GtmAssessmentScoring.Band b : bands) {
            if (total <= b.highest) {
                return b.tier;
            }
        }
        // Above the top band. The top band's tier is the honest answer: a total
        // that exceeds the authored maximum is still, unambiguously, in the
        // best band -- returning null would unband a submission for being too
        // good.
        return bands[bands.size() - 1].tier;
    }

    /** An Integer from a JSON number, or null if it is not a whole number. */
    private static Integer asInt(Object value) {
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Decimal || value instanceof Double) {
            Decimal d = Decimal.valueOf(String.valueOf(value));
            return d.scale() > 0 && d != d.setScale(0) ? null : d.intValue();
        }
        return null;
    }

    private static Map<String, GTM_Assessment_Frame__mdt> rows() {
        if (cached != null) {
            return cached;
        }
        cached = new Map<String, GTM_Assessment_Frame__mdt>();
        List<GTM_Assessment_Frame__mdt> found = rowOverride != null ? rowOverride : [
            SELECT Offering_Key__c, Min_Answer_Value__c, Max_Answer_Value__c,
                   Bands_JSON__c, Complexity_Min_Answer_Value__c,
                   Complexity_Max_Answer_Value__c, Complexity_Bands_JSON__c
            FROM GTM_Assessment_Frame__mdt
            LIMIT 200
        ];
        for (GTM_Assessment_Frame__mdt row : found) {
            if (String.isNotBlank(row.Offering_Key__c)) {
                cached.put(row.Offering_Key__c.trim().toLowerCase(), row);
            }
        }
        return cached;
    }

    /** Clears the per-transaction cache. Test-only. */
    @TestVisible
    private static void resetCache() {
        cached = null;
    }
}
