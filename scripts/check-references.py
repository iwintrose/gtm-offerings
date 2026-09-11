#!/usr/bin/env python3
"""
Whole-app reference audit.

Answers "what would break if I removed this?" across EVERY metadata type that
can reference a component, not just the obvious ones. Written after deleting
four LWC bundles on the strength of a grep that covered only *.html and *.js
inside force-app/main/default/lwc - which cannot see a Custom Tab, a
FlexiPage, an Experience Cloud view, an app's nav, or a permission set.

Reports, per Lightning component and Apex class:
  - every place that references it, by metadata type
  - anything referenced but missing from source (a dangling pointer)
  - anything defined but referenced nowhere (a genuine orphan)

Extended when the org this was built in turned out to be expiring: the same
question ("what breaks?") asked of a whole fresh org rather than one component.
The second half of this file is a deployability audit -- it checks that every
grant, record, page, route, layout and seed row in this tree points at
something that is also in this tree, so that a deploy into an org that has
never seen this solution has nothing left to resolve. There is no `sf` CLI and
no org here; nothing below deploys or compiles anything. Every check is static.

Usage:  python3 scripts/check-references.py
        python3 scripts/check-references.py --inventory       # what is in the tree
        python3 scripts/check-references.py --list-blocking   # one line per
                                                                # deploy-blocking
                                                                # finding, sorted,
                                                                # for diffing two
                                                                # trees against
                                                                # each other
Exit:   0 = nothing found that would fail a deploy
        1 = at least one dangling reference or deploy-blocking problem
"""
import contextlib
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "force-app", "main", "default")


def kebab(name):
    """gtmStory -> gtm-story, so c-gtm-story is findable."""
    return re.sub(r"(?<!^)(?=[A-Z])", "-", name).lower()


def walk(root):
    for base, _dirs, files in os.walk(root):
        for f in files:
            yield os.path.join(base, f)


def metadata_kind(path):
    rel = os.path.relpath(path, SRC)
    top = rel.split(os.sep)[0]
    return {
        "lwc": "LWC",
        "aura": "Aura",
        "classes": "Apex",
        "tabs": "CustomTab",
        "applications": "App",
        "flexipages": "FlexiPage",
        "experiences": "ExperienceSite",
        "permissionsets": "PermissionSet",
        "profiles": "Profile",
        "objects": "Object",
        "flows": "Flow",
        "customMetadata": "CustomMetadata",
        "genAiPlugins": "GenAiPlugin",
        "bots": "Bot",
        "layouts": "Layout",
    }.get(top, top)


# ---------------------------------------------------------------------------
# DEPLOYABILITY AUDIT
#
# Added when the dev org this was built in turned out to be expiring, and the
# question became "can this repo rebuild the whole solution in a fresh org?".
# check-references.py already answered "what points at what" for LWCs and Apex.
# These passes answer the harder question: would a deploy of this tree, into an
# org that has never seen it, actually succeed -- and if it doesn't, which file
# is at fault. There is no `sf` CLI here and no org to try it against, so every
# check below is a static one, and each is written to catch a specific failure
# mode that has a real Salesforce error message behind it.
# ---------------------------------------------------------------------------
import xml.etree.ElementTree as ET

NS = "{http://soap.sforce.com/2006/04/metadata}"

# Standard objects this solution attaches to. A permission set or layout may
# reference these without a matching folder under objects/ -- they exist in
# every org. Anything NOT on this list and not ending __c/__mdt/__e is treated
# as suspicious, because a typo'd standard object name is a deploy failure that
# reads like a permissions problem.
STANDARD_OBJECTS = {
    "Account", "Contact", "Lead", "Opportunity", "Case", "CaseComment", "Task",
    "Event", "User", "Campaign", "CampaignMember", "Contract", "Product2",
    "Pricebook2", "Asset", "Order", "Quote", "Idea", "Solution", "Note",
    "Attachment", "ContentDocument", "ContentVersion", "ContentNote", "Report",
    "Dashboard", "Document", "Folder", "Group", "Queue", "Individual",
    # Queried from Apex in this repo but never extended by it, so they have no
    # objects/ folder. Listing them keeps section 14 from calling a perfectly
    # good SOQL FROM clause a dangling reference.
    "Profile", "PermissionSet", "PermissionSetAssignment", "RecordType",
    "ContentDocumentLink", "ContentWorkspace", "ProcessInstance",
    "ProcessInstanceWorkitem", "ProcessInstanceStep", "CronTrigger",
    "AsyncApexJob", "OpportunityContactRole", "UserRecordAccess", "Domain",
    "DomainSite", "EmailMessage", "Network", "Site", "Organization",
    "AggregateResult", "FeedItem", "PricebookEntry", "OpportunityLineItem",
    # The child-relationship name in ProcessInstance's Workitems subquery.
    "Workitems",
}

# The standard fields section 14 needs in order to tell "this SOQL selects a
# field that does not exist" from "this SOQL selects a stock field". Only the
# ones this repo's Apex actually touches; the list does not need to be complete
# to be useful, because anything missing surfaces as a reviewable finding rather
# than a silent pass.
STANDARD_FIELDS_BY_OBJECT = {
    "Case": {"Subject", "Description", "Status", "Origin", "SuppliedEmail",
             "SuppliedName", "ContactId", "AccountId", "CaseNumber", "Type",
             "Reason", "Priority", "IsClosed", "ClosedDate", "ParentId"},
    "Lead": {"FirstName", "LastName", "Company", "Email", "Phone", "Status",
             "Title", "Website", "LeadSource", "IsConverted",
             "ConvertedContactId", "ConvertedAccountId",
             "ConvertedOpportunityId", "Street", "City", "State", "PostalCode",
             "Country"},
    "Opportunity": {"AccountId", "Amount", "CloseDate", "StageName",
                    "Probability", "Type", "LeadSource", "IsClosed", "IsWon",
                    "Description", "NextStep", "Pricebook2Id", "ContactId",
                    "ForecastCategoryName"},
    "User": {"Username", "Email", "FirstName", "LastName", "Alias", "ProfileId",
             "UserRoleId", "IsActive", "TimeZoneSidKey", "LocaleSidKey",
             "EmailEncodingKey", "LanguageLocaleKey", "ContactId", "UserType",
             "CommunityNickname"},
}

# Fields Salesforce itself creates on Opportunity in a new org. They are spelled
# __c but they are not ours and are not in this repo -- a layout may place them
# and still deploy, PROVIDED the target org still has them. An admin who deleted
# them (or an org template that never made them) turns each into a deploy error,
# so they are a warning rather than a silent pass.
ORG_PROVISIONED_FIELDS = {
    "Opportunity": {"MainCompetitors__c", "CurrentGenerators__c", "OrderNumber__c",
                    "TrackingNumber__c", "DeliveryInstallationStatus__c"},
}

# Features whose standard tabs only exist when the feature is provisioned.
# Granting tab visibility on one of these in an org that lacks the licence is a
# hard deploy error ("In field: tab - no CustomTab named standard-X found"),
# and it is the single most likely way a first deploy into a plain org dies.
LICENCE_GATED_TAB_PREFIXES = (
    "standard-Data", "standard-Devops", "standard-Cms", "standard-Loyalty",
    "standard-Commerce", "standard-Einstein", "standard-Agentforce",
    "standard-Mfg", "standard-Fsc", "standard-Health", "standard-Clm",
    "standard-Prompt", "standard-Segment", "standard-Activation",
    "standard-Calculated", "standard-DataCloud", "standard-Audience",
)


def xml_root(path):
    return ET.parse(path).getroot()


def text_of(el):
    return (el.text or "").strip()


