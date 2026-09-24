"""Tests for scripts/migrate-instrument-yaml.py.

Local-only: parses committed YAML/CMDT fixtures and asserts on the in-memory
result plus temp-directory output. Never touches an org, never runs `sf`.

Run: python3 -m unittest scripts.tests.test_migrate_instrument_yaml -v
     (from the repo root)
"""
import importlib.util
import json
import os
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT_PATH = os.path.join(os.path.dirname(HERE), "migrate-instrument-yaml.py")

spec = importlib.util.spec_from_file_location("migrate_instrument_yaml", SCRIPT_PATH)
migrate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migrate)


class MigrateReadinessSlotsTests(unittest.TestCase):
    def test_migrates_all_eight_migration_accelerator_slots_with_no_warnings(self):
        result = migrate.migrate_offering("migration-accelerator")
        self.assertEqual(len(result["question_definitions"]), 8)
        self.assertEqual(result["warnings"], [])

    def test_question_keys_preserved_verbatim_from_dimensions_yaml(self):
        result = migrate.migrate_offering("migration-accelerator")
        keys = [q["Question_Key__c"] for q in result["question_definitions"]]
        self.assertEqual(keys, [
            "estate_scale",
            "source_access",
            "orchestration_portability",
            "content_portability",
            "data_model_readiness",
            "integration_containment",
            "consent_portability",
            "decision_readiness",
        ])

    def test_slot_order_matches_dimensions_yaml_position(self):
        result = migrate.migrate_offering("migration-accelerator")
        orders = [q["Slot_Order__c"] for q in result["question_definitions"]]
        self.assertEqual(orders, [1, 2, 3, 4, 5, 6, 7, 8])

    def test_every_slot_has_four_options_with_points_matching_value(self):
        result = migrate.migrate_offering("migration-accelerator")
        for q in result["question_definitions"]:
            options = json.loads(q["Options_JSON__c"])
            self.assertEqual(len(options), 4, q["Question_Key__c"])
            for opt in options:
                self.assertEqual(str(opt["points"]), opt["value"])

    def test_rules_json_is_empty_array_not_ported_from_pair_overrides(self):
        result = migrate.migrate_offering("migration-accelerator")
        for q in result["question_definitions"]:
            self.assertEqual(json.loads(q["Rules_JSON__c"]), [])

    def test_instrument_definition_shape(self):
        result = migrate.migrate_offering("migration-accelerator")
        defn = result["instrument_definition"]
        self.assertEqual(defn["Offering_Key__c"], "migration-accelerator")
        self.assertEqual(defn["Status__c"], "Draft")
        self.assertEqual(defn["Version__c"], 1)

    def test_outcome_ranges_match_compiled_scoring_bands(self):
        result = migrate.migrate_offering("migration-accelerator")
        ranges = result["outcome_ranges"]
        self.assertEqual(len(ranges), 4)
        self.assertEqual(ranges[0]["Min_Score__c"], 8)
        self.assertEqual(ranges[-1]["Max_Score__c"], 32)
        tiers = [r["Tier_Label__c"] for r in ranges]
        self.assertEqual(tiers, [
            "Discovery First", "Prep Required", "Accelerator-Ready", "Fast-Track"
        ])
        # Contiguous, no gaps or overlaps -- every total 8-32 resolves exactly once.
        for prev, cur in zip(ranges, ranges[1:]):
            self.assertEqual(cur["Min_Score__c"], prev["Max_Score__c"] + 1)

    def test_unmigrated_summary_enumerates_every_pair_gate_and_supplement_file(self):
        result = migrate.migrate_offering("migration-accelerator")
        unmig = result["unmigrated"]
        self.assertEqual(len(unmig["pairs"]), 6)
        self.assertEqual(len(unmig["gates"]), 3)
        self.assertEqual(len(unmig["complexity_dimensions"]), 6)
        self.assertEqual(len(unmig["supplement_sets"]), 3)
        for p in unmig["pairs"]:
            self.assertIn("note", p)
        for g in unmig["gates"]:
            self.assertIn("note", g)

    def test_missing_offering_raises_rather_than_silently_producing_empty_output(self):
        with self.assertRaises(SystemExit):
            migrate.migrate_offering("no-such-offering")

    def test_missing_cmdt_row_is_a_warning_not_a_crash(self):
        dims_doc = {
            "slots": [
                {"position": 1, "key": "ghost_dimension", "substitutable": False},
            ]
        }
        questions, warnings = migrate.migrate_readiness_slots("migration-accelerator", dims_doc)
        self.assertEqual(len(questions), 1)
        self.assertIsNone(questions[0]["Question_Text__c"])
        self.assertEqual(len(warnings), 1)
        self.assertIn("ghost_dimension", warnings[0])


class WriteReportTests(unittest.TestCase):
    def test_writes_json_and_markdown_to_out_dir_only_no_network_no_org(self):
        result = migrate.migrate_offering("migration-accelerator")
        tmp = tempfile.mkdtemp()
        try:
            json_path, md_path = migrate.write_report(result, tmp)
            self.assertTrue(os.path.isfile(json_path))
            self.assertTrue(os.path.isfile(md_path))
            with open(json_path, encoding="utf-8") as fh:
                loaded = json.load(fh)
            self.assertEqual(loaded["offering_key"], "migration-accelerator")
            self.assertEqual(len(loaded["question_definitions"]), 8)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
