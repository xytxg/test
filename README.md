# NodeSeek++ XY Test

基于 [rirh/nodeseek-plus](https://github.com/rirh/nodeseek-plus) **26.1027.1729** 源码独立维护的测试优化版。遵循 [GPL-3.0-only](LICENSE)，保留上游许可与 [第三方声明](THIRD_PARTY_NOTICES.md)。

> **测试版**：请先禁用原版 NodeSeek++，再安装本版，避免两个脚本同时修改 NodeSeek / DeepFlood 页面。未经真人浏览器测试，不保证所有功能正常。

## 一键安装

[安装 NodeSeek++ XY Test](https://raw.githubusercontent.com/xytxg/test/main/dist/nodeseek-plus-plus.user.js)

[仅查看版本元数据](https://raw.githubusercontent.com/xytxg/test/main/dist/nodeseek-plus-plus.meta.js)

## 本版修复

- **签到可靠性**：签到失败、HTTP 错误和网络异常不再被当成签到成功；每日自动尝试仍有记录，用户可手动重试。
- **iOS Userscripts 存储**：对同一存储键串行提交，在“保存并刷新”前等待异步写入，明确报告写入失败。
- **请求队列取消**：页面关闭、模块卸载时提前删除尚未发起的排队请求，降低无效排队。
- **独立版本更新**：独立脚本 namespace / updateURL / downloadURL，不会从上游仓库覆盖测试版。
- **持续集成**：GitHub Actions 运行类型检查、构建及测试，通过后提交打包产物。

## 参与开发

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm typecheck
pnpm build
pnpm test
```

> 主分支构建与测试是否通过，以 [GitHub Actions](https://github.com/xytxg/test/actions) 的真实运行状态为准。

上游版权归原项目贡献者所有。本仓库是独立测试版本，不代表原作者官方发布。
