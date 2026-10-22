<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md"><strong>简体中文</strong></a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a>
</p>

# UsageDock

UsageDock 是一款轻量级 macOS 屏幕边缘用量栏，可快速查看 AI 服务的使用量与重置时间，无需打开完整仪表盘也能持续掌握配额状态。

## 动态演示

<a href="https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview">
  <img src="docs/images/usagedock-rail.png" alt="观看 UsageDock 液态拖拽动态演示" width="763">
</a>

**▶ [观看 UsageDock 动态演示](https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview)**

## 预览

### 屏幕边缘栏

<img src="docs/images/usagedock-rail.png" alt="显示 AI 使用量的 UsageDock 屏幕边缘栏" width="763">

### 设置

<img src="docs/images/usagedock-settings.png" alt="UsageDock 设置窗口" width="900">

## 主要功能

- 在紧凑的屏幕边缘栏中显示不同服务商与账号的使用量。
- 最多可选择 3 个显示账号，并可独立配置菜单栏显示账号。
- 支持环形进度、百分比、重置时间、服务商/账号颜色与配额来源配置。
- 支持左右屏幕边缘、布局、边框、材质、水滴以及弹性液态拖拽效果。
- 在 macOS 菜单栏中提供紧凑状态项与弹出面板。
- 外观、位置、显示账号与菜单栏设置均可跨重启保存。

## 点击打开目标

在 **Settings → Data → Provider Order, Colors & Click Targets** 中，为每个服务商选择 **App（默认）** 或 **Link**。通过 **Choose App…** 选择正在运行的应用，或使用从 `/Applications` 开始的 Finder 文件选择器指定 `.app`。设置显示应用名称和图标，并在重启后保留。边缘栏、账号菜单和菜单栏账号行使用同一设置。

已安装时的默认应用为 Claude.app、Codex 对应的 ChatGPT.app、Antigravity.app、Kimi Code.app、Cursor.app 和 Grok 对应的 Grok Bot.app。应用缺失或启动失败时会打开可编辑的备用 URL，并在设置和工具提示中显示状态。账号 URL 优先；空白或无效的 URL 会回退到有效的服务商 URL。**Use Default App / Use Default URL** 可恢复默认值。应用选择不改变仅限登录账号的策略。

## 按账号选择边缘栏配额

在 **Settings → Accounts → Rail display override** 中，可分别为 **Percent、Outer、Inner、Timer** 选择配额。Antigravity 可单独选择 Gemini Models 和 Claude and GPT models 的 5h／1w 配额，其他服务商也可按配额名称选择。**Global、Auto、5h、1w** 和进度环的 **None** 保持原有行为，默认值不变。选择按账号保存，重启和刷新配额后仍然保留。

配额行名称可换行显示，工具提示中也可查看完整名称。所选配额被隐藏或暂时不可用时，将不显示数值，直到它重新启用并恢复可用；不会自动切换到其他模型的配额。

## 账号策略

UsageDock **仅支持登录账号**。

- Claude、Codex、Antigravity、Kimi 和 Grok 可通过受支持的已认证登录/会话注册。
- Cursor 在拥有经过验证的登录方式及实时用量集成之前暂不可用。
- 未由受支持的认证登录提供的账号不会进入活动账号集合。

Grok 有两种登录。**Sign in on grok.com** 会在应用内窗口打开 `https://grok.com/?_s=usage`。该会话留在按账号隔离的网页存储中，是 grok.com Settings → Usage 上每周用量百分比和重置时间的来源。**Use Current Login** 与 **Login New Profile** 仍使用 `grok login`。如果没有网页会话、会话已过期，或响应无法解码，UsageDock 会显示 CLI 账单读数，并说明需要重新登录网页。无法解码的网页响应不会被当成 0%。Cookie 和令牌不会复制到 UsageDock 的设置中。Copy diagnostics 只复制解码出的字段路径。

## 系统要求

- macOS 14 或更高版本
- 推荐 Xcode 16+

## 构建

Release:

```bash
xcodebuild \
  -project UsageDock.xcodeproj \
  -scheme UsageDock \
  -configuration Release \
  -derivedDataPath DerivedDataRelease \
  build
```

Debug:

```bash
xcodebuild \
  -project UsageDock.xcodeproj \
  -scheme UsageDock \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build
```

## 注册账号

打开 **Settings → Accounts**，使用对应服务商的登录操作。UsageDock 只会注册受支持的已认证登录/会话来源。

## 项目结构

- `UsageDock/Domain` — 用量模型、聚合与边缘栏运动运行时
- `UsageDock/Providers` — 服务商适配器与实时用量集成
- `UsageDock/Storage` — 设置与账号状态持久化
- `UsageDock/UI` — 边缘栏与设置 UI
- `UsageDock/Window` — AppKit 面板/窗口集成
- `UsageDockTests` — 单元测试与行为测试

更多实现说明请参阅 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。
