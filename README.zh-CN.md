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

## 账号策略

UsageDock **仅支持登录账号**。

- Claude、Codex、Antigravity 和 Kimi 可通过受支持的已认证登录/会话注册。
- Cursor 与 Grok 在拥有经过验证的登录方式及实时用量集成之前暂不可用。
- 未由受支持的认证登录提供的账号不会进入活动账号集合。

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
