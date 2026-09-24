"""Tests for patch-related-lists-layouts.py. Run: python3 -m unittest scripts/test_patch_related_lists_layouts.py"""
import importlib.util
import os
import unittest

_p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "patch-related-lists-layouts.py")
_s = importlib.util.spec_from_file_location("patcher", _p)
P = importlib.util.module_from_spec(_s)
_s.loader.exec_module(P)

WITH = """<?xml version="1.0" encoding="UTF-8"?>
<Layout xmlns="http://soap.sforce.com/2006/04/metadata">
    <layoutSections>
        <label>Info</label>
    </layoutSections>
    <relatedLists>
        <relatedList>RelatedNoteList</relatedList>
    </relatedLists>
    <showEmailCheckbox>false</showEmailCheckbox>
</Layout>
"""
NONE = WITH.replace("""    <relatedLists>
        <relatedList>RelatedNoteList</relatedList>
    </relatedLists>
""", "")


class T(unittest.TestCase):
    def test_adds_two_blocks_before_first_related_list(self):
        out = P.patch(WITH, "Account")
        self.assertIn("<relatedList>GTM_Assessment_Request__c.Account__c</relatedList>", out)
        self.assertIn("<relatedList>GTM_Saved_Configuration__c.Account__c</relatedList>", out)
        self.assertLess(out.index("GTM_Assessment_Request__c.Account__c"), out.index("RelatedNoteList"))
        self.assertIsNone(P.verify(WITH, out, "Account"))
        self.assertEqual(out.count("<relatedLists>"), 3)

    def test_idempotent(self):
        once = P.patch(WITH, "Opportunity")
        self.assertEqual(P.patch(once, "Opportunity"), once)

    def test_already_has_them(self):
        full = P.patch(WITH, "Contact")
        self.assertEqual(P.patch(full, "Contact"), full)
        self.assertEqual(full.count("GTM_Saved_Configuration__c.Contact__c"), 1)

    def test_partial_adds_only_missing(self):
        part = P.patch(WITH, "Contact")
        part = part.replace("GTM_Saved_Configuration__c.Contact__c", "X.Y")
        out = P.patch(part, "Contact")
        self.assertEqual(out.count("GTM_Assessment_Request__c.Contact__c"), 1)
        self.assertEqual(out.count("GTM_Saved_Configuration__c.Contact__c"), 1)

    def test_no_existing_related_lists_inserts_before_successor(self):
        out = P.patch(NONE, "Account")
        self.assertLess(out.index("GTM_Assessment_Request__c"), out.index("<showEmailCheckbox>"))
        self.assertIsNone(P.verify(NONE, out, "Account"))

    def test_mini_layout_related_lists_ignored(self):
        mini = WITH.replace("    <relatedLists>", """    <miniLayout>
        <fields>Name</fields>
        <relatedLists>
            <relatedList>RelatedNoteList</relatedList>
        </relatedLists>
    </miniLayout>
    <relatedLists>""", 1)
        out = P.patch(mini, "Account")
        self.assertLess(out.index("</miniLayout>"), out.index("GTM_Assessment_Request__c.Account__c"))
        self.assertIsNone(P.verify(mini, out, "Account"))

    def test_columns(self):
        out = P.patch(WITH, "Account")
        for c in P.AR_COLS + P.SC_COLS:
            self.assertIn("<fields>%s</fields>" % c, out)

    def test_verify_rejects_other_changes(self):
        self.assertIsNotNone(P.verify(WITH, WITH.replace("Info", "Other"), "Account"))
        self.assertIsNotNone(P.verify(WITH, WITH.replace("<showEmail", "<x>1</x>\n    <showEmail"), "Account"))

    def test_crlf_preserved(self):
        crlf = WITH.replace("\n", "\r\n")
        out = P.patch(crlf, "Account")
        self.assertNotIn("\n", out.replace("\r\n", ""))
        self.assertIsNone(P.verify(crlf, out, "Account"))

    def test_rejects_non_layout(self):
        with self.assertRaises(ValueError):
            P.patch("<a/>", "Account")


if __name__ == "__main__":
    unittest.main()
