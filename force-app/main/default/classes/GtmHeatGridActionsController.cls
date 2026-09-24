/**
 * "Next best action" DML for the heat grid (issue
 * overview-bd-heat-redesign-2-heat-grid). Deliberately separate from
 * `GtmLinkStageService`, which documents itself as read-only/no-DML (its
 * `getHeatGrid()` aggregation this class's caller reads from) -- this class
 * exists so that invariant stays true and this one stays small and obvious:
 * one Task insert, nothing else.
 *
 * "Call now" needs no Apex -- it is a client-side Log a Call quick-action
 * navigation (see c/gtmHeatGrid). Only "Follow up" needs a server call.
 *
 * Grepped first for an existing Task-creation helper before adding this one:
 * `GtmReadoutController.fileFollowUpTask` and
 * `GtmAssessmentRequestController`'s Task inserts are both scoped to
 * Assessment Requests (`WhatId` = the request), not Opportunities, so
 * neither fits a heat-grid row's "Follow up" action, which is explicitly
 * scoped to the row's Opportunity (`WhatId`). Not a duplicate of either.
 *
 * Contract: docs/architecture/overview-bd-heat-redesign-2-heat-grid.md.
 */
public with sharing class GtmHeatGridActionsController {

    @AuraEnabled
    public static Id createFollowUpTask(Id opportunityId, String accountName) {
        try {
            if (opportunityId == null) {
                throw new IllegalArgumentException('An Opportunity is required to create a follow-up task.');
            }
            Task t = new Task(
                Subject      = 'Follow up: ' + (String.isNotBlank(accountName) ? accountName : 'prospect')
                    + ' started an assessment',
                WhatId       = opportunityId,
                OwnerId      = UserInfo.getUserId(),
                ActivityDate = Date.today().addDays(1),
                Status       = 'Not Started',
                Priority     = 'Normal'
            );
            insert t;
            return t.Id;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }
}
