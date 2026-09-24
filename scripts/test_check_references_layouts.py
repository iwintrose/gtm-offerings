"""Tests for check-references.py section 9 (layout related-list fields).

Run: python3 -m unittest scripts/test_check_references_layouts.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, "check-references.py")
MD = "force-app/main/default"
NS = "http://soap.sforce.com/2006/04/metadata"


def obj_fields(fields):
    return "".join(
        '<fields><fullName>%s</fullName></fields>' % f for f in fields)


def layout(items=(), related=()):
    body = "".join(
        "<layoutSections><layoutColumns><layoutItems><field>%s</field>"
        "</layoutItems></layoutColumns></layoutSections>" % i for i in items)
    for name, cols in related:
        body += "<relatedLists>%s<relatedList>%s</relatedList></relatedLists>" % (
            "".join("<fields>%s</fields>" % c for c in cols), name)
    return '<?xml version="1.0"?><Layout xmlns="%s">%s</Layout>' % (NS, body)


class LayoutRelatedListTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        os.makedirs(os.path.join(self.tmp, "scripts"))
        shutil.copy(CHECKER, os.path.join(self.tmp, "scripts"))
        for d in ("lwc", "classes", "flexipages", "tabs", "applications",
                  "permissionsets", "profiles", "flows", "triggers"):
            os.makedirs(os.path.join(self.tmp, MD, d), exist_ok=True)
        self._obj("Parent__c", ["Name__c"])
        self._obj("Child__c", ["Parent__c", "ChildOnly__c"])

    def _write(self, rel, content):
        p = os.path.join(self.tmp, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(content)

    def _obj(self, name, fields):
        for f in fields:
            self._write("%s/objects/%s/fields/%s.field-meta.xml" % (MD, name, f),
                        '<?xml version="1.0"?><CustomField xmlns="%s">'
                        "<fullName>%s</fullName></CustomField>" % (NS, f))
        self._write("%s/objects/%s/%s.object-meta.xml" % (MD, name, name),
                    '<?xml version="1.0"?><CustomObject xmlns="%s"/>' % NS)

    def _run(self, xml):
        self._write("%s/layouts/Parent__c-Parent Layout.layout-meta.xml" % MD, xml)
        p = subprocess.run(
            [sys.executable, os.path.join(self.tmp, "scripts", "check-references.py")],
            capture_output=True, text=True)
        out = p.stdout + p.stderr
        lines = out.splitlines()
        hits = []
        for i, l in enumerate(lines):
            if l.strip().startswith("x") and "Parent Layout" in l:
                hits.append(" ".join(lines[i:i + 2]))
        return hits, out

    def test_missing_child_field_flagged(self):
        hits, out = self._run(layout(["Name__c"], [("Child__c.Parent__c", ["Nonexistent__c"])]))
        self.assertTrue(any("Nonexistent__c" in h for h in hits), out)

    def test_field_on_child_not_parent_passes(self):
        hits, out = self._run(layout(["Name__c"], [("Child__c.Parent__c", ["ChildOnly__c"])]))
        self.assertEqual(hits, [], out)

    def test_standard_related_list_passes(self):
        hits, out = self._run(layout(["Name__c"], [("RelatedNoteList", ["NAME", "Whatever__c"])]))
        self.assertEqual(hits, [], out)

    def test_bad_parent_layout_item_flagged(self):
        hits, out = self._run(layout(["Bogus__c"]))
        self.assertTrue(any("Bogus__c" in h for h in hits), out)


if __name__ == "__main__":
    unittest.main()
