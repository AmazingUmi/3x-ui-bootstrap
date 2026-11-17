# Security Guide

English | [简体中文](security.zh-CN.md) · [Project home](../README.md) · [Operations](operations.md) · [Configuration](configuration.md)

3X-UI Bootstrap hardens a standard 3x-ui deployment by isolating the subscription backend, restricting public subscription routes, randomizing administrative credentials before first launch, and keeping the management panel off the public internet by default.

> **Important**: Security hardening minimizes unnecessary public attack surface, but no proxy setup can prevent full-port scanning or guarantee immunity from network-level heuristics or IP reputation databases.

---

## 1. Service Boundaries & Network Isolation

The default subscription flow routes all public HTTPS requests through Nginx before reaching the loopback-only 3x-ui subscription service:

```text
Clients ──► Public 38443/TCP (HTTPS / Nginx)
                     │
                     ▼ (127.0.0.1 HTTP)
              127.0.0.1:12096 (3x-ui subscription backend)
```

| Endpoint | Default binding & behavior | Security boundary |
| --- | --- | --- |
| Node (`443/TCP`) | Xray VLESS + REALITY; routes by authenticated client identity | Independent of subscription port; node uptime does not imply subscription availability |
| Subscription (`38443/TCP`) | Nginx terminates TLS 1.2/1.3 and forwards only valid subscription URLs | Allow publicly; handles subscription downloads and quota refreshes |
| Backend (`12096/TCP`) | 3x-ui HTTP subscription service bound strictly to `127.0.0.1` | **Never expose** in cloud or host firewalls |
| Panel (`7777/TCP`, default) | Bound to `127.0.0.1` (`PANEL_HTTPS=false`), accessed via SSH tunnel | Default and recommended; eliminates public panel exposure and IP allowlist maintenance |
| Panel (`7777/TCP`, optional) | Bound to `0.0.0.0` with HTTPS (`PANEL_HTTPS=true`, requires `SUB_DOMAIN`) | Opt-in only; protected by a random URL path and generated credentials |
| ACME (`80/TCP`) | Temporary standalone Certbot listener during issuance/renewal | Keep reachable in firewalls; no persistent listener runs between renewals |

> **IPv6 check**: If your VPS has a public IPv6 address, audit its IPv6 firewall and listeners (`ss -lntup`) separately from IPv4.

---

## 2. Subscription Gateway Access Control

`3x-ui-subscription.service` runs an isolated Nginx configuration (`/var/lib/3x-ui-bootstrap/nginx.conf`) with strict allowlisting:

- **Exact route allowlist**: Only active clients' exact `/sub/<id>` and `/mihomo/<id>` paths are forwarded. Checks evaluate the un-normalized `$request_uri`, `Host` header, and HTTP method.
- **Blocked surface**: Only `GET` and `HEAD` are permitted. Root requests (`/`), `/assets/`, directory listings, invalid IDs, encoded path variants, query strings (such as `?html=1`), and the 3x-ui HTML subscription page all return `404` without touching the backend.
- **Header sanitization**: Only `User-Agent` is passed upstream (with fixed `Host` and `Accept: */*`). Client `Cookie`, `Authorization`, and `X-Forwarded-For` headers are stripped, and `Profile-Web-Page-Url` is hidden on responses while keeping `Subscription-Userinfo` and `Profile-Update-Interval` intact.
- **Rate limiting & log rotation**: Valid subscription downloads are rate-limited per source IP to `1 req/s` (burst `20`, max `16` active connections), returning `429` above threshold. Access logging is disabled; error logs rotate daily or above `10 MiB` (retaining 7 files with mode `0600`).

> **Treat subscription URLs as credentials**: Anyone possessing a complete `/sub/<id>` or `/mihomo/<id>` URL can fetch that node configuration and usage summary. Keep subscription links, VLESS URIs, QR codes, and installation screenshots private.

