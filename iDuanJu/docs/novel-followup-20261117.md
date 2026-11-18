# 番茄、书旗及小说统一主题验收

本轮继续使用用户提供的合集 1335，快照 SHA-256 为 `874efe33cbe38b7dcf830704b5bd0614b9485fe1974a20d9c09030ebec07df30`。不把原始第三方书源、正文、设备状态或登录信息提交到仓库。

## 真实来源验证

生产 Swift 引擎在 [44000947821](https://github.com/my-name-is-alan/iDuanJu/actions/runs/44000947821) 的 `sources` 任务运行；Kotlin 使用同一合集和生产 `NovelSources` 引擎在本地运行。每次测试使用独立进程，关键词采用合集自己的 `checkKeyWord`。

- **番茄小说《十日终焉》**：24 个栏目、榜单 16 本、搜索 10 本、目录 1496 章；前三章清理后的正文长度分别为 2417、2386、2146 字符。Swift/Kotlin 结果一致，3 章写入生产缓存后离线回读一致。
- **书旗小说《凡人修仙传》**：47 个栏目、榜单 10 本、搜索 10 本、目录 2451 章；前三章清理后的正文长度分别为 2455、1980、1670 字符。Swift/Kotlin 结果一致，3 章写入生产缓存后离线回读一致。

这验证的是上述书籍、栏目与章节，不代表所有书籍、付费章或未来上游变化均可用。没有绕过登录、付费或已下架限制。

### 修复和判断依据

番茄脚本依赖内存字节流、GZIP、HTTP 字节请求、随机数和大整数。本轮在显式宿主接口中增加兼容实现；字节流、压缩输出、大整数和随机数组均有长度上限，Android 仍使用禁用 Java 类访问的 Rhino 沙箱。Swift 修复了章节 URL 的 fragment 被 HTTP 响应地址丢弃、卷标题被当成章节的问题。

Android 模拟器测试还发现桌面 JVM 与 Android ICU 正则引擎的差异：规则中的闭合花括号未转义，在 Android 会抛出 `PatternSyntaxException`，阻断榜单和搜索。已修正 `@put` 和模板表达式的字面花括号转义，并将两源真实链路加入 Android instrumentation 验收。

书旗上轮固定用“西游记”搜索，首个结果的目录接口实际返回 `chapterList=[]`、`readIsOpen=false`，旧网页目录入口返回跳转脚本。这是该书当前不可读，不能证明全部书旗目录规则损坏。按合集自己的校验词“凡人修仙传”实测后，已有规则能够获取目录和正文。本轮增加连续三章及离线验证，并改进空目录提示，明确说明可能下架、受限或书源失效，可换书或换源。不会将不可读书籍伪装为成功。

## 统一页面规范

小说书架、榜单、搜索、详情、书源配置、缓存下载沿用应用的 `STVTheme` / `IdjThemeColors` 蓝色主题，跟随系统浅深色。小说页面共享导航、17 点标题、58×80 封面行、正文辅助色、16 点内容间距和 14 点面板圆角。

iOS 的榜单不再自带独立红色主题；搜索与榜单复用书籍行，书源配置与下载页共享背景、强调色和返回入口。Android 的书源配置、缓存下载从小弹窗改成完整页面，搜索与榜单区分入口但保留同一主题，并加入书源启用开关。

布局验收使用明确标注的合成数据；真实网络结果单独记录。尚未进行真机验收。

## 构建、原生操作与发布

- [44009268349](https://github.com/my-name-is-alan/iDuanJu/actions/runs/44009268349)：Android 模拟器实网执行两源榜单、搜索、目录、前三章正文和离线回读；浅色、深色两项界面操作测试均通过，包含搜索、书源配置、详情和下载 50 章。iOS 模拟器启动曾遇到系统后台断言失败，重试后通过。
- 最终功能构建 [44011435053](https://github.com/my-name-is-alan/iDuanJu/actions/runs/44011435053) 双端成功，源码为 `0c072389e56789e0ffff29e804ad2952eab4e6b8`。后续提交仅修改测试截图导出，不影响安装包功能。
- [44024300977](https://github.com/my-name-is-alan/iDuanJu/actions/runs/44024300977) 核验 APK 固定签名、版本和 IPA 结构后发布上述构建，无重复编译；Android 1.5.10（1510）、iOS 1.5 build 10 已公开，下载链接均已核验 HTTP 200。
- APK SHA-256：`ceed9e4b2807f083f2fe680df7e52dab2e0f7d1c49cb6ae942dfdf2d6f5c07dc`。
- IPA SHA-256：`caf0c6979675151f08bb822f6a70903e303323b96ca5800bdb8010de46b9928d`。

原生主题截图（合成数据）：

<img src="screenshots/novel-rank.png" width="240" alt="统一主题的榜单">
<img src="screenshots/novel-download.png" width="240" alt="统一主题的缓存下载">
<img src="screenshots/novel-sources.png" width="240" alt="统一主题的书源配置">
<img src="screenshots/novel-search.png" width="240" alt="统一主题的搜索">

Android 原生截图已从 [44024121759](https://github.com/my-name-is-alan/iDuanJu/actions/runs/44024121759) 下载并检查。该次 Android 实网测试再次取得上述两本书的相同目录数和前三章长度，3 章离线回读、浅深色界面操作均通过；测试截图导出管道也已修复。

<img src="screenshots/novel-android-download.png" width="240" alt="Android 深色缓存下载">
<img src="screenshots/novel-android-sources.png" width="240" alt="Android 浅色书源配置">

## 复现

Android：先将合集保存到本地，不提交文件。

```powershell
.\android\gradlew.bat -p android :core:test :core:novelProbeClasspath -I "$PWD/scripts/novel-validation/kotlin.init.gradle" -PnovelClasspathFile="$PWD/work/novel-classpath.txt"
$cp = Get-Content work/novel-classpath.txt -Raw
java -Xmx256m -cp $cp app.iduanju.core.NovelCollectionProbe work/1335.json 8 live
java -Xmx256m -cp $cp app.iduanju.core.NovelCollectionProbe work/1335.json 9 live
```

索引 8/9 仅适用于记录的合集快照。Swift/macOS 和双端原生主题操作使用 `novel source validation` Actions；Android 模拟器测试用 `:app:connectedDebugAndroidTest`。
