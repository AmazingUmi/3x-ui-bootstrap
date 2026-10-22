# Changelog

English | [简体中文](CHANGELOG.zh-CN.md)

## 0.1.0 — 2026-10-22

- Initialize a standalone project from the existing 3X-UI deployment script.
- Move user settings into a JSON file selected with --config; add a public example and ignore rules for sensitive files.
- Add --validate-config without root or network requirements, with strict field and type validation.
- Preserve 3x-ui v3.10.2, Xray 26.6.27, Direct / ISP routing, native quotas, and monthly resets tied to the original deployment day.
- Add configuration, usage, and troubleshooting documentation, plus offline tests / CI.

This configuration-entry refactor has not yet been deployed on a real VPS. Historical deployment results are not new acceptance evidence for this version.
