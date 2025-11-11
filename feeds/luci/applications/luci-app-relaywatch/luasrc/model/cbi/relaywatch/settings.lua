local uci = require "luci.model.uci".cursor()

local m = Map("relaywatch", translate("Relay Watch"), translate("Configure watchdog policies and relayd-aware health checks."))

local s = m:section(NamedSection, "global", "relaywatch", translate("Daemon & Policy"))
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("Enable relaywatchd daemon"))
enabled.rmempty = false
enabled.default = enabled.enabled

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

local lan = s:option(Value, "lan_bridge", translate("LAN Bridge"))
lan.placeholder = "br-lan"
lan.datatype = "string"

local relayd = s:option(Value, "relayd_instance", translate("Relayd Instance"))
relayd.placeholder = "bridge"
relayd.datatype = "uciname"

local method = s:option(Value, "check_method", translate("Health Check Method"))
method.rmempty = false
method.placeholder = "ping,http"
method.description = translate("Comma-separated methods such as ping,http.")

local target = s:option(Value, "check_target", translate("Health Check Targets"))
target.placeholder = "1.1.1.1,8.8.8.8"
target.description = translate("Comma-separated IPv4/URL targets used for health checks.")

local interval = s:option(Value, "check_interval", translate("Check Interval (s)"))
interval.datatype = "uinteger"
interval.placeholder = "30"

local fail = s:option(Value, "fail_threshold", translate("Failure Threshold"))
fail.datatype = "uinteger"
fail.placeholder = "3"

local cooldown = s:option(Value, "switch_cooldown", translate("Switch Cooldown (s)"))
cooldown.datatype = "uinteger"
cooldown.placeholder = "120"

local blacklist = s:option(Value, "blacklist_time", translate("Blacklist Time (s)"))
blacklist.datatype = "uinteger"
blacklist.placeholder = "600"

local renew = s:option(Flag, "dhcp_renew", translate("Renew DHCP After Switch"))
renew.default = renew.enabled
renew.description = translate("Applies ubus renew on the STA interface once a new uplink is established.")

return m
