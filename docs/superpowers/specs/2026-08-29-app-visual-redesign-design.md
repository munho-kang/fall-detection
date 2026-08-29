# 앱 디자인 개편 설계 — 컬러 히어로

2026-08-29. 보호자 앱(`app/`)의 시각 디자인을 "밝고 현대적인 컬러 히어로" 스타일로 전면 교체한다.
기능·화면 흐름·API·폴링·알림 로직은 바꾸지 않는다. 브레인스토밍에서 시안 3개(화이트&블루 ·
컬러 히어로 · 소프트 파스텔) 중 **컬러 히어로**를 골랐고, 그 규칙을 나머지 화면에 적용한 시안
4장(사고 발생 창 · 알림 상세 · 방 관리 · 시작 화면)까지 승인받았다. 이 문서는 그 결정 기록이며
구현 계획의 입력이 된다. 시안 원본은 `.superpowers/brainstorm/2106-1787977035/content/`에 있다
(git 추적 밖).

## 1. 범위와 결정

포함한다.

1. **디자인 토큰 교체** — `lib/app_theme.dart`의 팔레트·글꼴·모서리·그림자·컴포넌트 테마를 새로 쓴다.
2. **공통 위젯 신설** — `lib/widgets.dart` 하나에 `AppCard` · `HeroCard` · `StatusChip` · `FallTile` ·
   `ActionButton`을 둔다. 화면마다 복붙돼 있던 카드·타일·버튼·상태 문구 로직을 한 곳으로 모은다.
3. **12개 화면 전부** 새 스타일로 다시 그린다. 위젯 트리는 바뀌지만 화면이 하는 일은 같다.
4. **홈 재구성** — 맨 위에 "지금 안전한지"를 색으로 말하는 히어로 카드. '방 추가' 배너는 '내 방' 카드로.
5. **Pretendard 글꼴 번들** — iPhone · 안드로이드 · 웹에서 같은 글꼴로 보이게 한다.
6. **테스트** — 기존 테스트가 찾는 문구·위젯 종류는 유지한다. 팔레트 테스트는 새 값으로 갱신하고,
   공통 위젯 테스트 파일 하나를 더한다.
7. **문서** — README 보호자 앱 절과 `docs/screenshots/01~14`를 새 화면으로 갱신한다.

범위 밖.

- **기능 변경** — 알림 확인·삭제·전화·119·폴링·인증·설정 저장 로직은 한 줄도 바꾸지 않는다.
- **다크모드** — 없다(e734e9a에서 삭제). 라이트 하나뿐인 구조를 유지한다.
- **새 화면 · 새 패키지** — 없다. 글꼴은 의존성이 아니라 자산(assets)이다.
- **감지 페이지(`web/`) · 백엔드** — 손대지 않는다.
- **탭 화면의 뒤로 가기 화살표** — 브레인스토밍 때 스크린샷에서 발견했으나 이미 82d2a24에서
  고쳐져 있다(로그인·회원가입이 `pushAndRemoveUntil`로 스택을 비움, `login_test.dart`가 보장).
  스크린샷이 낡았을 뿐이라 이번 갱신으로 해소된다.

### 결정 1 — 상태를 색으로 말하는 히어로 카드

보호자가 앱을 여는 이유는 "지금 괜찮은가"다. 홈 맨 위 카드 하나가 색과 한 문장으로 답한다.

| 상태 | 톤 | 큰 글씨 | 작은 글씨 | 버튼 |
|------|----|---------|-----------|------|
| 미확인 낙상 N건 | 빨강 | `미확인 낙상 N건` | `{방 이름} {방 번호} · {월일 시:분}` (최신 1건) | 흰 버튼 `확인하기` → 최신 미확인 건의 상세 화면 |
| 0건 | 초록 | `지금은 안전해요` | `미확인 알림 0건 · 방 N개 연결됨` | 없음 |
| 서버 연결 끊김 | 회색 | `서버와 연결이 끊겼습니다` | `연결되면 자동으로 다시 확인해요` | 없음 |
| 첫 로딩 중 | 회색 | `불러오는 중…` | 없음 | 없음 |

우선순위는 표의 순서다 — 연결이 끊겨도 이미 받아 둔 미확인 건이 있으면 빨강이 이긴다(보호자가
놓치면 안 되는 쪽). 홈의 기존 빨간 연결 오류 배너는 회색 히어로가 대신하므로 없앤다. 알림 목록
화면의 오류 배너는 그대로 둔다(그 화면엔 히어로가 없다).

