# ShellCrash 管理器交接文档
真实密码、订阅链接、节点 UUID、公钥、Short ID、住宅代理账号密码。需要这些信息时，直接查看 `LOCAL_SECRETS.md`，在本机填写；该文件已被忽略和排除打包。

## 项目介绍

本项目是小米路由器上的 ShellCrash 可视化管理器，目标是尽量不用 SSH 手改 YAML，也能完成：
- ShellCrash 安装、启动、停止、日志查看。
- 订阅链接保存和订阅更新。
- 自建节点管理。
- 静态住宅 SOCKS5 出口管理。
- 分流网站管理。
- 防泄露规则管理。
- ShellCrash 面板 iframe 嵌入。
- YAML 高级编辑和运行时配置查看。

管理页默认地址：

```text
http://192.168.0.1:19999/
```

ShellCrash 原面板默认地址：

```text
http://192.168.0.1:9999/ui/
```

## 目录结构

```text
www/index.html                 页面结构和 tab 分区
www/app.css                    页面样式
www/app.js                     总览、订阅、规则、设置、面板、任务、YAML 逻辑
www/nodes.js                   自建节点列表和表单逻辑
www/residential.js             静态住宅出口列表和表单逻辑
www/cgi-bin/api                安装、订阅、规则、面板、出口测试接口
www/cgi-bin/advanced           功能设置、防泄露、任务命令、YAML 编辑接口
www/cgi-bin/nodes              自建节点 CRUD 接口
www/cgi-bin/residential        静态住宅出口 CRUD 接口
scripts/cgi_common.sh          CGI 公共函数
scripts/setup-shellcrash-custom.sh  核心恢复脚本，写入 YAML、钩子、防泄露
scripts/custom_nodes.sh        自建节点数据库和 YAML 生成
scripts/residential_nodes.sh   静态住宅出口数据库和 YAML 生成
scripts/group_helpers.sh       从订阅配置识别可作为中转的分组
scripts/rule_helpers.sh        分流规则提取、规范化和生成
scripts/block_proxy_leaks.sh   防泄露 iptables/ipset 规则
scripts/residential-ui-start.sh 管理页 uhttpd 启停
scripts/shellcrash-auto-install.sh ShellCrash 自动安装脚本
package.sh                     生成恢复包
SERVER_NODE_INSTALL.md         服务器节点安装教程
LOCAL_SECRETS.template.md      本机敏感信息模板
```

## 核心概念

管理器只新增两个可见分组：

```text
自建节点
静态住宅IP
```

`自建节点` 用来决定前面是否先中转：

- `使用订阅节点`：走订阅原有分组。
- `直接使用静态住宅IP`：不经过订阅节点，直接连最终出口。
- 未勾选“这个节点就是最终出口 IP”的自建节点：作为中转节点。

`静态住宅IP` 用来决定最终出口：

- 静态住宅 SOCKS5 出口。
- 勾选了“这个节点就是最终出口 IP”的自建节点。
- `不使用静态住宅IP`：直接使用前面的订阅节点或自建节点作为出口。

## 当前推荐选择

如果希望直接使用某台 ISP 服务器作为最终出口：

```text
自建节点：直接使用静态住宅IP
静态住宅IP：选择对应 ISP 出口节点
```

如果希望先走订阅节点，再从某个住宅出口出去：

```text
自建节点：使用订阅节点
静态住宅IP：选择具体住宅出口
```

如果希望先走某台自建中转，再从住宅出口出去：

```text
自建节点：选择中转节点
静态住宅IP：选择具体住宅出口
```

## 运行时封装逻辑

订阅更新会覆盖：

```text
/data/other_vol/ShellCrash/yamls/config.yaml
```

管理器自己的配置保存在：

```text
/data/other_vol/shellcrash-manager/custom-nodes.db
/data/other_vol/shellcrash-manager/residential-nodes.db
/data/other_vol/ShellCrash/yamls/proxies.yaml
/data/other_vol/ShellCrash/yamls/proxy-groups.yaml
/data/other_vol/ShellCrash/yamls/rules.yaml
```

