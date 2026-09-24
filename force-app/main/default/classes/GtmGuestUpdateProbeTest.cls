/**
 * THE PROBE, and its permanent regression gate.
 *
 * The question this class was written to settle before any of
 * GtmAssessmentDraftController was written:
 *
 *      Can a guest user UPDATE a record it does not own, via Apex running in
 *      system mode (`without sharing`), in a real org?
 *
 * ANSWERED. Run empirically against this org on 2026-09-07, via both
 * System.runAs (this class, run as a real test) and scripts/probe-guest-
 * update.apex's mechanism (an anonymous-Apex script, which -- a real finding
 * of its own -- CANNOT use System.runAs at all: it is only legal inside a
 * test method, so that script's original form could never have run as
 * written). Both approaches agree.
 *
 * THE ANSWER IS NO. A guest cannot update a record it does not own, and
 * cannot update a record it created itself moments earlier in the same
 * transaction, either -- both return the identical
 * INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY. "Secure guest user record
 * access" (Salesforce's platform-level hardening) overrides `without sharing`
 * for the guest user specifically; the sharing keyword does not rescue it.
 *
 * CONSEQUENCE. GtmAssessmentDraftController does not use `update`, anywhere,
 * on GTM_Form_Draft__c. Every save is an INSERT (append-and-count); every
 * revocation is an appended terminal row, never a flipped status column. See
 * that class's own header and docs/handoff/port-map-ma-to-gtm.md section F.
 *
 * WHY THIS TEST STAYS. Two reasons this class is not deleted now that the
 * question is settled:
 *   1. It is the permanent regression gate for the platform fact itself
 *      (aGuestCannotUpdateARecordItDoesNotOwn / ...ItOwnsItself) -- if
 *      Salesforce ever changes this behavior, or this org's guest-access
 *      settings are ever reconfigured, these tests are what would notice.
 *   2. It is the guest-context proof that the append-and-count design
 *      actually works AS A GUEST (System.runAs), not just as the internal
 *      user GtmAssessmentDraftControllerTest exercises the mechanism as.
 *
 * IF NO GUEST USER EXISTS in the target org, every test no-ops with an
 * explanatory pass rather than a red build. An org with no Experience Cloud
 * site cannot answer this question and should not pretend to.
 */
@IsTest
private class GtmGuestUpdateProbeTest {

