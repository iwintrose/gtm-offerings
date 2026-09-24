/**
 * Guided Setup actions (docs/architecture/guided-setup-implementation-plan.md
 * section 2.3). The only DML in the Setup feature lives here, in three methods:
 * assignPermissionSet, assignPermissionSetToMe (setup-object DML only) and
 * createFrameworkPage (non-setup DML only, its own transaction, so the two
 * never share a transaction and MIXED_DML cannot occur).
 *
 * Access: granted only to GTM_Offering_Admin. There is deliberately no in-Apex
 * role check, so a System Administrator who does not yet hold the set can use
 * "assign to me". Platform failures (missing Assign Permission Sets system
 * permission, INSUFFICIENT_ACCESS) never report success: they return
 * fallbackToSetup = true and the Setup path, and the LWC renders a link.
 */
public with sharing class GtmSetupActionController {

    public static final String PS_OFFERING_USER  = 'GTM_Offering_User';
    public static final String PS_CONTENT_MANAGER = 'GTM_Content_Manager';
    public static final String PS_OFFERING_ADMIN = 'GTM_Offering_Admin';
    public static final String PS_CONTENT_ADMIN  = 'GTM_Content_Admin';

    /** Assignable to any active Standard user. Exact match, never from input. */
    private static final Set<String> ANY_USER_SETS = new Set<String>{
        PS_OFFERING_USER, PS_CONTENT_MANAGER
    };
    /** Admin tier: self only, so this is not an admin-promotion lever. */
    private static final Set<String> SELF_ONLY_SETS = new Set<String>{
        PS_OFFERING_ADMIN, PS_CONTENT_ADMIN
    };
    /** The five framework page templates (offering key is always 'gtm'). */
    private static final Set<String> FRAMEWORK_TEMPLATES = new Set<String>{
        'offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager', 'assistant'
    };

    public static final String SETUP_PATH_PERMSETS = '/lightning/setup/PermSets/home';

    /** Test seam: forces the assignment insert to fail as a platform error. */
    @TestVisible private static Boolean forceAssignFailure = false;

    public class AssignResult {
        @AuraEnabled public Boolean assigned;
        @AuraEnabled public String  permissionSetName;
        @AuraEnabled public String  message;
        @AuraEnabled public Boolean fallbackToSetup;
        @AuraEnabled public String  setupPath;
    }

    public class FrameworkPageResult {
        @AuraEnabled public String  templateType;
        @AuraEnabled public Boolean created;
        @AuraEnabled public Integer sectionCount;
        @AuraEnabled public String  message;
    }

    @AuraEnabled
    public static AssignResult assignPermissionSet(Id userId, String permissionSetName) {
        return doAssign(userId, permissionSetName);
    }

    @AuraEnabled
    public static AssignResult assignPermissionSetToMe(String permissionSetName) {
        return doAssign(UserInfo.getUserId(), permissionSetName);
    }

    @AuraEnabled
    public static FrameworkPageResult createFrameworkPage(
        String templateType, List<GtmPageSectionController.SectionSeed> sections
    ) {
        if (String.isBlank(templateType) || !FRAMEWORK_TEMPLATES.contains(templateType)) {
            throw fail('That is not a framework page.');
        }
        String offeringKey = GtmPageContentController.FRAMEWORK_KEY;

        FrameworkPageResult result = new FrameworkPageResult();
        result.templateType = templateType;

        Integer existing = [
            SELECT COUNT() FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :offeringKey AND Template_Type__c = :templateType
        ];
        if (existing > 0) {
            result.created = false;
            result.sectionCount = existing;
            result.message = 'This page already has sections, so nothing was changed.';
            return result;
        }

        // createPage is all-or-nothing; a failure is returned as a message, never reported as created.
        try {
            Integer count = GtmPageSectionController.createPage(offeringKey, templateType, sections);
            result.created = true;
            result.sectionCount = count;
            result.message = 'Created ' + count + ' empty section' + (count == 1 ? '' : 's') + '.';
        } catch (Exception e) {
            result.created = false;
            result.sectionCount = 0;
            String m = e.getMessage();
            result.message = 'The page could not be created'
                + (String.isBlank(m) || m.startsWith('Script-thrown') ? '.' : ': ' + m)
                + ' Nothing was changed for this page.';
        }
        return result;
    }

    private static AssignResult doAssign(Id userId, String permissionSetName) {
        if (String.isBlank(permissionSetName)
            || !(ANY_USER_SETS.contains(permissionSetName) || SELF_ONLY_SETS.contains(permissionSetName))) {
            throw fail('That permission set cannot be assigned from Setup.');
        }
        if (userId == null) {
            throw fail('Choose a user first.');
        }
        if (SELF_ONLY_SETS.contains(permissionSetName) && userId != UserInfo.getUserId()) {
            throw fail(
                'You can only assign this admin permission set to yourself. Use Setup to assign it to someone else.'
            );
        }

        List<User> users = [
            SELECT Id, IsActive, UserType FROM User WHERE Id = :userId LIMIT 1
        ];
        if (users.isEmpty() || users[0].IsActive != true || users[0].UserType != 'Standard') {
            throw fail('Permission sets can only be assigned to active Standard users.');
        }
        List<PermissionSet> sets = [
            SELECT Id FROM PermissionSet
            WHERE Name = :permissionSetName AND IsOwnedByProfile = false LIMIT 1
        ];
        if (sets.isEmpty()) {
            throw fail('That permission set was not found in this org.');
        }

        AssignResult r = new AssignResult();
        r.permissionSetName = permissionSetName;
        r.fallbackToSetup = false;

        Integer held = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :sets[0].Id
        ];
        if (held > 0) {
            r.assigned = false;
            r.message = 'Already assigned.';
            return r;
        }

        if (forceAssignFailure) {
            return fallback(r, 'INSUFFICIENT_ACCESS (simulated)');
        }
        Database.SaveResult sr;
        try {
            sr = Database.insert(
                new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = sets[0].Id), false
            );
        } catch (Exception e) {
            return fallback(r, e.getMessage());
        }
        if (!sr.isSuccess()) {
            String msg = sr.getErrors().isEmpty() ? 'Unknown error' : sr.getErrors()[0].getMessage();
            return fallback(r, msg);
        }
        r.assigned = true;
        r.message = 'Assigned.';
        return r;
    }

    /** AuraHandledException whose message the client actually sees (not 'Script-thrown exception'). */
    private static AuraHandledException fail(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    private static AssignResult fallback(AssignResult r, String reason) {
        r.assigned = false;
        r.fallbackToSetup = true;
        r.setupPath = SETUP_PATH_PERMSETS;
        r.message = 'This could not be done here (' + reason + '). Assign it in Setup instead.';
        return r;
    }
}
