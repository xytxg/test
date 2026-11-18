# UI redesign / 1.5 build 11

本轮版本：iOS 1.5 (11)，Android 1.5.11-android (1511)。交付 tag：`v1.5b11-ui-redesign`；仅推送 `codex/ui-redesign`，不合并 main，不创建 GitHub Release。

## 实现与验收范围

- iOS/Android 重做的列表、详情、小说 04–08、播放器 14–17；播放器横屏标题/技术信息/进度和底部操作分层，底部加深渐变，统一 30 集分组。
- 小说搜索、榜单、书源页用 Debug-only 的合成离线数据验收深浅色布局；`.invalid` 测试域名不是真实书源，Release 不包含这些 fixtures。
- 播放器使用明确标记“本地彩条测试 · 非真实片源”的 MP4，实际只有 360P；不伪造多画质、弹幕或直播能力。iOS 无适用片头时不绘制跳过片头按钮。截图不能证明直播源可用或播放流畅度，也不声称与设计稿像素级 1:1。
- 实际横屏截图：iOS 2622×1206，Android 2556×1180，均为原生模拟器输出，不旋转竖屏截图冒充横屏。对照图按原始 1800×882 设计图去除外框后归一化比较。
- PR8 意图已由 `85f6d3e` 纳入：横竖屏中间 60% 切集、外侧 20% 调节、锁屏/拖进度/面板/PiP 等状态禁止误切集。
- PR10 head `9e38bc7` 是本分支祖先；`561887c` 与 `7cda81c` 的静默中心控制意图已整合，换集不弹出中心 transport，标题/进度常驻。
- Android `a1acc91`：KEEP_SCREEN_ON 跟随实际 isPlaying；模拟器 dumpsys 已验证竖/横屏播放时开启、暂停与离开时释放。Android 现有 PiP 入口尚未实现，不能宣称 PiP 路径通过。
- Android `9cdd82b`/`6852ad7`：找剧数据、过滤器、分页、滚动状态由 back-stack ViewModel 持有；首页请求生命周期提升到 repository。返回列表 cache hit，未新增加载；找剧列表去除状态/标签栏后的前后截图差异 0 像素。首页轮播会自己切换，不把整张图像差异当作缓存丢失。
- Android 面板提高遮罩不透明度，避免标题/进度透过面板干扰文字；未伪造模糊效果。
- iOS 点击进度条与拖动进度改用互斥的 SpatialTapGesture / DragGesture，防止静止点击被零距离拖动识别丢失。UI 测试保留相同 seek 数值要求并等待异步确认；切集手势明确跨越半页，避免 45% 慢拖依赖释放速度导致正常回弹。未移除任何相关断言或新增测试排除。

## 验证与明确限制

最终所选 iOS 回归已通过：STVTests 182 项（14 跳过、0 失败），PlayerUITests 18 项（1 跳过、0 失败），小说填充预览 UI 1 项通过；进度条修复另连续重复 3 次通过。打包结果与 SHA-256 见交付目录中的 VALIDATION.txt / SHA256SUMS.txt。

- STVTests 选择集 182 项（14 跳过）；另有两个 Apple 实网测试在此前完整运行失败：`testLiveAppleHLSPrefetchReachesBudget`（300 < 330）与 `testLiveAVPlayerThroughProxyHLSAndMP4`（未推进播放/预取不足）。最终离线回归仅排除这两个已披露的网络依赖测试。
- PlayerUITests 18 项（1 个实网来源用例跳过）与小说填充搜索/榜单/书源 UI 用例；最终结果见随包记录。
- Android core 强制重跑 78 项、18 跳过、0 失败；小说深浅色 instrumentation 两项通过；assembleDebug / assembleRelease 成功。
- 未完成真机 PiP、真机长时间流畅度与 iOS Animation Hitches 性能验收。模拟器旧采样为 247 帧、3.24% jank、median21ms/p99 73ms，不能据此声称稳定 60fps。

## 打包约定与签名

`scripts/package.sh` 生成 unsigned IPA。Android 本地 release 在无分发签名环境时按仓库约定回退 Android Debug 证书，本轮本地 debug/release APK 均如此；不能保证覆盖安装正式分发签名版本。未读取或导出签名密钥。

本地文件：

- `iDuanJu-1.5.11-ui-redesign-android-release.apk`（release 构建，Debug 证书）
- `iDuanJu-1.5.11-ui-redesign-android-debug.apk`（debug 构建/Debug 证书，含测试 fixtures）
- `STV-1.5b11-unsigned.ipa`（需重签侧载，不含 Debug fixtures）

现有 `package.yml` 仅支持手动 dispatch，可在该 tag 上使用已有 CI 签名配置；不读取 secrets。tag 本身不会自动创建发布页。分支推送触发 macOS player regression（75 分钟超时），不等待它结束才交付本地包；最终报告必须注明实际 CI 状态。
