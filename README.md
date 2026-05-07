# ShellCrash 管理器

这是给小米路由器准备的 ShellCrash 可视化管理与恢复包。它的目标很简单：尽量不用 SSH、不用手动改 YAML，也能完成 ShellCrash 安装、订阅更新、住宅出口、防泄露和常用维护操作。

管理页面默认地址：

```text
http://192.168.31.1:19999/
```

## 当前状态

- 管理器安装目录：`/data/other_vol/shellcrash-manager`
- ShellCrash 默认目录：`/data/other_vol/ShellCrash`
- 页面监听地址：`192.168.31.1:19999`
- 恢复包文件：`shellcrash-manager-restore.tar.gz`
- 恢复包不包含真实订阅链接、住宅代理账号或住宅代理密码。

## 页面功能

### 总览

- 打开页面后自动读取路由器 CPU、内存、磁盘占用率。
- 可以点击 `刷新资源` 重新读取系统资源。
- 打开页面后自动检测当前海外网站看到的出口 IP、出口地区和连接协议。
- 可以点击 `刷新出口` 重新测试出口。
- 支持查看安装日志和服务日志。
- 支持安装、覆盖安装、启动、停止、重启 ShellCrash。

### 订阅规则

- 页面打开后会自动加载当前订阅链接。
- 可以单独保存订阅链接。
- 更换 VPN 订阅时，粘贴新链接后点击 `保存并更新订阅`，会先保存新链接，再拉取新节点。
- 住宅出口是独立板块，可以单独保存静态住宅 SOCKS5 出口。
- 支持配置住宅出口服务器、端口、账号、密码。
- 分流网站是独立板块，可以单独保存直连和住宅出口规则。
- 支持一行一个配置：
  - 本地直连网站后缀。
  - 海外/住宅出口网站后缀。
  - 本地直连关键词。
  - 海外/住宅出口关键词。
- 网站后缀会写成 `DOMAIN-SUFFIX`，例如 `cn` 只匹配 `.cn` 域名。
- 关键词会写成 `DOMAIN-KEYWORD`，例如 `google`、`gemini`、`openai`、`claude`、`anthropic` 可固定走住宅出口。
- 注意：关键词是包含匹配，`cn` 会命中所有域名里包含 `cn` 的请求；如果只想让 `.cn` 直连，建议填到“网站后缀”里。
- 保存住宅出口时，账号或密码留空会保留旧值，避免误清空。
- 住宅出口不会改写订阅原始分组和原始规则；它只在运行时给原本需要代理的分组包一层出口。
- 手动分流网站只是少量补丁，订阅判断不准时再填写，留空时完全交给订阅原规则。

### 静态出口

- 支持新增、编辑、删除多台静态出口服务器。
- 支持协议：
  - Shadowsocks。
  - Socks5。
  - HTTP。
  - VLESS Reality。
  - VLESS WS TLS。
- 每个节点可以填写地址、端口、账号、密码、加密方式、UUID、SNI、Reality 公钥、Short ID 等字段。
- VLESS 节点会写入 `packet-encoding: xudp`，用于更好地承载 UDP 请求。
- 不勾选“这个节点只做中转，最终走住宅出口”时，这个节点自己的 IP 就是最终出口。
- 勾选后，会额外生成 `美国静态住宅IP-经-节点名`，适合把 VPS 当作中转，最终仍然从住宅出口访问目标网站。
- 已启用的静态出口会出现在 `美国静态住宅IP` 分组里，后续可以在 ShellCrash 面板里像选择普通节点一样手动切换。
- 推荐服务器安装脚本路径：`/data/other_vol/shellcrash-manager/scripts/install-reality-node.sh`。
- 兼容旧方案的安装脚本路径：`/data/other_vol/shellcrash-manager/scripts/install-static-node.sh`。
- 推荐脚本默认生成 VLESS Reality/XUDP 节点；旧脚本默认生成 Shadowsocks，也支持 VLESS WS TLS。
- 页面不会回显真实节点密码；编辑旧节点时密码留空，会继续保留原密码。

### 功能设置

- 可视化配置 ShellCrash 常用运行项。
- 支持路由模式：混合模式、Redir、Tproxy、Tun、纯净模式。
- 支持 DNS 模式：mix、redir_host、fake-ip、hosts。
- 支持配置劫持范围、DNS 端口和自启延迟。
- 支持开关：
  - 跳过证书验证。
  - 域名嗅探。
  - 非常用端口过滤。
  - ShellCrash 内置 QUIC 过滤。
  - 中国 IP 绕过内核。
  - 保守模式启动。
  - 自启网络检查。
