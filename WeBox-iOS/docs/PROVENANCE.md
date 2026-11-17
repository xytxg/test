# 来源与许可

Android 参考包：用户提供的 WeBox 0.1.101 beta，build-info revision `ea064604`，时间 `2026-11-17 14:33:35 UTC+8`。APK 自带 GPL-3.0 许可，已保留完整文本。

- `sdk-widget.js`、`sdk-webox.js`、`sdk-xptv.js`、`compute-worker.js`：从该 APK 的 runtime/ 与 assets/ 提取的宿主接口实现，原样保留。它们不包含内容站点源。
- `sdk-cheerio.js`、`sdk-cryptojs.js`：使用 Tools/vendor/ 的锁定 npm 依赖重新构建；源版本和第三方声明见 Resources/licenses/THIRD_PARTY.txt。CryptoJS 仅为兼容既有脚本提供，主要加密桥使用系统实现。
- 用户的红果源只在 Tests/Fixtures/hongguo.webox.js 保留，遵循其 GPL-3.0-only 声明与上游归属。它不进入发布应用。
- Android radio / demo 源只作为接口回归测试夹具；不进入发布应用。
- Screenshots/ 三个模拟源、media/ 原创几何测试封面和合成 H.264/AAC 视频用于离线测试和截图。没有商业影视内容。它们不进入发布应用。
- Swift 客户端、导入流程、统一数据适配器、HTTP 与播放器控制器为本项目实现，GPL-3.0-only。

## 原始附件 SHA-256

- `WeBox-0.1.101-beta.apk`: `139705d9fceef2588484d572b8964928ac341e17d869da74a6373623430a17cb`
- `红果短剧.webox.js`: `0470539eaff5d7f9defc08ccf5dedf551f46cbbc6ccc4e99fec17b406dfb92d5`
