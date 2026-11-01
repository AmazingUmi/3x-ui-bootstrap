# 操作指南

[English](operations.md) | 简体中文 · [项目首页](../README.md) · [安全说明](security.zh-CN.md) · [参数配置](configuration.zh-CN.md)

本指南用于全新 VPS 的安装、验收和日常维护。脚本不会迁移已有 3x-ui 或 Nginx 部署；同版本安装中断后，可以保留状态继续执行。

## 新机部署

### 1. 准备服务器和配置

服务器要求：Ubuntu 22.04+ 或 Debian 12+、systemd、Python 3.10+、amd64 或 arm64，以及静态公网 IPv4。准备可用的 SSH 登录方式和 sudo 权限。

在本机项目目录中，首次创建配置；已有 `config.json` 时直接编辑，保留其中的账号信息：

~~~bash
test -f config.json || cp config.example.json config.json
chmod 600 config.json
nano config.json
bash ./install-3x-ui.sh --config ./config.json --validate-config
~~~

默认 Direct 线路、SSH 面板、不限流量时，只需填写 `SERVER_IP`。选择 ISP 线路时还需填写上游账号；开启公网 HTTPS 面板时必须填写域名。字段含义和完整示例见[参数配置](configuration.zh-CN.md)。

`--validate-config` 只检查本地配置格式与逻辑，无需 sudo 或网络；通过不代表 DNS、上游代理或公网连接已可用。

### 2. 配置 DNS 和防火墙

使用域名时，将 `SUB_DOMAIN` 的 A 记录直接指向 `SERVER_IP`，关闭该记录的 CDN 代理，等待公共 DNS 解析一致。域名留空时，订阅使用公网 IP 的 HTTPS 证书，面板通过 SSH 隧道访问。

同时检查云防火墙和服务器防火墙。脚本只输出端口清单，不自动修改防火墙或 SSH 设置。

| 默认 TCP 端口 | 用途 | 公网规则 |
| --- | --- | --- |
| 实际 SSH 端口，常见为 22 | 登录、上传、SSH 隧道 | 保留管理连接 |
| 80 | 证书申请和自动续期 | 保持可达 |
| 443 | Direct / ISP 共享节点入站 | 放行 |
| 2096 | Nginx HTTPS 订阅入口 | 放行 |
| 7777 | 公网 HTTPS 面板 | 仅 `PANEL_HTTPS=true` 时放行，建议限制管理来源 IP |
| 12096 | 本机订阅后端 | 不开放公网，仅监听 `127.0.0.1` |

修改端口后，以配置校验输出为准。默认 SSH 面板无需开放 7777；Direct 和 ISP 共用 `NODE_PORT`，不需要另开 ISP 入站端口。

### 3. 上传和安装

在本机项目目录执行，替换 SSH 用户名和新机 IP；上传当前要测试或部署的脚本版本：

~~~bash
scp ./install-3x-ui.sh ./config.json ubuntu@YOUR_VPS_IP:~/
ssh ubuntu@YOUR_VPS_IP
~~~

在 VPS 上先执行预检：

~~~bash
chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
~~~

预检通过后安装：

~~~bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
~~~

`--check` 检查系统、端口占用、ISP、DNS、REALITY 目标和证书条件，不安装软件或修改服务。`--install` 安装组件、申请证书、配置节点与订阅入口，并执行服务端检查。

订阅由独立的 `3x-ui-subscription.service` 管理。发行版默认 `nginx.service` 被屏蔽是预期行为，80 端口留给 Certbot 的独立验证服务。

### 4. 访问面板、导入订阅

安装结束会输出账号、完整面板地址、Mihomo / Shadowrocket 订阅和 VLESS 链接。之后可在 VPS 再次查看：

~~~bash
sudo bash ~/install-3x-ui.sh --show
~~~

结果保存在 `/var/lib/3x-ui-bootstrap/result.txt`，仅 root 可读。完整订阅链接和安装输出应保密。

