# 브라우저 E2E 스크립트

수동 검증 항목 중 브라우저로 자동화한 두 개다. 시스템에 설치된 실제 Chrome을 그대로 쓴다
(playwright-core + `channel: "chrome"` — 별도 브라우저 다운로드 없음).

| 스크립트 | 검증 내용 |
|---|---|
| `queue-e2e.mjs` | 감지 페이지 오프라인→온라인 큐 재전송 — 차단 중 큐 유지, online 이벤트 재전송, 멱등 200 흡수 |
| `push-e2e.mjs` | 데스크톱 웹 푸시 — 로그인, 알림 켜기(구독), 낙상 POST → 서비스 워커 알림 표시까지 |

## 준비

```bash
cd scripts/e2e && npm install                     # playwright-core 하나뿐이다

# 터미널 1 — Django (푸시 E2E는 VAPID 환경변수가 필요하다. 생성법은 README "푸시 알림 (선택)" 절)
cd backend && VAPID_PRIVATE_KEY=<키> VAPID_SUBJECT=mailto:<이메일> .venv/bin/python manage.py runserver 8000

# 터미널 2 — 감지 페이지 정적 서버 (스크립트가 5500을 하드코딩하고 있다)
python3 -m http.server 5500 -d web
```

## 실행

```bash
node scripts/e2e/queue-e2e.mjs
node scripts/e2e/push-e2e.mjs            # 헤드리스로도 실수신까지 확인된다
node scripts/e2e/push-e2e.mjs --headed   # 알림이 뜨는 걸 눈으로 보고 싶을 때
```

매 실행 `e2e_queue_*` / `e2e_push_*` 계정을 새로 만들어 로컬 `db.sqlite3`에 남는다.
전부 통과하면 종료 코드 0, 하나라도 실패하면 1이다.

## 주의 — 이 스크립트가 우회하는 함정 3개

다음에 손댈 때 지우면 안 되는 부분이다 (자세한 내막은 `context-notes.md`의 "E2E 검증 라운드").

1. **시크릿 컨텍스트에는 Push API가 없다** — `launchPersistentContext`(일반 프로필)를 써야 한다.
2. **Playwright 기본 인자 `--disable-background-networking`이 GCM 소켓을 끊는다** — 구독은 되는데
   수신만 안 되는 증상. `ignoreDefaultArgs`로 제거해야 한다.
3. **알림 감지→수집을 두 번의 evaluate로 나누면 레이스로 놓친다** — 한 evaluate 안에서 100ms 샘플링한다.
