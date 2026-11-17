# 贡献指南

[English](CONTRIBUTING.md) | 简体中文

感谢你关注并参与 **3X-UI Bootstrap** 的开发与维护。

## 本地测试

运行环境需要 **Bash**、**Python 3.10+** 与 **Git**（本机安装 `nginx` 与 `openssl` 后还可运行真实本地 Nginx 网关集成测试）。

在仓库根目录运行：

```bash
bash scripts/check.sh
```

离线测试覆盖 Shell / Python 语法、JSON 示例校验、配置边界、分流路由规则、原生流量配额、核心切换回退逻辑与本地 Nginx 访问控制；不会申请真实证书、修改系统服务或连接真实 ISP 上游。

## 容器化发行包冒烟测试

`scripts/check-release.py` 用于在无网络的一次性 root Docker 容器（`--network none`）中使用真实 `x-ui`、`xray` 和 `certbot` 二进制验证完整安装链路，包括 CLI/数据库初始化、共享入站、原生配额、HTTPS 订阅导出、双向核心切换与故障自动回退。

在 `linux/amd64` 或 `linux/arm64` 上运行步骤如下：

1. 准备仅包含公开文件（`install-3x-ui.sh`、`config.example.json`、`scripts/`、`tests/`）的源码目录；切勿挂载私有 `config.json`、宿主机 Docker socket 或宿主状态目录。
2. 准备资产目录，放入目标架构的 `x-ui` 官方压缩包、两个固定版本 Xray 压缩包（`26.6.27` 文件名前加 `old-`）以及 `Certbot` wheel 包（运行前会自动校验全部 SHA-256 摘要）。
3. 以资产目录作为构建上下文构建 `scripts/release-check.Dockerfile`（用于离线缓存 Certbot 依赖）。
4. 使用 `--rm --network none` 且不映射端口启动容器，将公开源码只读挂载到 `/src`、资产只读挂载到 `/assets` 并执行：

```bash
python3 /src/scripts/check-release.py --assets /assets
```

## 设计与安全约定

提交 PR 时请务必保持以下核心约束不变：

- **单脚本 + 纯 JSON 边界**：`install-3x-ui.sh` 为唯一部署入口，配置仅作为纯数据解析，不支持 Shell source 或旧字段别名。增删配置字段时需同步更新 `config.example.json`、中英文文档及边界测试。
- **固定版本与摘要校验**：所有上游发行包必须显式固定版本号并核验 SHA-256 摘要，不接受任意下载 URL 或自动追随 `latest`。
- **可续跑与状态保护**：保留安装归属校验、失败断点续跑、已有客户端 UUID / 订阅 ID、流量统计与原部署重置日，不盲目覆盖手工配置。
- **严格分流隔离**：ISP 上游失效绝不自动回退 Direct；共享入站必须按客户端 email（`user`）精确分流、阻断 ISP UDP 并拒绝未匹配客户端。
- **严禁提交私密信息**：仓库内仅保留示例占位符；提交前请检查暂存区，确保不含真实 IP、凭据、密钥或私有日志。

## 文档维护规范

项目所有文档均需同步维护英文版（`*.md`）与简体中文版（`*.zh-CN.md`），包括 `README*`、`CHANGELOG*`、`CONTRIBUTING*` 以及 `docs/{operations,configuration,security}*`。请确保双语文档中的命令、默认值、字段约束保持一致，并将故障排查内容统一放在操作指南中。

## 发布检查清单

项目遵循 [MIT License](LICENSE)。在发布正式版本标签前请完成以下检查：

1. 确保 `bash scripts/check.sh` 在受支持的 Python 版本上全部通过。
2. 在 `amd64` 与 `arm64` 容器环境中通过 `scripts/check-release.py` 验证。
3. 在真实全新 VPS 上完成部署、ACME 证书申请、Direct / ISP 出口以及客户端（Mihomo、Shadowrocket）实机连通性验证。
