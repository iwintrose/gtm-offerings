/**
 * Apex backing for maStageActions LWC and the MA_Config_Send_To_Client flow.
 *
 * Manages the Presentation_Stage__c lifecycle on MA_Saved_Configuration__c
 * and sends the proposal email to the client when the rep triggers "Send".
 *
 * Runs without sharing — config managers (internal users) need to read/write
 * client config records regardless of ownership. The entry points are narrow
 * and validate every input before touching data.
 */
public without sharing class MaStageActionsController {

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
        if (!isValidId(configId, 'MA_Saved_Configuration__c')) {
            return new StageContext();
        }

        MA_Saved_Configuration__c cfg = [
            SELECT Presentation_Stage__c, Generated_URL__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :Id.valueOf(configId)
            LIMIT 1
        ];

        StageContext ctx       = new StageContext();
        ctx.stage              = cfg.Presentation_Stage__c;
        ctx.sharedUrl          = cfg.Generated_URL__c;

        List<MA_Assessment_Request__c> requests = [
            SELECT Requester_Name__c, Requester_Email__c, Company__c
            FROM MA_Assessment_Request__c
            WHERE Saved_Configuration__c = :Id.valueOf(configId)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!requests.isEmpty()) {
            ctx.assessmentId      = requests[0].Id;
            ctx.requesterName     = requests[0].Requester_Name__c;
            ctx.requesterEmail    = requests[0].Requester_Email__c;
            ctx.requesterCompany  = requests[0].Company__c;
        }
        return ctx;
    }

    /**
     * Advances the stage and, when transitioning to Sent, sends the proposal
     * email to the requester.
     */
    @AuraEnabled
    public static void advanceStage(String configId, String newStage) {
        if (!isValidId(configId, 'MA_Saved_Configuration__c')) {
            throw new AuraHandledException('Invalid configuration ID.');
        }
        if (!VALID_STAGES.contains(newStage)) {
            throw new AuraHandledException('Invalid stage value: ' + newStage);
        }

        MA_Saved_Configuration__c cfg = [
            SELECT Id, Presentation_Stage__c, Generated_URL__c
            FROM MA_Saved_Configuration__c
            WHERE Id = :Id.valueOf(configId)
            FOR UPDATE
        ];

        cfg.Presentation_Stage__c = newStage;
        update cfg;

        if ('Sent'.equals(newStage) && String.isNotBlank(cfg.Generated_URL__c)) {
            sendProposalEmailIfPresent(Id.valueOf(configId), cfg.Generated_URL__c);
        }
    }

    // ── Flow invocable (fallback / scheduled re-sends) ────────────────────────

    public class SendEmailInput {
        @InvocableVariable(required=true label='Config Id')
        public String configId;
        @InvocableVariable(required=true label='Shared URL')
        public String sharedUrl;
    }

    @InvocableMethod(label='Send Proposal Email to Client' category='GTM Offerings')
    public static void sendProposalEmails(List<SendEmailInput> inputs) {
        for (SendEmailInput inp : inputs) {
            if (isValidId(inp.configId, 'MA_Saved_Configuration__c')
                    && String.isNotBlank(inp.sharedUrl)) {
                sendProposalEmailIfPresent(Id.valueOf(inp.configId), inp.sharedUrl);
            }
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private static void sendProposalEmailIfPresent(Id configId, String sharedUrl) {
        List<MA_Assessment_Request__c> requests = [
            SELECT Requester_Name__c, Requester_Email__c, Company__c
            FROM MA_Assessment_Request__c
            WHERE Saved_Configuration__c = :configId
                AND Requester_Email__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (requests.isEmpty()) return;

        MA_Assessment_Request__c req = requests[0];
        String firstName = firstWord(req.Requester_Name__c);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ req.Requester_Email__c });
        msg.setSubject('Your Migration Accelerator proposal is ready');
        msg.setHtmlBody(buildEmailHtml(firstName, req.Company__c, sharedUrl));
        msg.setPlainTextBody(buildEmailText(firstName, req.Company__c, sharedUrl));
        msg.setSaveAsActivity(false);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        } catch (Exception e) {
            // Log but do not surface to the rep — the stage is already updated
            System.debug('MaStageActionsController.sendProposalEmailIfPresent: ' + e.getMessage());
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

    private static Boolean isValidId(String s, String objectApiName) {
        if (String.isBlank(s)) return false;
        try {
            Id i = Id.valueOf(s);
            return String.valueOf(i.getSobjectType()) == objectApiName;
        } catch (Exception e) {
            return false;
        }
    }
}
