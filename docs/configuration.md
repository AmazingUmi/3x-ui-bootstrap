# Configuration reference

[简体中文](configuration.zh-CN.md) | [Operations guide](operations.md) | [Security notes](security.md) | [Project home](../README.md)

Start with [config.example.json](../config.example.json). Use `--config FILE` to select a private configuration file; otherwise, the installer reads `config.json` beside the script. All 19 public fields are listed below. Omitted optional fields use their defaults.

## File format

- Use a UTF-8 JSON object no larger than 64 KiB, with permissions of `600` or stricter.
- Ports are integers, quotas are numbers, and `PANEL_HTTPS` is Boolean `true` / `false`; do not quote these values.
- Comments, duplicate fields, unknown fields, `NaN`, and `Infinity` are rejected. Field names are case-sensitive.
- Escape double quotes and backslashes according to JSON syntax. Single quotes, dollar signs, and backticks need no Shell escaping.
- Configuration is read as data, never executed. `BOOTSTRAP_*` environment variables cannot override it. See [Security notes](security.md) for handling private files and links.

## Required settings

| Scenario | Required fields |
| --- | --- |
| Every deployment | `SERVER_IP`: the new VPS static public IPv4 |
| `NODE_MODE="isp"` or `"direct+isp"` | `ISP_HOST`, `ISP_PORT`, `ISP_USERNAME`, `ISP_PASSWORD` |
| `PANEL_HTTPS=true` | `SUB_DOMAIN` |
| Dual routes with `TOTAL_MONTHLY_GB>0` | `ISP_MONTHLY_GB`, satisfying `0 < ISP_MONTHLY_GB < TOTAL_MONTHLY_GB` |

The defaults provide Direct, an SSH-only panel, and unlimited traffic. Only `SERVER_IP` is required for that setup.

## VPS and routes

| Field | Type | Default | Meaning and constraints |
| --- | --- | --- | --- |
| `SERVER_IP` | String | None; required | VPS static public IPv4; private addresses, reserved addresses, and placeholders are rejected |
| `NODE_NAME` | String | `"MyNode"` | Nickname, 1–64 characters; no whitespace, `/`, `\`, or control characters |
| `NODE_MODE` | String | `"direct"` | One of `direct`, `isp`, or `direct+isp` |
| `REALITY_HOST` | String | `"www.cloudflare.com"` | REALITY target and SNI; domain only, without a scheme, port, or path; ownership of the domain is not required |

`direct` uses the VPS exit, `isp` uses the upstream proxy exit, and `direct+isp` provides both routes. Every mode uses one inbound on `NODE_PORT`. Dual routes authenticate with independent UUIDs and use different exits; their client names are `<nickname>-Direct` and `<nickname>-ISP`. Renaming a node in a client app does not change its exit.

Installation preflight checks the REALITY target for TLS 1.3 and HTTP/2 support.

## ISP upstream

These settings apply only to modes that include ISP. Keep the default empty values for Direct-only mode.

| Field | Type | Default | Meaning and constraints |
| --- | --- | --- | --- |
| `ISP_HOST` | String | `""` | Required for ISP; upstream IP or domain without a scheme, port, or path |
| `ISP_PORT` | Integer or `null` | `null` | Required for ISP; 1–65535; the upstream destination port, not a local inbound port |
| `ISP_USERNAME` | String | `""` | Required for ISP; no control characters; HTTP proxy usernames cannot contain `:` |
| `ISP_PASSWORD` | String | `""` | Required for ISP; no control characters |
| `ISP_PROTOCOL` | String | `"socks5"` | `socks5` or `http`, matching the provider's protocol |
| `ISP_EXPECTED_IP` | String | `""` | Optional expected exit public IPv4; when set, the actual exit must match. Leave empty for a dynamic exit |

For SOCKS5, the username and password must each be no longer than 255 UTF-8 bytes. `ISP_HOST` is the connection endpoint; `ISP_EXPECTED_IP` is the actual exit, which may differ. The ISP exit must always differ from `SERVER_IP`.

The ISP route supports TCP and explicitly blocks UDP. Upstream failure does not fall back to Direct. Upstream credentials are not included in client subscriptions.

## Domain and panel

| Field | Type | Default | Meaning and constraints |
| --- | --- | --- | --- |
| `SUB_DOMAIN` | String | `""` | Your domain without a scheme, port, or path; when empty, subscriptions use the VPS public IP with an HTTPS certificate |
| `PANEL_HTTPS` | Boolean | `false` | `false`: loopback-only panel accessed through SSH; `true`: public domain-based HTTPS panel, requiring `SUB_DOMAIN` |
| `ACME_EMAIL` | String | `""` | Optional certificate contact email; must have a valid email format when provided |

When `SUB_DOMAIN` is set, its A record must point directly to `SERVER_IP`. Setting a domain while keeping `PANEL_HTTPS=false` uses the domain only for subscriptions; panel access stays behind the SSH tunnel. The public panel and Nginx subscriptions share a domain and certificate, with separate ports.

`SUB_DOMAIN` and `REALITY_HOST` are normalized to lowercase. Domains must contain a dot and be at most 253 characters long. Each label must be 1–63 characters, using letters, digits, and internal hyphens only.

## Listening ports

| Field | Type | Default | Listener and purpose |
| --- | --- | --- | --- |
| `NODE_PORT` | Integer | `443` | Public VLESS + REALITY inbound shared by all active routes |
| `PANEL_PORT` | Integer | `7777` | Panel port; loopback-only by default, public when `PANEL_HTTPS=true` |
| `SUB_PORT` | Integer | `2096` | Public HTTPS subscription entry served by Nginx; allow it through the firewalls |
| `SUB_BACKEND_PORT` | Integer | `12096` | 3x-ui HTTP subscription backend bound only to `127.0.0.1`; **do not expose publicly** |

All four listening ports must be integers from 1–65535 and distinct. None may use `80/TCP`, which is reserved for certificate issuance and renewal. VPS preflight also checks for conflicts with the actual SSH port and other processes. `ISP_PORT` is an outbound destination and does not need to differ from these four local listening ports.

The default subscription path is `public 2096 HTTPS → Nginx → 127.0.0.1:12096 HTTP`. Client downloads and quota refreshes use the public `SUB_PORT`; do not put the backend port into client URLs. See [Security notes](security.md) for access-control rules and the [Operations guide](operations.md) for firewall and inspection commands.

## Monthly traffic quotas

| Field | Type | Default | Meaning and constraints |
| --- | --- | --- | --- |
| `TOTAL_MONTHLY_GB` | Number | `0` | Total monthly budget in GiB; `0` means no total limit |
| `ISP_MONTHLY_GB` | Number | `0` | ISP monthly quota in GiB; its interpretation depends on the route mode below |

Both accept `0–9999999.999`, with up to three decimal places. One GiB is 1024³ bytes. Let `T` be the total budget and `I` the ISP quota:

| Mode and settings | Direct quota | ISP quota | Constraint |
| --- | --- | --- | --- |
| `direct` | `T`; unlimited when `T=0` | No ISP route | `I` must be `0` |
| `isp` | No Direct route | The smaller nonzero value of `T` and `I`; unlimited if both are zero | Either value can be set alone |
| `direct+isp`, `T>0` | `T−I` | `I` | Requires `0<I<T` |
| `direct+isp`, `T=0` | Unlimited | `I`; unlimited when `I=0` | ISP can be limited independently |

Native panel client quotas disable only the exhausted client. Resets retain the original deployment day at midnight in the panel's time zone; shorter months use their last day. Routes do not borrow unused quota from each other. Changing a limit does not move the reset day to today. Client traffic accounting has a different scope from the provider's whole-server billing.

## Examples

Each example is a complete JSON object; omitted fields use defaults. Replace `YOUR_VPS_IP`, example domains, and upstream credentials with actual values before installation.

### Minimal Direct setup

```json
{
  "SERVER_IP": "YOUR_VPS_IP"
}
```

This uses the default ports, IP-based HTTPS subscriptions, an SSH-only panel, and unlimited traffic.

### Direct + ISP with domain subscriptions and a public HTTPS panel

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
  "PANEL_HTTPS": true,
  "ACME_EMAIL": "you@example.com",
  "TOTAL_MONTHLY_GB": 1000,
  "ISP_MONTHLY_GB": 100
}
```

