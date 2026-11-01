# Security

English | [简体中文](security.zh-CN.md)

This project reduces exposure by isolating the subscription backend, restricting public download paths, and protecting administrative credentials. A reachable port, an identifiable application, and an IP reputation label are different findings. The project does not promise to conceal proxy use or prevent IP classification.

See the [Operations guide](operations.md) for deployment, acceptance checks, and troubleshooting, and the [Configuration reference](configuration.md) for fields and defaults. This document applies to fresh deployments of version 0.3.0.

## 1. Service boundaries

The default subscription path is:

```text
Client → public 2096 / HTTPS / Nginx
                         ↓ local HTTP
                  127.0.0.1:12096 / 3x-ui subscription backend
```

| Endpoint | Default behavior | Boundary to preserve |
| --- | --- | --- |
| Node `443/TCP` | Xray serves VLESS + REALITY; Direct / ISP share an inbound and route by client identity | Node and subscription ports are independent; working nodes do not prove subscription refresh works |
| Subscription `2096/TCP` | Nginx serves HTTPS and forwards only complete download URLs for managed clients | Keep it publicly reachable; simply closing it prevents subscription refresh |
| Backend `12096/TCP` | Local HTTP bound only to `127.0.0.1` | Do not open it in cloud or host firewalls, or change it to a public listener |
| Default panel `7777/TCP` | With `PANEL_HTTPS=false`, the panel binds to loopback and is reached through SSH | No public panel port is required |
| Optional public panel `7777/TCP` | With `PANEL_HTTPS=true`, x-ui itself serves HTTPS | Separate from subscription Nginx; restrict access to administrative source IPs |
| Certificate validation `80/TCP` | Certbot listens temporarily during issuance and renewal | Keep firewall access allowed and the port available; no listener between validations is normal |

A random panel path reduces common-path discovery. It does not replace authentication, source restrictions, or security updates. If the server has public IPv6, inspect its listeners and firewall separately; IPv4 checks or an A record alone are insufficient.

## 2. Subscription access control

Nginx allows only the complete `/sub/<id>` and `/mihomo/<id>` paths of active managed clients. It checks the original request URL, Host, and method. Only GET / HEAD can download; invalid IDs, query strings, encoded or normalized path variants, `/assets/`, and nested static-resource paths do not reach the backend.

The gateway preserves the client User-Agent, fixes the backend Host and `Accept: */*`, and does not forward other client headers such as Cookie or Authorization. A browser opening a valid URL receives subscription data instead of an HTML page. Usage and update-interval response headers remain available for client downloads, subscription updates, and quota refreshes.

**A complete subscription URL is an access credential.** Anyone holding it can retrieve that subscription. Random IDs and the gateway allowlist do not identify the person using a link. Keep URLs, QR codes, VLESS URIs, and screenshots containing them private.

The installer manages subscription IDs, paths, backend listeners, and gateway rules together. Manually adding clients or changing these fields does not update the gateway allowlist automatically. Use the configuration commands in the operations guide for the managed deployment.

## 3. Credentials, files, and certificates

- Before the first public start, the installer sets a random administrator username, password, and panel path. It does not first expose the panel with `admin/admin`.
- Keep private `config.json` files at mode `600` or stricter on both the local machine and the VPS. `/var/lib/3x-ui-bootstrap` must be root-owned with mode `700`.
- The database, state, installation results, backups, and generated Nginx configuration contain credentials or subscription IDs and must remain private. Nginx access logging is disabled, but error logs can contain request paths. Redact diagnostics before sharing and do not publish full `nginx -T` output.
- `.gitignore` protects common filenames from accidental commits, not every custom filename. Review staged content before committing.
- The subscription gateway allows only TLS 1.2 / 1.3. Startup and reload checks validate the certificate hostname or IP, validity, chain, and matching private key. Renewal validates the configuration before reloading the gateway; a public HTTPS panel also restarts x-ui to load its certificate.

The installer verifies digests of pinned 3x-ui, Xray, and Certbot release files; Nginx comes from system package repositories. A matching digest establishes the expected download, not the absence of vulnerabilities. The installer does not configure firewalls, Fail2ban, Nginx request rate limits, or an OS patch policy.

## 4. What scanners can still observe

