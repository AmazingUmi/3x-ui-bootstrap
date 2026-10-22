#!/usr/bin/env bash
# 3X-UI Bootstrap — see README.md and config.example.json.
# Usage: sudo bash install-3x-ui.sh --config /path/to/config.json [--check]
set -Eeuo pipefail
umask 077
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' '需要 Python 3.10+；Ubuntu / Debian 可先安装 python3。' >&2
  exit 1
fi
exec python3 - "${BASH_SOURCE[0]}" "$@" <<'PYTHON'
import argparse
import contextlib
import base64
import decimal
import datetime
import fcntl
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import socket
import sqlite3
import ssl
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
if sys.version_info < (3, 10):
    raise SystemExit("需要 Python 3.10+；服务器请使用 Ubuntu 22.04+ 或 Debian 12+。")
from zoneinfo import ZoneInfo

PROJECT_VERSION = "0.1.0"
MODE = "--install"
INPUT_CONFIG = None

VERSION = "v3.10.2"
CORE_VERSION = "26.6.27"
CERTBOT_VERSION = "5.8.0"
CERTBOT_WHEEL_URL = "https://files.pythonhosted.org/packages/71/a9/7742882b276c06e430fb23da13e4512b3cd89d4aa6fb9ddfd7b96812bbff/certbot-5.8.0-py3-none-any.whl"
CERTBOT_SHA256 = "c06793e6a0169b07ee09e11e6a017c7d5a77310055d693fffd66c53363ab87ff"
CORE_ASSETS = {
    "amd64": ("Xray-linux-64.zip", "b3e5902d06d6282fe53cfa2fc426058b9aeaa429b2c812e20887cd47f26d08bf"),
    "arm64": ("Xray-linux-arm64-v8a.zip", "13a251379bea366c2cf10363ad71e75734193d401f26f518bf0c25e5c8f8c931"),
}
DIGESTS = {
    "amd64": "bfda7921984e7a72555c38d4e861c7a8b67b3686b658608937de99682f1452d0",
    "arm64": "a867c65ce52ad49f6504dd4c9c395337dc92ba57ae478da4f1b7ddb624014ed5",
}
STATE_DIR = Path("/var/lib/3x-ui-bootstrap")
APP = Path("/usr/local/x-ui")
DB = Path("/etc/x-ui/x-ui.db")
UNIT = Path("/etc/systemd/system/x-ui.service")
RENEW_SERVICE = Path("/etc/systemd/system/3x-ui-cert-renew.service")
RENEW_TIMER = Path("/etc/systemd/system/3x-ui-cert-renew.timer")
RENEW_HOOK_DIR = Path("/etc/letsencrypt/renewal-hooks/deploy")
LEGACY_QUOTA_SERVICE = Path("/etc/systemd/system/3x-ui-quota.service")
LEGACY_QUOTA_TIMER = Path("/etc/systemd/system/3x-ui-quota.timer")
OWNER = "3x-ui-bootstrap-v5"
ENV = {k: v for k, v in os.environ.items() if not k.startswith(("XUI_", "BOOTSTRAP_"))}
ENV.update(XUI_DB_TYPE="sqlite", XUI_DB_FOLDER="/etc/x-ui",
           XUI_LOG_FOLDER="/var/log/x-ui", XUI_BIN_FOLDER=str(APP / "bin"),
           XUI_ENABLE_FAIL2BAN="false", XRAY_LOCATION_ASSET=str(APP / "bin"),
           DEBIAN_FRONTEND="noninteractive", NEEDRESTART_MODE="l")


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


# Public configuration is data, never shell code. Values are normalized at this
# boundary so the tested deployment/state format remains unchanged.
CONFIG_DEFAULTS = {
    "NODE_NAME": "MyNode", "NODE_MODE": "direct", "NODE_PORT": 443,
    "ISP_NODE_PORT": 8443, "ISP_PROTOCOL": "socks5", "ISP_HOST": "",
    "ISP_PORT": None, "ISP_USERNAME": "", "ISP_PASSWORD": "", "ISP_EXPECTED_IP": "",
    "PANEL_PORT": 7777, "SUB_PORT": 2096, "SUB_DOMAIN": "", "PANEL_HTTPS": False,
    "TOTAL_MONTHLY_GB": 0, "ISP_MONTHLY_GB": 0, "ACME_EMAIL": "",
    "REALITY_HOST": "www.cloudflare.com",
}
CONFIG_KEYS = frozenset(CONFIG_DEFAULTS) | {"SERVER_IP"}
CONFIG_MODES = frozenset(("--install", "--check", "--validate-config", "--configure-domain",
                          "--configure-nodes", "--configure-traffic"))


def reject_duplicate_keys(pairs):
    obj = {}
    for key, value in pairs:
        require(key not in obj, "JSON 存在重复字段：" + key)
        obj[key] = value
    return obj


def reject_json_constant(value):
    raise RuntimeError("配置不允许 NaN 或 Infinity。")


def load_config_values(path):
    path = Path(path).expanduser()
    try:
        with path.open("rb") as stream:
            info = os.fstat(stream.fileno())
            require(stat.S_ISREG(info.st_mode), "配置必须是普通文件。")
            require(not info.st_mode & 0o077, "配置文件权限必须为 600 或更严格，请执行 chmod 600。")
            content = stream.read(65537)
    except FileNotFoundError:
        raise RuntimeError("找不到配置文件；请复制 config.example.json 为 config.json，填写后通过 --config 指定。") from None
    except OSError:
        raise RuntimeError("无法读取配置文件，请检查路径及访问权限。") from None
    require(len(content) <= 65536, "配置文件不能超过 64 KiB。")
    try:
        data = json.loads(content.decode("utf-8"), object_pairs_hook=reject_duplicate_keys,
                          parse_float=decimal.Decimal, parse_constant=reject_json_constant)
    except json.JSONDecodeError as exc:
        raise RuntimeError("JSON 语法错误：第 " + str(exc.lineno) + " 行，第 " + str(exc.colno) + " 列。") from None
    except (UnicodeDecodeError, ValueError):
        raise RuntimeError("配置必须为有效的 UTF-8 JSON。") from None
    require(type(data) is dict, "配置顶层必须是 JSON 对象。")
    unknown = set(data) - CONFIG_KEYS
    require(not unknown, "配置包含不支持的字段：" + ", ".join(sorted(unknown)))
    require("SERVER_IP" in data, "配置缺少 SERVER_IP。")
    values = {**CONFIG_DEFAULTS, **data}
    for key, value in values.items():
        if key == "PANEL_HTTPS":
            require(type(value) is bool, "PANEL_HTTPS 必须是 JSON 布尔值 true 或 false。")
            values[key] = "true" if value else "false"
        elif key in ("NODE_PORT", "ISP_NODE_PORT", "PANEL_PORT", "SUB_PORT", "ISP_PORT"):
            if key == "ISP_PORT" and value is None:
                values[key] = ""
                continue
            require(type(value) is int and 1 <= value <= 65535, key + " 必须是 1–65535 的 JSON 整数。")
            values[key] = str(value)
        elif key in ("TOTAL_MONTHLY_GB", "ISP_MONTHLY_GB"):
            require(type(value) in (int, decimal.Decimal), key + " 必须是 JSON 数字；0 表示不限。")
            number = decimal.Decimal(value)
            require(number.is_finite() and 0 <= number <= decimal.Decimal("9999999.999")
                    and number.as_tuple().exponent >= -3,
                    key + " 必须在 0–9999999.999 之间，最多三位小数。")
            values[key] = format(number, "f")
        else:
            require(type(value) is str, key + " 必须是 JSON 字符串。")
    return values


def config_values():
    require(INPUT_CONFIG is not None, "此操作需要通过 --config 指定配置文件。")
    return dict(INPUT_CONFIG)


def config_from_file():
    return parse_config(config_values())


