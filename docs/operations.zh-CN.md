# 操作指南

[English](operations.md) | 简体中文 · [项目首页](../README.zh-CN.md) · [参数配置](configuration.zh-CN.md) · [安全说明](security.zh-CN.md)

本指南涵盖全新 VPS 部署、客户端导入、日常维护以及常见故障排查。

> **适用范围**：本工具面向全新 Ubuntu / Debian VPS，不会迁移已有的 3x-ui 或 Nginx 部署。如果安装或变更配置过程中意外中断，请保留状态目录并直接重新执行同一命令即可安全续跑。

---

## 全新 VPS 部署

### 1. 服务器要求

- **系统**：Ubuntu 22.04+ 或 Debian 12+（带 `systemd` 与 Python 3.10+）
- **架构**：`amd64`（`x86_64`）或 `arm64`（`aarch64`）
- **网络**：静态公网 IPv4 地址
- **权限**：可用的 SSH 登录方式及 `sudo` 权限

### 2. 在本地准备并校验 `config.json`

在本地项目目录中生成配置文件（仅在不存在时复制模板，避免覆盖已有凭据或配置）：

```bash
test -f config.json || cp config.example.json config.json
chmod 600 config.json
nano config.json
bash ./install-3x-ui.sh --config ./config.json --validate-config
```

使用默认选项（`direct` 直连、SSH 隧道管理面板、不限流量）时，只需填写 `SERVER_IP` 即可安装。启用 ISP 线路需要上游代理凭据；启用 `PANEL_HTTPS=true` 需要填写域名 `SUB_DOMAIN`。完整字段与示例见[参数配置](configuration.zh-CN.md)。

`--validate-config` 会在本地检查 JSON 语法、字段类型、端口冲突与模式约束，无需 `sudo` 或联网。

### 3. 配置域名解析与防火墙

如果填写了 `SUB_DOMAIN`，请将其 `A` 记录直接指向 `SERVER_IP`，关闭 CDN 代理（仅 DNS 解析），等待解析生效。如果留空 `SUB_DOMAIN`，订阅将自动使用公网 IPv4 申请 HTTPS 证书。

脚本不会自动修改防火墙或 SSH 设置，请在**云控制台安全组**和**服务器本机防火墙**中同时核对以下端口：

| 默认 TCP 端口 | 用途 | 放行规则 |
| --- | --- | --- |
| SSH 端口（常见为 `22`） | 远程管理及 SSH 面板隧道 | 保持放行 |
| `80` | Let's Encrypt 证书申请与自动续期 | 放行公网 |
| `443` | Direct / ISP 共享节点入站（`NODE_PORT`） | 放行公网 |
| `38443` | Nginx HTTPS 订阅入口（`SUB_PORT`） | 放行公网 |
| `7777` | 管理面板端口（`PANEL_PORT`） | 默认**不要放行**；仅开启 `PANEL_HTTPS=true` 时放行 |
| `12096` | 内部订阅后端（`SUB_BACKEND_PORT`） | **严禁放行**（仅监听 `127.0.0.1`） |

若自定义了端口，请以 `--validate-config` 输出的端口清单为准。`direct+isp` 模式下两条线路共用 `NODE_PORT`，无需额外开放 ISP 入站端口。

### 4. 上传脚本、预检并安装

在本地终端上传 `install-3x-ui.sh` 与 `config.json` 并登录 VPS（将 `ubuntu` 和 `YOUR_VPS_IP` 替换为实际值）：

```bash
scp ./install-3x-ui.sh ./config.json ubuntu@YOUR_VPS_IP:~/
ssh ubuntu@YOUR_VPS_IP
```

建议在部署前先安装系统安全更新并确认 SSH 密钥登录正常。

在 VPS 上执行安装前预检：

```bash
chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
```