def audit(problems, warnings):
    """Every pass appends (file, message). problems block a deploy; warnings
    are things that deploy but will not work in a fresh org."""

    def P(where, msg):
        problems.append((os.path.relpath(where, ROOT) if os.path.isabs(where) else where, msg))

    def W(where, msg):
        warnings.append((os.path.relpath(where, ROOT) if os.path.isabs(where) else where, msg))

    # --- inventory ---------------------------------------------------------
    objects_dir = os.path.join(SRC, "objects")
    objects = {}          # API name -> set of field API names present in source
    for name in sorted(os.listdir(objects_dir)) if os.path.isdir(objects_dir) else []:
        odir = os.path.join(objects_dir, name)
        if not os.path.isdir(odir):
            continue
        fields = set()
        fdir = os.path.join(odir, "fields")
        if os.path.isdir(fdir):
            for f in os.listdir(fdir):
                if f.endswith(".field-meta.xml"):
                    fields.add(f[: -len(".field-meta.xml")])
        objects[name] = fields

    lwc_dir = os.path.join(SRC, "lwc")
    lwc_names = {d for d in os.listdir(lwc_dir) if os.path.isdir(os.path.join(lwc_dir, d))}
    apex_names = {f[:-4] for f in os.listdir(os.path.join(SRC, "classes")) if f.endswith(".cls")}
    tab_names = {f.split(".tab-meta.xml")[0] for f in os.listdir(os.path.join(SRC, "tabs"))} \
        if os.path.isdir(os.path.join(SRC, "tabs")) else set()
    app_names = {f.split(".app-meta.xml")[0] for f in os.listdir(os.path.join(SRC, "applications"))} \
        if os.path.isdir(os.path.join(SRC, "applications")) else set()
    flexi_names = {f.split(".flexipage-meta.xml")[0] for f in os.listdir(os.path.join(SRC, "flexipages"))} \
        if os.path.isdir(os.path.join(SRC, "flexipages")) else set()

    # =======================================================================
    # 1. Every file parses. A malformed XML or JSON file fails the deploy at
    #    the parse step with a message that names the file but not the reason.
    # =======================================================================
    section("1. FILE INTEGRITY (every XML parses, every JSON parses)")
    checked = 0
    for path in walk(SRC):
        if path.endswith(".xml"):
            checked += 1
            try:
                xml_root(path)
            except ET.ParseError as e:
                P(path, "malformed XML: %s" % e)
        elif path.endswith(".json"):
            checked += 1
            try:
                with open(path, encoding="utf-8") as fh:
                    json.load(fh)
            except (ValueError, OSError) as e:
                P(path, "malformed JSON: %s" % e)
    for path in walk(os.path.join(ROOT, "data")):
        if path.endswith(".json"):
            checked += 1
            try:
                with open(path, encoding="utf-8") as fh:
                    json.load(fh)
            except (ValueError, OSError) as e:
                P(path, "malformed JSON: %s" % e)
    print("  %d XML/JSON files parsed" % checked)

    # =======================================================================
    # 2. Companion files. Apex without its -meta.xml is invisible to the
    #    deploy; a -meta.xml without its body is a hard error.
    # =======================================================================
    section("2. COMPANION FILES (.cls/.trigger/LWC each need their -meta.xml)")
    pairs = 0
    for sub, ext in (("classes", ".cls"), ("triggers", ".trigger")):
        d = os.path.join(SRC, sub)
        if not os.path.isdir(d):
            continue
        bodies = {f for f in os.listdir(d) if f.endswith(ext)}
        metas = {f for f in os.listdir(d) if f.endswith(ext + "-meta.xml")}
        for b in sorted(bodies):
            pairs += 1
            if b + "-meta.xml" not in metas:
                P(os.path.join(d, b), "has no %s-meta.xml -- it will not deploy" % ext)
        for m in sorted(metas):
            if m[: -len("-meta.xml")] not in bodies:
                P(os.path.join(d, m), "meta file with no %s body" % ext)
    for name in sorted(lwc_names):
        bdir = os.path.join(lwc_dir, name)
        files = os.listdir(bdir)
        pairs += 1
        if name + ".js" not in files:
            P(bdir, "LWC bundle has no %s.js" % name)
        if name + ".js-meta.xml" not in files:
            P(bdir, "LWC bundle has no %s.js-meta.xml -- it will not deploy" % name)
        # An .html with no matching .js, or a bundle whose folder name and file
        # names disagree, is the other half of the same mistake.
        for f in files:
            if f.endswith((".js", ".html", ".css")) and not f.startswith(name) \
                    and not f.startswith("__"):
                W(os.path.join(bdir, f), "file name does not match its bundle "
                  "'%s' -- only files named after the bundle are entry points" % name)
    print("  %d Apex/trigger/LWC bundles checked" % pairs)

    # =======================================================================
    # 3. Object and field definitions. A field file whose <fullName> disagrees
    #    with its filename deploys under the filename and silently is not the
    #    field everything else references.
    # =======================================================================
    section("3. OBJECTS AND FIELDS (fullName matches filename, types resolve)")
    for obj, fields in sorted(objects.items()):
        for fld in sorted(fields):
            path = os.path.join(objects_dir, obj, "fields", fld + ".field-meta.xml")
            try:
                r = xml_root(path)
            except ET.ParseError:
                continue
            fn = r.find(NS + "fullName")
            if fn is None:
                P(path, "field has no <fullName>")
            elif text_of(fn) != fld:
                P(path, "<fullName> is '%s' but the filename says '%s'"
                  % (text_of(fn), fld))
            # A master-detail/lookup pointing at an object that is neither
            # standard nor in this repo cannot deploy.
            ref = r.find(NS + "referenceTo")
            if ref is not None:
                t = text_of(ref)
                if t not in objects and t not in STANDARD_OBJECTS:
                    P(path, "looks up to '%s', which is neither a standard object "
                      "nor defined in this repo" % t)
    print("  %d objects, %d custom fields"
          % (len(objects), sum(len(v) for v in objects.values())))

    # =======================================================================
    # 4. Permission sets and profiles. This is where a fresh-org deploy most
    #    often dies: a grant on a class, field, object, tab or app that the
    #    target org has never heard of.
    # =======================================================================
    section("4. PERMISSION SETS AND PROFILES (every grant resolves in source)")
    for sub, kind in (("permissionsets", "permission set"), ("profiles", "profile")):
        d = os.path.join(SRC, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            path = os.path.join(d, f)
            if kind == "profile":
                # A profile deploy is a merge into a profile every user in the
                # org already sits on, and the standard profiles here exist in
                # every org under the same name -- so this lands whether or not
                # anyone meant it to.
                W(path, "is a standard profile. Deploying it changes a profile "
                  "the target org's own users are already on. Prefer granting "
                  "the same access through a permission set and leaving "
                  "profiles/ out of the deploy entirely.")
            try:
                r = xml_root(path)
            except ET.ParseError:
                continue
            for el in r.iter(NS + "apexClass"):
                if text_of(el) not in apex_names:
                    P(path, "grants Apex class '%s', which is not in source" % text_of(el))
            for el in r.iter(NS + "object"):
                o = text_of(el)
                if o in objects or o in STANDARD_OBJECTS:
                    continue
                if "__" in o and not o.endswith(("__c", "__mdt", "__e", "__b", "__x")):
                    W(path, "object permission on '%s' looks namespaced -- it "
                      "belongs to a package that must be installed first" % o)
                elif o.endswith(("__c", "__mdt", "__e")):
                    P(path, "object permission on '%s', which is not in source" % o)
                else:
                    W(path, "object permission on non-standard-looking object '%s'" % o)
            for el in r.iter(NS + "field"):
                ref = text_of(el)
                if "." not in ref:
                    continue
                obj, fld = ref.split(".", 1)
                if obj not in objects:
                    if obj not in STANDARD_OBJECTS:
                        W(path, "field permission on '%s' -- object not in source" % ref)
                    elif fld.endswith("__c"):
                        P(path, "field permission on '%s': custom field on a "
                          "standard object, but no such field is in source" % ref)
                    continue
                if fld.endswith("__c") and fld not in objects[obj]:
                    P(path, "field permission on '%s', which is not in source" % ref)
            for el in r.iter(NS + "name"):
                # customMetadataTypeAccesses/<name>
                v = text_of(el)
                if v.endswith("__mdt") and v not in objects:
                    P(path, "grants custom metadata type '%s', which is not in source" % v)
            for el in r.iter(NS + "application"):
                a = text_of(el)
                if a not in app_names and not a.startswith("standard__"):
                    P(path, "grants app '%s', which is not in source" % a)
            for el in r.iter(NS + "tab"):
                t = text_of(el)
                if t in tab_names:
                    continue
                if "__" in t and not t.startswith("standard-"):
                    P(path, "grants tab '%s' from a managed package namespace -- "
                      "this deploys only into an org that already has that "
                      "package installed" % t)
                elif t.startswith(LICENCE_GATED_TAB_PREFIXES):
                    W(path, "grants '%s': a standard tab that only exists when "
                      "the matching feature/licence is provisioned" % t)
                elif not t.startswith("standard-"):
                    P(path, "grants tab '%s', which is not in source" % t)

    # =======================================================================
    # 5. Custom metadata records. The type must be in source, and every
    #    <field> in a record must exist on that type -- a record naming a field
    #    the type does not have fails the whole customMetadata pass.
    # =======================================================================
    section("5. CUSTOM METADATA RECORDS (type exists, every field exists, "
            "DeveloperName is legal)")
    cmdt_dir = os.path.join(SRC, "customMetadata")
    rec_count = 0
    double_underscore = []
    if os.path.isdir(cmdt_dir):
        for f in sorted(os.listdir(cmdt_dir)):
            if not f.endswith(".md-meta.xml"):
                continue
            rec_count += 1
            path = os.path.join(cmdt_dir, f)
            stem = f[: -len(".md-meta.xml")]
            if "." not in stem:
                P(path, "filename must be <Type>.<RecordName>.md-meta.xml")
                continue
            type_name, dev_name = stem.split(".", 1)
            mdt = type_name + "__mdt"
            if mdt not in objects:
                P(path, "record of type '%s', whose type is not in source" % mdt)
                continue
            # DeveloperName legality. Salesforce documents DeveloperName as
            # letters/digits/underscore, starting with a letter, no trailing
            # underscore and no two consecutive underscores.
            if not re.match(r"^[A-Za-z][A-Za-z0-9_]*$", dev_name) or dev_name.endswith("_"):
                P(path, "'%s' is not a usable DeveloperName" % dev_name)
            elif "__" in dev_name:
                # Collected rather than reported per file: there are two dozen
                # of them, they are all the same decision, and twenty-four
                # copies of one warning is how a runbook reader learns to skim.
                double_underscore.append(dev_name)
            try:
                r = xml_root(path)
            except ET.ParseError:
                continue
            for v in r.iter(NS + "values"):
                fe = v.find(NS + "field")
                if fe is None:
                    P(path, "a <values> block has no <field>")
                    continue
                fld = text_of(fe)
                if fld not in objects[mdt]:
                    P(path, "sets field '%s', which %s does not define" % (fld, mdt))
    print("  %d custom metadata records" % rec_count)
    if double_underscore:
        W("force-app/main/default/customMetadata/",
          "%d records have a DeveloperName containing consecutive underscores "
          "(%s, ...), which Salesforce documents as disallowed. Nothing in this "
          "repo has ever been deployed to a real org, so it is unproven in both "
          "directions -- the GTM_Migration_Pair 'precedent' was written in the "
          "same unverified batch. If the customMetadata pass of a deploy is "
          "rejected on a DeveloperName, run scripts/rename-pair-keys.py --apply "
          "then scripts/build-instrument.py. See docs/runbooks/fresh-org-deploy.md."
          % (len(double_underscore), ", ".join(sorted(double_underscore)[:3])))

    # =======================================================================
    # 6. FlexiPages, tabs and apps.
    # =======================================================================
    section("6. FLEXIPAGES / TABS / APPS (every component and target exists)")
    fdir = os.path.join(SRC, "flexipages")
    for f in sorted(os.listdir(fdir)) if os.path.isdir(fdir) else []:
        path = os.path.join(fdir, f)
        try:
            r = xml_root(path)
        except ET.ParseError:
            continue
        for el in r.iter(NS + "componentName"):
            c = text_of(el)
            if ":" in c:
                ns, name = c.split(":", 1)
                if ns == "c" and name not in lwc_names:
                    P(path, "uses c:%s, which is not an LWC in source" % name)
            elif c not in lwc_names and not c.startswith(("flexipage", "force", "runtime")):
                P(path, "uses component '%s', which is not an LWC in source" % c)
        for el in r.iter(NS + "sobjectType"):
            o = text_of(el)
            if o not in objects and o not in STANDARD_OBJECTS:
                P(path, "is a record page for '%s', which is not in source" % o)
    tdir = os.path.join(SRC, "tabs")
    for f in sorted(os.listdir(tdir)) if os.path.isdir(tdir) else []:
        path = os.path.join(tdir, f)
        try:
            r = xml_root(path)
        except ET.ParseError:
            continue
        name = f.split(".tab-meta.xml")[0]
        for el in r.iter(NS + "lwcComponent"):
            if text_of(el) not in lwc_names:
                P(path, "points at LWC '%s', which is not in source" % text_of(el))
        for el in r.iter(NS + "flexiPage"):
            if text_of(el) not in flexi_names:
                P(path, "points at FlexiPage '%s', which is not in source" % text_of(el))
        if r.find(NS + "customObject") is not None and name not in objects:
            P(path, "is an object tab for '%s', which is not in source" % name)
    adir = os.path.join(SRC, "applications")
    for f in sorted(os.listdir(adir)) if os.path.isdir(adir) else []:
        path = os.path.join(adir, f)
        try:
            r = xml_root(path)
        except ET.ParseError:
            continue
        for el in r.iter(NS + "tabs"):
            t = text_of(el)
            if t.startswith("standard-") or t in tab_names:
                continue
            P(path, "navigation includes tab '%s', which is not in source" % t)

    # =======================================================================
    # 7. Experience Cloud. Every route names a view; every view that draws an
    #    LWC must name one that exists.
    # =======================================================================
    section("7. EXPERIENCE CLOUD SITES (routes -> views -> components)")
    edir = os.path.join(SRC, "experiences")
    for site in sorted(os.listdir(edir)) if os.path.isdir(edir) else []:
        sdir = os.path.join(edir, site)
        if not os.path.isdir(sdir):
            continue
        vdir, rdir = os.path.join(sdir, "views"), os.path.join(sdir, "routes")
        views = {f[:-5] for f in os.listdir(vdir)} if os.path.isdir(vdir) else set()
        for f in sorted(os.listdir(rdir)) if os.path.isdir(rdir) else []:
            path = os.path.join(rdir, f)
            try:
                with open(path, encoding="utf-8") as fh:
                    data = json.load(fh)
            except ValueError:
                continue
            v = data.get("viewType") or data.get("view")
            if v and v not in views:
                P(path, "route renders view '%s', which has no file under "
                  "%s/views/" % (v, site))
        for f in sorted(os.listdir(vdir)) if os.path.isdir(vdir) else []:
            path = os.path.join(vdir, f)
            try:
                with open(path, encoding="utf-8") as fh:
                    raw = fh.read()
                json.loads(raw)
            except ValueError:
                continue
            for name in set(re.findall(r'"componentName"\s*:\s*"c:(\w+)"', raw)):
                if name not in lwc_names:
                    P(path, "draws c:%s, which is not an LWC in source" % name)
        # The bundle carries no Network. Deploying an ExperienceBundle into an
        # org that has no site of that name fails -- the site has to be created
        # by hand first. Say so once per site rather than leaving it to be
        # discovered at deploy time.
        W(os.path.join(edir, site + ".site-meta.xml"),
          "ExperienceBundle only. There is no Network/CustomSite metadata in "
          "this repo, so the site itself must be created by hand in the target "
          "org (Setup > Digital Experiences > New Site, Build Your Own) BEFORE "
          "this deploys, and published by hand AFTER.")

    # =======================================================================
    # 8. Approval process, workflow and queue -- the readout review chain.
    # =======================================================================
    section("8. APPROVAL CHAIN (approval actions, field updates, queue targets)")
    wf_updates = {}
    wdir = os.path.join(SRC, "workflows")
    for f in sorted(os.listdir(wdir)) if os.path.isdir(wdir) else []:
        obj = f.split(".workflow-meta.xml")[0]
        path = os.path.join(wdir, f)
        try:
            r = xml_root(path)
        except ET.ParseError:
            continue
        if obj not in objects and obj not in STANDARD_OBJECTS:
            P(path, "workflow on '%s', which is not in source" % obj)
        for fu in r.iter(NS + "fieldUpdates"):
            nm = fu.find(NS + "fullName")
            fld = fu.find(NS + "field")
            if nm is not None:
                wf_updates[text_of(nm)] = obj
            if fld is not None and obj in objects and text_of(fld).endswith("__c") \
                    and text_of(fld) not in objects[obj]:
                P(path, "field update writes '%s.%s', which is not in source"
                  % (obj, text_of(fld)))
    adir2 = os.path.join(SRC, "approvalProcesses")
    for f in sorted(os.listdir(adir2)) if os.path.isdir(adir2) else []:
        path = os.path.join(adir2, f)
        obj = f.split(".")[0]
        try:
            r = xml_root(path)
        except ET.ParseError:
            continue
        if obj not in objects and obj not in STANDARD_OBJECTS:
            P(path, "approval process on '%s', which is not in source" % obj)
        for act in r.iter(NS + "action"):
            nm, ty = act.find(NS + "name"), act.find(NS + "type")
            if nm is None:
                continue
            if ty is not None and text_of(ty) == "FieldUpdate" \
                    and text_of(nm) not in wf_updates:
                P(path, "references field update '%s', which no workflow in "
                  "source defines -- workflows/ must deploy before this"
                  % text_of(nm))
        for fe in r.iter(NS + "field"):
            fld = text_of(fe)
            if obj in objects and fld.endswith("__c") and fld not in objects[obj]:
                P(path, "approval page field '%s.%s' is not in source" % (obj, fld))
        if r.find(NS + "active") is not None and text_of(r.find(NS + "active")) == "true":
            W(path, "deploys ACTIVE. An active approval process cannot be "
              "deleted or have its steps edited without deactivating first.")
    qdir = os.path.join(SRC, "queues")
    for f in sorted(os.listdir(qdir)) if os.path.isdir(qdir) else []:
        path = os.path.join(qdir, f)
        try:
            r = xml_root(path)
        except ET.ParseError:
            continue
        for el in r.iter(NS + "sobjectType"):
            o = text_of(el)
            if o not in objects and o not in STANDARD_OBJECTS:
                P(path, "queue serves '%s', which is not in source" % o)
        W(path, "queue MEMBERSHIP is org state, not metadata -- the queue "
          "deploys empty and nobody is in it until somebody is added by hand.")

    # =======================================================================
    # 9. Layouts and list views.
    # =======================================================================
    section("9. LAYOUTS AND LIST VIEWS (every field on them exists)")
    ldir = os.path.join(SRC, "layouts")
    for f in sorted(os.listdir(ldir)) if os.path.isdir(ldir) else []:
        path = os.path.join(ldir, f)
        obj = f.split("-")[0]
        try:
            r = xml_root(path)
        except ET.ParseError:
            continue
        if obj not in objects and obj not in STANDARD_OBJECTS:
            P(path, "layout for '%s', which is not in source" % obj)
            continue
        known = objects.get(obj, set())
        provisioned = ORG_PROVISIONED_FIELDS.get(obj, set())
        for el in r.iter(NS + "field"):
            fld = text_of(el)
            if not fld.endswith("__c") or fld in known:
                continue
            if fld in provisioned:
                W(path, "places '%s.%s', a field Salesforce provisions in a new "
                  "org rather than one this repo defines -- fine in a stock org, "
                  "a deploy error in one where it was deleted" % (obj, fld))
            elif obj in objects:
                P(path, "places '%s.%s', which is not in source" % (obj, fld))
            else:
                W(path, "places '%s.%s' on a standard object; the field is not "
                  "in source, so the target org must already have it" % (obj, fld))
        # A whole layout for a standard object REPLACES that org's layout. In a
        # dedicated org that is what you want; in a shared org it silently
        # discards whatever anyone else had on it.
        if obj not in objects:
            W(path, "is a complete layout for the standard object '%s'. "
              "Deploying it REPLACES the target org's own layout. In a shared "
              "org, add the fields to the existing layout by hand instead of "
              "deploying this file." % obj)
    for obj, fields in sorted(objects.items()):
        lvdir = os.path.join(objects_dir, obj, "listViews")
        for f in sorted(os.listdir(lvdir)) if os.path.isdir(lvdir) else []:
            path = os.path.join(lvdir, f)
            try:
                r = xml_root(path)
            except ET.ParseError:
                continue
            for el in list(r.iter(NS + "columns")) + list(r.iter(NS + "field")):
                fld = text_of(el)
                if fld.endswith("__c") and fld not in fields:
                    P(path, "column '%s' is not a field on %s in source" % (fld, obj))

    # =======================================================================
    # 10. Seed data. `sf data tree` files must name objects and fields that
    #     exist, or the import fails halfway and leaves the org part-seeded.
    # =======================================================================
    section("10. SEED DATA (data/seed/*.json -> objects and fields in source)")
    seed_dir = os.path.join(ROOT, "data", "seed")
    seed_recs = 0
    for f in sorted(os.listdir(seed_dir)) if os.path.isdir(seed_dir) else []:
        if not f.endswith(".json"):
            continue
        path = os.path.join(seed_dir, f)
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except ValueError:
            continue
        for rec in data.get("records", []):
            seed_recs += 1
            obj = rec.get("attributes", {}).get("type")
            if obj is None:
                P(path, "a record has no attributes.type")
                continue
            if obj not in objects and obj not in STANDARD_OBJECTS:
                P(path, "seeds '%s', which is not in source" % obj)
                continue
            for k in rec:
                if k == "attributes":
                    continue
                if k.endswith("__c") and obj in objects and k not in objects[obj]:
                    P(path, "sets %s.%s, which is not in source" % (obj, k))
    print("  %d seed records" % seed_recs)

    # =======================================================================
    # 11. Deploy coverage. Every directory under force-app has to be named by
    #     the deploy script, or it silently never reaches the org -- which is
    #     indistinguishable, in the target org, from never having been built.
    # =======================================================================
    section("11. DEPLOY COVERAGE (every source directory is actually deployed)")
    present = {d for d in os.listdir(SRC) if os.path.isdir(os.path.join(SRC, d))}
    covered = set()
    for script in ("deploy.sh", "deploy-fresh-org.sh"):
        sp = os.path.join(ROOT, "scripts", script)
        if not os.path.isfile(sp):
            continue
        with open(sp, encoding="utf-8") as fh:
            body = fh.read()
        # Four spellings, because the deploy scripts write it four ways: a
        # literal path, a $SRC-relative path, a bare directory name in the
        # argument list of the deploy() helper, or a `for d in
        # force-app/main/default/*/` loop that enumerates every directory at
        # deploy time rather than naming them one by one -- in which case
        # everything present is covered except whatever the loop body itself
        # excludes by name (e.g. `if [ "$name" != "customMetadata" ]`).
        covered |= set(re.findall(r"force-app/main/default/(\w+)", body))
        covered |= set(re.findall(r"\$SRC/(\w+)", body))
        if "force-app/main/default/*/" in body:
            excluded = set(re.findall(r'!=\s*"(\w+)"', body))
            covered |= present - excluded
        for line in body.splitlines():
            m = re.match(r'\s*deploy "[^"]*"(.*)$', line)
            if m:
                covered |= {w for w in m.group(1).split() if w in present}
            # continuation line of a deploy() call: a line that is nothing
            # but source directory names
            elif line.strip() and all(w in present for w in line.split()):
                covered |= set(line.split())
    missing = sorted(present - covered)
    for d in missing:
        P("scripts/", "force-app/main/default/%s/ is in source but no deploy "
          "script deploys it -- it would never reach a fresh org" % d)
    print("  %d source directories, %d covered by a deploy script"
          % (len(present), len(present & covered)))

    # =======================================================================
    # 12. Org-specific values. Nothing here may carry this dev org's identity.
    # =======================================================================
    section("12. ORG-SPECIFIC VALUES AND SECRETS (nothing org-bound in source)")
    ID_RE = re.compile(r"\b(?:001|003|005|006|00D|00e|00G|00Q|0ap|500|00N)"
                       r"[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?\b")
    URL_RE = re.compile(r"https://[\w.-]*(?:my\.salesforce\.com|my\.site\.com|"
                        r"lightning\.force\.com|develop\.my\.)[\w./-]*")
    KEY_RE = re.compile(r"\b(?:sk-ant-[\w-]{10,}|AKIA[0-9A-Z]{16}|"
                        r"xox[baprs]-[\w-]{10,}|gh[pousr]_[A-Za-z0-9]{20,})")
    scan_roots = [SRC, os.path.join(ROOT, "data"), os.path.join(ROOT, "scripts"),
                  os.path.join(ROOT, "docs"), os.path.join(ROOT, "instrument"),
                  os.path.join(ROOT, "reference")]
    scan_files = []
    for rt in scan_roots:
        if os.path.isdir(rt):
            scan_files += [p for p in walk(rt) if p.endswith(
                (".xml", ".json", ".js", ".html", ".cls", ".css", ".md", ".py",
                 ".sh", ".yaml", ".yml", ".trigger", ".apex"))]
    for p in sorted(set(scan_files) | {os.path.join(ROOT, f) for f in os.listdir(ROOT)
                                       if f.endswith(".md")}):
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding="utf-8") as fh:
                text = fh.read()
        except (UnicodeDecodeError, OSError):
            continue
        rel = os.path.relpath(p, ROOT)
        for m in sorted(set(KEY_RE.findall(text))):
            # Apex tests have to put SOMETHING in the key field. A value that
            # says out loud that it is not a key is not one.
            if re.search(r"test|fake|dummy|placeholder|not[-_]real|example", m, re.I):
                continue
            P(rel, "contains what looks like a live API key/token (%s...)" % m[:12])
        for m in sorted(set(ID_RE.findall(text))):
            # Apex tests mint fake ids; those are fine and are not org identity.
            if rel.endswith("Test.cls") or "__tests__" in rel:
                continue
            P(rel, "contains a hardcoded Salesforce record id '%s' -- it names a "
              "record in the org it was written against and is wrong in any "
              "other org" % m)
        for m in sorted(set(URL_RE.findall(text))):
            W(rel, "contains the org-specific URL '%s' -- it must become a "
              "post-deploy configuration step, not a committed value" % m)

    # =======================================================================
    # 13. Apex syntax gates. Apex has no local compiler -- it compiles
    #     server-side, on deploy, against an org. Everything below is a fault
    #     a parser finds and a deploy would otherwise be the first thing to
    #     tell you about. Both classes here were found in blind-written code
    #     on this branch and cost a deploy each.
    # =======================================================================
    section("13. APEX SYNTAX (no double-quoted strings, no reserved identifiers)")

    # Apex string literals are single-quoted only. A '"' that survives after
    # comments and single-quoted literals are removed is a syntax error, not a
    # style preference.
    def apex_blank(src):
        """Comments and string literals replaced by spaces, length preserved,
        so offsets and line numbers still line up with the original."""
        out, i, n = [], 0, len(src)
        while i < n:
            c = src[i]
            if c == "'":
                out.append(" ")
                i += 1
                while i < n:
                    if src[i] == "\\":
                        out.append("  ")
                        i += 2
                        continue
                    if src[i] == "'":
                        out.append(" ")
                        i += 1
                        break
                    out.append("\n" if src[i] == "\n" else " ")
                    i += 1
                continue
            if src.startswith("//", i):
                while i < n and src[i] != "\n":
                    out.append(" ")
                    i += 1
                continue
            if src.startswith("/*", i):
                j = src.find("*/", i + 2)
                j = n if j < 0 else j + 2
                out.append(re.sub(r"[^\n]", " ", src[i:j]))
                i = j
                continue
            out.append(c)
            i += 1
        return "".join(out)

    # Determined empirically against PMD 7.7.0's Apex grammar: each of these
    # fails to parse in method-name, variable-name and parameter-name
    # position. Deliberately does NOT include the SOQL-ish soft keywords
    # (system, select, from, where, group, limit, offset, like, in, not, and,
    # or, with, without, sharing, when, switch, transient, trigger, get, set,
    # user, data), all of which Apex does accept as identifiers.
    APEX_RESERVED = {
        "abstract", "break", "catch", "class", "continue", "delete", "do",
        "else", "enum", "extends", "false", "final", "finally", "for",
        "global", "if", "implements", "insert", "interface", "list", "map",
        "merge", "new", "null", "on", "override", "private", "public",
        "return", "static", "super", "testmethod", "this", "throw", "true",
        "try", "undelete", "update", "upsert", "virtual", "void", "webservice",
        "while",
    }
    DECL_RE = re.compile(
        r"(?:^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*"
        r"(?:(?:public|private|global|protected|static|virtual|abstract|"
        r"override|final|transient|webservice|testmethod)\s+)+"
        r"[A-Za-z_][\w.]*(?:\s*<[^;{}()]*>)?(?:\s*\[\s*\])?\s+"
        r"([A-Za-z_]\w*)\s*[({=;])",
        re.M,
    )
    apex_files = []
    for sub, ext in (("classes", ".cls"), ("triggers", ".trigger")):
        d = os.path.join(SRC, sub)
        if os.path.isdir(d):
            apex_files += [os.path.join(d, f) for f in sorted(os.listdir(d))
                           if f.endswith(ext)]
    for path in apex_files:
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
        except (UnicodeDecodeError, OSError):
            continue
        blanked = apex_blank(raw)
        for m in re.finditer(r'"', blanked):
            P(path, "line %d: double-quoted string literal. Apex string "
                    "literals are single-quoted; write '...' and escape any "
                    "inner quote as \\'. This does not compile."
              % (blanked[:m.start()].count("\n") + 1))
            break   # one report per file is enough to fail the build
        for m in DECL_RE.finditer(blanked):
            name = m.group(1)
            if name.lower() in APEX_RESERVED:
                P(path, "line %d: '%s' is a reserved word in Apex and cannot "
                        "be used as an identifier. This does not compile."
                  % (blanked[:m.start()].count("\n") + 1, name))
    print("  %d Apex files scanned for syntax faults a deploy would reject"
          % len(apex_files))

    # =======================================================================
    # 14. Apex/LWC symbol resolution. A parser cannot see any of this, and
    #     neither can a JS test: it is all resolved server-side at deploy, or
    #     at runtime against the org schema. These are the faults blind-written
    #     Apex actually ships -- a field queried that is not on the object, a
    #     field read that was never SELECTed, an LWC sending a parameter name
    #     the Apex method does not have.
    # =======================================================================
    section("14. APEX/LWC SYMBOLS (fields, relationships, @AuraEnabled bindings)")

    NSM = NS
    STD_FIELDS = {
        "Id", "Name", "CreatedDate", "CreatedById", "LastModifiedDate",
        "LastModifiedById", "OwnerId", "IsDeleted", "SystemModstamp",
        "CurrencyIsoCode", "RecordTypeId", "DeveloperName", "MasterLabel",
        "Label", "NamespacePrefix", "QualifiedApiName", "Language",
        "IsProtected",
    }
    parent_rel, child_rel, picklists, custom_settings = {}, {}, {}, set()
    for obj in objects:
        odir = os.path.join(objects_dir, obj)
        ometa = os.path.join(odir, obj + ".object-meta.xml")
        if os.path.isfile(ometa):
            try:
                with open(ometa, encoding="utf-8") as fh:
                    if "customSettingsType" in fh.read():
                        custom_settings.add(obj)
            except (UnicodeDecodeError, OSError):
                pass
        for fld in objects[obj]:
            fpath = os.path.join(odir, "fields", fld + ".field-meta.xml")
            try:
                r = xml_root(fpath)
            except (ET.ParseError, OSError):
                continue
            ftype = r.find(NSM + "type")
            if ftype is not None and text_of(ftype) in ("Lookup", "MasterDetail"):
                # Traversing child -> parent uses the FIELD name minus __c.
                # <relationshipName> is the other direction (parent -> children,
                # in a subquery) and is not interchangeable with it.
                parent_rel.setdefault(
                    (fld[:-3] if fld.endswith("__c") else fld) + "__r", []).append(obj)
                rn = r.find(NSM + "relationshipName")
                if rn is not None:
                    child_rel.setdefault(text_of(rn) + "__r", []).append(obj)
            vs = r.find(NSM + "valueSet")
            if vs is not None:
                vals = {text_of(v.find(NSM + "fullName"))
                        for v in vs.iter(NSM + "value")
                        if v.find(NSM + "fullName") is not None}
                if vals:
                    picklists["%s.%s" % (obj, fld)] = vals
    valid_rel = set(parent_rel) | set(child_rel)
    pick_by_field = {}
    for k, v in picklists.items():
        pick_by_field.setdefault(k.split(".", 1)[1], {})[k.split(".", 1)[0]] = v

    def fields_of(obj):
        f = set(STD_FIELDS) | objects.get(obj, set())
        f |= STANDARD_FIELDS_BY_OBJECT.get(obj, set())
        if obj in custom_settings:
            f |= {"SetupOwnerId"}
        return {x.lower() for x in f}

    def balanced(src, start, open_c="(", close_c=")"):
        d, j = 0, start
        while j < len(src):
            if src[j] == open_c:
                d += 1
            elif src[j] == close_c:
                d -= 1
                if d == 0:
                    return j
            j += 1
        return len(src) - 1

    AGG = re.compile(r"^(COUNT|COUNT_DISTINCT|MIN|MAX|SUM|AVG|toLabel|FORMAT|"
                     r"convertCurrency|GROUPING)\b", re.I)
    n_soql = n_ctor = n_rel = 0
    for path in apex_files:
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
        except (UnicodeDecodeError, OSError):
            continue
        src = apex_blank(raw)
        line_of = lambda off: src[:off].count("\n") + 1

        # --- SOQL: every selected field is on the object -------------------
        for m in re.finditer(r"\[\s*(SELECT\b.*?)\]", src, re.I | re.S):
            q = m.group(1)
            depth, frm = 0, None
            for t in re.finditer(r"[()]|\bFROM\b", q, re.I):
                if t.group(0) == "(":
                    depth += 1
                elif t.group(0) == ")":
                    depth -= 1
                elif depth == 0:
                    frm = t
                    break
            if not frm:
                continue
            om = re.match(r"\s*([A-Za-z0-9_]+)", q[frm.end():])
            if not om:
                continue
            obj = om.group(1)
            n_soql += 1
            sel = re.sub(r"\([^()]*\)", "()", q[q.upper().find("SELECT") + 6:frm.start()])
            picked = []
            for f in sel.split(","):
                f = re.sub(r"\s+\w+$", "", f.strip()).strip()
                if not f or f == "()" or f.startswith("(") or AGG.match(f):
                    continue
                picked.append(f)
            if obj not in objects:
                if obj not in STANDARD_OBJECTS:
                    W(path, "line %d: SOQL FROM '%s', which is neither a "
                            "standard object nor defined in this repo"
                      % (line_of(m.start()), obj))
                for f in picked:
                    if f.endswith("__c") and "." not in f and f not in objects.get(obj, set()):
                        P(path, "line %d: SOQL selects '%s' on %s, but no such "
                                "custom field is defined in this repo"
                          % (line_of(m.start()), f, obj))
                continue
            known = fields_of(obj)
            for f in picked:
                if "." in f:
                    root = f.split(".")[0]
                    if root.endswith("__r") and root not in valid_rel:
                        P(path, "line %d: SOQL traverses '%s' on %s, but no "
                                "lookup declares that relationship"
                          % (line_of(m.start()), root, obj))
                    continue
                if f.lower() not in known:
                    P(path, "line %d: SOQL selects '%s', which is not a field "
                            "of %s" % (line_of(m.start()), f, obj))

        # --- new SObject(Field = ...) --------------------------------------
        for m in re.finditer(r"\bnew\s+([A-Za-z_]\w*(?:__[ce]|__mdt)?)\s*\(", src):
            obj = m.group(1)
            if obj not in objects:
                continue
            args = src[m.end():balanced(src, m.end() - 1)]
            if "=" not in args:
                continue
            n_ctor += 1
            known = fields_of(obj)
            for a in re.finditer(r"(?:^|,)\s*([A-Za-z_]\w*)\s*=(?!=)", args):
                if a.group(1).lower() not in known:
                    P(path, "line %d: 'new %s(%s = ...)' -- %s has no such field"
                      % (line_of(m.start()), obj, a.group(1), obj))

        # --- __r relationship names ----------------------------------------
        for m in re.finditer(r"\b([A-Za-z_]\w*__r)\b", src):
            n_rel += 1
            if m.group(1) not in valid_rel:
                P(path, "line %d: '%s' -- no lookup or master-detail in this "
                        "repo declares that relationship name"
                  % (line_of(m.start()), m.group(1)))

        # --- picklist literals ---------------------------------------------
        for m in re.finditer(r"\b([A-Za-z_]\w*__c)\s*(?:=>|==|!=|=)\s*'([^']*)'", raw):
            fld, lit = m.group(1), m.group(2)
            if fld not in pick_by_field:
                continue
            if any(lit in vals for vals in pick_by_field[fld].values()):
                continue
            W(path, "line %d: '%s' is compared or assigned the literal '%s', "
                    "which is not in its value set (%s). Harmless on an "
                    "unrestricted picklist and on a record never inserted; a "
                    "runtime failure otherwise"
              % (raw[:m.start()].count("\n") + 1, fld, lit,
                 "; ".join("%s: %s" % (o, ", ".join(sorted(v)))
                           for o, v in pick_by_field[fld].items())))
    print("  %d SOQL queries, %d SObject constructors, %d relationship "
          "traversals" % (n_soql, n_ctor, n_rel))

    # --- LWC -> Apex bindings ----------------------------------------------
    # An LWC calls Apex by NAME and passes parameters BY NAME. A renamed Apex
    # parameter still compiles, still deploys, and still passes every Jest test
    # (the Apex module is mocked); it fails in the browser, in front of whoever
    # is using the page. Nothing else in this repo checks it.
    apex_members = {}          # class -> {method: [(arity, params, aura)]}
    for path in apex_files:
        if not path.endswith(".cls"):
            continue
        cls = os.path.basename(path)[:-4]
        try:
            with open(path, encoding="utf-8") as fh:
                body = apex_blank(fh.read())
        except (UnicodeDecodeError, OSError):
            continue
        members = {}
        for m in re.finditer(
                r"^[ \t]*((?:@\w+(?:\([^)]*\))?\s*)*)"
                r"((?:(?:public|private|global|protected|static|virtual|abstract|"
                r"override|final|transient|webservice|testmethod)\s+)+)"
                r"([A-Za-z_][\w.]*(?:\s*<[^;{}()]*>)?(?:\s*\[\s*\])?)\s+"
                r"([A-Za-z_]\w*)\s*\(([^;{)]*)\)\s*\{", body, re.M):
            anns, _mods, _ret, name, params = m.groups()
            names = []
            depth, cur = 0, ""
            for ch in params + ",":
                if ch == "<":
                    depth += 1
                elif ch == ">":
                    depth -= 1
                if ch == "," and depth == 0:
                    pm = re.match(r"^(?:final\s+)?.*?\s+([A-Za-z_]\w*)$",
                                  cur.strip(), re.S)
                    if pm:
                        names.append(pm.group(1))
                    cur = ""
                else:
                    cur += ch
            members.setdefault(name, []).append(
                (len(names), names, "auraenabled" in anns.lower()))
        apex_members[cls] = members

    def js_blank(src):
        out, i, n = [], 0, len(src)
        while i < n:
            if src.startswith("//", i):
                while i < n and src[i] != "\n":
                    out.append(" ")
                    i += 1
                continue
            if src.startswith("/*", i):
                j = src.find("*/", i + 2)
                j = n if j < 0 else j + 2
                out.append(re.sub(r"[^\n]", " ", src[i:j]))
                i = j
                continue
            if src[i] in "'\"`":
                q = src[i]
                out.append(" ")
                i += 1
                while i < n:
                    if src[i] == "\\":
                        out.append("  ")
                        i += 2
                        continue
                    if src[i] == q:
                        out.append(" ")
                        i += 1
                        break
                    out.append("\n" if src[i] == "\n" else " ")
                    i += 1
                continue
            out.append(src[i])
            i += 1
        return "".join(out)

    n_imports = n_bindings = 0
    for path in sorted(walk(lwc_dir)) if os.path.isdir(lwc_dir) else []:
        if not path.endswith(".js") or "__tests__" in path:
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
        except (UnicodeDecodeError, OSError):
            continue
        js = js_blank(raw)
        imports = {}
        for m in re.finditer(
                r"import\s+(\w+)\s+from\s+['\"]@salesforce/apex/([\w.]+)['\"]", raw):
            local, ref = m.group(1), m.group(2)
            n_imports += 1
            if ref.count(".") != 1:
                P(path, "'@salesforce/apex/%s' is not <ApexClass>.<method>" % ref)
                continue
            cls, meth = ref.split(".")
            if cls not in apex_members:
                P(path, "imports '%s' but there is no Apex class %s in this repo"
                  % (ref, cls))
                continue
            if meth not in apex_members[cls]:
                P(path, "imports '%s' but %s has no method '%s'" % (ref, cls, meth))
                continue
            aura = [o for o in apex_members[cls][meth] if o[2]]
            if not aura:
                P(path, "imports '%s', but %s.%s is not @AuraEnabled and is not "
                        "callable from a component" % (ref, cls, meth))
                continue
            imports[local] = (cls, meth, aura[0])
        for local, (cls, meth, sig) in imports.items():
            arity, pnames, _ = sig
            valid = set(pnames)
            call = (r"(?:@wire\(\s*" + re.escape(local) + r"\s*,\s*|"
                    r"(?<![.\w$])" + re.escape(local) + r"\s*\(\s*)")
            for m in re.finditer(call + r"\{", js):
                open_brace = js.index("{", m.end() - 1)
                body = js[open_brace + 1:balanced(js, open_brace, "{", "}")]
                n_bindings += 1
                keys, opaque, depth, cur = set(), False, 0, ""
                for ch in body + ",":
                    if ch in "([{":
                        depth += 1
                    elif ch in ")]}":
                        depth -= 1
                    if ch == "," and depth == 0:
                        e = cur.strip()
                        cur = ""
                        if not e:
                            continue
                        km = re.match(r"^([A-Za-z_$][\w$]*)\s*:", e) or \
                            re.match(r"^([A-Za-z_$][\w$]*)$", e)
                        if km:
                            keys.add(km.group(1))
                        else:
                            opaque = True     # spread or computed key
                    else:
                        cur += ch
                unknown = keys - valid
                if unknown:
                    P(path, "calls %s.%s with parameter name(s) %s; the Apex "
                            "method takes %s. LWC passes parameters by name, so "
                            "this fails at runtime, not at deploy"
                      % (cls, meth, ", ".join(sorted(unknown)),
                         ", ".join(sorted(valid)) or "none"))
                missing = valid - keys
                if missing and not opaque:
                    W(path, "calls %s.%s without %s" % (
                        cls, meth, ", ".join(sorted(missing))))
            for _ in re.finditer(call + r"\)", js):
                if arity:
                    P(path, "calls %s.%s with no arguments; it takes %s"
                      % (cls, meth, ", ".join(sorted(valid))))
    print("  %d LWC->Apex imports, %d parameterised call sites"
          % (n_imports, n_bindings))


