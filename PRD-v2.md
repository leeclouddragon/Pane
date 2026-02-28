# Pane v2 优化 PRD

## 1. Slash 命令面板优化

### 现状

- 面板固定宽度 320pt，位于 composer overlay 区域
- 每行只展示一个命令（icon + name + description 横排）
- 面板与 composer 外框左对齐，而非与输入框左对齐

### 需求

**1.1 与输入框左对齐**

面板左边缘与输入框文字起始位置对齐，而非与 composer 外框对齐。当前 composer 左侧有 `+` 附件按钮占位，面板应跳过这段偏移。

**1.2 加宽面板，一行多列**

加宽面板至 composer 同宽（减去左右 padding），每行展示 2-3 个命令，网格布局。每个命令卡片包含 icon、name、description（description 可折行或截断）。

**1.3 交互保持不变**

- `/` 触发，继续输入过滤
- Up/Down 键盘导航（网格中改为上下行跳转）
- Enter 确认，Escape 关闭
- 鼠标点击选中

### 参考

Claude Code CLI 的 slash 面板：多列网格、宽面板、与输入区左对齐。

---

## 2. Streaming 期间排队发送用户消息

### 现状

- Agent 正在输出（`isStreaming = true`）时，composer 的发送按钮被禁用
- 用户无法在 agent 输出过程中提前编写和发送下一条消息
- Claude Code CLI 支持此能力：streaming 时可以输入并发送，消息排队等待当前输出结束后发出

### 需求

**2.1 Streaming 期间允许输入和发送**

- `isStreaming` 状态下，composer 输入框保持可编辑
- 发送按钮保持可用（可考虑视觉上区分，如改为排队图标）
- 用户按 Enter/点击发送后，消息进入待发送队列

**2.2 消息队列机制**

- `ConversationState` 新增 `pendingMessages: [PendingMessage]` 队列
- 发送时若 `isStreaming`，将消息（文本 + 附件）入队而非立即发送
- 当前 streaming 结束（收到 `.result` 事件）后，自动出队并发送下一条
- 队列中的消息在 UI 上即时展示为用户气泡（灰色/半透明状态标识待发送）

**2.3 队列可取消**

- 待发送消息可被用户取消（点击消息上的取消按钮或快捷键）
- 取消后从队列和 UI 中移除

**2.4 边界处理**

- 多条排队消息按顺序逐条发送
- 如果当前 streaming 被用户中断（stop），排队消息仍然正常发出
- 附件（图片）随消息一起入队保存

---

## 3. Bug 修复：分屏时粘贴图片进入错误分屏

### 现象

分屏模式下，用户在右侧分屏中 Cmd+V 粘贴图片，图片出现在左侧分屏的 composer 中。

### 根因分析

`InputTextView` 中 `PaneTextView` 重写了 `performKeyEquivalent(_:)` 拦截 Cmd+V。`performKeyEquivalent` 由 AppKit 沿视图树广播给所有子视图，不仅仅是 first responder。两个分屏各自的 `PaneTextView` 都会收到此调用，先返回 `true` 的那个"吃掉"事件——但这个顺序取决于视图树遍历顺序（通常是先左后右），而非用户焦点。

### 修复方案

在 `performKeyEquivalent` 处理 Cmd+V 前，检查 `self` 是否是当前 window 的 first responder：

```swift
override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command),
          event.charactersIgnoringModifiers == "v",
          window?.firstResponder == self else {  // ← 新增守卫
        return super.performKeyEquivalent(with: event)
    }
    pasteFromClipboard()
    return true
}
```

只有实际拥有焦点的 text view 才处理粘贴。

---

## 优先级

| # | 需求 | 优先级 | 复杂度 |
|---|------|--------|--------|
| 3 | 粘贴图片 Bug | P0 | 低 |
| 2 | Streaming 排队发送 | P1 | 中 |
| 1 | Slash 面板优化 | P2 | 低 |