def parse_config(values):
    c = dict(values)
    c.setdefault("NODE_MODE", "direct")
    c.setdefault("ISP_NODE_PORT", "8443")
    require(c["NODE_MODE"] in ("direct", "direct+isp", "isp"),
            "NODE_MODE 只能填写 direct、direct+isp 或 isp。")
    budget = parse_traffic_budget(c, {key: c.pop(key, "0") for key in ("TOTAL_MONTHLY_GB", "ISP_MONTHLY_GB")})
    if any(budget.values()):
        c["TRAFFIC_BUDGET"] = budget
    require(isinstance(c["NODE_NAME"], str) and 0 < len(c["NODE_NAME"]) <= 64
            and c["NODE_NAME"] == c["NODE_NAME"].strip()
            and not any(x in c["NODE_NAME"] for x in ("/", "\\"))
            and not any(x.isspace() for x in c["NODE_NAME"])
            and not any(ord(x) < 32 or ord(x) == 127 for x in c["NODE_NAME"]),
            "NODE_NAME 是用户自定义昵称：需为 1–64 个字符，不能含空白、路径分隔符或控制字符。")
    proxy = {key: c.pop(key, "socks5" if key == "ISP_PROTOCOL" else "") for key in
             ("ISP_PROTOCOL", "ISP_HOST", "ISP_PORT", "ISP_USERNAME", "ISP_PASSWORD", "ISP_EXPECTED_IP")}
    if "isp" in active_roles(c):
        require(all(proxy[k] for k in ("ISP_HOST", "ISP_PORT", "ISP_USERNAME", "ISP_PASSWORD")),
                "选择包含 ISP 的模式时，必须填写 ISP_HOST、ISP_PORT、ISP_USERNAME、ISP_PASSWORD。")
        require(proxy["ISP_PROTOCOL"] in ("socks5", "http"), "ISP_PROTOCOL 只能填写 socks5 或 http。")
        host = proxy["ISP_HOST"]
        try:
            ipaddress.ip_address(host)
        except ValueError:
            require(len(host) <= 253 and "." in host and all(re.fullmatch(
                r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", x) for x in host.split(".")),
                "ISP_HOST 必须是 IP 或域名，不带协议、路径或端口。")
        require(re.fullmatch(r"[1-9][0-9]{0,4}", str(proxy["ISP_PORT"])) is not None
                and int(proxy["ISP_PORT"]) <= 65535, "ISP_PORT 必须是 1–65535 的整数。")
        for key in ("ISP_USERNAME", "ISP_PASSWORD"):
            require(not any(ord(x) < 32 or ord(x) == 127 for x in proxy[key]), key + " 不能含控制字符。")
            require(proxy["ISP_PROTOCOL"] != "socks5" or len(proxy[key].encode()) <= 255,
                    key + " 的 SOCKS5 编码不能超过 255 字节。")
        require(proxy["ISP_PROTOCOL"] != "http" or ":" not in proxy["ISP_USERNAME"],
                "HTTP 代理用户名不能包含冒号。")
        if proxy["ISP_EXPECTED_IP"]:
            try:
                expected = ipaddress.ip_address(proxy["ISP_EXPECTED_IP"])
                require(expected.version == 4 and expected.is_global, "ISP_EXPECTED_IP 必须是公网 IPv4。")
            except ValueError:
                raise RuntimeError("ISP_EXPECTED_IP 必须是公网 IPv4。") from None
        c["ISP"] = {"protocol": proxy["ISP_PROTOCOL"], "host": host, "port": int(proxy["ISP_PORT"]),
                    "username": proxy["ISP_USERNAME"], "password": proxy["ISP_PASSWORD"],
                    "expected_ip": proxy["ISP_EXPECTED_IP"]}
    panel_mode = c.pop("PANEL_HTTPS", "false")
    require(panel_mode in ("true", "false"), "PANEL_HTTPS 只能填写 true 或 false。")
    if panel_mode == "true":
        c["PANEL_HTTPS"] = True
    # 未启用时不新增持久化字段，既有 SSH 模式的安装记录可直接沿用。
    try:
        ip = ipaddress.ip_address(c["SERVER_IP"])
    except ValueError:
        raise RuntimeError("SERVER_IP 必须是公网 IPv4，请替换示例占位符。") from None
    require(ip.version == 4 and ip.is_global and not ip.is_multicast,
            "SERVER_IP 必须是公网 IPv4。")
    for key in ("NODE_PORT", "ISP_NODE_PORT", "PANEL_PORT", "SUB_PORT"):
        c[key] = str(c[key])
        require(re.fullmatch(r"[1-9][0-9]{0,4}", c[key]) is not None,
                key + " 必须是 1–65535 的整数。")
        c[key] = int(c[key])
        require(c[key] <= 65535, key + " 超出范围。")
    used = node_ports(c) + [c["PANEL_PORT"], c["SUB_PORT"]]
    require(len(set(used)) == len(used),
            "节点、面板、订阅端口必须互不相同。")
    for key in ("REALITY_HOST", "SUB_DOMAIN"):
        host = c[key]
        if key == "SUB_DOMAIN" and host == "":
            continue
        require(len(host) <= 253 and "." in host and all(
            re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
            for label in host.split(".")) and not re.fullmatch(r"[0-9.]+", host),
                key + " 必须是域名，不带协议、路径或端口；请替换占位符。")
        c[key] = host.lower()
    require(not c["ACME_EMAIL"] or re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", c["ACME_EMAIL"]),
            "ACME_EMAIL 格式无效；不填写时留空。")
    c["SUB_HOST"] = c["SUB_DOMAIN"] or c["SERVER_IP"]
    require(not c.get("PANEL_HTTPS") or c["SUB_DOMAIN"],
            "启用域名 HTTPS 面板时必须填写 SUB_DOMAIN；留空时面板使用 SSH 隧道。")
    base = "/etc/letsencrypt/live/" + c["SUB_HOST"]
    c.update(CERT_FILE=base + "/fullchain.pem", CERT_KEY=base + "/privkey.pem")
    require(80 not in used,
            "自动申请与续期需要空闲的 80/TCP，不能用作节点、面板或订阅端口。")
    return c


def active_roles(c):
    return {"direct": ("direct",), "direct+isp": ("direct", "isp"), "isp": ("isp",)}[c.get("NODE_MODE", "direct")]


def parse_traffic_budget(c, values):
    budget = {}
    for role, key in (("total", "TOTAL_MONTHLY_GB"), ("isp", "ISP_MONTHLY_GB")):
        raw = str(values[key])
        require(re.fullmatch(r"(?:0|[1-9][0-9]{0,6})(?:\.[0-9]{1,3})?", raw) is not None,
                key + " 必须是非负数，最多三位小数；0 表示不限。")
        budget[role] = int(decimal.Decimal(raw) * (1024 ** 3))
    roles = active_roles(c)
    require(not budget["isp"] or "isp" in roles, "没有 ISP 线路时 ISP_MONTHLY_GB 必须为 0。")
    if len(roles) == 2 and budget["total"]:
        require(0 < budget["isp"] < budget["total"],
                "双线路有限总预算时，ISP_MONTHLY_GB 必须大于 0 且小于 TOTAL_MONTHLY_GB；Direct 自动分配剩余额度。")
    return budget


def client_quota(c, role):
    budget = c.get("TRAFFIC_BUDGET", {})
    total, isp = budget.get("total", 0), budget.get("isp", 0)
    if role == "direct":
        return total - isp if total and len(active_roles(c)) == 2 else total
    if active_roles(c) == ("isp",):
        finite = [value for value in (total, isp) if value]
        return min(finite) if finite else 0
    return isp


def panel_timezone():
    with contextlib.closing(sqlite3.connect("file:" + str(DB) + "?mode=ro", uri=True)) as db:
        row = db.execute('SELECT value FROM settings WHERE "key"=?', ("timeLocation",)).fetchone()
    return row[0] if row and row[0] else "Local"


def bind_traffic_reset(c, state):
    zone = panel_timezone()
    if "traffic_reset" in state:
        anchor = state["traffic_reset"]
        require(type(anchor.get("day")) is int and 1 <= anchor["day"] <= 31
                and anchor.get("timezone") == zone, "月配额重置记录或面板时区已变化；请先核对并恢复原面板时区。")
        return
    deployed_at = state.get("deployed_at")
    if deployed_at is None:
        # 旧部署没有时间字段：使用原始客户端的官方创建时间，不把本次更新当成重新部署。
        api = API(c, state)
        rows = api.call("inbounds/list")
        matches = [client for row in rows for client in object_field(row, "settings").get("clients", [])
                   if client.get("id") == state["uuid"]]
        require(len(matches) == 1, "无法确认原始部署客户端，停止绑定重置日。")
        record = api.call("clients/get/" + urllib.parse.quote(matches[0]["email"], safe="")).get("client", {})
        created = record.get("createdAt")
        require(record.get("uuid") == state["uuid"] and type(created) is int and created > 0,
                "无法读取原部署创建时间；不会用今天代替原部署日。")
        deployed_at = created / 1000
    require(isinstance(deployed_at, (int, float)) and 0 < deployed_at <= time.time() + 300,
            "部署时间记录异常。")
    moment = datetime.datetime.fromtimestamp(deployed_at, datetime.timezone.utc)
    local = moment.astimezone() if zone == "Local" else moment.astimezone(ZoneInfo(zone))
    state["traffic_reset"] = {"deployed_at": deployed_at, "day": local.day, "timezone": zone,
                              "deployment_date": local.date().isoformat()}
    save(state)  # API 写配额前持久化；重试、修改额度和增加线路均沿用原部署日。


def native_quota_fields(c, role, state):
    cap = client_quota(c, role)
    anchor = state.get("traffic_reset", {})
    require(not cap or type(anchor.get("day")) is int and 1 <= anchor["day"] <= 31,
            "月配额尚未绑定部署日。")
    return {"totalGB": cap, "trafficReset": "monthly" if cap else "never", "trafficResetDay": anchor.get("day", 1)}


def node_ports(c):
    return [c["NODE_PORT"] if role == "direct" else c["ISP_NODE_PORT"] for role in active_roles(c)]


def node_view(c, state, role):
    nc = dict(c, NODE_PORT=c["NODE_PORT"] if role == "direct" else c["ISP_NODE_PORT"],
              NODE_NAME=c["NODE_NAME"] + ("-Direct" if role == "direct" else "-ISP"), ROLE=role)
    ns = dict(state)
    if "nodes" in state:
        require(role in state["nodes"], "安装记录缺少所选线路，请使用 --configure-nodes 配置。")
        ns.update(state["nodes"][role])
    elif "NODE_MODE" not in c:
        nc["NODE_NAME"] = c["NODE_NAME"]  # 已部署的单入站记录；显式配置线路时才改名。
    return nc, ns


IDENTITY_KEYS = ("uuid", "short_id", "sub_id", "private_key", "public_key")


def prepare_nodes(c, state):
    if "nodes" not in state:
        primary = active_roles(state["config"])[0]
        state["nodes"] = {primary: {k: state[k] for k in IDENTITY_KEYS if k in state}}
    for role in active_roles(c):
        if role not in state["nodes"]:
            state["nodes"][role] = {"uuid": str(uuid.uuid4()), "short_id": secrets.token_hex(8),
                                    "sub_id": secrets.token_hex(8)}


def ensure_node_keys(api, c, state):
    for role in active_roles(c):
        node = state["nodes"][role]
        if not node.get("private_key"):
            pair = api.call("server/getNewX25519Cert")
            require(isinstance(pair, dict) and all(re.fullmatch(r"[A-Za-z0-9_-]{43}", pair.get(k, ""))
                    for k in ("privateKey", "publicKey")), "REALITY 密钥生成结果异常。")
            node.update(private_key=pair["privateKey"], public_key=pair["publicKey"])
            if node["uuid"] == state["uuid"]:
                state.update(private_key=node["private_key"], public_key=node["public_key"])
            save(state)


def atomic_write(path, text):
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def save(state):
    atomic_write(STATE_DIR / "state.json", json.dumps(state, indent=2) + "\n")


def run(args, capture=False, cwd=None):
    # 不把包含密码的命令行或子进程输出写到终端；日志仅 root 可读。
    with open(STATE_DIR / "install.log", "ab") as log:
        p = subprocess.run(args, cwd=cwd, env=ENV, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE if capture else log, stderr=log)
    require(p.returncode == 0, "操作失败：" + Path(args[0]).name + "；请查看私有安装日志。")
    return p.stdout.decode() if capture else None


def service_active():
    return subprocess.run(["systemctl", "is-active", "--quiet", "x-ui"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def sockets():
    text = subprocess.check_output(["ss", "-H", "-lntp"], text=True)
    rows = []
    for line in text.splitlines():
        parts = line.split()
        address, port = parts[3].rsplit(":", 1)
        rows.append((address, int(port), line))
    return rows


def check_environment(c, owned):
    require(sys.version_info >= (3, 10), "需要系统 Python 3.10+；请使用 Ubuntu 22.04+ 或 Debian 12+。")
    os_release = Path("/etc/os-release").read_text()
    distro = re.search(r'^ID=["\']?([^"\'\n]+)', os_release, re.M)
    require(distro and distro[1] in ("ubuntu", "debian"), "仅支持 Ubuntu / Debian。")
    arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
    require(arch in DIGESTS, "仅支持 amd64 / arm64。")
    require(shutil.which("apt-get") and shutil.which("systemctl") and shutil.which("ss"),
            "缺少 apt-get、systemctl 或 ss（iproute2）。")
    if not owned:
        paths = [APP, DB.parent, UNIT, RENEW_SERVICE, RENEW_TIMER,
                 Path("/usr/bin/x-ui"), Path("/etc/default/x-ui")]
        existing_unit = subprocess.run(["systemctl", "cat", "x-ui.service"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        require(not any(p.exists() or p.is_symlink() for p in paths) and not existing_unit,
                "发现已有 3X-UI 或残留文件；此脚本只接管自己的安装，请勿删除旧数据后盲目重试。")
    for address, port, line in sockets():
        if port in node_ports(c) + [c["PANEL_PORT"], c["SUB_PORT"]]:
            expected = "xray" if port in node_ports(c) else '"x-ui"'
            require(owned and expected in line, "配置的端口已被其他进程占用：" + str(port))
    # 即使 sshd 暂未监听，也拒绝其配置端口；不修改任何 SSH 设置。
    sshd = shutil.which("sshd") or "/usr/sbin/sshd"
    if Path(sshd).exists():
        p = subprocess.run([sshd, "-T"], text=True, capture_output=True)
        require(p.returncode == 0, "无法读取 sshd 有效配置，请先检查 SSH 服务。")
        ssh_ports = {int(x) for x in re.findall(r"^port (\d+)$", p.stdout, re.M)}
        require(not ssh_ports.intersection(node_ports(c) + [c["PANEL_PORT"], c["SUB_PORT"]]),
                "配置端口与 SSH 端口冲突。")
    return arch


def check_target(c):
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(["h2"])
    try:
        with socket.create_connection((c["REALITY_HOST"], 443), timeout=10) as tcp:
            with context.wrap_socket(tcp, server_hostname=c["REALITY_HOST"]) as tls:
                require(tls.selected_alpn_protocol() == "h2", "REALITY 目标没有协商 HTTP/2。")
    except (OSError, ssl.SSLError) as e:
        raise RuntimeError("REALITY 目标 TLS 1.3 / HTTP/2 探测失败；检查域名、网络和系统时间。") from e


def firewall_instructions(c):
    lines = ["端口放行（云防火墙与服务器防火墙均需手动配置）："]
    for role, port in zip(active_roles(c), node_ports(c)):
        lines.append("  " + ("Direct" if role == "direct" else "ISP") + " 节点：" + str(port) + "/TCP")
    lines.append("  订阅：" + str(c["SUB_PORT"]) + "/TCP")
    if c.get("PANEL_HTTPS"):
        lines.append("  域名 HTTPS 面板：" + str(c["PANEL_PORT"]) + "/TCP（允许管理设备来源 IP）")
    else:
        lines.append("  面板：" + str(c["PANEL_PORT"]) + " 仅本机，通过 SSH 隧道访问，无需公网放行")
    lines += ["  证书签发与自动续期：80/TCP",
              "保留实际 SSH 端口的访问规则；脚本不自动修改防火墙。"]
    return "\n".join(lines) + "\n"


def receive_exact(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        require(chunk, "ISP 代理提前断开连接。")
        data += chunk
    return data


def check_isp(c):
    if "isp" not in active_roles(c):
        return None
    proxy = c["ISP"]
    try:
        with socket.create_connection((proxy["host"], proxy["port"]), timeout=10) as tcp:
            if proxy["protocol"] == "socks5":
                tcp.sendall(b"\x05\x01\x02")
                require(receive_exact(tcp, 2) == b"\x05\x02", "SOCKS5 代理不接受用户名密码认证。")
                user, password = proxy["username"].encode(), proxy["password"].encode()
                tcp.sendall(b"\x01" + bytes([len(user)]) + user + bytes([len(password)]) + password)
                require(receive_exact(tcp, 2) == b"\x01\x00", "SOCKS5 认证失败。")
                tcp.sendall(b"\x05\x01\x00\x01" + socket.inet_aton("1.1.1.1") + (443).to_bytes(2, "big"))
                reply = receive_exact(tcp, 4)
                require(reply[:3] == b"\x05\x00\x00", "SOCKS5 代理无法连接测试目标。")
                require(reply[3] in (1, 3, 4), "SOCKS5 代理响应地址类型无效。")
                length = {1: 4, 4: 16}.get(reply[3])
                if length is None:
                    length = receive_exact(tcp, 1)[0]
                receive_exact(tcp, length + 2)
            else:
                auth = base64.b64encode((proxy["username"] + ":" + proxy["password"]).encode()).decode()
                tcp.sendall(("CONNECT 1.1.1.1:443 HTTP/1.1\r\nHost: 1.1.1.1:443\r\n"
                             "Proxy-Authorization: Basic " + auth + "\r\n\r\n").encode("ascii"))
                header = b""
                while not header.endswith(b"\r\n\r\n"):
                    require(len(header) < 16384, "HTTP 代理响应头过大。")
                    header += receive_exact(tcp, 1)
                require(re.fullmatch(rb"HTTP/1\.[01] 200(?: [^\r\n]*)?", header.split(b"\r\n", 1)[0]),
                        "HTTP 代理认证或 CONNECT 请求失败。")
            with ssl.create_default_context().wrap_socket(tcp, server_hostname="1.1.1.1") as tls:
                tls.sendall(b"GET /cdn-cgi/trace HTTP/1.1\r\nHost: 1.1.1.1\r\nConnection: close\r\n\r\n")
                with http.client.HTTPResponse(tls) as response:
                    response.begin()
                    require(response.status == 200, "ISP HTTPS 测试未返回 HTTP 200。")
                    body = response.read(65537)
                    require(len(body) <= 65536, "ISP HTTPS 测试响应过大。")
            match = re.search(rb"(?m)^ip=([^\r\n]+)", body)
            require(match is not None, "ISP HTTPS 测试未返回出口 IP。")
            ip = ipaddress.ip_address(match[1].decode("ascii"))
            require(ip.version == 4 and ip.is_global, "ISP HTTPS 测试未返回公网 IPv4。")
            require(str(ip) != c.get("SERVER_IP"), "ISP 预检出口与 VPS 公网 IP 相同。")
            require(not proxy["expected_ip"] or str(ip) == proxy["expected_ip"], "ISP 出口不符合 ISP_EXPECTED_IP。")
            print("ISP 上游预检：PASS；出口 IPv4=" + str(ip), flush=True)
            return str(ip)
    except (OSError, ValueError, http.client.HTTPException, RuntimeError) as exc:
        detail = str(exc) if isinstance(exc, RuntimeError) else type(exc).__name__
        raise RuntimeError("ISP 上游预检失败（" + detail +
                           "）；请核对代理协议、地址、端口、认证、预期出口及系统 CA/时间。未进入下载、证书或服务修改。") from None


def check_dns(c):
    if not c["SUB_DOMAIN"]:
        return
    try:
        addresses = {r[4][0] for r in socket.getaddrinfo(c["SUB_DOMAIN"], 0, socket.AF_INET, socket.SOCK_STREAM)}
    except OSError as e:
        raise RuntimeError("无法解析订阅域名，请先设置 A 记录。") from e
    require(addresses == {c["SERVER_IP"]},
            "订阅域名的 A 记录必须直接指向 SERVER_IP；请关闭该记录的 CDN 代理。")


def tls_guard_source(c):
    # 同一检查用于安装验收和 systemd 每次启动，避免后端证书加载失败时回退明文 HTTP。
    ip_mode = not c["SUB_DOMAIN"]
    commands = [
        ["/usr/bin/openssl", "x509", "-in", c["CERT_FILE"], "-noout",
         "-checkip" if ip_mode else "-checkhost", c["SUB_HOST"]],
        ["/usr/bin/openssl", "x509", "-in", c["CERT_FILE"], "-noout", "-checkend", "0"],
        ["/usr/bin/openssl", "verify", "-purpose", "sslserver",
         "-verify_ip" if ip_mode else "-verify_hostname", c["SUB_HOST"],
         "-CAfile", "/etc/ssl/certs/ca-certificates.crt", "-untrusted", c["CERT_FILE"], c["CERT_FILE"]],
    ]
    return ("import ssl, subprocess\n"
            "ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)\n"
            "ctx.load_cert_chain(" + repr(c["CERT_FILE"]) + ", " + repr(c["CERT_KEY"]) + ", password=lambda: '')\n"
            "for command in " + repr(commands) + ":\n"
            "    subprocess.run(command, check=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n")


def validate_tls(c):
    p = subprocess.run(["/usr/bin/python3", "-c", tls_guard_source(c)],
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    require(p.returncode == 0, "HTTPS 证书无效：请核对域名/IP、有效期、完整证书链和匹配的未加密私钥。")


def needs_certificate(c):
    if not all(Path(c[k]).is_file() for k in ("CERT_FILE", "CERT_KEY")):
        return True
    try:
        validate_tls(c)
        return False
    except RuntimeError:
        return True


def check_certificate_readiness(c):
    if needs_certificate(c):
        require(not any(port == 80 for _, port, _ in sockets()),
                "自动签发证书需要空闲的 80/TCP；请先处理端口占用后重试。")
        print("将通过 80/TCP 为 " + c["SUB_HOST"] + " 申请订阅证书；请先手动放行两层防火墙。", flush=True)


def install_renewal_hook(c):
    directory = RENEW_HOOK_DIR
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / ("3x-ui-bootstrap-" + c["SUB_HOST"])
    text = ("#!/bin/sh\nset -eu\n"
            'case " ${RENEWED_DOMAINS:-} " in\n'
            '  *" ' + c["SUB_HOST"] + ' "*)\n'
            '    if systemctl is-active --quiet x-ui || systemctl is-failed --quiet x-ui; then systemctl restart x-ui; fi\n'
            '    ;;\nesac\n')
    require(not path.exists() or path.read_text() == text, "已有不同内容的同名证书续期 hook，请先检查。")
    atomic_write(path, text)
    path.chmod(0o700)


def certbot_path():
    return STATE_DIR / "certbot-venv/bin/certbot"


def install_certbot():
    venv = STATE_DIR / "certbot-venv"
    if not certbot_path().is_file():
        run(["/usr/bin/python3", "-m", "venv", str(venv)])
        wheel = STATE_DIR / ("certbot-" + CERTBOT_VERSION + "-py3-none-any.whl")
        download_verified(CERTBOT_WHEEL_URL, wheel, CERTBOT_SHA256)
        run([str(venv / "bin/python"), "-m", "pip", "install", "--disable-pip-version-check",
             "--no-input", "--only-binary=:all:", "--index-url", "https://pypi.org/simple", str(wheel)])
    version = run([str(certbot_path()), "--version"], capture=True)
    require(version.strip() == "certbot " + CERTBOT_VERSION, "证书客户端版本不符合预期。")


def install_renewal_timer(c):
    service = ("[Unit]\nDescription=Renew 3X-UI HTTPS certificate\n"
               "Wants=network-online.target\nAfter=network-online.target\n\n"
               "[Service]\nType=oneshot\nUMask=0077\nExecStart=" + str(certbot_path()) +
               " renew --quiet --no-random-sleep-on-renew --cert-name " + c["SUB_HOST"] + "\n")
    timer = ("[Unit]\nDescription=Check 3X-UI certificate renewal every six hours\n\n"
             "[Timer]\nOnCalendar=*-*-* 00,06,12,18:00:00\nRandomizedDelaySec=30m\nPersistent=true\n\n"
             "[Install]\nWantedBy=timers.target\n")
    for path, content in ((RENEW_SERVICE, service), (RENEW_TIMER, timer)):
        atomic_write(path, content)
        path.chmod(0o644)
    run(["systemctl", "daemon-reload"])
    run(["systemctl", "enable", "--now", RENEW_TIMER.name])


def activate_certificate(c):
    install_renewal_hook(c)
    install_renewal_timer(c)
    atomic_write(STATE_DIR / "check-sub-tls.py", tls_guard_source(c))


def ensure_certificate(c, activate=True):
    if needs_certificate(c):
        check_certificate_readiness(c)
        command = [str(certbot_path()), "certonly", "--non-interactive", "--agree-tos", "--standalone",
                   "--preferred-challenges", "http", "--http-01-port", "80", "--keep-until-expiring",
                   "--cert-name", c["SUB_HOST"]]
        command += (["-d", c["SUB_DOMAIN"]] if c["SUB_DOMAIN"] else
                    ["--ip-address", c["SERVER_IP"], "--required-profile", "shortlived"])
        command += ["--email", c["ACME_EMAIL"]] if c["ACME_EMAIL"] else ["--register-unsafely-without-email"]
        run(command)
    validate_tls(c)
    if activate:
        activate_certificate(c)


def download_verified(url, archive, expected_digest):
    if not archive.exists():
        partial = str(archive) + ".part"
        run(["curl", "--fail", "--location", "--retry", "3", "--connect-timeout", "20",
             "--max-time", "900", "--proto", "=https", "--proto-redir", "=https",
             "--output", partial, url])
        os.replace(partial, archive)
    with open(archive, "rb") as f:
        digest = hashlib.sha256()
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_digest:
        archive.unlink()
        raise RuntimeError("发行包 SHA-256 不符，已删除；未执行该发行包。")


def install_release(arch):
    archive = STATE_DIR / ("x-ui-" + VERSION + "-" + arch + ".tar.gz")
    url = "https://github.com/MHSanaei/3x-ui/releases/download/" + VERSION + "/x-ui-linux-" + arch + ".tar.gz"
    download_verified(url, archive, DIGESTS[arch])
    with tempfile.TemporaryDirectory(prefix="extract-", dir=STATE_DIR) as tmp:
        with tarfile.open(archive, "r:gz") as tar:
            for member in tar.getmembers():
                p = Path(member.name)
                require(not p.is_absolute() and ".." not in p.parts and p.parts and
                        p.parts[0] == "x-ui" and (member.isfile() or member.isdir()),
                        "发行包包含非预期路径或特殊文件。")
        run(["tar", "--no-same-owner", "--no-same-permissions", "-xzf", str(archive), "-C", tmp])
        source = Path(tmp) / "x-ui"
        require((source / "x-ui").is_file() and (source / "bin" / ("xray-linux-" + arch)).is_file(),
                "发行包缺少面板或 Xray。")
        shutil.copytree(source, APP, dirs_exist_ok=True)
    (APP / "x-ui").chmod(0o700)
    (APP / "bin" / ("xray-linux-" + arch)).chmod(0o700)


def verify_core(arch):
    output = run([str(APP / "bin" / ("xray-linux-" + arch)), "version"], capture=True, cwd=APP)
    require(re.search(r"(?m)^Xray " + re.escape(CORE_VERSION) + r"(?:\s|$)", output),
            "Xray-core 版本不符，要求 " + CORE_VERSION + "；请勿自动更新核心。")


def install_core(arch):
    require(not service_active(), "替换 Xray-core 前，x-ui 必须处于停止状态。")
    name, digest = CORE_ASSETS[arch]
    archive = STATE_DIR / ("xray-" + CORE_VERSION + "-" + arch + ".zip")
    url = "https://github.com/XTLS/Xray-core/releases/download/v" + CORE_VERSION + "/" + name
    download_verified(url, archive, digest)
    binary = APP / "bin" / ("xray-linux-" + arch)
    fd, tmp = tempfile.mkstemp(prefix=".xray-", dir=binary.parent)
    try:
        with os.fdopen(fd, "wb") as output, zipfile.ZipFile(archive) as z:
            item = z.getinfo("xray")
            require(0 < item.file_size <= 200 * 1024 * 1024, "核心压缩包中的 xray 大小异常。")
            with z.open(item) as source:
                shutil.copyfileobj(source, output)
        os.chmod(tmp, 0o700)
        os.replace(tmp, binary)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    verify_core(arch)


def initial_settings(c, state):
    public_panel = c.get("PANEL_HTTPS", False)
    settings = {"webListen": "0.0.0.0" if public_panel else "127.0.0.1", "webPort": str(c["PANEL_PORT"]),
            "webDomain": c["SUB_HOST"] if public_panel else "",
            "webCertFile": c["CERT_FILE"] if public_panel else "",
            "webKeyFile": c["CERT_KEY"] if public_panel else "",
            "webBasePath": state["base_path"], "subEnable": "true", "subListen": "0.0.0.0",
            "subPort": str(c["SUB_PORT"]), "subClashEnable": "true", "subClashPath": "/mihomo/",
            "subDomain": c["SUB_HOST"], "subCertFile": c["CERT_FILE"], "subKeyFile": c["CERT_KEY"]}
    if "NODE_MODE" in c:
        settings.update(remarkTemplate="{{INBOUND}}", subPath=state.get("raw_sub_path", "/sub/"), subEncrypt="true")
    return settings


def harden_initial_db(c, state):
    require(not service_active(), "首次写入设置前，x-ui 必须处于停止状态。")
    run([str(APP / "x-ui"), "setting", "-port", str(c["PANEL_PORT"]),
         "-listenIP", initial_settings(c, state)["webListen"], "-username", state["username"],
         "-password", state["password"], "-webBasePath", state["base_path"]], cwd=APP)
    require(DB.is_file(), "CLI 未生成预期 SQLite 数据库。")
    # v3.10.2 的 CLI 没有订阅开关；仅在服务启动前更新 settings 表，节点通过 API 创建。
    safe = initial_settings(c, state)
    with contextlib.closing(sqlite3.connect(DB)) as db, db:
        cols = {row[1] for row in db.execute("PRAGMA table_info(settings)")}
        require({"id", "key", "value"} <= cols, "数据库设置结构与固定版本不符。")
        for key, value in safe.items():
            db.execute('DELETE FROM settings WHERE "key" = ?', (key,))
            db.execute('INSERT INTO settings ("key", value) VALUES (?, ?)', (key, value))
    DB.chmod(0o600)


def check_db(c, state):
    with contextlib.closing(sqlite3.connect("file:" + str(DB) + "?mode=ro", uri=True)) as db:
        actual = dict(db.execute('SELECT "key", value FROM settings'))
    require(contains(actual, initial_settings(c, state)),
            "设置已变化；停止自动安装，请核对面板访问模式、HTTPS 证书、端口和 Mihomo 路径。")


def write_unit():
    unit = """[Unit]
Description=3X-UI (optional HTTPS panel and public HTTPS subscription, bootstrap v5)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/x-ui
ExecStartPre=/usr/bin/python3 @TLS_GUARD@
ExecStart=/usr/local/x-ui/x-ui
Environment=XUI_DB_TYPE=sqlite
Environment=XUI_DB_FOLDER=/etc/x-ui
Environment=XUI_BIN_FOLDER=/usr/local/x-ui/bin
Environment=XUI_LOG_FOLDER=/var/log/x-ui
Environment=XUI_ENABLE_FAIL2BAN=false
UMask=0077
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
"""
    atomic_write(UNIT, unit.replace("@TLS_GUARD@", str(STATE_DIR / "check-sub-tls.py")))
    UNIT.chmod(0o644)
    run(["systemctl", "daemon-reload"])
    run(["systemctl", "enable", "x-ui"])


class API:
    def __init__(self, c, state):
        origin = "https://" + c["SUB_HOST"] if c.get("PANEL_HTTPS") else "http://127.0.0.1"
        self.url = origin + ":" + str(c["PANEL_PORT"]) + state["base_path"] + "panel/api/"
        self.token = state["api_token"]
        self.config = c
        self.base_path = state["base_path"]
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def call(self, route, payload=None, form=False):
        try:
            if self.config.get("PANEL_HTTPS"):
                status, raw = https_request(self.config["PANEL_PORT"], self.config["SUB_HOST"],
                    self.base_path + "panel/api/" + route, payload, self.token, form=form)
                require(status == 200, "面板 HTTPS API 未返回 HTTP 200。")
                body = json.loads(raw)
            else:
                data = None if payload is None else (urllib.parse.urlencode(payload).encode() if form else json.dumps(payload).encode())
                request = urllib.request.Request(self.url + route, data=data,
                    headers={"Authorization": "Bearer " + self.token, "Content-Type":
                             "application/x-www-form-urlencoded" if form else "application/json"})
                with self.opener.open(request, timeout=15) as response:
                    body = json.load(response)
            require(isinstance(body, dict) and body.get("success") is True,
                    "面板 API 拒绝请求：" + route)
            return body.get("obj")
        except (OSError, http.client.HTTPException, ValueError) as e:
            raise RuntimeError("面板 API 连接或响应异常：" + route) from e


def wait_api(api):
    for _ in range(30):
        try:
            rows = api.call("inbounds/list")
            require(isinstance(rows, list), "节点列表不是数组。")
            return rows
        except RuntimeError:
            time.sleep(1)
    raise RuntimeError("30 次重试后面板 API 仍未就绪；检查服务日志。")


def object_field(row, key):
    value = row.get(key, {})
    return json.loads(value) if isinstance(value, str) else value


def contains(actual, expected):
    # 面板可补充默认字段；读回时只要求所指定的配置完整保留。
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(k in actual and contains(actual[k], v)
                                               for k, v in expected.items())
    return actual == expected


def inbound_payload(c, state):
    client = {"id": state["uuid"], "flow": "xtls-rprx-vision", "email": c["NODE_NAME"] if c.get("ROLE") else "client-01",
              "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True,
              "tgId": 0, "subId": state["sub_id"], "reset": 0}
    if "TRAFFIC_BUDGET" in c:
        client.update(native_quota_fields(c, c.get("ROLE", "direct"), state))
    reality = {"show": False, "xver": 0, "target": c["REALITY_HOST"] + ":443",
               "serverNames": [c["REALITY_HOST"]], "privateKey": state["private_key"],
               "shortIds": [state["short_id"]], "minClientVer": "", "maxClientVer": "", "maxTimediff": 0,
               "settings": {"publicKey": state["public_key"], "fingerprint": "chrome",
                            "serverName": c["REALITY_HOST"], "spiderX": "/"}}
    return {"enable": True, "remark": c["NODE_NAME"], "listen": "0.0.0.0", "port": c["NODE_PORT"],
            "shareAddrStrategy": "custom", "shareAddr": c["SERVER_IP"],
            "protocol": "vless", "expiryTime": 0, "total": 0,
            "settings": json.dumps({"clients": [client], "decryption": "none", "fallbacks": []}),
            "streamSettings": json.dumps({"network": "tcp", "security": "reality",
                "tcpSettings": {"header": {"type": "none"}}, "realitySettings": reality}),
            "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": False})}


def ensure_inbound(api, c, state, allow_create=True):
    rows = api.call("inbounds/list")
    require(isinstance(rows, list), "面板未返回节点列表。")
    matches = [r for r in rows if any(x.get("id") == state["uuid"]
               for x in object_field(r, "settings").get("clients", []))]
    if not matches:
        require(allow_create, "原节点或首个客户端已删除；脚本不会在已完成的安装中重建。")
        require(not any(r.get("port") == c["NODE_PORT"] for r in rows),
                "该端口已有其他节点；停止，避免覆盖或重复创建。")
        if c.get("ROLE"):
            require(not any(str(v.get("email", "")).casefold() == c["NODE_NAME"].casefold()
                    for r in rows for v in object_field(r, "settings").get("clients", [])),
                    "客户端名称已被其他入站使用。")
        api.call("inbounds/add", inbound_payload(c, state))
        rows = api.call("inbounds/list")
        matches = [r for r in rows if any(x.get("id") == state["uuid"]
                   for x in object_field(r, "settings").get("clients", []))]
    require(len(matches) == 1, "节点创建后未能唯一读回；请检查面板，勿重复手动添加。")
    row = matches[0]
    expected = inbound_payload(c, state)
    require(all(row.get(k) == expected[k] for k in
                ("port", "protocol", "listen", "enable", "shareAddrStrategy", "shareAddr")),
            "已存在节点的关键设置发生变化；停止自动安装。")
    for field in ("settings", "streamSettings"):
        actual, wanted = object_field(row, field), object_field(expected, field)
        require(contains(actual, {k: v for k, v in wanted.items() if k != "clients"}),
                "已存在节点的协议设置发生变化：" + field)
    clients = object_field(row, "settings").get("clients", [])
    client = next(x for x in clients if x.get("id") == state["uuid"])
    exhausted = False
    if "TRAFFIC_BUDGET" in c:
        detail = api.call("clients/get/" + urllib.parse.quote(client["email"], safe=""))
        record = detail.get("client", {})
        cap = client_quota(c, c.get("ROLE", "direct"))
        require(record.get("uuid") == state["uuid"] and type(detail.get("usedTraffic")) is int
                and detail["usedTraffic"] >= 0 and contains(record, native_quota_fields(c, c.get("ROLE", "direct"), state)),
                "客户端原生月配额已变化；请使用 --configure-traffic。")
        exhausted = bool(cap and detail.get("usedTraffic", 0) >= cap)
    require((client.get("enable") is True or exhausted) and client.get("flow") == "xtls-rprx-vision",
            "首个客户端已禁用或 flow 被修改。")
    if c.get("ROLE") and "NODE_MODE" in c:
        require(row.get("remark") == c["NODE_NAME"] and client.get("email") == c["NODE_NAME"]
                and client.get("subId") == state["sub_id"], "线路或客户端名称、订阅标识已变化；请使用 --configure-nodes。")
    return row


def ensure_inbounds(api, c, state, allow_create=True):
    return {role: ensure_inbound(api, *node_view(c, state, role), allow_create=allow_create)
            for role in active_roles(c)}


def native_clients(api, c, state):
    result = {}
    rows = api.call("inbounds/list")
    for role in active_roles(c):
        _, ns = node_view(c, state, role)
        matches = [(r, client) for r in rows for client in object_field(r, "settings").get("clients", [])
                   if client.get("id") == ns["uuid"]]
        require(len(matches) == 1, "未能唯一找到受管客户端；不会自动重建。")
        row, client = matches[0]
        detail = api.call("clients/get/" + urllib.parse.quote(client["email"], safe=""))
        record = detail.get("client", {})
        require(record.get("uuid") == ns["uuid"] and record.get("email") == client["email"]
                and record.get("subId") == ns["sub_id"] and row["id"] in detail.get("inboundIds", [])
                and type(detail.get("usedTraffic")) is int and detail["usedTraffic"] >= 0
                and type(record.get("totalGB")) is int and record["totalGB"] >= 0,
                "客户端身份或原生流量数据异常。")
        result[role] = {"row": row, "client": client, "record": record, "used": detail["usedTraffic"]}
    return result


def native_exhausted(c, state):
    if "TRAFFIC_BUDGET" not in c:
        return set()
    return {role for role, item in native_clients(API(c, state), c, state).items()
            if client_quota(c, role) and item["used"] >= client_quota(c, role)}


def preserved_client(client, record):
    payload = dict(client)
    # Record.id 是数据库主键，Client.id 是 UUID；仅补齐可写元数据。
    for key in ("group", "comment", "limitHwid", "limitIp", "tgId", "reset", "resetDay", "resetWeekday",
                "resetMax", "expiryTime", "enable", "adTag"):
        if key in record:
            payload[key] = record[key]
    return payload


def apply_native_quotas(c, state, force=False):
    if "TRAFFIC_BUDGET" not in c and not force:
        return False
    api = API(c, state)
    changed = False
    for role, item in native_clients(api, c, state).items():
        wanted = native_quota_fields(c, role, state)
        if contains(item["record"], wanted):
            continue
        payload = preserved_client(item["client"], item["record"])
        payload.update(wanted)
        route = "clients/update/" + urllib.parse.quote(item["client"]["email"], safe="") + "?inboundIds=" + str(item["row"]["id"])
        api.call(route, payload)
        changed = True
    for role, item in native_clients(api, c, state).items():
        require(contains(item["record"], native_quota_fields(c, role, state)), "原生客户端配额未能读回确认，请用相同参数重试。")
    return changed


def verify_native_metering(api):
    template = read_routing(api)
    level = template.get("policy", {}).get("levels", {}).get("0", {})
    require(all(level.get(key) is True for key in ("statsUserUplink", "statsUserDownlink"))
            and isinstance(template.get("stats"), dict)
            and "StatsService" in template.get("api", {}).get("services", []),
            "Xray 原生客户端计量未开启；请先恢复等级 0 上传/下载统计、stats 和 StatsService，再设置配额。")


def traffic_status(c, state):
    def amount(value):
        return f"{value / (1024 ** 3):g} GiB" if value else "不限"
    lines = ["原生客户端月配额（固定分配）："]
    for role, item in native_clients(API(c, state), c, state).items():
        record = item["record"]
        exhausted = bool(record["totalGB"] and item["used"] >= record["totalGB"])
        label = "额度耗尽" if exhausted else "已启用" if record.get("enable") else "已停用"
        cycle = ("；每月 " + str(record.get("trafficResetDay")) + " 日重置"
                 if record.get("trafficReset") == "monthly" else "；无月重置")
        lines.append("  " + role + "：" + f'{item["used"] / (1024 ** 3):.3f} GiB / ' + amount(record["totalGB"]) + "；" + label + cycle)
    if state.get("traffic_reset"):
        anchor = state["traffic_reset"]
        lines.append("  原部署日期：" + anchor["deployment_date"] + "；面板时区：" + anchor["timezone"] + "（Local 为 VPS 本地时区）。")
    lines.append("  月底缺少对应日期时在当月最后一天重置；未使用额度不在两条线路间调剂。")
    return "\n".join(lines) + "\n"


def retire_shared_quota(state, apply=False):
    # 只停用本安装器上一版的共享任务，保留文件和历史计量供核对。
    paths = [LEGACY_QUOTA_SERVICE, LEGACY_QUOTA_TIMER]
    for path in paths:
        require(not path.is_symlink() and (not path.exists() or "# " + OWNER in path.read_text()),
                "旧共享额度任务不属于此安装器，停止迁移。")
    q = {}
    path = STATE_DIR / "quota-state.json"
    if path.exists():
        require(not path.is_symlink() and path.stat().st_mode & 0o077 == 0, "旧共享额度记录权限异常。")
        q = json.loads(path.read_text())
        require(q.get("owner") == OWNER and q.get("uuid") == state["uuid"], "旧共享额度记录不属于此安装。")
    if apply:
        if paths[1].exists():
            run(["systemctl", "disable", "--now", paths[1].name])
        if paths[0].exists():
            run(["systemctl", "stop", paths[0].name])
    return q


def configure_traffic(c, state, arch=None):
    require(state.get("phase") == "complete" and state.get("api_token") and service_active(),
            "请先完成安装并启动面板，再设置原生月配额。")
    values = {key: config_values()[key] for key in ("TOTAL_MONTHLY_GB", "ISP_MONTHLY_GB")}
    budget = parse_traffic_budget(c, values)
    candidate = dict(c)
    candidate.pop("TRAFFIC_LIMITS", None)
    candidate.pop("TRAFFIC_BUDGET", None)
    if any(budget.values()):
        candidate["TRAFFIC_BUDGET"] = budget
        verify_native_metering(API(c, state))
    records = native_clients(API(c, state), candidate, state)
    legacy = retire_shared_quota(state)  # 先验证全部归属，再修改任何配额或任务。
    for role, entry in legacy.get("blocked", {}).items():
        if role in records:
            item = records[role]
            require(entry == {"uuid": item["client"]["id"], "inbound_id": item["row"]["id"]}, "旧任务停用记录的身份不一致。")
    bind_traffic_reset(candidate, state)
    retire_shared_quota(state, apply=True)
    apply_native_quotas(candidate, state, force=True)
    api = API(c, state)
    for role, entry in legacy.get("blocked", {}).items():
        if role not in records:
            continue
        item = records[role]
        if item["row"].get("enable") is False:
            api.call("inbounds/setEnable/" + str(item["row"]["id"]), {"enable": True})
    # 显式配置结束时统一应用；API 提交成功但响应丢失后的重试也会完成这一步。
    run(["systemctl", "restart", "x-ui"])
    wait_api(api)
    state["config"] = candidate
    save(state)
    write_results(candidate, state)
    print("原生客户端月配额已设置；保留既有流量计数及客户端开关。\n" + traffic_status(candidate, state))


def isp_outbound(c):
    p = c["ISP"]
    return {"tag": "bootstrap-isp", "protocol": "socks" if p["protocol"] == "socks5" else "http",
            "settings": {"servers": [{"address": p["host"], "port": p["port"],
                         "users": [{"user": p["username"], "pass": p["password"]}]}]}}


def read_routing(api):
    raw = api.call("xray/", {})
    wrapper = json.loads(raw) if isinstance(raw, str) else raw
    require(isinstance(wrapper, dict) and isinstance(wrapper.get("xraySetting"), dict),
            "面板未返回预期的 Xray 模板。")
    template = wrapper["xraySetting"]
    require(isinstance(template.get("outbounds"), list) and
            isinstance(template.get("routing", {}).get("rules"), list), "Xray 模板缺少出站或路由。")
    return template


def route_rules(c, rows):
    rules = []
    for role in active_roles(c):
        require(isinstance(rows[role].get("tag"), str) and rows[role]["tag"], "未读回真实入站标签。")
        tag = rows[role]["tag"]
        if role == "isp":
            rules.append({"type": "field", "inboundTag": [tag], "network": "udp", "outboundTag": "blocked"})
        rule = {"type": "field", "inboundTag": [tag], "outboundTag": "direct" if role == "direct" else "bootstrap-isp"}
        if role == "isp":
            rule["network"] = "tcp"
        rules.append(rule)
    return rules


def routing_matches(template, c, rows):
    outbounds = template["outbounds"]
    require(any(o.get("tag") == "direct" and o.get("protocol") == "freedom" for o in outbounds)
            and any(o.get("tag") == "blocked" and o.get("protocol") == "blackhole" for o in outbounds),
            "Xray 的 direct 或 blocked 基础出站已变化。")
    if "isp" in active_roles(c):
        require([o for o in outbounds if o.get("tag") == "bootstrap-isp"] == [isp_outbound(c)],
                "ISP 出站与保存的配置不一致；脚本不会悄悄覆盖。")
    rules = template["routing"]["rules"]
    for expected in route_rules(c, rows):
        require(sum(r == expected for r in rules) == 1, "所选线路的路由缺失、重复或已变化。")
        index = rules.index(expected)
        for earlier in rules[:index]:
            if earlier in route_rules(c, rows) or earlier.get("outboundTag") in ("api", "blocked"):
                continue
            tags = earlier.get("inboundTag")
            require(tags and not set(tags).intersection(expected["inboundTag"]),
                    "已有路由可能覆盖线路出口，请先检查路由优先级。")


def ensure_routing(api, c, state, rows, allow_update=False):
    if "NODE_MODE" not in c:
        return
    current = read_routing(api)
    path = STATE_DIR / "routing-plan.json"
    if not allow_update:
        routing_matches(current, c, rows)
        return
    if path.exists():
        plan = json.loads(path.read_text())
        require(plan.get("owner") == OWNER and plan.get("uuid") == state["uuid"]
                and plan.get("config") == c, "路由安装记录与参数不一致；请使用 --configure-nodes。")
        # 原模板可能已满足保留线路，但仍含本次要移除的 ISP 出站或停用线路规则。
        # 只有读回结果已变化（含服务端规范化），或本次确实无变更，才按已提交处理。
        if current != plan["old_template"] or current == plan["new_template"]:
            routing_matches(current, c, rows)
            return
        target = plan["new_template"]
    else:
        target = json.loads(json.dumps(current))
        require(not any(o.get("tag") == "bootstrap-isp" for o in target["outbounds"]),
                "发现未由此安装记录管理的 bootstrap-isp 出站，请先检查。")
        if "isp" in active_roles(c):
            target["outbounds"].append(isp_outbound(c))
        rules = target["routing"]["rules"]
        tags = {row["tag"] for row in rows.values()}
        require(not any(tags.intersection(r.get("inboundTag", [])) for r in rules),
                "已有规则引用所选入站，请使用 --configure-nodes 显式配置。")
        index = next((i for i, r in enumerate(rules) if r.get("outboundTag") not in ("api", "blocked")
                      and not (r.get("inboundTag") and tags.isdisjoint(r["inboundTag"]))), len(rules))
        rules[index:index] = route_rules(c, rows)
        routing_matches(target, c, rows)
        plan = {"owner": OWNER, "uuid": state["uuid"], "config": c,
                "old_template": current, "new_template": target}
        atomic_write(path, json.dumps(plan, indent=2) + "\n")
    api.call("xray/update", {"xraySetting": json.dumps(target)}, form=True)
    routing_matches(read_routing(api), c, rows)


def managed_inbound(api, state):
    rows = api.call("inbounds/list")
    require(isinstance(rows, list), "面板未返回节点列表。")
    matches = [r for r in rows if any(v.get("id") == state["uuid"]
               for v in object_field(r, "settings").get("clients", []))]
    require(len(matches) == 1, "未能唯一找到原客户端所属的节点；修复不会重建节点。")
    return matches[0]


def vless_link(c, state):
    query = urllib.parse.urlencode({"encryption": "none", "security": "reality", "type": "tcp",
        "sni": c["REALITY_HOST"], "fp": "chrome", "pbk": state["public_key"],
        "sid": state["short_id"], "spx": "/", "flow": "xtls-rprx-vision"})
    return "vless://" + state["uuid"] + "@" + c["SERVER_IP"] + ":" + str(c["NODE_PORT"]) + "?" + query + "#" + urllib.parse.quote(c["NODE_NAME"], safe="")


def mihomo_link(c, state):
    return "https://" + c["SUB_HOST"] + ":" + str(c["SUB_PORT"]) + "/mihomo/" + state["sub_id"]


def https_request(port, host, path, payload=None, token=None, form=False, user_agent="mihomo"):
    # 回环 TCP 连接使用实际域名/IP 校验证书，保留 Host，不依赖公网回流或代理设置。
    context = ssl.create_default_context()
    with socket.create_connection(("127.0.0.1", port), timeout=15) as tcp:
        with context.wrap_socket(tcp, server_hostname=host) as tls:
            body = b"" if payload is None else (urllib.parse.urlencode(payload).encode() if form else json.dumps(payload).encode("utf-8"))
            headers = [("POST" if payload is not None else "GET") + " " + path + " HTTP/1.1",
                       "Host: " + host + ":" + str(port), "User-Agent: " + user_agent, "Connection: close"]
            if token is not None:
                headers.append("Authorization: Bearer " + token)
            if payload is not None:
                headers += ["Content-Type: " + ("application/x-www-form-urlencoded" if form else "application/json"),
                            "Content-Length: " + str(len(body))]
            tls.sendall(("\r\n".join(headers) + "\r\n\r\n").encode("ascii") + body)
            with http.client.HTTPResponse(tls) as response:
                response.begin()
                raw = response.read(2 * 1024 * 1024 + 1)
                require(len(raw) <= 2 * 1024 * 1024, "HTTPS 响应过大。")
                return response.status, raw


def fetch_subscription(c, state):
    status, raw = https_request(c["SUB_PORT"], c["SUB_HOST"], "/mihomo/" + state["sub_id"])
    require(status == 200, "Mihomo 订阅未返回 HTTP 200。")
    return raw


def verify_subscription(c, state):
    import yaml  # 由系统包 python3-yaml 提供；--check 不需要安装此依赖。
    try:
        body = fetch_subscription(c, state)
        require(len(body) <= 2 * 1024 * 1024, "Mihomo 配置响应过大。")
        config = yaml.safe_load(body.decode("utf-8"))
    except (OSError, http.client.HTTPException, UnicodeError, yaml.YAMLError) as e:
        raise RuntimeError("Mihomo 订阅下载或 YAML 解析失败。") from e
    require(isinstance(config, dict) and isinstance(config.get("proxies"), list)
            and isinstance(config.get("proxy-groups"), list) and isinstance(config.get("rules"), list),
            "订阅未返回完整 Mihomo 配置。")
    expected = {"type": "vless", "server": c["SERVER_IP"], "port": c["NODE_PORT"],
                "uuid": state["uuid"], "flow": "xtls-rprx-vision", "tls": True,
                "servername": c["REALITY_HOST"], "reality-opts": {
                    "public-key": state["public_key"], "short-id": state["short_id"]}}
    require(any(contains(p, expected) for p in config["proxies"]),
            "Mihomo 配置缺少预期的公网节点或 REALITY 参数；未将其标记为安装成功。")
    if c.get("ROLE") and "NODE_MODE" in c:
        require(len(config["proxies"]) == 1 and config["proxies"][0].get("name") == c["NODE_NAME"],
                "Mihomo 订阅包含其他线路或名称不符合昵称。")
        atomic_write(STATE_DIR / (c["ROLE"] + "-mihomo.yaml"), body.decode("utf-8"))
    if not c.get("ROLE") or c["ROLE"] == active_roles(c)[0]:
        atomic_write(STATE_DIR / "mihomo.yaml", body.decode("utf-8"))


def verify_shadowrocket(c, state):
    status, raw = https_request(c["SUB_PORT"], c["SUB_HOST"], state.get("raw_sub_path", "/sub/") + state["sub_id"], user_agent="Shadowrocket")
    require(status == 200, "Shadowrocket 订阅未返回 HTTP 200。")
    try:
        links = base64.b64decode(b"".join(raw.split()), validate=True).decode("utf-8").splitlines()
        require(len(links) == 1, "Shadowrocket 订阅应只包含对应的一条线路。")
        link = urllib.parse.urlsplit(links[0])
        query = urllib.parse.parse_qs(link.query)
        require(link.scheme == "vless" and link.username == state["uuid"] and link.hostname == c["SERVER_IP"]
                and link.port == c["NODE_PORT"] and urllib.parse.unquote(link.fragment) == c["NODE_NAME"]
                and all(query.get(key) == [value] for key, value in {
                    "security": "reality", "sni": c["REALITY_HOST"], "pbk": state["public_key"],
                    "sid": state["short_id"], "flow": "xtls-rprx-vision", "fp": "chrome",
                    "type": "tcp", "encryption": "none"}.items()),
                "Shadowrocket 订阅内容与所选线路不一致。")
    except (ValueError, UnicodeError):
        raise RuntimeError("Shadowrocket 订阅编码或内容无效。") from None


def listener_summary(c, rows):
    parts = []
    services = [("面板", c["PANEL_PORT"]), ("订阅", c["SUB_PORT"])] + list(zip(active_roles(c), node_ports(c)))
    for label, service_port in services:
        found = []
        for address, port, line in rows:
            if port == service_port:
                process = "x-ui" if '"x-ui"' in line else "xray" if "xray" in line else "其他/未知进程"
                found.append(address + ":" + str(port) + " (" + process + ")")
        parts.append(label + "=" + (", ".join(found) or "未监听"))
    return "；".join(parts)


def diagnostic_lines(text, state):
    # REALITY show 会输出会话密钥及 Short ID；这些行直接丢弃。
    sensitive = []
    def collect(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key in ("uuid", "private_key", "public_key", "short_id", "sub_id", "username", "password", "api_token", "base_path") and isinstance(child, str):
                    sensitive.append(child)
                else:
                    collect(child)
    collect(state)
    selected = []
    for line in text.splitlines():
        lower = line.lower()
        if "failed to read client hello" in lower or "ishandshakecomplete.load(): false" in lower:
            continue  # 临时端口的 TCP 就绪探测会产生这两条无效握手记录。
        if any(k in lower for k in ("authkey", "shortid", "sessionid", "privatekey", "publickey")):
            continue
        if not any(k in lower for k in ("handshake", "server hello", "hs.c.conn == conn", "verified:",
                                       "failed", "invalid", "blocked target", "panic", "fatal")):
            continue
        for value in sensitive:
            if value:
                line = line.replace(value, "[redacted]")
        selected.append(line[:600])
    return selected[-16:]


def free_local_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


@contextlib.contextmanager
def temporary_core(binary, config, path, log_path, port):
    path.write_text(json.dumps(config))
    path.chmod(0o600)
    with log_path.open("w") as log:
        log_path.chmod(0o600)
        process = subprocess.Popen([str(binary), "run", "-config", str(path)], cwd=APP,
            env=ENV, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        try:
            for _ in range(40):
                require(process.poll() is None, "临时 Xray 退出，请查看下方脱敏错误。")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                        break
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError("临时回环端口未就绪。")
            yield process
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)


def probe_reality_target(c, state, arch, host, existing_port=None, expected_exit=None, forbidden_exit=None):
    binary = APP / "bin" / ("xray-linux-" + arch)
    server_port = existing_port if existing_port is not None else free_local_port()
    socks_port = free_local_port()
    while socks_port == server_port:
        socks_port = free_local_port()
    server = {"log": {"loglevel": "debug", "access": "none"}, "inbounds": [
        {"listen": "127.0.0.1", "port": server_port, "protocol": "vless", "settings": {
            "decryption": "none", "clients": [{"id": state["uuid"], "flow": "xtls-rprx-vision"}]},
         "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
            "show": True, "target": host + ":443", "xver": 0, "serverNames": [host],
            "privateKey": state["private_key"], "shortIds": [state["short_id"]]}}}],
        "outbounds": [{"protocol": "freedom"}]}
    client = {"log": {"loglevel": "debug", "access": "none"}, "inbounds": [
        {"listen": "127.0.0.1", "port": socks_port, "protocol": "socks", "settings": {"auth": "noauth", "udp": False}}],
        "outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": "127.0.0.1", "port": server_port,
            "users": [{"id": state["uuid"], "encryption": "none", "flow": "xtls-rprx-vision"}]}]},
            "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
                "show": True, "serverName": host, "fingerprint": "chrome", "publicKey": state["public_key"],
                "shortId": state["short_id"], "spiderX": "/"}}}]}
    print("\n" + ("正式节点本机验收：" if existing_port is not None else "测试目标：") + host, flush=True)
    passed = False
    with tempfile.TemporaryDirectory(prefix="3x-ui-diagnose-") as directory:
        root = Path(directory)
        root.chmod(0o700)
        try:
            server_context = (contextlib.nullcontext() if existing_port is not None else
                temporary_core(binary, server, root / "server.json", root / "server.log", server_port))
            with server_context, \
                 temporary_core(binary, client, root / "client.json", root / "client.log", socks_port):
                # 使用公共 IP HTTPS，避免把 VPS 的域名解析故障混入首个认证测试。
                result = subprocess.run(["curl", "--silent", "--show-error", "--noproxy", "",
                    "--socks5-hostname", "127.0.0.1:" + str(socks_port), "--connect-timeout", "18", "--max-time", "25",
                    "--output", str(root / "trace.txt"), "--write-out", "%{http_code}", "https://1.1.1.1/cdn-cgi/trace"],
                    env=ENV, text=True, capture_output=True, timeout=28)
                code = result.stdout.strip()
                passed = result.returncode == 0 and code == "200"
                if passed and (expected_exit is not None or forbidden_exit is not None):
                    match = re.search(r"(?m)^ip=([^\r\n]+)", (root / "trace.txt").read_text())
                    exit_ip = str(ipaddress.ip_address(match[1])) if match else None
                    passed = exit_ip is not None and (expected_exit is None or exit_ip == expected_exit)
                    passed = passed and (forbidden_exit is None or exit_ip != forbidden_exit)
                    print("实际代理出口 IPv4=" + (exit_ip or "未取得"), flush=True)
                print(("PASS" if passed else "FAIL") + "：REALITY/VLESS/Vision → HTTPS；curl=" +
                      str(result.returncode) + "，HTTP=" + code, flush=True)
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
            print("FAIL：临时连接测试未完成（" + type(exc).__name__ + "）。", flush=True)
        finally:
            for name in ("server.log", "client.log"):
                path = root / name
                if path.exists():
                    for line in diagnostic_lines(path.read_text(errors="replace"), state):
                        print(name + ": " + line, flush=True)
    return passed


