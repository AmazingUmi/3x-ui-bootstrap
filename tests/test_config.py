from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from _loader import ROOT, load_installer


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.app = load_installer()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "config.json"
        self.data = json.loads((ROOT / "config.example.json").read_text())
        self.data["SERVER_IP"] = "8.8.8.8"
        self.data["NODE_NAME"] = "测试节点"

    def write(self, data=None, raw=None):
        self.path.write_text(raw if raw is not None else json.dumps(data or self.data))
        self.path.chmod(0o600)
        return self.path

    def parse(self, data=None):
        return self.app.parse_config(self.app.load_config_values(self.write(data)))

    def isp(self):
        return dict(self.data, NODE_MODE="direct+isp", ISP_HOST="proxy.example.com", ISP_PORT=1080,
                    ISP_USERNAME="test-account", ISP_PASSWORD="fake-password-not-a-secret")

    def test_direct_defaults_and_ssh_panel(self):
        c = self.parse()
        self.assertEqual(self.app.active_roles(c), ("direct",))
        self.assertEqual(c["NODE_PORT"], 443)
        self.assertEqual(c["SUB_HOST"], "8.8.8.8")
        self.assertFalse(c.get("PANEL_HTTPS"))
        self.assertNotIn("ISP", c)
        self.assertNotIn("TRAFFIC_BUDGET", c)

    def test_only_server_ip_is_required_and_others_have_defaults(self):
        c = self.parse({"SERVER_IP": "8.8.8.8"})
        self.assertEqual(c["NODE_NAME"], "MyNode")
        self.assertEqual(c["SUB_PORT"], 2096)

    def test_public_domain_panel(self):
        c = self.parse(dict(self.data, SUB_DOMAIN="Node.Example.Com", PANEL_HTTPS=True))
        self.assertEqual(c["SUB_HOST"], "node.example.com")
        self.assertTrue(c["PANEL_HTTPS"])
        self.assertIn("7777/TCP", self.app.firewall_instructions(c))

    def test_https_panel_requires_domain(self):
        with self.assertRaisesRegex(RuntimeError, "SUB_DOMAIN"):
            self.parse(dict(self.data, PANEL_HTTPS=True))

    def test_isp_credentials_are_required_before_other_checks(self):
        for field in ("ISP_HOST", "ISP_PORT", "ISP_USERNAME", "ISP_PASSWORD"):
            with self.subTest(field=field):
                data = self.isp()
                data[field] = None if field == "ISP_PORT" else ""
                with self.assertRaisesRegex(RuntimeError, "必须填写"):
                    self.parse(data)

    def test_socks5_and_http_upstreams(self):
        for protocol in ("socks5", "http"):
            with self.subTest(protocol=protocol):
                c = self.parse(dict(self.isp(), ISP_PROTOCOL=protocol))
                self.assertEqual(c["ISP"]["protocol"], protocol)
                self.assertEqual(c["ISP"]["port"], 1080)

    def test_shell_characters_are_preserved_as_data(self):
        value = "fake-'\"\\$()\u0060text\u0060-密码"
        c = self.parse(dict(self.isp(), ISP_PASSWORD=value))
        self.assertEqual(c["ISP"]["password"], value)

    def test_control_characters_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "控制字符"):
            self.parse(dict(self.isp(), ISP_PASSWORD="fake\npassword"))

    def test_unknown_and_duplicate_fields_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "不支持的字段"):
            self.parse(dict(self.data, CORE_VERSION="other"))
        with self.assertRaisesRegex(RuntimeError, "重复字段"):
            self.app.load_config_values(self.write(raw='{"SERVER_IP":"8.8.8.8","SERVER_IP":"1.1.1.1"}'))

    def test_configuration_does_not_accept_environment_overrides(self):
        with patch.dict(os.environ, {"BOOTSTRAP_NODE_MODE": "isp", "BOOTSTRAP_SERVER_IP": "127.0.0.1"}):
            c = self.parse()
        self.assertEqual(c["SERVER_IP"], "8.8.8.8")
        self.assertEqual(c["NODE_MODE"], "direct")

    def test_strict_json_types(self):
        invalid = (("PANEL_HTTPS", "false"), ("PANEL_HTTPS", 0), ("NODE_PORT", "443"),
                   ("NODE_PORT", True), ("NODE_PORT", 443.0), ("ISP_PORT", "1080"),
                   ("TOTAL_MONTHLY_GB", "1000"), ("TOTAL_MONTHLY_GB", True),
                   ("NODE_NAME", 12), ("ISP_PASSWORD", None), ("SUB_DOMAIN", []))
        for key, value in invalid:
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                self.parse(dict(self.data, **{key: value}))

    def test_invalid_ports_and_conflicts(self):
        for key, value in (("NODE_PORT", 0), ("NODE_PORT", 65536), ("NODE_PORT", -1),
                           ("NODE_PORT", 80), ("NODE_PORT", 7777), ("PANEL_PORT", 2096)):
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                self.parse(dict(self.data, **{key: value}))
        with self.assertRaises(RuntimeError):
            self.parse(dict(self.isp(), ISP_NODE_PORT=443))

    def test_nickname_and_host_validation(self):
        for key, value in (("NODE_NAME", "two words"), ("NODE_NAME", "a/b"), ("NODE_NAME", ""),
                           ("NODE_NAME", "x" * 65), ("SERVER_IP", "YOUR_VPS_IP"),
                           ("SERVER_IP", "127.0.0.1"), ("SERVER_IP", "192.168.1.1"),
                           ("SERVER_IP", "2001:4860:4860::8888"), ("SUB_DOMAIN", "https://example.com"),
                           ("REALITY_HOST", "example.com:443")):
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                self.parse(dict(self.data, **{key: value}))

    def test_invalid_modes_and_upstream_formats(self):
        for data in (dict(self.data, NODE_MODE="both"), dict(self.isp(), ISP_PROTOCOL="https"),
                     dict(self.isp(), ISP_HOST="socks5://example.com"),
                     dict(self.isp(), ISP_PROTOCOL="http", ISP_USERNAME="user:name"),
                     dict(self.isp(), ISP_EXPECTED_IP="127.0.0.1"),
                     dict(self.isp(), ISP_PASSWORD="界" * 86)):
            with self.subTest(data_keys=tuple(data)), self.assertRaises(RuntimeError):
                self.parse(data)

    def test_invalid_quotas_are_rejected(self):
        for value in (-1, 0.0001, 10000000):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                self.parse(dict(self.data, TOTAL_MONTHLY_GB=value))
        for total, isp in ((1000, 0), (100, 100), (100, 101)):
            with self.subTest(total=total, isp=isp), self.assertRaises(RuntimeError):
                self.parse(dict(self.isp(), TOTAL_MONTHLY_GB=total, ISP_MONTHLY_GB=isp))
        with self.assertRaises(RuntimeError):
            self.parse(dict(self.data, ISP_MONTHLY_GB=100))

    def test_malformed_json_never_echoes_secret_content(self):
        raw = '{"SERVER_IP":"8.8.8.8","ISP_PASSWORD":"fake-secret-for-redaction",}'
        with self.assertRaises(RuntimeError) as caught:
            self.app.load_config_values(self.write(raw=raw))
        self.assertNotIn("fake-secret-for-redaction", str(caught.exception))
        self.assertIn("JSON 语法错误", str(caught.exception))

    def test_nonstandard_numbers_and_top_level_values(self):
        for raw in ('[]', 'null', '1', '"text"', '{}', '{"SERVER_IP":NaN}',
                    '{"SERVER_IP":"8.8.8.8","TOTAL_MONTHLY_GB":Infinity}',
                    '{"SERVER_IP":"8.8.8.8","TOTAL_MONTHLY_GB":1e999999}',
                    '{"SERVER_IP":"8.8.8.8","TOTAL_MONTHLY_GB":1e-999999}'):
            with self.subTest(raw=raw), self.assertRaises(RuntimeError):
                self.app.load_config_values(self.write(raw=raw))

    def test_oversize_file_and_public_permissions_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "64 KiB"):
            self.app.load_config_values(self.write(raw=" " * 65537))
        self.write().chmod(0o644)
        with self.assertRaisesRegex(RuntimeError, "chmod 600"):
            self.app.load_config_values(self.path)

    def test_missing_configuration_has_actionable_error(self):
        with self.assertRaisesRegex(RuntimeError, "config.example.json"):
            self.app.load_config_values(self.path)

    def test_cli_validation_does_not_need_root_network_or_state(self):
        self.write(self.isp())
        with patch.object(self.app.os, "geteuid", side_effect=AssertionError("root check")), \
                patch.object(self.app.socket, "create_connection", side_effect=AssertionError("network")), \
                patch.object(self.app, "main", side_effect=AssertionError("installer")), \
                redirect_stdout(StringIO()) as output:
            result = self.app.cli(["--config", str(self.path), "--validate-config"])
        self.assertEqual(result, 0)
        self.assertIn("PASS", output.getvalue())
        self.assertNotIn("fake-password-not-a-secret", output.getvalue())

    def test_default_config_is_next_to_script_not_current_directory(self):
        self.write()
        with patch.object(self.app, "main", side_effect=AssertionError("installer")), redirect_stdout(StringIO()):
            result = self.app.cli(["--validate-config"], script_path=self.path.with_name("install-3x-ui.sh"))
        self.assertEqual(result, 0)

    def test_shell_entry_point_help_version_and_validation(self):
        self.write()
        for args in (("--help",), ("--version",), ("--validate-config", "--config", str(self.path)),
                     ("--config", str(self.path), "--validate-config")):
            with self.subTest(args=args):
                result = subprocess.run(["bash", str(ROOT / "install-3x-ui.sh"), *args],
                                        capture_output=True, text=True, timeout=10, cwd=self.directory.name)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cli_rejects_multiple_operations(self):
        result = subprocess.run(["bash", str(ROOT / "install-3x-ui.sh"), "--check", "--install"],
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
