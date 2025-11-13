# relaywatch 无线中继看门狗

## 项目简介
relaywatch 是面向 OpenWrt 的无线中继稳连解决方案，提供后台守护进程 `relaywatchd` 与 LuCI 管理界面。守护进程负责对接入网的无线 STA 接口进行健康检测、自动切换候选热点，并维持 relayd 桥接的可用性。LuCI 前端提供候选列表维护、实时状态查看与手动操作入口。

## 核心特性
- **多策略健康检测**：支持 Ping 与 HTTP 方式，按优先顺序组合执行。
- **自动切换与黑名单**：连续失败后自动在候选列表中切换，并为不可用候选打入黑名单。
- **热点可见性校验**：在切换前调用 `ubus iwinfo` 扫描，确保目标热点实际可见后再尝试连接。
- **状态可视化**：通过 `/var/run/relaywatch/state.json` 与 `/var/log/relaywatch.log` 暴露运行态，LuCI 页面可直接查看。
- **事件联动**：集成 wireless hotplug 钩子，实时响应关联/断开事件并触发快速检测。

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

## LuCI 使用流程
1. 访问 `网络 -> Relay Watch`，在“设置”页启用守护进程并填写检测/切换参数。
2. 在“候选列表”页录入多个热点及优先级，可选择 BSSID 锁定具体 AP。
3. “状态”页可查看当前连接信息、黑名单、日志，并支持手动检测、手动切换和扫描附近网络。
4. 当扫描到新的热点后，可根据结果手动添加到候选列表。

## 日志与排障
- 运行日志保存在 `/var/log/relaywatch.log`，状态文件位于 `/var/run/relaywatch/state.json`。
- 如需手动诊断，可执行 `/usr/sbin/relaywatchd --check`、`/usr/sbin/relaywatchd --switch <SSID>` 等命令。
- 当候选无法连接时，可查看状态文件中的 `blacklist` 字段，确认是否因黑名单被暂时禁用。

## 开发与测试建议
- 修改 shell/Lua 代码后建议运行 `shellcheck` 与 `luacheck`（如有配置）确保语法正确。
- 可通过模拟网络故障（屏蔽上游热点、关闭 DHCP）验证自动切换与回滚逻辑。
- 进行 LuCI 调试时，可在浏览器控制台查看 Ajax 返回的 JSON，用于排查前端交互问题。

## 已知限制
- 当前尚未实现指数退避策略，长时间网络不可用时仍可能频繁轮询候选。
- 候选导入按钮尚未在 LuCI 状态页实现，需要手动根据扫描结果添加候选。
- 依赖 `ubus iwinfo scan` 获取热点列表，若固件未包含 `iwinfo` JSON 接口则会跳过可见性校验。

## 许可证
本项目以 GPL-3.0-or-later 授权发布。
