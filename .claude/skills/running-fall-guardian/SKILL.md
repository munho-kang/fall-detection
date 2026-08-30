---
name: running-fall-guardian
description: Use when running, installing, or demoing this fall-detection project — starting the Spring Boot backend, serving the MediaPipe detection page, installing the Flutter app on a physical iPhone, capturing an iOS device screenshot, diagnosing why `flutter run` fails on a real device, why the app cannot reach the backend over an iPhone hotspot, or why 119 auto-reporting never fires.
---

# 낙상 감지 프로젝트 실행

세 프로세스를 한 Mac에서 띄우고 폰과 Mac을 같은 망에 둔다. 같은 와이파이여도 되고 폰 핫스팟에 Mac을 붙여도 되는데, 핫스팟은 주소 잡는 법이 다르다(아래 별도 절). 배포는 없다.

| 구성 | 포트 | 기동 |
|---|---|---|
| Spring Boot | 8000 | `cd backend && ./gradlew bootRun` |
| 감지 페이지 | 5500 | `cd web && python3 -m http.server 5500` |
| Flutter 앱 | — | 아래 iOS 실기기 절차 |

전제는 PostgreSQL이 떠 있고 `fall_detection` DB가 있는 것이다. 없으면 `createdb fall_detection`.

## iOS 실기기 설치 — `flutter run`은 쓰지 않는다

`flutter run --release -d <udid>`는 **빌드와 서명까지 통과하고 설치 단계에서 실패한다**(`Could not run build/ios/iphoneos/Runner.app`). 빌드는 flutter로, 설치·실행은 `devicectl`로 나눠서 한다.

```bash
xcrun devicectl list devices          # Identifier 열을 복사한다 (아래 $DEV)
cd app
HOST=$(ipconfig getifaddr en0)        # 같은 와이파이
[ -z "$HOST" ] && HOST="[$(ifconfig en0 | awk '/inet6 2/ && !/temporary/ && !/clat46/ {print $2; exit}')]"
echo "$HOST"                          # 비었거나 "[]"면 여기서 멈춘다 — 빈 값은 조용히 폴백한다
flutter build ios --release --dart-define=API_HOST="$HOST"
xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device $DEV com.example.fallGuardian
```

**기기 ID가 두 종류다.** `flutter devices`가 주는 하드웨어 UDID(`00008140-…`)와 `devicectl`이 쓰는 CoreDevice UUID(`529A6455-…`)는 서로 다른 값이고 바꿔 쓸 수 없다.

`API_HOST`는 실기기에만 필요하다. 시뮬레이터는 `127.0.0.1`, Android 에뮬레이터는 `10.0.2.2`를 자동으로 쓴다(`app/lib/api.dart`).

### iPhone 핫스팟에 붙으면 Mac에 IPv4 주소가 없다

핫스팟이 IPv6 전용이면 `ipconfig getifaddr en0`이 **에러 없이 빈 값**을 낸다. 그대로 쓰면 `--dart-define=API_HOST=`가 되고 앱은 `127.0.0.1:8000`으로 폴백해 자기 자신을 찌른다. 빌드·설치·실행이 모두 성공하고 로그인에서만 실패하므로, 위 `echo "$HOST"`로 먼저 끊는다.

`ifconfig en0`의 `inet 192.0.0.2/32`는 **쓰면 안 된다.** 464XLAT CLAT 주소라 Mac 내부 변환용이고 폰에서 라우팅되지 않는다. 써야 할 것은 글로벌 IPv6이며 `temporary`(주기 교체)와 `clat46`을 걸러야 안정 주소가 남는다. `ipconfig getv6ifaddr`는 존재하지 않는 명령이다.

**대괄호째 넘긴다.** `api.dart`가 `'http://$host:8000'` 문자열 조합이라 `[2001:…]`을 그대로 주면 유효한 URL이 된다 — 코드 수정 없이 동작하는 것을 실측했다(2026-07-27).

| 예상했던 벽 | 실제 |
|---|---|
| ATS가 평문 HTTP를 막는다 | 막지 않았다. `NSAllowsLocalNetworking`뿐이고 글로벌 IPv6는 ATS의 로컬 범위 밖이라 차단을 예상했으나 통과했다(2026-07-27 실측). 미리 `NSAllowsArbitraryLoads`를 넣지 않는다 |
| 핫스팟이 클라이언트를 격리한다 | 격리하지 않는다. Mac과 폰이 같은 /64에 있어 직접 통신한다 |

**프리픽스는 재접속 때 바뀐다.** `API_HOST`는 컴파일 타임에 박히므로, 핫스팟이 끊겼다 붙으면 재빌드·재설치해야 한다. 증상은 "어제까지 되던 앱이 서버만 못 찾음"이다.

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