- 面板本身已经提供的 Mixed 端口、Redir 端口、主题、测速、代理样式等设置，不在这里重复展示。

### 面板

- 通过 iframe 直接加载 ShellCrash 面板。
- 默认加载地址：`http://192.168.31.1:9999/ui/`。
- 支持保存面板端口和路径。
- 支持安装或覆盖安装本地 Dashboard 面板。
- 支持面板类型：
  - zashboard。
  - MetaXD。
  - Yacd-Meta 魔改版。
  - 基础面板。
  - Meta 基础面板。
  - Yacd。
- 支持填写自定义面板包地址；一般留空即可。
- 面板自己的语言、字体、主题、测速、代理样式、连接样式等设置，请在 iframe 内的面板里调整。

### 防泄露

这是唯一的防泄露应用入口，避免重复按钮造成误解。

- 支持配置局域网接口，默认 `br-lan`。
- 支持阻断 QUIC / HTTP3。
- 支持阻断 WebRTC / STUN。
- 支持阻断 DoT / DoQ。
- 支持阻断国外 IPv6 转发。
- 支持中国目的地址不拦截：IPv4 使用 `cn_ip`，IPv6 会在有 `cn_ipv6.txt` 时自动生成 `cn_ip6`。
- 点击 `保存并应用防泄露` 后会立即写入路由器防火墙规则。
- 推荐模式是国内地址放行、国外地址拦截，避免抖音、淘宝、微信等国内 App 被防泄露规则误伤。

### 任务命令

- 支持刷新任务列表。
- 支持执行内置维护命令：
  - 更新管理脚本。
  - 更新当前内核。
  - 更新数据库。
  - 重设防火墙。
  - 热更新配置。
- 支持添加、删除自定义任务。
- 支持立即执行自定义命令。
- 自定义命令会直接在路由器上执行，不熟悉命令时建议只使用内置按钮。

### YAML 高级编辑

- 选择文件后自动读取，不需要再点读取按钮。
- 支持编辑：
  - `yamls/config.yaml`：订阅原始配置。
  - `yamls/rules.yaml`：自定义规则。
  - `yamls/proxies.yaml`：住宅出口节点。
  - `yamls/proxy-groups.yaml`：住宅出口分组。
  - `yamls/others.yaml`：其他自定义配置。
- 支持查看 `/tmp/ShellCrash/config.yaml`：运行时合并配置。
- 运行时合并配置只能查看，不能保存，避免把正在生效的最终配置写坏。

## 订阅更新为什么不会丢住宅出口

订阅更新通常会覆盖：

```text
/data/other_vol/ShellCrash/yamls/config.yaml
```

住宅出口和自定义规则单独保存在：

```text
/data/other_vol/ShellCrash/yamls/proxies.yaml
/data/other_vol/ShellCrash/yamls/proxy-groups.yaml
/data/other_vol/ShellCrash/yamls/rules.yaml
```

所以更新订阅时只更新订阅节点，住宅出口、分流规则和防泄露设置会继续保留。

住宅出口的实际生效方式是运行时封装：

```text
原始规则判断需要代理
→ 对应的住宅封装组
→ 原始订阅分组里当前选择的节点
→ 美国静态住宅IP
→ 目标网站
```

管理器不会直接改写 `yamls/config.yaml` 里的原始代理组。ShellCrash 启动时会先按订阅生成临时配置，管理器再在临时配置里做一层封装：

- `AI网站`、`媒体解锁`、`漏网之鱼` 等原始分组仍然保留原来的节点列表，用户可以继续在面板里选择不同节点。
- 运行时会额外生成 `美国静态住宅IP-AI网站` 这类封装组。
- 规则会临时指向封装组，封装组再通过原始分组作为前置连接住宅 SOCKS5。
- 如果封装后的配置没有通过内核校验，管理器会自动回滚到 ShellCrash 原始运行配置，避免服务启动失败。

所以你在 `/tmp/ShellCrash/config.yaml` 里会看到更多 `美国静态住宅IP-...` 名称，这是运行时封装，不是新增了一份大规则，也不会写回订阅原始文件。

如果在运行时合并配置 `/tmp/ShellCrash/config.yaml` 里看到 `rule-providers: cn` 或 `rule-set:cn`，它来自 ShellCrash 在 `mix` / `route` DNS 模式下的自动 DNS 优化，不属于住宅出口规则。需要完全不生成这段时，可以把 DNS 模式切到 `redir_host`，但这会改变 DNS 处理方式。

## 路由器本地安装

