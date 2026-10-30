"""Shared ingress contracts; no root privileges, downloads, or live services."""
from copy import deepcopy
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit
import json
import tempfile
import unittest
from unittest.mock import patch

from _loader import load_installer


class FakePanel:
    """Small native-client API model, with counters independent of inbounds."""

    def __init__(self):
        self.rows = []
        self.details = {}
        self.add_calls = 0
        self.key_calls = 0
        self.lose_add_response = False
        self.lose_client_add_response = False
        self.lose_update_response = False
        self.client_add_calls = 0
        self.updates = []

    def call(self, route, payload=None, form=False):
        if route == "server/getNewX25519Cert":
            self.key_calls += 1
            return {"privateKey": "a" * 43, "publicKey": "b" * 43}
        if route == "inbounds/list":
            return deepcopy(self.rows)
        if route == "inbounds/add":
            self.add_calls += 1
            row = dict(deepcopy(payload), id=1, tag="inbound-443")
            self.rows.append(row)
            for client in json.loads(row["settings"])["clients"]:
                record = dict(client, id=len(self.details) + 1, uuid=client["id"], createdAt=1792281600000)
                self.details[client["email"]] = {"client": record, "inboundIds": [1], "usedTraffic": 0}
            if self.lose_add_response:
                self.lose_add_response = False
                raise RuntimeError("response lost after successful create")
            return deepcopy(row)
        if route.startswith("clients/get/"):
            return deepcopy(self.details[unquote(route.split("clients/get/", 1)[1])])
        if route == "clients/add":
            self.client_add_calls += 1
            client = deepcopy(payload["client"])
            for row in self.rows:
                if row["id"] in payload["inboundIds"]:
                    settings = json.loads(row["settings"])
                    settings["clients"].append(client)
                    row["settings"] = json.dumps(settings)
            record = dict(client, id=len(self.details) + 1, uuid=client["id"], createdAt=1792281600000)
            self.details[client["email"]] = {"client": record, "inboundIds": payload["inboundIds"], "usedTraffic": 0}
            if self.lose_client_add_response:
                self.lose_client_add_response = False
                raise RuntimeError("response lost after successful client add")
            return True
        if route.startswith("clients/update/"):
            email = unquote(route.split("clients/update/", 1)[1].split("?", 1)[0])
            self.updates.append((route, deepcopy(payload)))
            record = self.details[email]["client"]
            record.update({key: value for key, value in payload.items() if key != "id"})
            record["uuid"] = payload["id"]
            for row in self.rows:
                settings = json.loads(row["settings"])
                settings["clients"] = [dict(client, **payload) if client["email"] == email else client
                                       for client in settings["clients"]]
                row["settings"] = json.dumps(settings)
            if payload["email"] != email:
                self.details[payload["email"]] = self.details.pop(email)
            if self.lose_update_response:
                self.lose_update_response = False
                raise RuntimeError("response lost after successful client update")
            return True
        raise AssertionError("Unexpected panel route: " + route)


