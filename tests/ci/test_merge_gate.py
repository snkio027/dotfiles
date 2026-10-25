#!/usr/bin/env python3
"""Exercise gate policy, failure propagation, and the workflow/ruleset wiring."""

from __future__ import annotations

import copy
import importlib.util
import itertools
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ci/merge_gate.py"
SPEC = importlib.util.spec_from_file_location("merge_gate", SCRIPT)
assert SPEC and SPEC.loader
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)

# Independent event expectations: do not generate the oracle from the gate's policy.
LANES = (
    ("macos-smoke", "macos"),
    ("devcontainer-build", "devcontainer_build"),
    ("brew-core-profile", "brew_core"),
    ("devcontainer-lifecycle", "devcontainer_lifecycle"),
    ("neovim-locked-cold-start", "neovim_locked"),
)
EXTRAS = {"supply-chain-provenance", "neovim-cold-start"}
JOBS = {"classify_pr", "validate", *(job for job, _ in LANES), *EXTRAS}


def observations(event="pull_request", bits=("1",) * 5):
    needed = {"validate"}
    if event == "pull_request":
        needed.add("classify_pr")
        needed.update(job for (job, _), bit in zip(LANES, bits) if bit == "1")
    elif event == "push":
        needed.update(job for job, _ in LANES)
    else:
        needed.update(job for job, _ in LANES if job != "neovim-locked-cold-start")
        needed.update(EXTRAS)
    needs = {job: {"result": "success" if job in needed else "skipped", "outputs": {}} for job in JOBS}
    if event == "pull_request":
        needs["classify_pr"]["outputs"] = {lane: bit for (_, lane), bit in zip(LANES, bits)}
    return needs, needed


