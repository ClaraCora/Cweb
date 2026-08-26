# 环境浏览器

一个仅面向个人使用的 iOS 26 多环境浏览器。每个环境使用独立的持久化 WebKit data store、独立 User-Agent 配置和按 Profile 分区的 App 内 Keychain 凭据。

## 当前能力

- 启动后先选择或创建浏览器环境。
- 环境间隔离 Cookie、Web Storage、缓存等 WebKit 网站数据。
- 每个环境独立保存主页、User-Agent 和标识颜色。
- HTTPS 站点可按精确 origin 保存并主动填充凭据。
- 凭据展示前使用 Face ID 或设备密码验证。
- 可单独清理或永久删除某个环境的网站数据。
- 诊断页显示 data store、Cookie 数量，并可按需查询当前公网 IP。
- 可用密码加密导出环境元数据和凭据，并导入为新的环境。
- GitHub Actions 只产出未签名 IPA，不使用任何 Apple 签名材料。

## 工程结构

工程使用 XcodeGen。App 业务源码全部为 Swift；`project.yml`、Info.plist、Asset Catalog 和 GitHub Actions YAML 是 iOS 构建所需配置。

```text
ProfileBrowser/       App 源码与资源
ProfileBrowserTests/  Swift Testing 测试
project.yml           XcodeGen 工程描述
.github/workflows/    未签名 IPA 构建
```

## GitHub 构建

1. 将目录放入 GitHub 仓库并使用 `main` 分支。
2. 打开 Actions，运行 `Build unsigned iOS IPA`，或向 `main` 推送相关文件。
3. 构建成功后下载 `ProfileBrowser-unsigned-<commit>` artifact。
4. 用 `SHA256SUMS.txt` 校验 IPA。

未签名 IPA 无法直接安装到普通 iPhone；签名和安装由使用者在 CI 外自行处理。

## 本地限制

Windows 没有 Apple SDK，无法完整编译 SwiftUI/WebKit 代码或运行 iOS Simulator。项目的真实编译与测试关卡是 GitHub Actions 的 macOS 26 runner。

完整架构、边界与验收标准见 [方案.md](方案.md)。
