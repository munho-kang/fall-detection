# 배포 가이드

이 문서는 세 구성요소를 실제 서비스로 올리는 절차다.

| 대상 | 배포 위치 | 결과물 |
|------|-----------|--------|
| `backend/` (Django) | Render 웹 서비스 + Postgres | `https://fall-backend-XXXX.onrender.com` |
| `web/` (감지·보호자 페이지) | GitHub Pages | `https://<아이디>.github.io/<저장소>/` — 보호자 페이지는 `guardian.html` |
| `app/` (Flutter) | 본인 아이폰 | 홈 화면의 Fall Guardian 앱 |

**순서가 중요하다.** Render 주소는 배포해 봐야 알 수 있고(랜덤 접미사가 붙는다), 그 주소를 웹과 앱 코드에 반영해야 하기 때문이다. 아래 1→5 순서대로 진행한다.

## 0. 준비물

- GitHub 계정, Render 계정(GitHub 계정으로 가입하면 저장소 연동이 쉽다).
- 카드 등록 불필요 — 전부 무료 플랜으로 진행한다.
- Mac + Xcode. 이전에 실기기 실행을 해봤으므로 서명 팀 설정은 이미 끝나 있다.

## 1. GitHub 저장소 만들고 올리기

1. github.com → 우측 상단 `+` → New repository. 이름은 예를 들어 `fall-detection`. **Public**으로 만든다(무료 계정의 GitHub Pages는 공개 저장소에서만 동작한다). "Add a README" 등은 전부 체크하지 않는다.
2. 터미널에서 원격을 연결하고 push한다.

```bash
cd /Users/munhokang/82107/weniv_project
git remote add origin https://github.com/<아이디>/<저장소>.git
git push -u origin main
```

push에서 인증을 요구하면 GitHub 계정으로 로그인한다(비밀번호 대신 브라우저 인증 또는 Personal Access Token).

3. 저장소 Settings → Pages → Build and deployment → Source를 **GitHub Actions**로 바꾼다.
   - 방금 push 때 실행된 "Deploy web to GitHub Pages" 워크플로는 이 설정 전이라 실패했을 수 있다. 3단계에서 다시 push하면 자동으로 재실행되니 지금은 넘어가도 된다.
   - 대안. Source를 그대로 두고 Branch를 `main`으로 저장하는 "브랜치 배포"도 동작한다 — 이 경우 저장소 전체가 사이트가 되고, 루트의 `index.html`이 감지 페이지(`web/`)로 자동 이동시킨다. 두 방식 비교는 [deploy-guide.html](deploy-guide.html) 1단계 참고.

## 2. Render에 백엔드 배포

1. render.com → New + → **Blueprint** → 방금 만든 저장소 선택. 루트의 `render.yaml`을 자동으로 읽어 웹 서비스(fall-backend)와 무료 Postgres(fall-db)를 함께 만든다.
2. 환경변수 입력 화면에서 다음을 채운다.

| 키 | 값 |
|----|----|
| `CORS_ALLOWED_ORIGINS` | `https://<아이디>.github.io` — 끝에 `/` 없이, 저장소 이름 없이 |
| `DJANGO_SUPERUSER_USERNAME` | 보호자 로그인 아이디 |
| `DJANGO_SUPERUSER_EMAIL` | 이메일(형식만 맞으면 된다) |
| `DJANGO_SUPERUSER_PASSWORD` | 보호자 비밀번호 — 길고 어렵게 |

