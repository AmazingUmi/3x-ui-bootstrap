# 常见问题

[English](troubleshooting.md) | 简体中文

## 配置校验失败

先运行 bash install-3x-ui.sh --config config.json --validate-config。JSON 不支持注释，端口应为数字，布尔值应为 true / false；确认配置文件权限为 600。

--validate-config 只验证本地格式及逻辑，不验证 DNS、ISP 账号、系统端口占用或公网可达性。系统与上游条件在 VPS 上使用 --check，公网可达性再由真实客户端验收。

## 域名仍指向旧 IP

核对权威 DNS 的 A 记录，再分别查询常用公共 DNS。清理 VPS 的本地缓存不能强制公共递归 DNS 提前过期；等待 TTL 和解析同步，并确认没有启用 CDN 代理。

## 面板或订阅无法访问

确认完整 URL 中的协议、端口、随机路径和订阅 ID。SSH 面板必须先建立隧道；公网 HTTPS 面板需要开放面板端口。订阅默认使用 2096/TCP，与面板、节点端口各自独立。

检查 VPS：

~~~bash
sudo systemctl status x-ui --no-pager
sudo ss -lntp
sudo ufw status verbose
sudo journalctl -u x-ui -n 80 --no-pager
~~~

同时核对云防火墙。UFW inactive 表示它未启用，单独添加规则不会解决其他路径的问题。

## Direct 和 ISP 共用端口时如何核对

两组节点都应连接 VPS 的 `NODE_PORT`（默认 `443`），UUID 和订阅 ID 不同。面板中应只有一个受管 VLESS + REALITY 入站，其客户端名称为 `<昵称>-Direct` 和 `<昵称>-ISP`。路由同时匹配入站标签与客户端 email（`user`），分别指向 `direct` 和 `bootstrap-isp`；不要删除这些客户端匹配条件或只按共享入站标签分流。

ISP 的 UDP 被阻断，上游失败不会自动回退 Direct。配额按客户端独立计量；某一客户端用尽额度时，另一客户端仍可使用同一入站。若只剩一条线路可用，核对对应客户端的配额、启用状态、UUID 和路由。使用 443 不代表公网路径必然可用，仍需分别测试实际连接和出口。

## ISP 出站能测通，客户端仍不通

分开确认：上游代理可用、正式入站的认证及转发可用、客户端到 VPS 的 TCP 连接可用。

本机验收通过不能替代客户端公网测试。切换 Wi-Fi / 蜂窝网络做对照；必要时捕获客户端连接对应的数据包。TCP 端口测试也不能替代真实 VLESS 认证。桌面启用 TUN 时，普通连接测试可能被代理接管，需要核对测试实际走的路径。

面板手工更换 bootstrap-isp 后，先同步私有配置，保留入站标签、客户端 email 以及指向 bootstrap-isp 的用户路由，再保存并应用面板设置。不要先重装或运行旧参数的 --configure-nodes。

## Shadowrocket 连接失败

历史已验证组合为 **Shadowrocket 2.2.92（3345）+ Xray-core 26.6.27**，依据此前用户对订阅导入、网页访问和出口 IP 检查的成功反馈。**本项目尚未验证其他 Shadowrocket / Xray 版本组合。**

历史验收来自双入站部署，新的共享入站拓扑仍需重新验收。

确认内核仍为固定的 26.6.27，核对 UUID、Vision flow、REALITY 公钥、SNI、Short ID、客户端连接地址和入站端口。更换内核或客户端后需要重新测试。

--diagnose 使用临时回环副本检查 REALITY 握手目标；它不复现正式 ISP 出站，也不证明公网客户端路径可用。

## 安装中断

保留 /var/lib/3x-ui-bootstrap、数据库和私有日志。修复原因后使用同一配置重试；不要清空状态目录。日志和状态可能包含凭据，分享前需脱敏。
