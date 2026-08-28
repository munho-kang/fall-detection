# 브라우저 E2E 스크립트

수동 검증 항목 중 브라우저로 자동화한 것이다. 시스템에 설치된 실제 Chrome을 그대로 쓴다
(playwright-core + `channel: "chrome"` — 별도 브라우저 다운로드 없음).

| 스크립트 | 검증 내용 |
|---|---|
| `queue-e2e.mjs` | 감지 페이지 오프라인→온라인 큐 재전송 — 차단 중 큐 유지, online 이벤트 재전송, 멱등 200 흡수 |

## 준비

```bash
cd scripts/e2e && npm install                     # playwright-core 하나뿐이다

# 터미널 1 — Spring Boot
cd backend && ./gradlew bootRun

# 터미널 2 — 감지 페이지 정적 서버 (스크립트가 5500을 하드코딩하고 있다)
python3 -m http.server 5500 -d web
```

## 실행

```bash
node scripts/e2e/queue-e2e.mjs
```

매 실행 `e2e_queue_*` 계정을 새로 만들어 로컬 `fall_detection` DB(PostgreSQL)에 남는다.
전부 통과하면 종료 코드 0, 하나라도 실패하면 1이다.
