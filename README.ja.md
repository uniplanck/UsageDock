<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ja.md"><strong>日本語</strong></a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a>
</p>

# UsageDock

UsageDockは、AIサービスの使用量とリセット時刻をひと目で確認するための軽量macOSエッジレールです。大きなダッシュボードを開かなくても、必要なクォータ情報を常時見える位置に置けます。

## 動作デモ

<a href="https://drive.google.com/file/d/1hCO0oAMye-B4IhnjYHwatP7F_iUe9UIo/preview">
  <img src="docs/images/usagedock-rail.png" alt="UsageDockの液体ドラッグ動作デモを見る" width="763">
</a>

**▶ [UsageDockの動作デモを見る](https://drive.google.com/file/d/1hCO0oAMye-B4IhnjYHwatP7F_iUe9UIo/preview)**

## プレビュー

### エッジレール

<img src="docs/images/usagedock-rail.png" alt="AI使用量を表示するUsageDockのエッジレール" width="763">

### 設定

<img src="docs/images/usagedock-settings.png" alt="UsageDockの設定画面" width="900">

## 主な機能

- プロバイダー／アカウントごとの使用量をコンパクトなエッジレールに表示します。
- 最大3件の表示アカウントを選択でき、メニューバー側の表示対象は独立して設定できます。
- リング、パーセンテージ、リセット時刻、プロバイダー／アカウント色、表示するクォータ種別を設定できます。
- 左右エッジ配置、レイアウト、枠線、マテリアル、水滴、弾性的な液体ドラッグ表現に対応します。
- macOSメニューバーにコンパクトなステータス表示とポップオーバーを提供します。
- 外観、配置、表示アカウント、メニューバー設定を再起動後も保持します。

## アカウントポリシー

UsageDockは**ログインオンリー**です。

- Claude、Codex、Antigravity、Kimiは、対応する認証済みログイン／セッションから登録できます。
- CursorとGrokは、検証済みのログイン経路とライブ使用量連携が実装されるまで利用できません。
- 対応する認証済みログインに紐づかないアカウントは、アクティブなアカウント集合から除外されます。

## 必要環境

- macOS 14以降
- Xcode 16以降を推奨

## ビルド

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

## アカウント登録

**Settings → Accounts**を開き、各プロバイダーのログイン操作を使用してください。UsageDockが登録するのは、対応する認証済みログイン／セッションのみです。

## プロジェクト構成

- `UsageDock/Domain` — 使用量モデル、集計、レール動作ランタイム
- `UsageDock/Providers` — プロバイダーアダプター、ライブ使用量連携
- `UsageDock/Storage` — 設定とアカウント状態の永続化
- `UsageDock/UI` — レールと設定UI
- `UsageDock/Window` — AppKitパネル／ウィンドウ統合
- `UsageDockTests` — 単体・挙動テスト

追加の実装情報は[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)を参照してください。
