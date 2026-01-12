# 扫描、缓存与刷新机制

本文档详细说明了 Gallery 的文件扫描、元数据缓存和刷新触发的内部逻辑。

## 1. 架构概览

扫描系统集中在 `core.Scanner` 组件中。它负责编排发现文件、处理元数据及更新内存树 (`TraverseNode`) 的整个生命周期。

### 核心组件
- **Scanner**: 编排扫描管道并管理状态。
- **Gallery**: 持有根节点 (`Root`) 并触发扫描的高层服务。
- **Pipeline (管道)**: 并发处理文件的流水线 (`Discovery` -> `Size` -> `Meta` -> `Mutator`)。

## 2. 扫描流程

`Scanner.Scan(root *TraverseNode)` 方法执行文件树的完全刷新。其步骤如下：

1.  **Discovery (文件发现)**:
    - 使用 `StartDiscovery` 遍历文件系统。
    - 生成 `ScanItem` 流（目录、文件、图片）。
    - 遵循 `Exclude` 排除规则。

2.  **Pipeline Processing (管道处理)**:
    - **SizeProbe (尺寸探测)**: 过滤有效图片并解析尺寸（从缓存读取或解码文件头）。
    - **MetaEnricher (元数据增强)**: 从缓存加载标签和说明。高并发（4个工作线程）。
    - **Mutator (变更器)**: 管道的“汇聚”阶段，负责更新全局 `TraverseNode` 树。

### Mutator 详解 (变更逻辑)

Mutator 是管道的终点，采用 4 个并发工作线程 (`workerSize=4`) 将处理好的 `ScanItem` 写入内存树。为了支持高并发与高性能，它采用了以下关键机制：

1.  **基于代的更新 (Generation-based Update)**:
    - 每次 `Scan` 开始时，会生成一个唯一的 `currentScanID`（通常是纳秒级时间戳）。
    - 每一个目录节点 (`TraverseNode`) 都有一个 `LastScanID` 字段，记录它最后一次被更新的扫描代数。

2.  **O(1) 追加优化 (The Optimization)**:
    - 传统做法：在插入一张图片时，遍历当前目录下的 `Images` 列表，检查是否存在，存在则更新，不存在则追加。这是 O(N) 操作，会导致 O(N²) 的目录扫描复杂度。
    - **当前做法**:
        - 当 Mutator 收到一个图片项目时，先锁定该目录节点 (`node.mu.Lock()`)。
        - 检查 `node.LastScanID`。
        - **情况 A (首次访问)**: 如果 `LastScanID < currentScanID`，说明这是本次扫描第一次访问该目录。
            - 将 `LastScanID` 更新为 `currentScanID`。
            - **清空** `Images` 和 `Others` 列表 (`make([]ImageNode, 0)`)。
            - 将该图片 **追加** 到列表。
        - **情况 B (后续访问)**: 如果 `LastScanID == currentScanID`，说明该目录在本次扫描中已经被重置过。
            - 直接将该图片 **追加** 到列表。
    - **结果**: 插入操作永远是 O(1) 的简单的切片追加。无需查找，无需去重（因为文件发现阶段保证了路径唯一性）。

3.  **自动清理 (Implicit Cleanup)**:
    - 由于我们在“首次访问”时清空了列表，那些存在于旧版本但本次扫描中未出现的文件（即被删除的文件），自然就不会被添加到新列表中。
    - 这种“重建”策略自动处理了文件的删除，无需额外的 diff 逻辑。
    - *注意*: 对于完全删除的子目录，由后续的 `cleanupDeletedFiles` 递归步骤处理。

3.  **Virtual Paths (虚拟路径)**:
    - 物理扫描结束后，`ApplyVirtualPaths` 将配置的虚拟文件夹合并到根节点中。

4.  **Persistence (持久化)**:
    - 最后，`Persist` 将当前状态（尺寸、结构）保存到缓存文件中。

## 3. 缓存与预热

### Warm-up (预热/恢复)
启动时，`Gallery.warmUp` 调用 `Scanner.Restore`。
- 从缓存文件中加载扁平化的项目列表。
- 将它们像文件系统扫描一样送入 **管道**。
- 这能立即重建内存树，无需接触磁盘（除非检查文件存在性/属性涉及磁盘 I/O，但通常快得多）。

### Persistence (持久化)
- `Scanner.Persist` 将树状态转储为 JSON 缓存文件。
- 包含图片尺寸、标签和结构，加速后续启动。

## 4. 刷新策略 (Trigger)

系统支持“防抖”刷新，以在不导致系统过载的情况下保持视图一致性。

### 触发机制
- **方法**: `Gallery.Trigger()`
- **条件**: 仅在上次扫描超过 300 秒后触发（冷却时间）。
- **节流 (Throttling)**:
    - 使用 **无缓冲通道** (`make(chan struct{})`)。
    - 逻辑: `select { case ch <- struct{}{}: ... default: drop }`
    - **行为**:
        - 如果工作线程空闲，信号被接收，扫描开始。
        - 如果工作线程忙碌（正在扫描），信号被 **丢弃**。
        - 这防止了多个触发器排队导致的“无限循环刷新”。在扫描期间到达的触发器实际上会被正在进行的扫描满足（因为该扫描结束时数据是新鲜的）。

### 扫描工作线程
- 在后台 goroutine (`scanWorker`) 中运行。
- 监听 `rescanTrigger` 通道。
- 收到信号后调用 `scanner.Scan(g.Root)`。
