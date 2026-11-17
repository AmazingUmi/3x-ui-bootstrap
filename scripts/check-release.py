#!/usr/bin/env python3
"""Offline upstream-binary smoke test, ONLY in a disposable Linux container.

Mount this repository and verified release archives read-only. The test starts
local services without systemd and does not exercise ACME, ISP, or real clients.
Certbot dependency wheels must be available in /opt/certbot-wheels.
"""
import argparse
import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from _loader import load_installer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != "Linux" or not Path("/.dockerenv").is_file() or os.geteuid() != 0:
        raise SystemExit("Run only as root inside a disposable Docker container with --network none.")
    if any(name != "lo" for _, name in socket.if_nameindex()):
        raise SystemExit("The release smoke test requires --network none (loopback only).")
    app = load_installer()
    arch = {"x86_64": "amd64", "aarch64": "arm64"}[platform.machine()]
    app.STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=False)
    app.DB.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    app.ENV.update(PIP_NO_INDEX="1", PIP_FIND_LINKS="/opt/certbot-wheels")

    def cache(source, target, digest):
        source = args.assets / source
        if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
            raise RuntimeError("Release checksum mismatch: " + source.name)
        shutil.copyfile(source, app.STATE_DIR / target)

    cache("x-ui-linux-" + arch + ".tar.gz", "x-ui-" + app.VERSION + "-" + arch + ".tar.gz", app.DIGESTS[arch])
    for version, assets in app.CORE_RELEASES.items():
        name, digest = assets[arch]
        cache(("" if version == app.CORE_VERSION else "old-") + name,
              "xray-" + version + "-" + arch + ".zip", digest)
    cache("certbot-" + app.CERTBOT_VERSION + "-py3-none-any.whl",
          "certbot-" + app.CERTBOT_VERSION + "-py3-none-any.whl", app.CERTBOT_SHA256)

    processes = {}
    logs = {}
    original_run = app.run

    def stop(name):
        process = processes.pop(name, None)
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)

    def start(name):
        if name in processes and processes[name].poll() is None:
            return
        if name == "x-ui":
            command, cwd = [str(app.APP / "x-ui")], app.APP
        else:
            command, cwd = ["nginx", "-c", str(app.NGINX_CONF), "-g", "daemon off;"], None
        if name not in logs:
            logs[name] = (app.STATE_DIR / (name + "-smoke.log")).open("ab")
        log = logs[name]
        processes[name] = subprocess.Popen(command, cwd=cwd, env=app.ENV, stdout=log, stderr=log,
                                            start_new_session=True)
        if name != "x-ui":
            for _ in range(50):
                if processes[name].poll() is not None:
                    raise RuntimeError("Test Nginx exited; see container-private log")
                if any(port == config["SUB_PORT"] for _, port, _ in app.sockets()):
                    return
                time.sleep(0.1)
            raise RuntimeError("Test Nginx did not start")

    def run(command, **kwargs):
        if command[0] == "systemctl":
            operation, name = command[1:3]
            if operation == "stop":
                stop(name)
            elif operation == "start":
                start(name)
            else:
                raise RuntimeError("Unexpected service operation in smoke test")
            return None
        return original_run(command, **kwargs)

    app.run = run
    app.service_active = lambda: "x-ui" in processes and processes["x-ui"].poll() is None
    values = dict(app.CONFIG_DEFAULTS, SERVER_IP="8.8.8.8", SUB_DOMAIN="sub.example.test",
                  NODE_NAME="Smoke", NODE_MODE="direct+isp", ISP_HOST="proxy.example.test",
                  ISP_PORT=1080, ISP_USERNAME="fixture", ISP_PASSWORD="fixture-only",
                  TOTAL_MONTHLY_GB=10, ISP_MONTHLY_GB=2)
    file = app.STATE_DIR / "fixture.json"
    file.write_text(json.dumps(values))
    file.chmod(0o600)
    app.INPUT_CONFIG = app.load_config_values(file)
    config = app.config_from_file()
    config.update(CERT_FILE="/tmp/bootstrap-test.crt", CERT_KEY="/tmp/bootstrap-test.key")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-keyout", config["CERT_KEY"], "-out", config["CERT_FILE"],
                    "-subj", "/CN=sub.example.test", "-addext", "subjectAltName=DNS:sub.example.test"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.copyfile(config["CERT_FILE"], "/usr/local/share/ca-certificates/bootstrap-test.crt")
    subprocess.run(["update-ca-certificates"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    state = {"owner": app.OWNER, "version": app.VERSION, "config": config,
             "username": "fixture-admin", "password": secrets.token_urlsafe(24),
             "base_path": "/" + secrets.token_hex(12) + "/", "uuid": str(uuid.uuid4()),
             "short_id": secrets.token_hex(8), "sub_id": secrets.token_hex(8),
             "phase": "complete", "deployed_at": int(time.time()), "core_version": app.CORE_VERSION}
    app.prepare_nodes(config, state)
    try:
        app.install_release(arch)
        app.install_core(arch, app.CORE_VERSION)
        app.install_certbot()
        app.install_log_rotation()
        subprocess.run(["logrotate", "--debug", str(app.LOGROTATE_CONF)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("PASS", arch, "verified releases, Certbot venv and logrotate syntax", flush=True)
        app.harden_initial_db(config, state)
        token = app.run([str(app.APP / "x-ui"), "setting", "-getApiToken", "-tokenName", app.OWNER,
                         "-tokenScope", "admin"], capture=True, cwd=app.APP)
        match = re.search(r"(?m)^apiToken:\s*(\S+)\s*$", token)
        if match is None:
            raise RuntimeError("CLI did not return an API token")
        state["api_token"] = match[1]
        start("x-ui")
        api = app.API(config, state)
        app.wait_api(api)
        app.ensure_node_keys(api, config, state)
        app.bind_traffic_reset(config, state)
        rows = app.ensure_inbounds(api, config, state)
        app.ensure_routing(api, config, state, rows, allow_update=True)
        stop("x-ui")
        start("x-ui")
        app.wait_api(api)
        app.ensure_inbounds(api, config, state, allow_create=False)
        app.verify_native_metering(api)
        baseline = {role: {k: item["record"][k] for k in ("uuid", "subId", "totalGB", "trafficResetDay")}
                    for role, item in app.native_clients(api, config, state).items()}
        identity = copy.deepcopy(state["nodes"])
        print("PASS", arch, "3x-ui CLI, API, shared inbound and native monthly quotas", flush=True)
        app.NGINX_PID.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        app.atomic_write(app.NGINX_CONF, app.render_subscription_nginx(config, state))
        app.run(["nginx", "-t", "-c", str(app.NGINX_CONF)])
        start(app.NGINX_SERVICE)

        def local_runtime(candidate, saved, architecture):
            app.check_db(candidate, saved)
            app.verify_core(architecture, app.core_version(candidate))
            app.validate_tls(candidate)
            api = app.API(candidate, saved)
            rows = app.ensure_inbounds(api, candidate, saved, allow_create=False)
            app.ensure_routing(api, candidate, saved, rows)
            app.verify_native_metering(api)
            app.run([str(app.APP / "bin" / ("xray-linux-" + architecture)), "run", "-test", "-config",
                     str(app.APP / "bin/config.json")], cwd=app.APP)
            app.verify_subscription_denials(candidate, saved)
            for role in app.active_roles(candidate):
                nc, ns = app.node_view(candidate, saved, role)
                app.verify_subscription(nc, ns)
                app.verify_shadowrocket(nc, ns)
            current = {role: {k: item["record"][k] for k in ("uuid", "subId", "totalGB", "trafficResetDay")}
                       for role, item in app.native_clients(api, candidate, saved).items()}
            if current != baseline or saved["nodes"] != identity:
                raise RuntimeError("Core switch changed client identity or native quotas")

        app.verify_runtime = local_runtime  # No systemd or public REALITY/ISP probe in this test.
        local_runtime(config, state, arch)
        print("PASS", arch, "new core config and live HTTPS subscriptions in both formats", flush=True)
        for version in ("26.6.27", app.CORE_VERSION):
            app.INPUT_CONFIG["XRAY_VERSION"] = version
            with contextlib.redirect_stdout(io.StringIO()):
                app.switch_core(state["config"], state, arch)
            print("PASS", arch, "real core switch to", version, "and unchanged identity/quotas", flush=True)
        original_runtime = app.verify_runtime

        def reject_comparison(candidate, saved, architecture):
            if app.core_version(candidate) != app.CORE_VERSION:
                raise RuntimeError("Intentional acceptance failure to exercise rollback")
            original_runtime(candidate, saved, architecture)

        app.verify_runtime = reject_comparison
        app.INPUT_CONFIG["XRAY_VERSION"] = "26.6.27"
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                app.switch_core(state["config"], state, arch)
        except RuntimeError as error:
            if "已回退到 " + app.CORE_VERSION not in str(error):
                raise
        else:
            raise RuntimeError("Expected rollback did not run")
        app.verify_core(arch)
        print("PASS", arch, "injected failure restored the actual original binary and subscriptions", flush=True)
        print("LIMITS: no systemd boot, ACME issuance/renewal, public forwarding, ISP exit, or phone-client acceptance.", flush=True)
    finally:
        for name in tuple(processes):
            stop(name)
        for log in logs.values():
            log.close()


if __name__ == "__main__":
    main()
