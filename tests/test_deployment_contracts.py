"""Offline contracts for behavior that the configuration refactor must preserve."""
from pathlib import Path
import datetime
import json
import tempfile
import unittest
from unittest.mock import patch

from _loader import load_installer


class DeploymentContracts(unittest.TestCase):
    def setUp(self):
        self.app = load_installer()

    def config(self, **changes):
        values = dict(self.app.CONFIG_DEFAULTS, SERVER_IP="8.8.8.8", NODE_NAME="TestNode")
        values.update(changes)
        # Normalize through the same public JSON boundary used by the CLI.
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            path.write_text(json.dumps(values))
            path.chmod(0o600)
            self.app.INPUT_CONFIG = self.app.load_config_values(path)
        return self.app.config_from_file()

    def dual_config(self, **changes):
        values = dict(NODE_MODE="direct+isp", ISP_HOST="proxy.example.com", ISP_PORT=1080,
                      ISP_USERNAME="fake-user", ISP_PASSWORD="fake-pass")
        values.update(changes)
        return self.config(**values)

    def test_versions_and_existing_state_owner_are_preserved(self):
        self.assertEqual(self.app.VERSION, "v3.10.2")
        self.assertEqual(self.app.CORE_VERSION, "26.6.27")
        self.assertEqual(self.app.OWNER, "3x-ui-bootstrap-v5")

    def test_routing_uses_actual_inbound_tags_and_blocks_isp_udp(self):
        c = self.dual_config()
        rules = self.app.route_rules(c, {"direct": {"tag": "actual-443"}, "isp": {"tag": "actual-8443"}})
        self.assertEqual(rules, [
            {"type": "field", "inboundTag": ["actual-443"], "outboundTag": "direct"},
            {"type": "field", "inboundTag": ["actual-8443"], "network": "udp", "outboundTag": "blocked"},
            {"type": "field", "inboundTag": ["actual-8443"], "outboundTag": "bootstrap-isp", "network": "tcp"},
        ])

    def test_native_fixed_allocation_and_fractional_gib(self):
        c = self.dual_config(TOTAL_MONTHLY_GB=1000, ISP_MONTHLY_GB=100)
        self.assertEqual(self.app.client_quota(c, "direct"), 900 * 1024 ** 3)
        self.assertEqual(self.app.client_quota(c, "isp"), 100 * 1024 ** 3)
        c = self.config(TOTAL_MONTHLY_GB=0.125)
        self.assertEqual(self.app.client_quota(c, "direct"), 128 * 1024 ** 2)

    def test_single_isp_uses_smaller_finite_limit(self):
        c = self.dual_config(NODE_MODE="isp", TOTAL_MONTHLY_GB=50, ISP_MONTHLY_GB=100)
        self.assertEqual(self.app.active_roles(c), ("isp",))
        self.assertEqual(self.app.client_quota(c, "isp"), 50 * 1024 ** 3)

    def test_native_monthly_fields_keep_deployment_day(self):
        c = self.dual_config(TOTAL_MONTHLY_GB=1000, ISP_MONTHLY_GB=100)
        fields = self.app.native_quota_fields(c, "isp", {"traffic_reset": {"day": 31}})
        self.assertEqual(fields, {"totalGB": 100 * 1024 ** 3, "trafficReset": "monthly", "trafficResetDay": 31})

    def test_reset_anchor_is_not_replaced_on_rerun(self):
        c = self.config(TOTAL_MONTHLY_GB=1000)
        anchor = {"day": 18, "timezone": "UTC", "deployment_date": "2026-10-18"}
        state = {"traffic_reset": dict(anchor)}
        with patch.object(self.app, "panel_timezone", return_value="UTC"), \
                patch.object(self.app, "save", side_effect=AssertionError("anchor must not change")):
            self.app.bind_traffic_reset(c, state)
        self.assertEqual(state["traffic_reset"], anchor)

    def test_new_anchor_uses_deployed_at(self):
        c = self.config(TOTAL_MONTHLY_GB=1000)
        deployed = datetime.datetime(2026, 1, 31, 12, tzinfo=datetime.timezone.utc).timestamp()
        state = {"deployed_at": deployed}
        with patch.object(self.app, "panel_timezone", return_value="UTC"), patch.object(self.app, "save"):
            self.app.bind_traffic_reset(c, state)
        self.assertEqual(state["traffic_reset"]["day"], 31)
        self.assertEqual(state["traffic_reset"]["deployment_date"], "2026-01-31")

    def test_node_identity_is_retained_and_roles_have_separate_subscriptions(self):
        c = self.dual_config()
        state = {"config": c, "uuid": "00000000-0000-4000-8000-000000000001",
                 "short_id": "1122334455667788", "sub_id": "first-sub", "public_key": "test-public"}
        self.app.prepare_nodes(c, state)
        original = dict(state["nodes"]["direct"])
        self.app.prepare_nodes(c, state)
        self.assertEqual(state["nodes"]["direct"], original)
        self.assertNotEqual(state["nodes"]["isp"]["uuid"], original["uuid"])
        self.assertNotEqual(state["nodes"]["isp"]["sub_id"], original["sub_id"])
        direct_c, direct_s = self.app.node_view(c, state, "direct")
        isp_c, isp_s = self.app.node_view(c, state, "isp")
        self.assertEqual((direct_c["NODE_PORT"], isp_c["NODE_PORT"]), (443, 8443))
        self.assertNotEqual(self.app.mihomo_link(direct_c, direct_s), self.app.mihomo_link(isp_c, isp_s))

    def test_isp_password_stays_out_of_vless_link(self):
        c = self.dual_config()
        link = self.app.vless_link(c, {"uuid": "test-uuid", "public_key": "test-public", "short_id": "ab12"})
        self.assertNotIn("fake-pass", link)
        self.assertNotIn("fake-user", link)
        self.assertIn("flow=xtls-rprx-vision", link)

    def test_domain_change_keeps_saved_isp_and_quota(self):
        c = self.dual_config(TOTAL_MONTHLY_GB=1000, ISP_MONTHLY_GB=100)
        before = dict(c["ISP"])
        self.app.INPUT_CONFIG.update(SUB_DOMAIN="node.example.com", PANEL_HTTPS="true", ISP_PASSWORD="other-candidate")
        result = self.app.domain_config(c)
        self.assertEqual(result["ISP"], before)
        self.assertEqual(result["TRAFFIC_BUDGET"], c["TRAFFIC_BUDGET"])
        self.assertEqual(result["SUB_HOST"], "node.example.com")

    def test_node_change_reads_candidate_credentials_and_keeps_domain(self):
        c = self.dual_config(SUB_DOMAIN="old.example.com", PANEL_HTTPS=True)
        self.app.INPUT_CONFIG.update(ISP_PASSWORD="new-fake-password", SUB_DOMAIN="ignored.example.com")
        result = self.app.selected_node_config(c)
        self.assertEqual(result["ISP"]["password"], "new-fake-password")
        self.assertEqual(result["SUB_HOST"], "old.example.com")

    def test_state_only_operations_do_not_load_a_config_file(self):
        with patch.object(self.app, "load_config_values", side_effect=AssertionError("unexpected config read")), \
                patch.object(self.app.os, "geteuid", return_value=0), \
                patch.object(self.app.platform, "system", return_value="Linux"), \
                patch.object(self.app.Path, "is_dir", return_value=True), patch.object(self.app, "main") as main:
            for mode in ("--diagnose", "--traffic-status", "--repair-reality-target"):
                self.app.cli([mode])
        self.assertEqual(main.call_count, 3)

    def test_reconfiguration_refuses_another_server_before_any_mutation(self):
        self.config(SUB_DOMAIN="candidate.example.com")
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            saved = {"owner": self.app.OWNER, "version": self.app.VERSION,
                     "config": {"SERVER_IP": "1.1.1.1"}}
            state_path.write_text(json.dumps(saved))
            fake_stat = type("Info", (), {"st_uid": 0, "st_mode": 0o700})()
            self.app.MODE = "--configure-domain"
            with patch.object(self.app, "STATE_DIR", Path(directory)), \
                    patch.object(self.app.Path, "lstat", return_value=fake_stat), \
                    patch.object(self.app, "configure_domain", side_effect=AssertionError("mutation")), \
                    self.assertRaisesRegex(RuntimeError, "SERVER_IP 与此部署不一致"):
                self.app.main()


if __name__ == "__main__":
    unittest.main()
