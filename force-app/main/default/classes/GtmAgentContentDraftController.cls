/**
 * GUS entry point for the Content Manager "Draft with AI" modal.
 *
 * Deliberately a SEPARATE class from GtmAgentProxyController rather than a
 * new @AuraEnabled method on it. Apex class-access permission (Setup ->
 * Permission Sets -> Apex Class Access) gates the class a client directly
 * invokes, not classes that class calls into server-side -- so granting
 * GTM_Content_Manager/GTM_Content_Admin access to THIS class only, while
 * leaving GtmAgentProxyController ungranted for those permission sets,
 * keeps chat()/chatOnReadout()/chatOnApp() unreachable from the Content
 * Manager app exactly as decision F4 requires, even though this class calls
 * straight into GtmAgentProxyController.runLoop() to reuse the one shared
 * tool-use loop. See docs/architecture/industry-variants-agentforce-draft.md §4.
 */
public with sharing class GtmAgentContentDraftController {

    /**
     * @param offeringKey   the section's Offering_Key__c
     * @param templateType  the section's Template_Type__c
     * @param sectionKey    the VARIANT section's own Section_Key__c -- constructor
     *                      state for GtmContentDraftAgentSurface, never a tool argument
     * @param userMessage   the editor's latest chat message
     * @param historyJson   JSON-serialised conversation history from prior turns
     * @return              JSON: { text, historyJson, changes } where
     *                      changes.proposedFields (if present) is a
     *                      fieldKey -> proposed value map for the LWC to
     *                      land into the field editor as drafts
     */
    @AuraEnabled
    public static String chat(String offeringKey, String templateType, String sectionKey,
                              String userMessage, String historyJson) {
        if (String.isBlank(offeringKey) || String.isBlank(templateType) || String.isBlank(sectionKey)) {
            throw new AuraHandledException('offeringKey, templateType and sectionKey are required.');
        }
        return GtmAgentProxyController.runLoop(
            new GtmContentDraftAgentSurface(offeringKey, templateType, sectionKey),
            userMessage, historyJson);
    }
}
