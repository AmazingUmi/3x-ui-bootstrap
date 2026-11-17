# Operations Guide

English | [简体中文](operations.zh-CN.md) · [Project home](../README.md) · [Configuration](configuration.md) · [Security](security.md)

Use this guide to deploy on a fresh VPS, verify client connectivity, perform routine maintenance, and troubleshoot common issues.

> **Scope**: The installer targets fresh Ubuntu / Debian VPS hosts and does not migrate pre-existing 3x-ui or Nginx installations. If an installation or configuration change is interrupted, keep the existing state directory and re-run the same command to resume safely.

---

## Fresh VPS Deployment

### 1. Prerequisites

- **OS**: Ubuntu 22.04+ or Debian 12+ with `systemd` and Python 3.10+
- **Architecture**: `amd64` (`x86_64`) or `arm64` (`aarch64`)
- **Network**: A static public IPv4 address
- **Access**: Working SSH login and `sudo` privileges

### 2. Prepare and validate `config.json` locally

In your local project directory, copy the example template only if you do not already have a configuration file (so existing credentials or edits are not overwritten):

```bash
test -f config.json || cp config.example.json config.json
chmod 600 config.json
nano config.json
bash ./install-3x-ui.sh --config ./config.json --validate-config
```

With the default settings—`direct` routing, an SSH-tunneled panel, and unlimited traffic—only `SERVER_IP` is required. ISP modes require upstream proxy credentials, and enabling `PANEL_HTTPS=true` requires `SUB_DOMAIN`. See the [Configuration Reference](configuration.md) for all fields and examples.

`--validate-config` checks JSON syntax, types, port conflicts, and mode constraints locally without root privileges or network access.

### 3. Configure DNS and firewalls

If you specify `SUB_DOMAIN`, point its DNS `A` record directly to `SERVER_IP`, disable CDN proxying (grey cloud / DNS-only), and wait for propagation. If `SUB_DOMAIN` is left empty, subscriptions automatically use an HTTPS certificate for your public IPv4 address.

Ensure **both** your cloud provider's security group and the server's host firewall allow the required ports (the installer does not modify firewall or SSH configurations automatically):

| Default TCP port | Purpose | Firewall rule |
| --- | --- | --- |
| SSH port (usually `22`) | Administration and SSH panel tunnel | Keep open |
| `80` | Let's Encrypt HTTP-01 issuance & renewal | Allow publicly |
| `443` | Shared VLESS + REALITY node inbound (`NODE_PORT`) | Allow publicly |
| `38443` | Nginx HTTPS subscription gateway (`SUB_PORT`) | Allow publicly |
| `7777` | Management panel (`PANEL_PORT`) | **Do not expose** by default; allow only if `PANEL_HTTPS=true` |
| `12096` | Internal subscription backend (`SUB_BACKEND_PORT`) | **Never expose** (bound to `127.0.0.1` only) |

If you customize ports in `config.json`, follow the port list printed by `--validate-config`. In `direct+isp` mode, both routes share `NODE_PORT`; there is no separate inbound port for ISP.

### 4. Upload, preflight, and install

On your local machine, upload `install-3x-ui.sh` and `config.json` to the VPS (replace `ubuntu` and `YOUR_VPS_IP` as appropriate):

```bash
scp ./install-3x-ui.sh ./config.json ubuntu@YOUR_VPS_IP:~/
ssh ubuntu@YOUR_VPS_IP
```

Before installing, applying OS security updates and confirming SSH key login is recommended.

Run the live preflight check on the VPS:

```bash
chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
```

`--check` verifies the OS, architecture, port availability, ISP upstream connectivity and exit IP (if enabled), DNS resolution, REALITY target TLS 1.3 / HTTP/2 support, and certificate prerequisites without modifying the system.

Once `--check` passes, run the installation:

```bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
```

`--install` installs system packages and SHA-256 verified upstream releases, obtains the TLS certificate, initializes randomized panel credentials, configures Xray routing and the Nginx subscription gateway (`3x-ui-subscription.service`), and runs local runtime checks.

> **Note**: The distribution's default `nginx.service` is deliberately masked so that `3x-ui-subscription.service` owns the isolated gateway configuration and port `80/TCP` remains free for Certbot's standalone challenge.

### 5. Access the panel and import subscriptions

Upon completion, the installer prints the generated panel username, password, access URL, Mihomo / Shadowrocket subscription URLs, and VLESS links. You can display this output again anytime with:

```bash
sudo bash ~/install-3x-ui.sh --show
```

Results are stored in `/var/lib/3x-ui-bootstrap/result.txt` (readable only by `root`). Treat all subscription URLs, QR codes, and VLESS URIs as private credentials.

