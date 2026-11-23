# Surge Monitor Pro v3.7.0 — 全面维护升级

**升级基线：v3.6.0（不是旧 v3.4.0）**。保留后台 Cron 与按钮实时读取、近 24 小时的历史、三种视图和相同安装链接。

## 改进

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

在 Surge 中更新模块、再更新外部资源，确认所有入口指向 `surge-monitor-pro-v3.7.0.js`。原本在设备上设置的 `api_key`、`api_port`、`wake`、`tap`、`view` 等参数无需重填。若用户更重视续航，可自行设 `wake=false`。

默认 `view:glance` 保持极简；`compact` 增加版本及采样信息；`detail` 展示重载、低值、旧 Build 及 Mac 统计说明。Surge 原生 Panel 无法渲染自由布局、CSS 或网页卡片。

## 回归测试

```bash
node Surge/tests/surge-monitor-pro.test.cjs
```

新版测试模拟 Surge 的 WebView API，覆盖手动实时读取、定时采样、历史去重/迁移、版本切换、异常状态和恢复、重载事件、超时重试。模拟测试通过不能替代 iPhone/Mac 实机后台调度验证。

官方参考：[Information Panel](https://manual.nssurge.com/tools/panel.html) · [Prometheus Metrics](https://manual.nssurge.com/tools/http-api.html) · [Cron](https://manual.nssurge.com/scripting/cron.html) · [Event](https://manual.nssurge.com/scripting/event.html)
