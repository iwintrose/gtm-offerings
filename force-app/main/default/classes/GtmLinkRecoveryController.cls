public without sharing class GtmLinkRecoveryController {

    private static final Pattern EMAIL_PATTERN = Pattern.compile(
        '^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$'
    );

    @AuraEnabled
    public static String recoverLink(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email is required.');
        }
        Matcher m = EMAIL_PATTERN.matcher(email.trim());
        if (!m.matches()) {
            throw new AuraHandledException('Invalid email address.');
        }

        List<GTM_Saved_Configuration__c> configs = [
            SELECT Generated_URL__c
            FROM GTM_Saved_Configuration__c
            WHERE Contact__r.Email = :email.trim()
            AND Active__c = true
            LIMIT 1
        ];

        if (!configs.isEmpty()) {
            try {
                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setSaveAsActivity(false);
                msg.setToAddresses(new List<String>{ email.trim() });
                msg.setSubject('Your engagement link');
                msg.setPlainTextBody(
                    'Here is your engagement link: ' + configs[0].Generated_URL__c
                );
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
            } catch (EmailException e) {
                System.debug(LoggingLevel.ERROR, 'GtmLinkRecoveryController email error: ' + e.getMessage());
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, 'GtmLinkRecoveryController DML error: ' + e.getMessage());
            }
        }

        return 'OK';
    }
}
