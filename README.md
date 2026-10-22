# 3X-UI Bootstrap

面向 Ubuntu / Debian 的 3X-UI 一键部署工具。填写独立 JSON 配置，上传脚本与配置文件，即可部署 VLESS + REALITY 节点。

支持 Direct、ISP、Direct + ISP 三种线路模式；域名可选，面板默认通过 SSH 隧道管理。安装完成后输出控制台账号、密码、完整 URL、Mihomo 订阅、Shadowrocket 订阅和 VLESS 链接。

## 当前能力

- Direct 使用 VPS 出口；ISP 使用指定的 SOCKS5 / HTTP 代理，先验证认证、HTTPS 转发和实际出口。
- 每条线路使用独立客户端、UUID、REALITY 密钥和订阅 ID。
- 自动申请、续期公网 IP 或域名 HTTPS 证书；域名模式可选开放 HTTPS 面板。
- 使用面板原生客户端月配额，按原部署日重置；双线路固定分配 Direct = 总预算 − ISP 预留。
- 校验官方发行包摘要，并验证正式入站的 REALITY / VLESS / Vision 认证、HTTPS 转发和出口。

固定版本：3x-ui **v3.10.2**、Xray-core **26.6.27**、Certbot **5.8.0**。Xray 固定版本用于保留已验证的 Shadowrocket 兼容性；升级前需要重新验收 Shadowrocket 和 Mihomo。

## 1. 准备 VPS

适用于新建、已绑定静态公网 IPv4 的 Ubuntu 22.04+ / Debian 12+ VPS，要求 systemd、Python 3.10+、amd64 或 arm64。

准备好 SSH 登录方式和 sudo 权限。脚本只接管自身创建的安装；已有其他 3X-UI 部署时会停止。

部署前重点确认：**配置填对、域名解析生效、端口已开放**。

## 2. 填写配置

在本机项目目录执行：

~~~bash
cp config.example.json config.json
chmod 600 config.json
nano config.json
~~~

至少替换 SERVER_IP 和 NODE_NAME。首次建议使用默认 direct 模式。配置格式为 JSON：端口和流量额度使用数字，PANEL_HTTPS 使用 true / false，未填写的 ISP_PORT 使用 null。

先执行本地校验，无需 sudo 或网络：

~~~bash
bash ./install-3x-ui.sh --config ./config.json --validate-config
~~~

完整字段、双线路及域名示例见 [配置说明](docs/configuration.md)。真实 config.json 已加入 Git 忽略规则；请只提交示例。

## 3. 解析域名并开放端口

SUB_DOMAIN 可留空，订阅使用 VPS 公网 IP 和可信 HTTPS 证书；此时面板通过 SSH 隧道访问。

填写域名时，将 A 记录直接指向 SERVER_IP，关闭该记录的 CDN 代理，等待公共 DNS 解析一致。PANEL_HTTPS 为 true 时，面板与订阅共用该域名及证书。

以下是默认端口，**云防火墙和服务器防火墙均需检查**。脚本只输出清单，不修改防火墙或 SSH 设置。

| TCP 端口 | 用途 | 何时开放 |
| --- | --- | --- |
| 实际 SSH 端口（常见为 22） | 登录、上传、SSH 隧道 | 始终保留 |
| 80 | 证书申请与自动续期 | 始终需要 |
| 443 | Direct 节点 | 模式包含 Direct |
| 8443 | ISP 节点 | 模式包含 ISP |
| 2096 | 公网 HTTPS 订阅 | 始终需要 |
| 7777 | 公网 HTTPS 面板 | 仅 PANEL_HTTPS=true 时；建议限制管理来源 IP |

修改端口后以配置校验输出为准。默认 SSH 面板无需开放 7777。

## 4. 上传、登录和安装

在本机执行，将 YOUR_VPS_IP 和 ubuntu 替换成实际信息。命令使用现有 SSH 配置或代理中的密钥：

~~~bash
scp ./install-3x-ui.sh ./config.json ubuntu@YOUR_VPS_IP:~/
ssh ubuntu@YOUR_VPS_IP
~~~

登录 VPS 后执行：

~~~bash
chmod 600 ~/config.json
sudo bash ~/install-3x-ui.sh --config ~/config.json --check
sudo bash ~/install-3x-ui.sh --config ~/config.json --install
~~~

--check 会联网验证候选配置、ISP、DNS 和安装条件，但不安装软件或修改服务。安装失败后，保留状态，修复问题并使用同一配置重试。

## 5. 访问面板与导入订阅

安装成功时，终端输出完整访问地址和订阅链接，也保存在 VPS 的 /var/lib/3x-ui-bootstrap/result.txt，仅 root 可读。

默认 SSH 面板需要在本机另外建立隧道；下面示例使用默认面板端口 7777：

~~~bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:17777:127.0.0.1:7777 ubuntu@YOUR_VPS_IP
~~~

保持该终端开启，再打开安装结果输出的 http://127.0.0.1:17777/ 后带随机路径的完整 URL。域名 HTTPS 面板直接使用安装结果中的 HTTPS URL。

将对应线路的订阅导入 Mihomo / Shadowrocket，验证网页访问和实际出口。服务端本机检查通过后，仍需完成客户端公网验收。

## 维护命令

在 VPS 上执行；使用配置的操作默认读取脚本同目录的 config.json，也可明确使用 --config 指定。

| 操作 | 命令 | 配置来源 |
| --- | --- | --- |
| 显示账号和链接 | sudo bash ~/install-3x-ui.sh --show | 服务器保存的结果 |
| 查询原生月流量 | sudo bash ~/install-3x-ui.sh --traffic-status | 服务器保存的部署 |
| 临时 REALITY 诊断 | sudo bash ~/install-3x-ui.sh --diagnose | 服务器保存的部署 |
| 修改域名、面板 HTTPS | sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-domain | 配置中的域名、HTTPS、邮箱 |
| 修改昵称、模式和 ISP | sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-nodes | 配置中的线路、ISP、配额 |
| 修改月配额 | sudo bash ~/install-3x-ui.sh --config ~/config.json --configure-traffic | 配置中的总预算、ISP 预留 |
| 修复 REALITY 目标 | sudo bash ~/install-3x-ui.sh --repair-reality-target | 服务器保存的部署和修复记录 |

配置文件是候选设置。面板内手工修改 ISP 后，不要用旧配置执行 --configure-nodes；先同步配置文件，避免覆盖当前账号。

排查说明见 [常见问题](docs/troubleshooting.md)。

## 开发与验证

~~~bash
bash scripts/check.sh
~~~

本地检查覆盖 Shell / Python 语法、配置边界、线路路由、配额和 CLI。CI 不部署 VPS，不使用真实 ISP 凭据；真实客户端与证书签发需要另行验收。贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 项目状态

当前为 0.1.0 初始化版本，由已经使用的一键脚本整理而来，新增独立配置及离线检查。项目仓库：[AmazingUmi/3x-ui-bootstrap](https://github.com/AmazingUmi/3x-ui-bootstrap)。许可证待项目所有者确定后补充。

依赖项目：[3x-ui](https://github.com/MHSanaei/3x-ui)、[Xray-core](https://github.com/XTLS/Xray-core)、[Certbot](https://github.com/certbot/certbot)。本项目不包含它们的发行二进制，安装时下载并校验固定版本。
