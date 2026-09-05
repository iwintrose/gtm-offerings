/**
 * One name for a deal this app creates.
 *
 * Two code paths create opportunities -- a prospect submitting an assessment
 * request, and a rep saving an engagement link -- and each had invented its
 * own convention. The result in one org was:
 *
 *     MUCH Music - Assessment Follow-up      (request path, hyphen)
 *     Migration Accelerator — MUCH Music     (link path, em dash, offering
 *                                             hardcoded rather than looked up)
 *
 * Same kind of record, same account, two shapes and two dashes. Anyone
 * scanning the Opportunities list had to know which code path made which name
 * to understand what they were looking at.
 *
 * The convention is "<Client> — <Offering>": the client leads because the
 * list is read by client, and the offering qualifies it. One dash, one order,
 * one source for the offering's label.
 */
public with sharing class GtmDealNaming {

    /** Used when an offering key is missing or unknown to the metadata. */
    @TestVisible
    private static final String FALLBACK_OFFERING = 'Assessment Follow-up';

    /**
     * The offering's own label, from MA_Offering__mdt.
     *
     * Both paths used to answer this differently: one looked it up, the other
     * hardcoded 'Migration Accelerator', which would have been wrong the day a
     * second offering existed.
     */
    public static String offeringLabel(String offeringKey) {
        if (String.isBlank(offeringKey)) return FALLBACK_OFFERING;
        try {
            List<MA_Offering__mdt> rows = [
                SELECT Label__c FROM MA_Offering__mdt
                WHERE Offering_Key__c = :offeringKey LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Label__c)) {
                return rows[0].Label__c;
            }
        } catch (Exception e) {
            // A metadata read failing is not a reason to fail the save.
        }
        return FALLBACK_OFFERING;
    }

    /**
     * The name a new deal gets.
     *
     * When the account already has one by this name, the new one carries the
     * date it was opened -- two identically named deals on one account is the
     * same guessing problem one level down, and a rep picking from a list
     * could not tell them apart.
     */
    public static String nameFor(String company, String offeringKey, Id accountId) {
        String client = String.isNotBlank(company) ? company.trim() : 'New Prospect';
        String base   = client + ' — ' + offeringLabel(offeringKey);
        if (accountId == null) return base;

        Integer clash = [
            SELECT COUNT() FROM Opportunity WHERE AccountId = :accountId AND Name = :base
        ];
        return clash > 0 ? base + ' (' + Date.today().format() + ')' : base;
    }
}