def section(title):
    print()
    print("=" * 72)
    print(title)
    print("=" * 72)



def inventory():
    """What is actually in this tree, counted rather than remembered.

    docs/runbooks/fresh-org-deploy.md opens with an inventory of what a fresh
    org is going to receive. A hand-maintained list of that goes stale the first
    time somebody adds a field, and a runbook that undercounts the solution is
    how a deploy ends up missing a piece. So the runbook says to run this
    instead of trusting a number typed into a table.
    """
    def count(sub, pred=lambda f: True):
        d = os.path.join(SRC, sub)
        if not os.path.isdir(d):
            return 0
        return sum(1 for f in os.listdir(d) if pred(f))

    objects_dir = os.path.join(SRC, "objects")
    objs = sorted(d for d in os.listdir(objects_dir)
                  if os.path.isdir(os.path.join(objects_dir, d)))
    custom = [o for o in objs if o.endswith("__c")]
    cmdt = [o for o in objs if o.endswith("__mdt")]
    events = [o for o in objs if o.endswith("__e")]
    standard = [o for o in objs if not o.endswith(("__c", "__mdt", "__e"))]

    def fields(o):
        d = os.path.join(objects_dir, o, "fields")
        return sorted(f[: -len(".field-meta.xml")] for f in os.listdir(d)) \
            if os.path.isdir(d) else []

    settings = [o for o in custom
                if "<customSettingsType>" in open(
                    os.path.join(objects_dir, o, o + ".object-meta.xml"),
                    encoding="utf-8").read()]

    print("=" * 72)
    print("INVENTORY  (what a fresh org receives, counted from this tree)")
    print("=" * 72)
    print("  custom objects        %d   %s"
          % (len(custom), ", ".join(o for o in custom if o not in settings)))
    print("  custom settings       %d   %s" % (len(settings), ", ".join(settings)))
    print("  platform events       %d   %s" % (len(events), ", ".join(events)))
    print("  custom metadata types %d   %s" % (len(cmdt), ", ".join(cmdt)))
    print("  standard objects extended:")
    for o in standard:
        print("        %-14s %s" % (o, ", ".join(fields(o)) or "(no custom fields)"))
    print("  custom fields total   %d" % sum(len(fields(o)) for o in objs))
    print("  custom metadata records %d   (%s generated from "
          "instrument/)"
          % (count("customMetadata", lambda f: f.endswith(".md-meta.xml")),
             count("customMetadata",
                   lambda f: f.startswith("GTM_Assessment_") and f.endswith(".md-meta.xml"))))
    apex_all = count("classes", lambda f: f.endswith(".cls"))
    apex_test = count("classes", lambda f: f.endswith("Test.cls"))
    print("  Apex classes          %d   (%d of them tests)" % (apex_all, apex_test))
    print("  Apex triggers         %d" % count("triggers", lambda f: f.endswith(".trigger")))
    print("  LWC bundles           %d"
          % sum(1 for d in os.listdir(os.path.join(SRC, "lwc"))
                if os.path.isdir(os.path.join(SRC, "lwc", d))))
    for sub, label in (("flexipages", "flexipages"), ("tabs", "tabs"),
                       ("applications", "apps"), ("layouts", "layouts"),
                       ("managedContentTypes", "managed content types"),
                       ("permissionsets", "permission sets"), ("profiles", "profiles"),
                       ("queues", "queues"), ("approvalProcesses", "approval processes"),
                       ("workflows", "workflows"), ("flows", "flows"),
                       ("remoteSiteSettings", "remote site settings"),
                       ("cspTrustedSites", "CSP trusted sites"),
                       ("bots", "Agentforce bots"), ("genAiPlugins", "genAiPlugins")):
        print("  %-21s %d" % (label, count(sub)))
    edir = os.path.join(SRC, "experiences")
    for site in sorted(d for d in os.listdir(edir)
                       if os.path.isdir(os.path.join(edir, d))):
        rdir = os.path.join(edir, site, "routes")
        routes = sorted(f[:-5] for f in os.listdir(rdir)) if os.path.isdir(rdir) else []
        print("  site %-16s %d routes: %s" % (site, len(routes), ", ".join(routes)))
    seed = os.path.join(ROOT, "data", "seed")
    for f in sorted(os.listdir(seed)) if os.path.isdir(seed) else []:
        if f.endswith(".json"):
            with open(os.path.join(seed, f), encoding="utf-8") as fh:
                print("  seed %-16s %d records"
                      % (f, len(json.load(fh).get("records", []))))