class SharedInboundTests(unittest.TestCase):
    def setUp(self):
        self.app = load_installer()

    def config(self, mode="direct+isp", **changes):
        values = dict(self.app.CONFIG_DEFAULTS, SERVER_IP="8.8.8.8", NODE_NAME="SharedTest", NODE_MODE=mode,
                      ISP_HOST="proxy.example.com", ISP_PORT=1080, ISP_USERNAME="fake-user", ISP_PASSWORD="fake-pass")
        values.update(changes)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            path.write_text(json.dumps(values))
            path.chmod(0o600)
            return self.app.parse_config(self.app.load_config_values(path))

    def state(self, c, api):
        state = {"config": c, "uuid": "00000000-0000-4000-8000-000000000001",
                 "short_id": "1122334455667788", "sub_id": "initial-sub", "base_path": "/panel-test/",
                 "traffic_reset": {"day": 18, "timezone": "UTC", "deployment_date": "2026-10-18"}}
        self.app.prepare_nodes(c, state)
        with patch.object(self.app, "save"):
            self.app.ensure_node_keys(api, c, state)
        return state

    def test_one_keypair_is_reused_for_distinct_authenticated_client_links(self):
        c, api = self.config(), FakePanel()
        state = self.state(c, api)
        identities = deepcopy(state["nodes"])
        with patch.object(self.app, "save"):
            self.app.ensure_node_keys(api, c, state)
        self.assertEqual(api.key_calls, 1)
        self.assertEqual(state["nodes"], identities)
        direct_c, direct_s = self.app.node_view(c, state, "direct")
        isp_c, isp_s = self.app.node_view(c, state, "isp")
        direct = urlsplit(self.app.vless_link(direct_c, direct_s))
        isp = urlsplit(self.app.vless_link(isp_c, isp_s))
        self.assertEqual((direct.hostname, direct.port), (isp.hostname, isp.port))
        self.assertEqual(direct.port, 443)
        self.assertNotEqual(direct.username, isp.username)
        self.assertEqual(parse_qs(direct.query)["pbk"], parse_qs(isp.query)["pbk"])
        self.assertNotEqual(direct_s["sub_id"], isp_s["sub_id"])
        self.assertEqual(unquote(direct.fragment), "SharedTest-Direct")
        self.assertEqual(unquote(isp.fragment), "SharedTest-ISP")

    def test_shared_payload_keeps_per_client_caps_and_subscription_names(self):
        c, api = self.config(TOTAL_MONTHLY_GB=1000, ISP_MONTHLY_GB=100), FakePanel()
        state = self.state(c, api)
        payload = self.app.inbound_payload(c, state)
        self.assertEqual(payload["port"], 443)
        self.assertEqual(payload["remark"], "SharedTest")
        clients = {client["email"]: client for client in json.loads(payload["settings"])["clients"]}
        self.assertEqual(set(clients), {"SharedTest-Direct", "SharedTest-ISP"})
        self.assertEqual(clients["SharedTest-Direct"]["totalGB"], 900 * 1024 ** 3)
        self.assertEqual(clients["SharedTest-ISP"]["totalGB"], 100 * 1024 ** 3)
        reality = json.loads(payload["streamSettings"])["realitySettings"]
        for role in ("direct", "isp"):
            _, node = self.app.node_view(c, state, role)
            self.assertEqual(node["private_key"], reality["privateKey"])
            self.assertIn(node["short_id"], reality["shortIds"])
        for client in clients.values():
            self.assertEqual(client["flow"], "xtls-rprx-vision")
            self.assertEqual((client["trafficReset"], client["trafficResetDay"]), ("monthly", 18))
        self.assertEqual(self.app.initial_settings(c, state)["remarkTemplate"], "{{EMAIL}}")

    def test_each_mode_creates_exactly_one_inbound_with_expected_clients(self):
        for mode, expected in (("direct", {"SharedTest-Direct"}), ("isp", {"SharedTest-ISP"}),
                               ("direct+isp", {"SharedTest-Direct", "SharedTest-ISP"})):
            with self.subTest(mode=mode):
                c, api = self.config(mode), FakePanel()
                state = self.state(c, api)
                rows = self.app.ensure_inbounds(api, c, state)
                self.app.ensure_inbounds(api, c, state)
                self.assertEqual(api.add_calls, 1)
                self.assertEqual({row["id"] for row in rows.values()}, {1})
                clients = json.loads(api.rows[0]["settings"])["clients"]
                self.assertEqual({client["email"] for client in clients}, expected)

    def test_retry_after_lost_create_response_does_not_duplicate_shared_inbound(self):
        c, api = self.config(), FakePanel()
        state = self.state(c, api)
        api.lose_add_response = True
        with self.assertRaisesRegex(RuntimeError, "response lost"):
            self.app.ensure_inbounds(api, c, state)
        rows = self.app.ensure_inbounds(api, c, state)
        self.assertEqual(api.add_calls, 1)
        self.assertEqual({row["id"] for row in rows.values()}, {1})

    def test_missing_isp_client_or_unknown_extra_client_is_rejected(self):
        for corruption in ("missing", "extra", "duplicate"):
            with self.subTest(corruption=corruption):
                c, api = self.config(), FakePanel()
                state = self.state(c, api)
                self.app.ensure_inbounds(api, c, state)
                row = api.rows[0]
                settings = json.loads(row["settings"])
                if corruption == "missing":
                    settings["clients"] = settings["clients"][:1]
                elif corruption == "extra":
                    settings["clients"].append(dict(settings["clients"][0], id="unmanaged-uuid", email="unknown"))
                else:
                    settings["clients"].append(deepcopy(settings["clients"][0]))
                row["settings"] = json.dumps(settings)
                with self.assertRaises(RuntimeError):
                    self.app.ensure_inbounds(api, c, state, allow_create=False)
                self.assertEqual(api.add_calls, 1)

    def test_clients_split_across_two_inbounds_are_rejected(self):
        c, api = self.config(), FakePanel()
        state = self.state(c, api)
        self.app.ensure_inbounds(api, c, state)
        row = api.rows[0]
        settings = json.loads(row["settings"])
        isp_client = settings["clients"].pop()
        row["settings"] = json.dumps(settings)
        second = dict(deepcopy(row), id=2, tag="inbound-other", port=8443)
        second["settings"] = json.dumps(dict(settings, clients=[isp_client]))
        api.rows.append(second)
        with self.assertRaises(RuntimeError):
            self.app.ensure_inbounds(api, c, state, allow_create=False)
        self.assertEqual(api.add_calls, 1)

    def test_quota_change_preserves_independent_counters_and_disabled_client(self):
        c, api = self.config(TOTAL_MONTHLY_GB=1000, ISP_MONTHLY_GB=100), FakePanel()
        state = self.state(c, api)
        self.app.ensure_inbounds(api, c, state)
        api.details["SharedTest-Direct"]["usedTraffic"] = 123456789
        api.details["SharedTest-ISP"]["usedTraffic"] = 12345
        api.details["SharedTest-ISP"]["client"]["enable"] = False
        candidate = self.config(TOTAL_MONTHLY_GB=1200, ISP_MONTHLY_GB=200)
        before = deepcopy(api.details)
        with patch.object(self.app, "API", return_value=api):
            self.assertTrue(self.app.apply_native_quotas(candidate, state))
        after = self.app.native_clients(api, candidate, state)
        for role, email, cap in (("direct", "SharedTest-Direct", 1000), ("isp", "SharedTest-ISP", 200)):
            self.assertEqual(after[role]["used"], before[email]["usedTraffic"])
            self.assertEqual(after[role]["record"]["subId"], before[email]["client"]["subId"])
            self.assertEqual(after[role]["record"]["uuid"], before[email]["client"]["uuid"])
            self.assertEqual(after[role]["record"]["enable"], before[email]["client"]["enable"])
            self.assertEqual(after[role]["record"]["totalGB"], cap * 1024 ** 3)
            self.assertEqual(after[role]["record"]["trafficResetDay"], 18)
        self.assertEqual(after["direct"]["row"]["id"], after["isp"]["row"]["id"])
        with patch.object(self.app, "API", return_value=api):
            self.assertFalse(self.app.apply_native_quotas(candidate, state))

    def test_one_exhausted_client_keeps_other_client_available_on_shared_port(self):
        c, api = self.config(TOTAL_MONTHLY_GB=1000, ISP_MONTHLY_GB=100), FakePanel()
        state = self.state(c, api)
        self.app.ensure_inbounds(api, c, state)
        api.details["SharedTest-ISP"]["usedTraffic"] = 100 * 1024 ** 3
        with patch.object(self.app, "API", return_value=api):
            self.assertEqual(self.app.native_exhausted(c, state), {"isp"})
        self.assertTrue(api.rows[0]["enable"])
        self.assertEqual(self.app.node_ports(c), [443])

    def test_route_validation_rejects_catchalls_and_reordered_fallback(self):
        c = self.config()
        row = {"tag": "inbound-443"}
        rows = {"direct": row, "isp": row}
        intended = self.app.route_rules(c, rows)
        outbounds = [{"tag": "direct", "protocol": "freedom"},
                     {"tag": "blocked", "protocol": "blackhole"}, self.app.isp_outbound(c)]
        self.app.routing_matches({"outbounds": outbounds, "routing": {"rules": intended}}, c, rows)
        bad_rules = [
            [{"type": "field", "inboundTag": ["inbound-443"], "outboundTag": "direct"}] + intended,
            [{"type": "field", "outboundTag": "direct"}] + intended,
            [intended[-1]] + intended[:-1],
            intended[:-1],
        ]
        for rules in bad_rules:
            with self.subTest(rules=rules), self.assertRaises(RuntimeError):
                self.app.routing_matches({"outbounds": outbounds, "routing": {"rules": rules}}, c, rows)

    def test_routing_does_not_send_unknown_clients_to_direct_or_isp(self):
        # Evaluate only the selectors generated here, retaining Xray's first-match semantics.
        c = self.config()
        row = {"tag": "inbound-443"}
        rules = self.app.route_rules(c, {"direct": row, "isp": row})

        def exit_for(email, network):
            for rule in rules:
                if "user" in rule and email not in rule["user"]:
                    continue
                if "network" in rule and network not in rule["network"].split(","):
                    continue
                return rule["outboundTag"]
            return None

        self.assertEqual(exit_for("SharedTest-Direct", "tcp"), "direct")
        self.assertEqual(exit_for("SharedTest-ISP", "tcp"), "bootstrap-isp")
        self.assertEqual(exit_for("SharedTest-ISP", "udp"), "blocked")
        self.assertEqual(exit_for("unknown-client", "tcp"), "blocked")

    def test_switch_to_direct_disables_only_isp_client_and_preserves_its_meter(self):
        c, api = self.config(TOTAL_MONTHLY_GB=1000, ISP_MONTHLY_GB=100), FakePanel()
        state = self.state(c, api)
        row = self.app.ensure_inbounds(api, c, state)["direct"]
        api.details["SharedTest-ISP"]["usedTraffic"] = 234567
        original = deepcopy(api.details["SharedTest-ISP"])
        candidate = self.config("direct", TOTAL_MONTHLY_GB=1000)
        clients = self.app.plan_node_clients(api, c, candidate, state, row)
        plan = {"inbound_id": row["id"], "clients": clients}
        self.app.apply_node_clients(api, plan, state)
        self.assertTrue(api.rows[0]["enable"])
        self.assertTrue(api.details["SharedTest-Direct"]["client"]["enable"])
        isp = api.details["SharedTest-ISP"]
        self.assertFalse(isp["client"]["enable"])
        self.assertEqual(isp["client"]["trafficReset"], "never")
        for field in ("uuid", "subId", "totalGB", "createdAt"):
            self.assertEqual(isp["client"][field], original["client"][field])
        self.assertEqual(isp["usedTraffic"], original["usedTraffic"])
        self.assertEqual(isp["inboundIds"], [row["id"]])
        self.app.ensure_inbounds(api, candidate, state, allow_create=False)

    def test_adding_isp_reuses_shared_inbound_after_lost_client_add_response(self):
        c, api = self.config("direct"), FakePanel()
        state = self.state(c, api)
        row = self.app.ensure_inbounds(api, c, state)["direct"]
        direct = deepcopy(api.details["SharedTest-Direct"])
        candidate = self.config()
        self.app.prepare_nodes(candidate, state)
        with patch.object(self.app, "save"):
            self.app.ensure_node_keys(api, candidate, state)
        clients = self.app.plan_node_clients(api, c, candidate, state, row)
        plan = {"inbound_id": row["id"], "clients": clients}
        api.lose_client_add_response = True
        with self.assertRaisesRegex(RuntimeError, "response lost"):
            self.app.apply_node_clients(api, plan, state)
        self.app.apply_node_clients(api, plan, state)
        self.assertEqual(api.add_calls, 1)
        self.assertEqual(api.client_add_calls, 1)
        self.assertEqual(api.key_calls, 1)
        self.assertEqual(api.details["SharedTest-Direct"], direct)
        self.assertEqual(api.details["SharedTest-ISP"]["inboundIds"], [row["id"]])
        self.app.ensure_inbounds(api, candidate, state, allow_create=False)

    def test_switch_to_isp_keeps_shared_listener_when_original_client_is_disabled(self):
        c, api = self.config(), FakePanel()
        state = self.state(c, api)
        row = self.app.ensure_inbounds(api, c, state)["direct"]
        candidate = self.config("isp")
        clients = self.app.plan_node_clients(api, c, candidate, state, row)
        self.app.apply_node_clients(api, {"inbound_id": row["id"], "clients": clients}, state)
        self.assertFalse(api.details["SharedTest-Direct"]["client"]["enable"])
        self.assertTrue(api.details["SharedTest-ISP"]["client"]["enable"])
        self.assertTrue(api.rows[0]["enable"])
        self.assertEqual(self.app.managed_inbound(api, state)["id"], row["id"])
        self.app.ensure_inbounds(api, candidate, state, allow_create=False)

    def test_rename_retry_preserves_uuid_subscription_and_traffic(self):
        c, api = self.config(), FakePanel()
        state = self.state(c, api)
        row = self.app.ensure_inbounds(api, c, state)["direct"]
        api.details["SharedTest-Direct"]["usedTraffic"] = 7654321
        api.details["SharedTest-ISP"]["usedTraffic"] = 123456
        before = deepcopy(api.details)
        candidate = self.config(NODE_NAME="Renamed")
        clients = self.app.plan_node_clients(api, c, candidate, state, row)
        plan = {"inbound_id": row["id"], "clients": clients}
        api.lose_update_response = True
        with self.assertRaisesRegex(RuntimeError, "response lost"):
            self.app.apply_node_clients(api, plan, state)
        self.app.apply_node_clients(api, plan, state)
        self.assertEqual(len(api.updates), 2)
        for role in ("Direct", "ISP"):
            old, new = before["SharedTest-" + role], api.details["Renamed-" + role]
            self.assertEqual(new["usedTraffic"], old["usedTraffic"])
            self.assertEqual(new["client"]["uuid"], old["client"]["uuid"])
            self.assertEqual(new["client"]["subId"], old["client"]["subId"])
        self.assertEqual(len(api.rows), 1)
        self.assertEqual(api.rows[0]["port"], 443)

    def test_routing_reconfiguration_changes_only_managed_clients(self):
        c = self.config()
        row = {"tag": "inbound-443"}
        unrelated = {"type": "field", "inboundTag": ["other"], "outboundTag": "other-out"}
        other_outbound = {"tag": "other-out", "protocol": "freedom"}
        template = {"outbounds": [{"tag": "direct", "protocol": "freedom"},
                                   {"tag": "blocked", "protocol": "blackhole"},
                                   self.app.isp_outbound(c), other_outbound],
                    "routing": {"rules": [unrelated] + self.app.route_rules(c, {"direct": row, "isp": row})}}
        before = deepcopy(template)
        candidate = self.config("direct")
        target = self.app.shared_node_template(template, c, candidate, row)
        self.assertEqual(template, before)
        self.assertIn(unrelated, target["routing"]["rules"])
        self.assertIn(other_outbound, target["outbounds"])
        self.assertNotIn("bootstrap-isp", {outbound["tag"] for outbound in target["outbounds"]})
        self.assertFalse(any(rule.get("user") == ["SharedTest-ISP"] for rule in target["routing"]["rules"]))
        self.app.routing_matches(target, candidate, {"direct": row})



if __name__ == "__main__":
    unittest.main()
