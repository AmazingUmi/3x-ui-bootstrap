# 配置说明

使用 --config FILE 指定 JSON 文件；默认读取脚本同目录的 config.json。配置文件只作为数据读取，不执行 Shell 内容，也不读取 BOOTSTRAP_* 环境变量作为配置。

配置必须是 UTF-8 JSON 对象，大小不超过 64 KiB，权限为 600 或更严格。未知字段、重复字段、错误类型和非标准 JSON 数值会被拒绝。SERVER_IP 必填，其余字段有默认值，建议始终从完整示例开始修改。

## 字段

| 字段 | 类型 / 默认值 | 说明 |
| --- | --- | --- |
| SERVER_IP | 字符串，必填 | VPS 静态公网 IPv4；不能保留占位符 |
| NODE_NAME | 字符串，MyNode | 自定义昵称，1–64 字符，不能包含空白、路径分隔符、控制字符 |
| NODE_MODE | 字符串，direct | direct、direct+isp、isp 三选一 |
| NODE_PORT | 整数，443 | Direct 入站端口 |
| ISP_NODE_PORT | 整数，8443 | ISP 入站端口 |
| ISP_PROTOCOL | 字符串，socks5 | socks5 或 http |
| ISP_HOST | 字符串，空 | 上游 IP / 域名，不带协议、端口或路径 |
| ISP_PORT | 整数或 null，null | 上游端口，包含 ISP 的模式必须填写 |
| ISP_USERNAME | 字符串，空 | ISP 账号，包含 ISP 的模式必须填写 |
| ISP_PASSWORD | 字符串，空 | ISP 密码，包含 ISP 的模式必须填写 |
| ISP_EXPECTED_IP | 字符串，空 | 可选预期出口公网 IPv4，填写后严格比较 |
| PANEL_PORT | 整数，7777 | 面板端口，默认仅监听本机 |
| SUB_PORT | 整数，2096 | 公网 HTTPS 订阅端口 |
| SUB_DOMAIN | 字符串，空 | 自有域名；留空时使用 SERVER_IP |
| PANEL_HTTPS | 布尔值，false | true 时必须有域名，开放公网 HTTPS 面板 |
| TOTAL_MONTHLY_GB | 数字，0 | 受管客户端总月预算，单位 GiB；0 为不限 |
| ISP_MONTHLY_GB | 数字，0 | ISP 月预留，单位 GiB；0 为不限 |
| ACME_EMAIL | 字符串，空 | 可选证书联系邮箱 |
| REALITY_HOST | 字符串，www.cloudflare.com | REALITY 目标和 SNI，无需拥有该域名 |

端口范围为 1–65535，不能和实际 SSH 端口冲突。所选线路的端口、面板、订阅必须互不相同，80/TCP 留给证书签发与续期。流量额度为非负数，最多三位小数。

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
