<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ko.md"><strong>한국어</strong></a> ·
  <a href="README.es.md">Español</a>
</p>

# UsageDock

UsageDock은 AI 서비스의 사용량과 리셋 시간을 한눈에 확인할 수 있는 가벼운 macOS 화면 가장자리 레일입니다. 전체 대시보드를 열지 않아도 필요한 할당량 상태를 계속 확인할 수 있습니다.

## 동작 데모

<a href="https://drive.google.com/file/d/1hCO0oAMye-B4IhnjYHwatP7F_iUe9UIo/preview">
  <img src="docs/images/usagedock-rail.png" alt="UsageDock의 액체 드래그 동작 데모 보기" width="763">
</a>

**▶ [UsageDock 동작 데모 보기](https://drive.google.com/file/d/1hCO0oAMye-B4IhnjYHwatP7F_iUe9UIo/preview)**

## 미리보기

### 화면 가장자리 레일

<img src="docs/images/usagedock-rail.png" alt="AI 사용량을 표시하는 UsageDock 화면 가장자리 레일" width="763">

### 설정

<img src="docs/images/usagedock-settings.png" alt="UsageDock 설정 창" width="900">

## 주요 기능

- 서비스 제공자/계정별 사용량을 컴팩트한 화면 가장자리 레일에 표시합니다.
- 최대 3개의 표시 계정을 선택할 수 있으며 메뉴 막대의 표시 계정은 별도로 설정할 수 있습니다.
- 링, 백분율, 리셋 시간, 제공자/계정 색상 및 표시할 할당량 소스를 설정할 수 있습니다.
- 좌/우 화면 가장자리 배치, 레이아웃, 테두리, 재질, 물방울, 탄성 액체 드래그 효과를 지원합니다.
- macOS 메뉴 막대에 컴팩트한 상태 항목과 팝오버를 제공합니다.
- 외형, 위치, 표시 계정 및 메뉴 막대 설정이 재시작 후에도 유지됩니다.

## 계정 정책

UsageDock은 **로그인 전용**입니다.

- Claude, Codex, Antigravity, Kimi는 지원되는 인증 로그인/세션을 통해 등록할 수 있습니다.
- Cursor와 Grok은 검증된 로그인 경로와 실시간 사용량 연동이 제공될 때까지 사용할 수 없습니다.
- 지원되는 인증 로그인에 연결되지 않은 계정은 활성 계정 집합에서 제외됩니다.

## 요구 사항

- macOS 14 이상
- Xcode 16+ 권장

## 빌드

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

## 계정 등록

**Settings → Accounts**를 열고 각 제공자의 로그인 기능을 사용하세요. UsageDock은 지원되는 인증 로그인/세션 소스만 등록합니다.

## 프로젝트 구조

- `UsageDock/Domain` — 사용량 모델, 집계 및 레일 모션 런타임
- `UsageDock/Providers` — 제공자 어댑터 및 실시간 사용량 연동
- `UsageDock/Storage` — 설정 및 계정 상태 저장
- `UsageDock/UI` — 레일과 설정 UI
- `UsageDock/Window` — AppKit 패널/창 통합
- `UsageDockTests` — 단위 및 동작 테스트

추가 구현 정보는 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)를 참고하세요.
