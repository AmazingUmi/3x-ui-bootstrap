# 更新记录

[English](CHANGELOG.md) | 简体中文

## 0.2.0 — 未发布

- Direct 和 ISP 改为共用一个 VLESS + REALITY 入站（默认 443），通过独立客户端 UUID 认证后按 `user` 规则分别选择出口。
- 保留独立订阅 ID、节点名称与原生月配额；共享入站共用 REALITY 密钥，ISP UDP 继续阻断，ISP 失败不回退 Direct。
- 所有模式统一使用一个 `NODE_PORT`，同步更新防火墙清单。
- 新共享入站拓扑尚待真实 VPS / Shadowrocket / Mihomo 验收；保留固定的 Xray 26.6.27。

- 补充历史已验证的 Shadowrocket 2.2.92（3345）+ Xray 26.6.27 组合，明确其他 Shadowrocket / Xray 组合尚未验证。
- 添加 MIT License，并同步更新中英文授权说明。

## 0.1.0 — 2026-10-22

- 从既有 3X-UI 一键脚本初始化独立项目。
- 用户配置改为 --config 指定的 JSON 文件，补充公开示例和敏感文件忽略规则。
- 增加无需 root / 网络的 --validate-config、严格字段及类型校验。
- 保留 3x-ui v3.10.2、Xray 26.6.27、Direct / ISP 路由、原生配额及原部署日重置逻辑。
- 增加配置、使用、故障排查说明和离线测试 / CI。

本次配置入口重构尚未在真实 VPS 部署；历史部署结果不作为此版本的新验收记录。
