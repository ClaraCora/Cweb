# Product

## Register

product

## Platform

ios

## Users

唯一主要用户是 App 的作者本人，在 iPhone 上为几个固定网站维护彼此独立的登录环境。使用情境以快速选择环境、打开页面、登录和重复访问为主，不需要团队协作或公开分发。

## Product Purpose

提供一个轻量的多环境浏览器：每个环境拥有独立的 WebKit 网站数据、固定 UA 和 App 内凭据。成功标准是环境切换清晰、登录状态不串用、常用页面进入迅速，并能由 Windows 编写后通过 GitHub Actions 稳定产出未签名 IPA。

## Positioning

用 iOS 原生能力提供少而可靠的浏览器环境隔离，不声称匿名，也不把复杂网络或指纹功能塞进日常登录流程。

## Brand Personality

私密、明确、沉稳。界面应让当前使用的是哪个环境一目了然，同时保持 iOS 工具应有的熟悉感和低操作负担。

## Anti-references

不做营销页式大标题、霓虹安全主题、装饰性玻璃拟态、卡片堆叠或桌面浏览器式复杂工具栏。诊断信息不能压过“选环境并打开页面”的主要任务。

## Design Principles

- 当前环境始终明确，避免在错误身份下继续浏览。
- 常用操作走最短路径，首次创建环境后即可打开主页。
- 隔离状态用事实和诊断结果表达，不用夸大的安全文案。
- 危险操作可恢复时优先可恢复；不可恢复时明确确认范围。
- 采用系统组件和系统行为，让界面在不同尺寸与辅助功能设置下保持可信。

## Accessibility & Inclusion

遵循 iOS Human Interface Guidelines：支持 Dynamic Type、VoiceOver、深浅色和提高对比度；所有触控目标至少 44×44 pt；颜色不作为唯一状态提示；减少动态效果时不使用额外位移动画。
