# Configuration

English | [简体中文](configuration.zh-CN.md)

Use `--config FILE` to select a JSON file. By default, the installer reads `config.json` beside the script. Configuration is read as data: it is never executed as Shell code, and `BOOTSTRAP_*` environment variables are not accepted as configuration overrides.

Use a UTF-8 JSON object no larger than 64 KiB, with file permissions of `600` or stricter. Unknown fields, duplicate fields, incorrect types, and nonstandard JSON numbers are rejected.

## Required and optional settings at a glance

| Category | Fields to fill in | Condition |
| --- | --- | --- |
| Always required | `SERVER_IP` | Every installation mode; replace it with the VPS static public IPv4 |
| Required for ISP | `ISP_HOST`, `ISP_PORT`, `ISP_USERNAME`, `ISP_PASSWORD` | `NODE_MODE` is `isp` or `direct+isp` |
| Required for a public HTTPS panel | `SUB_DOMAIN` | `PANEL_HTTPS=true`; it may stay empty for an SSH-only panel |
| Required for a finite dual-route budget | `ISP_MONTHLY_GB` | `NODE_MODE="direct+isp"` and `TOTAL_MONTHLY_GB>0`; it must be greater than 0 and less than the total budget |
| All other settings | Defaults are available | Adjust them as described below |

**With the defaults—Direct, an SSH-only panel, and unlimited traffic—only `SERVER_IP` must be filled in.** `NODE_NAME` defaults to `MyNode`; a custom nickname is recommended. `NODE_MODE` defaults to `direct`.

The sections below follow the configuration template's order. JSON does not allow comments, so `config.example.json` and `config.json` separate groups with blank lines without adding extra fields.

## 1. VPS address: always required

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `SERVER_IP` | Required | String, no default | VPS static public IPv4; replace the `YOUR_VPS_IP` placeholder |

## 2. Nickname and route mode: optional

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `NODE_NAME` | Optional; customization recommended | String, `"MyNode"` | A 1–64 character nickname without whitespace, path separators, or control characters |
| `NODE_MODE` | Optional | String, `"direct"` | One of `direct`, `direct+isp`, or `isp` |

`direct` uses only the VPS exit; `isp` uses only the ISP exit; `direct+isp` creates two separate routes.

## 3. ISP upstream credentials: required by mode

All four fields below are required when `NODE_MODE` includes ISP. In `direct` mode, keep the example's empty values; the installer will not connect to an ISP.

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `ISP_HOST` | Required when using ISP | String, `""` | Upstream IP / domain without a scheme, port, or path |
| `ISP_PORT` | Required when using ISP | Integer or `null`; default `null` | Upstream proxy port; use an integer when set |
| `ISP_USERNAME` | Required when using ISP | String, `""` | ISP authentication username |
| `ISP_PASSWORD` | Required when using ISP | String, `""` | ISP authentication password |

## 4. ISP protocol and exit checks: optional

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `ISP_PROTOCOL` | Optional | String, `"socks5"` | `socks5` or `http`, matching the provider's proxy protocol |
| `ISP_EXPECTED_IP` | Optional | String, `""` | The exit public IPv4 supplied by your ISP provider; the actual ISP exit must match this value when set. Leave empty for dynamic or rotating exits |

These fields are used only in modes that include ISP.

Set `ISP_EXPECTED_IP` to the actual ISP exit IP. `ISP_HOST` is the proxy connection endpoint, which may differ from the exit. `SERVER_IP` is the VPS public IP and is the expected exit for Direct. ISP checks always require a different exit from the VPS IP to detect accidental Direct routing.

## 5. Domain and panel access: optional

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `SUB_DOMAIN` | Optional; required for a public HTTPS panel | String, `""` | Your domain without a scheme, port, or path; subscriptions use the VPS public IP when empty |
| `PANEL_HTTPS` | Optional | Boolean, `false` | Manage through an SSH tunnel by default; set to `true` for a domain-based HTTPS panel |
| `ACME_EMAIL` | Optional | String, `""` | Certificate contact email |

Without a domain, keep `SUB_DOMAIN=""` and `PANEL_HTTPS=false`. If a domain is provided, its A record must point directly to `SERVER_IP`. Setting a domain alone does not expose the panel publicly.

## 6. Ports: optional, defaults are ready to use

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `NODE_PORT` | Optional | Integer, `443` | Direct inbound port, used only when the mode includes Direct |
| `ISP_NODE_PORT` | Optional | Integer, `8443` | ISP inbound port, used only when the mode includes ISP |
| `PANEL_PORT` | Optional | Integer, `7777` | Panel port; loopback-only by default. Allow it through the firewalls when enabling the public HTTPS panel |
| `SUB_PORT` | Optional | Integer, `2096` | Public HTTPS subscription port; allow it through the firewalls |

