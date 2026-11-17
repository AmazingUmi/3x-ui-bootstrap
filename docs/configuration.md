# Configuration Reference

English | [简体中文](configuration.zh-CN.md) · [Project home](../README.md) · [Operations](operations.md) · [Security](security.md)

Start by copying [config.example.json](../config.example.json). Use `--config FILE` to specify a custom path; otherwise, the installer reads `config.json` in the same directory as `install-3x-ui.sh`. All 20 supported fields are documented below, and any omitted optional field uses its default value.

## File Format

- Must be a valid UTF-8 JSON object no larger than **64 KiB**, with file permissions set to `600` or stricter (`chmod 600 config.json`).
- Ports are JSON integers, traffic quotas are JSON numbers, and `PANEL_HTTPS` is a JSON Boolean (`true` / `false`). Do not wrap these values in quotes.
- Comments, duplicate keys, unknown keys, `NaN`, and `Infinity` are rejected. Key names are case-sensitive.
- Escape double quotes and backslashes using standard JSON rules. Single quotes, `$`, and backticks do not require shell escaping.
- The configuration file is parsed strictly as data and is never sourced or executed by a shell. `BOOTSTRAP_*` environment variables cannot override settings.

## Required Fields Quick Lookup

| Scenario | Required fields |
| --- | --- |
| Every deployment | `SERVER_IP` (the VPS static public IPv4 address) |
| `NODE_MODE="isp"` or `"direct+isp"` | `ISP_HOST`, `ISP_PORT`, `ISP_USERNAME`, `ISP_PASSWORD` |
| `PANEL_HTTPS=true` | `SUB_DOMAIN` |
| Dual routes with `TOTAL_MONTHLY_GB > 0` | `ISP_MONTHLY_GB`, satisfying `0 < ISP_MONTHLY_GB < TOTAL_MONTHLY_GB` |

With the defaults (`direct` mode, SSH-tunneled panel, unlimited traffic), only `SERVER_IP` is required.

## Server and Routing