def diagnose_node(c, state, arch):
    binary = APP / "bin" / ("xray-linux-" + arch)
    version = subprocess.run([str(binary), "version"], text=True, capture_output=True, timeout=5)
    require(version.returncode == 0 and re.search(r"\bXray " + re.escape(CORE_VERSION) + r"\b", version.stdout),
            "现有核心不是要求的 " + CORE_VERSION + "；诊断不会更新核心。")
    print("临时副本诊断，Xray-core " + CORE_VERSION + "；读取已保存的配置。", flush=True)
    print("现有服务、数据库、节点和安装记录不变；临时端口只监听 127.0.0.1。", flush=True)
    current = probe_reality_target(c, state, arch, c["REALITY_HOST"])
    alternate = None
    if c["REALITY_HOST"] != "www.cloudflare.com":
        alternate = probe_reality_target(c, state, arch, "www.cloudflare.com")
    if not current and alternate:
        print("\n当前目标失败，对照目标通过：已复现目标相关的握手差异；尚未修改正式节点。", flush=True)
    elif current:
        print("\n当前目标的临时副本通过；需继续核对正式进程配置、路由和客户端公网路径。", flush=True)
    else:
        print("\n临时副本未通过；请反馈以上脱敏错误，继续检查目标、核心运行及 VPS 出站。", flush=True)
    print("诊断结束，临时进程和文件已清理；回环测试不能代替客户端公网验收。", flush=True)


