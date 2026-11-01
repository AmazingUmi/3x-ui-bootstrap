# Contributing

English | [简体中文](CONTRIBUTING.zh-CN.md)

## Local checks

You need Bash, Python 3.10+, and Git. From the repository root, run:

~~~bash
bash scripts/check.sh
~~~

Checks do not request certificates, install software, connect to real ISP proxies, or change system services. Changes to release packages, panel APIs, certificates, routing, or client compatibility need additional VPS / Shadowrocket / Mihomo acceptance results.

## Change guidelines

- The installation entry point is install-3x-ui.sh. User settings come only from a separate JSON file. Preserve deployment by uploading just the script and configuration.
- Do not add legacy configuration aliases or source Shell configuration files. Update the example, documentation, and boundary tests when adding a field.
- Keep Xray pinned to 26.6.27. The historically verified Shadowrocket pair is 2.2.92 (3345) with Xray 26.6.27; other Shadowrocket / Xray combinations are unverified. Upgrades require actual acceptance results from both Shadowrocket and Mihomo.
- Preserve ownership checks, resumable installation, existing client identities, traffic counters, and the original deployment day. Do not blindly overwrite manual panel changes.
- ISP failure must not automatically fall back to Direct. Explain native client quotas separately from whole-server traffic billing.
- Shared-inbound routing must match the authenticated client email. Cover two clients on one port, independent subscriptions and quotas, blocked ISP UDP, and blocked unmatched clients. Historical version-pair evidence does not replace real-client acceptance of a new topology.
- Commit only example data. Check staged configurations, logs, accounts, subscriptions, and keys for private information.

User documentation has three topics: [operations](docs/operations.md), [security](docs/security.md), and [configuration](docs/configuration.md). Put troubleshooting in the operations guide and keep README focused on the project overview and document links. Topic documents have English versions and Simplified Chinese copies named `*.zh-CN.md`; the project home page is in Simplified Chinese. Keep commands, defaults, constraints, and verification records aligned across languages.

## Release preparation

This project uses the [MIT License](LICENSE). Before a formal release, record VPS and client acceptance for the release being published. See the operations guide for the 2026-11-01 deployment feedback and its version limits. Passing local checks alone does not establish successful deployment or client connectivity.
