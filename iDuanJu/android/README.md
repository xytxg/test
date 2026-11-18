# i短剧 Android

原生 Kotlin + Jetpack Compose，目标与 iOS 功能对齐。计划见 [PLAN_ZH.md](PLAN_ZH.md)，进度见 [PROGRESS.md](PROGRESS.md)。

当前版本：**1.5.10-android (1510)**。

下载 [1.5.10 小说统一主题版](https://github.com/my-name-is-alan/iDuanJu/releases/tag/v1.5.10-novel-android)：包含小说改动及上一版红果修复；与 1.5.8 分发签名相同，可覆盖安装。下载 APK，SHA-256 见 Release 附件。

[直接下载 Android APK](https://github.com/my-name-is-alan/iDuanJu/releases/download/v1.5.10-novel-android/iDuanJu-1.5.10-novel-android.apk)；iOS 用户请前往 [iOS 1.5 build 10 发布页](https://github.com/my-name-is-alan/iDuanJu/releases/tag/v1.5b10-novel)。旧版 Release 已清理，仅保留这两个新版。

本轮修复番茄脚本兼容及 Android ICU 正则、JSON 桥接差异；番茄、书旗的榜单、搜索、目录、前三章正文及离线缓存已在 Android 模拟器实网验证。榜单、搜索、书源配置、缓存下载统一使用应用主题，书源配置与下载改为完整页面。详见 [本轮验收记录](../docs/novel-followup-20261117.md)。

小说支持 CSS/Jsoup、JSONPath、部分 XPath / JS、GET/POST、分页、分组发现、预取、离线下载与同书换源。已用用户提供的合集 1335 检查；不是全部书源都可用，详见 [验收记录](../docs/novel-followup-20261117.md)。完整 Java/WebView 兼容、EPUB 文件导入与朗读尚未完成。

详情和阅读页的“缓存 / 下载”可下载后 50 / 200 章或全本，支持暂停、继续和预取章数设置。保持应用在前台，已完成章节可从离线条目读取。换源按同名同作者匹配，优先按章节标题接续。

## 要求
- minSdk 26 / targetSdk 35
- JDK 21（字节码目标 17）

## 构建
```bash
cd android
./gradlew :app:assembleDebug :app:assembleRelease
```
APK：`app/build/outputs/apk/{debug,release}/`

GitHub Actions 使用固定分发签名；本地默认仍用调试签名。分发构建需要设置 `ANDROID_KEYSTORE_PATH` 与 `ANDROID_KEYSTORE_PASSWORD`，别名为 `iduanju`。不要提交私钥。
从旧调试签名包升级可能需要卸载重装，卸载会清除数据；先保存书源和插件配置。

## 红果取流
已同步 gateway `0613b49`：当前 Medusa 播放签名、复用健康匿名身份、同身份端点回退、最多 3 次身份恢复；筛选独立使用 551，按剧种加载面板。公开构建不写死设备 ID 或 SDK token。也可在“我的”填入自己的 `device_id,iid` 覆盖。上方新版已包含这些修复。

## 测试
```bash
./gradlew :core:test
./gradlew :core:test -Plive=1                          # 联网：注册+榜单
./gradlew :core:test -Plive=1 -PhgDevice=did,iid       # 联网：取流（需可用设备对）
```
