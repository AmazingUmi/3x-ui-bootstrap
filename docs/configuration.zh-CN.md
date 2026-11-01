# 参数配置介绍

[English](configuration.md) | [操作指南](operations.zh-CN.md) | [安全说明](security.zh-CN.md) | [项目首页](../README.md)

配置模板为 [config.example.json](../config.example.json)，使用 `--config FILE` 指定私有配置文件；默认读取脚本同目录的 `config.json`。下文列出全部 19 个公开字段，省略可选字段时使用默认值。

## 配置文件格式

- 使用 UTF-8 JSON 对象，大小不超过 64 KiB，文件权限为 `600` 或更严格。
- 端口使用整数，配额使用数字，`PANEL_HTTPS` 使用布尔值 `true` / `false`；不能把它们写成字符串。
- 不支持注释、重复字段、未知字段、`NaN` 或 `Infinity`。字段名称区分大小写。
- 字符串中的双引号、反斜杠按 JSON 规则转义。单引号、美元符号和反引号不需要 Shell 转义。
- 配置只作为数据读取，不执行命令，也不接受 `BOOTSTRAP_*` 环境变量覆盖。私密文件和链接的保管方式见[安全说明](security.zh-CN.md)。

## 必填项速查

| 场景 | 必须填写 |
| --- | --- |
| 所有部署 | `SERVER_IP`：新 VPS 的静态公网 IPv4 |
| `NODE_MODE="isp"` 或 `"direct+isp"` | `ISP_HOST`、`ISP_PORT`、`ISP_USERNAME`、`ISP_PASSWORD` |
| `PANEL_HTTPS=true` | `SUB_DOMAIN` |
| 双线路且 `TOTAL_MONTHLY_GB>0` | `ISP_MONTHLY_GB`，并满足 `0 < ISP_MONTHLY_GB < TOTAL_MONTHLY_GB` |

默认使用 Direct、SSH 面板和不限流量，只需填写 `SERVER_IP` 即可安装。

## VPS 与线路

| 字段 | 类型 | 默认值 | 含义与约束 |
| --- | --- | --- | --- |
| `SERVER_IP` | 字符串 | 无，必填 | VPS 静态公网 IPv4；不接受私网、保留地址或占位符 |
| `NODE_NAME` | 字符串 | `"MyNode"` | 昵称，1–64 字符；不能包含空白、`/`、`\` 或控制字符 |
| `NODE_MODE` | 字符串 | `"direct"` | 仅允许 `direct`、`isp`、`direct+isp` |
| `REALITY_HOST` | 字符串 | `"www.cloudflare.com"` | REALITY 目标与 SNI；填写域名，不带协议、端口或路径；不要求拥有该域名 |

`direct` 使用 VPS 出口，`isp` 使用上游代理出口，`direct+isp` 同时提供两条线路。所有模式共用一个 `NODE_PORT` 入站；双线路以独立 UUID 认证并路由到不同出口，客户端显示名为 `<昵称>-Direct`、`<昵称>-ISP`。修改客户端应用里的显示名不会改变出口。

安装预检会验证 REALITY 目标的 TLS 1.3 和 HTTP/2 支持。

## ISP 上游

以下字段仅在包含 ISP 的模式中生效。Direct 模式保持默认空值即可。

| 字段 | 类型 | 默认值 | 含义与约束 |
| --- | --- | --- | --- |
| `ISP_HOST` | 字符串 | `""` | ISP 模式必填；上游 IP 或域名，不带协议、端口或路径 |
| `ISP_PORT` | 整数或 `null` | `null` | ISP 模式必填；1–65535，是 VPS 连接上游的端口，不是本机入站端口 |
| `ISP_USERNAME` | 字符串 | `""` | ISP 模式必填；不能含控制字符；HTTP 代理用户名不能含 `:` |
| `ISP_PASSWORD` | 字符串 | `""` | ISP 模式必填；不能含控制字符 |
| `ISP_PROTOCOL` | 字符串 | `"socks5"` | `socks5` 或 `http`，与供应商提供的协议一致 |
| `ISP_EXPECTED_IP` | 字符串 | `""` | 可选的预期出口公网 IPv4；填写后实际出口必须一致，动态出口可留空 |

SOCKS5 的用户名和密码各自按 UTF-8 编码后不能超过 255 字节。`ISP_HOST` 是代理入口，`ISP_EXPECTED_IP` 是实际出口，两者可以不同。ISP 出口始终要求与 `SERVER_IP` 不同。

ISP 线路支持 TCP，UDP 明确阻断；上游失败时不会自动改走 Direct。上游账号和密码不会写入客户端订阅。

## 域名与面板

| 字段 | 类型 | 默认值 | 含义与约束 |
| --- | --- | --- | --- |
| `SUB_DOMAIN` | 字符串 | `""` | 自有域名，不带协议、端口或路径；留空时订阅使用 VPS 公网 IP 和 HTTPS 证书 |
| `PANEL_HTTPS` | 布尔值 | `false` | `false`：面板只监听本机，经 SSH 隧道访问；`true`：使用域名公开 HTTPS 面板，必须填写 `SUB_DOMAIN` |
| `ACME_EMAIL` | 字符串 | `""` | 可选的证书联系邮箱；填写时须为有效邮箱格式 |

填写 `SUB_DOMAIN` 后，A 记录须直接指向 `SERVER_IP`。只填写域名、保持 `PANEL_HTTPS=false` 时，域名仅用于订阅，面板仍通过 SSH 隧道访问。公网面板与 Nginx 订阅使用同一域名和证书，各自保留独立端口。

`SUB_DOMAIN` 和 `REALITY_HOST` 会转换为小写；域名须包含点号、总长度不超过 253 字符，每段 1–63 字符，仅使用字母、数字和中间的连字符。

## 监听端口

| 字段 | 类型 | 默认值 | 监听位置与用途 |
| --- | --- | --- | --- |
| `NODE_PORT` | 整数 | `443` | 公网 VLESS + REALITY 入站，所有启用线路共用 |
| `PANEL_PORT` | 整数 | `7777` | 面板端口；默认仅本机，`PANEL_HTTPS=true` 时公开 |
| `SUB_PORT` | 整数 | `2096` | Nginx 公网 HTTPS 订阅入口，需要防火墙放行 |
| `SUB_BACKEND_PORT` | 整数 | `12096` | 3x-ui HTTP 订阅后端，仅绑定 `127.0.0.1`，**不要公网放行** |

四个监听端口均须为 1–65535 的整数，彼此不同，不能使用证书签发与续期所需的 `80/TCP`。VPS 预检还会检查它们是否与实际 SSH 端口或其他进程冲突。`ISP_PORT` 是出站目标端口，不受这四个本机监听端口的互斥限制。

默认订阅链路为 `公网 2096 HTTPS → Nginx → 127.0.0.1:12096 HTTP`。客户端下载和额度刷新使用公网 `SUB_PORT`；不要把后端端口填入客户端。访问控制规则见[安全说明](security.zh-CN.md)，放行和检查命令见[操作指南](operations.zh-CN.md)。

## 月流量配额

| 字段 | 类型 | 默认值 | 含义与约束 |
| --- | --- | --- | --- |
| `TOTAL_MONTHLY_GB` | 数字 | `0` | 总月预算，单位 GiB；`0` 表示不设总上限 |
| `ISP_MONTHLY_GB` | 数字 | `0` | ISP 月额度，单位 GiB；含义随线路模式变化，见下表 |

两项允许范围均为 `0–9999999.999`，最多三位小数；1 GiB = 1024³ 字节。令 `T` 为总预算、`I` 为 ISP 额度：

| 模式与设置 | Direct 额度 | ISP 额度 | 约束 |
| --- | --- | --- | --- |
| `direct` | `T`；`T=0` 时不限 | 无 ISP 线路 | `I` 必须为 `0` |
| `isp` | 无 Direct 线路 | `T`、`I` 中非零值的较小者；均为零则不限 | 可只设置其中一项 |
| `direct+isp`，`T>0` | `T−I` | `I` | 必须满足 `0<I<T` |
| `direct+isp`，`T=0` | 不限 | `I`；`I=0` 时不限 | 可单独限制 ISP |

使用面板原生客户端配额，超额后仅停用对应客户端。重置日沿用原部署日期，在面板时区的零点重置；短月取当月最后一天。两条线路不互借剩余额度，修改额度不会把重置日改为当天。客户端用量与供应商整机账单的统计范围不同。

## 配置示例

以下示例都是完整 JSON 对象，省略字段使用默认值。必须把 `YOUR_VPS_IP`、示例域名和上游凭据替换为实际信息；不能原样安装。

### 最小 Direct 配置

```json
{
  "SERVER_IP": "YOUR_VPS_IP"
}
```

该配置使用默认端口、IP HTTPS 订阅、SSH 面板和不限流量。

### Direct + ISP、域名订阅及公网 HTTPS 面板

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
  "PANEL_HTTPS": true,
  "ACME_EMAIL": "you@example.com",
  "TOTAL_MONTHLY_GB": 1000,
  "ISP_MONTHLY_GB": 100
}
```

