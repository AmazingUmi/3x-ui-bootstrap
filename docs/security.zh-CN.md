# 安全说明

[English](security.md) | 简体中文 · [项目首页](../README.zh-CN.md) · [操作指南](operations.zh-CN.md) · [参数配置](configuration.zh-CN.md)

3X-UI Bootstrap 通过隔离订阅后端、收窄公网下载路径、在首次启动前写入随机管理凭据以及默认关闭面板公网监听，显著缩小标准 3x-ui 部署的公网暴露面。

> **说明**：安全加固可以有效减少信息泄露与未授权访问风险，但任何代理服务都无法阻止全端口扫描，也不能保证完全规避网络侧特征探测或 IP 信誉库标记。

---

## 1. 服务边界与网络隔离

默认订阅请求流向如下，3x-ui 订阅后端不直接暴露于公网：

```text
客户端 ──► 公网 38443/TCP（HTTPS / Nginx 网关）
                   │
                   ▼（仅 127.0.0.1 HTTP）
            127.0.0.1:12096（3x-ui 订阅后端）
```

| 端口 / 服务 | 默认监听与行为 | 安全边界 |
| --- | --- | --- |
| 节点入站（`443/TCP`） | Xray 提供 VLESS + REALITY，按客户端认证身份分流 | 与订阅端口相互独立；节点通畅不代表订阅网关可用 |
| 订阅入口（`38443/TCP`） | Nginx 提供 TLS 1.2/1.3，仅放行受管客户端精确下载路径 | 保持公网放行，用于客户端更新订阅与配额 |
| 订阅后端（`12096/TCP`） | 3x-ui HTTP 订阅服务，严格绑定 `127.0.0.1` | **严禁**在云防火墙或主机防火墙中开放 |
| 管理面板（`7777/TCP`，默认） | 仅绑定 `127.0.0.1`（`PANEL_HTTPS=false`），通过 SSH 隧道访问 | **默认且推荐**；零公网面板暴露，无需维护动态 IP 白名单 |
| 管理面板（`7777/TCP`，可选） | 显式设置 `PANEL_HTTPS=true` 时监听 `0.0.0.0` 并启用域名 HTTPS | 仅按需开启；配备随机路径与强随机账号密码 |
| 证书验证（`80/TCP`） | Certbot 仅在申请与自动续期时临时监听 | 防火墙需保持放行，平时无进程监听属正常现象 |

> **IPv6 检查**：如果 VPS 分配了公网 IPv6 地址，请单独检查 IPv6 监听与防火墙规则（`ss -lntup`），不要只核对 IPv4。

---

## 2. 订阅网关访问控制

`3x-ui-subscription.service` 使用独立的 Nginx 配置（`/var/lib/3x-ui-bootstrap/nginx.conf`）执行严格的白名单放行策略：

- **精确路径白名单**：仅转发当前活跃客户端的完整 `/sub/<id>` 与 `/mihomo/<id>` 路径；校验原始未归一化 `$request_uri`、请求 `Host` 与请求方法。
- **最小暴露面**：仅允许 `GET` 与 `HEAD` 方法。根路径（`/`）、`/assets/`、目录列表、无效 ID、编码路径变体、查询参数（如 `?html=1`）以及 3x-ui 的浏览器展示页全部直接返回 `404`，请求不会到达订阅后端。
- **请求/响应头净化**：仅向后端透传客户端 `User-Agent`（固定 `Host` 与 `Accept: */*`），丢弃 `Cookie`、`Authorization`、`X-Forwarded-For` 等请求头；响应隐藏 `Profile-Web-Page-Url`，同时完整保留客户端所需的 `Subscription-Userinfo` 流量头和 `Profile-Update-Interval`。
- **限流与日志轮转**：有效订阅下载按来源 IP 限制为平均 `1 req/s`（突发 `20`、最大并发连接 `16`），超限返回 `429`。默认关闭访问日志；错误日志由 `logrotate` 按日检查并在超过 `10 MiB` 时轮转（保留 7 份，权限 `0600`）。

> **妥善保管订阅链接**：任何持有完整 `/sub/<id>` 或 `/mihomo/<id>` URL 的人均可获取对应节点配置与流量状态。请勿公开分享订阅链接、VLESS URI、二维码或包含上述信息的截图。

