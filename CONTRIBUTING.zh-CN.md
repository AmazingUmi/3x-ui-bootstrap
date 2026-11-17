# 贡献说明

[English](CONTRIBUTING.md) | 简体中文

## 本地检查

需要 Bash、Python 3.10+ 和 Git。在仓库根目录运行：

~~~bash
bash scripts/check.sh
~~~

检查不申请证书、不安装软件、不连接真实 ISP、不修改系统服务。涉及发行包、面板 API、证书、路由或客户端兼容性的修改，需要额外记录 VPS / Shadowrocket / Mihomo 验收结果。

## 隔离发行包检查

`scripts/check-release.py` 只允许在一次性的 root Docker 容器内运行，并要求 `--network none`；拒绝宿主机或带非回环网卡的容器。它使用真实上游二进制验证 CLI／数据库／API 初始化、共享入站与原生配额、HTTPS 订阅、新旧核心切换及故障回退。人为注入的验收失败必须恢复原核心及可用订阅。它不覆盖 systemd 开机启动、真实 ACME 申请／续期、公网转发、ISP 出口或手机应用。

准备仅含公开 `install-3x-ui.sh`、`config.example.json`、`scripts/` 和 `tests/` 的源文件副本，以及目标架构的官方面板包、两个固定 Xray 包和 Certbot wheel。新发行包保留原文件名，历史 Xray 包文件名前加 `old-`；运行器执行前逐项校验摘要。用发行包目录作为构建上下文，通过 `scripts/release-check.Dockerfile` 缓存 Certbot 依赖。分别在 `linux/arm64` 和 `linux/amd64` 上，以 `--rm --network none`、不映射端口、只读挂载公开源文件到 `/src` 和发行包到 `/assets`，执行 `python3 /src/scripts/check-release.py --assets /assets`。不要挂载私有 `config.json`、宿主 Docker socket 或宿主服务／数据库目录。

## 修改约定

- 安装入口为 install-3x-ui.sh，用户设置仅来自独立 JSON；保留脚本和配置两个文件即可上传的方式。
- 不支持旧配置别名或 Shell source 配置。新增字段同步更新示例、文档和边界测试。
- 本候选版默认固定 Xray 26.10.31，允许显式选择固定摘要的 26.6.27 做兼容对照。保留发行包摘要与版本检查，不接受任意下载地址或自动追随 latest。历史 Shadowrocket 2.2.92（3345）+ Xray 26.6.27 结果不外推；正式发布新版前，必须记录 Shadowrocket 和 Mihomo 真机验收。
- 保留安装归属校验、失败续跑、已有客户端身份、流量计数和部署日，不盲目覆盖手工面板修改。
- ISP 失效不得自动回退 Direct。原生客户端配额和整机流量账单分开说明。
- 共享入站按认证客户端 email 路由；测试需覆盖同端口双客户端、独立订阅与配额、ISP UDP 阻断和未匹配客户端阻断。新拓扑仍需真实客户端验收，历史版本组合记录不能替代。
- 提交只包含示例数据；检查暂存区中的配置、日志、账号、订阅和密钥。

用户文档分为[操作指南](docs/operations.zh-CN.md)、[安全说明](docs/security.zh-CN.md)和[参数配置介绍](docs/configuration.zh-CN.md)。故障排查归入操作指南，README 保留项目概览与文档入口。三类文档保留英文版本及 `*.zh-CN.md` 简体中文版本，项目首页使用简体中文；命令、默认值、约束和验证记录需同步。

## 发布准备

本项目采用 [MIT License](LICENSE)。发布正式版本前，需记录该发布版本的 VPS 与客户端验收。2026-11-01 的部署反馈及版本边界见操作指南；仅有本地测试通过仍不能代表部署或客户端验收通过。