This allocates 900 GiB to Direct and 100 GiB to ISP. To keep domain subscriptions with an SSH-only panel, set `PANEL_HTTPS` to `false`.

## Applying changes after installation

Editing JSON does not immediately change a running deployment. Each configuration operation reads only its own fields; see the [Operations guide](operations.md) for full commands.

Omitting a field read by an operation usually selects its default rather than retaining the server's previous value; the email exception is noted below. Maintain a complete candidate configuration aligned with the deployment instead of using the minimal installation example to change existing routes.

| Operation | Fields applied from JSON | Notes |
| --- | --- | --- |
| `--configure-domain` | `SUB_DOMAIN`, `PANEL_HTTPS`, `ACME_EMAIL` | Requires a nonempty domain; cannot clear the domain to return to IP-based subscriptions. An empty email preserves the previous email |
| `--configure-nodes` | `NODE_NAME`, `NODE_MODE`, every `ISP_*` field, `TOTAL_MONTHLY_GB` | Includes upstream credentials and quotas; synchronize JSON first to avoid overwriting panel changes with stale values |
| `--configure-traffic` | `TOTAL_MONTHLY_GB`, `ISP_MONTHLY_GB` | Uses the deployed route mode, preserving counters and the original reset day |

All three operations require the JSON `SERVER_IP` to match the saved deployment. `NODE_PORT`, `PANEL_PORT`, `SUB_PORT`, `SUB_BACKEND_PORT`, and `REALITY_HOST` are taken from saved state and are not changed by these operations. Editing those values in JSON alone has no effect.

`--repair-reality-target` is a separate repair operation. It reads saved deployment data and repairs the target to `www.cloudflare.com`, rather than applying a new target from JSON. `--show`, `--traffic-status`, and `--diagnose` also read saved server data and do not need a configuration file.

Initial installation requires a fresh VPS. An interrupted installation of the current version can resume with its saved state; older deployments are not migrated in place. Follow the [Operations guide](operations.md) for deployment, client acceptance, and troubleshooting.
