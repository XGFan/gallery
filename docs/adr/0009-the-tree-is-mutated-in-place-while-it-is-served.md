# 目录树在被服务的同时原地改，所以每条读路径都必须加锁

最初的实现是 **copy-and-swap**：扫描在一棵全新的私有树上进行，扫完一次性替换掉旧的。

```go
// 2109683:viewer.go —— 重构前
node := &TraverseNode{...}              // 全新的树
for info := range result {
    located := node.Locate(info.Path)   // 只写这棵新树
    located.Images = info.Images
}
v.Data = node                           // 扫完才发布
```

读的人始终读已发布的那棵，扫描期间没有任何共享可变状态。

`8b0eb7e`（2026-01-12，*overhaul scanning pipeline and cache mechanism*）换掉了它，理由写在
那次的 commit message 里：用 `LastScanID` 的代号机制做增量更新，把目录更新从 O(N²) 降到
O(1) 的 append-only；同时让冷启动的缓存恢复和运行时的实时扫描走同一条 Mutator 路径，不再
有两套代码。

代价是当时没有被记下来的那一半：**树从此是原地改的，而它同时正在被 HTTP 服务。**

## 这不是「数据竞争」那么轻

Go 对「一个 goroutine 遍历 map，另一个写同一张 map」的处理不是竞态读到脏值，而是：

```
fatal error: concurrent map iteration and map write
```

不可恢复，`recover` 接不住，整个进程死。`core/race_probe_test.go` 复现了它——修复前不带
`-race` 连跑 6 次有 3 次直接 fatal。

最危险的窗口是**冷启动**：启动日志里 `Open http://...` 出现在 `Scan started` 之前，服务在
首次全量扫描（成千上万次 `Locate` 写）期间就已经在收请求了。每次部署、每次 pod 重启都要过
一遍；崩了被拉起来，再走一遍。

## 决定

**保留原地改，给读路径加锁**，而不是退回 copy-and-swap。

`TraverseNode.mu` 本来就是 `sync.RWMutex`，只是读侧从来没用过它。现在所有读路径统一走加锁
访问器：`subdirs` / `namedSubdirs` / `subdirCount` 在读锁下把子节点快照成切片；
`imageSlice` / `videoSlice` / `otherSlice` / `coverIndex` 在读锁下取值——切片只拷 3 字的头，
不拷元素。写路径（`Load`、`LoadTagsAndCaptions`、`CleanupRecursively`）取写锁。

锁只圈住元素循环，**递归留在锁外**：持着父节点的锁走完整棵子树，会把扫描器挡在整片子树外面。

## 为什么不退回 copy-and-swap

它同样能消除这个问题，但要把 `8b0eb7e` 换来的东西一起还回去：O(1) 增量更新、冷启动与热扫描
共用一条路径。而且 10 万节点的树每次扫描全量重建一次，期间还要同时持有两棵。

加锁的代价小得多：读侧只是拷指针和切片头，没有元素拷贝。

## Consequences

- **读快照里 `[0, len)` 的元素始终安全**，因为扫描器只往读者捕获的长度之后追加。这条性质是
  访问器只拷切片头（而不是深拷元素）的前提，改动扫描器时不能破坏它。
- **不要在持锁期间递归**。这不是风格问题：父锁 + 子树遍历会让扫描器在整片子树上饿死。
- `core/race_probe_test.go` 是回归测试：6 条读路径 vs 扫描器同时改 map 和切片。它在普通
  `go test` 下也跑（不到 1 秒），退化了会重新 fatal。CI 若要加一道保险，`go test -race ./core`
  是最直接的。
- 这条约束对**所有**读路径成立，不只是新加的那条。任何新增的树遍历都必须走访问器。
