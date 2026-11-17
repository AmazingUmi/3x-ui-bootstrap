# 参数配置说明

[English](configuration.md) | 简体中文 · [项目首页](../README.zh-CN.md) · [操作指南](operations.zh-CN.md) · [安全说明](security.zh-CN.md)

请先复制模板 [config.example.json](../config.example.json) 生成自己的配置文件。可通过 `--config FILE` 指定路径；省略时默认读取与 `install-3x-ui.sh` 同目录下的 `config.json`。下文列出全部 20 个公开配置字段，省略的可选字段均会自动使用默认值。

## 配置文件格式要求

- 必须为有效的 UTF-8 JSON 对象，文件大小不超过 **64 KiB**，文件权限须设为 `600` 或更严格（`chmod 600 config.json`）。
- 端口号为 JSON 整数，流量配额为 JSON 数字，`PANEL_HTTPS` 为 JSON 布尔值（`true` / `false`），请勿加引号写成字符串。
- 不支持注释、重复字段、未知字段、`NaN` 或 `Infinity`；字段名区分大小写。
- 字符串中的双引号和反斜杠按标准 JSON 规则转义；单引号、`$` 和反引号无需额外做 Shell 转义。
- 配置文件仅作为纯数据解析，不会被当作 Shell 脚本执行，也不接受 `BOOTSTRAP_*` 环境变量覆盖。

## 必填字段速查

| 使用场景 | 必须填写的字段 |
| --- | --- |
| 所有部署 | `SERVER_IP`（VPS 的静态公网 IPv4 地址） |
| `NODE_MODE="isp"` 或 `"direct+isp"` | `ISP_HOST`、`ISP_PORT`、`ISP_USERNAME`、`ISP_PASSWORD` |
| `PANEL_HTTPS=true` | `SUB_DOMAIN` |
| 双线路且 `TOTAL_MONTHLY_GB > 0` | `ISP_MONTHLY_GB`，并满足 `0 < ISP_MONTHLY_GB < TOTAL_MONTHLY_GB` |

使用默认设置（`direct` 直连、SSH 隧道管理面板、不限流量）时，只需填写 `SERVER_IP`。

## 服务器与线路配置