### 결정 2 — '방 추가' 배너는 '내 방' 카드로

지금은 방이 있어도 "방을 등록해 두세요" 배너가 홈 맨 위를 차지한다. 새 홈에서는 히어로 아래
'내 방' 카드가 등록된 방을 칩(`1 거실`, `2 침실` …)으로 보여주고, 오른쪽 위 `+ 방 추가` 글자
버튼과 카드 전체 탭이 방 관리 탭으로 보낸다. 방이 없으면 칩 자리에 `아직 등록한 방이 없어요`.

### 결정 3 — 홈 목록은 '최근 알림' 하나

지금은 '확인하지 않은 알림'(첫 1건)과 '최근 확인한 알림' 두 묶음이다. 미확인은 히어로가 맡으므로
목록은 `최근 알림` 하나로 합치고, 서버가 준 최신순 그대로 전부 보여준다(미확인 건도 목록에
있다 — 히어로는 요약, 목록은 이력). 비어 있으면 카드 안에 `아직 감지된 낙상이 없어요.`

### 결정 4 — 공통 위젯으로 중복을 걷어낸다

같은 코드가 세 군데씩 살고 있어 디자인을 바꾸면 세 번 고쳐야 한다. 한 번만 고치도록 모은다.

- **상태 문구 우선순위**(`119 신고됨` > `괜찮다고 말함` > `확인함`/`미확인`)가 `home.dart`와
  `fall_list.dart`에 복사돼 있다 → `statusLabel(event)` 함수 하나 + 그것을 그리는 `StatusChip`.
- **알림 타일**이 두 화면에 복사돼 있다 → `FallTile`.
- **동작 버튼**은 `fall_detail.dart`의 `_actionButton`을 `fall_alert_dialog.dart`가 "미러링한다"는
  주석과 함께 복사해 쓴다 → `ActionButton` 하나(primary · outlined · emergency · destructive).
- **`월 일 시:분` 포맷**이 세 파일에 있다 → `fmtShort(DateTime)`.
- **흰 카드**와 **그라데이션 카드**는 새 규칙이라 처음부터 `AppCard` · `HeroCard`로 만든다.

### 결정 5 — Pretendard 정적 3종을 번들한다

Regular(400) · SemiBold(600) · Bold(700), `orioncactus/pretendard` v1.3.9의 OTF, OFL 라이선스
(LICENSE 파일을 같이 둔다). 합쳐서 약 4.7 MB. 가변 글꼴(Variable) 한 파일 안은 택하지 않았다 —
Flutter는 `fontWeight`를 파일 단위로 고르므로 가변 글꼴 하나로는 굵기 매핑이 보장되지 않는다.
ExtraBold(800)는 번들하지 않고 제목은 700을 쓴다(시안의 800 자리).

### 결정 6 — 창(dialog)은 종류를 유지하고 내용만 새로 그린다

- **사고 발생 창**은 `Dialog`로 바꾼다. 안은 빨간 `HeroCard`(작은 `낙상 감지` 줄 + `사고 발생` +
  `지금 바로 확인이 필요해요`) → 연회색 정보 상자(방 이름 · 방 번호 · 발생 시각, 값 형식은 지금과 같다)
  → `ActionButton` 셋(전화 outlined · 119 emergency · 확인 primary)과 안내문 둘. `PopScope(canPop: false)`
  와 "확인 버튼이 유일한 출구" 계약은 그대로다.
- **방 추가/수정 · 프로필 항목 수정 · 삭제/탈퇴 확인 창**은 `AlertDialog`를 유지한다
  (`edit_dialog_test.dart`가 `find.byType(AlertDialog)`로 찾는다). 모양은 `DialogTheme`과
  `InputDecorationTheme`이 바꾼다. 방 입력칸에는 힌트 `방 이름` · `방 번호`를 넣는다(지금은 빈 밑줄 둘).
  삭제·탈퇴 버튼은 연한 붉은 배경(destructive) 색으로.

### 결정 7 — 기존 테스트가 찾는 것은 그대로 둔다

바꾸면 테스트가 깨지는 것들. 구현할 때 이 표를 옆에 둔다.

