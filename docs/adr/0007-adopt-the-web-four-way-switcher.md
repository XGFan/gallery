# 客户端改用 Web 的四格切换器，推翻"三个模式是冗余"的结论

> **取代**：CONTEXT.md 早先的「废弃说法」表（把 `album`/`explore`/`image` 判为不该引入
> 新客户端的废弃说法）。该表已按本文重写。

原来的判断是：Web 的三个"模式"只是"是否递归 × 是否列出文件夹"的部分组合，冗余，客户端
用一个**递归开关**就能覆盖。客户端照此建成——`FolderStore` 一个 `recursive: Bool`，在
`/api/explore/` 与 `/api/media/` 之间切。

这个判断建立在一处**读错代码**上：`album` 被当成了"本层视图，只列文件夹"。它不是。
`core/types.go` 的 `ScanAlbum` 会一路递归下去，收集**所有直接装了媒体的后代文件夹**并
拉平：

```go
func (dn *TraverseNode) ScanAlbum(result *[]DirNode) {
	for _, sub := range dn.Directories {
		if sub.HasImages() || sub.HasVideos() { *result = append(*result, ...) }
		sub.ScanAlbum(result)   // 递归
	}
}
```

所以两个维度是 **是否递归 × 列文件夹还是列媒体**，三个模式是其中三种组合，彼此不冗余
（缺的第四种"本层且只列文件夹"才是没用的那个）。而客户端的递归开关只覆盖了 `explore`
与 `image` —— **`album` 整个没有实现**。

代价是具体的：库里 1822 个相册，其中 1507 个埋在第 3 层。Web 上点一个中层文件夹就能摊开
它底下所有相册，客户端只能一层层点进去。这才是"客户端的模式切换不如 Web"的实质，不是
呈现形式的问题。

## 决定

`explore` / `album` / `image` / `random` 四格并排，**名字沿用 Web，不另起中文名**——一套
词汇，两个前端。`random` 摆在同一条切换器里但不是第四种视图，见 ADR-0008。

视图**跟着路由走**，不再是全局偏好：`Route.folder(path)` 变成 `Route.folder(path, view)`，
`folder.recursive` 这个 `UserDefaults` 删除。每个导航入口显式声明落在哪个视图：

| 入口 | 落点 |
|---|---|
| 启动 / 根 | `album` |
| `explore` 里点文件夹 | `explore` |
| `album` 里点相册 | `image` |
| 目录树点非叶节点 | `album` |
| 目录树点叶节点 | `image` |
| Back | 那一屏原本的视图 |
| 手动切换 | 只改当前这一屏 |

## Consequences

- 全局递归开关消失，"在 A 文件夹拨一下、B 文件夹跟着变"这个 bug 类别整体消失。
- 叶子文件夹里 `album` 为空、`explore` 与 `image` 等价，这两格**藏起来**（与 Web 一致）。
  判据不用 Web 那套数斜杠的启发式：`TreeStore` 里已有整棵树，而 `ToTree()` 只收录
  子树里有媒体的目录，所以「树里没有子节点」⟺「`album` 为空」，精确且零请求。这个
  等价关系是被建立出来的，不是白捡的——`ToTree()` 原本按「能不能取到封面」收录，
  而封面对视频要求已探到尺寸，于是纯视频目录会掉出树外。见同批次的后端改动。
- `/api/album/` 不分页（`c.JSON(200, node.Album())` 一次全返）。线上根目录实测 3305 条，
  够用，后端不动。这个结论绑在库的规模上——量级涨一个数量级就得回来补分页。
- 切换器摆在底部悬浮胶囊里，与分页计数器互斥显示；两者都随滚动隐身。底边另外两个住户
  是加载中的 spinner 和分页失败的重试条，后者不随滚动隐身、永远可见（理由见 `FolderView`
  里那条注释）。
