# Changelog

English | [简体中文](CHANGELOG.zh-CN.md)

All notable user-facing changes to this project are documented in this file.

## 0.4.0-rc.1 — 2026-11-17 (Pre-release)

### Changed
- Set `PANEL_HTTPS=false` (loopback-only management panel over SSH tunnel) as the explicit default and recommendation across documentation and examples.
- Changed the default public HTTPS subscription port (`SUB_PORT`) from `2096` to `38443` while keeping `SUB_BACKEND_PORT` (`12096`) on loopback and supporting custom ports.
- Updated pinned upstream releases to **3x-ui v3.11.0**, **Xray-core 26.10.31** (default), and **Certbot 5.9.0** with pinned `amd64` / `arm64` SHA-256 digests.

### Added
- Added `XRAY_VERSION` config option and `--switch-core` command to switch between `26.10.31` and `26.6.27` safely. Pre-verifies both archives before stopping services and automatically rolls back on failure without touching the database, client identities, or traffic quotas.
- Added per-IP rate and connection limits (`1 req/s`, burst `20`, `16` active connections) and `logrotate` configuration for the Nginx subscription gateway.
- Added OS, running kernel, reboot-required marker, and basic SSH authentication checks to `--check` output (read-only; never modifies OS or SSH configuration).

---

## 0.3.0 — 2026-11-01

### Added
- Placed Nginx (`3x-ui-subscription.service`) in front of the public HTTPS subscription port, isolating the 3x-ui HTTP subscription backend strictly on `127.0.0.1:12096` (`SUB_BACKEND_PORT`).
- Restricted public subscription endpoints to exact active `/sub/<id>` and `/mihomo/<id>` routes (`GET`/`HEAD` only), returning `404` for static assets, HTML pages, invalid IDs, and query variants while preserving client format and `Subscription-Userinfo` headers.
- Reorganized documentation into the [Operations Guide](docs/operations.md), [Configuration Reference](docs/configuration.md), and [Security Guide](docs/security.md).

---

## 0.2.0 — 2026-10-31

### Added
- Unified Direct and ISP routes onto a single shared VLESS + REALITY inbound (`NODE_PORT`, default `443`) using per-client UUID authentication and `user` routing rules.
- Kept independent subscription IDs, node names (`<NODE_NAME>-Direct` / `<NODE_NAME>-ISP`), and native monthly quotas per route, with ISP UDP blocked and no silent fallback to Direct.
- Added the [MIT License](LICENSE).

---

## 0.1.0 — 2026-10-22

### Added
- Initialized the standalone `3X-UI Bootstrap` project with strict JSON configuration (`--config`), `config.example.json`, and sensitive-file `.gitignore` rules.
- Added offline configuration validation (`--validate-config`, no root or network required).
- Included Direct / ISP / Direct + ISP routing, native monthly traffic quotas anchored to the original deployment day, and automated Let's Encrypt HTTPS certificates.
