# 다크모드 색 정리와 낙상 발생 모달 설계

2026-07-28. 두 가지를 다룬다. 하나는 다크모드에서 배경만 밝게 남는 버그의 정리고, 다른 하나는
낙상이 감지되면 화면 한가운데 뜨는 "사고 발생" 창이다. screen_v3 새 UI 이관(b2309ce) 직후의
후속 라운드이며 브레인스토밍 결정 기록이다.

## 1. 배경

### 1-1. 다크모드

설정에서 다크모드를 켜면 카드만 어두워지고 페이지 배경은 밝은 회색으로 남는다. 어두운 카드 위에
진회색 보조 텍스트가 얹혀 "앱 설정"·"지원 및 정보"·"MVP v1.0"이 거의 안 보인다.

`app_theme.dart`는 문제가 아니다. 다크 테마의 `scaffoldBackgroundColor`(`0xFF131716`)와
`appBarTheme`은 이미 밝기별로 분기돼 있다. 원인은 화면 쪽이다. 화면들이 라이트 전용 상수
`AppColors.surface`(`0xFFF4F6F6`)를 `Scaffold`·`AppBar`의 `backgroundColor`에 직접 넣어 테마
값을 덮어쓴다. 카드만 `Theme.of(context).colorScheme.surfaceContainer`를 써서 정상적으로
어두워지고, 그래서 밝은 배경과 어두운 카드가 섞인다. 하드코딩된 `AppColors.*` 참조는 10개
파일에 145곳이고, `AppColors`를 거치지 않는 원시 색 리터럴이 12곳 더 있다(`splash.dart` 제외).

**배경만 고치면 상태가 나빠진다.** 페이지 위에 바로 놓인 텍스트가 `AppColors.onSurface`(거의
검정)를 하드코딩하고 있다. `home.dart:76`·`91`의 섹션 제목 "확인하지 않은 알림"·"최근 확인한
알림"이 카드 밖 배경 위에 있고, 배경을 어둡게 바꾸는 순간 이 글자들이 사라진다. 배경과 전경을
같이 옮겨야 한다.

실기기에서 관측한 증상이 이 구조로 전부 설명된다. 낙상 상세의 비활성 "돌봄 대상자에게 전화"
버튼은 배경을 테마에서(`surfaceContainer` → 다크 `0xFF222625`) 받고 글자색을 라이트 상수에서
받아서, 밝은 페이지 위에 놓인 어두운 버튼에 거의 안 보이는 글자가 얹힌 모양이 된다.

### 1-2. 낙상 발생 모달

지금 새 낙상을 보호자에게 알리는 경로는 OS 로컬 알림 하나뿐이다. 앱을 열어 둔 상태면 알림
배너가 스쳐 지나가고, 목록의 미확인 배지 숫자만 조용히 올라간다. 앱을 보고 있는 보호자가
가장 놓치기 쉬운 구간이다. 화면을 가로막는 창으로 확실히 알린다.

## 2. 범위와 결정

1. **다크모드는 화면 전체를 테마 색으로 전환** — 배경만 고치는 부분 수정이 아니라, 10개 화면의
   하드코딩 참조를 `Theme.of(context).colorScheme`으로 옮긴다(사용자 결정). 라이트 모드 외관은
   그대로 유지된다. `AppColors`에 다크 팔레트를 따로 두고 화면이 밝기를 읽어 고르는 안은
   제외했다 — 밝기를 읽는 헬퍼가 새로 필요한데 결국 같은 자리를 다 손대는 것은 같다.
2. **모달의 "확인"은 창만 닫는다** — 서버에 `acknowledged_at`을 기록하지 않는다(사용자 결정).
   "봤다"와 "확인 처리했다"를 분리해, 창을 닫아도 미확인 배지가 남아 나중에 놓치지 않는다.
   서버 호출이 없어 오프라인에서도 닫힌다. 확인까지 기록하는 안과, "상세 보기" 버튼을 함께 두는
   안은 제외했다.
3. **여러 건은 한 건씩 순차로** — 최신 낙상부터 하나씩 띄우고, 확인할 때마다 다음 것이 뜬다
   (사용자 결정). 모든 낙상을 빠짐없이 보게 되고 방·시각이 건별로 정확하다. 최신 1건만 띄우는
   안(이전 낙상을 모르고 지나침)과 한 창에 모아 보여주는 안(단일 건과 다중 건의 레이아웃이
   갈림)은 제외했다.