카메라에 어깨(11·12)와 골반(23·24)이 모두 들어와야 판정이 시작된다. 감지 화면 오른쪽의 **세 관문 막대**가 관문별 현재값과 기준선을 함께 보여주므로, 감지가 안 되면 어느 관문에서 걸렸는지 그대로 읽으면 된다. 원시 피크값과 CSV가 필요하면 **`d` 키**로 튜닝 패널을 연다.

감지 페이지는 반드시 Mac에서 연다. `getUserMedia`는 보안 컨텍스트를 요구하고 `localhost`만 예외라, 폰에서 `http://<Mac IP>:5500`으로 열면 카메라가 막힌다.

## 단계별 확인

각 단계가 실제로 됐는지 보는 명령이다. 화면만 보고 넘기지 않는다.

```bash
lsof -nP -iTCP:8000 -sTCP:LISTEN                      # 백엔드 기동
curl -s -g -o /dev/null -w "%{http_code}\n" \
  "http://$HOST:8000/api/rooms/"                      # 401이면 정상 (미인증). $HOST는 빌드 때 쓴 값
lsof -nP -iTCP:8000 | grep -vE "LISTEN|COMMAND"       # 폰에서 온 연결
psql -d fall_detection -c \
  "SELECT f.id, g.username, f.room_name, f.occurred_at, f.reported_119_at FROM fall_event f
   JOIN guardian g ON g.id=f.guardian_id ORDER BY f.occurred_at DESC LIMIT 3;"
```

폰 연결을 주소 대역으로 거르지 않는다 — 핫스팟이면 `192.168.`이 아니라 글로벌 IPv6로 찍힌다. HTTP 연결은 순간적으로 열렸다 닫히므로 `lsof` 한 번으로는 놓친다. 1초 간격으로 돌려놓고 폰을 조작하는 편이 확실하다.

앱은 시작 시 저장된 토큰만 읽고 API를 부르지 않는다. 첫 요청은 로그인 시점에 나가므로, 앱을 켠 것만으로는 네트워크 경로가 검증되지 않는다. 앱이 백그라운드로 내려가면 iOS가 정지시켜 폴링이 멎는데, 이건 연결 문제가 아니다.

## 119 자동 신고가 안 될 때 — 코드보다 서버가 언제 켜졌는지 본다

증상은 "낙상은 목록에 뜨는데 119 표시가 영영 안 붙는다" 하나뿐이고, **브라우저·서버 로그·DB 어디에도 에러가 남지 않는다.** 단서가 없으니 코드를 뒤지기 전에 프로세스 나이부터 본다.

낙상 확정 20초 뒤 감지 페이지가 `reported_119_at`을 담아 **같은 낙상을 다시 POST**하고 서버가 그 값을 병합하는 구조다(`web/js/escalation.js`, `web/js/main.js`). `bootRun`은 **켜질 때의 코드로 굳는다.** devtools가 없어 핫리로드가 없고 `ddl-auto: none`이라 Flyway 마이그레이션도 재시작해야만 돈다. 코드를 고치고 서버를 안 내리면 옛 코드가 계속 응답한다.

**왜 조용한가.** `FallEventRequest`의 `@JsonIgnoreProperties(ignoreUnknown = true)`가 원인이다(클라이언트가 `guardian`을 주입하지 못하게 막는 장치라 없앨 것이 아니다). 구 서버는 `reported_119_at`을 모르는 필드로 버리고, 남은 값이 기존 낙상과 같으니 중복 제거가 걸려 **기존 행을 200으로** 돌려준다. 클라이언트는 성공으로 읽고 재시도조차 하지 않는다.

```bash
ps -p $(lsof -ti tcp:8000 -sTCP:LISTEN | head -1) -o lstart=              # 서버가 켜진 시각
git log -1 --format="%ad %s" --date=format:"%m-%d %H:%M" -- backend/src   # 백엔드 코드 마지막 변경
# 코드가 더 최신이면 그것이 원인이다. 아래 둘로 확증한다
psql -d fall_detection -tAc \
  "SELECT version FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 1;"  # 2 미만이면 미적용
T=$(psql -d fall_detection -tAc "SELECT key FROM auth_token WHERE guardian_id=<id> LIMIT 1;")
curl -s -H "Authorization: Token $T" http://127.0.0.1:8000/api/falls/ \
  | grep -c reported_119_at                                              # 0이면 구 서버 확정
```

조치는 재시작뿐이다. 고칠 코드가 없다(2026-07-27 확정). 재시작 로그에 `Migrating schema "public" to version "2"`가 찍히면 적용된 것이다.

**서버를 갈아도 안 되면 클라이언트를 본다.** 감지 화면의 **응급 대응 카드**가 어디서 멈췄는지가 가른다.