| Field | Type | Default | Description and constraints |
| --- | --- | --- | --- |
| `SERVER_IP` | String | Required | Static public IPv4 address of the VPS; private, reserved, and placeholder values are rejected |
| `NODE_NAME` | String | `"MyNode"` | Node display nickname, 1–64 characters; no whitespace, `/`, `\`, or control characters |
| `NODE_MODE` | String | `"direct"` | Routing mode: `"direct"`, `"isp"`, or `"direct+isp"` |
| `REALITY_HOST` | String | `"www.cloudflare.com"` | REALITY target and SNI hostname (domain only, without scheme, port, or path; ownership not required) |

- `direct` routes traffic directly from the VPS. `isp` routes traffic through your upstream proxy. `direct+isp` enables both routes on the same `NODE_PORT` with separate UUIDs and subscription URLs (`<NODE_NAME>-Direct` and `<NODE_NAME>-ISP`).
- Renaming a node locally in a client app does not change its server-side exit route.
- During `--check` / `--install`, the installer verifies that `REALITY_HOST` supports TLS 1.3 and HTTP/2.

## Xray Core Version

| Field | Type | Default | Description and constraints |
| --- | --- | --- | --- |
| `XRAY_VERSION` | String | `"26.10.31"` | Allowed values: `"26.10.31"` (default) or `"26.6.27"` (legacy client compatibility). Both use pinned official SHA-256 checksums; custom URLs and `latest` are not accepted |

Used on fresh installations and by `--switch-core` to change the Xray binary safely. Other maintenance commands preserve the currently deployed core version. Keep `26.10.31` unless an older client requires `26.6.27`.

## ISP Upstream Proxy

These fields are used only when `NODE_MODE` includes `isp`. Keep the default empty values for `direct`-only deployments.

| Field | Type | Default | Description and constraints |
| --- | --- | --- | --- |
| `ISP_HOST` | String | `""` | Required for ISP modes; upstream IP or domain without scheme, port, or path |
| `ISP_PORT` | Integer or `null` | `null` | Required for ISP modes; `1–65535` (upstream proxy port) |
| `ISP_USERNAME` | String | `""` | Required for ISP modes; no control characters (HTTP usernames cannot contain `:`) |
| `ISP_PASSWORD` | String | `""` | Required for ISP modes; no control characters |
| `ISP_PROTOCOL` | String | `"socks5"` | `"socks5"` or `"http"`, matching your proxy provider |
| `ISP_EXPECTED_IP` | String | `""` | Optional expected public IPv4 exit; when set, preflight and runtime checks verify the actual exit matches. Leave empty for dynamic exits |

- For SOCKS5, username and password must each be at most 255 bytes when UTF-8 encoded.
- `ISP_HOST` is the proxy connection endpoint, whereas `ISP_EXPECTED_IP` is the resulting public exit IP (they may differ). The ISP exit IP must always differ from `SERVER_IP`.
- ISP routing carries TCP traffic and explicitly blocks UDP. Upstream failures never fall back to Direct. Upstream credentials are never included in client subscription exports.

## Domain and Management Panel

| Field | Type | Default | Description and constraints |
| --- | --- | --- | --- |
| `SUB_DOMAIN` | String | `""` | Custom domain without scheme, port, or path. When empty, subscriptions use an IP-based HTTPS certificate |
| `PANEL_HTTPS` | Boolean | `false` | **Recommended** `false`: panel binds only to `127.0.0.1` and is accessed via SSH tunnel. `true`: exposes HTTPS panel publicly (requires `SUB_DOMAIN`) |
| `ACME_EMAIL` | String | `""` | Optional email address for Let's Encrypt certificate notifications; must be a valid email format if provided |

- When `SUB_DOMAIN` is set, its `A` record must point directly to `SERVER_IP` without CDN proxying.
- You can set `SUB_DOMAIN` while keeping `PANEL_HTTPS=false`: your domain will be used for HTTPS subscriptions while the management panel stays private behind SSH.
- `SUB_DOMAIN` and `REALITY_HOST` are normalized to lowercase (max 253 chars, valid domain labels).

## Listening Ports

| Field | Type | Default | Listener and purpose |
| --- | --- | --- | --- |
| `NODE_PORT` | Integer | `443` | Public VLESS + REALITY inbound port shared by active routes |
| `PANEL_PORT` | Integer | `7777` | Management panel port (`127.0.0.1` by default; `0.0.0.0` if `PANEL_HTTPS=true`) |
| `SUB_PORT` | Integer | `38443` | Public Nginx HTTPS subscription gateway port |
| `SUB_BACKEND_PORT` | Integer | `12096` | Internal 3x-ui HTTP subscription backend (`127.0.0.1` only; **never expose publicly**) |

- All four listening ports must be distinct integers between `1` and `65535`.
- None may use `80`, which is reserved for Certbot HTTP-01 validation and renewal, and none may conflict with your SSH port. (`ISP_PORT` is an outbound destination port and does not conflict with these.)
- Client subscription URLs always point to `SUB_PORT` (`https://<SUB_HOST>:<SUB_PORT>/...`), never `SUB_BACKEND_PORT`.

## Monthly Traffic Quotas

| Field | Type | Default | Description and constraints |
| --- | --- | --- | --- |
| `TOTAL_MONTHLY_GB` | Number | `0` | Total monthly traffic budget in GiB (`0` = unlimited) |
| `ISP_MONTHLY_GB` | Number | `0` | ISP monthly traffic quota in GiB (behavior depends on `NODE_MODE`) |

Both accept `0` to `9999999.999` with up to 3 decimal places (`1 GiB = 1024³ bytes`). Let `T` = `TOTAL_MONTHLY_GB` and `I` = `ISP_MONTHLY_GB`:

| Mode and settings | Direct quota | ISP quota | Constraint |
| --- | --- | --- | --- |
| `direct` | `T` (unlimited if `T = 0`) | — | `I` must be `0` |
| `isp` | — | Smaller nonzero value of `T` and `I` (unlimited if both `0`) | Either can be set |
| `direct+isp`, `T > 0` | `T - I` | `I` | Must satisfy `0 < I < T` |
| `direct+isp`, `T = 0` | Unlimited | `I` (unlimited if `I = 0`) | Limits ISP independently |

- Quotas use 3x-ui's native client metering. Exhausting one route disables only that client; routes do not borrow unused quota from each other.
- Monthly resets occur at midnight (in the panel's configured time zone) on the original deployment day of the month (or the last day of shorter months). Updating quotas later preserves the original reset day.
- Note that proxy client traffic accounting may differ from your VPS provider's total NIC-level bandwidth billing.

## Configuration Examples

Omitted fields automatically use their defaults. Replace placeholders like `YOUR_VPS_IP`, example domains, and credentials with real values before deploying.

### Minimal Direct Setup

```json
{
  "SERVER_IP": "YOUR_VPS_IP"
}
```

Uses default ports (`443` / `38443` / `7777` / `12096`), IP-based HTTPS subscriptions, SSH-tunneled panel access, and unlimited traffic.

### Direct + ISP with Custom Domain and SSH Panel

```json
{
  "SERVER_IP": "YOUR_VPS_IP",
  "NODE_NAME": "MyNode",
  "NODE_MODE": "direct+isp",
  "ISP_PROTOCOL": "socks5",
  "ISP_HOST": "proxy.example.com",
  "ISP_PORT": 1080,
  "ISP_USERNAME": "YOUR_ISP_USERNAME",
  "ISP_PASSWORD": "YOUR_ISP_PASSWORD",
  "SUB_DOMAIN": "node.example.com",
  "PANEL_HTTPS": false,
  "ACME_EMAIL": "you@example.com",
  "TOTAL_MONTHLY_GB": 1000,
  "ISP_MONTHLY_GB": 100
}
```

Allocates `900 GiB` to Direct and `100 GiB` to ISP, serves subscriptions over HTTPS at `node.example.com:38443`, and keeps the management panel private behind your SSH tunnel.

## Updating Settings After Installation

Editing `config.json` alone does not modify a running deployment. Use the maintenance commands below to apply specific groups of settings.

Keep a complete `config.json` that reflects your active deployment—for fields read by a given command, omitting an optional field resets it to its default (except `ACME_EMAIL`, where empty preserves the previous email).

| Command | Fields applied from `config.json` | Notes |
| --- | --- | --- |
| `--switch-core` | `XRAY_VERSION` | Replaces the Xray binary with automatic verification and rollback; preserves database, identities, and quotas |
| `--configure-domain` | `SUB_DOMAIN`, `PANEL_HTTPS`, `ACME_EMAIL` | Requires a non-empty `SUB_DOMAIN`; empty `ACME_EMAIL` keeps existing email |
| `--configure-nodes` | `NODE_NAME`, `NODE_MODE`, all `ISP_*` fields, `TOTAL_MONTHLY_GB`, `ISP_MONTHLY_GB` | Synchronize `config.json` first if you edited ISP credentials in the web panel |
| `--configure-traffic` | `TOTAL_MONTHLY_GB`, `ISP_MONTHLY_GB` | Applies to the active mode while preserving traffic counters and the original reset day |

- All four commands verify that `SERVER_IP` in `config.json` matches the existing deployment.
- Listening ports (`NODE_PORT`, `PANEL_PORT`, `SUB_PORT`, `SUB_BACKEND_PORT`) and `REALITY_HOST` are fixed at initial installation and are not changed by these commands.
- `--repair-reality-target`, `--show`, `--traffic-status`, and `--diagnose` read saved server state and do not require `--config`. See the [Operations Guide](operations.md) for usage details.