    /**
     * A guest user to run as, or null if this org has none.
     *
     * Not `SeeAllData` -- User is a setup object and is visible to a test
     * without it. The `LIMIT 1` is deliberate: any guest user answers the
     * platform question, and picking a particular site's guest would make the
     * result look site-specific when it is not.
     */
    private static User guestUser() {
        List<User> found = [
            SELECT Id, Name, UserType
            FROM   User
            WHERE  UserType = 'Guest'
            AND    IsActive = true
            LIMIT  1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /**
     * THE PROBE, part 1: a record the guest does NOT own (seeded by the
     * running test user), updated as the guest. Uses GTM_Saved_Configuration__c
     * rather than GTM_Form_Draft__c deliberately -- this is a platform-level
     * question, not a GTM_Form_Draft__c-specific one, and using a different
     * object than the one the design decision is about keeps this test from
     * ever looking like it is testing the controller instead of the platform.
     */
    @IsTest
    static void aGuestCannotUpdateARecordItDoesNotOwn() {
        User guest = guestUser();
        if (guest == null) {
            System.assert(true,
                'SKIPPED: this org has no active guest user, so it cannot answer '
                + 'the guest-update question.');
            return;
        }

        GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
            Company__c  = 'GUEST-UPDATE-PROBE-NOT-OWNED',
            Offering__c = 'migration-accelerator',
            Active__c   = true
        );
        insert rec;

        Boolean updated;
        String  failure;

        Test.startTest();
        System.runAs(guest) {
            try {
                update new GTM_Saved_Configuration__c(Id = rec.Id, Active__c = false);
                updated = true;
            } catch (Exception e) {
                updated = false;
                failure = e.getTypeName() + ': ' + e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(false, updated,
            'THE PLATFORM ANSWER CHANGED. A guest user just updated a record it '
            + 'does not own, in this org -- previously confirmed impossible '
            + '(INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY). If this is now '
            + 'possible, GtmAssessmentDraftController\'s append-and-count design '
            + 'is no longer forced by the platform, though it remains correct. '
            + (failure != null ? '' : 'No exception was thrown where one always was before.'));
    }

    /**
     * THE PROBE, part 2: a record the guest DOES own -- inserted by the guest
     * itself, in the same transaction, then updated by that same guest
     * identity. This is the scenario that actually matters for
     * GtmAssessmentDraftController: the real production flow is guest inserts
     * (owns the row), guest later tries to update that same row.
     */
    @IsTest
    static void aGuestCannotUpdateARecordItOwnsItself() {
        User guest = guestUser();
        if (guest == null) {
            System.assert(true, 'SKIPPED: no active guest user in this org.');
            return;
        }

        Boolean updated;
        String  failure;

        Test.startTest();
        System.runAs(guest) {
            GTM_Saved_Configuration__c rec = new GTM_Saved_Configuration__c(
                Company__c  = 'GUEST-UPDATE-PROBE-OWN-RECORD',
                Offering__c = 'migration-accelerator',
                Active__c   = true
            );
            insert rec;
            try {
                update new GTM_Saved_Configuration__c(Id = rec.Id, Active__c = false);
                updated = true;
            } catch (Exception e) {
                updated = false;
                failure = e.getTypeName() + ': ' + e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(false, updated,
            'THE PLATFORM ANSWER CHANGED, for a record the guest created itself. '
            + 'Previously confirmed impossible in this org, even for the guest\'s '
            + 'own just-created rows. If this is now possible,'
            + ' GtmAssessmentDraftController could adopt in-place counters again, '
            + 'though the append-and-count design remains correct as written.');
    }

    /**
     * THE REAL CODE PATH, as a guest, proving the append-and-count design
     * actually works end to end -- not just that the platform forces it.
     * A prospect typing into the questionnaire calls saveDraft on every
     * pause; the second call is what would have been an update in the
     * discarded design and is an insert here.
     */
    @IsTest
    static void aGuestCanSaveTwiceThroughTheController() {
        User guest = guestUser();
        if (guest == null) {
            System.assert(true,
                'SKIPPED: no active guest user in this org. See the note on '
                + 'aGuestCannotUpdateARecordItDoesNotOwn.');
            return;
        }

        String  token;
        Boolean secondSaveWorked;
        String  failure;

        Test.startTest();
        System.runAs(guest) {
            try {
                GtmAssessmentDraftController.DraftHandle first =
                    GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc', null, null);
                token = first.resumeToken;

                GtmAssessmentDraftController.saveDraft(token, '{"q1":"a","q2":"b"}', 'hubspot__sfmc', null, null);
                secondSaveWorked = true;
            } catch (Exception e) {
                secondSaveWorked = false;
                failure = e.getTypeName() + ': ' + e.getMessage();
            }
        }
        Test.stopTest();

        System.assertNotEquals(null, token,
            'The guest could not even mint a draft. That is an insert, not an '
            + 'update, so this is a different and more basic problem than the '
            + 'one this class was written to probe -- most likely the guest '
            + 'permission set is not granting GtmAssessmentDraftController.');

        System.assertEquals(true, secondSaveWorked,
            'A guest minted a draft but could not save into it a second time -- '
            + failure + '. Every prospect hits this on their second keystroke '
            + 'pause. Progress cannot persist.');
    }

    /**
     * Resume is the other half of requirement 12 ("they can always pick up
     * where they left off"). Unlike the discarded design, this performs no
     * DML at all -- see GtmAssessmentDraftController.resumeDraft.
     */
    @IsTest
    static void aGuestCanResumeADraftItStarted() {
        User guest = guestUser();
        if (guest == null) {
            System.assert(true, 'SKIPPED: no active guest user in this org.');
            return;
        }

        String token;
        GtmAssessmentDraftController.DraftPayload resumed;

        Test.startTest();
        System.runAs(guest) {
            GtmAssessmentDraftController.DraftHandle h =
                GtmAssessmentDraftController.saveDraft(null, '{"q1":"a"}', 'hubspot__sfmc', null, null);
            token   = h.resumeToken;
            resumed = GtmAssessmentDraftController.resumeDraft(token);
        }
        Test.stopTest();

        System.assertNotEquals(null, resumed,
            'resumeDraft returned null for a token minted moments earlier in the '
            + 'same transaction. A prospect clicking their own resume link would '
            + 'see "this link is no longer valid" and have no way to tell it is '
            + 'a bug.');
    }
}