def verify_runtime(c, state, arch):
    check_db(c, state)
    verify_core(arch)
    validate_tls(c)
    require(service_active(), "x-ui 服务未运行。")
    if "TRAFFIC_BUDGET" in c:
        require(state.get("traffic_reset", {}).get("timezone") == panel_timezone(), "面板时区已变化；请先恢复原月配额时区。")
        verify_native_metering(API(c, state))
    exhausted = native_exhausted(c, state)
    expected_ports = {node_view(c, state, role)[0]["NODE_PORT"] for role in active_roles(c) if role not in exhausted}
    for _ in range(30):
        rows = sockets()
        panel = [r for r in rows if r[1] == c["PANEL_PORT"]]
        sub = [r for r in rows if r[1] == c["SUB_PORT"]]
        node = [r for r in rows if r[1] in node_ports(c)]
        panel_addresses = ("0.0.0.0", "*", "::", "[::]") if c.get("PANEL_HTTPS") else ("127.0.0.1",)
        if (not all(r[0] in panel_addresses and '"x-ui"' in r[2] for r in panel)
                or not all(r[0] in ("0.0.0.0", "*", "::", "[::]") and '"x-ui"' in r[2] for r in sub)):
            detail = listener_summary(c, rows)
            run(["systemctl", "stop", "x-ui"])
            raise RuntimeError("面板或订阅监听不符合配置要求；" + detail + "；已停止 x-ui。")
        if panel and sub and expected_ports.issubset({r[1] for r in node}) and all("xray" in r[2] for r in node):
            break
        time.sleep(1)
    else:
        raise RuntimeError("面板、订阅或 Xray 节点端口未按预期监听；" + listener_summary(c, rows))
    run([str(APP / "bin" / ("xray-linux-" + arch)), "run", "-test", "-config",
         str(APP / "bin/config.json")], cwd=APP)
    inbound_rows = ensure_inbounds(API(c, state), c, state, allow_create=False)
    try:
        if c.get("PANEL_HTTPS"):
            require(isinstance(API(c, state).call("inbounds/list"), list), "面板 HTTPS API 验收失败。")
        for role in active_roles(c):
            if role in exhausted:
                print(role + " 原生配额已耗尽；保留停用状态，跳过该线路订阅与转发检查。", flush=True)
                continue
            nc, ns = node_view(c, state, role)
            verify_subscription(nc, ns)
            if "NODE_MODE" in c:
                verify_shadowrocket(nc, ns)
    except Exception:
        run(["systemctl", "stop", "x-ui"])
        raise
    ensure_routing(API(c, state), c, state, inbound_rows)
    for role in active_roles(c):
        if role in exhausted:
            continue
        nc, ns = node_view(c, state, role)
        expected = c["SERVER_IP"] if role == "direct" else c["ISP"]["expected_ip"] or None
        forbidden = c["SERVER_IP"] if role == "isp" else None
        require(probe_reality_target(nc, ns, arch, c["REALITY_HOST"], existing_port=nc["NODE_PORT"],
                                    expected_exit=expected, forbidden_exit=forbidden),
                role + " 正式节点的 REALITY/VLESS 认证、HTTPS 转发或出口 IP 校验失败；保留配置，请执行 --diagnose。")


