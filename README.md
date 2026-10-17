# 环境浏览器

一个仅面向个人使用的 iOS 26 多环境浏览器。每个环境使用独立的持久化 WebKit data store、独立 User-Agent 配置和按 Profile 分区的 App 内 Keychain 凭据。

## 当前能力

- 启动后先选择或创建浏览器环境。
- 环境间隔离 Cookie、Web Storage、缓存等 WebKit 网站数据。
- 每个环境独立保存主页、User-Agent 和标识颜色。
- 环境可在编辑页设置分组，列表按分组展示。
- 编辑环境时可保存自动填充账号密码（由应用自身凭据库管理，不调用 iOS 系统自动填充），也可随机生成常见 UA。
- 首页会在后台读取已登录网页中的余额元素，并显示在环境名称后。
- HTTPS 站点可按精确 origin 保存并主动填充凭据。
- 凭据展示前使用 Face ID 或设备密码验证。
- 可单独清理或永久删除某个环境的网站数据。
- 诊断页显示 data store、Cookie 数量，并可按需查询当前公网 IP。
- 可用密码加密导出环境元数据和凭据，并导入为新的环境。
- 可选配置 SOCKS5 代理：支持 SOCKS URL/订阅链接导入、批量验证和按延迟排名；环境保存当前排名编号，代理列表更新后按新内容使用同一编号。
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
3. 构建成功后，到仓库 [Releases](https://github.com/ClaraCora/Cweb/releases) 下载当次构建的 `ProfileBrowser-unsigned-<commit>.ipa`、`SHA256SUMS.txt` 和 `BUILD-INFO.txt`。Actions 运行摘要也会显示下载链接。
4. 用 `SHA256SUMS.txt` 校验 IPA。

每次成功构建会发布一个预发布版本，标签格式为 `ios-unsigned-<构建编号>-<重跑次数>`，绑定本次构建的提交。重跑会发布新的版本，构建产物保存在 GitHub Releases，不占用 Actions artifact 存储配额。

未签名 IPA 无法直接安装到普通 iPhone；签名和安装由使用者在 CI 外自行处理。

## 本地限制

Windows 没有 Apple SDK，无法完整编译 SwiftUI/WebKit 代码或运行 iOS Simulator。项目的真实编译与测试关卡是 GitHub Actions 的 macOS 26 runner。

完整架构、边界与验收标准见 [方案.md](方案.md)。

## 备份与恢复

新备份导出为 `ProfileBrowser-backup.json`，账号密码仍以加密内容保存。导入也支持旧版无扩展名备份，无需改名：选择文件后，在备份页输入原备份密码，再点“解锁并导入”。密码错误可以重试；取消导入或导入成功后会清除本次选择和密码。导入会新增环境，不覆盖已有环境，网站 Cookie 和缓存不在备份内。

备份测试覆盖 JSON 文件读写、固定 v1 备份兼容、密码错误重试、源文件删除后的缓存读取，以及空文件、目录和损坏格式。文件选择器还需要在 iOS 26 真机确认：

1. 导出新备份，确认后缀为 `.json`，再选择并恢复环境及凭据。
2. 直接选择旧无扩展名备份，确认返回备份页并显示文件名和密码输入框。
3. 输入错误密码后改用正确密码；取消后重选；连续导入，确认原有环境仍保留。
4. 选择无效文件时确认出现格式提示；取消文件选择器时确认没有错误提示。

## UA / 环境检测页

根目录的 `ua-diagnostics.php` 是一个可独立部署的 PHP 检测页。将它放到 PHP 网站后直接访问，即可对比服务端收到的 User-Agent、请求头、浏览器参数和能力信息；页面会遮盖 Cookie、Authorization 等敏感请求头，浏览器端数据只在当前页面生成。建议只在自己的站点使用，并按需限制访问权限。
