# 代理节点 DNS 助手 0.1.0

面向 VM103 当前 PassWall + MosDNS 自定义加密 DNS 配置的 LuCI 插件。已在当前 VM103 安装并验证；其他固件尚未验证。

## 使用

1. 安装后进入 **服务 → 代理节点 DNS 助手**。
2. 新增或编辑 PassWall 节点后，先点 **检查配置**。
3. 点 **同步节点域名**，将节点服务器域名加入直连加密 DNS。
4. 需要撤销时，点 **恢复上次备份**。这是恢复上一轮操作前的整个 MosDNS 配置；不要在手动修改 MosDNS 后盲目恢复。

不会读取或展示节点凭据；不会变更节点地址、SNI、端口、默认代理、防火墙、DHCP 或安装代理内核。IP 地址节点自动跳过。不自动跟踪订阅更新或自动同步。

## 支持范围

仅支持 `/etc/mosdns/secure-proxy.json`，且其中具备 `cn_domains`、`domestic_doh`、`secure_main`，国内上游有固定 IPv4 连接地址，使用 HTTPS 并验证证书，不依赖 SOCKS。配置不匹配时停止操作，不猜测其他固件结构。

本插件解决节点域名解析的代理循环依赖，不保证节点可用、代理故障自动直连、浏览器自带 DoH 不绕过路由器，也不替代防火墙防泄漏规则。

## 安全与恢复

- LuCI 登录权限与 POST token 校验。
- 单操作文件锁，避免重复点击并发修改。
- 仅将服务器地址中有效的 ASCII 域名写入 JSON，不拼接到 shell 命令。
- 只移除插件记录为自己添加的条目，保留其他域名和规则。
- 在独立临时端口加载候选配置，避免占用生产监听端口。
- 原子写入；重新加载后检查 MosDNS 进程。失败则恢复文件并尝试重新启动。
- 进程存在不等于解析可用，初版尚无自动端到端 DNS 健康检查，不能承诺完全无中断。
- 每轮备份在 `/etc/node-dns-assistant/backup.json`，管理记录在 `managed.json`。重新加载会短暂影响 DNS 查询。
- 本插件暂未添加 sysupgrade 保留清单，升级固件前请导出插件文件及备份。

## 安装

将本目录完整复制到 OpenWrt，再以 root 执行：

```sh
sh install.sh
```

安装脚本只安装页面及后端，不同步 DNS、不重启网络。文件已存在时停止覆盖。

也可将目录放进 OpenWrt 构建树的 `package/`，通过所附 Makefile 构建 LuCI 包。当前交付不是已编译的 ipk/apk。

## 卸载

删除以下插件文件即可；不会自动撤销已同步的 DNS 域名。需要撤销时应先在页面恢复备份，并确认未覆盖之后的手动修改。

- `/usr/lib/lua/luci/controller/node_dns_assistant.lua`
- `/usr/lib/lua/luci/model/node_dns_assistant.lua`
- `/usr/lib/lua/luci/view/node_dns_assistant/index.htm`

重新登录或清除 LuCI 索引缓存后，菜单消失。`/etc/node-dns-assistant/` 可留作备份。

## 验证记录（2026-10-17）

- Lua 后端 26 项隔离断言通过：域名过滤与去重、保留手工规则、重复同步不重载、仅删除托管条目、恢复备份、预检查失败不写入、重载失败回退、配置不兼容拒绝操作、并发锁。
- 在 VM103 真实 MosDNS 上用临时端口加载候选配置通过，未占用生产端口。
- LuCI 登录后的页面渲染、状态接口、合法 POST 同步通过；错误 CSRF token 返回 403。
- 设备实际调用同步在“无变化”路径通过，没有写入当前 DNS 配置。新增域名后的完整实际写入/恢复流程目前仅做隔离测试，尚未在生产配置中故意添加测试节点。

运行隔离测试（需要 Lua 5.1 与 luci.jsonc；不会操作真实配置）：

```sh
lua tests/backend.lua luasrc/model/node_dns_assistant.lua
```
