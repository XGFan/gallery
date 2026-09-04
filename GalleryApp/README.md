# GalleryApp

Gallery 的 iOS / macOS 原生客户端。一套 SwiftUI 代码，两个平台。

设计决策见仓库根的 `CONTEXT.md`（领域词汇表）与 `docs/adr/`。

## 工程是生成的

`GalleryApp.xcodeproj` **不入库**，由 [XcodeGen](https://github.com/yonaskolb/XcodeGen)
从 `project.yml` 生成。改工程配置请改 `project.yml`，不要在 Xcode 里改。

```shell
brew install xcodegen   # 如未安装
cd GalleryApp
xcodegen generate
```

## 构建与测试

本机 `xcode-select` 指向 CommandLineTools，因此所有 `xcodebuild` 调用都要显式指定
`DEVELOPER_DIR`（与 `ios-cert/README.md` 的做法一致）：

```shell
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# macOS
xcodebuild -project GalleryApp.xcodeproj -scheme GalleryApp \
  -destination 'platform=macOS' -derivedDataPath .build build

# iOS 模拟器
xcodebuild -project GalleryApp.xcodeproj -scheme GalleryApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build build

# 单元测试（纯逻辑，不联网）
xcodebuild test -project GalleryApp.xcodeproj -scheme GalleryApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build \
  -only-testing:GalleryKitTests

# E2E（打真实后端，见下）
xcodebuild test -project GalleryApp.xcodeproj -scheme GalleryApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build \
  -only-testing:GalleryAppUITests
```

### macOS 上的 UI 测试需要先授权

E2E target 同时支持 macOS，但 macOS 的 UI 测试要求**辅助功能授权**，会弹一次系统对话框。
在非交互环境下它会直接失败：

```
The test runner failed to initialize for UI testing.
(Underlying Error: Authentication canceled. System authentication is running.)
```

首次在 macOS 上跑 E2E 时需要人工确认那个弹窗（同样的权限也决定了 `screencapture`
能否截到窗口内容）。授权前，macOS 端只能验证到「编译通过 + 启动不崩溃 + API 请求成功」。

装进模拟器手动看：

```shell
SIM=$(xcrun simctl list devices available | grep -m1 "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $SIM
xcrun simctl install $SIM .build/Build/Products/Debug-iphonesimulator/GalleryApp.app
xcrun simctl launch $SIM com.gallery.app
xcrun simctl io $SIM screenshot shot.png
```

## 网络前提

客户端**没有登录流程、不存任何凭证**：后端挂在 tinyauth 之后，但对
`192.168.2.0/24`（家庭局域网）与 `10.126.126.0/24`（easytier）配了 IP bypass。
详见 `docs/adr/0004`。

因此 **E2E 必须在这两个网段内跑**，否则会拿到 tinyauth 的登录页而非 JSON。
客户端会把这种情况识别出来并提示「请接入家庭局域网或 easytier」，而不是白屏。

默认指向 `https://gallery.test4x.com`；要指向别处，改 `UserDefaults` 的
`gallery.baseURL`。

## 签名

- **模拟器**：不需要签名。
- **本机 macOS**：ad-hoc 签名（`CODE_SIGN_IDENTITY = "-"`），`project.yml` 里已配好。
- **真机**：**不走 Xcode 签名**。按 `ios-cert/README.md` 的配方，先出未签名的 Release
  构建，再用那张 Ad Hoc 分发证书重签。该证书 `get-task-allow=false`，装上去的包
  无法用 Xcode 调试——真机调试要另用免费 personal team 签一个 `.dev` bundle id 的版本。

## 目录

| 路径 | 内容 |
|---|---|
| `Sources/GalleryKit/` | 模型、网络、分页状态机。无 UI 依赖，可在 macOS 上全速调试 |
| `Sources/GalleryUI/` | 瀑布流墙、单元格、文件夹页、播放器 |
| `Sources/App/` | App 入口与根视图（iOS sheet / macOS sidebar 的分叉在这里） |
| `Tests/GalleryKitTests/` | 纯逻辑单测 |
| `Tests/GalleryAppUITests/` | E2E，打真实后端 |
