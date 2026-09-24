/**
 * Shared Task + Custom Notification ("bell") fire/close primitives for the
 * seven ADR-0010 lifecycle wiring points (Unit 3b). Every lifecycle call
 * site (GtmReadoutController, GtmReadoutApprovalHandler,
 * GtmAssessmentRequestController) routes Task DML and
 * Messaging.sendCustomNotification calls through here instead of
 * hand-rolling its own SOQL/DML, so the Task-tracking contract lives in
 * exactly one place.
 *
 * Task-tracking mechanism (docs/agent-artifacts/task-scope-
 * notifications-unit-3b-lifecycle-wiring.md §1b): no new Id-holding field
 * on GTM_Readout__c/GTM_Assessment_Request__c. Instead, Task.WhatId points
 * back at the parent record (both objects have enableActivities=true) and a
 * per-stage constant Subject string is the exact-match key a later
 * lifecycle moment uses to find and close the Task it created earlier.
 *
 * Subject is therefore a LOAD-BEARING EXACT-MATCH KEY, not display text.
 * Fire-side code must never interpolate record-specific text (readout
 * name, requester name, company, etc.) into Subject -- that content
 * belongs in Description only. Doing so would make closeOpenTasks's
 * `WHERE Subject = :subject` query silently stop finding the Task it is
 * supposed to close.
 *
 * `with sharing`: this is called from both `with sharing` classes
 * (GtmReadoutController) and `without sharing` classes
 * (GtmReadoutApprovalHandler, GtmAssessmentRequestController) -- it does
 * not itself widen or narrow the caller's access, since Task/
 * CustomNotificationType visibility rides the running user's standard
 * Activity access either way (no row-level sharing rule on either object
 * relevant here).
 *
 * Bulk safety: fireTask/closeOpenTasks are single-record conveniences for
 * the RPC-style call sites (one readout/request per LWC or guest-submission
 * call). Any caller that can process more than one record in the same
 * transaction -- concretely, GtmReadoutApprovalHandler.
 * fireApprovalNotifications, since stampApproval is a trigger handler and
 * "an approval can be taken on several readouts at once from a list view"
 * (this class's own nextVersionNumbers() docstring, which already follows
 * this discipline) -- MUST use fireTasksBulk/closeOpenTasksBulk instead of
 * looping the single-record methods. Looping fireTask/closeOpenTasks issues
 * one DML/SOQL per record and will blow the 100-query/150-DML governor
 * limits once enough records are approved in one operation; the *Bulk
 * overloads issue exactly one aggregate SOQL and one DML per call
 * regardless of batch size. fireBell's CustomNotificationType lookup is
 * cached per transaction either way, so looping fireBell itself is fine.
 */
