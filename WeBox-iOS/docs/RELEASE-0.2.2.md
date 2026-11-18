## WeBox iOS 0.2.2

- 对照了 Android APK 的 QuickJS 和 OkHttp 请求链，以及用户源脚本的匿名注册和目录访问顺序。
- 开启「备用 DNS 连接」后，系统解析失败且原请求未发送时，WeBox 使用公共 DNS 查询 A/AAAA，然后连接解析出的 HTTPS 地址。沿用 0.2.1 的 DNS 开关状态。
- TLS 校验继续使用源的原始域名。不会为 HTTP、证书错误、HTTP 拒绝、已发送请求或跨域重定向启用备用连接。
- 当备用连接使用 IP 建立 TCP，VPN 的按域名规则可能无法识别它。默认关闭，可在 WeBox 的网络设置中切回系统解析。
- 测试使用独立的模拟器 HTTPS 服务，校验真实 TLS、服务端 SNI、Host 和 POST 正文。源脚本不内置。
- IPA 未签名，支持 iOS 17 及以上。
