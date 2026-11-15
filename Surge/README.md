# Surge Monitor Pro — 内存与运行时长

将 [Surge 启动时长](https://raw.githubusercontent.com/QingRex/LoonKissSurge/refs/heads/main/Surge/Official/Surge%20%E5%90%AF%E5%8A%A8%E6%97%B6%E9%95%BF.official.sgmodule) 的启动时间和点击手动重载功能，与 Surge 官方 `/v1/metrics` 引擎监控指标整合为一个 Surge 模块、两张信息面板。

## 安装

Surge → 模块 → 安装新模块：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

更新并启用模块，在 Surge 策略选择页查看两张面板。

## 内存指标准备

需要 Surge iOS **5.22.0+** / Surge Mac **6.9.0+**（支持 Prometheus 指标）。

脚本首先尝试内部无鉴权的 `$httpAPI(GET, /v1/metrics)`；由于官方文档说明此接口返回的是**纯文本**，而 `$httpAPI` 只保证解析 JSON，部分版本可能无法直接读取。此时需要在 Surge 自身设置中启用本机 HTTP API，并把**本机 API 密钥和端口**填入本模块的参数 `api_key`、`api_port`（默认 `6171`）。脚本通过 `http://127.0.0.1:<api_port>/v1/metrics` 带 `X-Key` 请求指标，不访问任何外部监控服务器；**不要将密钥写入或提交到 GitHub**。

本模块不会覆盖或自动修改你现有的 `[General] http-api` 配置。如你当前使用了其他端口，请在模块参数中同步修改。建议仅绑定 `127.0.0.1` 并使用强密钥，不要将 HTTP API 暴露在公网。

## 两个面板

- **Surge 内存监控**：引擎实际物理内存（MiB）、此轮引擎启动以来的观测峰值/低值、最近变化、最多 24 个采样点的趋势、活动请求数、DNS 缓存数量、更新时间。缺失指标时显示“暂不可用”，绝不虚构内存数值。
- **Surge 运行时长**：当前引擎运行时长、启动时间、版本、仅由此模块发起的配置重载次数、最近一次重载。点击右上角刷新会按原版功能执行一次 `POST /v1/profiles/reload`。该操作不是重启引擎。

`refresh` 默认为 60 秒；Surge 在用户打开面板时检查更新，**并非后台持续逐分钟采集**。持久化数据是在脚本真正触发时更新的。离线期间及进程崩溃时的真实峰值无法被本模块观察到。

## 重要安全提示

内存面板右上角按钮**默认只刷新数据**，不停止 Surge。若手动将模块参数 `restart` 设为 `1`，第一次点内存面板刷新会进入 20 秒确认状态，第二次点才执行 `POST /v1/stop`。**当 Surge iOS 的“始终开启”未启用时，该接口仅停止引擎，不会自动重启；网络连接可能中断。** 建议普通用户保持默认 `restart=0`。

- 自动刷新不执行配置重载/重启。
- 内存“峰值”只指实际采样记录的峰值，不能保证捕获瞬时峰值。
- “配置重载次数”只统计本模块点击触发的次数，并非 Surge 全局重载次数。
- 面板脚本使用 WebView 引擎，避免增加 NE 进程的 JSC 内存开销。

## 致谢

启动时长面板行为参考 `fishingworld/something`、`Rabbit-Spec/Surge`（原脚本 `SurgePro.js`）；模块入口参考 `QingRex/LoonKissSurge`。其余整合与内存采样为新实现。

文档：[Surge HTTP API](https://manual.nssurge.com/tools/http-api.html) · [Surge 信息面板](https://manual.nssurge.com/tools/panel.html)
