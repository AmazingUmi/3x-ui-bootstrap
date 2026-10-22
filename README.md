# 3X-UI Bootstrap

English | [简体中文](README.zh-CN.md)

A one-command 3X-UI deployment tool for Ubuntu / Debian. Fill in a separate JSON configuration file, upload it with the installer, and deploy VLESS + REALITY nodes.

Choose Direct, ISP, or Direct + ISP mode. A domain is optional, and panel management uses an SSH tunnel by default. After installation, the tool prints the panel username, password, full URL, Mihomo subscriptions, Shadowrocket subscriptions, and VLESS links.

## Features

- Direct uses the VPS public exit; ISP uses a specified SOCKS5 / HTTP upstream, with authentication, HTTPS forwarding, and exit-IP checks before deployment.
- Each route has a separate client, UUID, REALITY key pair, and subscription ID.
- Automatically obtain and renew trusted HTTPS certificates for a public IP or domain; optionally expose the panel over domain-based HTTPS.
- Use native panel client quotas with a monthly reset tied to the original deployment date. In dual-route mode, Direct receives the total budget minus the ISP reservation.
- Verify official release checksums, then test the deployed inbound's REALITY / VLESS / Vision authentication, HTTPS forwarding, and exit IP.

Pinned versions: 3x-ui **v3.10.2**, Xray-core **26.6.27**, and Certbot **5.8.0**. Xray is pinned to preserve verified Shadowrocket compatibility. Retest both Shadowrocket and Mihomo before upgrading.

## Verified Shadowrocket compatibility

| Shadowrocket | Xray-core | Verification record |
| --- | --- | --- |
| **2.2.92 (3345)** | **26.6.27** | Earlier user-confirmed subscription import, web browsing, and expected exit-IP checks |

This records feedback from earlier deployments. **Other Shadowrocket / Xray version combinations have not been verified by this project.** Retest before changing either version; keep the pinned core until a replacement combination has passed acceptance testing.

## 1. Prepare the VPS

Use a fresh Ubuntu 22.04+ / Debian 12+ VPS with a static public IPv4, systemd, Python 3.10+, and an amd64 or arm64 CPU.

Have SSH access and sudo privileges ready. The installer only manages deployments it created; it stops if it finds an existing, unrelated 3X-UI installation.

Before deployment, confirm **the configuration is correct, domain DNS has propagated if used, and the required ports are open**.

## 2. Configure

Run these commands in your local project directory:

~~~bash
cp config.example.json config.json
chmod 600 config.json
nano config.json
~~~

The example groups settings in this order: VPS, route mode, ISP credentials, ISP options, domain, ports, quotas, and REALITY target.

| Category | What to fill in |
| --- | --- |
| Always required | `SERVER_IP`: the VPS static public IPv4 |
| Required by mode | Set `ISP_HOST`, `ISP_PORT`, `ISP_USERNAME`, and `ISP_PASSWORD` when the mode includes ISP |
| Required by option | Set `SUB_DOMAIN` when `PANEL_HTTPS=true`; set `ISP_MONTHLY_GB` when dual-route mode has a finite total budget |
| Optional | Adjust the nickname, mode, ports, ISP protocol and expected exit, domain, email, quotas, and REALITY target as needed |

**With the defaults—Direct, an SSH-only panel, and unlimited traffic—only `SERVER_IP` must be filled in.** `NODE_NAME` defaults to `MyNode`; give it your own nickname if desired. `NODE_MODE` defaults to `direct`.

The file uses JSON: ports and quotas are numbers, `PANEL_HTTPS` is `true` / `false`, and an unset `ISP_PORT` is `null`.

Validate locally without sudo or network access:

~~~bash
bash ./install-3x-ui.sh --config ./config.json --validate-config
~~~

See [Configuration](docs/configuration.md) for all fields and dual-route / domain examples. The private config.json is ignored by Git; commit only the example.

## 3. Configure DNS and open ports

Leave SUB_DOMAIN empty to use the VPS public IP with a trusted HTTPS certificate for subscriptions. Panel management then uses an SSH tunnel.

If using a domain, point its A record directly to SERVER_IP, disable CDN proxying for that record, and wait for public DNS resolvers to agree. With PANEL_HTTPS set to true, the panel and subscriptions share the domain and certificate.

