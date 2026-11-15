# Surge Monitor Pro v2 — 单卡片状态监控

在**同一张 Surge 信息面板**中显示内存、变化趋势、运行时长、连接/DNS 缓存和本模块的配置重载记录。已替换旧版两张独立面板；沿用原安装链接。

## 安装 / 升级

Surge → 模块 → 安装新模块：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

已经安装旧版的用户请在 Surge **更新模块与外部脚本**；必要时关闭再启用模块，旧版的两张卡片应变成一张「Surge 状态监控」。脚本的远程更新检查间隔为 60 秒，但实际更新时机仍由 Surge 控制。

## 页面示例（示例数值，不是你的实时数据）

    Surge 状态监控
    ▌ 内存 · 26.6 MiB  · →0.0 MiB
      峰值 26.6 MiB   最低 24.9 MiB
      趋势  ▁▁▂▄▅█▇

    ▌ 运行 · 18 分 4 秒
      启动 11-15 09:15  ·  重载 6 次
      活跃请求 15  ·  DNS 缓存 191
      上次重载 11-15 09:28

    Surge 6.100.0 (4027)
    更新 09:33:38 · 间隔 60 秒

仅允许 Surge 文本和图标能力，不支持自定义 HTML/CSS 组件。峰值、最低值、趋势均来自**确实发生过的采样**，并不是后台实时进程记录；脚本最多保留 24 个历史采样点，显示最近 20 个。自动更新间隔为 60 秒，但 Surge 仅在进入面板页面时检查是否需要重新运行脚本，所以“间隔 60 秒”不等于每分钟在后台采样。进程重新启动时重置峰值与趋势。

## 内存接口

iOS **5.22.0+** / Mac **6.9.0+** 使用官方 Prometheus 文本接口 `GET /v1/metrics`，读取以下真实指标：

- `surge_memory_bytes`：物理内存
- `surge_active_requests`：活动请求数（不等于 TCP 连接总数）
- `surge_dns_cache_entries`：DNS 缓存条目
- `surge_uptime_seconds`：运行时长后备数据
- `surge_build_info`：版本后备数据

脚本先尝试 Surge 内置 `$httpAPI`，但它不保证能正确解析纯文本。如果显示内存“暂不可用”，请在 Surge 设置中启用**本机 HTTP API** 并在模块参数中填 `api_key`（本机密钥）、`api_port`（实际端口，默认 6171）。仅向本机 `127.0.0.1` 发出带 `X-Key` 的请求，不向第三方发送监控数据；**绝对不要把 API 密钥写进仓库**。也不要将 HTTP API 暴露在公网。

## 模块参数

- `api_key`：HTTP API 密钥，默认空。
- `api_port`：本机 HTTP API 端口，默认 6171。
- `refresh`：面板更新检查间隔，默认 60 秒。
- `tap`：点击右上角的操作。默认 `reload`，保留原 Surge Pro 的 `POST /v1/profiles/reload`；改为 `refresh` 只读刷新；`restart` 则第一次点击进入 20 秒确认，第二次点击通过 `POST /v1/stop` 停止引擎。
- `warn_mib`：内存超出此值时图标由蓝转橙，默认 45 MiB。
- `restart`：旧版兼容参数；`1` 会覆盖 `tap` 选项启用二次确认停止功能。默认 `0`。

**重要：** `/v1/stop` 在未开启 iOS Surge“始终开启”时仅会停止，不会自动重启，网络可能中断。因此默认**不**启用此操作。自动刷新（`$trigger=auto-interval`）不会发起配置重载或引擎停止。

“配置重载次数”**只统计本模块手动点击成功的重载**，不代表 Surge 全局重载总数；重载配置不会重启引擎。新的引擎会话会重置本模块统计。

## 致谢与资料

启动时长与配置手动重载交互，参考 [fishingworld](https://github.com/fishingworld/something) 与 [Rabbit-Spec SurgePro.js](https://github.com/Rabbit-Spec/Surge/blob/Master/Module/Panel/Surge-Pro/Moore/SurgePro.js)，原模块入口来自 [QingRex/LoonKissSurge](https://github.com/QingRex/LoonKissSurge)。内存指标与渲染逻辑为本仓库整合实现。

[Surge 官方面板文档](https://manual.nssurge.com/tools/panel.html) · [Surge 官方 HTTP API](https://manual.nssurge.com/tools/http-api.html)
