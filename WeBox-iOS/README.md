# WeBox iOS 0.2

固定 iOS 界面、多源数据驱动的原生播放器。首次启动没有内容源，用户导入自己的 JS 文件。iOS 17+，iPhone / iPad；使用 Xcode 27 和 iOS 27 SDK 构建，系统 TabView、工具栏与分层菜单采用原生 Liquid Glass，旧系统自然回退。

## 下载与使用

从本仓库 [Releases](https://github.com/xytxg/test/releases) 下载最新 **WeBox iOS 0.2** 的 `WeBox-iOS-unsigned.ipa`，先使用自己的证书签名，再安装。保持 `com.xylyra.webox` 标识可保留旧版用户数据。

1. 首页左上角 → 添加内容源，或「设置 → 内容源」。
2. 从「文件」App 选择一个或多个 JS 文件，也可填写 HTTP(S) 文件链接；GitHub `/blob/` 链接会转成 Raw。
3. 源需要配置时，点击其配置按钮填写。配置界面由脚本的字段定义生成，支持文本、网址、私密字段、选项、数值、开关和条件显示。
4. 左上角源选择面板切换浏览；当前播放器保持运行。搜索可选择当前源或所有已启用源。
5. 详情页切换线路、分集；超过 50 集会分段显示。播放器内也能切换资源、线路和选集；切换线路会尽量按集名/集号匹配并保留进度。
6. 收起播放器后，可从底栏上方的小播放器继续。倍速、缓冲策略、预热下一集和片头/片尾跳过见播放设置。

导入同一源 ID 会更新文件并保留配置、收藏和记录。普通配置本地保存；标记为 `secret` / `sensitive` 的字段使用设备钥匙串。只迁移移除旧版自动内置的红果源，用户自行导入的源保留；之后手动导入相同 ID 可重新关联记录。

## 协议与能力

| 源协议 | 接入路径 |
| --- | --- |
| WeBox API 1.0–1.5 | `WeBox.define`，settings / filters / list / search / detail / play |
| Widget | `WidgetMetadata`、modules、globalParams、loadDetail、stream 函数 |
| XPTV 常用接口 | getConfig / getCards / getTracks / getPlayinfo，含 JSON 文本返回值 |

| 能力 | 实现 |
| --- | --- |
| HTTP | 带响应上限的分块接收、连接复用、超时与取消；headers / query / text / JSON / Base64 |
| HTML / 加密 | Cheerio、兼容 CryptoJS、原生哈希/HMAC/AES/RSA/gzip，URL 工具 |
| 计算 / DOM | 限时 Worker 与无网络沙盒 iframe；独立于显示 UI |
| 二进制 / 封面 | 有界句柄读取/切片/写入/拼接、声明式 AES-CBC 封面解码、图片请求合并与内存缓存 |
| 播放 | AVFoundation 支持的 MP4/HLS/音频；原生字幕、音轨、AirPlay、画中画控件 |
| CENC MP4 | 源生成的 moov/分段计划、8 字节 IV 的整样本 AES-CTR、32 MiB 范围缓存预算；不提供 DRM 许可证 |
| 源切换 | 浏览选择与播放会话分离；资料库按源 ID 隔离 |

**不支持的扩展**：browserSession、memoryHls、mediaProcessor、任意 Node / ES Module、离线下载。要求这些能力的源会明确提示，不能宣称所有 JS 都兼容。部分 Widget 自定义宿主接口也可能尚未实现。

不包含任何内容站点的算法、密钥、地址或源文件。运行 SDK 参考并复用了用户提供 Android APK 中的协议适配器，站点源仅保留于测试夹具。原附件来源与许可见 [docs/PROVENANCE.md](docs/PROVENANCE.md)。

## 播放实现

播放控制器长期持有会话，不随详情页退出或浏览源切换销毁。状态区分解析、缓冲、播放、暂停、失败和结束。每 8 秒及暂停/后台时保存进度；下一集接近片尾时才预解析并 preroll，取消旧预加载，过期预加载不复用。失败先尝试未用过的返回资源，再刷新解析一次；不会无限重试。

CENC 使用单一 HTTPClient 保持连接。相邻样本从同一 512 KiB 块读取，重复并发范围共享任务；采样索引使用二分查找，内联 moov 只解码一次。原始块缓存 24 MiB，解密样本缓存 8 MiB，校验 Content-Range 和实体标识，取消旧播放时清理任务。

不以固定夹具代替真实网络结论。AVPlayer 实测证明本地合成 H.264/AAC 可播放、续播、切换浏览源后会话不变；仍需用户设备验证源站限流、长视频、后台锁屏、AirPlay、画中画及各类编码。附带红果源的目录/搜索/详情/播放签名和 MP4 计划测试使用模拟 HTTP，无需联系真实注册接口。

## 构建与测试

```bash
cd WeBox-iOS
node Scripts/check-source.mjs
brew install xcodegen
xcodegen generate
python3 Scripts/fixture-server.py &
xcodebuild test -project WeBox.xcodeproj -scheme WeBox -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project WeBox.xcodeproj -scheme WeBox -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
```

工作流使用 `xcode-27` Runner，先验证 SDK，再编译、运行模拟器测试和截图，最后构建设备 IPA。Release 包检查 JS 白名单，拒绝把 `.webox.js`、样例视频和测试资源放进正式应用。

截图夹具只在 Debug + `--screenshots --fixtures=…` 下从模拟器 Documents 临时载入。正式 Release 不包含此加载分支或测试源。截图有空源首页、内容首页、详情、源切换、资料库、设置与真实合成视频播放器。

第三方浏览器库可复现构建：`cd Tools/vendor && npm ci && npm run build`。版本和依赖锁定，许可证随库重新生成。GPL-3.0-only，完整许可与第三方声明同时包含在应用与源码中。