def write_results(c, state):
    public_panel = c.get("PANEL_HTTPS", False)
    panel_url = ("https://" + c["SUB_HOST"] + ":" + str(c["PANEL_PORT"]) if public_panel
                 else "http://127.0.0.1:17777") + state["base_path"]
    panel_label = "控制台 URL（域名 HTTPS，无需 SSH 隧道）：" if public_panel else "控制台 URL（必须先建立面板 SSH 隧道）："
    result = ("部署完成（本机检查通过）\n\n"
        "控制台账号：" + state["username"] + "\n"
        "控制台密码：" + state["password"] + "\n" +
        panel_label + "\n" + panel_url + "\n\n")
    for index, role in enumerate(active_roles(c)):
        nc, ns = node_view(c, state, role)
        link, sub_link = vless_link(nc, ns), mihomo_link(nc, ns)
        raw_link = "https://" + c["SUB_HOST"] + ":" + str(c["SUB_PORT"]) + state.get("raw_sub_path", "/sub/") + ns["sub_id"]
        result += ("线路：" + nc["NODE_NAME"] + "\n"
                   "Mihomo 链接（公网 HTTPS）：\n" + sub_link + "\n\n"
                   "VLESS 链接：\n" + link + "\n\n")
        if "NODE_MODE" in c:
            result += "Shadowrocket 订阅（公网 HTTPS）：\n" + raw_link + "\n\n"
            for suffix, value in (("vless.txt", link), ("mihomo-url.txt", sub_link), ("shadowrocket-url.txt", raw_link)):
                atomic_write(STATE_DIR / (role + "-" + suffix), value + "\n")
        if index == 0:
            atomic_write(STATE_DIR / "vless.txt", link + "\n")
            atomic_write(STATE_DIR / "mihomo-url.txt", sub_link + "\n")
    result += ("3X-UI：" + VERSION + "\n"
        "Xray-core：" + CORE_VERSION + "（Shadowrocket 兼容固定版本）\n"
        "线路模式：" + c.get("NODE_MODE", "direct") + "\n"
        "REALITY 目标 / SNI：" + c["REALITY_HOST"] + "\n"
        "面板监听：" + ("0.0.0.0:" if public_panel else "127.0.0.1:") + str(c["PANEL_PORT"]) +
        ("（域名 HTTPS）\n" if public_panel else "（SSH 隧道）\n") +
        "订阅监听：0.0.0.0:" + str(c["SUB_PORT"]) + "（HTTPS，无需 SSH 隧道）\n\n" +
        firewall_instructions(c) + "\n" +
        "已验证：未耗尽配额线路的本机 REALITY/VLESS/Vision 认证、HTTPS 转发与出口检查。\n"
        "下一步：客户端使用本次 Mihomo 订阅或 VLESS 链接；" +
        ("浏览器打开上面的完整 HTTPS 面板地址。\n" if public_panel else "面板通过 SSH 隧道管理。\n") +
        "尚未验证：客户端公网连接、客户端代理效果和实际出口。\n"
        "结果：/var/lib/3x-ui-bootstrap/result.txt（仅 root 可读）\n")
    if "TRAFFIC_BUDGET" in c:
        result += "\n" + traffic_status(c, state)
    atomic_write(STATE_DIR / "panel-url.txt", panel_url + "\n")
    atomic_write(STATE_DIR / "result.txt", result)
    return result


