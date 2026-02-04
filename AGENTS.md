# AGENTS.md (gallery)

> 供自动化/Agent 编码工具使用。本文件基于当前仓库配置与源码风格整理。

## 目录结构概览

- `web/`：Vite + React + TypeScript 前端
- `app/`：Go 后端入口（`app/main.go`）
- `tiny-viewer/`：Swift (macOS/iOS) 客户端

## 构建 / 运行 / Lint / 测试

### 前端（web/）

工作目录：`web/`

- 开发服务器：
  - `npm run dev`（实际执行：`vite --host`）
- 构建：
  - `npm run build`（实际执行：`tsc && vite build`）
- Lint：
  - `npm run lint`（`eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0`）
- 预览构建：
  - `npm run preview`
- 单元测试（Vitest）：
  - `npm run test`
  - 测试文件示例：`web/src/utils.test.ts`
- E2E（Playwright）：
  - `npm run test:e2e`
  - 视频支持验证：`npm run test:e2e -- web/tests/media-video.spec.ts`

#### 运行单个测试（前端）

- 运行单个 Vitest 文件：
  - `npm run test -- src/utils.test.ts`
- 运行单个 Vitest 用例（按名称匹配）：
  - `npm run test -- -t "maps media videos"`
- 运行单个 Playwright spec：
  - `npm run test:e2e -- web/tests/media-video.spec.ts`
- 运行单个 Playwright 用例（按名称匹配）：
  - `npm run test:e2e -- --grep "renders video card"`

### 后端（Go，根目录 / app/）

工作目录：仓库根

- Docker 构建使用：
  - `GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -tags vips -o gallery .`
  - 来源：`Dockerfile`（`/app` 目录内执行）
- 运行（开发）：
  - 入口：`app/main.go`，可通过 `go run ./app` 本地启动（如需）

> 说明：未发现 Go 测试文件（`*_test.go`）。

### tiny-viewer（Swift）

工作目录：`tiny-viewer/`

- 构建并运行（macOS CLI）：
  - `swift build && swift run tiny-viewer Weibo`
- Debug 运行：
  - `DEBUG=1 swift run tiny-viewer Weibo`
- 打包（macOS）：
  - `./scripts/package-macos.sh`（输出：`dist/TinyViewer.app`）
- iOS（Xcode）：
  - `open TinyViewerApp/TinyViewerApp.xcodeproj`，通过 Xcode `⌘R` 构建运行

> 说明：`Package.swift` 未定义 `testTarget`，暂无 Swift 测试目标。

## CI/CD 说明

- `.drone.yml` 定义 Drone 流水线：构建 Docker 镜像并部署到 K8s。
- 主要镜像构建入口为 `Dockerfile`。

## 代码风格与规范（当前仓库观察）

### 通用原则

- 本仓库未统一 Prettier/SwiftLint 配置：**不要强行全局格式化**。
- 同一文件内风格不一时，**优先保持当前文件已有风格**（引号、分号、缩进、空行）。
- 避免“顺手重排/重构”跨文件变更。

### TypeScript / React（web/）

#### ESLint（`web/.eslintrc.cjs`）

- `eslint:recommended`
- `@typescript-eslint/recommended`
- `react-hooks/recommended`
- `react-refresh/only-export-components`：`warn`（允许常量导出）
- Lint 需 **零警告**：`--max-warnings 0`

#### TypeScript（`web/tsconfig.json`）

- `strict: true`
- `noUnusedLocals: true`
- `noUnusedParameters: true`
- `moduleResolution: bundler`
- `jsx: react-jsx`

#### 命名与结构

- React 组件：`PascalCase`（如 `Viewer`, `TopBar`）
- 函数/变量：`camelCase`
- 常量：`UPPER_SNAKE_CASE`（如 `DEFAULT_PAGE_SIZE`）
- Types/Interfaces：`PascalCase`
- 文件名：组件多为 `PascalCase.tsx`；工具/模型使用 `camelCase.ts`

#### import / 格式

- 类型导入使用 `import type`（见 `web/src/utils.ts`）。
- 同仓库存在单双引号与分号混用（见 `web/src/App.tsx` 与 `web/src/utils.ts`）。
- 不存在统一的 import 排序规则：新增 import 时跟随当前文件顺序。
- 缩进有 2 或 4 空格混用：以当前文件为准。

#### 错误处理与日志

- 存在 `console.log` 调试输出（见 `web/src/utils.ts`, `web/src/Viewer.tsx`）。
- 新增日志保持克制，可读即可；不要新增冗长日志。
- 避免引入 `any` 或忽略类型错误（不要新增 `as any` / `@ts-ignore`）。

### Go 后端

- 代码由 `gofmt` 控制缩进（Tab）。
- 导入分组：标准库 / 三方 / 本地（见 `gallery.go`）。
- 错误处理：常用 `if err != nil` 并用 `log.Printf` 记录（见 `thumbnail/libvips.go`）。
- 可见 `_ =` 忽略错误的用法（如 `storage.SafetyCreateDirectoryByFileName`），新增时谨慎。

### Swift（tiny-viewer）

- 缩进使用 4 空格；类型与文件名多为 `PascalCase`。
- SwiftUI 组件为 `struct` 或 `class`，属性/方法 `camelCase`。
- 并发模式：`async throws` + `do/catch`（见 `NetworkManager.swift`, `GalleryViewModel.swift`）。
- 自定义错误实现 `LocalizedError`（见 `NetworkManager.swift`）。
- 依赖管理：SwiftPM（`Package.swift`）。

## 运行环境提示

- 前端 Vite proxy 指向：
  - `/api`, `/file`, `/thumbnail`, `/video`, `/poster` → `http://127.0.0.1:8000/`
  - 见 `web/vite.config.ts`

## Cursor / Copilot 规则

- 未找到 `.cursor/rules/` 或 `.cursorrules`
- 未找到 `.github/copilot-instructions.md`

## 约束与建议（Agent 执行）

- 更改命令前先确认工作目录（`web/`、`tiny-viewer/`、根目录）。
- 只在用户明确要求时提交/修改大范围格式。
- 保持改动小而精准，避免跨文件“顺手重构”。
- 测试存在时优先只跑受影响的单测/单个 spec。