These are the default ports. **Check both the cloud firewall and the server firewall.** The installer prints the required rules; it does not change firewall or SSH settings.

| TCP port | Purpose | When to allow it |
| --- | --- | --- |
| Actual SSH port, commonly 22 | Login, uploads, and SSH tunnels | Keep access available |
| 80 | Certificate issuance and automatic renewal | Always required |
| 443 | Direct node | When the mode includes Direct |
| 8443 | ISP node | When the mode includes ISP |
| 2096 | Public HTTPS subscriptions | Always required |
| 7777 | Public HTTPS panel | Only when PANEL_HTTPS=true; preferably restrict it to your management IP |

If you change ports, use the list printed by configuration validation. The default SSH-only panel does not require public access to 7777.

## 4. Upload, log in, and install

Run locally, replacing YOUR_VPS_IP and ubuntu with your server details. These commands use your existing SSH configuration or keys loaded in the SSH agent:

~~~bash
scp ./install-3x-ui.sh ./config.json ubuntu@YOUR_VPS_IP:~/
ssh ubuntu@YOUR_VPS_IP
~~~

After logging in to the VPS:

~~~bash
chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
~~~

--check uses the network to validate the candidate configuration, ISP, DNS, and installation prerequisites. It does not install software or modify services. If installation fails, keep the saved state, fix the cause, and retry with the same configuration.

## 5. Open the panel and import subscriptions

On success, the terminal prints full panel and subscription URLs. Results are also saved on the VPS at /var/lib/3x-ui-bootstrap/result.txt, readable only by root.

For the default SSH-only panel, open a separate tunnel from your local machine. This example uses the default panel port, 7777:

~~~bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:17777:127.0.0.1:7777 ubuntu@YOUR_VPS_IP
~~~

Keep that terminal running, then open the full URL from the installer output: http://127.0.0.1:17777/ followed by its random base path. For the domain-based HTTPS panel, use the printed HTTPS URL directly.

Import the subscription for the desired route into Mihomo / Shadowrocket, then verify browsing and the actual exit IP. Server-side loopback checks must be followed by real client testing over the public network.

## Maintenance commands

Run these on the VPS. Operations that use a configuration file default to config.json beside the installer; use --config to select another file.

| Operation | Command | Configuration source |
| --- | --- | --- |
| Show credentials and links | sudo bash ~/install-3x-ui.sh --show | Saved server results |
| Show native monthly traffic | sudo bash ~/install-3x-ui.sh --traffic-status | Saved deployment |
| Run temporary REALITY diagnostics | sudo bash ~/install-3x-ui.sh --diagnose | Saved deployment |
| Change the domain and panel HTTPS | sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-domain | Domain, HTTPS, and email settings in the file |
| Change the nickname, mode, and ISP | sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-nodes | Route, ISP, and quota settings in the file |
| Change monthly quotas | sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-traffic | Total budget and ISP reservation in the file |
| Repair the REALITY target | sudo bash ~/install-3x-ui.sh --repair-reality-target | Saved deployment and repair records |

The file contains candidate settings. After manually changing the ISP in the panel, update your private file before running --configure-nodes so an old configuration does not overwrite the current credentials.

See [Troubleshooting](docs/troubleshooting.md) for diagnostics.

## Development and verification

~~~bash
bash scripts/check.sh
~~~

Local checks cover Shell / Python syntax, configuration boundaries, routing, quotas, and the CLI. CI does not deploy a VPS or use real ISP credentials; certificate issuance and actual client connectivity require separate acceptance tests. See [Contributing](CONTRIBUTING.md).

## Project status

This is the initial 0.1.0 version, adapted from an installer already used for deployments, with a separate configuration file and offline validation. Repository: [AmazingUmi/3x-ui-bootstrap](https://github.com/AmazingUmi/3x-ui-bootstrap).

## License

This project is licensed under the [MIT License](LICENSE). Third-party projects retain their own licenses.

Dependencies: [3x-ui](https://github.com/MHSanaei/3x-ui), [Xray-core](https://github.com/XTLS/Xray-core), and [Certbot](https://github.com/certbot/certbot). Their release binaries are not bundled; the installer downloads and verifies pinned versions.