#### Opening the management panel

With the recommended default (`PANEL_HTTPS=false`), the panel binds only to `127.0.0.1`. Open a separate local terminal and start an SSH tunnel (replace `7777` if you changed `PANEL_PORT`):

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:17777:127.0.0.1:7777 ubuntu@YOUR_VPS_IP
```

Keep that terminal open and open the full `http://127.0.0.1:17777/<random-base-path>/` URL printed by the installer in your browser. If `PANEL_HTTPS=true`, open the printed `https://...` URL directly.

#### Importing client subscriptions

- Import the **Mihomo** or **Shadowrocket** HTTPS subscription link into your client app (or import the raw VLESS link directly).
- In `direct+isp` mode, two independent profiles/nodes are generated: `<NODE_NAME>-Direct` and `<NODE_NAME>-ISP`. Both connect to the same VPS port with distinct UUIDs and subscription IDs.
- Opening a valid subscription URL in a browser downloads subscription data directly rather than showing a web portal.

---

## Post-Install Verification

On the VPS, confirm that both services are active and listening on the expected addresses:

```bash
sudo systemctl status x-ui 3x-ui-subscription --no-pager
sudo ss -lntp | grep -E ':(38443|12096)\b'
```

With default ports, Nginx should listen on `0.0.0.0:38443` and `x-ui` should listen only on `127.0.0.1:12096`.

Then verify from your client device (disable any local VPN/TUN proxy when testing endpoint isolation directly):

1. **Subscription refresh**: Update the subscription in Mihomo or Shadowrocket and confirm the node list and traffic quota info refresh properly.
2. **Exit IP routing**: Browse through the Direct node (should show your VPS IP) and the ISP node (should show your ISP upstream IP).
3. **Gateway isolation**: Request `https://<SUB_HOST>:38443/`, `/assets/`, and `/sub/assets/` from your computer; all should return `404`, while the full valid subscription URL returns `200`.

---

## Routine Maintenance

Run these commands on the VPS. Note that editing `config.json` does not take effect until you apply it with the corresponding maintenance command.

| Task | Command |
| --- | --- |
| Show credentials, panel URL, and subscriptions | `sudo bash ~/install-3x-ui.sh --show` |
| Check native monthly client traffic usage | `sudo bash ~/install-3x-ui.sh --traffic-status` |
| Diagnose REALITY handshake with a temporary instance | `sudo bash ~/install-3x-ui.sh --diagnose` |
| Apply `SUB_DOMAIN`, `PANEL_HTTPS`, and `ACME_EMAIL` changes | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-domain` |
| Apply `NODE_NAME`, `NODE_MODE`, `ISP_*`, and quota changes | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-nodes` |
| Update monthly quotas while keeping the reset day | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-traffic` |
| Switch Xray-core version (`XRAY_VERSION`) | `sudo bash ~/install-3x-ui.sh --config ~/config.json --switch-core` |
| Repair REALITY target to `www.cloudflare.com` | `sudo bash ~/install-3x-ui.sh --repair-reality-target` |

- `--show`, `--traffic-status`, `--diagnose`, and `--repair-reality-target` read saved server state and do not require `--config`.
- `--configure-traffic` takes no extra CLI argument: edit `TOTAL_MONTHLY_GB` and `ISP_MONTHLY_GB` (in GiB) in your complete `config.json` and run the command. Existing usage counters and the original deployment reset day are preserved.
- `--diagnose` spins up temporary loopback Xray instances on `127.0.0.1` without touching your live nodes or services.
- If you manually edit ISP credentials inside the 3x-ui web panel, update `config.json` to match before running `--configure-nodes`. Keep managed subscription IDs, paths, and ports under script control so they stay synchronized with the Nginx allowlist.

---

## Switching Xray-core Versions

By default, the installer deploys Xray-core `26.10.31`. If older clients experience TLS or REALITY handshake compatibility issues, you can switch to the pinned `26.6.27` release (and switch back at any time).

Set `"XRAY_VERSION": "26.6.27"` (or `"26.10.31"`) in your `config.json` and run:

```bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --switch-core
```

**How `--switch-core` works:**
1. Downloads and SHA-256 verifies **both** the target build and the current build before stopping any service.
2. Briefly stops services, swaps the Xray binary, validates configuration, restarts services, and runs runtime verification.
3. If verification fails, automatically restores the original Xray binary. Client identities, databases, traffic counters, and reset days are never overwritten.

> **Best practice**: After switching cores, test both Wi-Fi and cellular connections, Direct/ISP exits, and subscription updates on your client devices. Avoid upgrading Xray directly from inside the 3x-ui web panel UI, as the managed runtime expects a pinned version.

---

## Inspecting Services and Certificate Renewal

Check service health, open sockets, firewall status, and recent logs:

```bash
sudo systemctl status x-ui 3x-ui-subscription --no-pager
sudo ss -lntp
sudo ufw status verbose
sudo journalctl -u x-ui -n 80 --no-pager
sudo journalctl -u 3x-ui-subscription -n 80 --no-pager
```

> Note: `ufw status: inactive` only means host-level UFW is disabled—always verify your cloud provider's firewall rules as well. Redact credentials, subscription IDs, and private paths before sharing logs.

Check Nginx gateway syntax and Certbot automatic renewal:

```bash
sudo /usr/sbin/nginx -t -c /var/lib/3x-ui-bootstrap/nginx.conf
sudo systemctl status 3x-ui-cert-renew.timer --no-pager
sudo journalctl -u 3x-ui-cert-renew.service -n 80 --no-pager
```

Always pass `-c /var/lib/3x-ui-bootstrap/nginx.conf` when running `nginx -t` manually. When Certbot renews the certificate, the renewal hook validates TLS and Nginx configuration before reloading `3x-ui-subscription.service` (and restarts `x-ui` if `PANEL_HTTPS=true`). Keep `80/TCP` open in your firewalls so scheduled renewals can succeed.

---

## Troubleshooting

### Configuration validation fails
Run `--validate-config` again and check the reported field or line number. Ensure the file is valid UTF-8 JSON without comments, ports are unquoted integers, `PANEL_HTTPS` is an unquoted Boolean (`true`/`false`), and permissions are set to `600` (`chmod 600 config.json`).

### Domain still resolves to a previous IP
Verify your authoritative `A` record and public DNS resolvers, confirm CDN proxying is disabled, and allow time for DNS TTL propagation.

### Panel or subscription URL is unreachable
Verify the scheme (`http://` over SSH tunnel vs `https://`), port, random base path, and subscription ID from `sudo bash ~/install-3x-ui.sh --show`:
- **SSH panel**: Make sure your local `ssh -N -L ...` tunnel terminal is actively running.
- **Public HTTPS panel**: Confirm `PANEL_PORT` (default `7777/TCP`) is open in both cloud and host firewalls.
- **Subscriptions**: Confirm `SUB_PORT` (default `38443/TCP`) is open and check `3x-ui-subscription` logs.