关键点：管理器不直接重写订阅原始分组。ShellCrash 先生成运行时配置：

```text
/tmp/ShellCrash/config.yaml
```

然后 `scripts/setup-shellcrash-custom.sh` 安装的运行时钩子会把原本需要代理的规则目标改成：

```text
静态住宅IP
```

这样订阅里的 `AI网站`、`媒体解锁`、`漏网之鱼` 等原始分组仍然存在，更新订阅时也会继续更新，但真正出口会进入管理器的 `静态住宅IP` 分组。

## 热更新关键坑

ShellCrash 的 `hotupdate` 只调用：

```text
/data/other_vol/ShellCrash/starts/clash_modify.sh
```

它不会经过完整启动流程里的 `bfstart.sh`。因此住宅出口封装必须同时挂在两个地方：

```text
/data/other_vol/ShellCrash/starts/clash_modify.sh
/data/other_vol/ShellCrash/starts/bfstart.sh
```

当前修复已经做到：

- `clash_modify.sh`：保证点击顶部 `更新配置` 时会封装规则。
- `bfstart.sh`：保证 ShellCrash 启动或重启时会封装规则。
- `www/cgi-bin/advanced`：执行 `hotupdate` 前会先跑 `setup-shellcrash-custom.sh`，避免 ShellCrash 自身更新后钩子丢失。

验证命令：

```sh
grep -n "residential_runtime_wrapper" \
  /data/other_vol/ShellCrash/starts/clash_modify.sh \
  /data/other_vol/ShellCrash/starts/bfstart.sh
```

## IPv6 关键坑

ShellCrash 配置里：

```text
ipv6_dns=OFF
```

只表示 DNS 不解析 IPv6，不等于内核不允许 IPv6 连接。之前出现过双栈网站看到 IPv6 出口的问题。

当前修复在运行时封装脚本里处理：

```text
当 ipv6_dns=OFF 时，把 /tmp/ShellCrash/config.yaml 里的顶层 ipv6: true 改为 ipv6: false
```

验证命令：

```sh
grep -nE '^ipv6:|DOMAIN-SUFFIX,ipify.org|MATCH,' /tmp/ShellCrash/config.yaml
curl -k -s --max-time 20 --proxy http://127.0.0.1:7890 https://api64.ipify.org
```

期望：`ipv6: false`，并且 `api64.ipify.org` 返回 IPv4。

## 出口验证

在路由器上验证代理出口：

```sh
curl -k -s --max-time 20 --proxy http://127.0.0.1:7890 https://api.ipify.org
curl -k -s --max-time 20 --proxy http://127.0.0.1:7890 https://api64.ipify.org
curl -k -s --max-time 20 --proxy http://127.0.0.1:7890 https://ifconfig.co/ip
curl -k -s --max-time 20 --proxy http://127.0.0.1:7890 https://chatgpt.com/cdn-cgi/trace
```

最近一次验证结果：

```text
api.ipify.org    -> 预期 ISP IPv4
api64.ipify.org  -> 预期 ISP IPv4
ifconfig.co      -> 预期 ISP IPv4
chatgpt trace    -> ip=预期 ISP IPv4, loc=US, http=http/2
```

真实预期 IPv4 写到 `LOCAL_SECRETS.md`，不要写进本文档。

## 常用部署命令

本地生成恢复包：

```sh
./package.sh
```

上传恢复包到路由器时，macOS 到小米路由器需要 `scp -O`：

```sh
scp -O ../shellcrash-manager-restore.tar.gz root@192.168.0.1:/tmp/shellcrash-manager-restore.tar.gz
```

路由器上恢复管理器：