def main():
    if "--inventory" in sys.argv:
        inventory()
        return 0

    list_blocking = "--list-blocking" in sys.argv
    # In --list-blocking mode we want ONLY the sorted finding lines on
    # stdout (see below) so a caller can diff two runs cleanly -- swallow
    # every other report section's normal output.
    out = (lambda *a, **k: None) if list_blocking else print

    lwcs = sorted(
        d for d in os.listdir(os.path.join(SRC, "lwc"))
        if os.path.isdir(os.path.join(SRC, "lwc", d))
    ) if os.path.isdir(os.path.join(SRC, "lwc")) else []

    apex = sorted(
        f[:-4] for f in os.listdir(os.path.join(SRC, "classes"))
        if f.endswith(".cls")
    ) if os.path.isdir(os.path.join(SRC, "classes")) else []

    # Read every source file once.
    files = {}
    for path in walk(SRC):
        if path.endswith((".xml", ".json", ".js", ".html", ".cls", ".css")):
            try:
                with open(path, encoding="utf-8") as fh:
                    files[path] = fh.read()
            except (UnicodeDecodeError, OSError):
                pass

    def refs_to(patterns, own_dir=None):
        hits = {}
        for path, text in files.items():
            if own_dir and os.sep + own_dir + os.sep in path:
                continue  # a component referencing itself is not a dependant
            for pat in patterns:
                if pat in text:
                    hits.setdefault(metadata_kind(path), set()).add(
                        os.path.relpath(path, ROOT))
                    break
        return hits

    out("=" * 72)
    out("LIGHTNING COMPONENTS")
    out("=" * 72)
    orphans = []
    for name in lwcs:
        # Every form a reference can take. Missing one of these is how four
        # bundles got deleted on the strength of an audit that saw nothing:
        #   c-gtm-story          markup composition
        #   c/gtmStory           ES module import
        #   c:gtmStory           FlexiPage and Experience Cloud view JSON
        #   <lwcComponent>      Custom Tab
        hits = refs_to([f"c-{kebab(name)}", f"c/{name}", f"c:{name}",
                        f"<componentName>{name}</componentName>",
                        f"<lwcComponent>{name}</lwcComponent>"], own_dir=name)
        if hits:
            where = ", ".join(f"{k}({len(v)})" for k, v in sorted(hits.items()))
            out(f"  {name:<24} <- {where}")
        else:
            orphans.append(name)
            out(f"  {name:<24} <- NOTHING (orphan)")

    out()
    out("=" * 72)
    out("APEX CLASSES  (grants shown so a guest-facing class is obvious)")
    out("=" * 72)
    for name in apex:
        if name.endswith("Test"):
            continue
        # An Apex class called only by other Apex, or wired to an Agentforce
        # action, is not unreferenced. Counting only LWC imports and grants
        # reported GtmContentAddress and the GtmAgent* classes as dead.
        # (Hunk re-applied from claude/gtm-offerings-ma-deploy-vtf5vl, a
        # genuine bug fix -- this audit's second half hard-codes many literal
        # class-name checks and would otherwise false-positive on them.)
        hits = refs_to([f"apex/{name}.", f"<apexClass>{name}</apexClass>",
                        f"{name}.", f"<invocationTarget>{name}</invocationTarget>"],
                       own_dir=None)
        where = ", ".join(f"{k}({len(v)})" for k, v in sorted(hits.items())) or "NOTHING"
        out(f"  {name:<32} <- {where}")

    # Dangling: something referenced that no longer exists in source.
    out()
    out("=" * 72)
    out("DANGLING REFERENCES")
    out("=" * 72)
    dangling = []
    known = set(lwcs)
    for path, text in files.items():
        for m in re.findall(r"<lwcComponent>(\w+)</lwcComponent>", text):
            if m not in known:
                dangling.append((os.path.relpath(path, ROOT), "lwcComponent", m))
        # Only quoted "c:name" counts. Bare c: also appears as the CSS
        # pseudo-class :hover and in HTML attributes, which are not references.
        for m in re.findall(r'"c:(\w+)"', text):
            if m not in known:
                dangling.append((os.path.relpath(path, ROOT), "c: reference", m))
        for m in re.findall(r"<apexClass>(\w+)</apexClass>", text):
            if m not in set(apex):
                dangling.append((os.path.relpath(path, ROOT), "apexClass", m))
    if dangling:
        for where, kind, what in dangling:
            out(f"  x {where} references missing {kind} '{what}'")
    else:
        out("  none")

    out()
    out(f"Orphaned components: {', '.join(orphans) if orphans else 'none'}")
    if orphans:
        # This scans the branch, and the branch is not the org. Ported from
        # claude/gtm-offerings-ma-deploy-vtf5vl: maAdminBar and gtmAppShell
        # both read as orphans there while the org had them placed on live
        # Experience Cloud pages -- the delete failed and said so.
        out()
        out("  These are unreferenced IN THIS BRANCH. Experience Builder keeps its")
        out("  own page layouts in the org, and a deploy of the site bundles does")
        out("  not always round-trip them. Before deleting any of these, confirm")
        out("  against the org:")
        out()
        out("      sf project retrieve start --metadata ExperienceBundle \\")
        out("        --target-metadata-dir /tmp/exp")
        out("      unzip -o /tmp/exp/unpackaged.zip -d /tmp/exp")
        out("      grep -rl '<NAME>' /tmp/exp/unpackaged/experiences/")
        out()
        out("  A destructive deploy also refuses and names the pages, which is the")
        out("  authoritative answer.")

    # ---- the deployability half -------------------------------------------
    problems, warnings = [], []
    if list_blocking:
        # audit() prints its own section headers unconditionally (it has no
        # knowledge of --list-blocking); swallow that too so stdout in this
        # mode is only ever the sorted finding lines below.
        with contextlib.redirect_stdout(io.StringIO()):
            audit(problems, warnings)
    else:
        audit(problems, warnings)

    if list_blocking:
        # Machine-readable, one line per deploy-blocking finding, sorted so
        # two runs of the identical tree always emit identical output. Used
        # by .github/workflows/agent-ci-gate.yml to diff a PR's findings
        # against main's baseline rather than fail on the raw count -- see
        # that workflow for why (issue #33).
        lines = [f"{where}\tmissing {kind} '{what}'" for where, kind, what in dangling]
        lines += [f"{where}\t{msg}" for where, msg in problems]
        for line in sorted(lines):
            print(line)
        return 1 if (dangling or problems) else 0

    out()
    out("=" * 72)
    out("WOULD-NOT-DEPLOY  (each of these fails, or silently omits, a deploy)")
    out("=" * 72)
    if dangling:
        for where, kind, what in dangling:
            out(f"  x {where}")
            out(f"      references missing {kind} '{what}'")
    for where, msg in problems:
        out(f"  x {where}")
        out(f"      {msg}")
    if not dangling and not problems:
        out("  none")

    out()
    out("=" * 72)
    out("DEPLOYS, BUT WILL NOT WORK UNTIL SOMEBODY DOES SOMETHING BY HAND")
    out("=" * 72)
    if warnings:
        for where, msg in warnings:
            out(f"  ! {where}")
            out(f"      {msg}")
    else:
        out("  none")

    out()
    out(f"{len(dangling) + len(problems)} deploy-blocking, "
          f"{len(warnings)} needing a manual step "
          f"(see docs/runbooks/fresh-org-deploy.md)")
    return 1 if (dangling or problems) else 0


if __name__ == "__main__":
    sys.exit(main())