### Subscription root (`/`) or `/assets/` returns 404
This is expected by design. The Nginx gateway intentionally rejects root paths, static assets, unknown IDs, and query parameters (`?html=1`). Test using the complete `/mihomo/<id>` or `/sub/<id>` URL inside your client app.

### Only one route works in `direct+isp` mode
Check each client's remaining quota, enabled status, UUID, and routing rules in the panel. Both routes share one VLESS + REALITY inbound and differentiate traffic using `inboundTag` + client email (`user` -> `direct` or `bootstrap-isp`). ISP UDP traffic is intentionally blocked and upstream outages never fall back to Direct.

### ISP preflight passes, but clients cannot connect
Verify each segment separately: local client → VPS `NODE_PORT`, Xray inbound → `bootstrap-isp` outbound, and VPS → ISP upstream. Test over both Wi-Fi and cellular networks. If you adjusted `bootstrap-isp` manually in the panel, preserve the inbound tag, client email, and user routing rules, then save and apply changes.

### Shadowrocket fails to connect
- Confirm the deployed Xray version (`sudo bash ~/install-3x-ui.sh --show`) and verify UUID, Vision flow (`xtls-rprx-vision`), REALITY public key (`pbk`), SNI, short ID (`sid`), server IP, and port match.
- Newer Xray REALITY releases require `X25519MLKEM768` support during handshake. Keep Shadowrocket updated, inspect the node's effective TLS fingerprint inside Shadowrocket, and leave `minClientVer` empty.
- If you rely on an older client build (such as Shadowrocket `2.2.92`), set `"XRAY_VERSION": "26.6.27"` in `config.json` and run `--switch-core`, then retest across Wi-Fi and cellular networks.
- References: [Xray REALITY documentation](https://docs.sanaei.dev/zh/docs/config/reality/), [Shadowrocket 2.2.93 notes](https://t.me/s/ShadowrocketNews?before=1642).

### Installation or reconfiguration was interrupted
Do **not** delete `/var/lib/3x-ui-bootstrap` or reinstall over it. Inspect `/var/lib/3x-ui-bootstrap/install.log`, fix the underlying network or DNS issue, and re-run the exact same command (`--install`, `--configure-domain`, `--configure-nodes`, `--switch-core`, or `--repair-reality-target`) with the same configuration to resume cleanly.
