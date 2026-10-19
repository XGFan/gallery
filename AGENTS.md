# AGENTS.md (gallery)

个人媒体库：Go 后端（Gin）+ React SPA（`web/`，Vite/TypeScript）+ Swift 客户端（`GalleryApp/`、`tiny-viewer/`）。前端经 `//go:embed web/dist` 打进 Go 二进制。领域词汇以 `CONTEXT.md` 为准，设计决策见 `docs/adr/`。

## 构建 / 运行 / Lint / 测试

### 后端（Go，仓库根目录）

- `go run ./app`：本地启动，默认端口 `8000`（`gallery.yaml` 的 `port` 可改），配置文件 `gallery.yaml` 不入库。
- `go test ./...`；单测：`go test -run TestName ./core -v`。
- 生产构建（同 `Dockerfile`）：`GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -tags vips -o gallery ./app`。
- `web/dist` 不入库，不存在时 Go 编译失败（`pattern web/dist: no matching files found`），需先在 `web/` 执行 `npm run build`。
- 缩略图实现由 build tag 决定：`vips` 用 govips/libvips，`nothumb` 不生成缩略图，默认纯 Go。
- Swagger：`swag fmt && swag init -g gallery.go -o swagger`（注解在 `gallery.go`；不带 `-g` 会因根目录无 `main.go` 而失败）。

### 前端（`web/`，Node 24，见 `.nvmrc`）

- `npm run dev`：Vite 端口 `3000`，按 `config/proxy.local.json` 将 `/api`、`/file`、`/thumbnail`、`/video`、`/poster` 代理到 `127.0.0.1:8000`；`npm run dev:remote` 改用 `proxy.remote.json` 代理到线上。
- `npm run build`：`tsc && vite build`，输出 `web/dist/`。
- `npm run lint`：ESLint，`--max-warnings 0`，必须零警告。
- `npm run test`：Vitest 跑一次；`npm run test:watch` 为 watch 模式。
  - 单文件：`npm run test -- src/utils.test.ts`；按名称：`npm run test -- -t "maps media videos"`。
- `npm run test:e2e`：Playwright，自动以 `5173` 端口启动 dev server；Chromium + WebKit × 桌面 1440×900 / 移动 430×932，四个 project：`chromium-desktop`、`chromium-mobile`、`webkit-desktop`、`webkit-mobile`。
  - 单 spec：`npm run test:e2e -- tests/media-video.spec.ts`；按名称：`npm run test:e2e -- --grep "renders video card"`。

### GalleryApp（iOS / macOS 原生客户端）

构建、测试命令与网络前提见 `GalleryApp/README.md`。macOS E2E（`GalleryAppUITests` 配合 `-destination 'platform=macOS'`）会接管真实鼠标与当前桌面空间，未设置 `TEST_RUNNER_GALLERY_MACOS_E2E=1` 时自动跳过，且只能在用户明确确认后触发；日常 E2E 使用 iOS 模拟器。

### tiny-viewer（Swift，`tiny-viewer/`）

- `swift build && swift run tiny-viewer Weibo`（参数为分类名）；`DEBUG=1` 开启调试输出。
- `swift test`：运行 `TinyViewerCoreTests`。
- 打包 macOS：`./scripts/package-macos.sh`，输出 `dist/TinyViewer.app`。
- iOS：`open TinyViewerApp/TinyViewerApp.xcodeproj` 后在 Xcode 中构建运行。

## CI/CD

- `.woodpecker.yaml`（master 的 push / manual）：构建 Docker 镜像，flux-bump 更新 infra 仓库镜像 tag，由 Flux 部署。
- `.github/workflows/ci.yml`（master push，忽略 `**.md` 等路径）构建推送镜像，`cd.yml` 在其成功后 `kubectl set image` 部署。
- 不想触发 CI 时在 commit message 中加 `[skip ci]`。

## 架构要点

- 路由全部在 `gallery.go` 的 `Init()` 注册：`/api/{tree,explore,media,image,album,random,tag}`、`/file/`、`/thumbnail/`、`/video/`、`/poster/`、`/swagger/`，其余走 SPA fallback。
- `/poster/`：先找物理 `cover.{jpg,jpeg,png,webp}` 与已缓存封面（`X-Poster-Status: ready`），否则入队异步生成并返回占位 SVG（`X-Poster-Status: pending`）。封面由 ffmpeg 生成：先用 `thumbnail=100` 滤镜，失败再按时长偏移重试。
- 扫描：`core/scanner.go` 为四级并发流水线 Discovery(8) → SizeProbe(4) → MetaEnricher(4) → Mutator(4)；节点以 `LastScanID` 标记本轮扫描，未被标记的节点被清理。内存树在对外服务期间被原地修改（见 ADR 0009），读路径必须加锁。
- 扫描生命周期：启动时 `warmUp()` 先从缓存恢复再触发扫描；任意 API 调用经 `Trigger()` 在距上次扫描超过 300 秒时触发重扫。
- 缓存：`CacheManager` 在 `.cache/` 下持久化 `.img.json`、`.img-size.v2.json`、`.img-tag.json`、`.img-caption.json`、`.video-meta.json`，用 `reflect.DeepEqual` 比对跳过无变化的写入。
- 配置 `config/conf.go`：`Resource.Base`（媒体根目录）、`Exclude`、`ForceThumbnail`、`VirtualPath`（把多个物理目录聚合成虚拟文件夹，其下媒体路径不以虚拟文件夹路径为前缀）、`TagBlacklist`。

## 代码风格

- 未统一 Prettier/SwiftLint 配置：不要全局格式化，引号、分号、缩进、import 顺序均以当前文件为准。
- TypeScript：`strict`、`noUnusedLocals`、`noUnusedParameters`；类型导入用 `import type`；不要新增 `any`、`as any`、`@ts-ignore`。
- 命名：React 组件 `PascalCase`（文件 `PascalCase.tsx`），函数/变量 `camelCase`，常量 `UPPER_SNAKE_CASE`，工具/模型文件 `camelCase.ts`。
- 日志保持克制，不新增冗长日志。
- Go：`gofmt`；导入分组为标准库 / 三方 / 本地；`if err != nil` 后用 `log.Printf` 记录；仓库中存在 `_ =` 忽略错误的写法，新增时谨慎。
- Swift：4 空格缩进；异步用 `async throws` + `do/catch`；自定义错误实现 `LocalizedError`。
