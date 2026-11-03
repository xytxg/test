# Surge-EN → Stash 兼容版

基于 [Rabbit-Spec/Surge 的 Surge-EN.conf](https://github.com/Rabbit-Spec/Surge/blob/Master/Conf/Spec/Surge-EN.conf)（参考 2026-11-01 / v5.1.3）；转换为 **Stash 原生 YAML**，保留核心分流策略、6 地区自动测速组、服务组及原规则优先级。

## 导入主配置
Stash → 配置文件 → 从 URL 下载：

```text
https://raw.githubusercontent.com/xytxg/test/main/Stash/Surge-EN-Stash.yaml
```

**重要：** 原 Surge 模板的 `policy-path=你的订阅地址` 不是实际 URL。出于安全考虑，公开主配置**不包含私人订阅**，所以只导入主配置时不会有机场节点；各策略组在无节点时可能回退到直连。必须按下面方法加入自己的订阅才能代理上网。

## 安全添加个人订阅
1. 下载 [subscription-override.example.stoverride](./subscription-override.example.stoverride)，**在本地编辑**。
2. 将 `https://example.invalid/REPLACE_WITH_YOUR_OWN_CLASH_STASH_URL` 改成你的 **Clash / Stash 格式**机场订阅完整 HTTPS URL。
3. 将编辑好的覆写文件导入 Stash 并启用；不要将私人链接、密钥或含 token 的覆写提交到 GitHub。
4. 在 Stash 更新资源，确认“我的节点”和地区策略组出现真实节点；按需要在策略组选择节点。

Stash 支持在覆写文件中合并 `proxy-providers` 字典，地区测速组和“我的节点”使用 `include-all: true` 自动提取远程节点。

> **注意**：如果机场只提供 Base64/Surge 专用订阅，可能无法作为 Stash 的 `proxy-providers` 直接使用；请向机场取得 Clash/Stash YAML 格式的节点订阅（至少包含 `proxies:` 字段）。

## 处理过的兼容问题

- 解决 `Invalid source URL: relative URL without a base`：去掉未填写的相对订阅 URL，提供本地私有覆写模板。
- 解决 `expected mapping start, got scalar`：Surge `.list` 使用 `format: text`，不再按 YAML 加载。
- `smart` 转成 Stash 原生 `url-test`，并保留香港、美国、日本、韩国、台湾、新加坡分组。
- `policy-regex-filter` 转成 Stash `filter`；修正台湾节点的 🇹🇼 筛选。
- `Proxy.list` 按域名、IP、少量其他规则拆分，域名和 IP 使用索引格式优化性能。
- `ChinaCIDR.list` 由逗号分隔的 Surge 规则转为 Stash 原生 IP 网段格式。
- 修复上游 AIGC、TikTok 的拼接注释行。
- 不直接移植 Surge 独有的 `FINAL,...,dns-failed`、`skip-proxy`、`geoip-maxmind-url` 等参数，以 Stash 的 `MATCH`、局域网规则、内建 DNS 替代。

## 注意事项

本项目使用上游可在线更新的规则集；`rules/Proxy*.txt`、`ChinaCIDR.txt`、`AIGC.list`、`TikTok.list` 在上游有更新时需要重新生成；最近一次核对为 2026-11-03。此版本已经过配置结构与公开规则源检查，但**未能在你的 Stash 实机进行运行测试**。

原作者：Rabbit-Spec；本转换版本仅作兼容性适配，规则来源与版权归原作者所有。

官方格式文档：[规则集合](https://stash.wiki/rules/rule-set) / [策略组](https://stash.wiki/proxy-protocols/proxy-groups) / [覆写配置](https://stash.wiki/configuration/override)

## 上游自动跟进

已设置每小时检查 Rabbit-Spec/Surge，重点跟进 `Conf/Spec/Surge-EN.conf`、引用规则及相关依赖。发现影响本配置的更新后，转换并校验 Stash YAML、策略引用及规则格式，通过后直接推送本仓库 main；没有相关变化时不重复提交或通知。

同步基准记录在 [upstream-state.json](./upstream-state.json)。保持现有主配置 URL；私有订阅仍通过本地覆写填写。

2026-11-03 本次核对：补齐 Proxy 域名快照缺失的 GitHub 域名，补齐上游 8 条 sslip.io / nip.io 本地回环域名 Fake-IP 排除项。其余 5 个规则快照核对一致（允许去重及排序差异）。后续遇到无法等价转换的新语法时，先保留可用版本并说明阻塞。

### 2026-11-03 规则同步

跟进 Rabbit-Spec/Surge 提交 `9196fb65c523ef354768c6b8bca0ebd1d16a4c22`（10:07:56）：ChinaCIDR 从 10036 条更新为 9686 条（新增 70、移除 420 条文本条目，含网段拆分/合并）；已重新生成 Stash ipcidr/text 快照。其余规则仅更新时间戳，主配置和导入链接保持不变。已通过静态校验，未进行 Stash 实机测试。
