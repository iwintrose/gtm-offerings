/**
 * Weekly analytics digest (issue #140, v3). One plain-text email per rep,
 * summarizing their own trailing-7-day GtmAnalyticsController numbers --
 * the same numbers the Analytics tab shows them, computed via
 * GtmAnalyticsController.summaryForOwner so this never drifts into a
 * second, independent definition of the metrics (see that method's
 * header, issue #140).
 *
 * NOT scheduled by this class or by any deploy step. Activating it is a
 * standing, org-mutating decision (a real recurring job that emails real
 * users) left to a human -- see TASK_SCOPE.md §5 for the one-line
 * System.schedule(...) call to run when ready.
 *
 * Recipients: every active, non-guest User who owns at least one
 * GTM_Saved_Configuration__c -- reaches every working rep without
 * depending on permission-set assignment introspection. A rep with zero
 * activity in the window is skipped entirely (no all-zero email), to keep
 * this useful rather than noisy for an inactive rep.
 *
 * Best-effort per rep: one rep's email failure is caught and logged, and
 * must never stop the rest of the batch from being emailed -- same
 * reasoning as the best-effort notification paths in GtmReadoutController.
 */
public with sharing class GtmAnalyticsDigestJob implements Schedulable {

    public void execute(SchedulableContext ctx) {
        Date rangeEnd = Date.today();
        Date rangeStart = rangeEnd.addDays(-6); // trailing 7 days, inclusive

        for (Id ownerId : activeLinkOwningUserIds()) {
            sendDigestFor(ownerId, rangeStart, rangeEnd);
        }
    }

    /**
     * Distinct, active, non-guest owners of at least one engagement link.
     * OwnerId is polymorphic (User or Group), so it cannot be filtered by
     * traversing Owner.IsActive/Owner.UserType directly in one query --
     * that resolves against the generic Name interface, not User, and
     * fails to compile. Two queries instead: distinct owner ids, then
     * which of those are actually active, non-guest Users (a Group-owned
     * link, e.g. a queue, is silently excluded rather than erroring).
     */
    private Set<Id> activeLinkOwningUserIds() {
        Set<Id> ownerIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT OwnerId
            FROM GTM_Saved_Configuration__c
            GROUP BY OwnerId
        ]) {
            ownerIds.add((Id) ar.get('OwnerId'));
        }
        if (ownerIds.isEmpty()) {
            return ownerIds;
        }
        Set<Id> activeUserIds = new Set<Id>();
        for (User u : [
            SELECT Id FROM User
            WHERE Id IN :ownerIds AND IsActive = true AND UserType != 'Guest'
        ]) {
            activeUserIds.add(u.Id);
        }
        return activeUserIds;
    }

    private void sendDigestFor(Id ownerId, Date rangeStart, Date rangeEnd) {
        try {
            GtmAnalyticsController.AnalyticsSummary summary =
                GtmAnalyticsController.summaryForOwner(ownerId, rangeStart, rangeEnd, null);

            // Skip a rep with no activity this week rather than sending an
            // all-zero digest every Monday forever.
            if (summary.linksCreated == 0 && summary.assessmentsSubmitted == 0
                    && summary.readoutsPublished == 0) {
                return;
            }

            List<User> recipients = [SELECT Id, Email, FirstName FROM User WHERE Id = :ownerId LIMIT 1];
            if (recipients.isEmpty() || String.isBlank(recipients[0].Email)) {
                return;
            }
            User rep = recipients[0];

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ rep.Email });
            mail.setSaveAsActivity(false);
            mail.setSubject('Your weekly GTM Offerings digest');
            mail.setPlainTextBody(digestBody(rep, summary, rangeStart, rangeEnd));

            if (!Test.isRunningTest()) {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Could not send the weekly analytics digest to owner ' + ownerId +
                ': ' + e.getTypeName() + ' -- ' + e.getMessage() +
                '. The rest of the batch is unaffected.'
            );
        }
    }

    private String digestBody(
        User rep, GtmAnalyticsController.AnalyticsSummary summary, Date rangeStart, Date rangeEnd
    ) {
        return 'Hi ' + rep.FirstName + ',\n\n' +
            'Here is your GTM Offerings activity for ' + rangeStart.format() + ' - ' + rangeEnd.format() + ':\n\n' +
            'Links created: ' + summary.linksCreated + '\n' +
            'Assessments submitted: ' + summary.assessmentsSubmitted + '\n' +
            'Readouts published: ' + summary.readoutsPublished + '\n' +
            (summary.avgDaysToPublish != null && summary.avgDaysToPublish > 0
                ? 'Avg. time to publish: ' + summary.avgDaysToPublish + ' day(s)\n'
                : '') +
            '\nOpen the Analytics tab in the GTM Offerings app for the full picture.\n\n' +
            'Best regards,\n' +
            'Publicis Sapient';
    }
}
