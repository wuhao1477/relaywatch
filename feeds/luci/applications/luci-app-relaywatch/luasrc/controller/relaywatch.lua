module("luci.controller.relaywatch", package.seeall)

local http = require "luci.http"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local jsonc = require "luci.jsonc"
local util = require "luci.util"
local uci = require "luci.model.uci".cursor()
local ubus_call = util.ubus or function() return nil end

local STATE_FILE = "/var/run/relaywatch/state.json"
local LOG_FILE = "/var/log/relaywatch.log"

local function resolve_sta_section()
	return uci:get("relaywatch", "global", "iface") or "wwan"
end

local function resolve_ifname()
	local section = resolve_sta_section()
	local status = ubus_call("network.wireless", "status", {}) or {}
	for _, radio in pairs(status) do
		local interfaces = radio.interfaces or {}
		for _, iface in ipairs(interfaces) do
			if iface.section == section then
				return iface.ifname or iface.device
			end
		end
	end
	return uci:get("wireless", section, "ifname")
end

function index()
	if not fs.access("/etc/config/relaywatch") then
		return
	end

	local page = entry({"admin", "network", "relaywatch"}, firstchild(), _("Relay Watch"), 60)
	page.dependent = true

	entry({"admin", "network", "relaywatch", "status"}, template("relaywatch/status"), _("Status"), 1).leaf = true
	entry({"admin", "network", "relaywatch", "settings"}, cbi("relaywatch/settings"), _("Settings"), 2).leaf = true
	entry({"admin", "network", "relaywatch", "candidates"}, cbi("relaywatch/candidates"), _("Candidates"), 3).leaf = true

	entry({"admin", "network", "relaywatch", "action", "scan"}, call("action_scan")).leaf = true
	entry({"admin", "network", "relaywatch", "action", "check"}, call("action_check")).leaf = true
	entry({"admin", "network", "relaywatch", "action", "switch"}, call("action_switch")).leaf = true
	entry({"admin", "network", "relaywatch", "action", "state"}, call("action_state")).leaf = true
end

function action_scan()
	local ok, iwinfo = pcall(require, "iwinfo")
	http.prepare_content("application/json")
	if not ok then
		http.write_json({ error = "iwinfo-missing" })
		return
	end

	local ifname = resolve_ifname()
	if not ifname then
		http.write_json({ error = "iface-down" })
		return
	end

	local t = iwinfo.type(ifname)
	if not t or not iwinfo[t] or not iwinfo[t].scanlist then
		http.write_json({ error = "scan-unsupported", ifname = ifname })
		return
	end

	local list = iwinfo[t].scanlist(ifname) or {}
	local result = {}
	for _, ap in ipairs(list) do
		result[#result + 1] = {
			ssid = ap.ssid,
			bssid = ap.bssid,
			signal = ap.signal,
			channel = ap.channel,
			encryption = ap.encryption and ap.encryption.description or ""
		}
	end

	http.write_json({ results = result, ifname = ifname })
end

function action_check()
	local rc = sys.call("/usr/sbin/relaywatchd --check >/dev/null 2>&1")
	http.prepare_content("application/json")
	http.write_json({
		status = (rc == 0) and "ok" or "fail"
	})
end

function action_switch()
	local token = http.formvalue("token") or ""
	http.prepare_content("application/json")
	if token == "" then
		http.write_json({ status = "fail", message = "missing token" })
		return
	end
	local cmd = string.format("/usr/sbin/relaywatchd --switch %q >/dev/null 2>&1", token)
	local rc = sys.call(cmd)
	http.write_json({
		status = (rc == 0) and "ok" or "fail",
		token = token
	})
end

function action_state()
	local state = {}
	if fs.access(STATE_FILE) then
		state = jsonc.parse(fs.readfile(STATE_FILE)) or {}
	end
	local log_tail = sys.exec(string.format("tail -n 40 %q 2>/dev/null", LOG_FILE))
	http.prepare_content("application/json")
	http.write_json({
		state = state,
		log = log_tail
	})
end
