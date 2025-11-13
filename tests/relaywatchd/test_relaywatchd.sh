#!/bin/sh
# 简易单元测试：覆盖黑名单逻辑与切换成功/失败路径

set -eu

SCRIPT_DIR="$(dirname "$0")"
ROOT_DIR="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(CDPATH= cd "$ROOT_DIR/.." && pwd)"
RELAYWATCHD="$ROOT_DIR/package/network/services/relaywatch/files/usr/sbin/relaywatchd"

export RELAYWATCHD_TEST_MODE=1

BASE_TMP="$(mktemp -d)"
trap 'rm -rf "$BASE_TMP"' EXIT
TMP_BASE="$BASE_TMP/runtime"
mkdir -p "$TMP_BASE"

MOCK_ROOT="$BASE_TMP/mock"
mkdir -p "$MOCK_ROOT/lib/functions" "$MOCK_ROOT/usr/share/libubox"

cat > "$MOCK_ROOT/lib/functions.sh" <<'EOF'
config_load() { :; }
config_foreach() { :; }
config_get() { :; }
config_get_bool() { :; }
uci() { :; }
EOF

cat > "$MOCK_ROOT/lib/functions/network.sh" <<'EOF'
network_get_device() { return 1; }
EOF

cat > "$MOCK_ROOT/usr/share/libubox/jshn.sh" <<'EOF'
json_init() { :; }
json_add_int() { :; }
json_add_string() { :; }
json_add_array() { :; }
json_add_object() { :; }
json_close_array() { :; }
json_close_object() { :; }
json_dump() { :; }
EOF

export RELAYWATCHD_LIB_PREFIX="$MOCK_ROOT/lib"
export RELAYWATCHD_UBOX_PREFIX="$MOCK_ROOT/usr/share/libubox"

# shellcheck source=/dev/null
. "$RELAYWATCHD"

# 覆盖日志输出，避免依赖系统 logger
log_buffer=""
log_msg() {
        local level="$1"
        shift
        log_buffer="${log_buffer}${level}:$*\n"
}

rotate_log() { :; }

assert_true() {
        [ "$1" -eq 0 ] || {
                echo "断言失败: $2" >&2
                exit 1
        }
}

assert_equals() {
        local expect="$1"
        local actual="$2"
        local msg="$3"
        [ "$expect" = "$actual" ] || {
                echo "断言失败: $msg (期望=$expect, 实际=$actual)" >&2
                exit 1
        }
}

reset_runtime() {
        local tmp
        tmp="$(mktemp -d "$TMP_BASE/testXXXX")"
        STATE_DIR="$tmp/state"
        STATE_FILE="$STATE_DIR/state.json"
        PID_FILE="$STATE_DIR/pid"
        BLACKLIST_FILE="$STATE_DIR/blacklist"
        HOTPLUG_FILE="$STATE_DIR/hotplug_event"
        LOG_FILE="$tmp/log"
        ensure_state_dir
        BLACKLIST_ACTIVE=""
        CURRENT_FAILS=0
        FAIL_ROUNDS=0
        NEXT_SWITCH_ALLOWED=0
        LAST_GOOD_KEY=""
        CANDIDATE_COUNT=0
}

test_blacklist_add_refresh() {
        reset_runtime
        blacklist_refresh
        local test_key="demo|any"
        blacklist_add "$test_key" 30 reason
        blacklist_refresh
        if ! blacklist_contains "$test_key"; then
                echo "断言失败: 黑名单应包含新增条目" >&2
                exit 1
        fi
}

test_switch_success_updates_state() {
        reset_runtime
        CANDIDATE_COUNT=1
        CAND_SECTION_0="cand0"
        CAND_SSID_0="AP_TEST"
        CAND_BSSID_0=""
        CAND_ENC_0="psk2"
        CAND_KEY_0="secret"
        CAND_PRIORITY_0=50
        SWITCH_COOLDOWN=40
        SWITCH_BACKOFF_MAX=300
        STUB_APPLY_CALLS=0

        apply_candidate() {
                STUB_APPLY_CALLS=$((STUB_APPLY_CALLS + 1))
                CURRENT_SSID="AP_TEST"
                CURRENT_BSSID=""
                CURRENT_SECTION="cand0"
                CURRENT_CANDIDATE_KEY="$(build_candidate_key "AP_TEST" "")"
                LAST_GOOD_KEY="$CURRENT_CANDIDATE_KEY"
                return 0
        }

        local now_before
        now_before=$(date +%s)
        local rc
        if maybe_switch_candidate; then
                rc=0
        else
                rc=$?
        fi
        assert_true "$rc" "切换应成功"
        assert_equals "1" "$STUB_APPLY_CALLS" "切换应调用一次 apply_candidate"
        [ "$FAIL_ROUNDS" -eq 0 ] || {
                echo "断言失败: FAIL_ROUNDS 应归零" >&2
                exit 1
        }
        [ "$NEXT_SWITCH_ALLOWED" -ge "$now_before" ] || {
                echo "断言失败: 下一次切换窗口需在当前时间之后" >&2
                exit 1
        }
        [ "$CURRENT_CANDIDATE_KEY" = "AP_TEST|any" ] || {
                echo "断言失败: 当前候选键应更新" >&2
                exit 1
        }
}

test_switch_failure_triggers_blacklist() {
        reset_runtime
        CANDIDATE_COUNT=1
        CAND_SECTION_0="cand1"
        CAND_SSID_0="AP_FAIL"
        CAND_BSSID_0=""
        CAND_ENC_0="none"
        CAND_KEY_0=""
        CAND_PRIORITY_0=10
        SWITCH_COOLDOWN=10
        SWITCH_BACKOFF_MAX=60
        BLACKLIST_TIME=20
        LAST_GOOD_KEY=""

        apply_candidate() {
                return 1
        }

        local rc
        if maybe_switch_candidate; then
                rc=0
        else
                rc=$?
        fi
        [ "$rc" -ne 0 ] || {
                echo "断言失败: 切换失败应返回非零" >&2
                exit 1
        }
        blacklist_refresh
        printf "%s" "$BLACKLIST_ACTIVE" | grep -q "AP_FAIL|any:" || {
                echo "断言失败: 失败候选应加入黑名单" >&2
                exit 1
        }
        [ "$FAIL_ROUNDS" -eq 1 ] || {
                echo "断言失败: FAIL_ROUNDS 应递增" >&2
                exit 1
        }
        [ "$NEXT_SWITCH_ALLOWED" -gt 0 ] || {
                echo "断言失败: 应记录回退窗口" >&2
                exit 1
        }
}

test_blacklist_add_refresh
test_switch_success_updates_state
test_switch_failure_triggers_blacklist

echo "relaywatchd 单元测试通过"
