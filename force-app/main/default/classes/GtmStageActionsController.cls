/**
 * Apex backing for maStageActions LWC and the GTM_Config_Send_To_Client flow.
 *
 * Manages the Presentation_Stage__c lifecycle on GTM_Saved_Configuration__c.
 * advanceStage() only moves the stage; the proposal email to the client is
 * sent exclusively by the org's "GTM Config — Send To Client" record-triggered
 * flow, which fires on that same update and calls the sendProposalEmails
 * invocable below. advanceStage() deliberately does NOT call the send path
 * itself -- doing so alongside the flow would email the client twice for a
 * single Send action. Keep this a single trigger point: if the send ever
 * needs to move back into Apex, deactivate/remove the flow's action call in
 * the same change rather than having both fire.
 *
 * Runs without sharing — config managers (internal users) need to read/write
 * client config records regardless of ownership. The entry points are narrow
 * and validate every input before touching data.
 *
 * GTM_Assessment_Request__c.Saved_Configuration__c is queried dynamically,
 * not through typed SOQL -- a static reference to this exact field is what
 * blocks Salesforce from letting it be deleted and recreated, which is the
 * only way to repoint an existing Lookup's referenceTo.
 */
public without sharing class GtmStageActionsController {

    static final Set<String> VALID_STAGES = new Set<String>{
        'Assessment', 'In_Review', 'Draft', 'Sent'
    };

    // ── Return types ──────────────────────────────────────────────────────────

    public class StageContext {
        @AuraEnabled public String  stage;
        @AuraEnabled public String  assessmentId;
        @AuraEnabled public String  requesterName;
        @AuraEnabled public String  requesterEmail;
        @AuraEnabled public String  requesterCompany;
        @AuraEnabled public String  sharedUrl;
    }

    // ── LWC entry points ──────────────────────────────────────────────────────

    /**
     * Returns the current stage plus the latest assessment request linked to
     * this config. Called by maStageActions on load and after each advance.
     */
    @AuraEnabled(cacheable=false)
    public static StageContext getStageContext(String configId) {
        Id resolvedId = GtmLegacyConfigId.resolve(configId);
        if (resolvedId == null) {
            return new StageContext();
        }

        GTM_Saved_Configuration__c cfg = [
            SELECT Presentation_Stage__c, Generated_URL__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            LIMIT 1
        ];

        StageContext ctx       = new StageContext();
        ctx.stage              = cfg.Presentation_Stage__c;
        ctx.sharedUrl          = cfg.Generated_URL__c;

        List<SObject> requests = Database.query(
            'SELECT Id, Requester_Name__c, Requester_Email__c, Company__c ' +
            'FROM GTM_Assessment_Request__c ' +
            'WHERE Saved_Configuration__c = :resolvedId ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT 1'
        );
        if (!requests.isEmpty()) {
            ctx.assessmentId      = (Id) requests[0].get('Id');
            ctx.requesterName     = (String) requests[0].get('Requester_Name__c');
            ctx.requesterEmail    = (String) requests[0].get('Requester_Email__c');
            ctx.requesterCompany  = (String) requests[0].get('Company__c');
        }
        return ctx;
    }

    /**
     * Advances the stage. Sending the proposal email on a transition to Sent
     * is NOT done here -- see the class header. The
     * GTM_Config_Send_To_Client flow reacts to this same `update` and owns
     * the send.
     */
    @AuraEnabled
    public static void advanceStage(String configId, String newStage) {
        Id resolvedId = GtmLegacyConfigId.resolve(configId);
        if (resolvedId == null) {
            throw new AuraHandledException('Invalid configuration ID.');
        }
        if (!VALID_STAGES.contains(newStage)) {
            throw new AuraHandledException('Invalid stage value: ' + newStage);
        }

        GTM_Saved_Configuration__c cfg = [
            SELECT Id, Presentation_Stage__c, Generated_URL__c
            FROM GTM_Saved_Configuration__c
            WHERE Id = :resolvedId
            FOR UPDATE
        ];

        cfg.Presentation_Stage__c = newStage;
        update cfg;
    }

    // ── Flow invocable (sole trigger point for the proposal email) ────────────
    // Called by the GTM_Config_Send_To_Client record-triggered flow only.
    // Do not also call this (or sendProposalEmailIfPresent) directly from
    // advanceStage() or anywhere else that flow already covers -- that is
    // exactly the double-send bug this class' header warns about.

    public class SendEmailInput {
        @InvocableVariable(required=true label='Config Id')
        public String configId;
        @InvocableVariable(required=true label='Shared URL')
        public String sharedUrl;
    }

    @InvocableMethod(label='Send Proposal Email to Client' category='GTM Offerings')
    public static void sendProposalEmails(List<SendEmailInput> inputs) {
        for (SendEmailInput inp : inputs) {
            Id resolvedId = GtmLegacyConfigId.resolve(inp.configId);
            if (resolvedId != null && String.isNotBlank(inp.sharedUrl)) {
                sendProposalEmailIfPresent(resolvedId, inp.sharedUrl);
            }
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private static void sendProposalEmailIfPresent(Id configId, String sharedUrl) {
        List<SObject> requests = Database.query(
            'SELECT Requester_Name__c, Requester_Email__c, Company__c ' +
            'FROM GTM_Assessment_Request__c ' +
            'WHERE Saved_Configuration__c = :configId ' +
            '    AND Requester_Email__c != null ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT 1'
        );
        if (requests.isEmpty()) return;

        SObject req = requests[0];
        String requesterName  = (String) req.get('Requester_Name__c');
        String requesterEmail = (String) req.get('Requester_Email__c');
        String company        = (String) req.get('Company__c');
        String firstName = firstWord(requesterName);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ requesterEmail });
        msg.setSubject('Your Migration Accelerator proposal is ready');
        msg.setHtmlBody(buildEmailHtml(firstName, company, sharedUrl));
        msg.setPlainTextBody(buildEmailText(firstName, company, sharedUrl));
        msg.setSaveAsActivity(false);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        } catch (Exception e) {
            // Log but do not surface to the rep — the stage is already updated
            System.debug('GtmStageActionsController.sendProposalEmailIfPresent: ' + e.getMessage());
        }
    }

    private static String firstWord(String fullName) {
        if (String.isBlank(fullName)) return 'there';
        String trimmed = fullName.trim();
        Integer space = trimmed.indexOf(' ');
        return space > 0 ? trimmed.substring(0, space) : trimmed;
    }

    private static String buildEmailHtml(String firstName, String company, String url) {
        String co = String.isNotBlank(company) ? ' for ' + company : '';
        return '<p>Hi ' + escHtml(firstName) + ',</p>'
            + '<p>Your Migration Accelerator proposal' + escHtml(co) + ' is ready. '
            + 'You can view it at any time using the link below — no login required.</p>'
            + '<p><a href="' + escHtml(url) + '" style="background:#0070d2;color:#fff;'
            + 'padding:10px 20px;border-radius:4px;text-decoration:none;display:inline-block;">'
            + 'View your proposal &rarr;</a></p>'
            + '<p style="color:#6b7280;font-size:13px;">If the button doesn\'t open, '
            + 'copy this URL into your browser:<br>' + escHtml(url) + '</p>'
            + '<p>— The Publicis Sapient team</p>';
    }

    private static String buildEmailText(String firstName, String company, String url) {
        String co = String.isNotBlank(company) ? ' for ' + company : '';
        return 'Hi ' + firstName + ',\n\n'
            + 'Your Migration Accelerator proposal' + co + ' is ready.\n\n'
            + 'View it here: ' + url + '\n\n'
            + '— The Publicis Sapient team';
    }

    private static String escHtml(String s) {
        if (s == null) return '';
        return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
                .replace('"', '&quot;');
    }
}
