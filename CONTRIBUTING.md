# Contributing

English | [简体中文](CONTRIBUTING.zh-CN.md)

Thank you for your interest in contributing to **3X-UI Bootstrap**.

## Local Tests

Prerequisites: **Bash**, **Python 3.10+**, and **Git** (plus local `nginx` and `openssl` to run the live Nginx gateway test suite).

From the repository root, run:

```bash
bash scripts/check.sh
```

Offline tests cover shell/Python syntax, JSON schema validation, configuration boundaries, routing rules, native client quotas, core-switching rollback logic, and local Nginx gateway access control. They do not request ACME certificates, modify host services, or connect to live ISP proxies.

## Containerized Release Smoke Test

`scripts/check-release.py` exercises the real upstream `x-ui`, `xray`, and `certbot` binaries inside an isolated, disposable root container with `--network none`. It validates CLI/DB initialization, shared-inbound routing, native quotas, HTTPS subscription downloads, bidirectional core switching, and automatic rollback on failure.

To run it locally for `linux/amd64` or `linux/arm64`:

1. Create a clean copy containing only public files (`install-3x-ui.sh`, `config.example.json`, `scripts/`, `tests/`). Never mount private `config.json` files, the host Docker socket, or host state directories.
2. Prepare an assets directory containing the official `x-ui` release archive, the current and `26.6.27` `Xray-core` archives (prefix the `26.6.27` filename with `old-`), and the `Certbot` wheel (checksums are verified before execution).
3. Build `scripts/release-check.Dockerfile` with the assets directory as the build context to cache Certbot dependencies.
4. Run the container with `--rm --network none` (no published ports), mounting the public source read-only at `/src` and assets read-only at `/assets`:

```bash
python3 /src/scripts/check-release.py --assets /assets
```

## Design & Security Invariants

Please keep these core contracts intact in all pull requests:

- **Single-script + JSON boundary**: `install-3x-ui.sh` is the sole entry point and reads user settings strictly as JSON data (never sourced shell code or legacy config aliases). Whenever you add or change a configuration field, update `config.example.json`, documentation, and boundary tests together.
- **Pinned, verified releases**: Upstream archives must remain pinned to explicit versions with SHA-256 checksum verification—never accept arbitrary download URLs or track `latest`.
- **Safe resumability & state ownership**: Preserve ownership validation, resumable failure handling, existing client UUIDs/subscription IDs, traffic counters, and original deployment reset days. Never overwrite manual panel changes silently.
- **Strict route isolation**: ISP upstream failure must never fall back to Direct. Shared-inbound routing must match authenticated client emails (`user`), block ISP UDP, and deny unmatched clients.
- **Zero secrets in Git**: Commit only placeholder/example data. Always review staged files for private IPs, credentials, keys, or logs before pushing.

## Documentation Conventions

All documentation is maintained in both English (`*.md`) and Simplified Chinese (`*.zh-CN.md`), covering `README*`, `CHANGELOG*`, `CONTRIBUTING*`, and `docs/{operations,configuration,security}*`. Keep commands, defaults, field constraints, and behavior aligned across both languages, with troubleshooting grouped under the Operations Guide.

## Release Checklist

Before tagging a formal release (licensed under [MIT](LICENSE)):

1. Confirm `bash scripts/check.sh` passes on supported Python versions.
2. Run `scripts/check-release.py` across `amd64` and `arm64` containers.
3. Verify fresh VPS installation, ACME issuance/renewal, Direct/ISP routing, and real client connectivity (Mihomo and Shadowrocket).
