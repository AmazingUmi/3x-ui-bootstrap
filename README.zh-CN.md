# 3X-UI Bootstrap

[项目首页](README.md) | 简体中文

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
客户端 ── 38443/TCP HTTPS ── Nginx ── 127.0.0.1:12096 HTTP ── 订阅后端
管理员 ── SSH 隧道 ── 127.0.0.1:7777 ── 管理面板（默认且推荐）
```

**默认且推荐 `PANEL_HTTPS=false`：面板仅本机监听，通过 SSH 密钥隧道管理，管理设备 IP 变化不需要更新来源白名单。** 域名可选；只有显式设置 `PANEL_HTTPS=true` 才会公开 HTTPS 面板。端口均可在新机配置中指定。订阅后端始终只绑定本机，不需要开放 `12096`。

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

当前为 **0.4.0-rc.1 测试候选版**。默认固定依赖：3x-ui **v3.11.0**、Xray-core **26.10.31**、Certbot **5.9.0**；Nginx 使用 Ubuntu / Debian 软件源中的版本。`XRAY_VERSION` 可显式选择 **26.6.27** 做兼容对照；使用 `--switch-core` 受控切换，不能在面板内任意更新核心。

2026-11-17 用户已确认本候选版部署可用；所选核心、客户端版本和分项验收结果未记录。安装器的订阅格式检查和本机 Xray 自测不能代替客户端验收。检查范围与历史反馈见[操作指南](docs/operations.zh-CN.md)和[安全说明](docs/security.zh-CN.md)。

默认订阅端口改为 `38443`，可以按需自定义；换端口不阻止全端口扫描，也不证明节点不会被 GFW 或信誉服务识别。系统安全更新、运行内核及重启状态需单独核对。

开发检查运行 `bash scripts/check.sh`。贡献与发布约定见[贡献说明](CONTRIBUTING.zh-CN.md)，版本变化见[更新记录](CHANGELOG.zh-CN.md)。

## 许可证与依赖

本项目采用 [MIT License](LICENSE)。第三方项目遵循各自的许可证，本仓库不包含其发行二进制。

依赖：[3x-ui](https://github.com/MHSanaei/3x-ui)、[Xray-core](https://github.com/XTLS/Xray-core)、[Certbot](https://github.com/certbot/certbot)、[Nginx](https://nginx.org/)。