`--check` 会检查系统环境、端口占用、ISP 上游连通性与出口 IP（如已启用）、DNS 解析、REALITY 伪装目标支持（TLS 1.3 / HTTP/2）以及证书条件，不会安装软件或修改系统服务。

预检通过后执行安装：

```bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
```

`--install` 会安装必要依赖并校验上游发行包 SHA-256 摘要、自动申请 TLS 证书、初始化随机管理员凭据、配置 Xray 节点与 Nginx 订阅网关（`3x-ui-subscription.service`），并完成本地连通性验证。

> **说明**：安装过程会自动屏蔽系统默认的 `nginx.service`，由独立的 `3x-ui-subscription.service` 专职托管订阅网关，同时让 `80/TCP` 保持空闲以供 Certbot 自动验证使用。

### 5. 打开管理面板并导入订阅

安装完成后，终端会输出随机生成的面板账号、密码、访问地址、Mihomo / Shadowrocket 订阅链接以及 VLESS 链接。之后可随时在 VPS 上运行以下命令查看：

```bash
sudo bash ~/install-3x-ui.sh --show
```

结果同时保存在 `/var/lib/3x-ui-bootstrap/result.txt`（仅 `root` 可读）。完整订阅链接、二维码和 VLESS 链接均属于访问凭据，请妥善保密。

#### 访问管理面板

在默认推荐配置（`PANEL_HTTPS=false`）下，面板仅监听 `127.0.0.1`。请在本地电脑**另开一个终端**建立 SSH 隧道（如修改过 `PANEL_PORT`，请同步替换第二个 `7777`）：

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:17777:127.0.0.1:7777 ubuntu@YOUR_VPS_IP
```

保持该终端连接，然后在浏览器打开安装结果给出的完整 `http://127.0.0.1:17777/<随机路径>/` 地址。如果开启了 `PANEL_HTTPS=true`，直接打开结果中的 `https://...` 地址即可。

#### 导入客户端订阅

- 将结果中的 **Mihomo** 或 **Shadowrocket** HTTPS 订阅链接导入对应客户端（也可直接导入 VLESS 节点链接）。
- 双线路（`direct+isp`）模式会生成 `<节点名>-Direct` 与 `<节点名>-ISP` 两组订阅和节点，两者连接同一 VPS 端口，使用独立的 UUID 与订阅 ID。
- 直接在浏览器打开有效订阅 URL 会直接下载订阅数据，不会显示网页。

---

## 部署后验证

在 VPS 上检查服务运行状态和端口监听地址：

```bash
sudo systemctl status x-ui 3x-ui-subscription --no-pager
sudo ss -lntp | grep -E ':(38443|12096)\b'
```

使用默认端口时，应看到 Nginx 监听 `0.0.0.0:38443`，`x-ui` 仅监听 `127.0.0.1:12096`。

随后在客户端设备上进行实测（如需测试原始端点，请先关闭电脑本地代理或 TUN 接管）：

1. **订阅更新**：在 Mihomo 或 Shadowrocket 中更新订阅，确认节点列表与流量配额信息正常刷新。
2. **出口分流**：分别切到 Direct 与 ISP 节点访问网页或查询 IP，确认 Direct 出口为 VPS IP、ISP 出口为上游供应商 IP。
3. **网关隔离**：从外部访问订阅端口的 `/`、`/assets/` 与 `/sub/assets/`，均应返回 `404`；完整有效订阅链接则应正常返回订阅数据。

---

## 日常维护

以下命令均在 VPS 上执行。仅编辑 `config.json` 不会改变运行中的服务，需执行对应的维护命令使其生效：

