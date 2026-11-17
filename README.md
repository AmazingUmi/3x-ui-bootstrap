# 3X-UI Bootstrap

English | [简体中文](README.zh-CN.md)

A declarative, single-script deployment tool for setting up **VLESS + REALITY** nodes, an isolated **HTTPS subscription gateway**, and a hardened **3x-ui** panel on fresh Ubuntu / Debian VPS instances.

Fill out a single `config.json`, upload it alongside `install-3x-ui.sh`, and get a production-ready deployment with automated TLS certificates, client traffic quotas, and safe in-place maintenance commands.

## Features

- **Flexible Routing Modes (`direct`, `isp`, `direct+isp`)**: Route traffic directly through your VPS, through a SOCKS5 / HTTP upstream proxy, or run both routes on the same `443/TCP` port with separate client identities, subscription links, and traffic limits. If an ISP upstream goes down, traffic never falls back silently to Direct.
- **Hardened by Default**: The 3x-ui management panel binds only to `127.0.0.1` (`PANEL_HTTPS=false`) and is accessed over an SSH tunnel, eliminating public panel exposure. Public HTTPS panel access is opt-in with a custom domain.
- **Isolated Subscription Gateway**: Nginx terminates public HTTPS (`38443/TCP` by default) and forwards only exact, active `/sub/<id>` and `/mihomo/<id>` download URLs to the loopback backend (`127.0.0.1:12096`). Static assets, unknown IDs, query variants, and the HTML web page return `404`.
- **Automated HTTPS Certificates**: Automatically issues and renews Let's Encrypt certificates via Certbot for either your domain (`SUB_DOMAIN`) or a public IPv4 address (short-lived IP certificates).
- **Native Monthly Traffic Quotas**: Uses 3x-ui's native client metering with monthly resets anchored to the original deployment day. In `direct+isp` mode, ISP gets its reserved quota and Direct receives the remainder.
- **Safe, Resumable Operations**: Verifies SHA-256 digests of pinned upstream releases, supports offline config validation (`--validate-config`) and live VPS preflight (`--check`), resumes interrupted installs cleanly, and supports controlled Xray-core switching (`--switch-core`) with automatic rollback.

## Architecture

```text
Clients ── 443/TCP ────────── Xray (VLESS + REALITY) ── Direct / ISP Exit
Clients ── 38443/TCP HTTPS ── Nginx Gateway ── 127.0.0.1:12096 HTTP ── Subscription Backend
Admin   ── SSH Tunnel ─────── 127.0.0.1:7777 ────────────────────────── Management Panel (default)
```

> **Note**: By default, only the node port (`443/TCP`), subscription gateway (`38443/TCP`), and ACME validation port (`80/TCP`) need to be reachable from the internet. Never expose `12096/TCP` publicly.

## Quick Start

**Requirements**: A fresh **Ubuntu 22.04+** or **Debian 12+** VPS (`amd64` or `arm64`) with systemd, Python 3.10+, a static public IPv4 address, and `sudo` access.

### 1. Create and validate `config.json` locally

```bash
cp config.example.json config.json
chmod 600 config.json
# Edit config.json (only SERVER_IP is required for minimal Direct mode)
bash ./install-3x-ui.sh --config ./config.json --validate-config
```

### 2. Upload and run preflight on the VPS

Ensure your firewall allows `80/TCP`, `443/TCP`, and `38443/TCP` (plus your SSH port). If using `SUB_DOMAIN`, point its DNS `A` record directly to `SERVER_IP` with CDN proxying disabled.

```bash
scp ./install-3x-ui.sh ./config.json ubuntu@YOUR_VPS_IP:~/
ssh ubuntu@YOUR_VPS_IP

chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
```

### 3. Install

```bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
```

When installation completes, the terminal prints your randomized panel credentials, SSH tunnel command, Mihomo / Shadowrocket subscription URLs, and VLESS links (also saved to `/var/lib/3x-ui-bootstrap/result.txt`).

## Documentation

| Guide | Description | 简体中文 |
| --- | --- | --- |
| [Operations Guide](docs/operations.md) | Step-by-step installation, client setup, maintenance commands, and troubleshooting | [操作指南](docs/operations.zh-CN.md) |
| [Configuration Reference](docs/configuration.md) | All 20 configuration fields, defaults, constraints, and examples | [参数配置](docs/configuration.zh-CN.md) |
| [Security Guide](docs/security.md) | Network isolation, gateway access control, credential handling, and self-checks | [安全说明](docs/security.zh-CN.md) |
| [Changelog](CHANGELOG.md) | Release history and user-facing changes | [更新日志](CHANGELOG.zh-CN.md) |
| [Contributing](CONTRIBUTING.md) | Development tests, containerized smoke checks, and contribution guidelines | [贡献指南](CONTRIBUTING.zh-CN.md) |

## Pinned Upstream Versions

Current release: **0.4.0-rc.1** (pre-release)

| Component | Version | Notes |
| --- | --- | --- |
| [3x-ui](https://github.com/MHSanaei/3x-ui) | `v3.11.0` | SHA-256 verified official release |
| [Xray-core](https://github.com/XTLS/Xray-core) | `26.10.31` | Default; `26.6.27` available via `XRAY_VERSION` for older client compatibility |
| [Certbot](https://github.com/certbot/certbot) | `5.9.0` | SHA-256 verified wheel in isolated venv |
| [Nginx](https://nginx.org/) | System package | Installed via Ubuntu / Debian APT |

## License

This project is licensed under the [MIT License](LICENSE). Third-party upstream software remains subject to its own licenses; this repository does not bundle third-party binaries.
