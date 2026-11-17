# Surge Monitor Pro v3.2.0

Surge iOS / macOS 只读内存监控面板。**v3.2.0 重新设计了狭窄卡片中的展示布局**：不再使用容易显示为巨大方块的 Unicode 柱形图和多余段落。默认紧凑显示，详细信息按需开启。

## 安装/升级

原来的模块 URL 不变（更新模块后也更新外部脚本）：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

新脚本固定版本 URL：

https://raw.githubusercontent.com/xytxg/test/main/Surge/scripts/surge-monitor-pro-v3.2.0.js

建议更新步骤：Surge → 模块 → Surge Monitor Pro → 更新；再到外部资源更新；重新进入策略组查看面板。如果旧界面仍在，请确认模块中的所有 script-path 都指向 v3.2.0.js，排除远程脚本缓存。

## 紧凑模式（默认）

示意值（非实时）：

```text
Surge 状态监控
内存 30.4 MiB  ↑0.4
1h均 30.7 · 24h峰 31.9
本次最低 14.7 MiB
近30分 +0.7 MiB
请求 35 · DNS 200 (+0)
运行 10时38分
重载 3次 · 12:06
采样 18:00 · 刚刚
Surge 6.100.0 (4032)
```

- 峰值/最低值是**成功采样观察到的值**，不是 iOS 系统中真实的连续内存峰值。
- `1h均` 是最近约 1 小时有效观测的算术平均数；`24h峰` 是过去 24 小时有效样本的最大值。`本次最低` 是本次引擎会话采样最低值。
- `近30分` 是对比距最新采样约 30 分钟的可用样本；没有可比值时直接隐藏。
- DNS 括号中的值是约 30 分钟缓存条目变化，不代表 DNS 故障或内存泄漏。
- 内存方向箭头是与上一个连续样本相比的差值。**默认不再展示文字模拟的柱状图**，避免 Surge 面板字体把方块渲染得过大。
- 当 6 个连续的约 6 分钟样本覆盖约 30 分钟，且总增长达到 `growth_mib` 默认 10 MiB，会显示橙色内存持续上涨预警。这不是泄漏判定。
- 采样连续失败、最后成功样本超过 18 分钟或内存超阈值时，面板出现橙色提示。不会自动清理内存或重启引擎。

## 详细模式

模块参数中将 `view` 改为 `detail`，可额外查看引擎启动时间、重载前后内存差值（仅显示一小时内可比结果）、有效样本条数。默认保持 `compact` 更适合 iPhone。

## 采样结构及兼容性

- 面板 `XY_Surge_Monitor`：只读；进入策略组后按 Surge 的面板更新机制刷新，不增加样本。
- Cron `XY_Surge_Sampler`：每 6 分钟计划采样一次，至多每小时 10 次，可设置 `wake=false` 降低后台唤醒尝试。
- 事件 `engine-started`：启动后采样，重启后隔离旧会话。
- 事件 `profile-reloaded`：统计真实发生的重载事件，与配置文本是否变化不是一回事。
- 持久化键仍是 `xy_surge_monitor_pro_v3`，不主动清空 v3.0/v3.1 历史数据；最多保留 240 个采样点，长期峰值/最低值仍按同次引擎会话保留。
- 同一次启动/定时任务在 30 秒内产生的重复采样合并。数据缺失不会补零、插值或伪装为实时数据。
- 版本化的远程脚本 URL 避免之前的 `timeOf` 缓存故障，代码中不存在 `timeOf()` 调用。
- 不增加 MITM、请求拦截、远程上报和额外的 Cron 定时任务。HTTP API 密钥只存于本机模块参数，不应提交至仓库或暴露公网。

## 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `api_key` | 空 | 访问本机 API 的密钥；使用明文 Prometheus /v1/metrics 时推荐填写 |
| `api_port` | 6171 | 本机 HTTP API 端口 |
| `wake` | true | 是否尝试通过静默通知唤醒定时采样（iOS） |
| `tap` | refresh | 右上角刷新只读；设置 reload 才允许手动重载配置 |
| `warn_mib` | 45 | 引擎内存橙色预警阈值 MiB |
| `growth_mib` | 10 | 连续约 30 分钟内存增长预警阈值 MiB |
| `view` | compact | 面板界面：compact（默认）/detail |

## 官方参考

- [Information Panel](https://manual.nssurge.com/tools/panel.html)
- [HTTP API / Prometheus](https://manual.nssurge.com/tools/http-api.html)
- [Cron Script](https://manual.nssurge.com/scripting/cron.html)
- [Event Script](https://manual.nssurge.com/scripting/event.html)

## 验证

本项目包含模拟 Surge 脚本环境的 Node 测试：`node Surge/tests/surge-monitor-pro.test.cjs`。模拟测试覆盖只读面板、定时采样、历史继承、自动重载计数、峰值/最低、DNS 差值、连续增长与故障恢复。不代表已经在你的 iPhone 上验证 iOS 后台调度。
