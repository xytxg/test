# Surge Monitor Pro v3.2.1

本次根据 iPhone 真实截图调整原生信息面板：内存占用成为 **Surge 原生粗体标题**，默认正文压缩为约 6 行；次要指标移至详细模式。

## Surge 原生界面的限制

Surge 官方 [Information Panel](https://manual.nssurge.com/tools/panel.html) 只支持 `title`、`content`、`icon`、`icon-color` 等字段。不能在信息面板里嵌入 HTML、CSS、放大的数字或双列小卡片。之前展示过的四宫格只是设计示意，不能被 Surge 原生面板实际渲染。

## 安装与更新

原模块地址不变：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

更新模块后，再去「外部资源」更新脚本。确认所有 `script-path` 改为 `surge-monitor-pro-v3.2.1.js`，避免旧版本缓存。保留原来的本地 API Key 配置。

## 真实原生面板能呈现的格式（示例值）

**粗体标题**：`Surge 内存 · 30.7 MiB`

正文是 Surge 的普通灰色文字：

```text
变化 ↑0.3 · 30分 -0.3 MiB
1h均 30.6 · 24h峰 31.9
请求 59 · DNS 200
运行 10时45分 · 重载3次
采样 18:06 · 1分前
Surge 6.100.0 (4032)
```

持续内存增长（默认连续约 30 分钟增加 10 MiB）、采样失败、数据过期时额外展示警告。默认图标为蓝色，警告为橙色。

## 详细模式

在模块参数中设置 `view:detail`，增加本次最低内存、DNS 缓存数量 30 分钟变化、启动时间、最近配置重载时间、重载前后对比及有效样本条数。日常推荐默认 `view:compact`。

## 采样与兼容性

- 保持 `xy_surge_monitor_pro_v3` 存储键，升级不主动清空既有数据。
- 保留 `Cron */6`：每 6 分钟定时采样一次；面板每次打开只读、不制造采样数据。
- 观察峰值不等于真正连续峰值，近 30 分钟增长也不代表必然内存泄漏。
- 仍采用 `engine-started`、`profile-reloaded` 事件，重启会隔离不同引擎会话的样本。
- 无自动重启、无 MITM、无广告、无第三方上报；HTTP API Key 只保存在本机模块配置。
- 通过模拟 Surge 脚本的回归测试，仍需在 iPhone 上验证真实 UI 和后台调度。

测试：`node Surge/tests/surge-monitor-pro.test.cjs`。
