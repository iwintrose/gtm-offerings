/**
 * Feedback on an offering: from the people who sell it, to the people who
 * write it, and back again.
 *
 * The offerings list on the GTM Offerings overview was a set of links to story
 * pages. A BD person could read what an offering says and had nowhere to say
 * "this claim doesn't survive a CFO", so the only route back to the writer was
 * a conversation nobody recorded. This is that route, with the loop closed: a
 * reply and a status the person who raised it can see.
 *
 * Both apps read the same records. The overview shows an offering's feedback to
 * the person who left it; the Content Manager shows the queue to whoever is
 * writing. Nothing here is guest-facing.
 */
public with sharing class GtmFeedbackController {

    private static final Integer MAX_BODY = 4000;

    public class FeedbackItem {
        @AuraEnabled public Id       recordId    { get; set; }
        @AuraEnabled public String   name        { get; set; }
        @AuraEnabled public String   offeringKey { get; set; }
        @AuraEnabled public String   templateType{ get; set; }
        @AuraEnabled public String   body        { get; set; }
        @AuraEnabled public String   status      { get; set; }
        @AuraEnabled public String   response    { get; set; }
        @AuraEnabled public String   submittedBy { get; set; }
        @AuraEnabled public Boolean  isMine      { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime answeredAt  { get; set; }
    }

    private static FeedbackItem toItem(GTM_Offering_Feedback__c f) {
        FeedbackItem i = new FeedbackItem();
        i.recordId     = f.Id;
        i.name         = f.Name;
        i.offeringKey  = f.Offering_Key__c;
        i.templateType = f.Template_Type__c;
        i.body         = f.Feedback__c;
        i.status       = f.Status__c;
        i.response     = f.Response__c;
        i.submittedBy  = f.Submitted_By__r != null ? f.Submitted_By__r.Name : null;
        i.isMine       = f.Submitted_By__c == UserInfo.getUserId();
        i.createdDate  = f.CreatedDate;
        i.answeredAt   = f.Answered_At__c;
        return i;
    }

    private static final String FIELDS =
        'Id, Name, Offering_Key__c, Template_Type__c, Feedback__c, Status__c, ' +
        'Response__c, Submitted_By__c, Submitted_By__r.Name, CreatedDate, Answered_At__c';

    /**
     * Everything raised about one offering, newest first.
     *
     * Not filtered to the caller's own: a BD person about to raise "the proof
     * number is stale" is better served by seeing that someone raised it last
     * week and it is being worked on.
     */
    @AuraEnabled(cacheable=false)
    public static List<FeedbackItem> getFeedbackFor(String offeringKey) {
        List<FeedbackItem> out = new List<FeedbackItem>();
        if (String.isBlank(offeringKey)) return out;
        for (GTM_Offering_Feedback__c f : Database.query(
            'SELECT ' + FIELDS + ' FROM GTM_Offering_Feedback__c ' +
            'WHERE Offering_Key__c = :offeringKey ORDER BY CreatedDate DESC LIMIT 100')) {
            out.add(toItem(f));
        }
        return out;
    }

    /**
     * The writer's queue: everything still open, across every offering.
     *
     * Ordered so the ones waiting on the writer come before the ones waiting on
     * whoever raised them — a queue that mixes the two is a queue where the
     * question you asked last week looks like work you have not started.
     */
    @AuraEnabled(cacheable=false)
    public static List<FeedbackItem> getOpenFeedback() {
        List<FeedbackItem> out = new List<FeedbackItem>();
        for (GTM_Offering_Feedback__c f : Database.query(
            'SELECT ' + FIELDS + ' FROM GTM_Offering_Feedback__c ' +
            'WHERE Status__c IN (\'New\', \'In Progress\', \'Needs More Info\') ' +
            'ORDER BY Status__c ASC, CreatedDate ASC LIMIT 200')) {
            out.add(toItem(f));
        }
        return out;
    }

    /** How many are waiting, for the badge on the Content Manager's home. */
    @AuraEnabled(cacheable=false)
    public static Integer countOpenFeedback() {
        return [
            SELECT COUNT() FROM GTM_Offering_Feedback__c
            WHERE Status__c IN ('New', 'In Progress', 'Needs More Info')
        ];
    }

    /** Raise a note against an offering, optionally against one of its pages. */
    @AuraEnabled(cacheable=false)
    public static FeedbackItem submitFeedback(String offeringKey, String templateType, String body) {
        if (String.isBlank(offeringKey)) {
            throw new AuraHandledException('Say which offering this is about.');
        }
        if (String.isBlank(body)) {
            throw new AuraHandledException('Feedback needs some words in it.');
        }
        GTM_Offering_Feedback__c f = new GTM_Offering_Feedback__c(
            Offering_Key__c  = offeringKey.trim().left(80),
            Template_Type__c = String.isBlank(templateType) ? null : templateType.trim().left(40),
            Feedback__c      = body.trim().left(MAX_BODY),
            Status__c        = 'New',
            Submitted_By__c  = UserInfo.getUserId()
        );
        insert f;
        return getOne(f.Id);
    }

    /**
     * The writer's reply, and where it now stands.
     *
     * Answered_At__c is stamped whenever a reply is written, which is what
     * lets the two apps tell "waiting on the writer" from "waiting on the
     * person who raised it" without either of them storing a second flag that
     * could disagree.
     */
    @AuraEnabled(cacheable=false)
    public static FeedbackItem respond(String recordId, String status, String response) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No feedback record given.');
        }
        GTM_Offering_Feedback__c f = new GTM_Offering_Feedback__c(Id = (Id) recordId);
        if (String.isNotBlank(status))   f.Status__c = status;
        if (String.isNotBlank(response)) {
            f.Response__c   = response.trim().left(MAX_BODY);
            f.Answered_At__c = System.now();
        }
        try {
            update f;
        } catch (Exception e) {
            throw new AuraHandledException('The reply could not be saved: ' + e.getMessage());
        }
        return getOne(f.Id);
    }

    private static FeedbackItem getOne(Id recordId) {
        List<GTM_Offering_Feedback__c> rows = Database.query(
            'SELECT ' + FIELDS + ' FROM GTM_Offering_Feedback__c WHERE Id = :recordId LIMIT 1');
        return rows.isEmpty() ? null : toItem(rows[0]);
    }
}
