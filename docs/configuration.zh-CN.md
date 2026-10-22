# 配置说明

[English](configuration.md) | 简体中文

使用 `--config FILE` 指定 JSON 文件；默认读取脚本同目录的 `config.json`。配置文件只作为数据读取，不执行 Shell 内容，也不读取 `BOOTSTRAP_*` 环境变量作为配置。

配置必须是 UTF-8 JSON 对象，大小不超过 64 KiB，权限为 `600` 或更严格。未知字段、重复字段、错误类型和非标准 JSON 数值会被拒绝。

## 必填与可选速查

| 分类 | 需要填写的字段 | 生效条件 |
| --- | --- | --- |
| 始终必填 | `SERVER_IP` | 所有安装模式，替换为 VPS 静态公网 IPv4 |
| 选择 ISP 时必填 | `ISP_HOST`、`ISP_PORT`、`ISP_USERNAME`、`ISP_PASSWORD` | `NODE_MODE` 为 `isp` 或 `direct+isp` |
| 开启公网 HTTPS 面板时必填 | `SUB_DOMAIN` | `PANEL_HTTPS=true`；只使用 SSH 面板时可留空 |
| 双线路设置有限总预算时必填 | `ISP_MONTHLY_GB` | `NODE_MODE="direct+isp"` 且 `TOTAL_MONTHLY_GB>0`；必须大于 0 且小于总预算 |
| 其余设置 | 可使用默认值 | 按下方分类按需修改 |

**默认 Direct 线路、SSH 面板、不限流量时，只需要填写 `SERVER_IP`。** `NODE_NAME` 默认是 `MyNode`，建议自定义昵称；`NODE_MODE` 默认是 `direct`。

下面顺序与配置模板一致。JSON 不支持注释，因此 `config.example.json` 和 `config.json` 使用空行分组，不增加额外字段。

## 1. VPS 地址：始终必填

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `SERVER_IP` | 必填 | 字符串，无默认值 | VPS 静态公网 IPv4；不能保留 `YOUR_VPS_IP` 占位符 |

## 2. 昵称与线路模式：可选

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `NODE_NAME` | 可选，建议修改 | 字符串，`"MyNode"` | 自定义昵称，1–64 字符，不能包含空白、路径分隔符或控制字符 |
| `NODE_MODE` | 可选 | 字符串，`"direct"` | `direct`、`direct+isp`、`isp` 三选一 |

`direct` 仅使用 VPS 出口；`isp` 仅使用 ISP 出口；`direct+isp` 同时创建两条独立线路。

## 3. ISP 上游账号：按模式必填

`NODE_MODE` 包含 ISP 时，下面四项全部必填。`direct` 模式保持示例中的空值即可，不会连接 ISP。

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `ISP_HOST` | 包含 ISP 时必填 | 字符串，`""` | 上游 IP / 域名，不带协议、端口或路径 |
| `ISP_PORT` | 包含 ISP 时必填 | 整数或 `null`，默认 `null` | ISP 上游端口；填写时使用整数 |
| `ISP_USERNAME` | 包含 ISP 时必填 | 字符串，`""` | ISP 认证账号 |
| `ISP_PASSWORD` | 包含 ISP 时必填 | 字符串，`""` | ISP 认证密码 |

## 4. ISP 协议与出口检查：可选

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `ISP_PROTOCOL` | 可选 | 字符串，`"socks5"` | `socks5` 或 `http`，与供应商提供的代理协议一致 |
| `ISP_EXPECTED_IP` | 可选 | 字符串，`""` | ISP 供应商提供的出口公网 IPv4；填写后，实际 ISP 出口必须与此值一致；动态或轮换出口可留空 |

这两项仅在包含 ISP 的模式中使用。

`ISP_EXPECTED_IP` 填写 ISP 的实际出口 IP。`ISP_HOST` 是连接代理的入口地址，两者可能不同。`SERVER_IP` 是 VPS 自身的公网 IP，用于 Direct 线路的出口校验；ISP 线路则始终检查出口与 VPS IP 不同，以排除误走 Direct。

## 5. 域名与面板访问：可选

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `SUB_DOMAIN` | 可选；开启 HTTPS 面板时必填 | 字符串，`""` | 自有域名，不带协议、端口或路径；留空时订阅使用 VPS 公网 IP |
| `PANEL_HTTPS` | 可选 | 布尔值，`false` | 默认通过 SSH 隧道管理；设为 `true` 时使用域名 HTTPS 面板 |
| `ACME_EMAIL` | 可选 | 字符串，`""` | 证书联系邮箱 |

无域名时保持 `SUB_DOMAIN=""`、`PANEL_HTTPS=false`。填写域名后，A 记录必须直接指向 `SERVER_IP`；仅填写域名不会自动开放公网面板。

