# Contributing

English | [简体中文](CONTRIBUTING.zh-CN.md)

## Local checks

You need Bash, Python 3.10+, and Git. From the repository root, run:

~~~bash
bash scripts/check.sh
~~~

Checks do not request certificates, install software, connect to real ISP proxies, or change system services. Changes to release packages, panel APIs, certificates, routing, or client compatibility need additional VPS / Shadowrocket / Mihomo acceptance results.

## Isolated release checks

`scripts/check-release.py` runs real upstream binaries only in a disposable root Docker container with `--network none`; it refuses host execution or a container with a non-loopback interface. It covers initial CLI/DB/API setup, the shared inbound and native quotas, HTTPS subscription exports, new/old core switching, and an injected acceptance failure with rollback. The injected acceptance failure must restore the original binary and working subscriptions. It does not exercise systemd boot, real ACME issuance/renewal, public forwarding, ISP exits, or phone apps.

Prepare a public-only copy of `install-3x-ui.sh`, `config.example.json`, `scripts/`, and `tests/`, plus an asset directory containing the official panel archive for the tested architecture, both pinned Xray archives, and the Certbot wheel. Keep original current-release filenames; prefix the historical Xray filename with `old-`. The runner validates all archive digests before execution. Build `scripts/release-check.Dockerfile` using the asset directory as build context to cache Certbot dependencies. For each of `linux/arm64` and `linux/amd64`, run that image with `--rm --network none`, no published ports, read-only mounts of the public source at `/src` and assets at `/assets`, and command `python3 /src/scripts/check-release.py --assets /assets`. Never mount private `config.json`, the host Docker socket, or host service/database directories into the test container.

## Change guidelines

- The installation entry point is install-3x-ui.sh. User settings come only from a separate JSON file. Preserve deployment by uploading just the script and configuration.
- Do not add legacy configuration aliases or source Shell configuration files. Update the example, documentation, and boundary tests when adding a field.
- This candidate defaults to Xray 26.10.31 and allows explicit selection of checksum-pinned 26.6.27 for comparison. Preserve digest and version checks; do not accept arbitrary download URLs or automatically follow latest. The historical Shadowrocket 2.2.92 (3345) + Xray 26.6.27 result does not transfer to this candidate. Record actual Shadowrocket and Mihomo acceptance before a formal release.
- Preserve ownership checks, resumable installation, existing client identities, traffic counters, and the original deployment day. Do not blindly overwrite manual panel changes.
- ISP failure must not automatically fall back to Direct. Explain native client quotas separately from whole-server traffic billing.
- Shared-inbound routing must match the authenticated client email. Cover two clients on one port, independent subscriptions and quotas, blocked ISP UDP, and blocked unmatched clients. Historical version-pair evidence does not replace real-client acceptance of a new topology.
- Commit only example data. Check staged configurations, logs, accounts, subscriptions, and keys for private information.

User documentation has three topics: [operations](docs/operations.md), [security](docs/security.md), and [configuration](docs/configuration.md). Put troubleshooting in the operations guide and keep README focused on the project overview and document links. Topic documents have English versions and Simplified Chinese copies named `*.zh-CN.md`; the project home page is in Simplified Chinese. Keep commands, defaults, constraints, and verification records aligned across languages.

## Release preparation

This project uses the [MIT License](LICENSE). Before a formal release, record VPS and client acceptance for the release being published. See the operations guide for the 2026-11-01 deployment feedback and its version limits. Passing local checks alone does not establish successful deployment or client connectivity.
