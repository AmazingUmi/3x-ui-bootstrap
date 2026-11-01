# 3X-UI Bootstrap

面向全新 Ubuntu / Debian VPS 的一键部署工具。填写 JSON 配置，上传脚本和配置文件，即可部署 VLESS + REALITY 节点、HTTPS 订阅和管理面板。

支持 Direct、ISP、Direct + ISP 三种模式。Direct 与 ISP 共用节点端口，使用独立身份、出口和流量配额；ISP 使用指定的 SOCKS5 / HTTP 上游，失效时不会回退到 Direct。

## 文档

| 文档 | 内容 | English |
| --- | --- | --- |
| [操作指南](docs/operations.zh-CN.md) | 新机安装、客户端导入、验收、日常维护和故障排查 | [Operations guide](docs/operations.md) |
| [安全说明](docs/security.zh-CN.md) | 公网暴露、订阅隔离、凭据保护、版本公告和安全复测记录 | [Security notes](docs/security.md) |
| [参数配置介绍](docs/configuration.zh-CN.md) | 必填项、默认值、参数约束、配置示例和修改范围 | [Configuration reference](docs/configuration.md) |

首次部署从操作指南开始；填写配置时查参数介绍；上线前阅读安全说明。

## 部署结构

```text
客户端 ── 443/TCP ── Xray VLESS + REALITY ── Direct / ISP 出口
客户端 ── 2096/TCP HTTPS ── Nginx ── 127.0.0.1:12096 HTTP ── 订阅后端
管理员 ── SSH 隧道 ── 127.0.0.1:7777 ── 管理面板（默认）
```

域名可选；启用 `PANEL_HTTPS` 后，面板改为公网域名 HTTPS 入口。端口均可在新机配置中指定。订阅后端始终只绑定本机，不需要开放 `12096`。

## 快速入口

在新 VPS 上完成配置上传、域名解析和防火墙准备后执行：

```bash
chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
```

检查通过后安装：

```bash
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
```

完整准备步骤见[操作指南](docs/operations.zh-CN.md)。仅支持新机部署和本版本安装中断后重试，不迁移旧部署。

## 版本与验证

项目版本为 **0.3.0**。固定依赖：3x-ui **v3.10.2**、Xray-core **26.6.27**、Certbot **5.8.0**；Nginx 使用 Ubuntu / Debian 软件源中的版本。

2026-11-01 已收到新部署正常使用的反馈，并完成公网 IPv4 订阅暴露复测。客户端具体版本及未覆盖项目见[操作指南](docs/operations.zh-CN.md)和[安全说明](docs/security.zh-CN.md)。3x-ui 3.10.2 涉及上游已公布的安全问题，适用条件与修复版本也列在安全说明中。

开发检查运行 `bash scripts/check.sh`。贡献与发布约定见[贡献说明](CONTRIBUTING.zh-CN.md)，版本变化见[更新记录](CHANGELOG.zh-CN.md)。

## 许可证与依赖

本项目采用 [MIT License](LICENSE)。第三方项目遵循各自的许可证，本仓库不包含其发行二进制。

依赖：[3x-ui](https://github.com/MHSanaei/3x-ui)、[Xray-core](https://github.com/XTLS/Xray-core)、[Certbot](https://github.com/certbot/certbot)、[Nginx](https://nginx.org/)。
