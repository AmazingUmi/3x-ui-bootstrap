# 更新日志

[English](CHANGELOG.md) | 简体中文

本文件记录项目面向用户的主要功能更新与安全变更。

## 0.4.0-rc.1 — 2026-11-17（预发布版）

### 变更
- 将默认且推荐的面板访问模式明确为仅监听 `127.0.0.1` 并通过 SSH 隧道访问（`PANEL_HTTPS=false`）。
- 将 Nginx 公网 HTTPS 默认订阅端口（`SUB_PORT`）从 `2096` 调整为 `38443`，继续支持自定义端口并保持订阅后端仅监听 `127.0.0.1:12096`。
- 升级内置校验的官方组件版本：**3x-ui v3.11.0**、**Xray-core 26.10.31**（默认）与 **Certbot 5.9.0**（均锁定 `amd64` / `arm64` SHA-256 摘要）。

### 新增
- 新增 `XRAY_VERSION` 配置字段与 `--switch-core` 命令，支持在 `26.10.31` 与 `26.6.27` 之间安全切换；切换前先下载并校验新旧压缩包，失败时自动回退且不影响数据库、节点身份与流量配额。
- 为 Nginx 订阅网关新增按来源 IP 限流与并发限制（`1 req/s`、突发 `20`、最多 `16` 个活跃连接）以及错误日志 `logrotate` 自动轮转。
- 在 `--check` 预检中新增系统版本、运行内核、待重启标记与 SSH 基础认证方式只读提示（不自动修改系统或 SSH 配置）。

---

## 0.3.0 — 2026-11-01

### 新增
- 引入 Nginx 托管公网 HTTPS 订阅入口（`3x-ui-subscription.service`），将 3x-ui HTTP 订阅后端严格隔离在 `127.0.0.1:12096`（`SUB_BACKEND_PORT`）。
- 仅放行活跃客户端的精确 `/sub/<id>` 与 `/mihomo/<id>` 下载地址（仅 `GET`/`HEAD`），拦截静态资源、HTML 展示页、无效 ID 与查询参数变体，同时保留客户端所需格式与 `Subscription-Userinfo` 流量头。
- 将用户文档重构为[操作指南](docs/operations.zh-CN.md)、[参数配置](docs/configuration.zh-CN.md)与[安全说明](docs/security.zh-CN.md)。

---

## 0.2.0 — 2026-10-31

### 新增
- 将 Direct 与 ISP 整合为共用单个 VLESS + REALITY 入站（`NODE_PORT`，默认 `443`），通过独立客户端 UUID 认证后按 `user` 规则分流至对应出口。
- 保留各线路独立的订阅 ID、节点名称（`<NODE_NAME>-Direct` / `<NODE_NAME>-ISP`）与原生月流量配额；ISP 线路阻断 UDP 且上游故障不回退到 Direct。
- 添加 [MIT License](LICENSE) 开源许可。

---

## 0.1.0 — 2026-10-22

### 新增
- 初始化独立项目 `3X-UI Bootstrap`，引入严格 JSON 配置（`--config`）、`config.example.json` 示例及敏感文件 `.gitignore` 规则。
- 新增无需 root 与网络的本地配置校验（`--validate-config`）。
- 支持 Direct / ISP / Direct + ISP 路由、绑定部署日重置的原生月流量配额以及自动化 Let's Encrypt HTTPS 证书签发与续期。