| 字段 | 类型 | 默认值 | 说明与约束 |
| --- | --- | --- | --- |
| `SERVER_IP` | 字符串 | 必填 | VPS 静态公网 IPv4 地址；拒绝内网地址、保留地址和示例占位符 |
| `NODE_NAME` | 字符串 | `"MyNode"` | 节点显示昵称，1–64 个字符；不能含空白字符、`/`、`\` 或控制字符 |
| `NODE_MODE` | 字符串 | `"direct"` | 路由模式：`"direct"`、`"isp"` 或 `"direct+isp"` |
| `REALITY_HOST` | 字符串 | `"www.cloudflare.com"` | REALITY 伪装目标与 SNI 域名（仅填域名，不带协议、端口或路径，无需拥有该域名） |

- `direct` 通过 VPS 本机出口；`isp` 通过指定的上游代理出口；`direct+isp` 在同一个 `NODE_PORT` 上同时提供两条线路，使用独立的 UUID 与订阅链接（节点名分别为 `<NODE_NAME>-Direct` 和 `<NODE_NAME>-ISP`）。
- 在客户端应用内手动重命名节点不会改变服务端路由出口。
- 执行 `--check` / `--install` 时会自动探测 `REALITY_HOST` 是否支持 TLS 1.3 和 HTTP/2。

## Xray 核心版本

| 字段 | 类型 | 默认值 | 说明与约束 |
| --- | --- | --- | --- |
| `XRAY_VERSION` | 字符串 | `"26.10.31"` | 仅允许 `"26.10.31"`（默认）或 `"26.6.27"`（旧版客户端兼容）；两者均内置官方 SHA-256 校验摘要，不支持 `latest` 或自定义下载地址 |

用于新机安装，以及通过 `--switch-core` 在线安全切换核心版本。其他维护命令均保持当前已部署的 Xray 核心不变。日常建议保持默认的 `26.10.31`。

## ISP 上游代理

仅在 `NODE_MODE` 包含 `isp` 时生效；纯 `direct` 模式保持默认空值即可。

| 字段 | 类型 | 默认值 | 说明与约束 |
| --- | --- | --- | --- |
| `ISP_HOST` | 字符串 | `""` | ISP 模式必填；上游代理 IP 或域名（不带协议、端口或路径） |
| `ISP_PORT` | 整数或 `null` | `null` | ISP 模式必填；`1–65535`（上游代理连接端口） |
| `ISP_USERNAME` | 字符串 | `""` | ISP 模式必填；不能含控制字符（HTTP 代理用户名不能含 `:`） |
| `ISP_PASSWORD` | 字符串 | `""` | ISP 模式必填；不能含控制字符 |
| `ISP_PROTOCOL` | 字符串 | `"socks5"` | `"socks5"` 或 `"http"`，需与上游供应商协议一致 |
| `ISP_EXPECTED_IP` | 字符串 | `""` | 可选的预期公网 IPv4 出口；填写后预检和运行时会强制校验实际出口一致；动态出口请留空 |

- SOCKS5 协议的用户名和密码按 UTF-8 编码后各不能超过 255 字节。
- `ISP_HOST` 是上游代理连接地址，`ISP_EXPECTED_IP` 是实际出口公网 IP（两者允许不同）；ISP 出口 IP 必须与 `SERVER_IP` 不同。
- ISP 线路仅转发 TCP 并明确阻断 UDP；上游故障时绝不会静默回退到 Direct。上游账号密码不会出现在客户端订阅链接中。

## 域名与管理面板

| 字段 | 类型 | 默认值 | 说明与约束 |
| --- | --- | --- | --- |
| `SUB_DOMAIN` | 字符串 | `""` | 自定义域名（不带协议、端口或路径）；留空时使用公网 IPv4 短效 HTTPS 证书 |
| `PANEL_HTTPS` | 布尔值 | `false` | **推荐** `false`：面板仅监听 `127.0.0.1`，经 SSH 隧道管理；`true`：公开域名 HTTPS 面板（必须填写 `SUB_DOMAIN`） |
| `ACME_EMAIL` | 字符串 | `""` | 可选的 Let's Encrypt 证书通知邮箱；填写时须符合邮箱格式 |

- 填写 `SUB_DOMAIN` 时，其 `A` 记录必须直接指向 `SERVER_IP` 且关闭 CDN 代理。
- 你可以填写 `SUB_DOMAIN` 的同时保持 `PANEL_HTTPS=false`：此时订阅使用域名 HTTPS，管理面板依然隐藏在 SSH 隧道之后。
- `SUB_DOMAIN` 和 `REALITY_HOST` 会自动转换为小写（总长不超过 253 字符，符合域名规范）。

## 监听端口

| 字段 | 类型 | 默认值 | 监听范围与用途 |
| --- | --- | --- | --- |
| `NODE_PORT` | 整数 | `443` | 公网 VLESS + REALITY 入站端口，所有启用线路共用 |
| `PANEL_PORT` | 整数 | `7777` | 管理面板端口（默认仅 `127.0.0.1`，开启 `PANEL_HTTPS=true` 时对外监听） |
| `SUB_PORT` | 整数 | `38443` | Nginx 公网 HTTPS 订阅网关端口 |
| `SUB_BACKEND_PORT` | 整数 | `12096` | 3x-ui 内部 HTTP 订阅后端（仅绑定 `127.0.0.1`，**严禁公网放行**） |

- 四个监听端口必须为 `1–65535` 之间互不相同的整数。
- 均不能占用 `80`（保留给 Certbot 证书签发与续期），也不能与 SSH 端口冲突。（`ISP_PORT` 属于出站目标端口，不受本机监听端口互斥限制。）
- 客户端订阅地址始终使用公网 `SUB_PORT`（`https://<SUB_HOST>:<SUB_PORT>/...`），切勿使用内部 `SUB_BACKEND_PORT`。

## 月流量配额

| 字段 | 类型 | 默认值 | 说明与约束 |
| --- | --- | --- | --- |
| `TOTAL_MONTHLY_GB` | 数字 | `0` | 每月总流量预算，单位 GiB（`0` 表示不限） |
| `ISP_MONTHLY_GB` | 数字 | `0` | ISP 线路月额度，单位 GiB（具体规则见下表） |

两者均允许 `0` 到 `9999999.999`，最多保留三位小数（`1 GiB = 1024³ 字节`）。令 `T = TOTAL_MONTHLY_GB`、`I = ISP_MONTHLY_GB`：

