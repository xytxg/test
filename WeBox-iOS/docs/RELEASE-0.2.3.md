## WeBox iOS 0.2.3

- 备用 DNS 合并阿里和 Cloudflare 的 IPv4、IPv6 地址，交错尝试 TCP 连接。只有选中的线路会发送 HTTPS 请求。
- 错误区分本地 CONNECT、上游 TCP、HTTPS 握手，保留 iOS 错误码。
- 新增「设置 → 网络 → 源网络线路」。当源站地址无法直接连通时，可手动选择用户已有的 HTTP CONNECT 或 SOCKS5 代理。支持一键填写本机 Surge 的默认 HTTP 端口，需按实际启用的代理服务配置。
- 代理只用于源脚本的 HTTPS 请求。源脚本、注册正文、请求签名及原域名的 TLS 校验保持原样。
- 模拟器测试覆盖首个 IP 不通后选用可达地址、所有地址不通时的阶段报告，以及真实脚本 POST 经手动代理完成 HTTPS。
- IPA 未签名，不内置内容源。