此配置分配 Direct 900 GiB、ISP 100 GiB。若只需要域名订阅和 SSH 面板，把 `PANEL_HTTPS` 改为 `false`。

## 安装后如何应用修改

编辑 JSON 不会立即修改运行中的服务。当前版本的三类配置操作只读取各自负责的字段；完整命令见[操作指南](operations.zh-CN.md)。

对操作读取的字段，省略通常表示使用默认值，不表示保留服务器旧值；邮箱的例外见下表。维护时应使用与当前部署一致的完整候选配置，避免把最小安装示例直接用于修改现有线路。

| 操作 | 从 JSON 应用的字段 | 特别说明 |
| --- | --- | --- |
| `--configure-domain` | `SUB_DOMAIN`、`PANEL_HTTPS`、`ACME_EMAIL` | 域名必须非空；不能用此操作清空域名退回 IP 订阅。邮箱留空时保留原邮箱 |
| `--configure-nodes` | `NODE_NAME`、`NODE_MODE`、全部 `ISP_*` 字段、`TOTAL_MONTHLY_GB` | 包含 ISP 账号及配额；先同步 JSON，避免用旧参数覆盖面板中的修改 |
| `--configure-traffic` | `TOTAL_MONTHLY_GB`、`ISP_MONTHLY_GB` | 按当前已部署线路模式修改额度，保留计数和原部署重置日 |

三类操作都要求 JSON 中的 `SERVER_IP` 与部署记录一致。`NODE_PORT`、`PANEL_PORT`、`SUB_PORT`、`SUB_BACKEND_PORT` 和 `REALITY_HOST` 沿用部署记录，不通过这些操作修改；仅编辑 JSON 中的这些值不会生效。

`--repair-reality-target` 是单独的修复操作，使用保存的部署数据，将目标修复为 `www.cloudflare.com`，不读取 JSON 中的新目标。`--show`、`--traffic-status` 和 `--diagnose` 也使用服务器保存的数据，无需配置文件。

首次安装仅支持全新 VPS；当前版本安装中断可保留状态重试，不提供旧部署的原地迁移。部署、客户端验收及排查步骤统一见[操作指南](operations.zh-CN.md)。
