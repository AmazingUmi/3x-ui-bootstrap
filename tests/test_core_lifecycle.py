"""Transaction failures must not turn a core comparison into a data migration."""
import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from _loader import load_installer


class CoreLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.app = load_installer()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.config = {"SERVER_IP": "8.8.8.8", "XRAY_VERSION": "26.10.31"}
        self.state = {"owner": self.app.OWNER, "phase": "complete", "api_token": "fake-token",
                      "uuid": "original-identity", "core_version": "26.10.31", "config": self.config,
                      "nodes": {"direct": {"uuid": "original-identity", "sub_id": "original-sub"}},
                      "traffic_reset": {"day": 31, "deployed_at": 1700000000}}
        self.identity = copy.deepcopy({k: self.state[k] for k in ("uuid", "nodes", "traffic_reset")})
        self.events = []
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(self.app, "STATE_DIR", self.root))
        self.stack.enter_context(patch.object(self.app, "INPUT_CONFIG", {"XRAY_VERSION": "26.6.27"}))
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.stack.enter_context(patch.object(self.app, "check_db"))
        self.initial_check = self.stack.enter_context(patch.object(self.app, "verify_core"))
        self.download = self.stack.enter_context(patch.object(self.app, "download_core",
            side_effect=lambda arch, ver: self.events.append(("download", ver))))
        self.install = self.stack.enter_context(patch.object(self.app, "install_core",
            side_effect=lambda arch, ver: self.events.append(("install", ver))))
        self.stack.enter_context(patch.object(self.app, "run", side_effect=lambda cmd, **kw: self.events.append(tuple(cmd))))
        self.stack.enter_context(patch.object(self.app, "API"))
        self.stack.enter_context(patch.object(self.app, "wait_api"))
        self.verify = self.stack.enter_context(patch.object(self.app, "verify_runtime"))
        self.stack.enter_context(patch.object(self.app, "write_results", return_value="server checks only"))

    def switch(self):
        self.app.switch_core(self.config, self.state, "amd64")

    def plan(self):
        return json.loads((self.root / "core-change.json").read_text())

    def assert_identity_unchanged(self):
        self.assertEqual({k: self.state[k] for k in self.identity}, self.identity)

    def test_success_downloads_rollback_before_stopping_and_commits_version(self):
        self.switch()
        self.assertEqual(self.events[:2], [("download", "26.10.31"), ("download", "26.6.27")])
        self.assertEqual(self.plan()["status"], "complete")
        self.assertEqual(self.state["core_version"], "26.6.27")
        self.assertEqual(self.state["config"]["XRAY_VERSION"], "26.6.27")
        self.assertEqual(json.loads((self.root / "state.json").read_text()), self.state)
        self.assert_identity_unchanged()

    def test_target_failure_restores_original_core_and_state(self):
        self.verify.side_effect = [RuntimeError("new core rejected"), None]
        with self.assertRaisesRegex(RuntimeError, "已回退到 26.10.31"):
            self.switch()
        self.assertEqual(self.install.call_args_list[0].args, ("amd64", "26.6.27"))
        self.assertEqual(self.install.call_args_list[1].args, ("amd64", "26.10.31"))
        self.assertEqual(self.state["config"], self.config)
        self.assertEqual(self.state["core_version"], "26.10.31")
        self.assertEqual(self.plan()["status"], "rolled_back")
        self.assert_identity_unchanged()

    def test_download_failure_does_not_stop_current_node(self):
        self.download.side_effect = RuntimeError("checksum mismatch")
        with self.assertRaisesRegex(RuntimeError, "checksum"):
            self.switch()
        self.assertEqual(self.events, [])
        self.install.assert_not_called()
        self.assertFalse((self.root / "core-change.json").exists())

    def test_failed_rollback_keeps_pending_transaction(self):
        self.verify.side_effect = RuntimeError("network unavailable")
        with self.assertRaisesRegex(RuntimeError, "自动回退未完成"):
            self.switch()
        self.assertEqual(self.plan()["status"], "prepared")
        self.assert_identity_unchanged()

    def test_interrupted_transaction_can_resume_with_same_target(self):
        plan = {"owner": self.app.OWNER, "uuid": self.state["uuid"], "status": "prepared",
                "old_config": self.config, "new_config": dict(self.config, XRAY_VERSION="26.6.27")}
        (self.root / "core-change.json").write_text(json.dumps(plan))
        self.switch()
        self.initial_check.assert_not_called()  # It may already be the target binary.
        self.assertEqual(self.plan()["status"], "complete")
        self.assert_identity_unchanged()

    def test_interrupted_transaction_rejects_changed_target(self):
        plan = {"owner": self.app.OWNER, "uuid": self.state["uuid"], "status": "prepared",
                "old_config": self.config, "new_config": dict(self.config, XRAY_VERSION="26.6.27")}
        (self.root / "core-change.json").write_text(json.dumps(plan))
        self.app.INPUT_CONFIG["XRAY_VERSION"] = "26.10.31"
        with self.assertRaisesRegex(RuntimeError, "原 XRAY_VERSION"):
            self.switch()
        self.download.assert_not_called()
        self.install.assert_not_called()

    def test_same_version_and_unknown_version_do_not_mutate(self):
        self.app.INPUT_CONFIG["XRAY_VERSION"] = "26.10.31"
        self.switch()
        self.download.assert_not_called()
        self.app.INPUT_CONFIG["XRAY_VERSION"] = "latest"
        with self.assertRaisesRegex(RuntimeError, "固定摘要"):
            self.switch()
        self.install.assert_not_called()

    def test_pending_core_switch_blocks_other_maintenance(self):
        saved = dict(self.state, version=self.app.VERSION)
        (self.root / "state.json").write_text(json.dumps(saved))
        (self.root / "core-change.json").write_text(json.dumps(
            {"owner": self.app.OWNER, "uuid": self.state["uuid"], "status": "prepared"}))
        stat = type("Info", (), {"st_uid": 0, "st_mode": 0o700})()
        self.app.MODE = "--traffic-status"
        with patch.object(self.app.Path, "lstat", return_value=stat), \
                self.assertRaisesRegex(RuntimeError, "核心切换尚未完成"):
            self.app.main()


if __name__ == "__main__":
    unittest.main()
