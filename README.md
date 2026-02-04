# Gallery

Gallery 是一个高性能、轻量级的个人媒体库管理系统，支持图片与视频的自动扫描、元数据管理和跨平台浏览。

## 核心特性

- **高性能扫描**: 并发流水线处理，支持数万级图片/视频秒级加载。
- **视频支持**: 自动提取视频宽高、时长，支持 ffmpeg 自动抽帧生成封面。
- **读写分离**: 内存树驱动，浏览体验极其流畅。
- **跨平台客户端**: 提供 Web 端、macOS/iOS 原生客户端 (`tiny-viewer`)。
- **AI 增强**: 支持自动标签标注与说明（可选）。

## 项目结构

- `app/`: 后端 Go 服务入口。
- `core/`: 核心业务逻辑（扫描器、缓存管理、API 处理）。
- `web/`: 基于 React + TypeScript 的前端单页应用。
- `tiny-viewer/`: 基于 Swift 的 Apple 平台原生客户端。
- `docs/`: 详细设计与接口文档。

## 快速开始

### 环境依赖

- **Go**: 1.20+
- **Node.js**: 18+
- **ffmpeg & ffprobe**: 视频元数据提取与抽帧必选。
- **libvips**: 图片处理库。

### 运行后端

```bash
# 复制并修改配置文件
cp gallery.yaml.example gallery.yaml

# 启动服务 (默认端口 8080)
go run ./app
```

### 运行前端

```bash
cd web
npm install
npm run dev        # 默认本地代理
npm run dev:local  # 本地代理 (127.0.0.1:8000)
npm run dev:remote # 远程代理 (https://gallery.test4x.com/)
```

代理配置从文件读取：
- `web/config/proxy.local.json`
- `web/config/proxy.remote.json`

## 测试与验证

### 后端测试
```bash
go test ./...
```

### 前端 Lint & 测试
```bash
cd web
npm run lint   # 静态检查
npm run test   # 单元测试 (Vitest)
npm run test:e2e # E2E 测试 (Playwright)
```

## 常见问题 (FAQ)

### 1. E2E 测试报错 "Proxy error"
如果 E2E 测试运行在无后端环境下，可能会出现代理错误，但由于测试使用了 Mock 机制，通常不影响测试结果的判定。

### 2. 视频无法播放或无封面
请确保 `ffmpeg` 和 `ffprobe` 已安装在系统环境变量中。系统会自动尝试生成 `.cache/` 目录下的视频封面。

### 3. API 返回空数据
Gallery 采用被动扫描机制。初次启动或访问新目录时，系统会在后台启动扫描。请稍等几秒后刷新页面，或查看 `/api/tree` 确认目录是否已被发现。

---
更多详情请参阅 `docs/` 目录下的文档。
