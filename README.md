# relaywatch 无线中继看门狗

## 项目简介（中文）
relaywatch 是面向 OpenWrt 的无线中继稳连解决方案，提供后台守护进程 `relaywatchd` 与 LuCI 管理界面。守护进程负责对接入网的无线 STA 接口进行健康检测、自动切换候选热点，并维持 relayd 桥接的可用性。LuCI 前端提供候选列表维护、实时状态查看与手动操作入口。

## 核心特性
- **多策略健康检测**：支持 Ping 与 HTTP 方式，按优先顺序组合执行，可灵活扩展检测目标。
- **自动切换、黑名单与指数退避**：连续失败后自动在候选列表中切换，对不可用候选打黑名单，并根据失败轮次指数延长冷却时间，避免频繁震荡。
- **热点可见性校验**：在切换前调用 `ubus iwinfo` 扫描，确保目标热点实际可见后再尝试连接，减少无效切换。
- **状态可视化**：通过 `/var/run/relaywatch/state.json` 与 `/var/log/relaywatch.log` 暴露运行态，LuCI 页面可直接查看实时信号、IP 与下一次切换时间。
- **事件联动**：集成 wireless hotplug 钩子，实时响应关联/断开事件并触发快速检测。
- **一键导入候选**：LuCI 状态页支持从扫描结果直接导入候选网络，自动填充 SSID/BSSID。

## 目录结构
```
package/network/services/relaywatch/  # 守护进程及默认配置
feeds/luci/applications/luci-app-relaywatch/  # LuCI 前端
.cursor/plans/l-82b8a035.plan.md  # 项目开发计划与进度
```

## 安装部署
1. 将本仓库放入 OpenWrt 源码树，例如 `package/network/services/relaywatch` 与 `feeds/luci/applications/luci-app-relaywatch`。
2. 运行 `./scripts/feeds update -a && ./scripts/feeds install luci-app-relaywatch` 以确保依赖齐全。
3. 在菜单配置中勾选 `Network -> relaywatch` 与 `LuCI -> Applications -> luci-app-relaywatch`。
4. 执行 `make package/relaywatch/compile V=s` 与 `make package/luci-app-relaywatch/compile V=s` 生成 IPK。
5. 将编译产物复制至目标设备并使用 `opkg install *.ipk` 安装。

## 配置说明
- 默认配置文件位于 `/etc/config/relaywatch`，示例中包含一个候选网络条目，可按实际热点修改 SSID、密钥及优先级。
- `iface` 应指向无线 STA 接口对应的 `wifi-iface` 段名（如 `wwan`）。
- `lan_bridge` 与 `relayd_instance` 需与现有 relayd 桥接配置一致。
- `check_method` 可填写 `ping`、`http` 或组合（逗号分隔），`check_target` 支持多个 IP/URL。
- `switch_cooldown` 指定切换成功后的基础冷却时间，`switch_backoff_max` 限定指数退避的最大等待秒数。

## LuCI 使用流程
1. 访问 `网络 -> Relay Watch`，在“设置”页启用守护进程并填写检测/切换参数。
2. 在“候选列表”页录入多个热点及优先级，可选择 BSSID 锁定具体 AP。
3. “状态”页可查看当前连接信息（含信号、噪声、IP、下一次切换窗口）、黑名单、日志，并支持手动检测、手动切换和扫描附近网络。
4. 当扫描到新的热点后，可直接点击“导入”按钮生成候选条目（密钥需在“候选列表”页补充）。

## 日志与排障
- 运行日志保存在 `/var/log/relaywatch.log`，状态文件位于 `/var/run/relaywatch/state.json`。
- 如需手动诊断，可执行 `/usr/sbin/relaywatchd --check`、`/usr/sbin/relaywatchd --switch <SSID>` 等命令。
- 当候选无法连接时，可查看状态文件中的 `blacklist` 字段，确认是否因黑名单被暂时禁用。

## 开发与测试建议
- 修改 shell/Lua 代码后建议运行 `shellcheck` 与 `luacheck`（如有配置）确保语法正确。
- 可通过模拟网络故障（屏蔽上游热点、关闭 DHCP）验证自动切换与回滚逻辑。
- 进行 LuCI 调试时，可在浏览器控制台查看 Ajax 返回的 JSON，用于排查前端交互问题。
- 可执行 `sh tests/relaywatchd/test_relaywatchd.sh` 运行内置单元测试，覆盖黑名单刷新与候选切换的核心路径。

### 回归测试矩阵

| 场景 | 操作步骤 | 预期结果 |
| --- | --- | --- |
| 上游 AP 掉线 | 关闭主热点电源，等待守护进程检测失败 | 守护进程在冷却期结束后切换到下一个可用候选，并在状态页记录切换事件与新窗口。 |
| DHCP 服务异常 | 在切换后阻断上游 DHCP，或清空租约不响应 | 守护进程判定健康检查失败，将候选加入黑名单并尝试下一候选，黑名单列表同步更新。 |
| 门户重定向 | 在上游启用 Web Portal，干扰 HTTP 访问 | HTTP 健康检测连续失败，守护进程执行指数退避并保留冷却剩余时间提示。 |
| 弱信号/远离 AP | 人为增加 AP 与客户端距离造成高丢包 | 状态页 RSSI/质量下降，失败轮次累积并触发切换，日志记录信号指标。 |
| 手动导入候选 | 使用状态页扫描后点击“导入” | LuCI 提示导入成功并在候选列表中生成条目，提醒补充密码。 |
## 已知限制
- 依赖 `ubus iwinfo` 获取热点列表与关联信息，若固件缺少 JSON 接口将自动降级为基础模式，状态页可能缺失部分指标。
- 老旧固件在缺省 `jsonfilter` 或 `uclient-fetch` 时需要手动安装依赖，否则健康检查与扫描能力会受限。
- 新功能仍需在多语言环境中同步维护 `po` 文本，避免中英文界面不一致。

## 许可证
本项目以 GPL-3.0-or-later 授权发布。

## Project Overview (English)
relaywatch is an OpenWrt-oriented solution that keeps wireless relay connections healthy. It ships a background daemon `relaywatchd` to monitor uplink status and automatically failover between predefined candidates, plus a LuCI interface for configuration, manual actions, and observability. The daemon works with relayd and the wireless STA interface, maintaining state files and logs for troubleshooting.

### Key Features
- Multi-strategy health checks (Ping/HTTP) with prioritized combinations.
- Automatic switching with blacklist and exponential backoff to avoid oscillation.
- Visibility validation via `ubus iwinfo` before attempting to associate with a target.
- State exposure through `/var/run/relaywatch/state.json` and `/var/log/relaywatch.log`, rendered on the LuCI status page.
- Wireless hotplug integration to react quickly to association or disconnection events.
- One-click candidate import from scan results in the LuCI status page.

### Repository Layout
- `package/network/services/relaywatch/`: daemon scripts and default configuration.
- `feeds/luci/applications/luci-app-relaywatch/`: LuCI front-end implementation.
- `.cursor/plans/l-82b8a035.plan.md`: project plan and progress tracking.

### Getting Started
1. Place the repository under the OpenWrt source tree (same paths as above).
2. Run `./scripts/feeds update -a && ./scripts/feeds install luci-app-relaywatch` to ensure dependencies.
3. Enable `Network -> relaywatch` and `LuCI -> Applications -> luci-app-relaywatch` in menuconfig.
4. Build IPKs with `make package/relaywatch/compile V=s` and `make package/luci-app-relaywatch/compile V=s`.
5. Transfer the packages to the device and install via `opkg install *.ipk`.

### License
GPL-3.0-or-later
