module("luci.controller.node_dns_assistant", package.seeall)
function index()
 local p={"admin","services","node_dns_assistant"}
 entry(p,template("node_dns_assistant/index"),_("代理节点 DNS 助手"),59).dependent=false
 entry({"admin","services","node_dns_assistant","status"},call("status_action")).leaf=true
 entry({"admin","services","node_dns_assistant","apply"},post("apply_action")).leaf=true
 entry({"admin","services","node_dns_assistant","restore"},post("restore_action")).leaf=true
end
local function respond(value)
 local h=require "luci.http"
 h.prepare_content("application/json");h.write_json(value)
end
function status_action() respond(require("luci.model.node_dns_assistant").status()) end
function apply_action() respond(require("luci.model.node_dns_assistant").change(false)) end
function restore_action() respond(require("luci.model.node_dns_assistant").change(true)) end