| 테스트 | 유지할 것 |
|--------|-----------|
| `splash_test` | 텍스트 `낙상 알림` · `프라이버시 보존형 낙상 감지`, 아이콘 `Icons.shield_outlined`, 셋 다 가로 중앙 |
| `login_test` | 시작 화면에 `로그인` 텍스트는 버튼 하나뿐, 로그인·가입 버튼은 `FilledButton`, `계정이 없나요? 회원가입`, `가입하기`, 입력칸 순서(아이디·비밀번호·확인) |
| `fall_alert_dialog_test` · `main_shell_alert_test` | `사고 발생` · `확인` · 방 이름 단독 텍스트(`안방`) · `2번` · `7월 28일 04:35` 형식 · `돌봄 대상자에게 전화` · `119 긴급 신고` · `프로필에서 전화번호를 등록하면 켜집니다.` · `응답이 없어 119에 자동 신고되었습니다`. 창이 떠 있는 동안 홈에 `확인`·`사고 발생`·`N번`과 같은 단독 텍스트가 있으면 안 된다 |
| `fall_detail_test` | `음성 확인` · `낙상자가 괜찮다고 말했습니다 (yyyy.MM.dd HH:mm)` · 119 안내문 |
| `fall_list_test` | `안방 1`(roomLabel) · `미확인` · `괜찮다고 말함` · `119 신고됨` |
| `edit_dialog_test` | `AlertDialog` 타입, `Icons.edit_outlined`, `방 추가` · `방 수정` · `저장` · `취소` · `닉네임 변경`, `TextField` 순서 |
| `app_theme_test` | **갱신한다** — 새 팔레트 값과 `fontFamily == 'Pretendard'`를 단언 |

### 결정 8 — 스크린샷을 새로 찍는다

`docs/screenshots/01~14`를 iOS 시뮬레이터에서 새 화면으로 다시 캡처한다(`running-fall-guardian`
스킬의 캡처 절차). 홈·알림·방 화면은 백엔드를 띄우고 시드 데이터로 찍는다. `21~24`는 과거 버그
재현 기록이라 그대로 둔다.

## 2. 디자인 토큰 (`AppColors` · 상수)

색.

| 이름 | 값 | 쓰임 |
|------|----|------|
| `bg` | `#F7F8FA` | 화면 바탕 |
| `card` | `#FFFFFF` | 카드 · 상단 바 아이콘 배경 · 하단 탭 |
| `text` | `#191F28` | 본문 · 제목 |
| `textSub` | `#6B7684` | 보조 글씨 · 섹션 제목 |
| `textMuted` | `#8B95A1` | 힌트 · 비활성 탭 · 시각 |
| `hairline` | `#F2F4F6` | 구분선 · 입력칸 배경 · 정보 상자 배경 |
| `border` | `#E5E8EB` | outlined 버튼 테두리 · 방 추가 칸 테두리 |
| `primary` | `#0E9F6E` | 포인트 · 주 버튼 · 활성 탭 · 안전 히어로 끝색 |
| `primaryLight` | `#14B98A` | 안전 히어로 시작색 |
| `primaryTint` | `#E3F6EE` | 초록 칩 배경 · 방 번호 동그라미 · 아바타 |
| `onPrimaryTint` | `#0A7A55` | 초록 칩 글씨 |
| `danger` | `#E5323F` | 긴급 버튼 · 빨간 칩 글씨 · 배지 · 긴급 히어로 끝색 |
| `dangerLight` | `#F25A66` | 긴급 히어로 시작색 |
| `dangerTint` | `#FDECEE` | 빨간 칩 배경 · 경고 배너 · destructive 버튼 배경 |
| `dangerDeep` | `#C9353F` | destructive 버튼 글씨 · 경고 배너 글씨 · 탈퇴 글씨 |
| `mutedHero` | `#6B7684` → `#4E5968` | 회색 히어로 그라데이션 |
| `shadow` | `#000000` 5% | 카드 그림자: blur 10, offset (0, 2) |

글꼴 — `Pretendard` 400 / 600 / 700. 크기 배율(`TextScale` 작게 0.9 · 보통 1.0 · 크게 1.15)은
그대로 `textTheme.apply(fontSizeFactor:)`로 건다.

| 역할 | 크기 / 굵기 |
|------|-------------|
| 화면 제목(상단 바) | 22 / 700 |
| 히어로 큰 글씨 | 24 / 700 (사고 발생 창·상세 22) |
| 섹션 제목 · 타일 제목 · 버튼 | 17 / 700 |
| 본문 · 목록 행 | 17 / 400 |
| 보조 · 값 | 15 / 400 (값은 600) |
| 칩 · 탭 라벨 | 13 / 700 |

모양·간격.