4. **로그인 중이면 어디서든 띄운다** — 홈·방 관리·프로필은 물론 설정·낙상 상세처럼 위에 쌓인
   화면도 덮는다(사용자 결정). 안전 알림이라 놓치지 않는 쪽을 택했다. 기존 대화상자 위에 겹쳐
   뜨는 것은 감수한다. 메인 탭에서만 띄우는 안과, 겹치면 뒤로 미루는 대기열 안(구현·테스트가
   복잡해짐)은 제외했다.
5. **구현은 `MainShell`이 대기열을 들고 루트 네비게이터에 `showDialog`** — 폴러가 이미 거기
   있고 `fresh` 리스트를 그대로 받는다. `MaterialApp`에 전역 `navigatorKey`를 두고 별도 프레젠터
   서비스를 만드는 안은 부르는 곳이 한 군데뿐이라 제외했다. `MainShell` body를 `Stack`으로 감싼
   오버레이 안은 위에 쌓인 화면을 덮지 못해 4번 결정과 어긋나 탈락했다.

범위 밖: 보호자 웹 화면, 알림 소리·진동 변경, 다크모드 자동/수동 전환 동작(기존 유지),
`primary` 색의 다크 변형, `splash.dart`의 브랜드 배경.

## 3. 다크모드 — `app_theme.dart`

`ColorScheme.fromSeed` 호출에서 `surface`·`surfaceContainer`·`onSurface`·`onSurfaceVariant`
넷만 `dark ? ... : ...`로 분기돼 있고 나머지는 라이트 값 하나로 고정이다. 기존 인라인 분기
스타일을 이어서 채운다.

| 색 | 라이트 (유지) | 다크 (추가) | 쓰이는 곳 |
|---|---|---|---|
| `outlineVariant` | `0xFFC0C9C6` | `0xFF3A4442` | 카드 안 구분선 |
| `primaryContainer` | `0xFFD3E0DC` | `0xFF1E4640` | 하단 네비 선택 표시, 화면 크기 선택 칩 |
| `onPrimaryContainer` | `0xFF1F3833` | `0xFFB8E7DD` | 위 칩의 글자 |
| `errorContainer` | `0xFFFBE3DD` | `0xFF4A241C` | 알림 끔 경고 배너 |
| `onErrorContainer` | `0xFFD64A2F` | `0xFFFFB4A0` | 위 배너의 글자·아이콘 |

`primary`(`0xFF00695C`)·`onPrimary`·`error`·`outline`은 양쪽 공통으로 둔다. 딥 틸을 다크에서
밝은 민트로 뒤집으면 브랜드 인상이 바뀌고, 화면에서 `primary`를 쓰는 20곳의 글자색까지 함께
손봐야 해서 요청 범위를 넘는다. 흰 글자를 얹은 딥 틸 버튼은 어두운 배경에서도 읽힌다.

`dangerBg`·`dangerFg`(기록 삭제·방 삭제·회원 탈퇴 버튼의 연분홍)는 Material `ColorScheme`에 대응
슬롯이 없어 화면이 테마에서 꺼내 쓸 수 없다. 쓰는 곳이 4군데뿐이라 `ThemeExtension`을 만들지
않고 순수 함수 하나를 둔다. `poller.dart`의 `PollDelta`가 이미 레코드 타입을 쓰고 있어 스타일이
맞는다.

```dart
// 파괴적 동작(기록 삭제·회원 탈퇴) 색 — ColorScheme에 대응 슬롯이 없어 밝기로 직접 고른다
({Color bg, Color fg}) dangerColors(Brightness brightness) => brightness == Brightness.dark
    ? (bg: Color(0xFF43201A), fg: Color(0xFFFFB4A0))
    : (bg: Color(0xFFF7DAD2), fg: Color(0xFFA03920));
```

`BuildContext` 대신 `Brightness`를 받는다. 순수 함수라 위젯 없이 단위 테스트할 수 있다.

## 4. 다크모드 — 화면 10개