| 응급 대응 카드 | 뜻 |
|---|---|
| 대답을 듣는 중 → 괜찮으세요? 확인 중 → 119 자동 신고됨 (세 점이 모두 채워짐) | 정상. 20초에 신고가 나간다 |
| 카드가 초록으로 바뀌고 "응답 확인 — 신고 안 함"에서 멈춤 | 마이크가 주변 소리를 응답으로 인식했다(`escalation.js`의 `heardOk`) |
| 카드가 통째로 사라짐 | 감지기가 STANDING으로 튀어 에피소드가 취소됐다. 누운 자세가 계속 잡히는지 본다 |
| 카드가 아예 안 뜸 | 브라우저가 옛 `main.js`를 물고 있다 → ⌘⇧R (아래 캐시 절 참고) |

## 브라우저가 `/detect`로 404를 낼 때

코드는 항상 상대 경로 `detect.html`로 이동한다(`web/index.html`). 확장자가 떨어져 나가면 브라우저가 프로필에 저장된 것으로 응답한 것이고, 진범은 **캐시된 301**이다(2026-07-27 확정). 7월 17일에 clean-URL 방식 서버(HTTP/1.1, 예: `npx serve`)가 `/detect.html → 301 /detect`를 냈고 Chrome이 이를 저장해 열흘간 네트워크 없이 재생했다. clean-URL 서버 밑에서는 `/detect`도 정상 서빙되어 증상이 숨고, python http.server로 바꾸는 순간 404로 터진다.

**확인법은 서버 로그와 브라우저 기록을 맞춰보는 것이다.** 브라우저는 `/detect.html` 방문을 기록했는데 서버 로그에 그 요청이 없으면 브라우저 내부 응답이다 — 후보는 서비스 워커와 캐시된 301 둘이고, 같은 관찰로는 구분되지 않는다(처음엔 워커로 오진했다).

```bash
grep -E "GET /detect" web-server.log     # 실패 순간에 /detect.html이 안 보이면 브라우저 내부 응답
# 둘을 가르는 지문 — 캐시에서 실물을 찾는다. grep은 반드시 -a (없으면 바이너리에서 거짓 음성)
grep -a -rl "5500/detect" "$HOME/Library/Caches/Google/Chrome/Default/Cache/Cache_Data" \
  | xargs -I{} sh -c 'strings -a {} | grep -aE "_dk_|^HTTP/|Location:"'
# HTTP/1.1이면 python(HTTP/1.0)이 아닌 다른 서버가 남긴 응답이다
```

이미 배제된 원인이라 다시 파지 않는다.

| 의심 | 판정 근거 |
|---|---|
| 주소창 직접입력·자동완성 | Chrome 방문 기록에서 `/detect`는 전부 리다이렉트 체인(SERVER_REDIRECT 플래그)으로 찍힌다 |
| URL 정리 확장 프로그램 | 설치된 확장의 호스트 권한이 Google 도메인뿐이라 `127.0.0.1`에 접근 자체가 안 된다 |
| 옛 서비스 워커 | 등록은 스코프 `/` 하나뿐이고 스크립트가 우리 `sw.js`(fetch 핸들러 없음)로 확인됐다. 워커 축출로는 증상이 안 사라졌다 |

조치는 로그인 페이지(`http://127.0.0.1:5500/`)를 새로 받아 한 번 여는 것뿐이다(⌘⇧R 권장). `web/index.html`(9fb5753)이 이동 대상들을 `fetch(cache: "reload")`로 다시 받아 오염된 301 항목을 정상 200으로 덮어쓰고, 로그인 이동 URL에도 `?t=<now>`를 붙여 키 자체를 우회한다. **DevTools → Application → Storage의 Clear site data는 이 병에 안 듣는다** — 스토리지·워커·CacheStorage만 지우고 HTTP 디스크 캐시는 범위 밖이라, 실행해도 301 항목이 mtime 7/17 그대로 남는 것을 실측했다(2026-07-27). 수동으로 지우려면 `chrome://settings/clearBrowserData`의 "캐시된 이미지 및 파일"(전역)뿐이다. 시크릿 창이 멀쩡한 것은 "프로필 저장물이 원인"이라는 공통 신호일 뿐 워커 확정이 아니다.

재발 방지는 세 겹이다. `web/`은 clean-URL 서버로 서빙하지 않는다 — `python3 -m http.server 5500`으로 고정한다(`npx serve`는 301을 다시 심는다). `web/index.html`이 `sw.js`를 등록하므로(bca77fc) 남의 워커가 오리진을 잡아도 로그인 페이지 방문 한 번으로 축출된다 — `cd web && npm run test:e2e:sw`가 검증한다. 캐시에 이미 박힌 301은 위 조치 문단의 덮어쓰기·키 우회(9fb5753)가 무력화한다 — 실제 디스크 캐시에 301을 심어 재현하는 `npm run test:e2e:301`이 검증한다.
