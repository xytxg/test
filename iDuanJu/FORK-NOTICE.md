# i短剧 XY

这是 iDuanJu 的修改版本。上游为 [my-name-is-alan/iDuanJu](https://github.com/my-name-is-alan/iDuanJu)，基于提交 [a13daac58a53](https://github.com/my-name-is-alan/iDuanJu/commit/a13daac58a53bf750befd7d0b25c4b1fa9e8bc63)。

2026-11-18，xytxg 版本 1.5.1（15）修改了 iOS 导航、搜索、频道和详情控件、播放器及读者面板，启用原生 Liquid Glass，加入应用外观选项，并修正分页任务取消和重复游标处理。iOS 显示名、版本和应用标识已更新。

本项目按 [GNU GPL v3](LICENSE) 提供完整修改后的源码，保留上游及其贡献者的版权与署名。第三方依赖与素材的许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和各组件的许可文件。此版本免费分发。

## iOS 构建

使用 Xcode 27 与 XcodeGen。在本目录运行 `xcodegen generate`，打开 `STV.xcodeproj`，选择 STV scheme。SwiftPM 依赖在 [project.yml](project.yml) 声明。按 [scripts/package.sh](scripts/package.sh) 可在 Mac 上构建未签名包。

`com.xylyra.iduanju` 使用自己的本机数据容器，可与上游应用分别安装。
