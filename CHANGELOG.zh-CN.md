# 更新记录

[English](CHANGELOG.md) | 简体中文

日期按对应版本提交到仓库 `main` 分支的时间记录。

## 0.3.0 — 2026-11-01

- 公网 HTTPS 订阅端口（默认 2096）交由 Nginx 接管，3x-ui 的 HTTP 订阅后端仅监听 `127.0.0.1`，使用 `SUB_BACKEND_PORT`（默认 12096）。
- 仅放行受管客户端的精确订阅下载 URL，允许 GET 或 HEAD；拒绝静态资源、目录列表、无效 ID 和其他公开路径，不提供浏览器订阅展示页。
- 保留 Mihomo / Shadowrocket 订阅下载与用量响应头；自动安装 Nginx，并同步适配证书续期、受管配置修改和运行检查。
- 面向全新 VPS，支持本版本安装中断后重试，不迁移旧部署。
- 用户文档统一为[操作指南](docs/operations.zh-CN.md)、[安全说明](docs/security.zh-CN.md)和[参数配置介绍](docs/configuration.zh-CN.md)；故障排查并入操作指南，README 精简为项目概览与文档入口。
- 增加真实本机 Nginx 访问控制测试和服务生命周期检查；记录上游安全公告、适用条件及公网暴露测试的边界。

验证结果：本地 **74 项检查全部通过**，[GitHub CI](https://github.com/AmazingUmi/3x-ui-bootstrap/actions/runs/41286644868) 的 **Python 3.10 和 3.13** 检查均通过。2026-11-01 新机部署已反馈正常使用；外部 IPv4 复测确认静态资源被拒绝、从测试网络无法连接订阅后端及 TLS 版本符合预期。本次未记录客户端版本；完整范围见安全说明，不能据此认定不存在漏洞或 IP 信誉标签。

## 0.2.0 — 2026-10-31

- Direct 和 ISP 改为共用一个 VLESS + REALITY 入站（默认 443），通过独立客户端 UUID 认证后按 `user` 规则分别选择出口。
- 保留独立订阅 ID、节点名称与原生月配额；共享入站共用 REALITY 密钥，ISP UDP 继续阻断，ISP 失败不回退 Direct。
- 所有模式统一使用一个 `NODE_PORT`，同步更新防火墙清单。
- 保留固定的 Xray 26.6.27；当时的新共享入站拓扑尚待真实 VPS / Shadowrocket / Mihomo 验收，后续部署反馈见 0.3.0 记录。
- 补充历史已验证的 Shadowrocket 2.2.92（3345）+ Xray 26.6.27 组合，明确其他 Shadowrocket / Xray 组合尚未验证。
- 添加 MIT License，并同步更新中英文授权说明。

## 0.1.0 — 2026-10-22

- 从既有 3X-UI 一键脚本初始化独立项目。
- 用户配置改为 --config 指定的 JSON 文件，补充公开示例和敏感文件忽略规则。
- 增加无需 root / 网络的 --validate-config、严格字段及类型校验。
- 保留 3x-ui v3.10.2、Xray 26.6.27、Direct / ISP 路由、原生配额及原部署日重置逻辑。
- 增加配置、使用、故障排查说明和离线测试 / CI。

记录 0.1.0 时，配置入口重构尚未在真实 VPS 部署；后续部署反馈见 0.3.0 记录。