- 모서리: 카드 18 · 히어로 22 · 버튼 14 · 창 24 · 입력칸 14 · 칩 999 · 정보 상자 14
- 버튼 높이 52(시작 화면 56), 입력칸 세로 패딩 18
- 화면 좌우 패딩 20, 카드 안 패딩 16(히어로 20), 요소 간격 12 · 섹션 간격 24
- 히어로 장식: 오른쪽 위 지름 120 흰 12% 원 + 오른쪽 아래 지름 90 흰 8% 원, `clipBehavior: antiAlias`

## 3. `ThemeData` 매핑 (`buildAppTheme({required TextScale scale})` 시그니처 유지)

`ColorScheme.fromSeed(seedColor: primary)` 위에 덮어쓴다: `primary`→primary, `onPrimary`→white,
`primaryContainer`→primaryTint, `onPrimaryContainer`→onPrimaryTint, `surface`→bg,
`surfaceContainer`·`surfaceContainerHigh`→card, `onSurface`→text, `onSurfaceVariant`→textSub,
`outline`→border, `outlineVariant`→hairline, `error`→danger, `errorContainer`→dangerTint,
`onErrorContainer`→dangerDeep.

컴포넌트 테마.

- `fontFamily: 'Pretendard'`, `scaffoldBackgroundColor: bg`
- `appBarTheme` — 배경 bg, 글씨·아이콘 text, elevation 0, `titleTextStyle` 22/700, 왼쪽 정렬
- `filledButtonTheme` — 배경 primary, 글씨 white, `minimumSize: Size.fromHeight(52)`, 모서리 14, 17/700,
  비활성 배경 text 12% · 글씨 text 38%
- `outlinedButtonTheme` — 배경 card, 글씨 text, 테두리 border, 같은 크기·모서리·글씨
- `textButtonTheme` — 글씨 primary, 15/600
- `inputDecorationTheme` — `filled`, 배경 hairline, 테두리 없음(모서리 14), 포커스 테두리 primary 1.5,
  힌트 textMuted 17, 패딩 가로 16 세로 18
- `dialogTheme` — 배경 card, 모서리 24, 제목 20/700 text, 본문 15 textSub
- `navigationBarTheme` — 배경 card, `indicatorColor` 투명, 높이 72, elevation 0, 아이콘·라벨 선택 primary /
  비선택 textMuted, 라벨 13/700, 위에 hairline 1px 선(셸에서 `Container` 테두리로)
- `dividerTheme` — hairline, 두께 1, 공간 1
- `badgeTheme` — 배경 danger, 글씨 white
- `snackBarTheme` — 배경 text, 글씨 white, floating, 모서리 12
- `progressIndicatorTheme` — primary

## 4. 공통 위젯 (`lib/widgets.dart`)

```dart
/// 흰 카드 — 배경 card, 모서리 18, 그림자. onTap이 있으면 잉크 효과.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
}

enum HeroTone { safe, alert, muted }

/// 그라데이션 카드 — 톤별 색, 장식 원 둘, 안의 글씨는 기본 흰색.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.tone, required this.child, this.padding = const EdgeInsets.all(20)});
}

/// 상태 문구 우선순위 — '119 신고됨' > '괜찮다고 말함' > '확인함' | '미확인'
String statusLabel(FallEvent e);

/// 상태 칩 — 문구별 배경/글씨: 119 신고됨·미확인 = dangerTint/danger,
/// 괜찮다고 말함 = primaryTint/onPrimaryTint, 확인함 = hairline/textSub
class StatusChip extends StatelessWidget { const StatusChip({super.key, required this.event}); }

/// '8월 4일 21:07' — 홈 · 목록 · 사고 발생 창 공용
String fmtShort(DateTime t);

/// 알림 한 줄 — 제목 roomLabel 17/700, 아래 fmtShort 15 textSub, 오른쪽 StatusChip
class FallTile extends StatelessWidget { const FallTile({super.key, required this.event, required this.onTap}); }

enum ActionKind { primary, outlined, emergency, destructive }

/// 높이 52 · 모서리 14 · 17/700. onPressed가 null이면 비활성(배경 text 12% · 글씨 38%,
/// destructive는 dangerTint 40% · dangerDeep 38%).
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.kind, this.icon, required this.onPressed});
}
```

`primary`·`emergency`·`destructive`는 `FilledButton`, `outlined`는 `OutlinedButton`이다
(`login_test`가 `FilledButton`으로 찾는 관례를 지킨다).

