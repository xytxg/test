# Surge Monitor Pro v3.4.0 — Beta API 恢复优化

Surge 本次 Beta 修复了**自动重启后 HTTP API 等服务可能未恢复**的问题。v3.4.0 针对监控脚本的采样链路做了补强，**不声称模块自己能修好 Surge 服务**。

## 本次优化

- 启动采样如遇指标暂不可读，等待约 **650 毫秒后仅重试一次**；普通 Cron 仍每 6 分钟只采样一次。
- 区分本地 HTTP API 无响应、HTTP 401/403 密钥/权限错误、5xx 服务异常、指标缺失等状态。不会显示、记录或上传本地 API Key。
- 采样失败后必须真正获得**成功指标**才能记录恢复，极简视图显示 15 分钟内的“采样已恢复”，详细视图显示恢复时间与本次引擎会话累计恢复次数。
- **超过 18 分钟未成功采样，标题变为“历史内存 xx MiB”**，避免旧数字被误认成实时占用。
- 保留 `glance`（默认四行）、`compact` 和 `detail`，平时不增加冗余行，只有异常时增加状态。
- 不通过 DNS 缓存数量猜测 Split DNS 或 Tailscale 的解析是否成功；继续仅展示官方实际提供的 `surge_dns_cache_entries`。

## 安装链接

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

更新模块及外部资源，确认脚本 URL 是 `Surge/scripts/surge-monitor-pro-v3.4.0.js`。

## 与旧版兼容

存储键仍为 `xy_surge_monitor_pro_v3`；已有历史不主动删除。继续使用六分钟 Cron、`engine-started` 和 `profile-reloaded` 事件、最多 240 个有效样本。没有 MITM、后台测速、主动 DNS 测试或自动重启引擎。iOS 后台调度仍取决于系统实际执行情况。

测试命令：`node Surge/tests/surge-monitor-pro.test.cjs`；模拟测试不能替代 iPhone 实机。官方指标来源：[Surge HTTP API](https://manual.nssurge.com/tools/http-api.html)。
