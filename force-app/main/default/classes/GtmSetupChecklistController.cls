/**
 * Backs the "Setup" section of the admin-only Settings tab (guided setup,
 * docs/architecture/guided-setup-implementation-plan.md section 2.2).
 *
 * Derive-only: nothing is stored. Every call re-detects from live org state
 * (SOQL, schema and custom-setting reads only). NO DML, NO callouts.
 *
 * Each detector runs inside its own try/catch, so one failing or unreadable
 * check yields status UNKNOWN for that row alone and never an exception, and
 * never a false DONE. No org id, username, or secret ever appears in an item.
 *
 * Apex class access is granted only to GTM_Offering_Admin (permission set is
 * owned by a different workstream). `with sharing`.
 */
public with sharing class GtmSetupChecklistController {

    // ---- Frozen constants shared with the LWC and Jest fixtures ----
    public static final String TIER_REQUIRED    = 'REQUIRED';
    public static final String TIER_RECOMMENDED = 'RECOMMENDED';
    public static final String TIER_OPTIONAL    = 'OPTIONAL';
    public static final String TIER_INFO        = 'INFO';

    public static final String STATUS_DONE    = 'DONE';
    public static final String STATUS_TODO    = 'TODO';
    public static final String STATUS_NOT_SET = 'NOT_SET';
    public static final String STATUS_BLOCKED = 'BLOCKED';
    public static final String STATUS_UNKNOWN = 'UNKNOWN';
    public static final String STATUS_INFO    = 'INFO';

    public static final String ACTION_NONE                   = 'NONE';
    public static final String ACTION_LINK                   = 'LINK';
    public static final String ACTION_ASSIGN_TO_ME           = 'ASSIGN_TO_ME';
    public static final String ACTION_ASSIGN_PICKER          = 'ASSIGN_PICKER';
    public static final String ACTION_SCHEDULE_JOBS          = 'SCHEDULE_JOBS';
    public static final String ACTION_CREATE_FRAMEWORK_PAGES = 'CREATE_FRAMEWORK_PAGES';

    public static final String LINK_NAV_ITEM   = 'NAV_ITEM';
    public static final String LINK_SETUP_PATH = 'SETUP_PATH';
    public static final String LINK_NONE       = 'NONE';

    private static final String CAT_ACCESS        = 'ACCESS';
    private static final String CAT_SITE          = 'SITE';
    private static final String CAT_CONTENT       = 'CONTENT';
    private static final String CAT_CONFIGURATION = 'CONFIGURATION';
    private static final String CAT_ORG           = 'ORG';

    private static final String PS_ADMIN           = 'GTM_Offering_Admin';
    private static final String PS_USER            = 'GTM_Offering_User';
    private static final String PS_CONTENT_MANAGER = 'GTM_Content_Manager';
    private static final String PS_CONTENT_ADMIN   = 'GTM_Content_Admin';
    private static final String PS_GUEST           = 'GTM_Guest';
    private static final List<String> GTM_SETS = new List<String>{
        PS_ADMIN, PS_USER, PS_CONTENT_MANAGER, PS_CONTENT_ADMIN, PS_GUEST
    };

    private static final String OWNER = 'gtm';
    private static final String SITE_NAME = 'GTM';
    private static final String QUEUE_NAME = 'GTM_Readout_Triage';
    private static final List<String> FRAMEWORK_TEMPLATES = new List<String>{
        'offerings-page', 'industry-chooser', 'faq-bd', 'faq-content-manager', 'assistant'
    };
    private static final Integer MAX_USER_RESULTS = 25;
    private static final Integer MAX_TERM_LENGTH = 80;
    private static final String GENERIC_UNKNOWN_DETAIL =
        'This could not be checked right now. Use Re-check, or open the related Setup page.';

    /** All Setup deep links live here (each is UNVERIFIED until QA opens it). */
    @TestVisible
    private static final Map<String, String> SETUP_PATHS = new Map<String, String>{
        'permission_sets'      => '/lightning/setup/PermSets/home',
        'all_sites'            => '/lightning/setup/SetupNetworks/home',
        'custom_metadata'      => '/lightning/setup/CustomMetadata/home',
        'queues'               => '/lightning/setup/Queues/home',
        'users'                => '/lightning/setup/ManageUsers/home',
        'digital_experiences'  => '/lightning/setup/NetworkSettings/home',
        'my_domain'            => '/lightning/setup/OrgDomain/home',
        'chatter'              => '/lightning/setup/CollaborationSettings/home',
        'email_deliverability' => '/lightning/setup/OrgEmailSettings/home',
        'flows'                => '/lightning/setup/Flows/home'
    };

    /** Issue #38: the specific org-bundled sample flow that silently blocked
     * every Case insert in gtm-staging on 2026-09-26 (CANNOT_EXECUTE_FLOW_TRIGGER).
     * Scoped to this one confirmed flow only -- see docs/backlog.md "Later:
     * SDO_Service_Case_Status_Updated" for the named, unconfirmed follow-up. */
    @TestVisible
    private static final String SDO_FLOW_API_NAME = 'SDO_Service_Case_Creation';

    /** Test seam: forces the named detector to throw so isolation can be proven. */
    @TestVisible private static String forceFailKey;

    // ---- DTOs (frozen) ----
    public class SetupChecklist {
        @AuraEnabled public List<SetupItem> items;
        @AuraEnabled public Integer requiredTotal;
        @AuraEnabled public Integer requiredDone;
        @AuraEnabled public Integer requiredUnknown;
        @AuraEnabled public Boolean selfApprovalEnabled;
        @AuraEnabled public String  checkedAt;
    }

    public class SetupItem {
        @AuraEnabled public String  key;
        @AuraEnabled public String  tier;
        @AuraEnabled public String  category;
        @AuraEnabled public String  status;
        @AuraEnabled public String  title;
        @AuraEnabled public String  why;
        @AuraEnabled public String  detail;
        @AuraEnabled public Boolean humanMustAct;
        @AuraEnabled public String  actionType;
        @AuraEnabled public String  actionLabel;
        @AuraEnabled public String  linkKind;
        @AuraEnabled public String  navApiName;
        @AuraEnabled public Map<String, String> navState;
        @AuraEnabled public String  setupPath;
        @AuraEnabled public String  permissionSetName;
        @AuraEnabled public List<String> blockedBy = new List<String>();
        @AuraEnabled public Boolean collapsedByDefault;
    }

    public class UserOption {
        @AuraEnabled public Id     userId;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
    }

    // ---- Catalogue (order is the on-screen order within a tier) ----
    private class Spec {
        String key; String tier; String category; String title; String why; Boolean human;
        Spec(String key, String tier, String category, String title, String why, Boolean human) {
            this.key = key; this.tier = tier; this.category = category;
            this.title = title; this.why = why; this.human = human;
        }
    }

    private static List<Spec> catalogue() {
        return new List<Spec>{
            new Spec('admin_assigned', TIER_REQUIRED, CAT_ACCESS, 'An administrator holds the GTM Offering Admin permission set',
                'Someone must hold the admin permission set to configure the app.', false),
            new Spec('content_access', TIER_RECOMMENDED, CAT_ACCESS, 'You can open the Content Manager',
                'Content rows open pages that need the Content Manager permission set.', false),
            new Spec('reps_assigned', TIER_RECOMMENDED, CAT_ACCESS, 'Reps have the GTM Offering User permission set',
                'Reps need this permission set to use the app.', true),
            new Spec('guest_permset', TIER_REQUIRED, CAT_SITE, 'The site guest user has the GTM Guest permission set',
                'Prospects see nothing on the site until the guest permission set is on the site\'s guest user.', true),
            new Spec('site_active', TIER_REQUIRED, CAT_SITE, 'The prospect site is active',
                'Prospects can only reach pages on an active, published site.', true),
            new Spec('framework_pages', TIER_REQUIRED, CAT_CONTENT, 'The framework pages are created',
                'The framework pages (offerings page, industry chooser, help panels, assistant) have no sections until they are created, so the Content Manager cards are empty and cannot be edited.', false),
            new Spec('industry_added', TIER_REQUIRED, CAT_CONTENT, 'An industry is added and published',
                'Prospects choose their industry on the Industry Chooser page, which stays empty until you add and publish an industry.', true),
            new Spec('offering_created', TIER_REQUIRED, CAT_CONTENT, 'An offering is created',
                'An offering is what reps sell and prospects see.', true),
            new Spec('offering_published', TIER_REQUIRED, CAT_CONTENT, 'An offering is published',
                'Draft offerings are hidden on purpose, so nothing shows until one is published.', true),
            new Spec('offering_listed', TIER_REQUIRED, CAT_CONTENT, 'A published offering is listed on the site',
                'The public offerings page lists an offering only once its site record exists.', true),
            new Spec('triage_queue', TIER_RECOMMENDED, CAT_CONFIGURATION, 'The readout triage queue has members',
                'A readout with no owner lands in this queue, and nobody can see it until someone is a member.', true),
            new Spec('manager_on_reps', TIER_RECOMMENDED, CAT_CONFIGURATION, 'Reps have a manager',
                'With manager approval, a readout submitted by a rep with no manager has nowhere to go.', true),
            new Spec('scheduled_jobs', TIER_RECOMMENDED, CAT_CONFIGURATION, 'The purge jobs are scheduled',
                'Old drafts and deleted records are purged on a schedule; the app works without it.', false),
            new Spec('site_members', TIER_RECOMMENDED, CAT_SITE, 'Reps are members of the site',
                'Reps who open the site themselves must be members of it.', true),
            new Spec('sdo_demo_flow', TIER_RECOMMENDED, CAT_CONFIGURATION, 'No blocking SDO demo-org flow is active on Case',
                'A bundled Salesforce "SDO Service" demo flow can silently block every Case insert (CANNOT_EXECUTE_FLOW_TRIGGER) with no error shown to anyone.', true),
            new Spec('agentforce_agent', TIER_RECOMMENDED, CAT_CONFIGURATION, 'The Agentforce Agent API is configured',
                'GUS\'s Agentforce integration needs an Agent Id that resolves to a real, active agent before it can be turned on.', true),
            new Spec('page_offerings', TIER_OPTIONAL, CAT_CONTENT, 'Offerings page intro copy',
                'Intro copy on the front page that lists every offering.', true),
            new Spec('page_faq_bd', TIER_OPTIONAL, CAT_CONTENT, 'Rep help panel',
                'Reps see this help panel; without it they see no help.', true),
            new Spec('page_faq_cm', TIER_OPTIONAL, CAT_CONTENT, 'Content author help panel',
                'Content authors see this help panel; without it they see no help.', true),
            new Spec('page_assistant', TIER_OPTIONAL, CAT_CONTENT, 'Assistant name and greeting',
                'Sets the assistant\'s name and greeting.', true),
            new Spec('analytics_digest', TIER_OPTIONAL, CAT_CONFIGURATION, 'Weekly analytics digest',
                'Turns on the weekly analytics email digest.', true),
            new Spec('ai_keys', TIER_OPTIONAL, CAT_CONFIGURATION, 'GUS chat provider key',
                'Enables the GUS chat assistant; nothing else depends on it.', true),
            new Spec('approval_routing', TIER_INFO, CAT_CONFIGURATION, 'Readout approval routing',
                'Decides whether a readout goes to the rep\'s manager or is self-approved.', true),
            new Spec('offering_pages', TIER_INFO, CAT_CONTENT, 'Offering story and configurator pages',
                'An offering\'s story and configurator pages exist only after they are created in the Content Manager.', true),
            new Spec('org_digital_experiences', TIER_INFO, CAT_ORG, 'Digital Experiences is enabled',
                'The prospect site needs Digital Experiences turned on in this org.', true),
            new Spec('org_my_domain', TIER_INFO, CAT_ORG, 'My Domain',
                'Site and app links depend on the org having a My Domain.', true),
            new Spec('org_chatter', TIER_INFO, CAT_ORG, 'Chatter',
                'Some Experience Cloud site features rely on Chatter being enabled.', true),
            new Spec('org_email', TIER_INFO, CAT_ORG, 'Email deliverability and sender',
                'Notification and digest emails only send when org email deliverability allows it.', true)
        };
    }

    // ---- Per-call context ----
    private class Ctx {
        Id viewerId;
        Map<String, Integer> assignCounts = new Map<String, Integer>();
        Set<String> viewerSets = new Set<String>();
        GTM_Readout_Approval_Settings__c approval;
        GTM_Analytics_Settings__c analytics;
        List<Network> networks = new List<Network>();
        Boolean networksReadable = true;
        Network site;                       // resolved site, or null
        Map<String, SetupItem> results = new Map<String, SetupItem>();
        Boolean contentAccessMet = false;
        // Offering tile sections, loaded once on first use
        Boolean offeringsLoaded = false;
        Integer offCreated = 0;
        Integer offPublished = 0;
        Integer offDrafts = 0;
        List<String> offeringKeys = new List<String>();
        Integer tileCount = null;
    }

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    @AuraEnabled
    public static SetupChecklist getChecklist() {
        Ctx c;
        try {
            c = buildCtx();
        } catch (Exception e) {
            AuraHandledException ae = new AuraHandledException('Setup could not be loaded.');
            ae.setMessage('Setup could not be loaded.');
            throw ae;
        }
        List<Spec> specs = catalogue();
        Map<String, List<SetupItem>> byTier = new Map<String, List<SetupItem>>{
            TIER_REQUIRED => new List<SetupItem>(),
            TIER_RECOMMENDED => new List<SetupItem>(),
            TIER_OPTIONAL => new List<SetupItem>(),
            TIER_INFO => new List<SetupItem>()
        };
        for (Spec s : specs) {
            SetupItem item;
            try {
                if (forceFailKey != null && forceFailKey == s.key) {
                    throw new IllegalArgumentException('forced');
                }
                item = detect(s, c);
            } catch (Exception e) {
                item = unknown(s);
            }
            if (item == null) continue;   // conditional row that is not shown
            c.results.put(s.key, item);
            byTier.get(s.tier).add(item);
        }
        SetupChecklist out = new SetupChecklist();
        out.items = new List<SetupItem>();
        for (String tier : new List<String>{TIER_REQUIRED, TIER_RECOMMENDED, TIER_OPTIONAL, TIER_INFO}) {
            out.items.addAll(byTier.get(tier));
        }
        out.requiredTotal = 0; out.requiredDone = 0; out.requiredUnknown = 0;
        for (SetupItem i : byTier.get(TIER_REQUIRED)) {
            out.requiredTotal++;
            if (i.status == STATUS_DONE) out.requiredDone++;
            if (i.status == STATUS_UNKNOWN) out.requiredUnknown++;
        }
        out.selfApprovalEnabled = c.approval != null && c.approval.Self_Approval_Enabled__c == true;
        out.checkedAt = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        return out;
    }

    /** Standard, active users only, so a guest/site/portal user is never offered. */
    @AuraEnabled
    public static List<UserOption> searchAssignableUsers(String searchTerm) {
        String term = searchTerm == null ? '' : searchTerm.trim();
        if (term.length() > MAX_TERM_LENGTH) term = term.substring(0, MAX_TERM_LENGTH);
        term = term.replace('%', '').replace('_', '');
        String pattern = '%' + term + '%';
        List<UserOption> out = new List<UserOption>();
        for (User u : [
            SELECT Id, Name, Username FROM User
            WHERE IsActive = true AND UserType = 'Standard'
              AND (Name LIKE :pattern OR Username LIKE :pattern)
            ORDER BY Name ASC
            LIMIT :MAX_USER_RESULTS
        ]) {
            UserOption o = new UserOption();
            o.userId = u.Id;
            o.name = u.Name;
            o.username = u.Username;
            out.add(o);
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Context
    // ------------------------------------------------------------------

    private static Ctx buildCtx() {
        Ctx c = new Ctx();
        c.viewerId = UserInfo.getUserId();
        for (AggregateResult ar : [
            SELECT PermissionSet.Name nm, COUNT(Id) cnt
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN :GTM_SETS AND Assignee.IsActive = true
            GROUP BY PermissionSet.Name
        ]) {
            c.assignCounts.put((String) ar.get('nm'), (Integer) ar.get('cnt'));
        }
        for (PermissionSetAssignment psa : [
            SELECT PermissionSet.Name FROM PermissionSetAssignment
            WHERE AssigneeId = :c.viewerId AND PermissionSet.Name IN :GTM_SETS
        ]) {
            c.viewerSets.add(psa.PermissionSet.Name);
        }
        c.approval = GTM_Readout_Approval_Settings__c.getOrgDefaults();
        c.analytics = GTM_Analytics_Settings__c.getOrgDefaults();
        try {
            c.networks = [SELECT Id, Name, Status FROM Network LIMIT 200];
        } catch (Exception e) {
            c.networksReadable = false;
        }
        if (c.networksReadable) {
            for (Network n : c.networks) {
                if (n.Name == SITE_NAME) { c.site = n; break; }
            }
            if (c.site == null && c.networks.size() == 1) c.site = c.networks[0];
        }
        c.contentAccessMet = c.viewerSets.contains(PS_CONTENT_MANAGER)
            || c.viewerSets.contains(PS_CONTENT_ADMIN);
        return c;
    }

    // ------------------------------------------------------------------
    // Item helpers
    // ------------------------------------------------------------------

    private static SetupItem base(Spec s) {
        SetupItem i = new SetupItem();
        i.key = s.key; i.tier = s.tier; i.category = s.category;
        i.title = s.title; i.why = s.why; i.humanMustAct = s.human;
        i.actionType = ACTION_NONE; i.linkKind = LINK_NONE;
        i.blockedBy = new List<String>();
        i.collapsedByDefault = (s.tier == TIER_OPTIONAL || s.tier == TIER_INFO);
        return i;
    }

    private static SetupItem unknown(Spec s) {
        SetupItem i = base(s);
        i.status = STATUS_UNKNOWN;
        i.detail = GENERIC_UNKNOWN_DETAIL;
        i.humanMustAct = true;
        return i;
    }

    private static SetupItem done(SetupItem i, String detail) {
        i.status = STATUS_DONE; i.detail = detail;
        i.actionType = ACTION_NONE; i.linkKind = LINK_NONE; i.actionLabel = null;
        return i;
    }

    private static SetupItem blocked(SetupItem i, String detail, List<String> blockedBy) {
        i.status = STATUS_BLOCKED; i.detail = detail;
        i.blockedBy = blockedBy == null ? new List<String>() : blockedBy;
        return i;
    }

    private static SetupItem setupLink(SetupItem i, String pathKey, String label) {
        i.actionType = ACTION_LINK; i.linkKind = LINK_SETUP_PATH;
        i.setupPath = SETUP_PATHS.get(pathKey); i.actionLabel = label;
        return i;
    }

    private static SetupItem navLink(SetupItem i, String navApiName, Map<String, String> state, String label) {
        i.actionType = ACTION_LINK; i.linkKind = LINK_NAV_ITEM;
        i.navApiName = navApiName; i.navState = state; i.actionLabel = label;
        return i;
    }

    /** Opens another Settings section through the shell event; sectionId is in navState. */
    private static SetupItem sectionLink(SetupItem i, String sectionId, String label) {
        i.actionType = ACTION_LINK; i.linkKind = LINK_NONE;
        i.navState = new Map<String, String>{ 'sectionId' => sectionId };
        i.actionLabel = label;
        return i;
    }

    private static Map<String, String> pageState(String template) {
        return new Map<String, String>{ 'c__offering' => OWNER, 'c__template' => template };
    }

    private static Boolean isUsable(String v) {
        if (String.isBlank(v)) return false;
        String t = v.trim();
        return t != '[]' && t != '{}' && t != 'null' && t != '""';
    }

    private static String plural(Integer n, String singular, String pluralForm) {
        return n + ' ' + (n == 1 ? singular : pluralForm);
    }

    private static Boolean dependencyMet(Ctx c, String key) {
        SetupItem it = c.results.get(key);
        return it != null && it.status == STATUS_DONE;
    }

    // ------------------------------------------------------------------
    // Detectors
    // ------------------------------------------------------------------

    private static SetupItem detect(Spec s, Ctx c) {
        SetupItem i = base(s);
        switch on s.key {
            when 'admin_assigned'          { return detectAdmin(i, c); }
            when 'content_access'          { return detectContentAccess(i, c); }
            when 'reps_assigned'           { return detectReps(i, c); }
            when 'guest_permset'           { return detectGuest(i, c); }
            when 'site_active'             { return detectSiteActive(i, c); }
            when 'framework_pages'         { return detectFramework(i, c); }
            when 'industry_added'          { return detectIndustry(i, c); }
            when 'offering_created'        { return detectOfferingCreated(i, c); }
            when 'offering_published'      { return detectOfferingPublished(i, c); }
            when 'offering_listed'         { return detectOfferingListed(i, c); }
            when 'triage_queue'            { return detectQueue(i, c); }
            when 'manager_on_reps'         { return detectManagers(i, c); }
            when 'scheduled_jobs'          { return detectJobs(i, c); }
            when 'site_members'            { return detectMembers(i, c); }
            when 'sdo_demo_flow'           { return detectSdoDemoFlow(i, c); }
            when 'agentforce_agent'        { return detectAgentforceAgent(i, c); }
            when 'page_offerings'          { return detectPage(i, 'offerings-page'); }
            when 'page_faq_bd'             { return detectPage(i, 'faq-bd'); }
            when 'page_faq_cm'             { return detectPage(i, 'faq-content-manager'); }
            when 'page_assistant'          { return detectPage(i, 'assistant'); }
            when 'analytics_digest'        { return detectDigest(i, c); }
            when 'ai_keys'                 { return detectAiKeys(i); }
            when 'approval_routing'        { return detectApproval(i, c); }
            when 'offering_pages'          { return detectOfferingPages(i, c); }
            when 'org_digital_experiences' { return detectOrgDx(i, c); }
            when 'org_my_domain'           { return staticInfo(i, 'Not checked here. Confirm a My Domain is deployed.', 'my_domain', 'Open My Domain'); }
            when 'org_chatter'             { return staticInfo(i, 'Not checked here. Confirm Chatter is enabled if your site needs it.', 'chatter', 'Open Chatter settings'); }
            when 'org_email'               { return staticInfo(i, 'Not checked here. Confirm email deliverability and your sender address.', 'email_deliverability', 'Open email deliverability'); }
            when else                      { return unknown(s); }
        }
    }

    private static SetupItem detectAdmin(SetupItem i, Ctx c) {
        Integer n = c.assignCounts.containsKey(PS_ADMIN) ? c.assignCounts.get(PS_ADMIN) : 0;
        if (n >= 1) {
            return done(i, plural(n, 'active user holds', 'active users hold') + ' this permission set.');
        }
        i.status = STATUS_TODO;
        i.detail = 'No active user holds this permission set yet.';
        i.actionType = ACTION_ASSIGN_TO_ME; i.actionLabel = 'Assign to me';
        i.permissionSetName = PS_ADMIN;
        return i;
    }

    private static SetupItem detectContentAccess(SetupItem i, Ctx c) {
        if (c.contentAccessMet) return null;   // helper row: shown only when unmet
        i.status = STATUS_TODO;
        i.detail = 'You do not hold the Content Manager or Content Admin permission set.';
        i.actionType = ACTION_ASSIGN_TO_ME; i.actionLabel = 'Assign to me';
        i.permissionSetName = PS_CONTENT_MANAGER;
        return i;
    }

    private static SetupItem detectReps(SetupItem i, Ctx c) {
        Integer n = c.assignCounts.containsKey(PS_USER) ? c.assignCounts.get(PS_USER) : 0;
        if (n >= 1) return done(i, plural(n, 'active rep has', 'active reps have') + ' this permission set.');
        i.status = STATUS_TODO;
        i.detail = 'No rep has this permission set yet. Choose who should have it.';
        i.actionType = ACTION_ASSIGN_PICKER; i.actionLabel = 'Choose reps';
        i.permissionSetName = PS_USER;
        return i;
    }

    private static SetupItem detectGuest(SetupItem i, Ctx c) {
        setupLink(i, 'all_sites', 'Open Digital Experiences');
        String fallback = 'Open Experience Builder > Settings > General > Guest User Profile and confirm GTM Guest is assigned.';
        if (!c.networksReadable || c.site == null) {
            i.status = STATUS_UNKNOWN; i.detail = fallback;
            return i;
        }
        Id guestId = null;
        try {
            String siteName = c.site.Name;
            List<SObject> rows = Database.query(
                'SELECT GuestUserId FROM Site WHERE Name = :siteName LIMIT 1');
            if (!rows.isEmpty()) guestId = (Id) rows[0].get('GuestUserId');
        } catch (Exception e) {
            guestId = null;
        }
        if (guestId == null) {
            i.status = STATUS_UNKNOWN; i.detail = fallback;
            return i;
        }
        Integer n = [SELECT COUNT() FROM PermissionSetAssignment
                     WHERE AssigneeId = :guestId AND PermissionSet.Name = :PS_GUEST];
        if (n >= 1) return done(i, 'The site guest user has the GTM Guest permission set.');
        i.status = STATUS_TODO;
        i.detail = 'The site guest user does not have GTM Guest yet. ' + fallback;
        return i;
    }

    private static SetupItem detectSiteActive(SetupItem i, Ctx c) {
        setupLink(i, 'all_sites', 'Open Digital Experiences');
        if (!c.networksReadable) {
            i.status = STATUS_UNKNOWN;
            i.detail = 'Sites could not be read. Open Digital Experiences > All Sites to check.';
            return i;
        }
        if (c.networks.isEmpty()) {
            return blocked(i, 'No site exists. Turn on Digital Experiences and create the site first.', null);
        }
        if (c.site == null) {
            i.status = STATUS_UNKNOWN;
            i.detail = 'More than one site exists and none is named "' + SITE_NAME + '", so it could not be identified.';
            return i;
        }
        if (c.site.Status == 'Live') {
            return done(i, 'The site is live. Unpublished changes cannot be detected here.');
        }
        i.status = STATUS_TODO;
        i.detail = 'The site status is ' + c.site.Status + '. Activate and publish it.';
        return i;
    }

    private static SetupItem detectFramework(SetupItem i, Ctx c) {
        if (!Schema.GTM_Page_Section__c.SObjectType.getDescribe().isAccessible()) return unknown(specFor(i));
        Set<String> have = new Set<String>();
        for (AggregateResult ar : [
            SELECT Template_Type__c t, COUNT(Id) cnt FROM GTM_Page_Section__c
            WHERE Offering_Key__c = :OWNER AND Template_Type__c IN :FRAMEWORK_TEMPLATES
            GROUP BY Template_Type__c
        ]) {
            have.add((String) ar.get('t'));
        }
        List<String> missing = new List<String>();
        for (String t : FRAMEWORK_TEMPLATES) {
            if (!have.contains(t)) missing.add(t);
        }
        if (missing.isEmpty()) return done(i, 'All five framework pages have sections.');
        i.status = STATUS_TODO;
        i.detail = 'Missing: ' + String.join(missing, ', ');
        i.actionType = ACTION_CREATE_FRAMEWORK_PAGES; i.actionLabel = 'Create framework pages';
        return i;
    }

    private static Spec specFor(SetupItem i) {
        return new Spec(i.key, i.tier, i.category, i.title, i.why, i.humanMustAct);
    }

    private static SetupItem detectIndustry(SetupItem i, Ctx c) {
        navLink(i, 'GTM_Content_Manager', pageState('industry-chooser'), 'Add industry');
        Integer labelled = 0;
        Integer unlabelled = 0;
        for (GtmPageContentReader.IndustryProfile p : GtmPageContentReader.getIndustryProfiles(OWNER, 'industry-chooser')) {
            if (String.isNotBlank(p.industryLabel)) labelled++; else unlabelled++;
        }
        if (labelled >= 1) {
            return done(i, plural(labelled, 'industry is', 'industries are') + ' published.');
        }
        List<String> unmet = new List<String>();
        if (!dependencyMet(c, 'framework_pages')) unmet.add('framework_pages');
        if (!c.contentAccessMet) unmet.add('content_access');
        if (!unmet.isEmpty()) {
            return blocked(i, unmet.contains('framework_pages')
                ? 'Create the framework pages first.'
                : 'Assign yourself the Content Manager permission set first.', unmet);
        }
        i.status = STATUS_TODO;
        i.detail = unlabelled > 0
            ? 'An industry exists but is incomplete (it has no name). Fix it, then publish the Industry Chooser page.'
            : 'Add an industry, then Publish the Industry Chooser page.';
        return i;
    }

    private static void loadOfferings(Ctx c) {
        if (c.offeringsLoaded) return;
        c.offeringsLoaded = true;
        for (GTM_Page_Section__c sec : [
            SELECT Offering_Key__c, Offering_Status__c, Archived__c
            FROM GTM_Page_Section__c
            WHERE Template_Type__c = 'offerings-listing' AND Section_Key__c = 'tile'
              AND Offering_Key__c != :OWNER AND Active__c = true
            LIMIT 500
        ]) {
            c.offCreated++;
            if (sec.Archived__c == true) continue;
            c.offeringKeys.add(sec.Offering_Key__c);
            if (sec.Offering_Status__c == 'Published') c.offPublished++; else c.offDrafts++;
        }
    }

    private static SetupItem detectOfferingCreated(SetupItem i, Ctx c) {
        navLink(i, 'GTM_Content_Home', null, 'New Offering');
        loadOfferings(c);
        if (c.offCreated >= 1) return done(i, plural(c.offCreated, 'offering exists', 'offerings exist') + '.');
        i.status = STATUS_TODO;
        i.detail = 'No offering yet. Create one from the Content Manager home.';
        return i;
    }

    private static SetupItem detectOfferingPublished(SetupItem i, Ctx c) {
        navLink(i, 'GTM_Content_Home', null, 'Open Content Manager');
        loadOfferings(c);
        if (c.offPublished >= 1) return done(i, plural(c.offPublished, 'offering is', 'offerings are') + ' published.');
        if (c.offCreated == 0) {
            return blocked(i, 'Create an offering first.', new List<String>{'offering_created'});
        }
        i.status = STATUS_TODO;
        i.detail = plural(c.offDrafts, 'draft offering is', 'draft offerings are') + ' hidden until published.';
        return i;
    }

    private static SetupItem detectOfferingListed(SetupItem i, Ctx c) {
        setupLink(i, 'custom_metadata', 'Open Custom Metadata Types');
        loadOfferings(c);
        c.tileCount = GtmPageContentReader.getOfferingTiles().size();
        if (c.tileCount >= 1) return done(i, plural(c.tileCount, 'offering is', 'offerings are') + ' listed on the site.');
        if (c.offPublished == 0) {
            return blocked(i, 'Publish an offering first.', new List<String>{'offering_published'});
        }
        i.status = STATUS_TODO;
        i.detail = 'Published, but no site record yet. Add a GTM Offering record under Custom Metadata Types > GTM Offering > Manage Records.';
        return i;
    }

    private static SetupItem detectQueue(SetupItem i, Ctx c) {
        setupLink(i, 'queues', 'Open Queues');
        List<Group> q = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :QUEUE_NAME LIMIT 1];
        if (q.isEmpty()) return blocked(i, 'The queue is not deployed in this org.', null);
        Id queueId = q[0].Id;
        Integer n = [SELECT COUNT() FROM GroupMember WHERE GroupId = :queueId];
        if (n >= 1) return done(i, plural(n, 'member', 'members') + ' in the queue.');
        i.status = STATUS_TODO;
        i.detail = 'The queue has no members yet.';
        return i;
    }

    private static SetupItem detectManagers(SetupItem i, Ctx c) {
        if (c.approval != null && c.approval.Self_Approval_Enabled__c == true) return null;
        setupLink(i, 'users', 'Open Users');
        List<User> users = [
            SELECT Name FROM User
            WHERE IsActive = true AND ManagerId = null
              AND Id IN (SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSet.Name = :PS_USER)
            ORDER BY Name LIMIT 200
        ];
        if (users.isEmpty()) return done(i, 'Every rep has a manager.');
        List<String> names = new List<String>();
        for (Integer k = 0; k < users.size() && k < 5; k++) names.add(users[k].Name);
        i.status = STATUS_TODO;
        i.detail = users.size() + (users.size() >= 200 ? '+' : '') + ' rep(s) have no manager, for example: '
            + String.join(names, ', ') + '.';
        return i;
    }

    private static SetupItem detectJobs(SetupItem i, Ctx c) {
        Integer scheduled = 0;
        List<GtmScheduledJobsController.JobStatus> statuses = GtmScheduledJobsController.getStatuses();
        for (GtmScheduledJobsController.JobStatus js : statuses) {
            if (js.isScheduled == true) scheduled++;
        }
        if (!statuses.isEmpty() && scheduled == statuses.size()) {
            return done(i, 'Both purge jobs are scheduled.');
        }
        i.status = STATUS_TODO;
        i.detail = scheduled + ' of ' + statuses.size() + ' purge jobs are scheduled.';
        i.actionType = ACTION_SCHEDULE_JOBS; i.actionLabel = 'Schedule jobs';
        return i;
    }

    private static SetupItem detectMembers(SetupItem i, Ctx c) {
        setupLink(i, 'all_sites', 'Open site members');
        if (!c.networksReadable || c.site == null) {
            i.status = STATUS_UNKNOWN;
            i.detail = 'The site could not be identified, so its members could not be counted.';
            return i;
        }
        Id netId = c.site.Id;
        Integer n = [SELECT COUNT() FROM NetworkMember WHERE NetworkId = :netId];
        if (n > 0) return done(i, plural(n, 'member', 'members') + ' on the site.');
        i.status = STATUS_TODO;
        i.detail = 'The site has no members yet.';
        return i;
    }

    /**
     * Issue #38: the specific "SDO Service - Case - On Create" demo flow
     * (`SDO_Service_Case_Creation`) requires a `helperConfig` input variable
     * no Apex insert ever supplies, so an active copy of it silently blocks
     * every Case insert with CANNOT_EXECUTE_FLOW_TRIGGER (fileReviewCase's
     * own try/catch swallows this into a debug log only -- see
     * docs/runbooks/fresh-org-deploy.md item 15). Scoped to this one
     * confirmed flow by design, not a generic "any SDO flow" scan -- a
     * fresh/CI org never carries the SDO demo bundle at all, so the
     * "absent -> DONE" branch is the only one an automated test can prove;
     * the "active -> TODO" branch needs a live org that actually ships the
     * bundle (see GtmSetupChecklistControllerTest's comment on this row).
     */
    private static SetupItem detectSdoDemoFlow(SetupItem i, Ctx c) {
        setupLink(i, 'flows', 'Open Flows');
        List<FlowDefinitionView> rows;
        try {
            rows = [
                SELECT Id, IsActive FROM FlowDefinitionView
                WHERE ApiName = :SDO_FLOW_API_NAME
                LIMIT 1
            ];
        } catch (Exception e) {
            return unknown(specFor(i));
        }
        if (rows.isEmpty() || rows[0].IsActive != true) {
            return done(i, 'The SDO Service demo flow (' + SDO_FLOW_API_NAME + ') is absent or inactive.');
        }
        i.status = STATUS_TODO;
        i.detail = 'The SDO Service demo flow (' + SDO_FLOW_API_NAME + ') is active and blocks every Case '
            + 'insert with CANNOT_EXECUTE_FLOW_TRIGGER. Deactivate it in Setup > Flows.';
        return i;
    }

    /**
     * Issue #38: GTM_Agent_Settings__c.Agentforce_Agent_Id__c is a non-secret
     * identifier (see GtmAgentSettingsController's header). "Active" is not a
     * field on BotDefinition itself -- it is tracked on the related
     * BotVersion row's Status ('Active'/'Draft'/etc; live-confirmed in
     * docs/architecture/gus-chat-provider-settings.md), so resolution here
     * means "at least one Active BotVersion for this BotDefinitionId", not a
     * field read directly off BotDefinition. A set-but-malformed Id (fails
     * the (Id) cast) is treated the same as a set-but-non-resolving Id: both
     * are BLOCKED with blockedBy left null on purpose -- this is a dangling
     * external reference, not an unmet prerequisite on another checklist row
     * (matching the existing null-blockedBy precedent in detectSiteActive's
     * "no site exists" branch and detectQueue's "queue not deployed" branch).
     * UNKNOWN is reserved for a read that could not be attempted at all.
     */
    private static SetupItem detectAgentforceAgent(SetupItem i, Ctx c) {
        sectionLink(i, 'claude-gus', 'Open GUS settings');
        GtmAgentSettingsController.AgentSettingsDto d = GtmAgentSettingsController.getAgentSettings();
        String agentId = d != null ? d.agentforceAgentId : null;
        if (String.isBlank(agentId)) {
            i.status = STATUS_TODO;
            i.detail = 'No Agentforce Agent Id is set yet.';
            return i;
        }
        Id botId;
        try {
            botId = (Id) agentId;
        } catch (Exception e) {
            botId = null;
        }
        if (botId == null) {
            return blocked(i, 'The Agentforce Agent Id is set but is not a valid record Id, so it cannot '
                + 'resolve to a real agent. Confirm the Id in Setup > Agentforce Studio > Agentforce Agents.', null);
        }
        Integer activeVersions;
        try {
            activeVersions = [SELECT COUNT() FROM BotVersion WHERE BotDefinitionId = :botId AND Status = 'Active'];
        } catch (Exception e) {
            return unknown(specFor(i));
        }
        if (activeVersions >= 1) {
            return done(i, 'The Agentforce Agent Id resolves to an active agent.');
        }
        return blocked(i, 'The Agentforce Agent Id is set but does not resolve to an active agent. Confirm the '
            + 'Id in Setup > Agentforce Studio > Agentforce Agents.', null);
    }

    private static SetupItem detectPage(SetupItem i, String template) {
        navLink(i, 'GTM_Content_Manager', pageState(template), 'Open page');
        if (!Schema.GTM_Page_Content__c.SObjectType.getDescribe().isAccessible()) return unknown(specFor(i));
        Boolean found = false;
        for (GTM_Page_Content__c r : [
            SELECT Text_Value__c, Rich_Value__c, JSON_Value__c FROM GTM_Page_Content__c
            WHERE Offering_Key__c = :OWNER AND Template_Type__c = :template AND Active__c = true
            LIMIT 200
        ]) {
            if (isUsable(r.Text_Value__c) || isUsable(r.Rich_Value__c) || isUsable(r.JSON_Value__c)) {
                found = true; break;
            }
        }
        if (found) return done(i, 'Content has been added.');
        i.status = STATUS_NOT_SET;
        i.detail = 'Not set. Everything else works without it.';
        return i;
    }

    private static SetupItem detectDigest(SetupItem i, Ctx c) {
        sectionLink(i, 'analytics-notifications', 'Open Analytics settings');
        if (c.analytics != null && c.analytics.Notify_Weekly_Digest__c == true) {
            return done(i, 'The weekly digest is on.');
        }
        i.status = STATUS_NOT_SET;
        i.detail = 'Not set. Everything else works without it.';
        return i;
    }

    private static SetupItem detectAiKeys(SetupItem i) {
        sectionLink(i, 'claude-gus', 'Open GUS settings');
        GtmAgentSettingsController.AgentSettingsDto d = GtmAgentSettingsController.getAgentSettings();
        if (d != null && (d.hasApiKey == true || d.hasOpenAiApiKey == true || d.hasGeminiApiKey == true)) {
            return done(i, 'A provider key is set.');
        }
        i.status = STATUS_NOT_SET;
        i.detail = 'Not set. GUS chat is off, everything else works.';
        return i;
    }

    private static SetupItem detectApproval(SetupItem i, Ctx c) {
        sectionLink(i, 'approval-routing', 'Open approval routing');
        Boolean self = c.approval != null && c.approval.Self_Approval_Enabled__c == true;
        i.status = STATUS_INFO;
        i.detail = 'Current mode: ' + (self ? 'Self-approval.' : 'Manager approval.');
        return i;
    }

    private static SetupItem detectOfferingPages(SetupItem i, Ctx c) {
        navLink(i, 'GTM_Content_Home', null, 'Open Content Manager');
        loadOfferings(c);
        i.status = STATUS_INFO;
        if (c.offeringKeys.isEmpty()) {
            i.detail = 'No offerings yet.';
            return i;
        }
        Map<String, Set<String>> have = new Map<String, Set<String>>();
        for (AggregateResult ar : [
            SELECT Offering_Key__c k, Template_Type__c t, COUNT(Id) cnt FROM GTM_Page_Section__c
            WHERE Offering_Key__c IN :c.offeringKeys AND Template_Type__c IN ('story', 'configurator')
            GROUP BY Offering_Key__c, Template_Type__c
        ]) {
            String k = (String) ar.get('k');
            if (!have.containsKey(k)) have.put(k, new Set<String>());
            have.get(k).add((String) ar.get('t'));
        }
        Integer lacking = 0;
        for (String k : c.offeringKeys) {
            Set<String> h = have.get(k);
            if (h == null || !h.contains('story') || !h.contains('configurator')) lacking++;
        }
        i.detail = lacking == 0
            ? 'Every offering has its story and configurator pages.'
            : plural(lacking, 'offering has', 'offerings have') + ' no story or configurator page yet.';
        return i;
    }

    private static SetupItem detectOrgDx(SetupItem i, Ctx c) {
        setupLink(i, 'digital_experiences', 'Open Digital Experiences settings');
        i.status = STATUS_INFO;
        i.detail = (c.networksReadable && !c.networks.isEmpty())
            ? 'Digital Experiences appears to be enabled (a site exists).'
            : 'Could not confirm that Digital Experiences is enabled.';
        return i;
    }

    private static SetupItem staticInfo(SetupItem i, String detail, String pathKey, String label) {
        setupLink(i, pathKey, label);
        i.status = STATUS_INFO;
        i.detail = detail;
        return i;
    }
}
