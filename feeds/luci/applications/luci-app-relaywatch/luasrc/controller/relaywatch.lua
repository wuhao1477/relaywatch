module("luci.controller.relaywatch", package.seeall)

-- 控制器负责注册 LuCI 路由与 Ajax 接口
local http = require "luci.http"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local jsonc = require "luci.jsonc"
local util = require "luci.util"
local uci = require "luci.model.uci".cursor()
local ubus_call = util.ubus or function() return nil end

local STATE_FILE = "/var/run/relaywatch/state.json"
local LOG_FILE = "/var/log/relaywatch.log"

local function normalize_encryption(enc)
        if type(enc) ~= "table" then
                return "none"
        end

        if enc.enabled == false then
                return "none"
        end

        if enc.wep == true or (type(enc.authentication) == "string" and enc.authentication:lower():find("wep")) then
                return "wep"
        end

        local has_wpa1, has_wpa2, has_wpa3
        if type(enc.wpa_version) == "table" then
                for _, v in ipairs(enc.wpa_version) do
                        if v == 1 then
                                has_wpa1 = true
                        elseif v == 2 then
                                has_wpa2 = true
                        elseif v == 3 then
                                has_wpa3 = true
                        end
                end
        end

        if has_wpa3 and has_wpa2 then
                return "sae-mixed"
        elseif has_wpa3 then
                return "sae"
        elseif has_wpa2 and has_wpa1 then
                return "psk-mixed"
        elseif has_wpa2 then
                return "psk2"
        elseif has_wpa1 then
                return "psk"
        end

        if type(enc.authentication) == "string" and enc.authentication:lower():find("psk") then
                return "psk"
        end

        return "none"
end

-- 解析守护进程绑定的 STA 接口配置段名称
local function resolve_sta_section()
        return uci:get("relaywatch", "global", "iface") or "wwan"
end

-- 通过 ubus 返回的无线状态获取实际的 ifname
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

-- 注册菜单入口与动作接口
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
        entry({"admin", "network", "relaywatch", "action", "import"}, call("action_import")).leaf = true
        entry({"admin", "network", "relaywatch", "action", "state"}, call("action_state")).leaf = true
end

-- 调用 iwinfo 扫描周边 AP，并将结果以 JSON 返回
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
                local suggestion = normalize_encryption(ap.encryption)
                result[#result + 1] = {
                        ssid = ap.ssid,
                        bssid = ap.bssid,
                        signal = ap.signal,
                        noise = ap.noise,
                        quality = ap.quality,
                        quality_max = ap.quality_max,
                        channel = ap.channel,
                        encryption = ap.encryption and ap.encryption.description or "",
                        encryption_suggestion = suggestion
                }
        end

        http.write_json({ results = result, ifname = ifname })
end

-- 触发一次守护进程的即时健康检查
function action_check()
        local rc = sys.call("/usr/sbin/relaywatchd --check >/dev/null 2>&1")
        http.prepare_content("application/json")
        http.write_json({
                status = (rc == 0) and "ok" or "fail"
        })
end

-- 调用守护进程命令行执行手动切换
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

-- 根据扫描结果快速导入候选网络
function action_import()
        local ssid = http.formvalue("ssid") or ""
        local bssid = http.formvalue("bssid") or ""
        local encryption = http.formvalue("encryption") or ""
        local priority = http.formvalue("priority") or ""
        http.prepare_content("application/json")

        if ssid == "" then
            http.write_json({ status = "fail", message = "missing-ssid" })
            return
        end

        if encryption == "" then
                encryption = "none"
        end

        if bssid ~= "" then
                bssid = bssid:upper()
        end

        local exists
        uci:foreach("relaywatch", "candidate", function(s)
                if s.ssid == ssid then
                        local sbssid = (s.bssid or ""):lower()
                        if bssid == "" or sbssid == bssid:lower() then
                                exists = s[".name"]
                                return false
                        end
                end
        end)

        if exists then
                http.write_json({ status = "exists", section = exists })
                return
        end

        local section = uci:add("relaywatch", "candidate")
        if not section then
                http.write_json({ status = "fail", message = "uci-add-failed" })
                return
        end

        uci:set("relaywatch", section, "ssid", ssid)
        if bssid ~= "" then
                uci:set("relaywatch", section, "bssid", bssid)
        end
        uci:set("relaywatch", section, "encryption", encryption)
        if priority == "" then
                priority = "10"
        end
        uci:set("relaywatch", section, "priority", priority)

        uci:commit("relaywatch")

        local needs_key = encryption ~= "none" and encryption ~= ""

        http.write_json({
                status = "ok",
                section = section,
                needs_key = needs_key,
                ssid = ssid,
                encryption = encryption
        })
end

-- 汇总状态文件与日志尾部，供前端刷新状态
function action_state()
        local state = {}
        local stat_mtime
        if fs.access(STATE_FILE) then
                local raw = fs.readfile(STATE_FILE)
                if raw and #raw > 0 then
                        state = jsonc.parse(raw) or {}
                end
                stat_mtime = fs.stat(STATE_FILE, "mtime")
        end

        local lines = tonumber(http.formvalue("log_lines") or "") or 40
        if lines < 10 then
                lines = 10
        elseif lines > 200 then
                lines = 200
        end

        local log_tail = ""
        if fs.access(LOG_FILE) then
                log_tail = sys.exec(string.format("tail -n %d %q 2>/dev/null", lines, LOG_FILE))
        end

        http.prepare_content("application/json")
        http.write_json({
                state = state,
                log = log_tail,
                log_lines = lines,
                state_mtime = stat_mtime
        })
end