```sh
rm -rf /tmp/shellcrash-residential-manager
tar -xzf /tmp/shellcrash-manager-restore.tar.gz -C /tmp
mkdir -p /data/other_vol/shellcrash-manager
cp -a /tmp/shellcrash-residential-manager/. /data/other_vol/shellcrash-manager/
rm -f /data/other_vol/shellcrash-manager/scripts/install-reality-node.sh
rm -f /data/other_vol/shellcrash-manager/scripts/install-static-node.sh
chmod +x /data/other_vol/shellcrash-manager/scripts/*.sh
chmod +x /data/other_vol/shellcrash-manager/www/cgi-bin/*
/data/other_vol/shellcrash-manager/scripts/residential-ui-start.sh restart
```

重新安装管理器钩子和自定义配置：

```sh
SHELLCRASH_HOME=/data/other_vol/ShellCrash \
  /data/other_vol/shellcrash-manager/scripts/setup-shellcrash-custom.sh
```

热更新配置：

```sh
curl -s --max-time 10 -X POST \
  -d 'action=run_builtin&cmd=hotupdate' \
  http://192.168.0.1:19999/cgi-bin/advanced
```

## 恢复包安全

`package.sh` 必须排除：

```text
.git
backups
custom-nodes.db
residential-nodes.db
LOCAL_SECRETS.md
scripts/install-reality-node.sh
scripts/install-static-node.sh
*.tar.gz
```

检查恢复包是否意外包含敏感文件：

```sh
tar -tzf ../shellcrash-manager-restore.tar.gz | \
  rg 'LOCAL_SECRETS|install-(reality|static)-node\.sh|custom-nodes\.db|residential-nodes\.db|\.git|backups|\.tar\.gz'
```

期望：无输出。

## 接口摘要

```text
GET/POST /cgi-bin/api
  status
  get_subscription
  save
  save_panel
  update_subscription
  install_shellcrash
  start / stop / restart
  test_exit
  log

POST /cgi-bin/advanced
  status
  save_settings
  save_leak
  run_builtin
  task_list
  add_task
  delete_task
  run_custom_command
  read_yaml
  save_yaml
  install_panel
  log

POST /cgi-bin/nodes
  list
  save
  delete

POST /cgi-bin/residential
  list
  save
  delete
```

## UI 注意事项

- 页面第一屏是实际工具，不做营销页。
- 面板 tab 排在第二位，iframe 尽量宽，不加标题栏和边框。
- `住宅出口`、`自建节点`、`分流网站` 保存后都提示点击顶部 `更新配置`。
- 页面不提供“重建本地文件”按钮，因为保存和删除时已经自动重建。
- 删除节点、删除出口、删除任务、执行自定义命令、保存 YAML、安装或覆盖安装都要二次确认。
- 不要在页面文案里出现研发沟通口吻，比如“补丁”“一般不用点”等。

## 服务器节点安装

服务器安装说明放在：

```text
SERVER_NODE_INSTALL.md
```

页面只显示 GitHub 教程链接，不显示本地服务器安装脚本路径。

服务器安装脚本不打入路由器恢复包：

```text
scripts/install-reality-node.sh
scripts/install-static-node.sh
```

## 已知当前状态

最近一次路由器接口验证：

```text
ShellCrash installed: true
ShellCrash running: true
Manager running: true
Leak guard active: true
Subscription configured: true
DNS mode: mix
Router mode: 混合模式
IPv6 DNS: OFF
Runtime ipv6: false
```

最近一次热更新后，运行时规则确认：

```text
DOMAIN-SUFFIX,ipify.org,静态住宅IP
MATCH,静态住宅IP
```

## 开发原则

- 不要把真实密码、订阅链接、节点密钥写进代码、README 或 HANDOFF。
- 不要自动提交 git commit，除非用户明确要求。
- 单文件尽量不超过 500 行，接近时拆分。
- 后端脚本需要兼容 busybox/ash，不要使用 bash 专属语法。
- 改 ShellCrash 运行时逻辑后，必须测试：
  - `sh -n scripts/*.sh www/cgi-bin/* package.sh`
  - `node --check www/app.js www/nodes.js www/residential.js`
  - `./package.sh`
  - 恢复包敏感文件检查
  - 路由器接口状态
  - 代理出口 IPv4/IPv6
