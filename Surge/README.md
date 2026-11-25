# Surge Monitor Pro v3.9.0 — 低开销维护与启动诊断

**升级基线：v3.8.0**。保留后台 Cron 与按钮实时读取、近 24 小时的历史、三种视图和相同安装链接。

## v3.9.0 增量改进

- 四个版本化脚本入口均设置 `script-update-interval=-1`，利用本次 Beta 修复后的禁用自动更新行为；首次安装仍需下载，新版由模块更新切换版本 URL。手动更新模块及外部资源仍可用。不要原地覆盖已经发布的版本文件。
- 正常有序历史原地压缩、过滤和去重，只有发现乱序才排序；会话列表同样避免常规 slice/filter/sort 临时数组。仍兼容旧 JSON，最多 240 点、64 个会话，无实机内存下降量的承诺。
- 区分启动时间变化和仅 Build/版本变化；两者都隔离统计基线，但仅实际启动时间变化记录重启时间。停止原因请查看 Surge 原生 Logbook，模块不能确认是否被其他 VPN 接管或内存超限。
- 详细模式增加最近一次后台采样故障的观测跨度（首次失败采样至首次成功采样，不代表真实网络中断时长）；极简模式不增加此行。
- 即使历史已全部超过 24 小时，仍标明此前采样已过期而不是首次运行。
- 继续使用 127.0.0.1 API，Wi-Fi 地址变化修复来自 Surge 本体；不引入 LAN 地址扫描、新轮询或网络探测。

## v3.8.0 功能保留

- 手动刷新时，内存和 DNS 趋势使用实时值作为终点，不再显示旧样本的差值。均值/峰值仍只取后台历史。
- 实时读取成功与后台定时采样恢复分别显示，只有后台真实成功才清除后台失败记录。
- 复用官方 `surge_active_bans` 指标：未授权访问封禁数量大于零且数据有效时才在极简视图提示；详细视图可显示零，旧版缺失该指标时隐藏。历史数据明确标注。它不是 DNS 或 Tailscale 故障指标。
- 内部 API 异常不再直接归因为密钥未填写；HTTP 回调解析异常受到保护。
- 新版 Surge 的 Tailscale/WireGuard 快速拒绝连接及不可达 DNS 警告属于引擎功能。官方 `GET /v1/events` 可读取事件中心，但未公开该告警的结构及消失语义，因此本版本不增加事件轮询、模糊匹配或 DNS 主动探测。请在 Surge 原生警告中查看具体不可达服务器。
- 正常路径不增加 API 请求；保留原存储键、六分钟 Cron 和 60 秒缓存面板刷新。

## 保留原有改进

- **引擎/Build 分组统计**：24h 采样峰值和 1h 均值只取当前引擎会话及 Build 的真实观测样本，不混用升级前后的进程内存口径；保留旧 Build 样本供详细模式参考。
- **历史数据保护**：继续使用 `xy_surge_monitor_pro_v3` 存储键，读取时过滤无效值、未来数据、过期记录，排序并去重；重复时间戳保留先前有效样本。最多 240 个采样点，最多 64 条引擎会话元数据。
- **WebView/Logbook 稳定性**：对 API 异常仅在首次失败或错误类型变化时记录简短日志；恢复时记录一次。保留请求超时与定时器清理，不额外增加每小时 Cron 次数。
- **Mac 内存统计提示**：仅在 Mac 6.12+ 检测到上个 Build 时，详细视图提醒 macOS 15+ 新 TCP 网络栈可能改变 Surge 进程内存归属。这不是内存泄漏证明，也不应用于 iOS。
- **实时与历史严格区分**：右上角手动刷新读取一次真实内存但不写入历史；自动展示缓存值并指明采样新鲜度。官方 Prometheus 的 `surge_memory_bytes` 是**引擎进程物理内存**，不是 WebView 脚本内存，也不是 iPhone 剩余内存。
- 仍使用 `engine-started`、`profile-reloaded`，以及启动时至多一次轻量重试，采样失败状态和恢复次数均保留。
- 没有新增 MITM、第三方遥测、DNS 主动测试、进程重启或额外后台采样负担。

## 安装 / 更新

原地址不变：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

在 Surge 中更新模块、再更新外部资源，确认所有入口指向 `surge-monitor-pro-v3.9.0.js`。原本在设备上设置的 `api_key`、`api_port`、`wake`、`tap`、`view` 等参数无需重填。若用户更重视续航，可自行设 `wake=false`。

默认 `view:glance` 保持极简；`compact` 增加版本及采样信息；`detail` 展示重载、低值、旧 Build 及 Mac 统计说明。Surge 原生 Panel 无法渲染自由布局、CSS 或网页卡片。

## 回归测试

```bash
node Surge/tests/surge-monitor-pro.test.cjs
```

新版测试模拟 Surge 的 WebView API，覆盖手动实时读取、定时采样、历史去重/迁移、版本切换、异常状态和恢复、重载事件、超时重试。模拟测试通过不能替代 iPhone/Mac 实机后台调度验证。

官方参考：[Information Panel](https://manual.nssurge.com/tools/panel.html) · [Prometheus Metrics](https://manual.nssurge.com/tools/http-api.html) · [Cron](https://manual.nssurge.com/scripting/cron.html) · [Event](https://manual.nssurge.com/scripting/event.html)
