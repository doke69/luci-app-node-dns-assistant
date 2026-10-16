-- Isolated backend regression suite. All filesystem/service/UCI operations are mocked.
local json=require 'luci.jsonc'
local files,fail,locked,rows={},nil,false,{}
local function copy(x) return json.parse(json.stringify(x)) end
local cfg={plugins={
 {tag='cn_domains',type='domain_set',args={exps={'full:keep.example.com'}}},
 {tag='domestic_doh',type='forward',args={upstreams={{addr='https://dns.example.com/dns-query',dial_addr='223.5.5.5',insecure_skip_verify=false}}}},
 {tag='secure_main',type='sequence',args={{matches='qname $cn_domains',exec='$domestic_doh'}}},
 {tag='udp_server',type='udp_server',args={listen=':5335'}}}}
local CONF='/etc/mosdns/secure-proxy.json'
local DIR='/etc/node-dns-assistant'
local active=CONF
local calls={}
local fs={readfile=function(p) return files[p] end,
 writefile=function(p,s) if fail=='write' then return nil end files[p]=s;return true end,
 rename=function(a,b) files[b]=files[a];files[a]=nil;return true end,
 chmod=function(_,mode) assert(type(mode)=="string","chmod mode must be an octal string");return true end,mkdirr=function() return true end,
 access=function(p) return files[p]~=nil end}
package.loaded['nixio.fs']=fs
package.loaded['nixio']={open=function(_,_,mode) assert(mode=="600","open mode must be octal string");return {lock=function(_,mode) if mode=='ulock' then locked=false;return true end if locked then return false end locked=true;return true end,close=function() end} end}
package.loaded['luci.model.uci']={cursor=function() return {get=function() return active end,foreach=function(_,_,_,fn) for _,r in ipairs(rows) do fn(r) end end} end}
package.loaded['luci.sys']={call=function(cmd)
 calls[#calls+1]=cmd
 if fail=='validation' and cmd:find('mosdns start',1,true) then return 1 end
 if fail=='restart' and cmd:find('init.d/mosdns restart',1,true) then fail=nil;return 1 end
 return 0
end}
local model=dofile(arg[1] or 'luasrc/model/node_dns_assistant.lua')
local count=0
local function check(v,label) assert(v,label);count=count+1 end
local function reset()
 files={[CONF]=json.stringify(copy(cfg))};fail=nil;locked=false;active=CONF;calls={};rows={}
end
reset()
rows={{address='Node.Example.com.'},{address='node.example.com'},{address='1.2.3.4'},{address='2001:db8::1'},{address='bad;touch /tmp/pwned'},{address='-bad.example.com'},{address='bad..example.com'}}
local s=model.status();check(s.ok,'compatible config');check(#s.nodes==1,'sanitize/deduplicate/IP filtering');check(s.nodes[1].domain=='node.example.com','normalization');check(not s.nodes[1].synced,'pending status')
local old=files[CONF];local a=model.change(false);check(a.ok,'sync');check(files[DIR..'/backup.json']~=nil,'backup exists');check(model.status().nodes[1].synced,'synced status')
local now=json.parse(files[CONF]);check(now.plugins[1].args.exps[1]=='full:keep.example.com','preserve manual entry');check(now.plugins[4].args.listen==':5335','production port preserved')
local before=files[CONF];check(model.change(false).ok,'repeat sync');check(files[CONF]==before,'idempotent')
rows={{address='next.example.com'}};check(model.change(false).ok,'changed nodes sync');local ex=json.parse(files[CONF]).plugins[1].args.exps;check(#ex==2 and ex[2]=='full:next.example.com','remove only managed stale entries')
check(model.change(true).ok,'restore');check(json.parse(files[CONF]).plugins[1].args.exps[2]=='full:node.example.com','restore previous config')
reset();rows={{address='new.example.com'}};fail='validation';old=files[CONF];check(not model.change(false).ok,'validation fails closed');check(files[CONF]==old,'failed preflight leaves config intact')
reset();rows={{address='new.example.com'}};fail='restart';old=files[CONF];check(not model.change(false).ok,'restart failure reported');check(files[CONF]==old,'restart failure rolls back')
reset();active='/var/etc/mosdns.json';check(not model.change(false).ok,'incompatible active config refused')
reset();local insecure=copy(cfg);insecure.plugins[2].args.upstreams[1].socks5='127.0.0.1:1070';files[CONF]=json.stringify(insecure);check(not model.status().ok,'proxy-dependent bootstrap refused')
reset();locked=true;check(not model.change(false).ok,'concurrent operation refused')
reset();check(not model.change(true).ok,'missing backup refused')
reset();rows={{address='keep.example.com'}};check(model.change(false).ok,'existing manual entry');rows={};check(model.change(false).ok,'empty nodes sync');check(json.parse(files[CONF]).plugins[1].args.exps[1]=='full:keep.example.com','manual entry never owned/deleted')
print('PASS '..count..' backend assertions (isolated mocks)')
