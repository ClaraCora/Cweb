# Design System

## Intent

场景是用户在日常环境光下快速确认身份并登录固定页面。界面以系统原生、低认知负担为骨架，以深靛色的少量强调和清晰的环境标识表达私密感，不模拟“黑客工具”。

## Foundation

- 使用 SwiftUI 原生 `NavigationStack`、`List`、`Form`、`sheet`、`alert`、`Menu` 和 `ToolbarItem`。
- 所有文字使用 San Francisco 的语义文本样式，不设置硬编码字号。
- 背景、分隔线、主次文字采用系统语义颜色，自动适配深浅色与提高对比度。
- 主色锚点为 `PrivacyTint`：概念值 `oklch(0.45 0.18 270)`，在 Asset Catalog 中提供可访问的浅色/深色 sRGB 版本。
- `PrivacyTint` 只用于主操作、选中环境和当前会话标识，表面积不超过约 10%。成功、警告和危险状态分别使用系统 green、orange、red。

## Layout

- 环境列表使用 inset grouped list，不把页面区块做成浮动卡片。
- 顶层环境页使用 Large Title；编辑、凭据和诊断页使用 inline title。
- iPhone 使用单列结构；iPad 保持可读宽度并使用系统列表适配，不强制固定像素宽度。
- 间距遵循 4/8 pt 节奏；图标按钮保持至少 44 pt 点击区域。
- 浏览器页面让网页占满剩余空间，地址栏与导航栏使用系统材质并尊重安全区。

## Components

### Profile Row

- 领先位置为圆角方形环境标识，使用 SF Symbol `person.crop.square`。
- 主文本显示环境名，次文本显示主页域名。
- 当前状态用图标加文字表达，不只依靠颜色。
- 行本身进入环境；更多操作使用系统 context menu 和 swipe actions。

### Empty State

- 使用 `ContentUnavailableView`、`person.crop.square.badge.plus` 和一个“新建环境”主操作。
- 文案只说明当前没有环境，不罗列功能介绍。

### Browser Chrome

- 顶部地址输入使用系统圆角输入外观，提交键为 Go。
- 底部工具栏仅保留返回、前进、主页、凭据和退出环境五项。
- 加载进度以细 `ProgressView` 表示，不改变工具栏尺寸。
- 当前环境名在导航栏中可见，避免错用身份。

### Forms And Feedback

- 每个表单字段有可见标签；错误显示在相关 Section 内。
- 保存按钮使用系统 toolbar Done；无更改或输入无效时禁用。
- 删除环境使用 destructive alert，明确列出网站数据与凭据都会删除。
- 长任务显示行内 ProgressView，并禁用会冲突的操作。

## Motion

- 使用系统 push、sheet 和 alert 转场。
- 状态变化只使用系统默认的 150–250 ms 反馈，不加入装饰性入场序列。
- `accessibilityReduceMotion` 开启时不增加自定义位移动画。

## Accessibility

- SF Symbols 配合文字，纯图标工具栏按钮提供 `accessibilityLabel` 和 `accessibilityHint`。
- 支持超大 Dynamic Type；工具栏保持稳定高度，必要时由系统折叠标签。
- VoiceOver 顺序与视觉顺序一致。
- 隔离、错误和删除状态均使用图标、文字和颜色三者中的至少两种。