把整个 `shellcrash-residential-manager` 目录上传到路由器后，在目录内执行：

```sh
/bin/ash install.sh
```

安装后会输出：

```text
ShellCrash 管理器已安装：http://192.168.31.1:19999/
```

## 使用恢复包安装

本地生成恢复包：

```sh
./shellcrash-residential-manager/package.sh
```

会得到：

```text
shellcrash-manager-restore.tar.gz
```

上传到路由器后执行：

```sh
rm -rf /tmp/shellcrash-residential-manager
tar -zxf /tmp/shellcrash-manager-restore.tar.gz -C /tmp
/bin/ash /tmp/shellcrash-residential-manager/install.sh
```

## 新服务器一键安装

把推荐脚本复制到新的 Debian 服务器后执行：

```sh
sh install-reality-node.sh
```

默认会安装：

```text
Xray + VLESS Reality/XUDP
端口：443
UUID、Reality 密钥、Short ID：自动生成
```

更推荐长期使用的服务器节点是 `VLESS Reality + XUDP`：

```text
入口：VLESS Reality / TCP 443
UDP 承载：packet-encoding: xudp
伪装 SNI：常见 HTTPS 域名，例如 www.microsoft.com
```

选择理由：

- 比 HY2/UDP 更不容易被运营商 UDP 抖动影响。
- 不依赖 Let’s Encrypt 证书，适合 `cn.mt` 这类共享后缀已经触发证书限额的情况。
- 和当前防泄露策略更兼容，因为 HY2 本质依赖 UDP/QUIC，容易被国外 QUIC 拦截规则误伤。

HY2/UDP 更适合做“测速很快时的备用高速节点”，不建议作为默认稳定节点。

安装完成后，真实节点信息会保存在服务器：

```text
/root/shellcrash-node/node-info.txt
```

如果想自定义名称、端口或域名，可以这样运行：

```sh
NODE_NAME='ISP出口-1' NODE_DOMAIN='example.com' NODE_PORT=443 sh install-reality-node.sh
```

如果这台服务器只是中转，最终还要走另一台 VLESS Reality ISP 服务器，可以这样运行：

```sh
UPSTREAM_SERVER='yikeyun.cn.mt' \
UPSTREAM_UUID='上游UUID' \
UPSTREAM_PUBLIC_KEY='上游Reality公钥' \
UPSTREAM_SHORT_ID='上游ShortID' \
sh install-reality-node.sh
```

旧 Shadowsocks 脚本仍然保留：

```sh
sh install-static-node.sh
```

安装脚本会做这些事情：

- 自动安装依赖。
- Debian 10 源不可用时，会切换到 archive 源。
- 安装或复用 Xray。
- 写入 Reality 或 Shadowsocks 入站配置。
- 开启 BBR、TCP Fast Open。
- 设置 Xray 开机自启。
- 生成节点信息文件，方便复制到管理页面。

## 域名和伪装

域名不是必须项，节点直接使用 IP 也能工作。

但建议后续准备一个域名，原因是：

- 服务器换 IP 时，只要改域名解析，路由器节点地址可以不变。
- 后续如果改成 VLESS Reality、Trojan、HTTPS 类伪装，域名和 SNI 会更有用。
- 域名能让配置更像正常服务，但不能解决“同一个 IP 已经被封”的问题。
- 免费或共享二级域名可能会触发 Let’s Encrypt 证书限额；这种情况下 Reality 比自动证书方案更稳。

如果 IP 被大陆封禁，单纯把节点地址从 IP 换成域名通常没有用，因为域名最后还是解析到同一个 IP。真正需要准备的是备用服务器、备用 IP，以及更像正常 HTTPS 流量的协议配置。

## 小米官方插件说明

这个目录保留了 `start_script`，可以作为小米路由器官方插件源码的一部分。

需要注意：真正上传成小米后台可识别的 `.mpk` 插件时，还需要小米开发者中心提供的插件 AppID、证书和私钥进行签名。没有签名时，部分路由器后台会拒绝安装 `.mpk`。

当前 `shellcrash-manager-restore.tar.gz` 是恢复包，不是官方签名 `.mpk`。

## 安全提醒

- 页面状态接口不会返回住宅代理密码。
- 修改住宅代理密码时填写新密码；留空表示保留旧密码。
- 生成的恢复包不包含真实住宅代理账号、密码和订阅链接。
- YAML 高级编辑适合排查问题；不确定 YAML 语法时，优先使用页面上的普通表单。
- 自定义命令会直接操作路由器，执行前请确认命令含义。