| 操作 | 命令 |
| --- | --- |
| 查看面板账号、访问地址与订阅链接 | `sudo bash ~/install-3x-ui.sh --show` |
| 查询客户端原生月流量用量 | `sudo bash ~/install-3x-ui.sh --traffic-status` |
| 使用临时本地实例诊断 REALITY 握手 | `sudo bash ~/install-3x-ui.sh --diagnose` |
| 应用 `SUB_DOMAIN`、`PANEL_HTTPS`、`ACME_EMAIL` 变更 | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-domain` |
| 应用 `NODE_NAME`、`NODE_MODE`、`ISP_*` 与配额变更 | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-nodes` |
| 仅调整月流量配额（保留原有重置日） | `sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-traffic` |
| 切换配置文件指定的 Xray-core 版本 | `sudo bash ~/install-3x-ui.sh --config ~/config.json --switch-core` |
| 将 REALITY 伪装目标修复为 `www.cloudflare.com` | `sudo bash ~/install-3x-ui.sh --repair-reality-target` |

- `--show`、`--traffic-status`、`--diagnose` 和 `--repair-reality-target` 读取服务器已保存的状态，无需提供 `--config`。
- `--configure-traffic` 后面不接数字：请直接修改完整 `config.json` 中的 `TOTAL_MONTHLY_GB` 和 `ISP_MONTHLY_GB`（单位 GiB）后再运行该命令，已用流量计数和原部署重置日均会保留。
- `--diagnose` 仅在 `127.0.0.1` 启动临时测试进程，不会更改现有服务、数据库或正式节点配置。
- 若曾在 3x-ui 面板网页端手工修改过 ISP 上游账号，请先同步更新 `config.json`，再执行 `--configure-nodes`。请勿手动修改受管订阅 ID、路径或监听端口，以免与 Nginx 白名单规则不一致。

---

## 切换 Xray-core 版本

安装器默认部署 Xray-core `26.10.31`。如旧版本客户端遇到 TLS 或 REALITY 握手兼容问题，可通过配置切换到内置校验的 `26.6.27` 版本，也可随时切回最新版。

修改 `config.json` 中的 `"XRAY_VERSION": "26.6.27"`（或 `"26.10.31"`），然后执行：

```bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --switch-core
```

**切换流程说明：**
1. 停止服务前先下载并校验目标版本与当前版本的 SHA-256 摘要，确保回退无忧。
2. 短暂停止服务、替换核心、校验配置并启动服务进行运行检查。
3. 若新核心未通过服务端检查，会自动回退至原版本；数据库、节点 UUID、订阅链接、已有流量计数与重置日均保持不变。

> **建议**：切换版本后请重新在客户端验证 Wi-Fi / 蜂窝网络、Direct / ISP 出口和订阅刷新。请勿直接在 3x-ui 面板界面中更新 Xray 核心，以免破坏脚本状态校验；日常使用建议保持默认的 `26.10.31` 以获取最新安全修复。

---

## 查看服务状态与证书续期

查看服务状态、端口监听、系统防火墙及近期日志：

```bash
sudo systemctl status x-ui 3x-ui-subscription --no-pager
sudo ss -lntp
sudo ufw status verbose
sudo journalctl -u x-ui -n 80 --no-pager
sudo journalctl -u 3x-ui-subscription -n 80 --no-pager
```

> 说明：`ufw status: inactive` 仅表示服务器本机 UFW 未开启，并不代表云厂商安全组已放行对应端口。分享日志前请先脱敏敏感信息，详见[安全说明](security.zh-CN.md)。

检查 Nginx 网关配置语法与 Certbot 自动续期定时器：

```bash
sudo /usr/sbin/nginx -t -c /var/lib/3x-ui-bootstrap/nginx.conf
sudo systemctl status 3x-ui-cert-renew.timer --no-pager
sudo journalctl -u 3x-ui-cert-renew.service -n 80 --no-pager
```

手动执行 `nginx -t` 时必须通过 `-c /var/lib/3x-ui-bootstrap/nginx.conf` 指定受管配置。证书续期成功后，hook 会自动校验 TLS 证书与 Nginx 配置并重载 `3x-ui-subscription`（若开启了 `PANEL_HTTPS=true`，也会重启 `x-ui` 加载新证书）。请始终在防火墙中保持 `80/TCP` 可达，以确保自动续期顺利完成。

