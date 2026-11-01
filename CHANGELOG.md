# Changelog

English | [简体中文](CHANGELOG.zh-CN.md)

Dates refer to publication on the repository's `main` branch.

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
