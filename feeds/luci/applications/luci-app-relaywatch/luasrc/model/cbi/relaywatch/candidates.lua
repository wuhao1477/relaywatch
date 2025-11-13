-- 候选网络列表：维护回程 WLAN 的优先级与认证信息
local m = Map("relaywatch", translate("Candidate Networks"), translate("Manage the relay backhaul candidates and their priorities."))

local s = m:section(TypedSection, "candidate", translate("Backhaul Candidates"))
s.template = "cbi/tblsection"
s.addremove = true
s.anonymous = true
s.sortable = true

-- SSID 必填
local ssid = s:option(Value, "ssid", translate("SSID"))
ssid.rmempty = false

-- 加密类型选择
local enc = s:option(ListValue, "encryption", translate("Encryption"))
enc.rmempty = false
enc.default = "psk2"
enc:value("none", translate("None (open)"))
enc:value("wep", translate("WEP"))
enc:value("psk", translate("WPA-PSK"))
enc:value("psk2", translate("WPA2-PSK"))
enc:value("sae", translate("WPA3-SAE"))
enc:value("psk-mixed", translate("WPA/WPA2 Mixed"))
enc:value("sae-mixed", translate("WPA2/WPA3 Mixed"))

-- 密码字段，根据加密模式决定是否展示
local key = s:option(Value, "key", translate("Password / Key"))
key.password = true
key.rmempty = true
key.placeholder = "password"
key:depends("encryption", "wep")
key:depends("encryption", "psk")
key:depends("encryption", "psk2")
key:depends("encryption", "psk-mixed")
key:depends("encryption", "sae")
key:depends("encryption", "sae-mixed")

-- 可选 BSSID，便于锁定具体 AP
local bssid = s:option(Value, "bssid", translate("BSSID (optional)"))
bssid.placeholder = "AA:BB:CC:DD:EE:FF"
bssid.datatype = "macaddr"
bssid.rmempty = true

-- 候选优先级，数值越大越优先
local priority = s:option(Value, "priority", translate("Priority"))
priority.datatype = "integer"
priority.rmempty = false
priority.default = "10"
priority.description = translate("Higher values will be preferred during failover.")

-- 可暂时禁用候选
local disabled = s:option(Flag, "disabled", translate("Disabled"))
disabled.default = disabled.disabled

return m
