local uci = require "luci.model.uci".cursor()

-- 全局配置表单：用于管理守护进程策略与健康检测参数
local m = Map("relaywatch", translate("Relay Watch"), translate("Configure watchdog policies and relayd-aware health checks."))

local s = m:section(NamedSection, "global", "relaywatch", translate("Daemon & Policy"))
s.addremove = false

-- 是否启用守护进程
local enabled = s:option(Flag, "enabled", translate("Enable relaywatchd daemon"))
enabled.rmempty = false
enabled.default = enabled.enabled

-- 绑定的 STA 接口配置段
local iface = s:option(Value, "iface", translate("STA Interface Section"))
iface.rmempty = false
iface.datatype = "uciname"
iface.placeholder = "wwan"
uci:foreach("wireless", "wifi-iface", function(sec)
	if sec[".name"] then
		local label = sec.ssid and string.format("%s (%s)", sec[".name"], sec.ssid) or sec[".name"]
		iface:value(sec[".name"], label)
	end
end)

-- relayd 所依赖的 LAN 桥名称
local lan = s:option(Value, "lan_bridge", translate("LAN Bridge"))
lan.placeholder = "br-lan"
lan.datatype = "string"

-- relayd 实例配置段
local relayd = s:option(Value, "relayd_instance", translate("Relayd Instance"))
relayd.placeholder = "bridge"
relayd.datatype = "uciname"

-- 健康检查方式，如 ping/http
local method = s:option(Value, "check_method", translate("Health Check Method"))
method.rmempty = false
method.placeholder = "ping,http"
method.description = translate("Comma-separated methods such as ping,http.")

-- 健康检查目标列表
local target = s:option(Value, "check_target", translate("Health Check Targets"))
target.placeholder = "1.1.1.1,8.8.8.8"
target.description = translate("Comma-separated IPv4/URL targets used for health checks.")

-- 检测间隔
local interval = s:option(Value, "check_interval", translate("Check Interval (s)"))
interval.datatype = "uinteger"
interval.placeholder = "30"

-- 连续失败阈值
local fail = s:option(Value, "fail_threshold", translate("Failure Threshold"))
fail.datatype = "uinteger"
fail.placeholder = "3"

-- 两次切换之间的冷却时间
local cooldown = s:option(Value, "switch_cooldown", translate("Switch Cooldown (s)"))
cooldown.datatype = "uinteger"
cooldown.placeholder = "120"

-- 黑名单封禁时长
local blacklist = s:option(Value, "blacklist_time", translate("Blacklist Time (s)"))
blacklist.datatype = "uinteger"
blacklist.placeholder = "600"

-- 切换后是否触发 DHCP renew
local renew = s:option(Flag, "dhcp_renew", translate("Renew DHCP After Switch"))
renew.default = renew.enabled
renew.description = translate("Applies ubus renew on the STA interface once a new uplink is established.")

return m