## 5. 화면별 설계

공통: 탭 화면 상단 바는 제목 + 오른쪽 종(미확인 배지) · 톱니. 밀어 올린 화면(알림 목록 · 상세 ·
설정 · 로그인 · 회원가입)은 왼쪽 뒤로 가기 + 제목. 본문은 `ListView(padding: 20, 16)`.

1. **스플래시** — 화면 전체 초록 그라데이션(primaryLight→primary, 왼쪽 위→오른쪽 아래) + 장식 원.
   가운데 `brandLogo(size: 120)`(흰 20% 배경 · 모서리 = size의 30% · `Icons.shield_outlined` 흰색, 크기 = size의 절반) ·
   `낙상 알림` 32/700 흰색 · `프라이버시 보존형 낙상 감지` 15 흰 80%. 1.2초 최소 노출과 토큰 분기는 그대로.
2. **시작** — 위 58%가 초록 그라데이션(아래 모서리 34), 안에 왼쪽 정렬로 `brandLogo(size: 72)` · `낙상 알림`
   32/700 · 소개 두 줄 15 흰 92%. 아래는 흰 바탕: `로그인` FilledButton 56 · `회원가입` OutlinedButton 56
   (글씨 primary · 테두리 primaryTint) · 맨 아래 `Icons.lock_outline` 14 + `영상은 집 밖으로 나가지 않아요`
   13 textMuted 가운데 정렬.
3. **로그인** — 상단 바는 뒤로 가기만(제목 없음). 본문: `로그인` 26/700 · `보호자 계정으로 들어가요` 15 textSub ·
   입력칸 둘(테마) · `로그인` FilledButton · `계정이 없나요? 회원가입` TextButton · 오류 15/600 danger.
4. **회원가입** — 같은 꼴. `회원가입` 26/700 · 부제 `비밀번호는 영문자, 숫자, 특수기호를 섞어 8자 이상으로
   만들어주세요.` 15 textSub(지금의 10px 안내를 부제로 승격) · 입력칸 셋 · `가입하기`.
5. **홈** — 제목 `낙상 알림`. 히어로(결정 1) → '내 방' `AppCard`(결정 2) → `최근 알림` 17/700 →
   `AppCard` 안 `FallTile` 목록(사이 hairline 구분선) 또는 빈 문구(결정 3).
6. **알림 목록** — 제목 `알림`. 오류 배너(dangerTint · dangerDeep · 모서리 14) → `AppCard` 안 `FallTile`
   목록. 비어 있으면 `아직 감지된 낙상이 없어요.` 가운데. 당겨서 새로고침 유지.
7. **알림 상세** — 제목 `알림`. 히어로: 미확인=alert, 괜찮다고 말함=safe, 그 외=muted. 안에 흰 22% 칩
   `statusLabel` · `roomLabel` 22/700 · `yyyy.MM.dd HH:mm` 13 흰 90%. 정보 `AppCard`: `발생 시각` ·
   `감지 신뢰도`(primary) · `현재 상태`(미확인 danger / 확인함 textSub) · `음성 확인`(있을 때, primary) —
   문구 형식은 지금과 같다. 버튼: `알림 확인`(primary · check) · `돌봄 대상자에게 전화`(outlined · phone) ·
   `119 긴급 신고`(emergency · warning) · 안내문 둘 · 24 띄우고 `기록 삭제`/`확인한 기록만 삭제할 수 있습니다`
   (destructive · delete_outline). 삭제 확인 창의 `삭제`는 dangerDeep 글씨.
8. **사고 발생 창** — 결정 6. `Dialog` 모서리 24, 바깥 여백 20, 안 여백 16.
9. **방 관리** — 제목 `방 관리`. 안내문 15 textSub → 2열 격자(간격 12, 정사각). 방 카드 = `AppCard`:
   번호 동그라미 32(primaryTint · primary 13/700) · 이름 17/700 · `기기 연결` 15 textSub · 아래 오른쪽
   `edit_outlined` · `delete_outline` 아이콘 버튼(textMuted). 추가 칸 = 테두리 border 1.5 · 모서리 18 ·
   `Icons.add` + `방 추가` 17/700 primary 가운데. (시안은 점선이었으나 Flutter에 내장 점선 테두리가 없어
   실선으로 간다 — `ponytail:` 주석으로 남긴다.)