## 6. 端口：可选，默认值可直接使用

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `NODE_PORT` | 可选 | 整数，`443` | Direct 入站端口，仅包含 Direct 时使用 |
| `ISP_NODE_PORT` | 可选 | 整数，`8443` | ISP 入站端口，仅包含 ISP 时使用 |
| `PANEL_PORT` | 可选 | 整数，`7777` | 面板端口；默认仅监听本机，开启 HTTPS 面板时需手动放行 |
| `SUB_PORT` | 可选 | 整数，`2096` | 公网 HTTPS 订阅端口，需手动放行 |

端口范围为 1–65535，不能和实际 SSH 端口冲突。所选线路的端口、面板、订阅必须互不相同，`80/TCP` 留给证书签发与续期。`ISP_PORT` 是连接上游代理的端口，与 VPS 的 `ISP_NODE_PORT` 用途不同。

## 7. 月流量配额：可选

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `TOTAL_MONTHLY_GB` | 可选 | 数字，`0` | 受管客户端总月预算，单位 GiB；`0` 为不限 |
| `ISP_MONTHLY_GB` | 可选；双线路有限总预算时必填 | 数字，`0` | ISP 月预留，单位 GiB；双线路有限总预算时须大于 0、小于总预算 |

额度为非负数，最多三位小数。默认两项均为 `0`，不启用流量上限。`direct` 模式的 `ISP_MONTHLY_GB` 必须保持 `0`；双线路的 Direct 额度固定分配为总预算减去 ISP 预留。

## 8. REALITY 目标：可选，通常保持默认

| 字段 | 必填性 | 类型 / 默认值 | 说明 |
| --- | --- | --- | --- |
| `REALITY_HOST` | 可选 | 字符串，`"www.cloudflare.com"` | REALITY 目标和 SNI，不带协议、端口或路径，无需拥有该域名 |

## Direct + ISP 示例

下面仅演示需修改的字段；把它们合并到 config.json。示例中的代理地址和凭据必须替换：

~~~json
{
  "NODE_NAME": "MyNode",
  "NODE_MODE": "direct+isp",
  "ISP_PROTOCOL": "socks5",
  "ISP_HOST": "proxy.example.com",
  "ISP_PORT": 1080,
  "ISP_USERNAME": "YOUR_ISP_USERNAME",
  "ISP_PASSWORD": "YOUR_ISP_PASSWORD",
  "TOTAL_MONTHLY_GB": 1000,
  "ISP_MONTHLY_GB": 100
}
~~~

此配置给 Direct 分配 900 GiB，给 ISP 分配 100 GiB。使用面板原生客户端月配额，超额后由面板停用；重置日绑定原部署日期，面板时区零点重置，短月取最后一天。两条线路不相互借用剩余额度；客户端统计不等同于供应商整机账单。

单独 ISP 模式只创建 ISP 线路。总预算与 ISP 额度同时有限时，取两者较小值。Direct 模式的 ISP_MONTHLY_GB 必须为 0。双线路设置有限总预算时，必须同时设置大于 0、低于总预算的 ISP 预留。

ISP 方案支持认证的单个 SOCKS5 / HTTP 上游，当前验证 TCP 转发，ISP 线路 UDP 明确阻断；不会在上游失败时自动改走 Direct。上游账号、密码不写入客户端订阅。

## 域名 HTTPS 示例

~~~json
{
  "SUB_DOMAIN": "node.example.com",
  "PANEL_HTTPS": true,
  "ACME_EMAIL": "you@example.com"
}
~~~

A 记录必须直接指向 SERVER_IP。面板与订阅使用同一域名及证书，分别保留自己的端口和路径。仅填写 SUB_DOMAIN、保持 PANEL_HTTPS=false 时，域名只用于订阅，面板继续使用 SSH 隧道。

## 密码与私有配置

密码使用 JSON 字符串；双引号和反斜杠分别写成反斜杠加双引号、两个反斜杠。单引号、美元符号和反引号无需 Shell 转义，也不会作为命令执行。配置不支持注释。

本机与 VPS 上均执行 chmod 600 config.json。不要把真实配置、安装状态、订阅 ID、VLESS 链接、私钥或 result.txt 提交到仓库。Git 忽略规则不能保护任意自定义文件名，提交前仍需检查暂存文件。

## 已有部署

不需要配置文件的 --show、--traffic-status、--diagnose 和 --repair-reality-target 使用服务器保存的数据。

显式修改操作按类别读取配置：--configure-domain 修改域名、面板 HTTPS 和证书邮箱；--configure-nodes 修改昵称、模式、ISP 入站端口、上游及配额；--configure-traffic 只修改配额。它们都要求配置中的 SERVER_IP 与当前部署一致。现有 Direct、面板、订阅端口不通过这些操作修改，需先评估迁移方案。

从旧版脚本迁移时，将原脚本头部各项值填写到新 config.json，并把端口改成 JSON 整数、PANEL_HTTPS 改成 JSON 布尔值、无上限额度改成数字 0。状态目录和安装归属格式保持不变，但本次初始化没有在现有 VPS 上验证迁移。