默认 SSH 面板需要在本机另开终端建立隧道，以下命令使用默认面板端口：

~~~bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:17777:127.0.0.1:7777 ubuntu@YOUR_VPS_IP
~~~

保持隧道运行，再打开安装结果给出的 `http://127.0.0.1:17777/` 后带随机路径的完整 URL。公网 HTTPS 面板直接使用结果中的 HTTPS URL。

在对应客户端导入本次安装生成的订阅。双线路会输出 `<昵称>-Direct` 和 `<昵称>-ISP`：两者连接同一 VPS 端口，使用不同 UUID 和订阅 ID。浏览器打开有效订阅会下载数据，不显示订阅展示页。

## 安装后验收

在 VPS 检查服务与监听地址：

~~~bash
sudo systemctl status x-ui 3x-ui-subscription --no-pager
sudo ss -lntp | grep -E ':(2096|12096)\b'
~~~

使用默认端口时，应看到 Nginx 监听 `0.0.0.0:2096`，x-ui 仅监听 `127.0.0.1:12096`。采用自定义端口时，相应替换命令中的数字。

再从真实客户端完成以下检查：

1. 更新订阅成功，额度信息可以刷新。
2. 分别使用 Direct / ISP 浏览网页；Direct 出口为 VPS IP，ISP 出口为供应商出口。
3. 从本机访问订阅入口的 `/`、`/assets/`、`/sub/assets/`，应返回 404；完整有效订阅链接应正常下载。

节点连接默认走 443，订阅刷新默认走 2096，需要分别验证。服务端检查和 TCP 端口连通不能代替真实 VLESS 认证及客户端公网验收。桌面 TUN 可能接管探测连接，测试前核对实际网络路径。

2026-11-01 已收到本版新机部署“正常使用”的用户反馈，并完成外部 IPv4 暴露复测，范围见[安全说明](security.zh-CN.md)。本次未记录客户端版本，不能扩展为所有版本的兼容性保证。

## 日常维护

以下命令在 VPS 执行。配置文件是待应用的设置，编辑文件本身不会修改正在运行的服务。