| 지금 | 바꿀 것 |
|---|---|
| `Scaffold(backgroundColor: AppColors.surface)` | **줄 삭제** — 테마의 `scaffoldBackgroundColor`로 떨어진다 |
| `AppBar(backgroundColor:, foregroundColor:)` | **줄 삭제** — 테마의 `appBarTheme`으로 떨어진다 |
| `AppColors.onSurface` · `onSurfaceVariant` | `Theme.of(context).colorScheme.<같은 이름>` |
| `AppColors.outline` · `outlineVariant` | 〃 |
| `AppColors.primaryContainer` · `onPrimaryContainer` | 〃 |
| `AppColors.errorContainer` · `onErrorContainer` | 〃 |
| `AppColors.dangerBg` · `dangerFg` | `dangerColors(Theme.of(context).brightness)` |
| `Color(0x1F191C1B)` · `Color(0x61191C1B)` | `colorScheme.onSurface.withValues(alpha: 0.12 / 0.38)` |
| `Color(0xFFF7DAD2)` · `Color(0xFFA03920)` + 알파 | `dangerColors(...)`의 값에 같은 알파 |
| `AppColors.primary` · `onPrimary` · `error` | 그대로 |

배경·앱바 25줄은 치환이 아니라 삭제로 정리되어 줄이 오히려 줄어든다. 테마에 이미 올바른 값이
있으므로 화면이 다시 지정할 이유가 없다. `fall_detail.dart:327`의 `foregroundColor:
AppColors.onSurface`는 앱바가 아니라 `OutlinedButton` 스타일이라 삭제가 아닌 치환 대상이다.

원시 색 리터럴 12곳은 전부 비활성 상태 색이다. `191C1B`는 라이트 `onSurface`와 같은 값이고
알파 `0x1F`·`0x61`은 Material의 비활성 배경 12%·전경 38%에 해당한다. 그래서 상수를 지우고
`colorScheme.onSurface`에 같은 알파를 씌우면 의미가 그대로 보존되면서 밝기를 따라간다.

부수 효과가 하나 있다. `const Icon(..., color: AppColors.onSurfaceVariant)`처럼 `const`로 잡힌
위젯은 `Theme.of(context)`를 쓰는 순간 `const`를 떼야 한다. 기계적인 작업이다.

**예외** — `splash.dart`는 배경이 `AppColors.primary`인 브랜드 화면이라 양쪽 모드에서 틸을
유지한다. 이 파일은 손대지 않는다.

## 5. 낙상 발생 모달

### 5-1. 데이터 흐름

```
FallPoller (5초)
  └─ onEvents(all, fresh, newlyOk)
       ├─ 기존: 로컬 알림 발송 + setState로 목록 갱신
       └─ 추가: _queueAlerts(fresh)      ← newlyOk는 넣지 않는다
                  └─ 큐에 append
                     이미 창이 떠 있으면 여기서 끝
                     아니면 _drainAlerts() 시작
                       └─ 큐가 빌 때까지: showDialog → 확인 대기 → 다음
```

`newlyOk`를 제외하는 이유는 그것이 새 사고가 아니라 이미 알린 낙상에 "괜찮다"는 음성 응답이
뒤늦게 붙은 전이이기 때문이다. 창을 띄울 일이 아니다.

### 5-2. `MainShell`

```dart
final _alertQueue = <FallEvent>[];
bool _alertShowing = false;

void _queueAlerts(List<FallEvent> fresh) {
  if (fresh.isEmpty) return;
  // fresh는 서버 최신순 목록에서 거른 것이라 이미 최신순이다 — 최신 낙상부터 뜬다
  _alertQueue.addAll(fresh);
  if (!_alertShowing) unawaited(_drainAlerts());
}

Future<void> _drainAlerts() async {
  _alertShowing = true;
  while (_alertQueue.isNotEmpty && mounted) {
    final event = _alertQueue.removeAt(0);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,   // 바깥을 눌러도 안 닫힌다
      useRootNavigator: true,      // 설정·상세처럼 위에 쌓인 화면도 덮는다
      builder: (_) => FallAlertDialog(event: event),
    );
  }
  _alertShowing = false;
}
```

