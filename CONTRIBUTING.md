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
- Keep Xray pinned to 26.6.27. Upgrades require actual acceptance results from both clients.
- Preserve ownership checks, resumable installation, existing client identities, traffic counters, and the original deployment day. Do not blindly overwrite manual panel changes.
- ISP failure must not automatically fall back to Direct. Explain native client quotas separately from whole-server traffic billing.
- Commit only example data. Check staged configurations, logs, accounts, subscriptions, and keys for private information.

Documentation defaults to English, with Simplified Chinese copies named *.zh-CN.md. Keep both languages in sync, including field requirements, default values, commands, and verification limits.

## Release preparation

Before a formal release, the project owner must select a license and complete VPS acceptance testing for the new configuration entry point. Passing local checks does not establish successful deployment or client connectivity.
