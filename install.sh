#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '请使用 root 安装'; exit 1; }
cd "$(dirname "$0")"
[ -x /usr/bin/lua ] && [ -x /usr/bin/mosdns ] || { echo '缺少现有 Lua 或 MosDNS'; exit 1; }
[ -f /etc/config/passwall ] || { echo '未找到 PassWall'; exit 1; }
[ -d /usr/lib/lua/luci/controller ] || { echo '需要支持 Lua 控制器的 LuCI'; exit 1; }
for path in /usr/lib/lua/luci/controller/node_dns_assistant.lua /usr/lib/lua/luci/model/node_dns_assistant.lua /usr/lib/lua/luci/view/node_dns_assistant/index.htm; do
 [ ! -e "$path" ] || { echo '插件文件已存在，停止覆盖；请先备份旧版本'; exit 1; }
done
mkdir -p /usr/lib/lua/luci/model /usr/lib/lua/luci/view/node_dns_assistant
cp luasrc/controller/node_dns_assistant.lua /usr/lib/lua/luci/controller/
cp luasrc/model/node_dns_assistant.lua /usr/lib/lua/luci/model/
cp luasrc/view/node_dns_assistant/index.htm /usr/lib/lua/luci/view/node_dns_assistant/
chmod 644 /usr/lib/lua/luci/controller/node_dns_assistant.lua /usr/lib/lua/luci/model/node_dns_assistant.lua /usr/lib/lua/luci/view/node_dns_assistant/index.htm
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
echo '已安装。刷新 LuCI，进入 服务 → 代理节点 DNS 助手。尚未修改 DNS 配置。'
