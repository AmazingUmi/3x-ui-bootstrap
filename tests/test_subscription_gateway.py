"""Subscription access-control contracts, including a real local Nginx gateway.

The integration fixture uses only generated credentials and loopback high ports.
It never reads a deployment config, talks to an external service, or needs root.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import http.client
import json
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from _loader import load_installer


class GatewayFixture:
    def config(self, mode="direct+isp", **changes):
        values = dict(self.app.CONFIG_DEFAULTS, SERVER_IP="8.8.8.8", NODE_NAME="GatewayTest",
                      NODE_MODE=mode, SUB_DOMAIN="sub.example.test", ISP_HOST="proxy.example.test",
                      ISP_PORT=1080, ISP_USERNAME="fake-user", ISP_PASSWORD="fake-pass")
        values.update(changes)
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "config.json"
            file.write_text(json.dumps(values))
            file.chmod(0o600)
            return self.app.parse_config(self.app.load_config_values(file))

    @staticmethod
    def state():
        return {"raw_sub_path": "/sub/", "nodes": {
            "direct": {"sub_id": "a" * 16}, "isp": {"sub_id": "b" * 16}}}


class SubscriptionGatewayContracts(GatewayFixture, unittest.TestCase):
    def setUp(self):
        self.app = load_installer()

    def test_only_active_roles_receive_download_routes(self):
        state = self.state()
        for mode, tokens in (("direct", ("a" * 16,)), ("isp", ("b" * 16,)),
                             ("direct+isp", ("a" * 16, "b" * 16))):
            with self.subTest(mode=mode):
                paths = self.app.subscription_paths(self.config(mode), state)
                self.assertEqual(set(paths), {prefix + token for token in tokens
                                             for prefix in ("/sub/", "/mihomo/")})
                self.assertEqual(len(paths), len(set(paths)))
        self.assertEqual(state, self.state(), "Rendering must not change stored identities")

    def test_invalid_or_repeated_subscription_tokens_fail_closed(self):
        config = self.config()
        for token in ("", "a" * 15, "a" * 17, "A" * 16, "g" * 16, "../assets/file",
                      "a" * 16 + "?html=1", "x; return 200; #", "x\n}", None, 123):
            with self.subTest(token=token):
                state = self.state()
                state["nodes"]["direct"]["sub_id"] = token
                with self.assertRaises(RuntimeError):
                    self.app.render_subscription_nginx(config, state)
        duplicate = self.state()
        duplicate["nodes"]["isp"]["sub_id"] = duplicate["nodes"]["direct"]["sub_id"]
        with self.assertRaises(RuntimeError):
            self.app.render_subscription_nginx(config, duplicate)

    def test_gateway_keeps_public_subscription_links_on_public_port(self):
        config = self.config(SUB_PORT=32096, SUB_BACKEND_PORT=42096)
        link = self.app.mihomo_link(config, {"sub_id": "a" * 16})
        self.assertEqual(link, "https://sub.example.test:32096/mihomo/" + "a" * 16)
        self.assertNotIn("42096", link)

    def test_valid_quota_and_refresh_headers_are_accepted(self):
        for info in ("upload=10; download=20; total=1000; expire=0",
                     "total=0;expire=0;upload=0;download=0",
                     "expire=1793397600; upload=1234567890123; download=2; total=1234567890124"):
            with self.subTest(info=info):
                self.app.verify_subscription_usage({"subscription-userinfo": info,
                                                    "profile-update-interval": "12"})

    def test_missing_or_invalid_usage_headers_are_rejected(self):
        valid = {"subscription-userinfo": "upload=10; download=20; total=1000; expire=0",
                 "profile-update-interval": "12"}
        invalid = ({}, {"profile-update-interval": "12"},
                   dict(valid, **{"subscription-userinfo": "upload=10; download=20; total=1000"}),
                   dict(valid, **{"subscription-userinfo": "upload=-1; download=20; total=1000; expire=0"}),
                   dict(valid, **{"subscription-userinfo": "upload=1.5; download=20; total=1000; expire=0"}),
                   {"subscription-userinfo": valid["subscription-userinfo"]},
                   dict(valid, **{"profile-update-interval": "unknown"}),
                   dict(valid, **{"profile-update-interval": "-1"}))
        for headers in invalid:
            with self.subTest(headers=headers), self.assertRaises(RuntimeError):
                self.app.verify_subscription_usage(headers)

    def test_http_200_without_usage_headers_cannot_pass_subscription_acceptance(self):
        config = self.config("direct")
        state = {"sub_id": "a" * 16}
        with patch.object(self.app, "https_request", return_value=(200, b"subscription-data", {})):
            for operation in (self.app.fetch_subscription, self.app.verify_shadowrocket):
                with self.subTest(operation=operation.__name__), self.assertRaisesRegex(RuntimeError, "流量/额度"):
                    operation(config, state)


class SubscriptionBackend(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        self.respond()

    def do_HEAD(self):
        self.respond()

    def respond(self):
        self.server.requests.append({"method": self.command, "path": self.path,
                                     "headers": dict(self.headers)})
        # Deliberately unsafe backend: a gateway failure would expose this body.
        is_html = "text/html" in self.headers.get("Accept", "") or "?" in self.path
        body = b"3x-ui browser page and static resources" if is_html else b"subscription-data"
        self.send_response(200)
        self.send_header("Content-Type", "text/html" if is_html else "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Subscription-Userinfo", "upload=10; download=20; total=1000; expire=0")
        self.send_header("Profile-Update-Interval", "12")
        self.send_header("Profile-Web-Page-Url", "https://sub.example.test/sub/fake?html=1")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)


class GatewayProcessFixture(GatewayFixture):
    subscription_domain = "sub.example.test"

    @classmethod
    def setUpClass(cls):
        cls.app = load_installer()
        cls.directory = tempfile.TemporaryDirectory(prefix="3x-ui-gateway-test-")
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        cert, key = cls.root / "cert.pem", cls.root / "key.pem"
        certificate_host = cls.subscription_domain or "8.8.8.8"
        certificate_san = ("DNS:" if cls.subscription_domain else "IP:") + certificate_host
        subprocess.run([shutil.which("openssl"), "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", str(key), "-out", str(cert), "-days", "1",
                        "-subj", "/CN=" + certificate_host, "-addext", "subjectAltName=" + certificate_san],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        cls.backend = ThreadingHTTPServer(("127.0.0.1", 0), SubscriptionBackend)
        cls.backend.daemon_threads = True
        cls.backend.requests = []
        cls.thread = threading.Thread(target=cls.backend.serve_forever, daemon=True)
        cls.thread.start()
        cls.addClassCleanup(cls.backend.server_close)
        cls.addClassCleanup(cls.backend.shutdown)
        with socket.socket() as port_holder:
            port_holder.bind(("127.0.0.1", 0))
            cls.public_port = port_holder.getsockname()[1]
        # Use the production parser and renderer, with only ephemeral resources.
        fixture = cls(methodName="runTest")
        cls.config_data = fixture.config(SUB_DOMAIN=cls.subscription_domain, SUB_PORT=cls.public_port,
                                         SUB_BACKEND_PORT=cls.backend.server_port)
        cls.config_data.update(CERT_FILE=str(cert), CERT_KEY=str(key))
        with patch.object(cls.app, "NGINX_PID", cls.root / "nginx.pid"), \
                patch.object(cls.app, "NGINX_ERROR_LOG", cls.root / "nginx-error.log"):
            rendered = cls.app.render_subscription_nginx(cls.config_data, cls.state())
        # User/paths/bind address are host-specific; routing and header policy are
        # the unmodified production output. Never expose test ports off-host.
        rendered = re.sub(r"(?m)^\s*user\s+[^;]+;", "", rendered)
        rendered = rendered.replace("listen 0.0.0.0:", "listen 127.0.0.1:")
        rendered = rendered.replace("listen [::]:", "listen [::1]:")
        rendered = re.sub(r"(?m)^\s*(?:daemon|master_process)\s+[^;]+;", "", rendered)
        rendered = rendered.replace("http {", "http {\n"
                                    + "    client_body_temp_path " + str(cls.root / "client-body") + ";\n"
                                    + "    proxy_temp_path " + str(cls.root / "proxy-temp") + ";\n"
                                    + "    fastcgi_temp_path " + str(cls.root / "fastcgi-temp") + ";\n"
                                    + "    uwsgi_temp_path " + str(cls.root / "uwsgi-temp") + ";\n"
                                    + "    scgi_temp_path " + str(cls.root / "scgi-temp") + ";\n", 1)
        cls.conf = cls.root / "nginx.conf"
        cls.conf.write_text(rendered)
        cls.conf.chmod(0o600)
        nginx = shutil.which("nginx")
        check = subprocess.run([nginx, "-p", str(cls.root) + "/", "-c", str(cls.conf), "-t"],
                               capture_output=True, text=True, timeout=15)
        if check.returncode:
            raise AssertionError("Generated Nginx config rejected: " + check.stderr)
        cls.output = (cls.root / "process.log").open("w+")
        cls.addClassCleanup(cls.output.close)
        cls.nginx = subprocess.Popen([nginx, "-p", str(cls.root) + "/", "-c", str(cls.conf),
                                      "-g", "daemon off; master_process off;"],
                                     stdout=cls.output, stderr=cls.output)
        cls.addClassCleanup(cls.stop_nginx)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if cls.nginx.poll() is not None:
                cls.output.seek(0)
                raise AssertionError("Nginx did not start: " + cls.output.read())
            try:
                with socket.create_connection(("127.0.0.1", cls.public_port), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            raise AssertionError("Nginx did not begin listening")

    @classmethod
    def stop_nginx(cls):
        if cls.nginx.poll() is None:
            cls.nginx.terminate()
            try:
                cls.nginx.wait(timeout=5)
            except subprocess.TimeoutExpired:
                cls.nginx.kill()
                cls.nginx.wait(timeout=5)

    def request(self, path, method="GET", **headers):
        connection = http.client.HTTPSConnection("127.0.0.1", self.public_port, timeout=5,
                                                  context=ssl._create_unverified_context())
        try:
            connection.request(method, path, headers={"Host": self.config_data["SUB_HOST"],
                                                     "User-Agent": "Mihomo/test", **headers})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()


@unittest.skipUnless(shutil.which("nginx") and shutil.which("openssl"),
                     "real gateway checks require local nginx and openssl")
class SubscriptionGatewayHTTP(GatewayProcessFixture, unittest.TestCase):
    def test_effective_subscriptions_keep_refresh_headers_and_client_identity(self):
        for prefix, agent in (("/sub/", "Shadowrocket/test"), ("/mihomo/", "Mihomo/test")):
            for token in ("a" * 16, "b" * 16):
                with self.subTest(prefix=prefix, token=token):
                    before = len(self.backend.requests)
                    path = prefix + token
                    status, headers, body = self.request(path, **{"User-Agent": agent})
                    self.assertEqual(status, 200)
                    self.assertEqual(body, b"subscription-data")
                    lower = {k.lower(): v for k, v in headers.items()}
                    self.assertEqual(lower["subscription-userinfo"],
                                     "upload=10; download=20; total=1000; expire=0")
                    self.assertEqual(lower["profile-update-interval"], "12")
                    self.assertNotIn("profile-web-page-url", lower)
                    self.assertEqual(len(self.backend.requests), before + 1)
                    seen = self.backend.requests[-1]
                    self.assertEqual(seen["path"], path)
                    self.assertEqual(seen["headers"]["User-Agent"], agent)
                    self.assertEqual(seen["headers"]["Host"], self.config_data["SUB_HOST"])

    def test_head_retains_quota_headers_without_response_body(self):
        status, headers, body = self.request("/mihomo/" + "a" * 16, method="HEAD")
        self.assertEqual((status, body), (200, b""))
        self.assertIn("subscription-userinfo", {k.lower() for k in headers})
        self.assertEqual(self.backend.requests[-1]["method"], "HEAD")

    def test_scanner_paths_unknown_ids_and_resource_aliases_never_reach_backend(self):
        paths = ("/", "/assets", "/assets/", "/assets/AppSidebar-test.js", "/sub/assets/",
                 "/sub/assets/AppSidebar-test.js", "/sub/anything/assets/AppSidebar-test.js",
                 "/sub/" + "a" * 16 + "/assets/AppSidebar-test.js", "/robots.txt", "/favicon.ico",
                 "/sub/", "/mihomo/", "/sub/" + "c" * 16, "/mihomo/" + "c" * 16,
                 "/json/" + "a" * 16, "/sub/" + "a" * 16 + "/")
        for path in paths:
            with self.subTest(path=path):
                before = len(self.backend.requests)
                status, _, _ = self.request(path)
                self.assertEqual(status, 404)
                self.assertEqual(len(self.backend.requests), before)

    def test_noncanonical_urls_and_html_queries_never_reach_backend(self):
        token = "a" * 16
        paths = ("/sub/" + token + "?html=1", "/sub/" + token + "?view=html",
                 "/sub/" + token + "?format=info", "/mihomo/" + token + "?x=1",
                 "/sub/" + token + "?", "//sub/" + token, "/sub//" + token,
                 "/unused/../sub/" + token, "/sub/./" + token, "/%73ub/" + token,
                 "/sub/%61" + token[1:], "/sub/" + token + "%3fhtml=1")
        for path in paths:
            with self.subTest(path=path):
                before = len(self.backend.requests)
                status, _, _ = self.request(path)
                self.assertEqual(status, 404)
                self.assertEqual(len(self.backend.requests), before)

    def test_browser_accept_is_normalized_and_untrusted_headers_are_removed(self):
        path = "/sub/" + "a" * 16
        status, _, body = self.request(path, Accept="text/html", Cookie="fake=secret",
                                       Authorization="Bearer fake", **{"X-Forwarded-For": "10.0.0.1"})
        self.assertEqual((status, body), (200, b"subscription-data"))
        headers = {k.lower(): v for k, v in self.backend.requests[-1]["headers"].items()}
        self.assertEqual(headers["accept"], "*/*")
        self.assertNotIn("cookie", headers)
        self.assertNotIn("authorization", headers)
        self.assertNotIn("x-forwarded-for", headers)

    def test_wrong_hosts_and_write_methods_never_reach_backend(self):
        path = "/mihomo/" + "a" * 16
        for host in ("other.example.test", "127.0.0.1", "sub.example.test.evil.test"):
            with self.subTest(host=host):
                before = len(self.backend.requests)
                self.assertEqual(self.request(path, Host=host)[0], 404)
                self.assertEqual(len(self.backend.requests), before)
        for method in ("POST", "PUT", "PATCH", "DELETE", "OPTIONS"):
            with self.subTest(method=method):
                before = len(self.backend.requests)
                self.assertEqual(self.request(path, method=method)[0], 404)
                self.assertEqual(len(self.backend.requests), before)


@unittest.skipUnless(shutil.which("nginx") and shutil.which("openssl"),
                     "real gateway checks require local nginx and openssl")
class SubscriptionGatewayIPHTTP(GatewayProcessFixture, unittest.TestCase):
    subscription_domain = ""

    def test_ip_subscription_reaches_backend_and_preserves_usage(self):
        status, headers, body = self.request("/sub/" + "a" * 16,
                                             **{"User-Agent": "Shadowrocket/test"})
        self.assertEqual((status, body), (200, b"subscription-data"))
        lower = {k.lower(): v for k, v in headers.items()}
        self.assertEqual(lower["subscription-userinfo"], "upload=10; download=20; total=1000; expire=0")
        self.assertEqual(lower["profile-update-interval"], "12")
        self.assertNotIn("profile-web-page-url", lower)
        self.assertEqual(self.backend.requests[-1]["headers"]["Host"], "8.8.8.8")
        self.assertEqual(self.config_data["SUB_DOMAIN"], "")


if __name__ == "__main__":
    unittest.main()