def repair_reality_target(c, state, arch):
    require(state.get("files_installed") and state.get("panel_ready") and state.get("api_token")
            and all(state.get(k) for k in ("uuid", "private_key", "public_key", "short_id")),
            "基础安装或身份记录不完整；修复不会重新安装或生成密钥。")
    verify_core(arch)
    check_db(c, state)
    validate_tls(c)
    require(service_active(), "x-ui 未运行；请先检查并启动已有服务。")
    path = STATE_DIR / "reality-target-repair.json"
    api = API(c, state)
    wait_api(api)
    if c["REALITY_HOST"] == "www.cloudflare.com":
        ensure_inbounds(api, c, state, allow_create=False)
        verify_runtime(c, state, arch)
        result = write_results(c, state)
        if path.exists():
            completed = json.loads(path.read_text())
            if completed.get("status") == "prepared":
                require(completed.get("owner") == OWNER and completed.get("uuid") == state["uuid"]
                        and completed.get("new_config") == c, "目标修复记录与安装参数不一致。")
                completed["status"] = "complete"
                atomic_write(path, json.dumps(completed, indent=2) + "\n")
        print(result)
        return
    if path.exists():
        require(not path.is_symlink() and path.stat().st_mode & 0o077 == 0,
                "目标修复记录权限异常。")
        plan = json.loads(path.read_text())
        require(plan.get("owner") == OWNER and plan.get("uuid") == state["uuid"]
                and plan.get("status") in ("prepared", "complete")
                and plan["new_config"]["REALITY_HOST"] == "www.cloudflare.com", "修复记录与当前部署不一致。")
        if plan["status"] == "complete":
            domain_keys = {"SUB_DOMAIN", "SUB_HOST", "CERT_FILE", "CERT_KEY", "ACME_EMAIL", "PANEL_HTTPS"}
            require({k: v for k, v in c.items() if k not in domain_keys} ==
                    {k: v for k, v in plan["new_config"].items() if k not in domain_keys},
                    "已完成的修复记录与安装参数不一致。")
            ensure_inbound(api, c, state, allow_create=False)
            verify_runtime(c, state, arch)
            print(write_results(c, state))
            return
        require(c in (plan["old_config"], plan["new_config"]), "未完成的修复记录与安装参数不一致。")
    else:
        require(c["REALITY_HOST"] == "www.microsoft.com", "本修复只处理 Microsoft → Cloudflare，不迁移其他目标。")
        rows = ensure_inbounds(api, c, state, allow_create=False)
        first_role = active_roles(c)[0]
        nc, ns = node_view(c, state, first_role)
        require(probe_reality_target(nc, ns, arch, "www.cloudflare.com"),
                "Cloudflare 临时副本未通过；未修改正式节点。")
        entries = []
        for role, row in rows.items():
            _, ns = node_view(c, state, role)
            old_stream = object_field(row, "streamSettings")
            new_stream = json.loads(json.dumps(old_stream))
            reality = new_stream["realitySettings"]
            reality.update(target="www.cloudflare.com:443", serverNames=["www.cloudflare.com"])
            if "dest" in reality:
                reality["dest"] = "www.cloudflare.com:443"
            reality.setdefault("settings", {})["serverName"] = "www.cloudflare.com"
            entries.append({"role": role, "uuid": ns["uuid"], "inbound_id": row["id"], "old_stream": old_stream,
                            "new_stream": new_stream, "old_inbound": row})
        new_config = dict(c, REALITY_HOST="www.cloudflare.com")
        plan = {"owner": OWNER, "uuid": state["uuid"], "status": "prepared", "old_config": c,
                "new_config": new_config, "entries": entries,
                **{k: v for k, v in entries[0].items() if k not in ("role", "uuid")}}
        atomic_write(path, json.dumps(plan, indent=2) + "\n")
    # API 已提交但响应丢失时，读回新值后继续验收，不重复创建节点或修改客户端。
    entries = plan.get("entries", [dict(plan, role="direct", uuid=state["uuid"])])
    for entry in entries:
        nc, ns = node_view(plan["old_config"], state, entry["role"])
        row = managed_inbound(api, ns)
        require(row.get("id") == entry["inbound_id"], "节点身份已变化；停止修复。")
        expected = inbound_payload(nc, ns)
        require(all(row.get(k) == expected[k] for k in (
            "port", "protocol", "listen", "enable", "shareAddrStrategy", "shareAddr")),
            "节点端口、监听或分享地址已被另外修改；停止修复。")
        stream = object_field(row, "streamSettings")
        require(stream in (entry["old_stream"], entry["new_stream"]), "节点协议已被另外修改；保留修复记录，停止自动覆盖。")
        if stream == entry["old_stream"]:
            print("更新原节点的 REALITY 目标和 SNI；保留客户端及端口…", flush=True)
            api.call("inbounds/update/" + str(entry["inbound_id"]), dict(row, streamSettings=json.dumps(entry["new_stream"])))
    new_config = plan["new_config"]
    ensure_inbounds(api, new_config, state, allow_create=False)
    run(["systemctl", "restart", "x-ui"])
    wait_api(api)
    ensure_inbounds(api, new_config, state, allow_create=False)
    verify_runtime(new_config, state, arch)
    state["config"] = new_config
    state["phase"] = "complete"
    save(state)
    result = write_results(new_config, state)
    plan["status"] = "complete"
    atomic_write(path, json.dumps(plan, indent=2) + "\n")
    print("REALITY 目标修复完成；Shadowrocket 请重新导入下面的新链接，Mihomo 更新原订阅。\n", flush=True)
    print(result)


def domain_config(c):
    values = {key: c[key] for key in ("SERVER_IP", "NODE_PORT", "PANEL_PORT", "SUB_PORT",
              "REALITY_HOST", "NODE_NAME", "SUB_DOMAIN", "ACME_EMAIL")}
    if "NODE_MODE" in c:
        values.update(NODE_MODE=c["NODE_MODE"], ISP_NODE_PORT=c["ISP_NODE_PORT"])
        if "ISP" in c:
            p = c["ISP"]
            values.update(ISP_PROTOCOL=p["protocol"], ISP_HOST=p["host"], ISP_PORT=p["port"],
                          ISP_USERNAME=p["username"], ISP_PASSWORD=p["password"], ISP_EXPECTED_IP=p["expected_ip"])
    values.update(SUB_DOMAIN=config_values()["SUB_DOMAIN"],
                  PANEL_HTTPS=config_values()["PANEL_HTTPS"],
                  ACME_EMAIL=config_values()["ACME_EMAIL"] or c["ACME_EMAIL"])
    require(values["SUB_DOMAIN"], "请先填写配置文件中的 SUB_DOMAIN，再执行 --configure-domain。")
    parsed = parse_config(values)
    if "TRAFFIC_BUDGET" in c:
        parsed["TRAFFIC_BUDGET"] = dict(c["TRAFFIC_BUDGET"])
    if "NODE_MODE" not in c:
        parsed.pop("NODE_MODE", None)
        parsed.pop("ISP_NODE_PORT", None)
    return parsed


def managed_settings(c, state):
    expected = initial_settings(c, state)
    with contextlib.closing(sqlite3.connect("file:" + str(DB) + "?mode=ro", uri=True)) as db:
        rows = [(k, v) for k, v in db.execute('SELECT "key", value FROM settings') if k in expected]
    require(len(rows) == len(expected) and len(dict(rows)) == len(expected),
            "面板或订阅配置缺失或重复，请先检查数据库。")
    return dict(rows)


