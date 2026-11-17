# Surge Monitor Pro v3.3.0 — 极简原生面板

根据 iPhone 真实截图对 Surge 信息面板进行第三次 UI 整理。**默认改为极简视图 `view:glance`**：系统粗体标题用于内存数值，其余只保留四行核心指标。以前的 `compact` 和 `detail` 仍可选择，所有采样历史保留。

## 重要界面限制

Surge 原生 [Information Panel](https://manual.nssurge.com/tools/panel.html) 仅支持 `title`、`content`、`style`、`icon` 和 `icon-color`。不能自定义字号、放大数字、CSS、图表或内部网格。之前的网页四宫格示意无法在 Surge 原生策略组面板中真实实现。

## 原生显示样例（数字仅是展示样例）

系统粗体标题：

**内存 30.7 MiB**

普通正文：

```text
近30分钟  ↓ 0.3 MiB
1h均 30.6  ·  24h峰 31.9
请求 59  ·  DNS 200
运行 10时45分  ·  采样1分前
```

只有发生持续增长、采样异常或样本过期时，才增加警告内容。不会假装为实时连续采样。

## 安装与更新

原安装地址不变：

https://raw.githubusercontent.com/xytxg/test/main/Surge/Surge-Monitor-Pro.sgmodule

更新模块，再到 Surge 外部资源更新脚本；确认所有远程脚本已使用 `surge-monitor-pro-v3.3.0.js`。保留本机已有 API Key，不必重新配置。

## 可调整的视图

- `view:glance`：默认极简，约四行正文
- `view:compact`：之前的完整概要，额外显示采样及版本等
- `view:detail`：最低值、配置重载、DNS 变化、重载前后内存对比等

## 性能和隐私

继续每 6 分钟 Cron 采样、引擎启动采样、配置重载事件统计，不增加额外 Cron 或网络拦截。使用原 `xy_surge_monitor_pro_v3` 存储键，不主动清空历史数据。30 分钟上涨预警阈值默认 10 MiB，内存阈值默认 45 MiB，均只改变显示。保留本机 API Key，不提交公开仓库。

运行测试：`node Surge/tests/surge-monitor-pro.test.cjs`。测试使用模拟 Surge 运行环境，不能替代 iPhone 实机 UI 验证。
