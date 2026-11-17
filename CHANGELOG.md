# Changelog

English | [简体中文](CHANGELOG.zh-CN.md)

Dates refer to publication on the repository's `main` branch.

## 0.4.0-rc.1 — 2026-11-17 (test candidate)

- Default to and recommend the loopback-only panel through an SSH key tunnel; examples no longer recommend exposing the panel.
- Change the default public HTTPS subscription port from 2096 to 38443, retaining custom ports and loopback backend 12096.
- Update and verify official 3x-ui 3.11.0, Xray 26.10.31, and Certbot 5.9.0 packages with pinned amd64 / arm64 digests.
- Add `XRAY_VERSION` and `--switch-core` for the new core and historical 26.6.27 comparison. Cache both builds before stopping; roll back on server-check failure without restoring the database or resetting identity or quotas.
- Add subscription request/connection limits and Nginx error-log rotation. Report the running kernel, reboot marker, and basic SSH authentication settings without modifying the OS or SSH.
- Separate subscription-format checks and local Xray tests from real Shadowrocket / Mihomo acceptance.

Validation: **85 offline checks** passed on macOS (Python 3.13) and Ubuntu 24.04 (Python 3.12). Official new and historical artifacts were SHA-256 verified. Isolated amd64 and arm64 containers passed real panel CLI/API, native quotas, both HTTPS subscription formats, bidirectional core switching, and injected-failure rollback checks. These local and container checks do not cover systemd boot, real ACME issuance/renewal, public or ISP forwarding, or phone-client acceptance.

Status: On 2026-11-17, the user confirmed this candidate deployment was usable. The selected core, client versions, and itemized acceptance results were not recorded. Retain candidate status; not a formal release. Fresh installations only; no migration of older deployments.

## 0.3.0 — 2026-11-01

- Put Nginx in front of the public HTTPS subscription port (default 2096), with the 3x-ui HTTP subscription backend bound only to `127.0.0.1` on `SUB_BACKEND_PORT` (default 12096).
- Allow only the managed clients' exact subscription download URLs using GET or HEAD. Reject static assets, directory listings, invalid IDs, and other public paths; do not expose the browser subscription page.
- Preserve Mihomo / Shadowrocket subscription downloads and usage headers. Install Nginx automatically and keep certificate renewal, managed configuration changes, and runtime checks consistent with the new listener layout.
- Support fresh VPS deployments and interrupted-install retries for this version; do not migrate older deployments in place.
- Organize user documentation into the [operations guide](docs/operations.md), [security notes](docs/security.md), and [configuration reference](docs/configuration.md). Merge troubleshooting into operations and simplify README into the project overview and document index.
- Add real local Nginx access-control tests and service lifecycle checks. Document upstream security advisories, their applicability, and the limits of public-exposure testing.

Validation: all **74 local checks passed**, and [GitHub CI](https://github.com/AmazingUmi/3x-ui-bootstrap/actions/runs/41286644868) passed on **Python 3.10 and 3.13**. The fresh VPS deployment was reported working on 2026-11-01; external IPv4 checks confirmed static-resource denial, that the subscription backend could not be reached from the test network, and the intended TLS versions. Client versions were not recorded. See the security notes for the tested scope; these results do not establish the absence of vulnerabilities or IP reputation labels.

## 0.2.0 — 2026-10-31

- Share one VLESS + REALITY inbound (default 443) between Direct and ISP, authenticating independent client UUIDs and selecting exits with `user` routing rules.
- Retain independent subscription IDs, node names, and native monthly quotas. Clients share the inbound's REALITY key pair; ISP UDP stays blocked and ISP failure does not fall back to Direct.
- Use one `NODE_PORT` in every mode and update firewall instructions.
- Keep Xray pinned to 26.6.27. At this stage, the shared-inbound topology awaited real VPS / Shadowrocket / Mihomo acceptance; later deployment feedback is recorded under 0.3.0.
- Record the historically verified Shadowrocket 2.2.92 (3345) + Xray 26.6.27 combination and mark other Shadowrocket / Xray combinations as unverified.
- Add the MIT License and update licensing information in both languages.

## 0.1.0 — 2026-10-22

- Initialize a standalone project from the existing 3X-UI deployment script.
- Move user settings into a JSON file selected with --config; add a public example and ignore rules for sensitive files.
- Add --validate-config without root or network requirements, with strict field and type validation.
- Preserve 3x-ui v3.10.2, Xray 26.6.27, Direct / ISP routing, native quotas, and monthly resets tied to the original deployment day.
- Add configuration, usage, and troubleshooting documentation, plus offline tests / CI.

At the time of the 0.1.0 entry, this configuration-entry refactor had not been deployed on a real VPS. Later deployment feedback is recorded under 0.3.0.
