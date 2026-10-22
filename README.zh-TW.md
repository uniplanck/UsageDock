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

## 點擊開啟目標

在 **Settings → Data → Provider Order, Colors & Click Targets** 中，為每個服務商選擇 **App（預設）** 或 **Link**。透過 **Choose App…** 選取正在執行的應用程式，或使用從 `/Applications` 開始的 Finder 檔案選擇器指定 `.app`。設定顯示名稱與圖示，並在重新啟動後保留。邊緣列、帳號選單與選單列帳號行使用相同設定。

已安裝時的預設應用程式為 Claude.app、Codex 對應的 ChatGPT.app、Antigravity.app、Kimi Code.app、Cursor.app 與 Grok 對應的 Grok Bot.app。應用程式遺失或無法啟動時會開啟可編輯的備用 URL，並在設定與工具提示中顯示狀態。帳號 URL 優先；空白或無效的 URL 會退回有效的服務商 URL。**Use Default App / Use Default URL** 可還原預設值。選取應用程式不會改變僅限登入帳號的政策。

## 依帳號選擇邊緣列配額

在 **Settings → Accounts → Rail display override** 中，可分別為 **Percent、Outer、Inner、Timer** 選擇配額。Antigravity 可個別選擇 Gemini Models 和 Claude and GPT models 的 5h／1w 配額，其他服務商也可依配額名稱選擇。**Global、Auto、5h、1w** 和進度環的 **None** 維持原有行為，預設值不變。選擇依帳號儲存，重新啟動和更新配額後仍會保留。

配額行名稱可換行顯示，工具提示中也可查看完整名稱。所選配額被隱藏或暫時無法取得時，將不顯示數值，直到它重新啟用並恢復可用；不會自動切換到其他模型的配額。

## 帳號政策

UsageDock **僅支援登入帳號**。

- Claude、Codex、Antigravity、Kimi 與 Grok 可透過支援的已驗證登入/工作階段註冊。
- Cursor 在具備經驗證的登入方式與即時用量整合之前暫不可用。
- 未由支援的已驗證登入提供的帳號不會加入有效帳號集合。

Grok 有兩種登入。**Sign in on grok.com** 會在應用程式內視窗開啟 `https://grok.com/?_s=usage`。該工作階段留在依帳號隔離的網頁儲存中，是 grok.com Settings → Usage 上每週用量百分比和重設時間的來源。**Use Current Login** 與 **Login New Profile** 仍使用 `grok login`。如果沒有網頁工作階段、工作階段已過期，或回應無法解碼，UsageDock 會顯示 CLI 帳單讀數，並說明需要重新登入網頁。無法解碼的網頁回應不會被當成 0%。Cookie 和權杖不會複製到 UsageDock 的設定中。Copy diagnostics 只複製解碼出的欄位路徑。

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
