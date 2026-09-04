<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md"><strong>繁體中文</strong></a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a>
</p>

# UsageDock

UsageDock 是一款輕量級 macOS 螢幕邊緣用量列，可快速查看 AI 服務的使用量與重置時間，不必打開完整儀表板也能持續掌握配額狀態。

## 動態示範

<a href="https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview">
  <img src="docs/images/usagedock-rail.png" alt="觀看 UsageDock 液態拖曳動態示範" width="763">
</a>

**▶ [觀看 UsageDock 動態示範](https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview)**

## 預覽

### 螢幕邊緣列

<img src="docs/images/usagedock-rail.png" alt="顯示 AI 使用量的 UsageDock 螢幕邊緣列" width="763">

### 設定

<img src="docs/images/usagedock-settings.png" alt="UsageDock 設定視窗" width="900">

## 主要功能

- 在精簡的螢幕邊緣列中顯示不同服務商與帳號的使用量。
- 最多可選擇 3 個顯示帳號，並可獨立設定選單列顯示帳號。
- 支援環形進度、百分比、重置時間、服務商/帳號顏色與配額來源設定。
- 支援左右螢幕邊緣、版面、邊框、材質、水滴與彈性液態拖曳效果。
- 在 macOS 選單列提供精簡狀態項目與彈出面板。
- 外觀、位置、顯示帳號與選單列設定都可在重新啟動後保留。

## 帳號政策

UsageDock **僅支援登入帳號**。

- Claude、Codex、Antigravity 與 Kimi 可透過支援的已驗證登入/工作階段註冊。
- Cursor 與 Grok 在具備經驗證的登入方式與即時用量整合之前暫不可用。
- 未由支援的已驗證登入提供的帳號不會加入有效帳號集合。

## 系統需求

- macOS 14 或更新版本
- 建議 Xcode 16+

## 建置

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

## 註冊帳號

開啟 **Settings → Accounts**，使用對應服務商的登入操作。UsageDock 只會註冊支援的已驗證登入/工作階段來源。

## 專案結構

- `UsageDock/Domain` — 用量模型、彙整與邊緣列動態執行邏輯
- `UsageDock/Providers` — 服務商介接與即時用量整合
- `UsageDock/Storage` — 設定與帳號狀態持久化
- `UsageDock/UI` — 邊緣列與設定 UI
- `UsageDock/Window` — AppKit 面板/視窗整合
- `UsageDockTests` — 單元測試與行為測試

更多實作說明請參閱 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。
