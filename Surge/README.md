# Surge Monitor Pro v3.0.1 — 自动内存监控

**一个 Surge 信息面板，三个采集/事件入口。** 这不是“每点一次刷新就增加一个曲线点”的统计面板，而是用 Surge 官方的 Cron + Event + Shared Persistent Store 做尽力而为的定时采样。

## v3.0.1 紧急修复：timeOf 未定义与旧脚本缓存

故障日志：\`[Surge Monitor Pro] Can't find variable: timeOf\`。

v3.0.0 最初使用了未定义的 \`timeOf()\`，后来改为现有的 \`clock()\`，但远程脚本配置使用 \`script-update-interval=3600\`，手机在自动更新检查前可能仍执行缓存旧脚本。

v3.0.1 的所有 4 个脚本入口改为全新的独立 URL：

https://raw.githubusercontent.com/xytxg/test/main/Surge/scripts/surge-monitor-pro-v3.0.1.js

这样更新模块后会下载新文件，不依赖旧 URL 的更新检查到期。今后脚本远程更新检查间隔调整为 **600 秒**；这不是内存采样间隔，Cron 仍然是每 6 分钟。

### 修复安装步骤

1. Surge → **模块** → 找到 Surge Monitor Pro → **更新**。
2. 进入 Surge 的 **外部资源** → **全部更新**（或主动更新对应外部脚本）。
3. 关闭策略组弹窗，再打开并点一次右上角刷新；**不需要重启 Surge 引擎**。
4. 如果继续报 \`timeOf\`，说明还是运行旧缓存：检查本模块内 4 处 \`script-path\` 是否全部使用上面的 \`v3.0.1.js\`，必要时停用旧模块并通过原模块链接重新安装。

> 新增 15 项脚本模拟回归检查，涵盖无样本面板、Cron 采样、点击不污染历史、真实配置重载、指标失败、重启隔离与版本号读取。尚未在用户设备上验证系统真实后台调度。

## 安装与升级

在 Surge → 模块 → 安装新模块中使用原来的地址：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

已安装旧版：更新模块、更新外部脚本、重新启用模块，然后进入策略组页面。**v3 采用全新存储键** `xy_surge_monitor_pro_v3`，不继承旧版由手动刷新生成的趋势和峰值，避免新旧采样逻辑混合。模块更新时若引擎已经启动，启动事件不会补发；等待下一次 Cron 定时采样（最多约 6 分钟的常规调度等待，实际还受 iOS 后台执行限制）。

## 新版架构

| 模块内脚本 | 触发条件 | 权限/责任 |
| --- | --- | --- |
| `XY_Surge_Sampler` | Cron `*/6 * * * *`，每小时 10 次 | **独立采样**，读取 Surge 内存、活动请求和 DNS 缓存，写入带时间戳的历史 |
| `XY_Surge_OnStart` | `engine-started` | 引擎启动后建立该次会话的第一个采样点，自动隔离上次引擎的样本 |
| `XY_Surge_OnReload` | `profile-reloaded` | 真实记录 Surge 配置被重新加载的次数及最后时间 |
| `XY_Surge_Monitor` | 进入 Panel 或点右上角 | **只读显示**历史、运行时长与状态，不修改采样点、极值或趋势 |

Cron 频率设为 6 分钟是因为 Surge 官方文档对**每小时超过 10 次**的 cron 脚本发出耗电提醒。没有高频采样，就无法保证记录 6 分钟窗口内一闪而过的峰值。峰值/最低值始终是**成功采样的观测极值**，不是系统测得的精确全时峰值。

默认 `wake:true` 会设置 iOS `wake-system=true`，让 Surge 尝试以**静默本地通知**唤醒采样任务。**这不是保活承诺**：用户关闭 Surge、禁用脚本、iOS 后台策略干预、API 故障或其他系统条件仍可能导致采样缺失。高可靠监控应使用外部 Prometheus/Grafana 抓取 Surge 官方 `/v1/metrics`，本模块不假装具备这种可靠性。

如更关心耗电，可在模块参数中设置 `wake=false`。采样记录保留最多 240 个，最多约 24 小时的 6 分钟采样（若中途缺采样则跨越更长的实际时间）；曲线只显示最近 18 个**真实**样本，不做插值、补零或基于刷新动作制造样本。

## 面板示例（非实时数据）

    Surge 状态监控
    ▌ 内存  39.0 MiB · ↓0.3 MiB
      峰值 39.3 · 最低 39.0 MiB
      趋势  █▁
      采样 12:18:00 · 4 分钟前

    ▌ 运行  31 分 25 秒
      启动 11-15 11:51 · 重载 2 次
      活跃请求 21 · DNS 139
      最近重载 11-15 12:03

    Surge 6.100.0 (4027)
    面板更新 12:22:14

**注意**：这里的内存、活跃请求、DNS 和趋势是**最近一次自动采样时**的数据；运行时长及面板更新时间在每次进入页面时更新。Panel 不具备持续逐秒重绘能力。如果采样超过 18 分钟没有更新，会明确显示「可能暂停」，而不是默默使用旧数据冒充当前状态。Surge 的真实版本和 Build 由指标元信息优先提供，取不到才回退到脚本环境字段。

## 参数

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `api_key` | 空 | 推荐填写本机 Surge HTTP API 密钥，可靠读取 Prometheus **纯文本**指标 |
| `api_port` | `6171` | 本机 HTTP API 端口，需与 Surge 实际设置一致 |
| `wake` | `true` | Cron 的 iOS 静默唤醒尝试，可能有额外耗电；设为 `false` 可关闭 |
| `tap` | `refresh` | `refresh` 只读查看；仅显式设为 `reload` 才保留原版按钮配置重载功能 |
| `warn_mib` | `45` | 观测内存达到阈值时图标显示橙色，不发送通知或执行清理 |

**模块已移除停止/重启引擎的按钮行为**，避免监控工具影响 Surge 的运行状态；右上角默认不执行任何配置更改。若手动启用 `tap=reload`，会使用 `POST /v1/profiles/reload`；成功后的统计由真实 `profile-reloaded` 事件维护，避免按钮重复计数。

## API 配置与隐私

Surge 官方 `/v1/metrics` 是 Prometheus **纯文本**响应，而脚本内 `$httpAPI` 按文档主要返回 JSON；部分版本不能直接解析。因此建议在 Surge 设置中启用**仅绑定本机**的 HTTP API，把密钥只填入此模块在手机上的 `api_key` 参数。脚本用 `$httpClient` 请求 `http://127.0.0.1:6171/v1/metrics`，并发送 `X-Key`。无法取得指标时明确显示失败，**不伪造数据**。不要把密钥提交到 GitHub，也不要把 HTTP API 暴露在公网。

所有观察记录由 `$persistentStore` 存在本机，没有第三方遥测、外部账户、MITM 或流量劫持。内存指标是 **Surge 引擎物理内存**，不是 iOS 剩余可用内存；活动请求数也不等于所有 TCP 连接总数。

## 官方资料及验证

- [Surge Information Panel](https://manual.nssurge.com/tools/panel.html)：进入视图时检查 `update-interval`，不是实时秒表。
- [Surge Cron](https://manual.nssurge.com/scripting/cron.html)：Cron 调度、每小时超过 10 次的耗电提醒，以及 `wake-system`。
- [Surge Event](https://manual.nssurge.com/scripting/event.html)：`engine-started` 和 `profile-reloaded`。
- [Surge Scripting API](https://manual.nssurge.com/scripting/api.html)：`$httpAPI`、`$httpClient`、`$persistentStore` 跨脚本共享键。
- [Surge HTTP API](https://manual.nssurge.com/tools/http-api.html)：`surge_memory_bytes`、`surge_active_requests`、`surge_dns_cache_entries`、`surge_build_info`。

启动时长面板理念参考 fishingworld / Rabbit-Spec `SurgePro.js`；本项目合并并重写了监控架构、图表统计与事件处理。
