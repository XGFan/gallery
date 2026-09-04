# 客户端依赖 tinyauth 的内网 IP bypass，不实现登录流程

Gallery 早已挂在 homelab 的 tinyauth 之后（Traefik forwardAuth → tinyauth →
Pocket ID passkey），并且配了内网免登陆：

```yaml
# infra: k8s/edge/tinyauth/tinyauth.yaml
- { name: TINYAUTH_APPS_GALLERY_IP_BYPASS, value: "192.168.2.0/24,10.126.126.0/24" }
```

`192.168.2.0/24` 是家庭局域网，`10.126.126.0/24` 是 easytier 虚拟网段。客户端的使用场景
就在这两个网段内，因此**客户端不实现任何登录流程、不存储任何凭证**，只要一个 baseURL。

## 必须实现的一件事

不在 bypass 网段时（公网且未接 VPN），forward-auth 返回 **302 跳登录页而非 401**。客户端
要能识别"请求 JSON 却收到 HTML"，给出明确提示（"请接入内网或 easytier"），而不是白屏
或崩溃。这不是为了登录，是为了错误提示不误导人。

## 为什么不做真正的 tinyauth 接入

即便要做，tinyauth 是**浏览器导向**的 forward-auth 代理，对原生客户端的成本是：

1. `ASWebAuthenticationSession` 走登录页拿 cookie —— 可接受。
2. **`AVURLAsset` 走自己的媒体加载栈，不共享 `URLSession` 的 cookie**，必须显式传
   `AVURLAssetHTTPCookiesKey`。漏了就是视频黑屏 401，报错极不直观。
3. `SESSION_EXPIRY` 默认 **86400 秒**且仅在活跃时续期 → App 一天不开就过期，
   **每天第一次打开都要重新登录**。对"随手打开瞟两眼"是硬伤。

而它的几个绕过口对原生客户端都不成立：`ip.bypass` 是我们已经在用的那条（走网络层，
不走客户端）；basic auth 标签是 tinyauth **向被保护应用**注入凭证，不是给客户端进门用的；
OIDC provider 模式只支持 `code` response type，文档未提 PKCE。

日后若真要让客户端在任意网络下可用，正确的路子不是接 tinyauth 的 cookie，而是走
**Pocket ID 的标准 OIDC + PKCE**（homelab 已有 `id.test4x.com`），拿 token 而非 cookie ——
那样 `AVURLAsset` 也只需带一个 header，不必碰 cookie 传递。

## 一条教训

最初的调研结论是"gallery 公网无鉴权裸奔"，依据是从**这台 Mac**（`192.168.2.0/24` 内）
`curl` 得到 200。那是命中 IP bypass 的假象。**在配了 IP bypass 的环境里，从内网探测
鉴权状态永远得不到真相。**
