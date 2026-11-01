"""Gateway lifecycle checks without systemd, package installs, or live servers."""
from contextlib import ExitStack, closing, redirect_stdout
from copy import deepcopy
from io import StringIO
from pathlib import Path
import json
import os
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from _loader import load_installer
from test_subscription_gateway import GatewayFixture


class SubscriptionLifecycle(GatewayFixture, unittest.TestCase):
    def setUp(self):
        self.app = load_installer()
        self.directory = tempfile.TemporaryDirectory(prefix="3x-ui-lifecycle-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def ready_state(self):
        state = self.state()
        state.update(uuid="00000000-0000-4000-8000-000000000001", phase="complete",
                     files_installed=True, panel_ready=True, api_token="fake-api-token",
                     base_path="/fake-panel/", private_key="p" * 43,
                     public_key="q" * 43, short_id="1122334455667788")
        for role, node in state["nodes"].items():
            node.update(uuid=role + "-fake-uuid", private_key=state["private_key"],
                        public_key=state["public_key"], short_id=state["short_id"])
        return state

    def test_failed_nginx_validation_restores_previous_config_without_service_changes(self):
        for existing in (False, True):
            with self.subTest(existing=existing):
                directory = self.root / ("existing" if existing else "fresh")
                directory.mkdir()
                conf, unit = directory / "nginx.conf", directory / "gateway.service"
                if existing:
                    conf.write_text("# previously validated config\n")
                    conf.chmod(0o600)
                with patch.object(self.app, "NGINX_CONF", conf), \
                        patch.object(self.app, "NGINX_UNIT", unit), \
                        patch.object(self.app, "NGINX_PID", directory / "run/nginx.pid"), \
                        patch.object(self.app, "run", side_effect=RuntimeError("nginx rejected candidate")) as run:
                    with self.assertRaisesRegex(RuntimeError, "nginx rejected"):
                        self.app.install_subscription_gateway(self.config(), self.state())
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.args[0][:2], ["/usr/sbin/nginx", "-t"])
                self.assertFalse(unit.exists())
                if existing:
                    self.assertEqual(conf.read_text(), "# previously validated config\n")
                    self.assertEqual(conf.stat().st_mode & 0o777, 0o600)
                else:
                    self.assertFalse(conf.exists())

    def test_renewal_checks_tls_and_reloads_gateway_restarting_only_public_https_panel(self):
        for public_panel in (False, True):
            with self.subTest(public_panel=public_panel):
                directory = self.root / ("https-panel" if public_panel else "ssh-panel")
                directory.mkdir()
                bin_dir, hooks = directory / "bin", directory / "hooks"
                bin_dir.mkdir()
                log = directory / "commands.log"
                for name in ("systemctl", "tls-check", "nginx-check"):
                    command = bin_dir / name
                    command.write_text("#!/bin/sh\nprintf '%s' \"${0##*/}\" >> \"$CALL_LOG\"\n"
                                       "printf ' %s' \"$@\" >> \"$CALL_LOG\"\n"
                                       "printf '\\n' >> \"$CALL_LOG\"\nexit 0\n")
                    command.chmod(0o700)
                config = self.config(PANEL_HTTPS=public_panel)
                with patch.object(self.app, "RENEW_HOOK_DIR", hooks), \
                        patch.object(self.app, "STATE_DIR", directory), \
                        patch.object(self.app, "NGINX_CONF", directory / "nginx.conf"):
                    self.app.install_renewal_hook(config)
                hook = hooks / ("3x-ui-bootstrap-" + config["SUB_HOST"])
                # Replace executable locations only, leaving the actual hook's
                # matching, ordering, and restart conditions unchanged.
                script = hook.read_text().replace("/usr/bin/python3", str(bin_dir / "tls-check"))
                script = script.replace("/usr/sbin/nginx", str(bin_dir / "nginx-check"))
                hook.write_text(script)
                environment = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                                   CALL_LOG=str(log), RENEWED_DOMAINS=config["SUB_HOST"])
                subprocess.run(["/bin/sh", str(hook)], env=environment, check=True, timeout=5)
                commands = log.read_text().splitlines()
                tls_index = next(i for i, line in enumerate(commands) if line.startswith("tls-check "))
                nginx_index = next(i for i, line in enumerate(commands) if line.startswith("nginx-check -t "))
                reload_index = commands.index("systemctl reload-or-restart " + self.app.NGINX_SERVICE)
                self.assertLess(tls_index, nginx_index)
                self.assertLess(nginx_index, reload_index)
                self.assertEqual("systemctl restart x-ui" in commands, public_panel)
                log.unlink()
                subprocess.run(["/bin/sh", str(hook)], env=dict(environment, RENEWED_DOMAINS="other.example.test"),
                               check=True, timeout=5)
                self.assertFalse(log.exists(), "Unrelated certificate renewals must not alter these services")

    def test_public_backend_or_wrong_public_owner_stops_both_services(self):
        config = self.config("direct")
        expected = [("127.0.0.1", config["PANEL_PORT"], 'users:(("x-ui",pid=1))'),
                    ("0.0.0.0", config["SUB_PORT"], 'users:(("nginx",pid=2))'),
                    ("127.0.0.1", config["SUB_BACKEND_PORT"], 'users:(("x-ui",pid=1))'),
                    ("0.0.0.0", config["NODE_PORT"], 'users:(("xray",pid=3))')]
        cases = []
        for address in ("0.0.0.0", "::", "[::]", "*", "127.0.0.2"):
            rows = list(expected)
            rows[2] = (address, config["SUB_BACKEND_PORT"], rows[2][2])
            cases.append(rows)
        rows = list(expected)
        rows[1] = ("0.0.0.0", config["SUB_PORT"], 'users:(("x-ui",pid=1))')
        cases.append(rows)
        for rows in cases:
            with self.subTest(rows=rows), ExitStack() as stack:
                for name in ("check_db", "check_subscription_gateway", "verify_core", "validate_tls"):
                    stack.enter_context(patch.object(self.app, name))
                stack.enter_context(patch.object(self.app, "service_active", return_value=True))
                stack.enter_context(patch.object(self.app, "native_exhausted", return_value=set()))
                stack.enter_context(patch.object(self.app, "sockets", return_value=rows))
                run = stack.enter_context(patch.object(self.app, "run"))
                with self.assertRaisesRegex(RuntimeError, "监听不符合"):
                    self.app.verify_runtime(config, self.state(), "amd64")
                self.assertEqual([call.args[0] for call in run.call_args_list],
                                 [["systemctl", "stop", self.app.NGINX_SERVICE], ["systemctl", "stop", "x-ui"]])

    def test_domain_change_rebuilds_gateway_before_final_verification(self):
        config = self.config("direct", SUB_DOMAIN="old.example.test")
        candidate = self.config("direct", SUB_DOMAIN="new.example.test")
        state = self.ready_state()
        db_path = self.root / "panel.db"
        with closing(sqlite3.connect(db_path)) as db, db:
            db.execute('CREATE TABLE settings ("key" TEXT, value TEXT)')
            db.executemany('INSERT INTO settings VALUES (?, ?)',
                           self.app.initial_settings(config, state).items())
        events = []
        with ExitStack() as stack:
            stack.enter_context(redirect_stdout(StringIO()))
            stack.enter_context(patch.object(self.app, "STATE_DIR", self.root))
            stack.enter_context(patch.object(self.app, "DB", db_path))
            stack.enter_context(patch.object(self.app, "domain_config", return_value=candidate))
            stack.enter_context(patch.object(self.app, "service_active", side_effect=[True, False]))
            for name in ("check_isp", "verify_core", "check_environment", "check_dns", "check_db",
                         "install_certbot", "ensure_certificate", "activate_certificate", "write_unit",
                         "wait_api", "save"):
                stack.enter_context(patch.object(self.app, name))
            stack.enter_context(patch.object(self.app, "API"))
            stack.enter_context(patch.object(self.app, "ensure_inbounds", return_value={}))
            stack.enter_context(patch.object(self.app, "write_results", return_value=""))
            stack.enter_context(patch.object(self.app, "run", side_effect=lambda args, **_: events.append(tuple(args))))
            install = stack.enter_context(patch.object(self.app, "install_subscription_gateway",
                                                        side_effect=lambda *_: events.append("install-gateway")))
            verify = stack.enter_context(patch.object(self.app, "verify_runtime",
                                                       side_effect=lambda *_: events.append("verify-runtime")))
            self.app.configure_domain(config, state, "amd64")
        install.assert_called_once_with(candidate, state)
        verify.assert_called_once_with(candidate, state, "amd64")
        self.assertLess(events.index("install-gateway"), events.index("verify-runtime"))
        self.assertLess(events.index(("systemctl", "stop", self.app.NGINX_SERVICE)),
                        events.index(("systemctl", "stop", "x-ui")))
        self.assertEqual(state["config"]["SUB_HOST"], "new.example.test")
        with closing(sqlite3.connect(db_path)) as db:
            settings = dict(db.execute('SELECT "key", value FROM settings'))
        self.assertEqual(settings["subDomain"], "new.example.test")
        self.assertEqual(settings["subListen"], "127.0.0.1")

    def test_changed_backend_database_stops_services_before_socket_checks(self):
        config, state = self.config("direct"), self.ready_state()
        database = self.root / "changed-backend.db"
        settings = self.app.initial_settings(config, state)
        settings["subListen"] = "0.0.0.0"
        with closing(sqlite3.connect(database)) as db, db:
            db.execute('CREATE TABLE settings ("key" TEXT, value TEXT)')
            db.executemany('INSERT INTO settings VALUES (?, ?)', settings.items())
        with patch.object(self.app, "DB", database), \
                patch.object(self.app, "run") as run, \
                patch.object(self.app, "sockets") as sockets, \
                patch.object(self.app, "check_subscription_gateway") as gateway:
            with self.assertRaisesRegex(RuntimeError, "设置已变化"):
                self.app.verify_runtime(config, state, "amd64")
        sockets.assert_not_called()
        gateway.assert_not_called()
        self.assertEqual([call.args[0] for call in run.call_args_list],
                         [["systemctl", "stop", self.app.NGINX_SERVICE], ["systemctl", "stop", "x-ui"]])

    def test_role_change_rebuilds_only_active_subscription_paths_before_verification(self):
        config, candidate = self.config(), self.config("direct")
        state = self.ready_state()
        db_path = self.root / "panel.db"
        with closing(sqlite3.connect(db_path)) as db, db:
            db.execute("CREATE TABLE backup_fixture (value TEXT)")
        row = {"id": 1, "tag": "inbound-443", "remark": config["NODE_NAME"], "port": 443,
               "protocol": "vless", "listen": "0.0.0.0", "enable": True,
               "shareAddrStrategy": "custom", "shareAddr": config["SERVER_IP"],
               "streamSettings": {"network": "tcp"}}
        routing = {"routing": {"rules": []}, "outbounds": []}
        target = {"routing": {"rules": [{"outboundTag": "direct"}]}, "outbounds": []}
        events, installed_paths = [], []

        def api_call(route, payload=None, **_):
            if route == "inbounds/list":
                return [deepcopy(row)]
            if route == "xray/update":
                routing.clear()
                routing.update(json.loads(payload["xraySetting"]))
                return True
            raise AssertionError("Unexpected fake API call: " + route)

        api = Mock()
        api.call.side_effect = api_call

        def install(config_arg, state_arg):
            installed_paths.extend(self.app.subscription_paths(config_arg, state_arg))
            events.append("install-gateway")

        with ExitStack() as stack:
            stack.enter_context(redirect_stdout(StringIO()))
            stack.enter_context(patch.object(self.app, "STATE_DIR", self.root))
            stack.enter_context(patch.object(self.app, "DB", db_path))
            stack.enter_context(patch.object(self.app, "selected_node_config", return_value=candidate))
            stack.enter_context(patch.object(self.app, "service_active", return_value=True))
            stack.enter_context(patch.object(self.app, "API", return_value=api))
            stack.enter_context(patch.object(self.app, "read_routing", side_effect=lambda _: deepcopy(routing)))
            stack.enter_context(patch.object(self.app, "shared_node_template", return_value=target))
            stack.enter_context(patch.object(self.app, "plan_node_clients", return_value=[]))
            stack.enter_context(patch.object(self.app, "ensure_inbounds", return_value={"direct": row}))
            stack.enter_context(patch.object(self.app, "write_results", return_value=""))
            for name in ("check_environment", "check_isp", "verify_core", "validate_tls", "check_db",
                         "save", "apply_node_clients", "wait_api", "routing_matches"):
                stack.enter_context(patch.object(self.app, name))
            stack.enter_context(patch.object(self.app, "run", side_effect=lambda args, **_: events.append(tuple(args))))
            gateway = stack.enter_context(patch.object(self.app, "install_subscription_gateway", side_effect=install))
            stack.enter_context(patch.object(self.app, "verify_runtime",
                                             side_effect=lambda *_: events.append("verify-runtime")))
            self.app.configure_nodes(config, state, "amd64")
        gateway.assert_called_once_with(candidate, state)
        self.assertEqual(set(installed_paths), {"/sub/" + "a" * 16, "/mihomo/" + "a" * 16})
        self.assertLess(events.index(("systemctl", "stop", self.app.NGINX_SERVICE)),
                        events.index("install-gateway"))
        self.assertLess(events.index("install-gateway"), events.index("verify-runtime"))


if __name__ == "__main__":
    unittest.main()
