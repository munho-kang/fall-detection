---
name: running-fall-guardian
description: Use when running, installing, or demoing this fall-detection project — starting the Spring Boot backend, serving the MediaPipe detection page, installing the Flutter app on a physical iPhone, capturing an iOS device screenshot, or diagnosing why `flutter run` fails on a real device.
---

# 낙상 감지 프로젝트 실행

세 프로세스를 한 Mac에서 띄우고 폰은 같은 와이파이로 붙는다. 배포는 없다.

| 구성 | 포트 | 기동 |
|---|---|---|
| Spring Boot | 8000 | `cd backend && ./gradlew bootRun` |
| 감지·보호자 페이지 | 5500 | `cd web && python3 -m http.server 5500` |
| Flutter 앱 | — | 아래 iOS 실기기 절차 |

전제는 PostgreSQL이 떠 있고 `fall_detection` DB가 있는 것이다. 없으면 `createdb fall_detection`.

## iOS 실기기 설치 — `flutter run`은 쓰지 않는다

`flutter run --release -d <udid>`는 **빌드와 서명까지 통과하고 설치 단계에서 실패한다**(`Could not run build/ios/iphoneos/Runner.app`). 빌드는 flutter로, 설치·실행은 `devicectl`로 나눠서 한다.

```bash
xcrun devicectl list devices          # Identifier 열을 복사한다 (아래 $DEV)
cd app
flutter build ios --release --dart-define=API_HOST=$(ipconfig getifaddr en0)
xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device $DEV com.example.fallGuardian
```

**기기 ID가 두 종류다.** `flutter devices`가 주는 하드웨어 UDID(`00008140-…`)와 `devicectl`이 쓰는 CoreDevice UUID(`529A6455-…`)는 서로 다른 값이고 바꿔 쓸 수 없다.

`API_HOST`는 실기기에만 필요하다. 시뮬레이터는 `127.0.0.1`, Android 에뮬레이터는 `10.0.2.2`를 자동으로 쓴다(`app/lib/api.dart`).

## 도구가 거짓말하는 지점

이 프로젝트에서 겪은 오진들이다. 메시지를 그대로 믿고 고치려 들면 시간을 버린다.

| 도구가 말하는 것 | 실제 원인 | 확인 명령 |
|---|---|---|
| `enable Developer Mode in Settings` | 이미 켜져 있는 경우가 많다. 재시도하면 그냥 진행된다 | `xcrun devicectl device info details --device $DEV \| grep developerModeStatus` |
| `Could not run Runner.app` | 설치 경로만 깨진 것이고 진짜 사유를 감춘다 | `devicectl device install app`으로 직접 설치해 원문 에러를 본다 |
| `invalid code signature, inadequate entitlements or its profile has not been explicitly trusted` | 무료 개인 계정 인증서 미신뢰 | 폰에서 **설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 → 신뢰** |

무료 개인 팀으로 서명하면 **프로파일이 7일 뒤 만료된다.** 만료일 확인은 이렇게 한다.

```bash
security cms -D -i app/build/ios/iphoneos/Runner.app/embedded.mobileprovision \
  | plutil -p - | grep -E "ExpirationDate|TeamName"
```

## iOS 17+ 기기 화면 캡처

`idevicescreenshot`은 `Invalid service`로 실패한다. DDI가 마운트돼 있어도 마찬가지다 — iOS 17+에서 `screenshotr`가 RemoteXPC 터널 뒤로 옮겨졌기 때문이다. `pymobiledevice3`가 no-root 터널로 우회한다.

```bash
pipx install pymobiledevice3
~/.local/bin/pymobiledevice3 developer dvt screenshot out.png
```

## 감지 테스트

**감지 페이지와 앱이 같은 계정으로 로그인해야 한다.** `fall_event`는 `guardian_id`에 묶여 있어서 계정이 다르면 폰 목록에 영영 뜨지 않는다. 계정에 방이 없으면 "감지 시작"이 비활성이므로 방을 먼저 추가한다.

낙상은 `web/js/detector.js`의 3단 관문을 모두 통과해야 전송된다.

| 관문 | 조건 | 거르는 것 |
|---|---|---|
| 속도 | 골반이 화면 높이의 45%/초 이상 하강 | 천천히 눕기 |
| 자세 | 1초 안에 몸통 기울기 60° 초과 | 급히 앉기 |
| 시간 | 그 자세로 5초 유지 | 자가 회복 |

