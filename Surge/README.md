# Surge Monitor Pro v2.3.0

将 [QingRex 启动时长模块](https://github.com/QingRex/LoonKissSurge) 与 Surge 引擎监控指标合并为 **一个模块、一张原生信息面板**。默认只读取数据，不会停止代理或重载配置。

## 安装

在 Surge → 模块 → 安装新模块中粘贴：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

旧版升级：在 Surge 中更新此模块及外部脚本；若仍看到旧界面，关闭再启用模块并重新打开策略选择页。请停用此前单独安装的 Surge 启动时长模块，以免出现多张卡片。

## 显示效果（下列数值仅为示例）

    Surge 状态监控
    ▌ 内存  34.8 MiB · ↑2.6 MiB
      峰值 34.8 · 最低 32.2 MiB
      趋势  ▁▂▄▆█

    ▌ 运行  17 分 44 秒
      启动 11-15 09:15 · 重载 1 次
      活跃请求 13 · DNS 80
      最近重载 11-15 09:28

    Surge 6.100.0 (4027)
    更新 09:33:38 · 采样 09:32:31

如果内存恰好在本次面板更新中重新采样，底部只显示「更新 HH:mm:ss」，不会再重复显示两次相同时间；**不会在卡片中显示「间隔 60 秒」**。

## v2.3.0 设计和逻辑改进

- 紧凑的 **内存 / 运行** 两段式排版，清理无意义的「已手动刷新数据」行，隐藏不存在的最近重载时间。
- 只在 **至少两次有效内存采样** 后显示相对变化和趋势图；不会首次采样就显示一格图形或误导性的 `→0.0 MiB`。
- 缓存期内沿用真实相邻采样的差值，避免每次进入面板都把「当前值」与它自身比较。
- 小幅变化（绝对值小于 0.05 MiB）显示「持平」，其余以 ↑ / ↓ 表示方向。
- 指标失效时将历史记录清楚标注为「最近记录」，不当作当前实时值，也不会把错误响应缓存成有效采样。
- 引擎重新启动时清空旧进程的峰值、最低值、趋势和本模块的重载计数。采样历史仅保留最近 24 个记录，趋势显示最近 20 个点。
- 内存达到 `warn_mib`（默认 45 MiB）时图标变橙，API 不可用时也以警示色表示。此阈值仅改变图标颜色，不会执行任何危险操作。
- 启动时长每次重新进入面板会尝试重新读取；缓存内存指标默认约每 60 秒才能在自动更新时重新采样，手动刷新可以强制重新读取。

## Surge 面板不是实时秒表

根据 [Surge 官方面板说明](https://manual.nssurge.com/tools/panel.html)，`update-interval=1` 意味着**重新进入策略选择视图时**会检查是否需要更新。停留在原页面时，数字**不会逐秒跳动**；必须重新进入面板或手动点击右上角刷新。因此界面时间表示「最后一次脚本运行时」的观测值。

## 数据与版本号

需要 Surge **iOS 5.22.0+** 或 **Mac 6.9.0+** 才能使用 `GET /v1/metrics` 的官方 Prometheus 指标。实际指标含义：

- `surge_memory_bytes`：Surge **引擎进程**物理内存，不是手机剩余内存。
- `surge_active_requests`：当前处理中的请求数，不等于全部 TCP 连接数。
- `surge_dns_cache_entries`：当前 DNS 缓存条目数。
- `surge_uptime_seconds`：启动时长的后备来源。
- `surge_build_info`：**实际引擎版本和 Build**，优先于脚本环境版本号；读取不到时使用 `$environment` 作为回退。

模块版本是 **v2.3.0**，与 Surge 客户端的实际版本号不是一回事；例子中的 6.100.0 (4027) 不是硬编码。

## 参数与安全

| 模块参数 | 默认值 | 作用 |
| --- | --- | --- |
| `api_key` | 空 | 在内置接口无法获得纯文本指标时，填写**本机 HTTP API 密钥** |
| `api_port` | `6171` | 实际本机 HTTP API 端口 |
| `refresh` | `60` | 内存自动采样最短间隔（秒），**不作为 UI 显示文字** |
| `tap` | `refresh` | `refresh` 仅刷新；`reload` 点击重载配置；`restart` 双击确认停止引擎 |
| `warn_mib` | `45` | 内存高亮阈值（MiB） |
| `restart` | `0` | 旧版兼容开关，设为 `1` 会强制启用引擎停止确认，不建议开启 |

内部 `$httpAPI` 不保证支持 `/v1/metrics` 的 Prometheus **纯文本**响应。若内存不可用，请在 Surge 设置中启用本机 HTTP API，并仅在本地模块参数中填写 `api_key`，脚本会向 `127.0.0.1:api_port` 携 `X-Key` 请求。**不要在 GitHub 提交 API 密钥，也不要把 HTTP API 暴露公网**。不采集或上传用户数据到第三方平台。

`tap=reload` 是沿用原 Surge Pro 的手动 `POST /v1/profiles/reload` 功能；只统计**由此模块发起的重载**，不是全局重载次数。该功能默认关闭，避免用户为刷新面板而意外重新加载配置。

**危险操作提醒：** `tap=restart`（或 `restart=1`）实际调用 `POST /v1/stop` **停止 Surge 引擎**，必须 20 秒内点击两次才执行。若 iOS 没有启用「始终开启」，它不会自动重启，可能导致网络中断；请保持默认 `tap=refresh`。

## 致谢

启动时长与手动重载交互参考 [fishingworld](https://github.com/fishingworld/something) 和 [Rabbit-Spec SurgePro.js](https://github.com/Rabbit-Spec/Surge/blob/Master/Module/Panel/Surge-Pro/Moore/SurgePro.js)；原模块入口参考 [QingRex/LoonKissSurge](https://github.com/QingRex/LoonKissSurge)。合并面板的内存指标、采样、缓存和显示逻辑为本项目实现。

文档：[Surge Information Panel](https://manual.nssurge.com/tools/panel.html) · [Surge HTTP API](https://manual.nssurge.com/tools/http-api.html)