Ports must be integers from 1–65535 and must not conflict with the actual SSH port. Active node ports, the panel port, and the subscription port must be distinct. Reserve `80/TCP` for certificate issuance and renewal. `ISP_PORT` connects the VPS to the upstream proxy; `ISP_NODE_PORT` accepts client connections to the VPS.

## 7. Monthly traffic quotas: optional

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `TOTAL_MONTHLY_GB` | Optional | Number, `0` | Total monthly budget for managed clients, in GiB; `0` means unlimited |
| `ISP_MONTHLY_GB` | Optional; required for a finite dual-route budget | Number, `0` | ISP monthly reservation, in GiB; with a finite dual-route total, it must be greater than 0 and less than the total budget |

Quotas are nonnegative numbers with up to three decimal places. Both default to `0`, leaving traffic unlimited. In `direct` mode, `ISP_MONTHLY_GB` must remain `0`. With a finite dual-route budget, Direct receives the total budget minus the ISP reservation.

## 8. REALITY target: optional, usually keep the default

| Field | Required? | Type / default | Description |
| --- | --- | --- | --- |
| `REALITY_HOST` | Optional | String, `"www.cloudflare.com"` | REALITY target and SNI, without a scheme, port, or path; you do not need to own this domain |

## Direct + ISP example

This snippet shows only the fields to change; merge them into config.json. Replace the example proxy address and credentials:

~~~json
{
  "NODE_NAME": "MyNode",
  "NODE_MODE": "direct+isp",
  "ISP_PROTOCOL": "socks5",
  "ISP_HOST": "proxy.example.com",
  "ISP_PORT": 1080,
  "ISP_USERNAME": "YOUR_ISP_USERNAME",
  "ISP_PASSWORD": "YOUR_ISP_PASSWORD",
  "TOTAL_MONTHLY_GB": 1000,
  "ISP_MONTHLY_GB": 100
}
~~~

This allocates 900 GiB to Direct and 100 GiB to ISP. Native panel client quotas disable a client when its quota is exhausted. Resets follow the original deployment day at midnight in the panel's time zone; shorter months use their last day. Unused quota is not shared between routes. Client traffic accounting is distinct from the provider's whole-server billing.

ISP-only mode creates only the ISP route. If both the total budget and ISP quota are finite, the smaller limit applies. In Direct mode, ISP_MONTHLY_GB must be 0. A finite dual-route total requires an ISP reservation greater than 0 and below the total budget.

The ISP setup uses a single authenticated SOCKS5 / HTTP upstream. TCP forwarding is currently verified, ISP-route UDP is explicitly blocked, and upstream failure does not fall back to Direct. Upstream credentials are not included in client subscriptions.

## Domain HTTPS example

~~~json
{
  "SUB_DOMAIN": "node.example.com",
  "PANEL_HTTPS": true,
  "ACME_EMAIL": "you@example.com"
}
~~~

The A record must point directly to SERVER_IP. The panel and subscriptions share a domain and certificate, with their own ports and paths. If only SUB_DOMAIN is set and PANEL_HTTPS remains false, the domain is used for subscriptions while panel management stays behind the SSH tunnel.

## Passwords and private configuration

Passwords are JSON strings. Escape double quotes and backslashes according to JSON syntax. Single quotes, dollar signs, and backticks need no Shell escaping and are never executed as commands. JSON does not support comments.

Run chmod 600 config.json on both your local machine and the VPS. Do not commit real configurations, installation state, subscription IDs, VLESS links, private keys, or result.txt. Git ignore rules do not protect arbitrary custom filenames; inspect staged files before committing.

## Existing deployments

--show, --traffic-status, --diagnose, and --repair-reality-target use saved server data and do not require a configuration file.

Explicit changes read settings by category: --configure-domain changes the domain, panel HTTPS, and certificate email; --configure-nodes changes the nickname, mode, ISP inbound port, upstream, and quotas; --configure-traffic changes only quotas. All require SERVER_IP to match the current deployment. These operations do not change existing Direct, panel, or subscription ports; assess a migration plan first.

To migrate from the old script, copy its header settings into the new config.json. Use JSON integers for ports, a JSON Boolean for PANEL_HTTPS, and numeric 0 for unlimited quotas. The state directory and installation ownership format are preserved, but this initialization has not been migration-tested on an existing VPS.