public with sharing class GtmLifecycleNotificationService {

    // Subject constants -- exact-match keys, see class header. Never
    // interpolate record-specific text into these.
    public static final String SUBJECT_APPROVE_READOUT   = 'Approve this readout';
    public static final String SUBJECT_READOUT_APPROVED  = 'Readout approved -- ready to publish';
    public static final String SUBJECT_RETURNED_TO_DRAFT = 'Readout returned to draft -- revise and resubmit';
    public static final String SUBJECT_NEW_REQUEST       = 'New assessment request needs review';
    // Published-stage subject reserved for the fire side (Bell + Task mode).
    // Its close trigger is out of scope for this unit -- see
    // Auto_Close_Published_Tasks__c in the scope doc's 1c-RESOLVED section.
    public static final String SUBJECT_READOUT_PUBLISHED = 'Readout published';

    private static final String NOTIFICATION_TYPE_NAME = 'GTM_Notification';

    // Cached for the life of the transaction so a caller firing a bell for
    // many records in a loop (e.g. GtmReadoutApprovalHandler.
    // fireApprovalNotifications across several approved readouts) issues this
    // lookup once, not once per call. Static state is scoped to one execution
    // context, so this never leaks across transactions.
    private static Id cachedNotificationTypeId;
    private static Boolean notificationTypeLookupFailed = false;

    /** One Task-to-create request, for the bulk overload of fireTask. */
    public class TaskRequest {
        public Id whatId;
        public Id ownerId;
        public String subject;
        public String description;

        public TaskRequest(Id whatId, Id ownerId, String subject, String description) {
            this.whatId = whatId;
            this.ownerId = ownerId;
            this.subject = subject;
            this.description = description;
        }
    }

    /**
     * Creates one open Task against whatId, assigned to ownerId, with the
     * given exact-match Subject and free-text Description.
     *
     * Thin wrapper around fireTasksBulk for the (common) single-Task call
     * sites -- see that method for the bulk-safety contract. No-ops
     * silently (does not insert, does not throw) when whatId or ownerId is
     * null -- every call site already gates on both being non-null before
     * calling in, but this is a second line of defense since a bad Task
     * insert must never be allowed to bubble up and fail the lifecycle
     * transition that triggered it.
     */
    public static void fireTask(Id whatId, Id ownerId, String subject, String description) {
        fireTasksBulk(new List<TaskRequest> { new TaskRequest(whatId, ownerId, subject, description) });
    }

    /**
     * Bulk-safe Task creation: builds every requested Task in memory first,
     * then issues exactly ONE Database.insert for the whole batch --
     * regardless of how many readouts/requests are involved. Callers with
     * more than one Task to fire in the same transaction (e.g.
     * GtmReadoutApprovalHandler.fireApprovalNotifications across several
     * approved readouts from a list-view bulk approval) must call this
     * once with the full list rather than looping calls to fireTask, or the
     * DML-per-record cost defeats the point of this method existing.
     *
     * Requests with a null whatId/ownerId or blank subject are skipped
     * (not inserted, never thrown) -- same no-op contract as fireTask.
     * Database.insert(..., false) means one bad record (e.g. an ownerId
     * without insert access) never fails the rest of the batch.
     */
    public static void fireTasksBulk(List<TaskRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        List<Task> tasks = new List<Task>();
        for (TaskRequest req : requests) {
            if (req.whatId == null || req.ownerId == null || String.isBlank(req.subject)) {
                continue;
            }
            tasks.add(new Task(
                WhatId       = req.whatId,
                OwnerId      = req.ownerId,
                Subject      = req.subject,
                Description  = req.description,
                Status       = 'Not Started',
                ActivityDate = Date.today()
            ));
        }
        if (tasks.isEmpty()) {
            return;
        }
        try {
            Database.insert(tasks, false);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'GtmLifecycleNotificationService.fireTasksBulk could not create ' +
                tasks.size() + ' Task(s): ' + e.getTypeName() + ' at line ' + e.getLineNumber() +
                ' -- ' + e.getMessage()
            );
        }
    }

    /**
     * Closes every open (Status != 'Completed') Task whose WhatId and
     * Subject exactly match -- the close-side half of the WhatId+Subject
     * tracking contract described in the class header.
     *
     * Thin wrapper around closeOpenTasksBulk for the (common) single-record
     * call sites -- see that method for the bulk-safety contract. A
     * no-match is a normal, silent outcome (e.g. the setting that would
     * have fired the Task was off, or it was already closed) -- not an
     * error condition.
     */
    public static void closeOpenTasks(Id whatId, String subject) {
        if (whatId == null) {
            return;
        }
        closeOpenTasksBulk(new Set<Id> { whatId }, subject);
    }

    /**
     * Bulk-safe close: one aggregate SOQL across every whatId sharing the
     * same exact-match Subject, then one Database.update for every open
     * Task found -- regardless of how many records are in whatIds. Callers
     * closing the same Subject across several records in one transaction
     * (e.g. GtmReadoutApprovalHandler.fireApprovalNotifications closing the
     * approver Task for every readout approved in one list-view bulk
     * operation) must call this once with the full set rather than looping
     * calls to closeOpenTasks, or the SOQL-per-record cost defeats the
     * point of this method existing -- this is the same discipline this
     * class's own nextVersionNumbers() docstring documents for exactly the
     * same "several readouts at once from a list view" scenario.
     *
     * Matches and closes every open Task found per whatId, not just the
     * first, so a rare duplicate-fire never leaves a stray open Task
     * behind.
     */
    public static void closeOpenTasksBulk(Set<Id> whatIds, String subject) {
        if (whatIds == null || whatIds.isEmpty() || String.isBlank(subject)) {
            return;
        }
        List<Task> openTasks = [
            SELECT Id, Status
            FROM Task
            WHERE WhatId IN :whatIds AND Subject = :subject AND Status != 'Completed'
        ];
        if (openTasks.isEmpty()) {
            return;
        }
        for (Task t : openTasks) {
            t.Status = 'Completed';
        }
        try {
            Database.update(openTasks, false);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'GtmLifecycleNotificationService.closeOpenTasksBulk could not close Task(s) for ' +
                whatIds.size() + ' record(s)/' + subject + ': ' + e.getTypeName() +
                ' at line ' + e.getLineNumber() + ' -- ' + e.getMessage()
            );
        }
    }

    /**
     * Fires a bell (Custom Notification) against the GTM_Notification
     * CustomNotificationType (force-app/main/default/notificationtypes/
     * GTM_Notification.notiftype-meta.xml) to a single recipient.
     * Best-effort: Messaging.sendCustomNotification failures (e.g. no
     * CustomNotificationType row resolvable in this context, or the
     * recipient has notifications disabled) are caught and logged, never
     * thrown -- a lifecycle transition must never fail because a bell
     * could not be delivered.
     *
     * The CustomNotificationType Id is resolved once per transaction and
     * cached (see resolveNotificationTypeId) -- calling this in a loop
     * across several records (e.g. one bell per readout in a bulk approval)
     * costs one SOQL total, not one per call.
     */
    public static void fireBell(Id recipientId, Id targetId, String title, String body) {
        if (recipientId == null) {
            return;
        }
        Id notificationTypeId = resolveNotificationTypeId();
        if (notificationTypeId == null) {
            return;
        }
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(notificationTypeId);
            if (targetId != null) {
                notification.setTargetId(targetId);
            }
            notification.send(new Set<String> { recipientId });
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'GtmLifecycleNotificationService.fireBell could not send notification to ' +
                recipientId + ': ' + e.getTypeName() + ' at line ' + e.getLineNumber() +
                ' -- ' + e.getMessage()
            );
        }
    }

    /**
     * Resolves and caches the GTM_Notification CustomNotificationType Id
     * for the life of this execution context. A failed lookup (e.g. the
     * type row does not exist in this org) is also cached as "failed" so a
     * bad org state does not re-issue the same failing query on every
     * fireBell call in the same transaction.
     */
    private static Id resolveNotificationTypeId() {
        if (cachedNotificationTypeId != null || notificationTypeLookupFailed) {
            return cachedNotificationTypeId;
        }
        try {
            CustomNotificationType notifType = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_TYPE_NAME
                LIMIT 1
            ];
            cachedNotificationTypeId = notifType.Id;
        } catch (Exception e) {
            notificationTypeLookupFailed = true;
            System.debug(
                LoggingLevel.WARN,
                'GtmLifecycleNotificationService could not resolve the ' + NOTIFICATION_TYPE_NAME +
                ' CustomNotificationType: ' + e.getTypeName() + ' at line ' + e.getLineNumber() +
                ' -- ' + e.getMessage()
            );
        }
        return cachedNotificationTypeId;
    }
}