| 线路模式与配置 | Direct 额度 | ISP 额度 | 约束条件 |
| --- | --- | --- | --- |
| `direct` | `T`（`T = 0` 时不限） | — | `I` 必须为 `0` |
| `isp` | — | `T` 与 `I` 中非零值的较小者（均为 `0` 则不限） | 任选其一或同时设置 |
| `direct+isp`，`T > 0` | `T - I` | `I` | 必须满足 `0 < I < T` |
| `direct+isp`，`T = 0` | 不限 | `I`（`I = 0` 时不限） | 可单独限制 ISP 额度 |

- 采用 3x-ui 原生客户端计量：某条线路耗尽后仅停用该客户端，两条线路之间不互相借用剩余额度。
- 重置日固定为首次部署当天的日期（在面板时区的零点重置，短月自动取当月最后一天）；后续调整配额不会改变原有重置日。
- 客户端统计口径与 VPS 商家整机网卡流量账单可能存在差异。

## 配置示例

所有示例省略的字段会自动取默认值。使用前请务必把 `YOUR_VPS_IP`、示例域名和代理账号替换为真实信息。

### 最简 Direct 配置

```json
{
  "SERVER_IP": "YOUR_VPS_IP"
}
```

使用默认端口（`443` / `38443` / `7777` / `12096`）、IP HTTPS 订阅、SSH 隧道管理面板以及不限流量。

### Direct + ISP 双线路（自定义域名订阅 + SSH 面板）

```json
{
  "SERVER_IP": "YOUR_VPS_IP",
  "NODE_NAME": "MyNode",
  "NODE_MODE": "direct+isp",
  "ISP_PROTOCOL": "socks5",
  "ISP_HOST": "proxy.example.com",
  "ISP_PORT": 1080,
  "ISP_USERNAME": "YOUR_ISP_USERNAME",
  "ISP_PASSWORD": "YOUR_ISP_PASSWORD",
  "SUB_DOMAIN": "node.example.com",
  "PANEL_HTTPS": false,
  "ACME_EMAIL": "you@example.com",
  "TOTAL_MONTHLY_GB": 1000,
  "ISP_MONTHLY_GB": 100
}
```

分配 `900 GiB` 给 Direct、`100 GiB` 给 ISP，通过 `node.example.com:38443` 提供 HTTPS 订阅，管理面板保持仅本机 SSH 隧道访问。

## 部署后更新配置

仅修改 `config.json` 不会自动影响正在运行的服务，需在 VPS 上执行对应的维护命令使相应字段生效。

建议始终维护一份与当前线上部署一致的完整 `config.json`——因为各变更命令对于所负责的字段，若在 JSON 中省略通常会重置为默认值（仅 `ACME_EMAIL` 留空时保留原值）。

| 命令 | 从 `config.json` 读取的字段 | 说明 |
| --- | --- | --- |
| `--switch-core` | `XRAY_VERSION` | 切换内置校验版 Xray 核心（失败自动回退），保留数据库、节点身份与配额 |
| `--configure-domain` | `SUB_DOMAIN`、`PANEL_HTTPS`、`ACME_EMAIL` | `SUB_DOMAIN` 须非空；`ACME_EMAIL` 留空时保留原有邮箱 |
| `--configure-nodes` | `NODE_NAME`、`NODE_MODE`、全部 `ISP_*` 字段、`TOTAL_MONTHLY_GB`、`ISP_MONTHLY_GB` | 若曾在网页面板修改过 ISP 凭据，请先同步到 `config.json` |
| `--configure-traffic` | `TOTAL_MONTHLY_GB`、`ISP_MONTHLY_GB` | 按当前已部署模式更新月配额，保留已用流量与原重置日 |

- 上述四个命令均会校验配置中的 `SERVER_IP` 是否与当前服务器一致。
- 四个监听端口（`NODE_PORT`、`PANEL_PORT`、`SUB_PORT`、`SUB_BACKEND_PORT`）及 `REALITY_HOST` 在首次安装时确定，不能通过上述命令修改。
- `--repair-reality-target`、`--show`、`--traffic-status` 与 `--diagnose` 直接读取服务器保存的状态，无需提供 `--config`。具体维护方法见[操作指南](operations.zh-CN.md)。
