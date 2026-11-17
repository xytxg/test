# WeBox iOS

独立重写的 SwiftUI iOS 客户端，适配附件 `红果短剧.webox.js` 使用的 WeBox 基础源协议。不是 APK 格式转换，也不是原 Android 应用全部功能的移植。

最低 iOS 17，iPhone / iPad。界面支持系统深浅色和动态字体。正式启动默认导入附件源，不自动加载演示源。

## 下载和安装

1. 在本仓库 [Releases](https://github.com/xytxg/test/releases) 找到 `WeBox iOS`，下载 `WeBox-iOS-unsigned.ipa`。
2. 使用自己的证书和描述文件，通过侧载/签名工具签名后安装。未签名 IPA 无法直接安装。
3. 首次进入「发现」会自动安装内置红果源。等待目录加载；如果上游返回错误，页面会展示错误和重试按钮。
4. 「源管理」→「从文件导入」选择 `.webox.js`，或「从链接导入」输入 HTTPS 文件直链。导入同一插件 ID 会更新已安装源。
5. 点击内容 → 选集 → 播放，播放结束自动进入下一集。收藏和播放记录保存在设备本地，退出详情页时保存进度；再次进入后点「继续观看」。

每个成功构建的 Release 还提供四张原生模拟器截图、截图 ZIP 和 IPA 的 SHA-256。截图使用显式启用的离线样例，便于复现 UI，不展示或声称实时源站数据。Release 工作流必须先通过 iOS 模拟器测试才发布 IPA。

## 支持范围

| 接口 / 功能 | 当前支持 |
| --- | --- |
| `WeBox.define` | `api: 1.0` 至 `1.5` 的基础接口（不保证所有版本扩展） |
| `filters/list/search/detail/play` | 单值筛选、字符串游标、卡片、分组和分集；播放选择返回的第一条媒体地址 |
| `ctx.http.get/post` | headers、bytes(Base64)、json、body；text/base64/json 响应；有大小和超时限制 |
| `ctx.store` | get/set/remove，每个安装源独立存储；单条 1 MiB |
| `ctx.crypto` | MD5、SHA-1/256/384/512、AES-CBC/ECB/CTR、gzip；UTF-8/hex/Base64 |
| 随机数 / JS | 原生安全随机数、BigInt、TypedArray、Promise |
| 普通媒体 | AVFoundation 支持的 MP4 / HLS 与编解码器；源 headers 传递给播放器 |
| 附件源的 `cencMp4` | 源生成的重建 moov、Range 映射、8 字节 IV / AES-CTR 全样本处理；不提供 DRM 许可证或 FairPlay |
| 收藏、播放记录 | 本地保存，最多 200 条播放记录 |
| 下载 / mpv / ByteVC2 | 未实现；附件源本身也不允许下载 |
| DOM、compute、任意 Node / 其它 WeBox 扩展 | 未实现；声明不支持的 requires 会拒绝导入 |

默认请求为 HTTPS。仅源明确声明 `allowHttp: true` 时基础 HTTP 桥允许 HTTP；加密视频 Range 要求 HTTPS。允许 HTTP 的系统配置是为了兼容用户导入源，不代表网络请求没有检查。不要导入不信任的脚本。

## 红果说明与实际验证边界

附件脚本原样保留在 `Resources/hongguo.webox.js`，其上游声明为 GPL-3.0-only，引用 `zfdang/hongguo-open-player` 的协议实现、`N3urda/hongguoTV` / drpys 的签名代码。原始附件没有包含注释提到的「红果接入说明.md」。没有反编译或复用 APK 中 mpv / FFmpeg 的二进制。

自动化测试覆盖：原附件元数据和筛选、超长 ID 保真、搜索翻页、详情分集；真实 WKWebView 中的同步加密桥和异步存储；AES 官方已知向量、gzip 标头；CENC 跨分段 / 跨样本范围重建和错误 Range 拒绝。网络测试使用固定 HTTP fixture，避免注册设备、上游限流和目录变化造成不稳定。

**尚需设备验证**：红果实际设备注册、签名接口可用性、CDN 视频播放、拖动与锁屏；此项目不能承诺源站永久可用。接口测试和界面截图不能代替这些验证。单个加密样本最多 16 MiB，元数据最多 4 MiB，缓存最多 24 MiB；碎片化 MP4、子样本加密等由附件源拒绝。

## 本地构建

需要 macOS、Xcode 16+、Homebrew 的 `xcodegen` 和 Node 22+：

```bash
cd WeBox-iOS
node Scripts/check-source.mjs
brew install xcodegen
xcodegen generate
xcodebuild test -project WeBox.xcodeproj -scheme WeBox -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project WeBox.xcodeproj -scheme WeBox -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
```

GitHub Actions `.github/workflows/webox-ios.yml` 会测试、截图、构建设备 arm64 应用、检查无签名及无描述文件，再打包为 `Payload/WeBox.app` 的 IPA 并发布 Release。完全不需要 Apple 证书或仓库签名 secrets。

## 许可

本目录代码 GPL-3.0-only，完整许可见 [LICENSE](LICENSE)。附件来源与 SHA-256 见 [docs/PROVENANCE.md](docs/PROVENANCE.md)。
