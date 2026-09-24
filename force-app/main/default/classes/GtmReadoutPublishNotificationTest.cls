/**
 * Covers Unit 4 of the D7-EXT backlog item: the publish-time prospect email
 * notification GtmReadoutController.publishReadout fires on the existing
 * Approved -> Published transition. Kept as its own class, separate from
 * GtmReadoutControllerTest, so the notification-specific fixtures (a
 * GTM_Saved_Configuration__c carrying Generated_URL__c) don't spread into
 * every other publish-path test that has no reason to care about them.
 *
 * Nothing here touches GTM_Readout_Approval / PRE_APPROVAL_STATUSES / the
 * Status__c gate -- readouts are moved to Approved the same direct-DML way
 * GtmReadoutControllerTest.approve() does, because that gate is out of scope
 * for this unit.
 */
@isTest
private class GtmReadoutPublishNotificationTest {

    private static final Decimal SAMPLE_SCORE = 18;

    /** Same shortcut GtmReadoutControllerTest.approve() uses -- see its comment. */
    private static void approve(Id readoutId) {
        update new GTM_Readout__c(Id = readoutId, Status__c = 'Approved');
    }

    /**
     * A GTM_Saved_Configuration__c carrying the already-shareable configurator
     * link. Generated_URL__c is exactly the "?cfgId=..." style link
     * gtmConfigWizard writes for a saved link, and it is what
     * sendPublishNotification appends "&readout=<token>" to.
     */
    private static GTM_Saved_Configuration__c seedSavedConfiguration() {
        GTM_Saved_Configuration__c cfg = new GTM_Saved_Configuration__c(
            Offering__c     = 'migration-accelerator',
            Generated_URL__c = 'https://example.my.site.com/gtmaccelerator/s/configurator?cfgId=abc123'
        );
        insert cfg;
        return cfg;
    }

    private static GTM_Assessment_Request__c seedRequest(
        String requesterEmail, GTM_Saved_Configuration__c cfg
    ) {
        GTM_Assessment_Request__c req = new GTM_Assessment_Request__c(
            Requester_Name__c   = 'Alex Rivera',
            Requester_Email__c  = requesterEmail,
            Company__c          = 'Northwind Retail',
            Assessment_Score__c = SAMPLE_SCORE,
            Assessment_Tier__c  = 'Prep Required',
            Saved_Configuration__c = cfg == null ? null : cfg.Id
        );
        insert req;
        return req;
    }

    private static Id publishedReadout(String requesterEmail, GTM_Saved_Configuration__c cfg) {
        GTM_Assessment_Request__c req = seedRequest(requesterEmail, cfg);
        Id readoutId = GtmReadoutController.generateDraftReadout(req.Id);
        approve(readoutId);
        GtmReadoutController.publishReadout(readoutId);
        return readoutId;
    }

    // ------------------------------------------------------------- success