def configure_domain(c, state, arch):
    require(state.get("phase") == "complete" and state.get("files_installed") and state.get("panel_ready")
            and state.get("api_token"), "必须先完成此脚本的基础安装，才能原地配置域名。")
    new_config = domain_config(c)
    print(firewall_instructions(new_config), flush=True)
    check_isp(new_config)
    verify_core(arch)
    path = STATE_DIR / "domain-change.json"
    plan = None
    if path.exists():
        require(not path.is_symlink() and path.stat().st_mode & 0o077 == 0, "域名切换记录权限异常。")
        previous = json.loads(path.read_text())
        require(previous.get("owner") == OWNER and previous.get("uuid") == state["uuid"]
                and previous.get("status") in ("prepared", "complete"), "域名切换记录与当前部署不一致。")
        if previous["status"] == "prepared":
            require(c in (previous["old_config"], previous["new_config"])
                    and new_config == previous["new_config"], "域名切换尚未完成，请使用原域名和 PANEL_HTTPS 参数续跑。")
            plan = previous
        else:
            fields = ("SERVER_IP", "PANEL_PORT", "SUB_PORT", "SUB_DOMAIN", "SUB_HOST", "CERT_FILE", "CERT_KEY", "ACME_EMAIL", "PANEL_HTTPS")
            require(all(c.get(k) == previous["new_config"].get(k) for k in fields),
                    "已完成的域名切换记录与安装参数不一致。")
    if plan is None and new_config == c:
        ensure_inbounds(API(c, state), c, state, allow_create=False)
        verify_runtime(c, state, arch)
        print(write_results(c, state))
        return
    check_environment(new_config, owned=True)
    check_dns(new_config)
    if plan is None:
        check_db(c, state)
        require(service_active(), "原服务未运行；请先恢复现有服务，再切换域名。")
        ensure_inbounds(API(c, state), c, state, allow_create=False)
    else:
        actual = managed_settings(c, state)
        require(actual in (plan["old_settings"], plan["new_settings"]),
                "面板或订阅已被另外修改；保留记录，停止自动覆盖。")
    # 先取得并校验证书；此时不替换现有启动检查或续期任务，签发失败仍可使用原服务。
    install_certbot()
    print("申请并校验域名 HTTPS 证书" + ("；面板和订阅共用证书…" if new_config.get("PANEL_HTTPS") else "；面板保持 SSH 模式…"), flush=True)
    ensure_certificate(new_config, activate=False)
    if plan is None:
        check_db(c, state)
        backup = STATE_DIR / ("before-domain-change-" + secrets.token_hex(6) + ".db")
        with contextlib.closing(sqlite3.connect("file:" + str(DB) + "?mode=ro", uri=True)) as source:
            with contextlib.closing(sqlite3.connect(backup)) as dest:
                source.backup(dest)
        backup.chmod(0o600)
        plan = {"owner": OWNER, "uuid": state["uuid"], "status": "prepared", "backup_db": str(backup),
                "old_config": c, "new_config": new_config, "old_settings": initial_settings(c, state),
                "new_settings": initial_settings(new_config, state)}
        atomic_write(path, json.dumps(plan, indent=2) + "\n")
    print("切换面板与订阅地址；保留账号、Base URL、节点和客户端…", flush=True)
    run(["systemctl", "stop", "x-ui"])
    require(not service_active(), "服务未停止，不写入正在运行的数据库。")
    require(managed_settings(c, state) in (plan["old_settings"], plan["new_settings"]),
            "停止服务后发现配置变化；保留记录，停止自动覆盖。")
    with contextlib.closing(sqlite3.connect(DB)) as db, db:
        for key, value in plan["new_settings"].items():
            db.execute('UPDATE settings SET value = ? WHERE "key" = ?', (value, key))
    activate_certificate(new_config)
    check_db(new_config, state)
    run(["systemctl", "start", "x-ui"])
    api = API(new_config, state)
    wait_api(api)
    ensure_inbounds(api, new_config, state, allow_create=False)
    verify_runtime(new_config, state, arch)
    state["config"] = new_config
    save(state)
    result = write_results(new_config, state)
    plan["status"] = "complete"
    atomic_write(path, json.dumps(plan, indent=2) + "\n")
    print("域名与 HTTPS 配置完成；客户端请使用下面的新订阅地址。\n", flush=True)
    print(result)


def selected_node_config(c):
    values = {key: c[key] for key in ("SERVER_IP", "NODE_PORT", "PANEL_PORT", "SUB_PORT",
              "REALITY_HOST", "NODE_NAME", "SUB_DOMAIN", "ACME_EMAIL")}
    values["PANEL_HTTPS"] = "true" if c.get("PANEL_HTTPS") else "false"
    for key, default in (("NODE_NAME", c["NODE_NAME"]), ("NODE_MODE", "direct"), ("ISP_NODE_PORT", "8443"),
                         ("TOTAL_MONTHLY_GB", "0"), ("ISP_MONTHLY_GB", "0"),
                         ("ISP_PROTOCOL", "socks5"), ("ISP_HOST", ""), ("ISP_PORT", ""),
                         ("ISP_USERNAME", ""), ("ISP_PASSWORD", ""), ("ISP_EXPECTED_IP", "")):
        values[key] = config_values().get(key, default)
    return parse_config(values)


def configure_nodes(c, state, arch):
    new_config = selected_node_config(c)  # 最先校验模式及 ISP 必填字段。
    require(state.get("phase") == "complete" and state.get("api_token"), "请先完成基础安装，再配置现有线路。")
    check_environment(new_config, True)
    print(firewall_instructions(new_config), flush=True)
    check_isp(new_config)
    verify_core(arch)
    validate_tls(new_config)
    path = STATE_DIR / "node-change.json"
    plan = None
    if path.exists():
        require(not path.is_symlink() and path.stat().st_mode & 0o077 == 0, "线路配置记录权限异常。")
        previous = json.loads(path.read_text())
        require(previous.get("owner") == OWNER and previous.get("uuid") == state["uuid"]
                and previous.get("status") in ("prepared", "complete"), "线路配置记录不属于此安装。")
        if previous["status"] == "prepared":
            require(new_config == previous["new_config"] and c in (previous["old_config"], new_config),
                    "线路配置尚未完成，请使用相同昵称、模式及 ISP 参数续跑。")
            plan = previous
    if plan is None and new_config == c:
        verify_runtime(c, state, arch)
        print(write_results(c, state))
        return
    if plan is None:
        check_db(c, state)
        require(service_active(), "现有服务未运行，请先恢复服务。")
        api = API(c, state)
        ensure_inbounds(api, c, state, allow_create=False)
        if "TRAFFIC_BUDGET" in new_config:
            bind_traffic_reset(c, state)
        old_template = read_routing(api)
        require("ISP" in c or not any(o.get("tag") == "bootstrap-isp" for o in old_template["outbounds"]),
                "bootstrap-isp 出站名称已被其他配置占用。")
        rows = api.call("inbounds/list")
        candidate = json.loads(json.dumps(state))
        prepare_nodes(new_config, candidate)
        with contextlib.closing(sqlite3.connect("file:" + str(DB) + "?mode=ro", uri=True)) as db:
            saved_path = db.execute('SELECT value FROM settings WHERE "key"=?', ("subPath",)).fetchone()
        raw_path = state.get("raw_sub_path", saved_path[0] if saved_path else "/sub/")
        require(re.fullmatch(r"/(?:[A-Za-z0-9_-]+/)*", raw_path) is not None,
                "原始订阅路径格式异常，请先检查面板的订阅路径。")
        for role in active_roles(new_config):
            nc, ns = node_view(new_config, candidate, role)
            matching = [r for r in rows if any(v.get("id") == ns["uuid"] for v in object_field(r, "settings").get("clients", []))]
            require(len(matching) <= 1 and (matching or not any(r.get("port") == nc["NODE_PORT"] for r in rows)),
                    "所选节点端口已有其他入站，停止配置。")
            if not matching:
                require(not any(port == nc["NODE_PORT"] for _, port, _ in sockets()), "新线路端口已被占用。")
            require(not any(str(v.get("email", "")).casefold() == nc["NODE_NAME"].casefold() and v.get("id") != ns["uuid"]
                    for r in rows for v in object_field(r, "settings").get("clients", [])), "昵称对应的客户端名称已被占用。")
        backup = STATE_DIR / ("before-node-change-" + secrets.token_hex(6) + ".db")
        with contextlib.closing(sqlite3.connect("file:" + str(DB) + "?mode=ro", uri=True)) as source:
            with contextlib.closing(sqlite3.connect(backup)) as dest:
                source.backup(dest)
        backup.chmod(0o600)
        plan = {"owner": OWNER, "uuid": state["uuid"], "status": "prepared", "old_config": c,
                "new_config": new_config, "nodes": candidate["nodes"], "backup_db": str(backup),
                "raw_sub_path": raw_path, "old_template": old_template, "old_rows": rows}
        atomic_write(path, json.dumps(plan, indent=2) + "\n")
    planned_nodes = json.loads(json.dumps(plan["nodes"]))
    for role, saved_node in state.get("nodes", {}).items():
        if role in planned_nodes:
            require(saved_node["uuid"] == planned_nodes[role]["uuid"], "节点身份记录已被另外修改。")
            planned_nodes[role].update(saved_node)
    state["nodes"] = planned_nodes
    state["raw_sub_path"] = plan["raw_sub_path"]
    save(state)  # 任何 API 写入之前保存新节点身份，响应丢失后仍使用同一 UUID/Sub ID。
    run(["systemctl", "stop", "x-ui"])
    require(not service_active(), "服务未停止，不修改数据库。")
    current_settings = managed_settings(c, state)
    require(current_settings == initial_settings(c, state) or
            all(current_settings.get(k) == initial_settings(new_config, state).get(k) for k in current_settings),
            "面板设置在配置期间已变化，停止自动覆盖。")
    with contextlib.closing(sqlite3.connect(DB)) as db, db:
        for key, value in initial_settings(new_config, state).items():
            cursor = db.execute('UPDATE settings SET value=? WHERE "key"=?', (value, key))
            if not cursor.rowcount:
                db.execute('INSERT INTO settings ("key",value) VALUES (?,?)', (key, value))
    run(["systemctl", "start", "x-ui"])
    api = API(new_config, state)
    wait_api(api)
    ensure_node_keys(api, new_config, state)
    plan["nodes"] = state["nodes"]
    atomic_write(path, json.dumps(plan, indent=2) + "\n")
    for role, identity in state["nodes"].items():
        ns = dict(state, **identity)
        found = [r for r in api.call("inbounds/list") if any(v.get("id") == ns["uuid"] for v in object_field(r, "settings").get("clients", []))]
        require(len(found) <= 1, "同一客户端出现在多个入站，停止配置。")
        if role not in active_roles(new_config):
            if found and found[0].get("enable"):
                api.call("inbounds/setEnable/" + str(found[0]["id"]), {"enable": False})
            continue
        nc, ns = node_view(new_config, state, role)
        if not found:
            ensure_inbound(api, nc, ns)
            continue
        row = found[0]
        expected = inbound_payload(nc, ns)
        require(all(row.get(k) == expected[k] for k in ("protocol", "listen", "shareAddrStrategy", "shareAddr"))
                and contains(object_field(row, "streamSettings"), object_field(expected, "streamSettings")),
                "原入站协议、监听或分享地址已被另外修改。")
        old_name = plan["old_config"]["NODE_NAME"] + ("-Direct" if role == "direct" else "-ISP")
        if "NODE_MODE" not in plan["old_config"]:
            old_name = plan["old_config"]["NODE_NAME"]
        old_row = next((r for r in plan["old_rows"] if any(v.get("id") == ns["uuid"]
                       for v in object_field(r, "settings").get("clients", []))), None)
        old_email = "client-01" if "NODE_MODE" not in plan["old_config"] else old_name
        if old_row:
            # 停用期间可能修改过全局昵称；以本次变更前的受管节点快照为准。
            old_name = old_row.get("remark")
            old_email = next(v.get("email") for v in object_field(old_row, "settings")["clients"] if v.get("id") == ns["uuid"])
        require(row.get("remark") in (old_name, nc["NODE_NAME"]) and row.get("port") == nc["NODE_PORT"],
                "原入站名称或端口在配置期间已被另外修改。")
        client = next(v for v in object_field(row, "settings")["clients"] if v.get("id") == ns["uuid"])
        allowed_emails = {old_email, nc["NODE_NAME"]}
        require(client.get("email") in allowed_emails, "原客户端名称已被另外修改。")
        if client["email"] != nc["NODE_NAME"]:
            route = "clients/update/" + urllib.parse.quote(client["email"], safe="") + "?inboundIds=" + str(row["id"])
            if "TRAFFIC_BUDGET" in c or "TRAFFIC_BUDGET" in new_config:
                record = api.call("clients/get/" + urllib.parse.quote(client["email"], safe="")).get("client", {})
                require(record.get("uuid") == ns["uuid"], "改名前的客户端身份不一致。")
                client = preserved_client(client, record)
            api.call(route, dict(client, email=nc["NODE_NAME"]))
        if row.get("remark") != nc["NODE_NAME"]:
            api.call("inbounds/update/" + str(row["id"]), dict(row, remark=nc["NODE_NAME"]))
        if not row.get("enable"):
            api.call("inbounds/setEnable/" + str(row["id"]), {"enable": True})
    apply_native_quotas(new_config, state, force="TRAFFIC_BUDGET" in c)
    rows = ensure_inbounds(api, new_config, state, allow_create=False)
    routing_path = STATE_DIR / "routing-plan.json"
    if not plan.get("routing_prepared"):
        current = read_routing(api)
        target = json.loads(json.dumps(current))
        tags = {r["tag"] for r in api.call("inbounds/list") if any(v.get("id") in
                {n["uuid"] for n in state["nodes"].values()} for v in object_field(r, "settings").get("clients", []))}
        require(not any(set(r.get("inboundTag", [])).intersection(tags) and not set(r["inboundTag"]).issubset(tags)
                for r in target["routing"]["rules"]), "已有规则混合引用其他入站，停止自动改写。")
        target["routing"]["rules"] = [r for r in target["routing"]["rules"] if not set(r.get("inboundTag", [])).intersection(tags)]
        existing_isp = [o for o in target["outbounds"] if o.get("tag") == "bootstrap-isp"]
        require(not existing_isp or "ISP" in plan["old_config"], "bootstrap-isp 出站名称已被其他配置占用。")
        target["outbounds"] = [o for o in target["outbounds"] if o.get("tag") != "bootstrap-isp"]
        if "isp" in active_roles(new_config):
            target["outbounds"].append(isp_outbound(new_config))
        rules = target["routing"]["rules"]
        index = next((i for i, r in enumerate(rules) if r.get("outboundTag") not in ("api", "blocked")
                      and not (r.get("inboundTag") and tags.isdisjoint(r["inboundTag"]))), len(rules))
        rules[index:index] = route_rules(new_config, rows)
        routing_matches(target, new_config, rows)
        atomic_write(routing_path, json.dumps({"owner": OWNER, "uuid": state["uuid"], "config": new_config,
                     "old_template": current, "new_template": target}, indent=2) + "\n")
        plan["routing_prepared"] = True
        atomic_write(path, json.dumps(plan, indent=2) + "\n")
    ensure_routing(api, new_config, state, rows, allow_update=True)
    run(["systemctl", "restart", "x-ui"])
    wait_api(api)
    verify_runtime(new_config, state, arch)
    state["config"] = new_config
    save(state)
    result = write_results(new_config, state)
    plan["status"] = "complete"
    atomic_write(path, json.dumps(plan, indent=2) + "\n")
    print(result)