---

## 常见问题排查

### 配置校验失败
重新运行 `--validate-config` 查看具体报错行号或字段提示。请确认配置文件为纯 UTF-8 JSON（不含注释），端口号为整数、`PANEL_HTTPS` 为布尔值 `true` / `false`（不加引号），且文件权限已设为 `600`（`chmod 600 config.json`）。

### 域名仍解析到旧 IP
检查权威 DNS 的 `A` 记录及公共 DNS 返回值，确认已关闭 CDN 代理，并等待旧记录的 TTL 过期。

### 面板或订阅链接无法访问
使用 `sudo bash ~/install-3x-ui.sh --show` 核对完整 URL 的协议、端口、随机路径与订阅 ID：
- **SSH 面板**：确认本地 `ssh -N -L ...` 隧道终端仍在运行。
- **公网 HTTPS 面板**：确认云防火墙和系统防火墙已放行 `PANEL_PORT`（默认 `7777/TCP`）。
- **订阅链接**：确认已放行 `SUB_PORT`（默认 `38443/TCP`），并通过 `journalctl -u 3x-ui-subscription` 查看日志。

### 访问订阅根路径（`/`）或 `/assets/` 返回 404
这是正常的安全策略。Nginx 订阅网关仅放行完整的有效下载路径，故意拦截根路径、静态资源、无效 ID 和查询参数（如 `?html=1`）。请直接在客户端中使用完整的 `/mihomo/<id>` 或 `/sub/<id>` 链接更新订阅。

### `direct+isp` 模式下只有一条线路可用
在面板中检查对应客户端的剩余配额、启用状态、UUID 及路由规则。双线路共用同一个 VLESS + REALITY 入站，必须通过“入站标签 + 客户端 email（`user`）”将流量分别指向 `direct` 与 `bootstrap-isp`。另外，ISP 线路默认阻断 UDP，且上游代理故障时不会回退到 Direct。

### ISP 预检通过，但客户端连不上
请分段排查：客户端到 VPS `NODE_PORT` 的公网连通性、面板中 `bootstrap-isp` 出站配置以及路由匹配规则，同时测试 Wi-Fi 与蜂窝网络。如曾在面板内手工修改过 `bootstrap-isp`，请确保入站标签、客户端 email 和用户路由未被更改并保存应用配置。

### Shadowrocket 无法连接
- 使用 `sudo bash ~/install-3x-ui.sh --show` 核对当前 Xray 版本，并检查节点 UUID、`flow=xtls-rprx-vision`、REALITY 公钥（`pbk`）、SNI、Short ID（`sid`）、服务器 IP 与端口是否一致。
- 新版 Xray REALITY 握手要求客户端支持 `X25519MLKEM768` 密钥交换，请保持 Shadowrocket 为较新版本，在节点 TLS 设置中核对实际生效的指纹，并将 `minClientVer` 留空。
- 若使用旧版 Shadowrocket（如 `2.2.92`），可在 `config.json` 中将 `XRAY_VERSION` 设为 `"26.6.27"` 后执行 `--switch-core`，并在 Wi-Fi 与蜂窝网络下分别复测。
- 参考资料：[Xray REALITY 配置说明](https://docs.sanaei.dev/zh/docs/config/reality/)、[Shadowrocket 2.2.93 开发说明](https://t.me/s/ShadowrocketNews?before=1642)。

### 安装或配置变更过程中意外中断
请**不要**删除 `/var/lib/3x-ui-bootstrap` 目录或清空重试。可查看 `/var/lib/3x-ui-bootstrap/install.log` 定位原因并修复（例如防火墙或 DNS 问题），随后使用同一份 `config.json` 重新执行原命令（`--install`、`--configure-domain`、`--configure-nodes`、`--switch-core` 或 `--repair-reality-target`）即可安全续跑。