如需增删线路或修改配置，请统一使用 `install-3x-ui.sh` 提供的维护命令，以免受管订阅 ID 与 Nginx 白名单规则脱节。

---

## 3. 凭据保护、文件权限与证书校验

- **首次启动前写入随机凭据**：安装器在首次启动 `x-ui` 前即写入随机管理员用户名、高强度随机密码与随机面板 Base Path，绝不使用默认的 `admin/admin` 暴露服务。
- **严格的文件权限**：
  - 本地与 VPS 上的私有 `config.json` 权限必须为 `600` 或更严格（`chmod 600 config.json`）。
  - 状态目录 `/var/lib/3x-ui-bootstrap` 属主为 `root`、权限 `700`，内部保存了数据库备份、状态、部署结果（`result.txt`）及包含订阅 ID 的 Nginx 配置。对外反馈问题时请先脱敏，切勿直接粘贴完整日志或 `nginx -T` 输出。
- **仓库安全规则**：`.gitignore` 已忽略常见私密文件名（`config.json`、`result.txt`、`*.log`、`*.pem`、`*.key` 等），提交代码前仍请检查 `git status` 与暂存内容。
- **证书强校验**：订阅入口仅启用 TLS 1.2 / 1.3。每次启动或证书续期重载前，前置守卫脚本会自动核对域名/IP SAN 匹配、证书有效期、完整证书链及私钥匹配性。

---

## 4. 内置组件安全基线与用户职责

所有核心下载包在执行前均会核验内置 SHA-256 摘要：

- **3x-ui（`v3.11.0`）**：包含上游已修复的历史面板与订阅安全补丁。
- **Xray-core（默认 `26.10.31`）**：默认关闭 MPTCP 以减少额外暴露面（`26.6.27` 仅作为旧版客户端兼容选项提供）。
- **Certbot（`5.9.0`）**：固定摘要的官方 wheel 包，安装于隔离的 Python 虚拟环境中。
- **Nginx**：由 Ubuntu / Debian 官方软件源安装维护。

### 仍需由管理员自行维护的事项

1. **系统与内核补丁**：更新 Xray 或 3x-ui 不会自动修复 Linux 内核或系统软件包漏洞。请定期运行 `apt update && apt upgrade`，并在出现 `/run/reboot-required` 时及时重启服务器。
2. **SSH 与防火墙加固**：安装脚本不会改动 `sshd` 配置或防火墙规则。请确认 SSH 密钥登录可用后再关闭密码登录，并同时核查云控制台安全组与本机防火墙（`ufw` / `nftables`）。
3. **公网可观测特征**：`server_tokens off` 会隐藏 Nginx 版本号，拦截静态资源可减少直接识别，但开放端口、TLS 证书域名/IP 以及机房 ASN 归属（例如 [MaxMind 代理信誉分类](https://support.maxmind.com/knowledge-base/articles/anonymizer-and-proxy-data-maxmind)）在公网上依然可被观察。

---

## 5. 部署安全自检清单

新机部署完成、更换域名或调整线路后，可从外部电脑（**请先临时关闭本机代理或 TUN 模式**）逐项核对以下安全边界：

1. **订阅路径隔离**：
   - `curl -I https://<SUB_HOST>:38443/` → 应返回 `404`
   - `curl -I https://<SUB_HOST>:38443/assets/` → 应返回 `404`
   - `curl -I https://<SUB_HOST>:38443/sub/invalid-id` → 应返回 `404`
   - `curl -I "https://<SUB_HOST>:38443/sub/<VALID_ID>?html=1"` → 应返回 `404`
2. **内部后端与默认面板不可直连**：
   - 尝试从公网访问 `<SERVER_IP>:12096` → 应超时或被拒绝。
   - 若 `PANEL_HTTPS=false`，尝试从公网访问 `<SERVER_IP>:7777` → 应超时或被拒绝。
3. **TLS 传输检查**：
   - 确认 `https://<SUB_HOST>:38443` 返回匹配 `SUB_DOMAIN`（或 `SERVER_IP`）的有效证书，且仅支持 TLS 1.2 / 1.3。
4. **REALITY 伪装检查**：
   - 从外部无凭据访问 `<SERVER_IP>:443`（指定 `Host: <REALITY_HOST>`），应只看到伪装目标站点响应，无 Xray 或 3x-ui 文本特征。
