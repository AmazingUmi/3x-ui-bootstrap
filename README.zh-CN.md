# 3X-UI Bootstrap

[English](README.md) | 简体中文

面向全新 Ubuntu / Debian VPS 的声明式一键部署工具。只需填写一份 `config.json` 并与 `install-3x-ui.sh` 一同上传，即可完成 **VLESS + REALITY** 节点、隔离的 **HTTPS 订阅网关** 与安全加固的 **3x-ui** 管理面板部署，同时提供自动化证书续期、原生月流量配额与安全的原地维护命令。

## 核心特性

- **灵活的线路模式（`direct`、`isp`、`direct+isp`）**：支持纯直连、纯 ISP 上游代理（SOCKS5 / HTTP），或双线路共用同一个 `443/TCP` 节点端口。双线路拥有独立的客户端 UUID、订阅链接与流量配额；ISP 上游故障时严格阻断，不会静默回退到直连。
- **默认最小暴露**：管理面板默认仅监听 `127.0.0.1`（`PANEL_HTTPS=false`），通过本地 SSH 隧道访问，无需暴露面板端口，也无需维护动态来源 IP 白名单；如需域名公网 HTTPS 访问可显式开启。
- **订阅后端隔离**：公网 HTTPS 订阅（默认 `38443/TCP`）由 Nginx 接管，3x-ui 订阅后端仅绑定 `127.0.0.1:12096`。网关仅放行当前活跃客户端的 `/sub/<id>` 与 `/mihomo/<id>` 精确下载路径，拒绝静态资源、目录枚举、无效 ID 及 HTML 展示页。
- **全自动 HTTPS 证书**：通过 Certbot 自动签发与续期 Let's Encrypt 证书，同时支持自定义域名（`SUB_DOMAIN`）与无域名公网 IPv4 短效证书。
- **原生月流量配额**：基于 3x-ui 原生客户端计量，按首次部署日期自动每月重置。`direct+isp` 模式下优先保障 ISP 预留额度，剩余预算自动分配给 Direct。
- **安全可续跑与受控维护**：所有上游发行包均校验 SHA-256 摘要；支持本地配置校验（`--validate-config`）、VPS 环境预检（`--check`）、中断后安全续跑，以及带自动回退的 Xray 核心切换（`--switch-core`）。

## 部署架构

```text
客户端 ── 443/TCP ────────── Xray (VLESS + REALITY) ── Direct / ISP 出口
客户端 ── 38443/TCP HTTPS ── Nginx 网关 ── 127.0.0.1:12096 HTTP ── 订阅后端
管理员 ── SSH 隧道 ────────── 127.0.0.1:7777 ────────────────────── 管理面板（默认）
```

> **提示**：默认情况下，公网防火墙只需放行节点端口（`443/TCP`）、订阅入口（`38443/TCP`）与证书验证端口（`80/TCP`）。切勿将内部订阅后端 `12096/TCP` 暴露到公网。

## 快速开始

**服务器要求**：全新的 **Ubuntu 22.04+** 或 **Debian 12+** VPS（`amd64` 或 `arm64`），带有 `systemd`、Python 3.10+、静态公网 IPv4 及 `sudo` 权限。

### 1. 在本地准备并校验配置文件

```bash
cp config.example.json config.json
chmod 600 config.json
# 编辑 config.json（最简 Direct 模式只需填写 SERVER_IP）
bash ./install-3x-ui.sh --config ./config.json --validate-config
```

### 2. 上传到 VPS 并执行环境预检

请确认云防火墙与系统防火墙已放行 `80/TCP`、`443/TCP` 和 `38443/TCP`（以及当前 SSH 端口）。若配置了 `SUB_DOMAIN`，请先将域名 `A` 记录直接解析到 `SERVER_IP` 并关闭 CDN 代理。

```bash
scp ./install-3x-ui.sh ./config.json ubuntu@YOUR_VPS_IP:~/
ssh ubuntu@YOUR_VPS_IP

chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
```

### 3. 执行安装

```bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
```

安装完成后，终端会输出随机生成的面板账号密码、SSH 隧道命令、Mihomo / Shadowrocket 订阅链接以及 VLESS 链接（同时保存在 `/var/lib/3x-ui-bootstrap/result.txt`）。

## 文档导航

| 文档 | 内容 | English |
| --- | --- | --- |
| [操作指南](docs/operations.zh-CN.md) | 新机安装、客户端导入、日常维护命令与常见问题排查 | [Operations Guide](docs/operations.md) |
| [参数配置](docs/configuration.zh-CN.md) | 全部 20 个配置字段说明、默认值、约束与配置示例 | [Configuration Reference](docs/configuration.md) |
| [安全说明](docs/security.zh-CN.md) | 服务隔离边界、订阅访问控制、凭据保护与自检清单 | [Security Guide](docs/security.md) |
| [更新日志](CHANGELOG.zh-CN.md) | 版本发布历史与功能变更记录 | [Changelog](CHANGELOG.md) |
| [贡献指南](CONTRIBUTING.zh-CN.md) | 本地测试、容器集成验证与开发修改约定 | [Contributing](CONTRIBUTING.md) |

## 内置上游组件版本

当前版本：**0.4.0-rc.1**（预发布版）

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| [3x-ui](https://github.com/MHSanaei/3x-ui) | `v3.11.0` | 官方发行包，内置 SHA-256 校验 |
| [Xray-core](https://github.com/XTLS/Xray-core) | `26.10.31` | 默认版本；可在配置中指定 `26.6.27` 以兼容旧版客户端 |
| [Certbot](https://github.com/certbot/certbot) | `5.9.0` | 官方 wheel 包，内置 SHA-256 校验并安装于独立 venv |
| [Nginx](https://nginx.org/) | 系统源版本 | 通过 Ubuntu / Debian APT 安装 |

## 许可证

本项目采用 [MIT License](LICENSE) 开源。所集成的第三方上游软件遵循其各自的开源许可证，本仓库不包含第三方二进制发行文件。