푸시 알림용 변수 3개(`FIREBASE_SERVICE_ACCOUNT`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`)도 함께 뜨는데, 지금은 비워 두어도 된다 — 아래 6번 절에서 채운다.

서버가 처음 뜰 때 이 계정이 자동 생성된다(`createsuperuser --noinput`). 이 계정은 `/ansgh/` 접속용 관리 계정이다(기본 `/admin/` 경로는 숨겨 두었다). 보호자 계정은 감지 페이지나 앱의 **회원가입**으로 만들면 된다(관리 계정으로 로그인해도 동작은 같다). 웹과 앱은 반드시 **같은 계정**으로 로그인해야 알림이 이어진다.

3. Apply를 누르면 빌드가 시작된다. 첫 빌드는 5~10분 걸린다.
4. 끝나면 fall-backend 서비스 페이지 상단의 URL을 복사한다. 예: `https://fall-backend-a1b2.onrender.com`.
5. 확인. 브라우저에서 그 URL을 열어 `{"status": "ok", ...}`가 보이고, `<URL>/ansgh/`에서 위 계정으로 로그인되면 백엔드 완료다.

## 3. 배포 주소를 코드에 반영

두 파일의 `XXXX` 자리 표시자를 방금 복사한 실제 주소로 바꾼다.

- `web/js/api.js`의 `PROD_API_BASE`
- `app/lib/api.dart`의 `_prodBaseUrl`

```bash
git add web/js/api.js app/lib/api.dart
git commit -m "배포된 Render 주소 반영"
git push
```

이 push가 GitHub Actions를 다시 실행해 감지 페이지도 새 주소로 재배포된다.

## 4. 감지 페이지(GitHub Pages) 확인

1. 저장소 Actions 탭에서 "Deploy web to GitHub Pages"가 성공(초록색)인지 확인한다.
2. `https://<아이디>.github.io/<저장소>/`에 접속하면 바로 로그인 화면이 뜬다 → 회원가입(또는 2단계 관리 계정으로 로그인) → 방 선택 → 감지 시작 → 카메라 허용. GitHub Pages는 https라서 카메라 권한이 정상 동작한다.
3. 주의. 무료 플랜 백엔드는 15분간 요청이 없으면 잠든다. 잠든 직후 첫 로그인은 최대 1분쯤 걸리니, 실패처럼 보이면 잠시 뒤 다시 시도한다.

## 5. 아이폰에 앱 설치

1. 아이폰을 Mac에 USB로 연결한다(이전에 무선 디버깅을 켜뒀다면 같은 Wi‑Fi에서도 잡힌다).
2. 릴리즈 모드로 설치한다.

```bash
cd /Users/munhokang/82107/weniv_project/app
flutter devices                        # 아이폰이 목록에 보이는지 확인
flutter run --release -d <기기 이름>
```

릴리즈 빌드는 자동으로 Render 백엔드를 바라본다(`api.dart`의 분기). 설치가 끝나면 케이블을 뽑아도 앱은 남는다.

3. 처음 설치하는 경우 폰에서 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 신뢰를 눌러준다.
4. 앱을 열어 같은 보호자 계정으로 로그인 → 낙상 목록이 보이면 끝. 감지 페이지 쪽에서 낙상이 확정되면 5초 폴링 안에 폰 알림이 온다.

**무료 Apple ID 서명은 7일 뒤 만료된다.** 앱이 안 열리게 되면 2번을 다시 실행하면 된다. Apple Developer Program($99/년)에 가입하면 1년짜리 서명이 된다.

## 6. 푸시 알림 설정 (선택)

푸시 없이도 전체 기능이 동작한다(앱을 켜 두면 폴링이 알린다). 아래를 설정하면 화면이 꺼져 있어도 알림이 온다. 채널은 두 개다.

| 채널 | 대상 | 필요한 환경변수 |
|------|------|-----------------|
| FCM | Android 앱 | `FIREBASE_SERVICE_ACCOUNT` |
| 표준 웹 푸시 | 데스크톱 브라우저·아이폰 홈 화면 PWA | `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` |

환경변수가 비어 있으면 해당 채널만 조용히 꺼지고 서버는 그대로 동작한다. 값은 Render 대시보드 → fall-backend → Environment에서 넣는다(저장하면 자동 재배포).

### 6-1. Android FCM

1. [Firebase 콘솔](https://console.firebase.google.com) → 프로젝트 추가(이름 자유, 애널리틱스 불필요).
2. 프로젝트 개요 → Android 아이콘 → 앱 등록. 패키지 이름은 정확히 `com.example.fall_guardian`.
3. `google-services.json`을 내려받아 `app/android/app/`에 둔다(저장소에 이미 커밋돼 있으면 불필요 — 이 파일은 식별자일 뿐 비밀키가 아니다).
4. 프로젝트 설정(톱니) → 서비스 계정 → **새 비공개 키 생성** → JSON 다운로드. 이 파일은 **비밀이다. 절대 커밋하지 않는다.**
5. JSON을 한 줄로 만들어 `FIREBASE_SERVICE_ACCOUNT`에 붙여넣는다.

```bash
python3 -c "import json; print(json.dumps(json.load(open('다운로드한파일.json'))))"
```

### 6-2. 웹 푸시 (VAPID)

1. 키쌍을 만든다.

```bash
cd backend && .venv/bin/python - <<'EOF'
import base64
from cryptography.hazmat.primitives.asymmetric import ec

key = ec.generate_private_key(ec.SECP256R1())
raw = key.private_numbers().private_value.to_bytes(32, "big")
print("VAPID_PRIVATE_KEY =", base64.urlsafe_b64encode(raw).rstrip(b"=").decode())
EOF
```

2. 출력값을 `VAPID_PRIVATE_KEY`에, `mailto:본인이메일`을 `VAPID_SUBJECT`에 넣는다. 공개키는 서버가 개인키에서 계산하므로 따로 넣지 않는다.
3. 데스크톱 크롬·엣지는 이걸로 끝이다 — 보호자 페이지(`guardian.html`)에서 **알림 켜기**를 누르면 된다.

### 6-3. 아이폰에서 보호자 페이지 알림 받기 (PWA)

iOS 16.4 이상에서 동작한다. **반드시 홈 화면에 추가한 아이콘으로 열어야** 알림 켜기가 가능하다 — Safari 탭에서는 iOS가 웹 푸시를 막는다.

1. Safari로 `https://<아이디>.github.io/<저장소>/guardian.html` 접속 → 로그인.
2. 공유 버튼 → **홈 화면에 추가**.
3. 홈 화면의 아이콘으로 다시 열어 로그인 → **알림 켜기** → 허용.
4. 확인. 감지 페이지에서 낙상을 확정시키면(또는 curl로 등록하면) 잠금 화면에 알림이 온다.

## 7. 운영할 때 알아둘 것

- **백그라운드 알림은 6번 절 설정에 달려 있다.** 설정했다면 Android 앱은 FCM으로, 아이폰·데스크톱은 보호자 페이지 푸시로 화면이 꺼져 있어도 알림이 온다. iOS 네이티브 앱만은 여전히 폴링이라 떠 있을 때만 알린다(README "알려진 한계"). 푸시를 설정하지 않았다면 예전처럼 앱을 화면에 켠 채 두는 운용을 권장한다.
- **앱이 떠 있는 동안 백엔드는 잠들지 않는다.** 앱이 5초마다 폴링하기 때문이다. 반대로 아무도 안 보고 있으면 백엔드가 잠들고, 다음 첫 요청이 느려진다.
- **무료 Postgres는 생성 30일 뒤 만료된다.** Render가 만료 전에 메일을 보낸다. 계속 쓰려면 둘 중 하나다. (a) Render에서 유료 플랜으로 업그레이드. (b) [Neon](https://neon.tech) 무료 Postgres를 만들어 Render 환경변수 `DATABASE_URL`만 그 연결 문자열로 교체 — 재배포되면 migrate와 보호자 계정 생성이 자동으로 다시 실행된다. 과거 낙상 기록까지 옮기려면 `pg_dump`/`pg_restore`가 필요하고, 안 옮기면 기록만 비워진 채 서비스는 계속된다.
- **카메라를 옮기면** README의 검수 3기준(넘어지기 hipV ≥ 0.5, 눕기 tilt ≥ 60°, 천천히 눕기 hipV < 0.3)을 다시 통과시켜야 한다.

## 8. 문제 해결

| 증상 | 원인과 해결 |
|------|-------------|
| 로그인이 한참 걸리거나 실패 | 무료 플랜 콜드스타트. 1분 뒤 재시도 |
| 브라우저 콘솔에 CORS 에러 | Render 환경변수 `CORS_ALLOWED_ORIGINS` 값 확인. `https://<아이디>.github.io` 정확히 — 끝 `/` 금지, 저장소 이름 금지. 고치면 자동 재배포를 기다린 뒤 재시도 |
| Pages가 404 | Settings → Pages의 Source가 GitHub Actions인지, Actions 탭의 최근 실행이 성공인지 확인 |
| Render 빌드가 Python 버전에서 실패 | `render.yaml`의 `PYTHON_VERSION`을 `3.13.4`로 낮춰 커밋·push |
| 앱에서 로그인 실패 | `api.dart`의 `XXXX`를 실제 주소로 바꿨는지, `--release`로 빌드했는지 확인 |
| 폰에 알림이 안 옴 | iOS 앱은 화면에 떠 있어야 한다. Android 앱은 `FIREBASE_SERVICE_ACCOUNT` 설정 여부, 아이폰 PWA는 `VAPID_*` 설정 여부와 "홈 화면 아이콘으로 열었는지"를 확인 |
| admin 화면이 깨져 보임 | 첫 배포 직후 캐시 문제일 수 있다. 강력 새로고침(Cmd+Shift+R) |