| 操作 | 命令 |
| --- | --- |
| 查看账号、面板及订阅链接 | `sudo bash ~/install-3x-ui.sh --show` |
| 查询客户端原生月流量 | `sudo bash ~/install-3x-ui.sh --traffic-status` |
| 临时诊断 REALITY 握手 | `sudo bash ~/install-3x-ui.sh --diagnose` |
| 应用域名、HTTPS 面板和邮箱设置 | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-domain` |
| 应用昵称、模式、ISP 和配额设置 | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-nodes` |
| 只调整月配额，保留原部署重置日 | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-traffic` |
| 修复已部署节点的 REALITY 目标 | `sudo bash ~/install-3x-ui.sh --repair-reality-target` |

`--show`、`--traffic-status`、`--diagnose` 和 `--repair-reality-target` 使用服务器保存的部署，不需要配置文件。三个 `--configure-*` 命令各有更新范围，详见[参数配置](configuration.zh-CN.md)；服务配置变更可能短暂中断连接，完成后按输出更新客户端。

`--diagnose` 使用临时回环副本，不更改现有节点或服务，也不复现正式 ISP 出站。`--repair-reality-target` 会修改正式部署，适合诊断已确认目标异常后使用。

通过面板手动修改 ISP 账号后，先同步私有配置；不要用旧参数运行 `--configure-nodes`。受管订阅 ID、路径、监听地址应由脚本维护，以免与 Nginx 白名单不一致。

## 证书和服务排查

先在 VPS 查看当前服务、监听与日志：

~~~bash
sudo systemctl status x-ui 3x-ui-subscription --no-pager
sudo ss -lntp
sudo ufw status verbose
sudo journalctl -u x-ui -n 80 --no-pager
sudo journalctl -u 3x-ui-subscription -n 80 --no-pager
~~~

同时检查云防火墙。`ufw inactive` 只表示 UFW 未启用，不能说明云防火墙已经放行。分享日志前先脱敏，处理范围见[安全说明](security.zh-CN.md)。

Nginx 与证书续期检查：

~~~bash
sudo /usr/sbin/nginx -t -c /var/lib/3x-ui-bootstrap/nginx.conf
sudo systemctl status 3x-ui-cert-renew.timer --no-pager
sudo journalctl -u 3x-ui-cert-renew.service -n 80 --no-pager
~~~

必须用 `-c` 指定受管配置；默认 Nginx 配置不是订阅配置。证书续期后会重载或启动订阅网关，开启公网 HTTPS 面板时还会重启 x-ui。

80 端口必须保留证书验证所需的公网规则，但平时不要求有常驻监听进程。订阅后端使用本机 HTTP，不需要自己的公网证书。不要用开放 12096 的方式处理订阅故障。

## 常见问题

### 配置校验失败

重新执行 `--validate-config`，确认 JSON 无注释、端口为数字、布尔值为 `true` / `false`，且文件权限为 600。它只验证格式与逻辑；DNS、ISP 和系统条件由 VPS 上的 `--check` 验证。

### 域名仍指向旧 IP

核对权威 DNS 的 A 记录和公共 DNS 返回值，关闭该记录的 CDN 代理，等待 TTL 过期与解析同步。清理 VPS 本地缓存不能强制公共递归 DNS 提前刷新。

### 面板或订阅无法访问

核对完整 URL 的协议、端口、随机路径与订阅 ID。SSH 面板需要已建立的隧道；公网 HTTPS 面板需要放行面板端口。订阅更新失败时单独检查 2096 的网关服务与 DNS。

### 订阅首页或静态资源返回 404

这是预期行为。只接受完整有效的下载链接，不接受首页、静态资源、无效 ID 或附加查询参数。请直接在客户端更新订阅；不要用首页是否显示网页判断服务是否正常。

### Direct / ISP 只有一条线路可用

检查对应客户端的配额、启用状态、UUID 和路由。两条线路共用一个 VLESS + REALITY 入站，路由必须同时匹配入站标签与客户端 email（`user`），分别指向 `direct` 和 `bootstrap-isp`；只按共享入站标签无法区分两条线路。

ISP 的 UDP 被阻断，上游失败不会自动回退 Direct。配额独立计量，一条线路用尽额度不会自动耗用另一条线路的配额。修改客户端显示名称也不会改变出口。

### ISP 出站测试通过，客户端仍不通

分别确认上游代理、正式入站的认证及转发、客户端到 VPS 的公网连接。切换 Wi-Fi / 蜂窝网络对照，必要时检查对应连接的数据包。面板中修改 `bootstrap-isp` 后，应保留入站标签、客户端 email 和用户路由，并保存应用设置；不要先重装。

### Shadowrocket 连接失败

历史明确验证的组合是 **Shadowrocket 2.2.92（3345）+ Xray-core 26.6.27**，来自此前双入站部署。当前新部署已反馈可用，但未记录本次客户端版本，因此不扩大版本兼容记录。

确认核心仍为固定的 26.6.27，核对 UUID、Vision flow、REALITY 公钥、SNI、Short ID、连接地址及端口。更换核心或客户端后，重新验证导入、联网、出口和额度刷新。

### 安装或配置修改中断

保留 `/var/lib/3x-ui-bootstrap`、数据库和私有日志，修复原因后使用同一配置及原命令重试。域名、节点或目标修复中断时，分别继续对应的 `--configure-domain`、`--configure-nodes` 或 `--repair-reality-target`；不要删除状态后重新安装。

中断续跑只适用于本版受管部署。若检测到其他版本或手工安装残留，请在全新 VPS 部署，不在旧机上迁移。
