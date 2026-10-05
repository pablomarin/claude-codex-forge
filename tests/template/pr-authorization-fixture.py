"""Exercise the real PR gate and evidence parsers without publishing anything."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
POWERSHELL = shutil.which("powershell.exe") or shutil.which("pwsh")
RUNTIMES = (["powershell"] if "--powershell" in sys.argv else ["bash"])
if "--powershell" not in sys.argv and POWERSHELL:
    RUNTIMES.append("powershell")
NONCE = "123e4567-e89b-42d3-a456-426614174000"


class AuthorizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="forge-pr-auth-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / ".forge/local").mkdir(parents=True)
        for args in (["init", "-q"], ["-c", "user.name=Forge", "-c",
                     "user.email=forge@example.invalid", "commit", "--allow-empty", "-qm", "base"]):
            subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)
        self.head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip()

    def approval(self, nonce=NONCE, head=None):
        return f"- [x] PR creation authorized — `2026-10-05T12:00:00Z` — nonce=`{nonce}` — head=`{head or self.head}`"

    def write_state(self, runtime, nonce, auth="", before="", after="", workflow="quick-fix", crlf=False, bom=None):
        text = f"""<!-- forge:state-schema v6 -->
## Identity
| Workflow base SHA | {self.head} |
## Workflow
| Command | /{workflow} fixture |
| Phase | publication |
| Next step | check authorization |
### Checklist
{before}
## /goal session
| nonce | {nonce} |
| workflow_command | /fix-bug fixture |
## PR authorization
{auth}
## State
{after}
"""
        if crlf:
            text = text.replace("\n", "\r\n")
        if bom is None:
            bom = runtime == "powershell" and os.name == "nt"
        encoding = "utf-8-sig" if bom else "utf-8"
        (self.root / ".forge/local/state.md").write_bytes(text.encode(encoding))

    def hook(self, runtime, name):
        if runtime == "powershell":
            self.assertIsNotNone(POWERSHELL, "PowerShell runtime is required")
            command = [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / f"hooks/{name}.ps1")]
        else:
            command = ["bash", str(ROOT / f"hooks/{name}.sh")]
        payload = {"cwd": str(self.root), "host": "codex", "tool_name": "Bash",
                   "tool_input": {"command": "gh pr create --title fixture"}}
        return subprocess.run(command, cwd=self.root, input=json.dumps(payload), text=True, capture_output=True)

    def evidence(self, runtime):
        result = self.hook(runtime, "build-evidence")
        self.assertEqual(result.returncode, 0, result.stderr)
        body = result.stderr.split("FORGE_GOAL_EVIDENCE_BEGIN", 1)[1].split("FORGE_GOAL_EVIDENCE_END", 1)[0]
        return json.loads(body.strip())

    def test_template_goal_is_inactive_but_normal_gates_remain(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                self.write_state(runtime, "<uuid-v4-lowercase>", self.approval("none"))
                result = self.hook(runtime, "check-workflow-gates")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIsNone(self.evidence(runtime)["session_nonce"])
                self.write_state(runtime, "<uuid-v4-lowercase>", workflow="fix-bug")
                result = self.hook(runtime, "check-workflow-gates")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("final receipt set", result.stderr)

    def test_real_goal_matching_and_stale_controls(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                self.write_state(runtime, NONCE, self.approval())
                self.assertEqual(self.hook(runtime, "check-workflow-gates").returncode, 0)
                self.assertTrue(self.evidence(runtime)["pr_authorization"]["authorized"])
                self.write_state(runtime, NONCE, self.approval("stale"))
                result = self.hook(runtime, "check-workflow-gates")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("nonce mismatch", result.stderr)
                self.assertFalse(self.evidence(runtime)["pr_authorization"]["authorized"])

    def test_real_goal_uses_only_canonical_approval(self):
        for runtime in RUNTIMES:
            for crlf in (False, True):
                for bom in ((False, True) if runtime == "powershell" else (False,)):
                    with self.subTest(runtime=runtime, crlf=crlf, bom=bom):
                        self.write_state(runtime, NONCE, self.approval(),
                                         before="- [x] PR creation authorized — summary only",
                                         after=self.approval("stale"), crlf=crlf, bom=bom)
                        result = self.hook(runtime, "check-workflow-gates")
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertNotIn("Multiple PR authorization", result.stderr)
                        self.assertTrue(self.evidence(runtime)["pr_authorization"]["authorized"])

    def test_narrative_cannot_replace_missing_or_stale_approval(self):
        for runtime in RUNTIMES:
            for auth, message in (("", "no ## PR authorization"),
                                  (self.approval("stale"), "nonce mismatch"),
                                  (self.approval(head="0" * 40), "HEAD mismatch")):
                with self.subTest(runtime=runtime, message=message):
                    self.write_state(runtime, NONCE, auth, after=self.approval())
                    result = self.hook(runtime, "check-workflow-gates")
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertIn(message, result.stderr)
                    self.assertFalse(self.evidence(runtime)["pr_authorization"]["authorized"])

    def test_canonical_duplicates_keep_last_line_defense(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                self.write_state(runtime, NONCE, self.approval("stale") + "\n" + self.approval())
                result = self.hook(runtime, "check-workflow-gates")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Multiple PR authorization", result.stderr)
                self.assertTrue(self.evidence(runtime)["pr_authorization"]["authorized"])
                self.write_state(runtime, NONCE, self.approval() + "\n" + self.approval("stale"))
                result = self.hook(runtime, "check-workflow-gates")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(self.evidence(runtime)["pr_authorization"]["authorized"])


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
