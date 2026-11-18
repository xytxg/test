## WeBox iOS 0.2.1

- 网络错误显示失败域名和 iOS 错误码，区分 DNS、蜂窝限制、连接、超时和证书问题。
- 首页 DNS 错误可选择「用 Google 加密 DNS 重试」。WeBox 会重建源会话并重新加载。该选项只改变 WeBox 的解析策略，iOS 已配置的 DNS 优先。可在 WeBox 设置中关闭。
- IPA 未签名，支持 iOS 17 及以上，不内置任何内容源。
