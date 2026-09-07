/**
 * Who is looking at a public page.
 *
 * This exists as its own class because Apex access is granted per class, not
 * per method. The guest user needs exactly one answer -- "am I a rep?" -- and
 * granting that through GtmSavedConfigurationController would have handed the
 * public saveConfiguration, deleteConfiguration and searchContacts along with
 * it. One question, one class, nothing else reachable.
 */
public with sharing class GtmViewerContext {

    /**
     * Whether the viewer is a rep, and so may see rep-only UI: Gus, the saved
     * links bar, the wizard.
     *
     * The answer is computed rather than implied. The previous version
     * returned true unconditionally and relied on the guest being unable to
     * call it at all: the wire threw, and the caller read that failure as
     * "not a rep". That works right up until the site has to tell a rep from
     * a prospect, because then the only signal is an exception -- and an
     * exception is indistinguishable from any other reason a call can fail.
     * A rep on the public site was shown the prospect's view.
     *
     * Guests are the site's own guest user. A prospect who has somehow
     * authenticated is a portal user, not a rep. Only an internal Salesforce
     * user -- someone with a seat in this org -- is a rep.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isRep() {
        return UserInfo.getUserType() == 'Standard';
    }
}