def main():
    mode = MODE
    saved_config_mode = mode in ("--diagnose", "--repair-reality-target", "--configure-domain", "--configure-nodes",
                                 "--configure-traffic", "--traffic-status")
    c = None if saved_config_mode else config_from_file()
    state_file = STATE_DIR / "state.json"
    state = None
    if STATE_DIR.exists():
        st = STATE_DIR.lstat()
        require(not STATE_DIR.is_symlink() and st.st_uid == 0 and st.st_mode & 0o077 == 0,
                "状态目录权限或所有者异常；应为 root、700。")
        require(state_file.is_file() and not state_file.is_symlink(), "状态目录不完整，请先检查，勿手动清空。")
        state = json.loads(state_file.read_text())
        require(state.get("owner") == OWNER and state.get("version") == VERSION,
                "状态文件不属于这一版安装器；本版不自动迁移旧部署，请保留现有数据。")
        require("TRAFFIC_LIMITS" not in state["config"] or mode in ("--configure-traffic", "--traffic-status", "--diagnose"),
                "此部署使用旧共享额度任务；请填写 TOTAL_MONTHLY_GB / ISP_MONTHLY_GB 并执行 --configure-traffic 迁移为原生固定配额。")
        if saved_config_mode:
            c = state["config"]
            if mode in CONFIG_MODES:
                require(config_values()["SERVER_IP"] == c["SERVER_IP"],
                        "配置中的 SERVER_IP 与此部署不一致；停止修改，请确认配置文件和目标服务器。")
        else:
            require(mode == "--check" or state.get("config") == c,
                    "参数与已有安装不一致；线路使用 --configure-nodes，域名使用 --configure-domain，配额使用 --configure-traffic。")
    if mode == "--traffic-status":
        require(state is not None and state.get("api_token"), "没有可查询的已部署面板。")
        require("TRAFFIC_LIMITS" not in c, "旧共享额度尚未迁移；请先用 --configure-traffic 设置原生配额。")
        print(traffic_status(c, state))
        return
    if mode == "--diagnose":
        require(state is not None, "没有找到本安装器保存的部署，无法诊断。")
        arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
        require(arch in DIGESTS, "仅支持 amd64 / arm64。")
        for role in active_roles(c):
            print("诊断线路：" + role, flush=True)
            diagnose_node(*node_view(c, state, role), arch)
        return
    domain_path = STATE_DIR / "domain-change.json"
    if domain_path.exists() and mode != "--configure-domain":
        require(json.loads(domain_path.read_text()).get("status") == "complete",
                "域名切换尚未完成；请使用 --configure-domain 续跑，不要重新安装或修复目标。")
    node_path = STATE_DIR / "node-change.json"
    if node_path.exists() and mode != "--configure-nodes":
        require(json.loads(node_path.read_text()).get("status") == "complete",
                "线路配置尚未完成；请使用 --configure-nodes 续跑。")
    if mode in ("--repair-reality-target", "--configure-domain", "--configure-nodes", "--configure-traffic"):
        require(state is not None, "没有找到本安装器保存的部署，无法执行现有部署配置。")
        arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
        require(arch in DIGESTS, "仅支持 amd64 / arm64。")
        with open(STATE_DIR / "install.lock", "a+") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("另一个安装或修复进程正在运行。")
            fresh = json.loads(state_file.read_text())
            require(fresh.get("owner") == OWNER and fresh.get("version") == VERSION, "安装记录已变化，停止修复。")
            repair_path = STATE_DIR / "reality-target-repair.json"
            if mode in ("--configure-domain", "--configure-nodes", "--configure-traffic"):
                require(not repair_path.exists() or json.loads(repair_path.read_text()).get("status") == "complete",
                        "目标修复尚未完成；请先用 --repair-reality-target 续跑。")
                operation = {"--configure-domain": configure_domain, "--configure-nodes": configure_nodes,
                             "--configure-traffic": configure_traffic}[mode]
                operation(fresh["config"], fresh, arch)
            else:
                repair_reality_target(fresh["config"], fresh, arch)
        return
    repair_path = STATE_DIR / "reality-target-repair.json"
    if repair_path.exists():
        require(json.loads(repair_path.read_text()).get("status") == "complete",
                "目标修复尚未完成；请使用 --repair-reality-target 续跑，不要重新安装。")
    arch = check_environment(c, state is not None)
    print(firewall_instructions(c), flush=True)
    check_isp(c)
    print("检查 REALITY 目标的 TLS 1.3 / HTTP/2…", flush=True)
    check_target(c)
    check_dns(c)
    check_certificate_readiness(c)
    if mode == "--check":
        print("检查通过；未安装软件、未修改服务。公网端口和客户端连通性需另外验证。")
        return
    if state is None:
        STATE_DIR.mkdir(mode=0o700)
    with open(STATE_DIR / "install.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("另一个安装进程正在运行。")
        if state is None:
            # 在安装、建库前先持久化身份，失败重跑沿用同一组凭据。
            state = {"owner": OWNER, "version": VERSION, "config": c,
                "username": "admin_" + secrets.token_hex(4), "password": secrets.token_urlsafe(24),
                "base_path": "/" + secrets.token_hex(12) + "/", "uuid": str(uuid.uuid4()),
                "short_id": secrets.token_hex(8), "sub_id": secrets.token_hex(8), "phase": "created",
                "deployed_at": int(time.time())}
            state["raw_sub_path"] = "/sub/"
            prepare_nodes(c, state)
            save(state)
        # 取得锁后重读，防止并发启动沿用过时状态。
        state = json.loads(state_file.read_text())
        if state["phase"] == "complete":
            ensure_inbounds(API(c, state), c, state, allow_create=False)
            verify_runtime(c, state, arch)
            print(write_results(c, state))
            return
        if not state.get("files_installed"):
            print("安装必要依赖并校验官方发行包…", flush=True)
            run(["apt-get", "update"])
            packages = ["curl", "ca-certificates", "tar", "python3-yaml", "openssl", "python3-venv"]
            run(["apt-get", "install", "-y", "--no-install-recommends"] + packages)
            install_release(arch)
            print("安装并校验 Xray-core " + CORE_VERSION + "…", flush=True)
            install_core(arch)
            install_certbot()
            state["files_installed"] = True
            state["core_version"] = CORE_VERSION
            save(state)
        print("配置 HTTPS 证书与自动续期…", flush=True)
        ensure_certificate(c)
        if not state.get("panel_ready"):
            print("配置管理入口（首次启动前）…", flush=True)
            harden_initial_db(c, state)
            if not state.get("api_token"):
                output = run([str(APP / "x-ui"), "setting", "-getApiToken", "-tokenName", OWNER,
                              "-tokenScope", "admin"], capture=True, cwd=APP)
                match = re.search(r"(?m)^apiToken:\s*(\S+)\s*$", output)
                require(match is not None, "未取得 API Token。")
                state["api_token"] = match[1]
                save(state)
            write_unit()
            state["panel_ready"] = True
            save(state)
        check_db(c, state)
        verify_core(arch)
        run(["systemctl", "start", "x-ui"])
        api = API(c, state)
        wait_api(api)
        ensure_node_keys(api, c, state)
        if "TRAFFIC_BUDGET" in c:
            bind_traffic_reset(c, state)
        print("创建并读回所选 VLESS + REALITY 线路…", flush=True)
        rows = ensure_inbounds(api, c, state)
        ensure_routing(api, c, state, rows, allow_update=True)
        run(["systemctl", "restart", "x-ui"])
        wait_api(api)
        ensure_inbounds(api, c, state)
        verify_runtime(c, state, arch)
        result = write_results(c, state)
        state["phase"] = "complete"
        save(state)
        print(result)


def cli(argv=None, script_path=None):
    global MODE, INPUT_CONFIG
    parser = argparse.ArgumentParser(
        prog="install-3x-ui.sh",
        description="3X-UI Bootstrap：使用独立 JSON 配置部署 Direct / ISP 节点。",
        epilog="配置默认位于脚本同目录的 config.json。--validate-config 可在本地执行，无需 root 或网络。")
    parser.add_argument("--config", metavar="FILE", help="指定私有 JSON 配置文件")
    parser.add_argument("--version", action="version", version=
                        "3x-ui-bootstrap " + PROJECT_VERSION + " / 3x-ui " + VERSION + " / Xray " + CORE_VERSION)
    actions = parser.add_mutually_exclusive_group()
    for flag, help_text in (
        ("--install", "安装或续跑（默认）"),
        ("--validate-config", "仅检查配置格式、模式和端口关系；不联网、不读安装状态"),
        ("--check", "在 VPS 预检系统、ISP、DNS、REALITY 目标和证书条件"),
        ("--show", "读取服务器保存的账号、面板和订阅链接"),
        ("--diagnose", "读取已保存配置，用临时副本诊断 REALITY 握手"),
        ("--repair-reality-target", "修复已有部署的 REALITY 目标"),
        ("--configure-domain", "从配置文件读取域名和 HTTPS 选项，原地修改"),
        ("--configure-nodes", "从配置文件读取线路、ISP 和配额选项，原地修改"),
        ("--configure-traffic", "从配置文件读取月配额，保留原部署重置日"),
        ("--traffic-status", "读取现有客户端原生用量"),
    ):
        actions.add_argument(flag, action="store_const", const=flag, dest="mode", help=help_text)
    args = parser.parse_args(argv)
    MODE = args.mode or "--install"
    INPUT_CONFIG = None
    if MODE in CONFIG_MODES:
        default = Path(script_path).resolve().with_name("config.json") if script_path else Path("config.json")
        INPUT_CONFIG = load_config_values(args.config or default)
    if MODE == "--validate-config":
        c = config_from_file()
        print("配置校验：PASS；仅检查本地配置，未联网、未读取或修改服务器状态。")
        print(firewall_instructions(c), end="")
        return 0
    require(os.geteuid() == 0, "请使用 sudo bash install-3x-ui.sh 执行服务器操作。")
    if MODE == "--show":
        result = STATE_DIR / "result.txt"
        require(result.is_file(), "尚未找到部署结果，请先完成安装。")
        print(result.read_text(), end="")
        return 0
    require(platform.system() == "Linux" and Path("/run/systemd/system").is_dir(),
            "服务器操作仅支持使用 systemd 的 Ubuntu / Debian VPS。")
    main()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(cli(sys.argv[2:], script_path=sys.argv[1]))
    except (Exception, KeyboardInterrupt) as exc:
        # 出错时不自动删除数据库、不覆盖既有节点，也不回显密码或响应体。
        if MODE in ("--validate-config", "--check"):
            print("校验未通过：" + (str(exc) if not isinstance(exc, KeyboardInterrupt) else "用户中断"), file=sys.stderr)
        elif MODE == "--diagnose":
            print("诊断未完成：" + (str(exc) if not isinstance(exc, KeyboardInterrupt) else "用户中断"))
            print("未修改现有服务配置、账号、节点和安装记录。")
        elif MODE == "--repair-reality-target":
            print("修复未完成：" + (str(exc) if not isinstance(exc, KeyboardInterrupt) else "用户中断"))
            print("保留节点、身份和修复记录；使用同一条 --repair-reality-target 命令重试。")
        elif MODE == "--configure-domain":
            print("域名配置未完成：" + (str(exc) if not isinstance(exc, KeyboardInterrupt) else "用户中断"))
            print("保留数据库备份和切换记录；使用相同参数及 --configure-domain 续跑，不要删除安装记录。")
        elif MODE == "--configure-nodes":
            print("线路配置未完成：" + (str(exc) if not isinstance(exc, KeyboardInterrupt) else "用户中断"))
            print("保留节点身份、数据库备份和配置记录；使用相同参数及 --configure-nodes 续跑。")
        elif MODE == "--configure-traffic":
            print("配额配置未完成：" + (str(exc) if not isinstance(exc, KeyboardInterrupt) else "用户中断"))
            print("保留原生流量计数和部署日；使用相同参数及 --configure-traffic 续跑。")
        else:
            print("安装未完成：" + (str(exc) if not isinstance(exc, KeyboardInterrupt) else "用户中断"))
            print("保留状态和数据；使用同一份脚本重试。日志：/var/lib/3x-ui-bootstrap/install.log")
        raise SystemExit(1)
PYTHON