    @isTest
    static void publishSendsProspectNotificationEmailAndStampsSentDate() {
        GTM_Saved_Configuration__c cfg = seedSavedConfiguration();

        Test.startTest();
        Id readoutId = publishedReadout('alex.rivera@example.com', cfg);
        // Read before stopTest() -- Test.stopTest() closes out the fresh
        // governor-limit window startTest() opened and hands control back to
        // the outer (pre-startTest) window's counters, so
        // Limits.getEmailInvocations() called after stopTest() reports 0
        // regardless of what happened inside, confirmed directly against
        // gtm-dev.
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Notification_Sent_Date__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
        ];
        Assert.areEqual('Published', readout.Status__c, 'Publish must still succeed');
        Assert.isNotNull(
            readout.Notification_Sent_Date__c,
            'A confirmed send should stamp Notification_Sent_Date__c'
        );
        Assert.areEqual(
            1, emailInvocations,
            'Exactly one notification email should be attempted per publish'
        );
    }

    // ---------------------------------------------- non-blocking guarantees

    @isTest
    static void publishStillSucceedsWhenProspectEmailIsMissing() {
        GTM_Saved_Configuration__c cfg = seedSavedConfiguration();

        Test.startTest();
        Id readoutId = publishedReadout(null, cfg);
        // See publishSendsProspectNotificationEmailAndStampsSentDate for why
        // this is read before stopTest().
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Public_Link_Token__c, Notification_Sent_Date__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
        ];
        Assert.areEqual(
            'Published', readout.Status__c,
            'A missing prospect email must not block or roll back publish'
        );
        Assert.isNotNull(readout.Public_Link_Token__c, 'The token must still be minted');
        Assert.isNull(
            readout.Notification_Sent_Date__c,
            'No email was sendable, so the sent-date must stay unset'
        );
        Assert.areEqual(
            0, emailInvocations,
            'No email should be attempted with no address to send to'
        );
    }

    /**
     * rep-initiated-assessment-no-page-3: a missing configurator link no
     * longer means "no email, ever" -- that was the real gap this sub-issue
     * found and fixed. A pageless (Rep_Direct) assessment request has no
     * Saved_Configuration__c page and so no Generated_URL__c to build a
     * link from, but sendPublishNotification now falls back to the
     * standalone readout link (GtmSavedConfigurationController.
     * getReadoutBaseUrl() + '/readout?token=', the same route
     * gtmReadoutReview's own rep-facing public link uses) instead of
     * silently skipping the prospect notification forever.
     *
     * Real unit test context never has an Experience Cloud site
     * ConnectApi.Communities can see (confirmed against
     * GtmSavedConfigurationControllerTest's own
     * orgAndSiteUrlHelpersDoNotThrowEvenWithoutASiteConfigured), so
     * getReadoutBaseUrl() always resolves null here regardless of gtm-dev's
     * real, live "gtm"-prefixed community -- readoutBaseUrlOverrideForTests
     * is the same kind of test-only seam as forceSendFailureForTests, used
     * here to make the fallback branch itself deterministically testable.
     */
    @isTest
    static void publishFallsBackToTheStandaloneReadoutLinkWhenTheConfiguratorLinkIsMissing() {
        GtmReadoutController.setReadoutBaseUrlOverrideForTests('https://example.my.site.com/gtm/s');

        Test.startTest();
        Id readoutId;
        try {
            readoutId = publishedReadout('alex.rivera@example.com', null);
        } finally {
            GtmReadoutController.setReadoutBaseUrlOverrideForTests(null);
        }
        // See publishSendsProspectNotificationEmailAndStampsSentDate for why
        // this is read before stopTest().
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Public_Link_Token__c, Notification_Sent_Date__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
        ];
        Assert.areEqual(
            'Published', readout.Status__c,
            'A missing configurator link must not block or roll back publish'
        );
        Assert.isNotNull(readout.Public_Link_Token__c, 'The token must still be minted');
        Assert.isNotNull(
            readout.Notification_Sent_Date__c,
            'The fallback standalone-link email must still be sent, and stamp the sent-date'
        );
        Assert.areEqual(
            1, emailInvocations,
            'One fallback-link email should be attempted with no page-linked configurator link'
        );
    }

    /**
     * The graceful-degradation floor underneath the fallback above: when
     * there is neither a page-linked URL NOR a resolvable site base (no
     * live Experience Cloud site at all -- exactly what an empty/unprovisioned
     * org, and every real unit test context, looks like), the notification
     * is still skipped rather than sending a broken link or throwing.
     * publishReadout itself must still succeed either way.
     */
    @isTest
    static void publishStillSucceedsWhenNeitherAPageLinkNorASiteBaseCanBeResolved() {
        Test.startTest();
        Id readoutId = publishedReadout('alex.rivera@example.com', null);
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Public_Link_Token__c, Notification_Sent_Date__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
        ];
        Assert.areEqual(
            'Published', readout.Status__c,
            'Publish must still succeed with no link of any kind to notify from'
        );
        Assert.isNotNull(readout.Public_Link_Token__c, 'The token must still be minted');
        Assert.isNull(
            readout.Notification_Sent_Date__c,
            'No link was available to send at all, so the sent-date must stay unset'
        );
        Assert.areEqual(
            0, emailInvocations,
            'No email should be attempted when no link -- page or fallback -- could be built'
        );
    }

    @isTest
    static void publishStillSucceedsWhenTheEmailSendFails() {
        // A genuine, non-throwing "the send itself failed" outcome cannot be
        // produced from test data: Requester_Email__c is a real Email-type
        // field, so a malformed address (e.g. one without "@") can never
        // actually be persisted -- Salesforce rejects it at DML time with
        // INVALID_EMAIL_ADDRESS before sendPublishNotification is ever
        // reached -- and any well-formed address reports success in test
        // context (unit tests never really dispatch mail). Governor-limit
        // exceptions were tried too and confirmed (directly against gtm-dev)
        // to be fatal/uncatchable even inside a try/catch, which would defeat
        // the very "publish must still succeed" guarantee this test exists
        // to prove. GtmReadoutController.forceSendFailureForTests is a
        // narrow, additive-only @TestVisible seam added specifically to make
        // this scenario reachable at all -- see its own comment in
        // GtmReadoutController for the full reasoning. It defaults to false
        // and cannot affect any real transaction.
        GTM_Saved_Configuration__c cfg = seedSavedConfiguration();
        GtmReadoutController.setForceSendFailureForTests(true);

        Test.startTest();
        Id readoutId;
        try {
            readoutId = publishedReadout('alex.rivera@example.com', cfg);
        } finally {
            GtmReadoutController.setForceSendFailureForTests(false);
        }
        Test.stopTest();

        GTM_Readout__c readout = [
            SELECT Status__c, Public_Link_Token__c, Notification_Sent_Date__c
            FROM GTM_Readout__c
            WHERE Id = :readoutId
        ];
        Assert.areEqual(
            'Published', readout.Status__c,
            'A failed send must not block or roll back publish -- the readout must ' +
            'still end up Published'
        );
        Assert.isNotNull(readout.Public_Link_Token__c, 'The token must still be minted');
        Assert.isNull(
            readout.Notification_Sent_Date__c,
            'A failed send must not stamp the sent-date'
        );
    }

    @isTest
    static void sendPublishNotificationNeverThrowsWithANullAssessmentRequest() {
        // Direct unit coverage of the helper's own defensive guard, exercised
        // through the @TestVisible seam rather than only indirectly through
        // publishReadout.
        Test.startTest();
        try {
            GtmReadoutController.sendPublishNotification(null, null, 'some-token');
        } catch (Exception e) {
            Assert.fail('sendPublishNotification must never throw: ' + e.getMessage());
        }
        Test.stopTest();

        Assert.areEqual(0, Limits.getEmailInvocations(), 'No email should be attempted with no request Id');
    }
}
