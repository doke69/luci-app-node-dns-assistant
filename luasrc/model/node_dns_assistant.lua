local M={}
local fs=require "nixio.fs"
local nixio=require "nixio"
local json=require "luci.jsonc"
local uci=require("luci.model.uci").cursor()
local sys=require "luci.sys"
local CONF="/etc/mosdns/secure-proxy.json"
local DIR="/etc/node-dns-assistant"
local RUN="/var/run/node-dns-assistant"
local function decode(path)
 local s=fs.readfile(path)
 return s and json.parse(s),s
end
local function atomic(path,s)
 assert(type(s)=="string","无法序列化配置")
 assert(fs.writefile(path..".new",s),"无法写入文件")
 fs.chmod(path..".new","600")
 assert(fs.rename(path..".new",path),"无法保存文件")
end
local function host(s)
 if type(s)~="string" then return nil end
 s=s:lower():gsub("%.$","")
 if #s>253 or not s:find("%.") or s:match("^[%d%.]+$") then return nil end
 if not s:match("^[a-z0-9%.%-]+$") or s:find("..",1,true) then return nil end
 for part in s:gmatch("[^.]+") do
  if #part>63 or not part:match("^[a-z0-9]") or not part:match("[a-z0-9]$") then return nil end
 end
 return s
end
local function domains()
 local out,seen={},{}
 uci:foreach("passwall","nodes",function(n)
  local d=host(n.address)
  if d and not seen[d] then seen[d]=true;out[#out+1]=d end
 end)
 table.sort(out);return out
end
local function equal_list(a,b)
 if #a~=#b then return false end
 for i,v in ipairs(a) do if v~=b[i] then return false end end
 return true
end
local function load()
 assert(uci:get("mosdns","config","configfile")==CONF,"当前未使用兼容的加密 DNS 配置；已停止操作")
 local x,raw=decode(CONF)
 assert(type(x)=="table" and type(x.plugins)=="table","MosDNS 配置无法读取")
 local cn,domestic,sequence
 for _,p in ipairs(x.plugins) do
  if p.tag=="cn_domains" and p.type=="domain_set" then cn=p end
  if p.tag=="domestic_doh" and p.type=="forward" then domestic=p end
  if p.tag=="secure_main" and p.type=="sequence" then sequence=p end
 end
 assert(cn and domestic and sequence,"当前配置缺少所需的加密解析分流")
 assert(type(cn.args)=="table" and (cn.args.exps==nil or type(cn.args.exps)=="table"),"域名列表格式异常")
 local upstreams=domestic.args and domestic.args.upstreams
 assert(type(upstreams)=="table" and #upstreams>0,"缺少独立加密 DNS 上游")
 for _,up in ipairs(upstreams) do
  assert(type(up)=="table" and type(up.addr)=="string" and up.addr:match("^https://"),"节点解析必须使用 HTTPS DNS")
  assert(type(up.dial_addr)=="string" and up.dial_addr:match("^[%d%.]+$"),"加密上游必须有独立的 IPv4 连接地址")
  assert(not up.socks5 and not up.insecure_skip_verify,"节点解析不可依赖代理或跳过证书验证")
 end
 local found=false
 for _,step in ipairs(sequence.args or {}) do
  if step.matches=="qname $cn_domains" and step.exec=="$domestic_doh" then found=true end
 end
 assert(found,"未找到直连加密解析规则")
 return x,raw,cn
end
function M.status()
 local ok,res=pcall(function()
  local _,_,cn=load();local have={}
  for _,v in ipairs(cn.args.exps or {}) do have[v]=true end
  local nodes={}
  for _,d in ipairs(domains()) do nodes[#nodes+1]={domain=d,synced=have["full:"..d] or false} end
  return {ok=true,nodes=nodes,backup=fs.access(DIR.."/backup.json"),message="仅同步节点域名；保留原有分流与防火墙规则"}
 end)
 return ok and res or {ok=false,message=tostring(res)}
end
local function validate(x)
 -- Run a separate instance on ephemeral loopback ports. Never bind production ports.
 local check=json.parse(json.stringify(x))
 check.api={http="127.0.0.1:0"};check.log={level="error",file=RUN.."/validation.log"}
 for _,p in ipairs(check.plugins) do
  if p.type=="udp_server" or p.type=="tcp_server" then p.args.listen="127.0.0.1:0" end
  if p.args then p.args.dump_file=nil end
 end
 atomic(RUN.."/check.json",json.stringify(check))
 local result=sys.call("/usr/bin/mosdns start -c /var/run/node-dns-assistant/check.json -d /etc/mosdns >/var/run/node-dns-assistant/validation-output 2>&1 & pid=$!; sleep 2; if kill -0 $pid 2>/dev/null; then kill $pid; wait $pid; exit 0; else wait $pid; exit 1; fi")
 assert(result==0,"配置预检查失败，现有配置未改动；请查看 /var/run/node-dns-assistant/validation-output")
end
local function restart()
 return sys.call("/etc/init.d/mosdns restart >/var/run/node-dns-assistant/restart.log 2>&1")==0
  and sys.call("sleep 1; /etc/init.d/mosdns running >/dev/null 2>&1")==0
end
function M.change(restore)
 fs.mkdirr(DIR);fs.chmod(DIR,"700");fs.mkdirr(RUN);fs.chmod(RUN,"700")
 local lock=nixio.open(RUN.."/lock","w","600")
 if not lock or not lock:lock("tlock") then
  if lock then lock:close() end
  return {ok=false,message="已有操作进行中，请稍后重试"}
 end
 local ok,res=pcall(function()
  local x,raw,cn=load()
  local owned=decode(DIR.."/managed.json") or {}
  local updated,newowned=x,{}
  if restore then
   local b=decode(DIR.."/backup.json")
   assert(type(b)=="table" and type(b.config)=="string","没有可用备份")
   updated=json.parse(b.config);newowned=b.managed or {}
   assert(type(updated)=="table","备份无法解析")
  else
   local remove,have={},{}
   for _,d in ipairs(owned) do remove["full:"..d]=true end
   local keep={}
   for _,v in ipairs(cn.args.exps or {}) do
    if not remove[v] then keep[#keep+1]=v;have[v]=true end
   end
   for _,d in ipairs(domains()) do
    if not have["full:"..d] then keep[#keep+1]="full:"..d;newowned[#newowned+1]=d end
   end
   if equal_list(cn.args.exps or {},keep) and equal_list(owned,newowned) then
    return {ok=true,message="节点域名已同步，无需修改或重新加载"}
   end
   cn.args.exps=keep
  end
  validate(updated)
  local original=json.stringify({config=raw,managed=owned})
  local changed,err=pcall(function()
   atomic(DIR.."/backup.json",original)
   atomic(CONF,json.stringify(updated))
   assert(restart(),"MosDNS 重新加载失败")
   atomic(DIR.."/managed.json",json.stringify(newowned))
  end)
  if not changed then
   atomic(CONF,raw);atomic(DIR.."/managed.json",json.stringify(owned))
   local recovered=restart()
   error(tostring(err)..(recovered and "；已恢复原配置" or "；原文件已恢复，但服务恢复失败，请检查日志"))
  end
  return {ok=true,message=restore and "已恢复上次操作前的配置" or "同步完成，MosDNS 已重新加载"}
 end)
 lock:lock("ulock");lock:close()
 return ok and res or {ok=false,message=tostring(res)}
end
return M
