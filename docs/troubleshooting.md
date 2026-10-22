# Troubleshooting

English | [简体中文](troubleshooting.zh-CN.md)

## Configuration validation fails

Run bash install-3x-ui.sh --config config.json --validate-config first. JSON does not allow comments; ports must be numbers and Boolean values must be true / false. Check that configuration permissions are 600.

--validate-config checks only local syntax and configuration logic. It does not check DNS, ISP authentication, system port occupancy, or public reachability. Run --check on the VPS for system and upstream prerequisites, then use real clients to test public reachability.

## The domain still resolves to an old IP

Check the A record at the authoritative DNS provider, then query common public resolvers separately. Clearing the VPS's local cache cannot force public recursive resolvers to expire cached records early. Wait for the TTL and DNS propagation, and confirm CDN proxying is disabled.

## The panel or subscription is unreachable

Check the full URL's scheme, port, random base path, and subscription ID. An SSH-only panel requires an active tunnel; a public HTTPS panel requires its panel port to be open. Subscriptions default to 2096/TCP, separate from panel and node ports.

On the VPS, check:

~~~bash
sudo systemctl status x-ui --no-pager
sudo ss -lntp
sudo ufw status verbose
sudo journalctl -u x-ui -n 80 --no-pager
~~~

Also check the cloud firewall. UFW inactive means UFW is not enabled; adding a UFW rule alone will not resolve a problem elsewhere on the connection path.

## The ISP outbound test passes, but clients cannot connect

Verify three layers separately: the upstream proxy works, authentication and forwarding through the actual inbound work, and the client can establish a TCP connection to the VPS.

Server-side loopback success does not replace public client testing. Compare Wi-Fi and cellular connectivity, and capture packets for the relevant client connection if needed. A TCP port test does not validate VLESS authentication. On a desktop with TUN enabled, connection tests may themselves be proxied; confirm which path the test actually uses.

After manually changing bootstrap-isp in the panel, update the private configuration, retain the inbound tag and routing to bootstrap-isp, then save and apply the panel settings. Do not start by reinstalling or running --configure-nodes with old parameters.

## Shadowrocket cannot connect

The historically verified pair is **Shadowrocket 2.2.92 (3345) + Xray-core 26.6.27**, based on earlier user-confirmed subscription import, web browsing, and exit-IP checks. **Other Shadowrocket / Xray version combinations have not been verified by this project.**

Confirm that Xray remains pinned to 26.6.27. Check the UUID, Vision flow, REALITY public key, SNI, Short ID, client server address, and inbound port. Retest after changing the core or client version.

--diagnose uses a temporary loopback copy to test the REALITY handshake target. It does not reproduce the actual ISP outbound or prove that the public client path works.

## Installation was interrupted

Keep /var/lib/3x-ui-bootstrap, the database, and private logs. Fix the cause and retry with the same configuration; do not clear the state directory. Logs and state may contain credentials, so redact them before sharing.