class MergeGateTest(unittest.TestCase):
    def assert_blocked(self, event, needs, cancelled=False):
        try:
            passed, report = GATE.evaluate(event, needs, cancelled)
        except ValueError:
            return
        self.assertFalse(passed, report)
        self.assertIn("Gate: BLOCK", report)

    def test_all_pr_path_combinations_and_each_result(self):
        for bits in itertools.product(("0", "1"), repeat=5):
            self.check_event("pull_request", bits)

    def test_push_and_both_maintenance_events(self):
        for event in ("push", "schedule", "workflow_dispatch"):
            self.check_event(event)

    def check_event(self, event, bits=("1",) * 5):
        baseline, needed = observations(event, bits)
        passed, report = GATE.evaluate(event, baseline, False)
        self.assertTrue(passed, report)
        self.assertIn("NOT APPLICABLE (not executed)", report)
        self.assert_blocked(event, baseline, cancelled=True)
        for job in JOBS:
            for result in ("success", "skipped", "failure", "cancelled"):
                with self.subTest(event=event, bits=bits, job=job, result=result):
                    needs = copy.deepcopy(baseline)
                    needs[job]["result"] = result
                    if result == "success" or (result == "skipped" and job not in needed):
                        self.assertTrue(GATE.evaluate(event, needs, False)[0])
                    else:
                        self.assert_blocked(event, needs)

    def test_classifier_failure_cannot_be_rescued_by_successful_fallback_runs(self):
        for result in ("failure", "cancelled", "skipped"):
            needs, _ = observations()
            needs["classify_pr"]["result"] = result
            self.assert_blocked("pull_request", needs)

    def test_missing_malformed_or_extra_classifier_outputs(self):
        needs, _ = observations()
        for outputs in (None, {}, [], "1", {"macos": "1"}):
            changed = copy.deepcopy(needs)
            changed["classify_pr"]["outputs"] = outputs
            self.assert_blocked("pull_request", changed)
        for lane in needs["classify_pr"]["outputs"]:
            for value in (None, "", "false", "true", "01", "1 ", 0, 1, True, [], {}):
                changed = copy.deepcopy(needs)
                changed["classify_pr"]["outputs"][lane] = value
                self.assert_blocked("pull_request", changed)
        del needs["classify_pr"]["outputs"]
        self.assert_blocked("pull_request", needs)
        needs, _ = observations()
        needs["classify_pr"]["outputs"]["new_lane"] = "0"
        self.assert_blocked("pull_request", needs)

    def test_missing_jobs_unknown_results_and_invalid_inventory(self):
        needs, _ = observations()
        for invalid in (None, [], {}, "success", {**needs, "uncovered-job": {"result": "success"}}):
            self.assert_blocked("pull_request", invalid)
        for job in JOBS:
            changed = copy.deepcopy(needs)
            del changed[job]
            self.assert_blocked("pull_request", changed)
            for value in (None, [], {}, "success", {"result": "neutral"}, {"result": "timed_out"},
                          {"result": "pending"}, {"result": ""}, {"result": []}):
                changed = copy.deepcopy(needs)
                changed[job] = value
                self.assert_blocked("pull_request", changed)
        self.assert_blocked("merge_group", needs)

    def test_real_cli_exit_status_and_summary(self):
        good, _ = observations()
        bad = copy.deepcopy(good)
        bad["devcontainer-lifecycle"]["result"] = "failure"
        cases = [
            ({"NEEDS_JSON": json.dumps(good)}, 0),
            ({"NEEDS_JSON": json.dumps(bad)}, 1),
            ({"NEEDS_JSON": "{"}, 1),
            ({"NEEDS_JSON": "null"}, 1),
            ({"NEEDS_JSON": ""}, 1),
            ({"GITHUB_EVENT_NAME": "unknown"}, 1),
            ({"WORKFLOW_CANCELLED": "true"}, 1),
            ({"WORKFLOW_CANCELLED": ""}, 1),
        ]
        with tempfile.TemporaryDirectory() as directory:
            summary = Path(directory) / "summary.md"
            for overrides, expected in cases:
                env = {**os.environ, "GITHUB_EVENT_NAME": "pull_request",
                       "NEEDS_JSON": json.dumps(good), "WORKFLOW_CANCELLED": "false",
                       "GITHUB_STEP_SUMMARY": str(summary), **overrides}
                result = subprocess.run([sys.executable, str(SCRIPT)], env=env, text=True,
                                        capture_output=True, check=False)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertIn("Gate: PASS" if expected == 0 else "Gate: BLOCK", result.stdout)
                self.assertTrue(summary.read_text().endswith(result.stdout))

    def test_workflow_and_ruleset_wiring(self):
        workflow = json.loads(subprocess.check_output([
            "ruby", "-rjson", "-ryaml", "-e",
            "puts JSON.generate(YAML.load_file(ARGV.fetch(0)))",
            str(ROOT / ".github/workflows/ci.yml"),
        ], text=True))
        jobs = workflow["jobs"]
        gate = jobs["merge-gate"]
        self.assertEqual(set(jobs) - {"merge-gate", "fast", "plan", "delivery"}, JOBS)
        self.assertEqual(set(gate["needs"]), JOBS)
        self.assertEqual(gate["if"], "${{ always() }}")
        self.assertEqual(gate["timeout-minutes"], 5)
        self.assertEqual(gate["name"], "${{ (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch') && 'Maintenance Gate' || 'Main Merge Gate' }}")
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(jobs["classify_pr"]["if"], "github.event_name == 'pull_request'")
        self.assertEqual(jobs["validate"]["if"], "${{ always() && !cancelled() }}")
        for job, lane in LANES:
            # Keep gate exemptions tied to the actual execution conditions.
            condition = " ".join(jobs[job]["if"].split())
            selection = (
                "!github.event.pull_request.draft || needs.classify_pr.result != 'success' || "
                f"format('lane:{{0}}', needs.classify_pr.outputs.{lane}) != 'lane:0'"
            )
            if job == "neovim-locked-cold-start":
                expected = (
                    "always() && !cancelled() && ( github.event_name == 'push' || "
                    "( github.event_name == 'pull_request' && ( " + selection + " ) ) )"
                )
            else:
                expected = (
                    "always() && !cancelled() && ( github.event_name != 'pull_request' || "
                    + selection + " )"
                )
            self.assertEqual(condition, expected)
        for job in EXTRAS:
            self.assertEqual(jobs[job]["if"], "github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'")
        for job in jobs.values():
            self.assertFalse(job.get("continue-on-error", False))
        checkout, evaluate, reject_cancelled = gate["steps"]
        self.assertEqual(checkout["if"], "${{ !cancelled() }}")
        self.assertFalse(checkout["with"]["persist-credentials"])
        self.assertEqual(evaluate["if"], "${{ !cancelled() }}")
        self.assertEqual(evaluate["env"], {"NEEDS_JSON": "${{ toJSON(needs) }}", "WORKFLOW_CANCELLED": "false"})
        self.assertEqual(reject_cancelled["if"], "${{ cancelled() }}")
        self.assertIn("python3 scripts/ci/merge_gate.py", evaluate["run"])
        for step in gate["steps"]:
            self.assertFalse(step.get("continue-on-error", False))
        self.assertTrue(any("python3 tests/ci/test_merge_gate.py" in step.get("run", "") for step in jobs["validate"]["steps"]))

        # Execute the *actual* shell step's cancellation guard without a checkout.
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["bash", "-e", "-c", reject_cancelled["run"]], cwd=directory,
                                    text=True, capture_output=True, check=False)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("workflow cancelled", result.stdout)
        ruleset = json.loads((ROOT / ".github/main-ruleset.json").read_text())
        self.assertEqual(ruleset["target"], "branch")
        self.assertEqual(ruleset["enforcement"], "active")
        self.assertEqual(ruleset["bypass_actors"], [])
        self.assertEqual(ruleset["conditions"], {"ref_name": {"include": ["refs/heads/main"], "exclude": []}})
        rules = {rule["type"]: rule.get("parameters", {}) for rule in ruleset["rules"]}
        self.assertEqual(set(rules), {"deletion", "non_fast_forward", "pull_request", "required_status_checks"})
        self.assertEqual(rules["pull_request"], {
            "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": False,
            "require_code_owner_review": False, "require_last_push_approval": False,
            "required_review_thread_resolution": False,
        })
        self.assertEqual(rules["required_status_checks"], {
            "strict_required_status_checks_policy": True, "do_not_enforce_on_create": False,
            "required_status_checks": [{"context": "Main Merge Gate", "integration_id": 15368}],
        })


if __name__ == "__main__":
    unittest.main()