10. **프로필** — 제목 `프로필`. 아바타 88 primaryTint 원 + `Icons.person` primary 44, 오른쪽 아래 카메라
    배지 30 primary(bg 색 2px 링). 이름 20/700 · 연락처 15 textSub 가운데. 묶음 셋은 `AppCard`
    (제목 15/700 textSub, 행 최소 높이 60, 라벨 17 · 값 15 textSub · chevron textMuted, 사이 hairline).
    `회원 탈퇴` 행은 글씨·아이콘 dangerDeep. 탈퇴 확인 창 `탈퇴` 버튼은 destructive.
11. **설정** — 제목 `설정`. `앱 설정` `AppCard`: `화면 크기` 행 오른쪽 세그먼트(바탕 hairline · 모서리 999 ·
    안 여백 3, 선택 칸 primaryTint 배경 + primary 13/700, 비선택 textSub 13/400) · `알림 설정` Switch.
    알림 끔 경고 배너(dangerTint · dangerDeep · 모서리 14). `지원 및 정보` `AppCard` 세 행.
12. **하단 탭(`MainShell`)** — `NavigationBar`는 테마가 그린다. 위에 hairline 1px. 목적지·아이콘·라벨은 그대로.

## 6. 파일 변경 목록

| 파일 | 변경 |
|------|------|
| `app/pubspec.yaml` | `flutter.fonts`에 Pretendard 3종 등록 |
| `app/assets/fonts/Pretendard-{Regular,SemiBold,Bold}.otf`, `LICENSE` | 새 자산 |
| `app/lib/app_theme.dart` | 토큰·테마 전면 교체(`TextScale`·`buildAppTheme` 시그니처 유지) |
| `app/lib/widgets.dart` | 신설 |
| `app/lib/screens/*.dart` 12개 + `main_shell.dart` | 새 스타일로 |
| `app/test/app_theme_test.dart` | 새 팔레트 값으로 갱신 |
| `app/test/widgets_test.dart` | 신설 — `statusLabel` 우선순위 4건, 홈 히어로 상태 3건 |
| `README.md` | 보호자 앱 절 갱신(홈 설명 · 글꼴 · 디자인 한 줄) |
| `docs/screenshots/01~14` | 재캡처 |

## 7. 검증

1. `flutter analyze` 경고 0, `flutter test` 전부 통과(기존 13파일 + 신규 1파일).
2. iOS 시뮬레이터에서 12개 화면을 직접 열어 시안과 대조 — 특히 히어로 4가지 상태, 사고 발생 창,
   화면 크기 '크게'에서 글자 잘림 없음.
3. `flutter build web --release`가 통과해 글꼴 자산이 웹 번들에 들어가는지 확인.
4. 스크린샷 재캡처 후 README 갱신, 커밋.

## 8. 구현 중 수정 (2026-08-29)

- **화면 크기 배율은 MediaQuery로 건다.** §2는 `textTheme.apply(fontSizeFactor:)`를 그대로 쓴다고
  했으나, 구현 중 새 테마 테스트가 그 방식이 애초에 동작하지 않았음을 드러냈다 — `ThemeData`의
  textTheme은 지역화 전이라 `fontSize`가 없고, 그래서 `작게`/`크게`에서 디버그 빌드는 `TextStyle.apply`의
  assert로 죽고 릴리스 빌드는 아무것도 안 커졌다. 이제 `buildAppTheme()`는 배율을 받지 않고,
  `main.dart`가 `MaterialApp.builder`에서 `applyTextScale(context, scale, child)`로 `MediaQuery.textScaler`를
  건다. 명시 `fontSize`가 있는 글자까지 전부 배율이 걸리므로 설정이 실제로 동작하게 된다.
  `app_theme_test.dart`가 세 배율의 렌더 높이를 비교해 지킨다.
- **스크린샷은 가짜 Api로 자동 촬영한다.** 결정 8은 백엔드 + 시드 데이터로 시뮬레이터에서 찍는다고
  했으나, `integration_test/screenshots_test.dart`가 `Api`를 상속한 가짜(방 3개 · 낙상 4건 · 전화번호)로
  12개 화면을 순서대로 띄우고 `takeScreenshot`으로 `docs/screenshots/NN-*.png`에 저장한다
  (`test_driver/integration_test.dart`가 파일로 쓴다). 서버·DB 없이 명령 하나로 재현된다:
  `cd app && flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart -d <시뮬레이터 UDID>`.
  Flutter 화면만 캡처되므로 옛 스크린샷과 달리 상단 상태 표시줄(시계·배터리)은 없다.
