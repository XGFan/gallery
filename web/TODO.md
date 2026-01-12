# TODO

## 高优先级

### 类型安全问题

- [ ] **viewer.tsx:91** - 移除 `as any` 类型断言
  ```tsx
  // 当前代码
  const key: string = (currentSlide as any).key
  
  // 建议: 为 lightbox slide 定义包含 key 的类型
  ```

- [ ] **App.tsx:40** - 移除 `as never` 类型断言
  ```tsx
  // 当前代码
  const images = resp2Image(resp.data as never, requestMode);
  
  // 建议: 定义 API 响应类型
  ```

### 可疑依赖

- [ ] 移除 package.json 中的无效依赖:
  - `"install": "^0.13.0"` - 不是有效的 npm 包
  - `"npm": "^10.5.0"` - 不应作为项目依赖

## 中优先级

### 调试日志清理

以下文件包含 console.log 语句，应在生产环境移除或使用环境变量控制的 logger：

- [ ] `viewer.tsx` (6处)
- [ ] `dto.tsx` → 现在是 `utils.ts` (3处)
- [ ] `file-tree.tsx` (2处)

### 可能未使用的 CSS

- [ ] `viewer.css` 中的 `.jg-caption` 类可能是旧库残留，验证是否仍在使用

## 低优先级

### 性能优化

- [ ] 考虑使用虚拟化列表（如 `react-window`）处理大量图片
- [ ] 为 API 请求添加 loading 状态和错误边界
- [ ] 考虑预加载当前视口外的几张图片

### 可访问性

- [ ] `Slider` 组件添加 `aria-label` 属性