카메라에 어깨(11·12)와 골반(23·24)이 모두 들어와야 판정이 시작된다. 화면의 튜닝 패널에 `hipV`·`tilt` 실시간 값이 뜨므로, 감지가 안 되면 어느 관문에서 걸렸는지 숫자로 확인한다.

감지 페이지는 반드시 Mac에서 연다. `getUserMedia`는 보안 컨텍스트를 요구하고 `localhost`만 예외라, 폰에서 `http://<Mac IP>:5500`으로 열면 카메라가 막힌다.

## 단계별 확인

각 단계가 실제로 됐는지 보는 명령이다. 화면만 보고 넘기지 않는다.

```bash
lsof -nP -iTCP:8000 -sTCP:LISTEN                      # 백엔드 기동
curl -s -o /dev/null -w "%{http_code}\n" \
  http://$(ipconfig getifaddr en0):8000/api/rooms/    # 401이면 정상 (미인증)
lsof -nP -iTCP:8000 | grep -E "192\.168\..+:8000->"   # 폰에서 온 연결
psql -d fall_detection -c \
  "SELECT f.id, g.username, f.room_name, f.occurred_at FROM fall_event f
   JOIN guardian g ON g.id=f.guardian_id ORDER BY f.occurred_at DESC LIMIT 3;"
```

앱은 시작 시 저장된 토큰만 읽고 API를 부르지 않는다. 첫 요청은 로그인 시점에 나가므로, 앱을 켠 것만으로는 네트워크 경로가 검증되지 않는다.

## 브라우저가 `/detect`로 404를 낼 때

코드는 항상 상대 경로 `detect.html`로 이동한다(`web/index.html`). 확장자가 떨어져 나가면 **옛 서비스 워커**다. 포트 5500이 VS Code Live Server 기본값이라 다른 프로젝트가 같은 오리진에 워커를 남겨두고, 그게 `detect.html` 요청을 가로채 `/detect`로 리다이렉트한다. 서비스 워커는 디렉터리가 아니라 오리진 단위로 남는다.

**확인법은 서버 로그와 브라우저 기록을 맞춰보는 것이다.** 브라우저는 `/detect.html` 방문을 기록했는데 서버 로그에 그 요청이 없으면, 네트워크가 아니라 워커가 응답한 것이다.

```bash
grep -E "GET /detect" web-server.log     # 실패한 순간에 /detect.html이 아예 안 보이면 워커다
```

이미 배제된 원인이라 다시 파지 않는다.

| 의심 | 판정 근거 |
|---|---|
| 주소창 직접입력·자동완성 | Chrome 방문 기록에서 `/detect`는 전부 LINK(리다이렉트 체인)이고 TYPED로 찍힌 적이 없다 |
| URL 정리 확장 프로그램 | 설치된 확장의 호스트 권한이 Google 도메인뿐이라 `127.0.0.1`에 접근 자체가 안 된다 |

조치는 로그인 페이지(`http://127.0.0.1:5500/`)를 한 번 여는 것이다. `web/index.html`이 `sw.js`를 등록하고, fetch 핸들러가 없는 우리 워커가 `skipWaiting()` + `clients.claim()`으로 옛 워커를 즉시 대체한다(bca77fc). 그래도 남으면 `chrome://serviceworker-internals/`에서 `127.0.0.1:5500` 등록을 직접 해제한다. 시크릿 창이 멀쩡한 것도 워커가 없어서다.

주의: `sw.js`에 skipWaiting을 넣는 것(08a230c)만으로는 부족했다. 등록 호출이 `guardian.js`의 푸시 설정에만 있어서 로그인 → 감지 흐름에서는 교체가 아예 일어나지 않았다. 축출 전 과정은 `cd web && npm run test:e2e:sw`가 단독 실행으로 검증한다 — 옛 워커를 심고, `/detect` 404를 재현하고, 로그인 페이지 방문만으로 교체되는 것까지 확인한다.

서버 로그가 없으면 Chrome 방문 기록(History SQLite의 `visits.transition`)으로도 판정된다. `/detect` 방문에 SERVER_REDIRECT(0x80000000) 플래그가 서 있으면 브라우저가 3xx 응답을 받은 것인데, python http.server는 파일 요청에 리다이렉트를 내지 않으므로 발신자는 워커다.