Ordinary probes can still observe open ports, certificate domain names, and `Server: nginx`. `server_tokens off` hides the Nginx version; it does not guarantee that the software name is hidden. [Nginx documentation](https://nginx.org/en/docs/http/ngx_http_core_module.html#server_tokens)

Blocking static resources reduces direct identification of 3x-ui, but does not prevent an IP from being classified as a proxy. Reputation providers may also use hosting-network ownership and other observations. This project neither queries nor controls those classification results. [MaxMind classification documentation](https://support.maxmind.com/knowledge-base/articles/anonymizer-and-proxy-data-maxmind)

Renaming a `sub` subdomain or concealing a panel path does not replace isolation. Inspect service content, listener scope, and access controls separately; a 404 at the root path is not a complete security assessment.

## 5. Upstream versions and advisories

As of **2026-11-01**, the project pins 3x-ui **3.10.2**, Xray-core **26.6.27**, and Certbot **5.8.0**. The affected ranges of the following four 3x-ui advisories include 3.10.2. Each lists **3.11.0** as the patched version:

| Official advisory | Required conditions | Applicability to the generated configuration |
| --- | --- | --- |
| [Default administrator credentials](https://github.com/MHSanaei/3x-ui/security/advisories/GHSA-766p-2p4j-3mfm) | A publicly running database retains `admin/admin` | The installer sets random credentials before the first start and does not use that default-credential startup flow |
| [Login rate-limit bypass behind a proxy](https://github.com/MHSanaei/3x-ui/security/advisories/GHSA-73xj-vvj7-fp4p) | The panel sits behind a trusted reverse proxy forwarding spoofable client-IP headers | x-ui serves the panel directly; project Nginx proxies subscriptions, not login |
| [WG/AWG injection in subscription HTML](https://github.com/MHSanaei/3x-ui/security/advisories/GHSA-r59q-h589-mcjq) | The HTML page processes malicious external WG/AWG links, then a user executes the generated configuration | The gateway blocks the HTML page; the installer creates its own VLESS nodes and does not configure those external subscriptions |
| [WG/AWG configuration-builder injection](https://github.com/MHSanaei/3x-ui/security/advisories/GHSA-vg5r-p8fc-gffw) | A malicious paired node or stored fields enter WG/AWG configuration, and a client executes injected hooks | The installer configures neither WG/AWG nor paired nodes; blocking HTML alone would not address this issue |

These are applicability judgments based on the installer's generated configuration, **not a claim that 3.10.2 contains the fixes**. Manually enabling other features, proxying the panel, or changing credentials changes the assumptions. Plan compatibility testing of a patched version and repeat subscription, quota, and real-client checks after upgrading. Version pinning supports reproducibility; it does not replace security updates.

## 6. Fresh-deployment acceptance record: 2026-11-01

The user confirmed that this fresh deployment worked normally. No new client-version compatibility matrix was recorded. A separate unauthenticated, read-only public IPv4 assessment was repeated through the physical network interface, excluding false-positive port results caused by a local TUN accepting TCP connections.

| Check | Observed result |
| --- | --- |
| 25 unauthorized paths on 2096 | All returned 404, covering static resources, known frontend JS, nested paths, invalid IDs, and encoding variants; no direct software-marker leak was found |
| 12 request variants | Wrong Host / SNI, unusual headers, methods, and plaintext HTTP did not retrieve subscription data; responses were 404, 400, or 405 |
| Backend 12096 | Public TCP / HTTP connections timed out, consistent with the server's `127.0.0.1:12096` listener record |
| HTTPS | Hostname and chain verification passed; TLS 1.2 / 1.3 worked and TLS 1.0 / 1.1 were rejected |
| Node 443 | Unauthenticated probes returned the expected Cloudflare content without direct VLESS / 3x-ui text markers |
| Panel 7777 | Reachable from the test network; seven common paths returned 404; this did not establish whether a source allowlist was configured |

The record does not cover a full port scan, variants of a real valid subscription ID, authenticated authorization or database checks, OS-package vulnerability assessment, other public IPv6 addresses, or commercial IP reputation databases. Local gateway integration tests cover rules using valid IDs, but those results are not a substitute for corresponding checks on the deployed VPS.

## 7. Rechecking a deployment

After creating a server, changing domains or routes, or upgrading software, repeat the [Operations guide](operations.md) checks: public Nginx and loopback backend listeners, real-client subscription and quota refresh, Direct / ISP exits, and denial of static resources. Also verify administrative source restrictions and the renewal service.

Exclude local TUN or proxy interception when testing ports externally. A timeout establishes only that the connection did not succeed from that test network; it does not independently prove the absence of a server listener. Interpret it alongside server-side listeners and both firewall layers.