Keep subscription IDs, paths, and ports managed through `install-3x-ui.sh` commands rather than manual panel edits so the Nginx allowlist stays synchronized.

---

## 3. Credentials, File Permissions & Certificates

- **Pre-start hardening**: Before `x-ui` ever starts, the installer writes a randomized administrator username, strong password, and random URL base path directly to the database. It never exposes a panel running with default `admin/admin` credentials.
- **Strict file permissions**:
  - Private `config.json` files must be mode `600` or stricter (`chmod 600 config.json`) on both your workstation and the VPS.
  - `/var/lib/3x-ui-bootstrap` is owned by `root` with mode `700`. It stores state, backups, credentials (`result.txt`), and the Nginx config—keep its contents private and redact sensitive tokens or paths before sharing logs or `nginx -T` output.
- **Repository hygiene**: `.gitignore` excludes common local files (`config.json`, `result.txt`, `*.log`, `*.pem`, `*.key`), though you should always review `git status` and staged diffs before committing.
- **TLS & certificate checks**: The Nginx gateway enforces TLS 1.2 / 1.3 only. Before startup and certificate reload, pre-flight guards validate hostname/IP SAN matching, expiration, certificate chain integrity, and key pairing.

---

## 4. Pinned Upstream Releases & Shared Responsibilities

The installer verifies SHA-256 checksums for all pinned upstream packages before execution:

- **3x-ui (`v3.11.0`)**: Incorporates upstream security patches for historical panel and subscription advisories.
- **Xray-core (`26.10.31` default)**: Disables MPTCP by default to minimize protocol exposure. (`26.6.27` is provided strictly as a legacy compatibility option via `--switch-core`.)
- **Certbot (`5.9.0`)**: Pinned wheel installed in an isolated Python virtual environment.
- **Nginx**: Installed from your distribution's official APT repository.

### What remains your responsibility

1. **OS & kernel patching**: Updating Xray or 3x-ui does not patch Linux kernel or system package vulnerabilities. Regularly run `apt update && apt upgrade` and reboot when `/run/reboot-required` is present.
2. **SSH & firewall hardening**: The installer never edits SSH daemon settings or firewall rules. Verify SSH key authentication works before disabling password logins, and configure both cloud security groups and host firewalls (`ufw` / `nftables`).
3. **Network visibility**: `server_tokens off` hides the Nginx version string, and blocking static assets prevents casual 3x-ui fingerprinting, but open ports, TLS certificate domains/IPs, and datacenter ASN reputation (such as [MaxMind anonymizer classification](https://support.maxmind.com/knowledge-base/articles/anonymizer-and-proxy-data-maxmind)) remain observable on the public internet.

---

## 5. Self-Verification Checklist

After fresh deployment, domain updates, or route changes, verify your server's external exposure from a separate computer (temporarily disable any local VPN/TUN client so requests hit the internet directly):

1. **Gateway path isolation**:
   - `curl -I https://<SUB_HOST>:38443/` → expect `404`
   - `curl -I https://<SUB_HOST>:38443/assets/` → expect `404`
   - `curl -I https://<SUB_HOST>:38443/sub/invalid-id` → expect `404`
   - `curl -I "https://<SUB_HOST>:38443/sub/<VALID_ID>?html=1"` → expect `404`
2. **Backend & private panel isolation**:
   - Attempt a TCP/HTTP connection to `<SERVER_IP>:12096` → should time out or be refused.
   - If `PANEL_HTTPS=false`, attempt a connection to `<SERVER_IP>:7777` → should time out or be refused.
3. **TLS verification**:
   - Confirm `https://<SUB_HOST>:38443` presents a valid, non-expired certificate matching `SUB_DOMAIN` (or `SERVER_IP`) and negotiates TLS 1.2 / 1.3 only.
4. **REALITY masquerade check**:
   - An unauthenticated HTTPS request to `<SERVER_IP>:443` (with `Host: <REALITY_HOST>`) should reflect the camouflage target without leaking Xray or 3x-ui identifiers.