호출 지점은 기존 `onEvents` 콜백 끝, `setState` 다음이다. 폴러는 `onEvents`를 `await`하지 않고
부르므로(`poller.dart:100`) 창이 떠 있는 동안에도 5초 폴링은 계속 돈다. 그 사이 도착한 새
낙상은 큐에 쌓였다가 이어서 뜬다.

정렬은 하지 않는다. `fresh`는 서버가 준 최신순 목록에서 `id > lastSeenId`로 거른 것이라 이미
최신순이다.

### 5-3. 창 — `app/lib/screens/fall_alert_dialog.dart` (신규)

```
        ⚠  ← colorScheme.error

       사고 발생

   방 이름        안방
   방 번호        1번
   발생 시각      7월 28일 04:35

   ┌──────────────────────┐
   │         확인         │
   └──────────────────────┘
```

`AlertDialog`을 `PopScope(canPop: false)`로 감싸 뒤로가기·스와이프로도 닫히지 않게 한다.
`barrierDismissible: false`와 합쳐 **확인 버튼이 유일한 출구**다.

시각 포맷은 홈 화면과 같은 `7월 28일 04:35` 형태다. 창 배경은 테마의 `surfaceContainerHigh`로
떨어지고 그 값은 3절에서 이미 밝기별로 분기돼 있어 다크모드에서 추가 작업이 없다.

### 5-4. 엣지 케이스

| 상황 | 처리 |
|---|---|
| 로그인 직후 | `NewEventTracker`가 최초 응답을 프라이밍해 빈 `fresh`를 준다. 과거 낙상이 무더기로 뜨지 않는다 |
| 백그라운드에서 복귀 | 그동안 쌓인 낙상이 한 번에 `fresh`로 와서 순차로 뜬다 |
| 창이 떠 있는데 새 낙상 도착 | 큐에 쌓였다가 확인 후 이어서 뜬다 |
| 새 낙상인데 이미 괜찮음이 실려 옴 | 사고는 발생한 것이므로 똑같이 띄운다. 문구는 동일하다 |
| 표시 중 세션 만료(401) | `_logout`의 `pushAndRemoveUntil((route) => false)`이 다이얼로그 라우트까지 걷어내고, `while`의 `mounted` 검사에서 루프가 빠져나온다 |

## 6. 테스트

기존 5개 테스트는 그대로 통과시킨다.

- **`app/test/fall_alert_dialog_test.dart`** — 방 이름·방 번호·발생 시각이 창에 뜬다 / 확인을
  누르면 닫힌다 / 바깥(barrier)을 탭해도 안 닫힌다 / 뒤로가기로도 안 닫힌다.
- **`app/test/main_shell_alert_test.dart`** — 새 낙상 2건이면 확인을 두 번 눌러야 둘 다 사라진다
  (순차 동작) / 로그인 직후 최초 응답의 기존 낙상으로는 창이 안 뜬다 / `newlyOk`로는 창이 안
  뜬다 / 확인을 눌러도 서버에 확인 기록 요청이 나가지 않는다(가짜 Api가 호출을 기록해 검증).
- **`app/test/app_theme_test.dart`** — 다크 테마의 `scaffoldBackgroundColor`·`outlineVariant`·
  `primaryContainer`·`errorContainer`가 라이트 값과 다르다 / `dangerColors`가 밝기별로 다른 값을
  준다 / 다크 테마로 설정 화면을 띄우면 Scaffold가 라이트 상수 `0xFFF4F6F6`로 칠해지지 않는다.

세 번째 묶음이 이번 버그를 그대로 겨냥한다. 정체가 "밝기 분기 누락"이므로 분기가 다시 빠지면
바로 실패해야 한다.

구현 중 걸릴 것이 하나 있다. `MainShell` 위젯 테스트는 폴러의 `Timer.periodic`이 살아 있어
테스트 끝에 pending timer 실패가 날 수 있다. 마지막에 다른 위젯을 pump해 `dispose`를 태운다.

## 7. 검증

`flutter test` 전체 통과 → `flutter analyze` 무경고 → 실기기 재빌드·재설치 후 다크모드 토글과
실제 낙상 감지로 창을 확인한다. 실기기 절차는 `.claude/skills/running-fall-guardian`을 따른다.
