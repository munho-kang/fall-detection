# 괜찮음 응답 앱 표시 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 낙상자가 "괜찮아"라고 답한 낙상을 서버에 `voice_ok_at`으로 기록하고, 보호자 앱 알림을 "낙상자가 괜찮다고 말한 낙상 사고입니다"로 교체하며 목록·상세에도 표시한다.

**Architecture:** 119 신고(`reported_119_at`)와 같은 재-POST 병합 패턴이다. 감지 페이지 상태머신(escalation.js)이 RESOLVED 전이에 `SEND_OK` 명령을 내놓고, 배선(main.js)이 `voice_ok_at`을 붙여 전송한다(원본 전송 전 조기 응답은 5초 원본 payload에 동승). 백엔드는 필드별 독립 병합, 앱은 폴링 트래커가 "이미 알린 이벤트에 괜찮음 도착" 전이를 감지해 같은 알림 id로 재표시(교체)한다.

**Tech Stack:** Spring Boot(JPA·Flyway·MockMvc) / Vanilla JS(Vitest) / Flutter(flutter_test, flutter_local_notifications)

**스펙:** `docs/superpowers/specs/2026-07-27-voice-ok-display-design.md`

## Global Constraints

- 이름 고정 — DB·API `voice_ok_at`, 상태머신 명령 `SEND_OK`, 앱 `voiceOkAt`·`isVoiceOk`, 도메인 `markVoiceOk`.
- 문구 원문 고정 — 알림 본문 `"HH:MM 발생 · 낙상자가 괜찮다고 말한 낙상 사고입니다"`, 목록 trailing `"괜찮다고 말함"`(초록·bold), 상세 행 라벨 `"음성 확인"`, 값 `"낙상자가 괜찮다고 말했습니다 (시각)"`.
- 조기 응답 원칙(스펙 2절 4항) — «"괜찮아"가 원본 전송(5초) 전에 나오면 바로 POST하지 않고 응답 시각만 들고 있다가 5초 원본 payload에 `voice_ok_at`을 실어 한 번에 보낸다.» "5초 내 회복 = 기록 없음" 동작이 깨지면 안 된다.
- 병합 불변식 — 기존 값이 null일 때만 쓴다. 쓸 것이 없으면 저장하지 않는다. 푸시는 201에만.
- 범위 밖 — 보호자 웹 배지, 웹 푸시 문구, 119 신고의 알림 갱신, 감지 페이지 화면 변경(RESOLVED 상태 문구 그대로), 큐 코드 변경.
- 새 소스 파일 첫 줄은 한국어 역할 주석(SQL은 `--`, Dart/JS는 `//`).
- 정적 타입 단계(Dart·Java)에서는 컴파일 에러가 곧 "실패하는 테스트" 확인이다.
- 커밋 메시지는 한국어 `feat:`/`docs:` 프리픽스, 푸터 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- 테스트 실행 위치 — backend `cd backend && ./gradlew test`, web `cd web && npm test`, app `cd app && flutter test`.

---

### Task 1: 백엔드 `voice_ok_at` — 마이그레이션·DTO·병합

**Files:**
- Create: `backend/src/main/resources/db/migration/V3__add_voice_ok_at.sql`
- Modify: `backend/src/main/java/com/weniv/falls/domain/FallEvent.java`
- Modify: `backend/src/main/java/com/weniv/falls/dto/FallEventRequest.java`
- Modify: `backend/src/main/java/com/weniv/falls/dto/FallEventResponse.java`
- Modify: `backend/src/main/java/com/weniv/falls/service/FallService.java`
- Test: `backend/src/test/java/com/weniv/falls/FallApiTest.java`

**Interfaces:**
- Consumes: 기존 `POST /api/falls/` 생성·중복 병합 흐름, `FallEvent.markReported119(Instant)` 패턴.
- Produces: 요청·응답 JSON 필드 `voice_ok_at`(ISO-8601, nullable) — Task 3의 전송과 Task 4의 앱 파싱이 이 계약을 쓴다. `FallEvent.markVoiceOk(Instant)`, `getVoiceOkAt()`.

- [ ] **Step 1: 실패하는 테스트 5건 추가**

`FallApiTest.java`의 `fallPayloadReported` 헬퍼 아래에 헬퍼 1개, 파일 끝(기존 `duplicate_post_without_reported_119_at_keeps_existing_value` 뒤)에 테스트 5건을 추가한다. 파일 첫 줄 요약 주석의 `신고 병합` 부분은 `신고·괜찮음 병합`으로 바꾼다.

```java
    private String fallPayloadVoiceOk(String okAt) {
        return "{\"room_name\": \"안방\", \"room_number\": 1, "
            + "\"occurred_at\": \"2026-07-23T03:00:00Z\", \"confidence\": 0.9, "
            + "\"voice_ok_at\": \"" + okAt + "\"}";
    }
```

```java
    @Test
    void post_with_voice_ok_at_creates_row_with_it() throws Exception {
        // 5초 전 조기 응답 — 원본 payload에 voice_ok_at이 동승해 201로 생성되는 경로
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadVoiceOk("2026-07-23T03:00:03Z")))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.voice_ok_at").value("2026-07-23T03:00:03Z"))
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        long id = ((Number) JsonPath.read(body, "$.id")).longValue();
        assertThat(fallEventRepository.findById(id).orElseThrow().getVoiceOkAt())
            .isEqualTo(Instant.parse("2026-07-23T03:00:03Z"));
    }

    @Test
    void duplicate_post_merges_voice_ok_at_and_sends_no_push() throws Exception {
        // 정상 경로 — 5s 원본 201 뒤에 응답 재-POST가 200으로 병합된다
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        int firstId = JsonPath.read(body, "$.id");
        clearInvocations(pushService);

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadVoiceOk("2026-07-23T03:00:12Z")))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.id").value(firstId))
            .andExpect(jsonPath("$.voice_ok_at").value("2026-07-23T03:00:12Z"));

        assertThat(fallEventRepository.count()).isEqualTo(1);
        verify(pushService, never()).sendToGuardianAsync(any());   // 200 병합은 푸시가 없다
    }

    @Test
    void voice_ok_at_is_immutable_once_set() throws Exception {
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadVoiceOk("2026-07-23T03:00:12Z")))
            .andExpect(status().isCreated());

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadVoiceOk("2026-07-23T03:00:59Z")))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.voice_ok_at").value("2026-07-23T03:00:12Z"));   // 첫 값 보존
    }

    @Test
    void duplicate_post_without_voice_ok_at_keeps_existing_value() throws Exception {
        // 오프라인 큐가 응답 이후 원본을 재전송해도 응답 시각이 지워지면 안 된다
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadVoiceOk("2026-07-23T03:00:12Z")))
            .andExpect(status().isCreated());

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.voice_ok_at").value("2026-07-23T03:00:12Z"));
    }

    @Test
    void merge_applies_voice_ok_and_reported_119_independently() throws Exception {
        // 상태머신 정상 경로에서는 공존하지 않지만, 서버 병합은 필드별로 독립이어야 한다
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated());

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadReported("2026-07-23T03:00:20Z")))
            .andExpect(status().isOk());

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadVoiceOk("2026-07-23T03:00:12Z")))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.voice_ok_at").value("2026-07-23T03:00:12Z"))
            .andExpect(jsonPath("$.reported_119_at").value("2026-07-23T03:00:20Z"));
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && ./gradlew test --tests 'com.weniv.falls.FallApiTest'`
Expected: 신규 5건 컴파일 에러(`getVoiceOkAt` 미정의). 컴파일 에러가 곧 RED다.

- [ ] **Step 3: 구현**

`V3__add_voice_ok_at.sql` 생성.

```sql
-- 낙상자가 음성으로 "괜찮아"라고 답한 시각 — null이면 응답 없음
ALTER TABLE fall_event ADD COLUMN voice_ok_at TIMESTAMPTZ;
```

`FallEvent.java` — `reported119At` 필드 선언 아래에 컬럼 추가.

```java
    @Column(name = "voice_ok_at")
    private Instant voiceOkAt;
```

`markReported119` 메서드 아래에 추가.

```java
    // 낙상자가 "괜찮아"라고 답한 첫 시각을 보존한다 — markReported119와 같은 멱등 패턴
    public void markVoiceOk(Instant at) {
        if (voiceOkAt == null && at != null) {
            voiceOkAt = at.truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        }
    }
```

getter 목록 끝에 추가.

```java
    public Instant getVoiceOkAt() { return voiceOkAt; }
```

`FallEventRequest.java` — 마지막 컴포넌트 `reported119At` 뒤에 추가(레코드라 닫는 괄호 위치 주의).

```java
    @JsonProperty("reported_119_at")
    OffsetDateTime reported119At,

    @JsonProperty("voice_ok_at")
    OffsetDateTime voiceOkAt) {
```

`FallEventResponse.java` — 컴포넌트와 `from` 둘 다.

```java
    @JsonProperty("acknowledged_at") Instant acknowledgedAt,
    @JsonProperty("reported_119_at") Instant reported119At,
    @JsonProperty("voice_ok_at") Instant voiceOkAt) {

    public static FallEventResponse from(FallEvent event) {
        return new FallEventResponse(event.getId(), event.getRoomName(), event.getRoomNumber(),
            event.getOccurredAt(), event.getCreatedAt(), event.getConfidence(),
            event.getAcknowledgedAt(), event.getReported119At(), event.getVoiceOkAt());
    }
```

`FallService.java` — `create`의 `reported119At` 반영 블록 바로 아래에 추가.

```java
            if (request.voiceOkAt() != null) {
                event.markVoiceOk(request.voiceOkAt().toInstant());
            }
```

`merge`를 두 필드 독립 병합으로 교체(주석 포함 통째로).

```java
    // 시각 병합 — 각 필드는 기존 값이 null일 때만 쓴다 (mark*가 보장). 쓸 것이 없으면 저장도 없다.
    private FallEvent merge(FallEvent event, FallEventRequest request) {
        boolean changed = false;
        if (request.reported119At() != null && event.getReported119At() == null) {
            event.markReported119(request.reported119At().toInstant());
            changed = true;
        }
        if (request.voiceOkAt() != null && event.getVoiceOkAt() == null) {
            event.markVoiceOk(request.voiceOkAt().toInstant());
            changed = true;
        }
        return changed ? fallEventRepository.save(event) : event;
    }
```

- [ ] **Step 4: 통과 확인 + 전체 백엔드 회귀**

Run: `cd backend && ./gradlew test`
Expected: 전부 PASS (기존 43 + 신규 5).

- [ ] **Step 5: 커밋**

```bash
git add backend/src/main/resources/db/migration/V3__add_voice_ok_at.sql \
  backend/src/main/java/com/weniv/falls/domain/FallEvent.java \
  backend/src/main/java/com/weniv/falls/dto/FallEventRequest.java \
  backend/src/main/java/com/weniv/falls/dto/FallEventResponse.java \
  backend/src/main/java/com/weniv/falls/service/FallService.java \
  backend/src/test/java/com/weniv/falls/FallApiTest.java
git commit -m "feat: 낙상 이벤트에 괜찮음 응답 시각(voice_ok_at) — 생성 반영·병합 일반화

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: escalation.js — RESOLVED 전이에 `SEND_OK` 명령

**Files:**
- Modify: `web/js/escalation.js:51-58` (LISTENING), `web/js/escalation.js:72-81` (WAITING)
- Test: `web/tests/escalation.test.js`

**Interfaces:**
- Consumes: `createEscalation().update(detectorState, t)` → `{ state, commands, statusText }`.
- Produces: `commands`에 새 명령 문자열 `"SEND_OK"` — RESOLVED 전이 프레임에 `"MIC_OFF"`보다 앞서 정확히 1회. Task 3의 배선이 이 명령을 소비한다.

- [ ] **Step 1: 실패하는 테스트 4건 추가**

`escalation.test.js`의 `describe` 블록 끝에 추가한다.

```js
  it("질문 전 '괜찮아'(RESOLVED)에 SEND_OK가 MIC_OFF와 함께 정확히 1회 나간다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000, { 4000: "heardOk" }),
      ...alerted(6000, 26000),
    ]);

    expect(r.times("SEND_OK")).toEqual([4000]);
    expect(r.times("MIC_OFF")).toEqual([4000]);
    expect(r.times("REPORT")).toEqual([]);
  });

  it("질문 후 대기 중 '괜찮아'(WAITING→RESOLVED)에도 SEND_OK가 1회 나간다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded", 15000: "heardOk" }),
    ]);

    expect(r.times("SEND_OK")).toEqual([15000]);
  });

  it("무응답 신고(REPORTED) 경로에는 SEND_OK가 없다", () => {
    const esc = createEscalation();
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded" }),
    ]);

    expect(r.times("SEND_OK")).toEqual([]);
    expect(r.times("REPORT")).toEqual([21000]);
  });

  it("RESOLVED 후 재무장 전에 heardOk가 또 와도 SEND_OK는 한 번뿐이다", () => {
    const esc = createEscalation();
    // 15000에 해제된 뒤 16000의 heardOk는 늦게 도착한 STT 결과다 — 중복 전송이 없어야 한다
    const r = run(esc, [
      ...standing(0, 1000),
      ...fallen(1000, 6000),
      ...alerted(6000, 26000, { 11500: "ttsEnded", 15000: "heardOk", 16000: "heardOk" }),
    ]);

    expect(r.times("SEND_OK")).toEqual([15000]);
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd web && npx vitest run tests/escalation.test.js`
Expected: 신규 4건 중 3건 FAIL (`SEND_OK` 기대 시각 배열이 빈 배열) — "무응답 경로에 없다"만 우연히 PASS.

- [ ] **Step 3: 구현 — 전이 2곳에 명령 추가**

`escalation.js` LISTENING 케이스.

```js
        case "LISTENING":
          if (heardOk) {
            state = "RESOLVED"; // 질문(10s) 전이면 질문도 생략된다
            commands.push("SEND_OK", "MIC_OFF");
          } else if (t - startedAt >= c.QUESTION_AT) {
            state = "ASKING";
            commands.push("PLAY_QUESTION");
          }
          break;
```

WAITING 케이스.

```js
        case "WAITING":
          // 마감 프레임에 함께 도착한 heardOk는 응답으로 인정한다 — 대답은 마감 전에 나왔다
          if (heardOk) {
            state = "RESOLVED";
            commands.push("SEND_OK", "MIC_OFF");
          } else if (t - startedAt >= c.REPORT_AT) {
            state = "REPORTED";
            commands.push("REPORT", "MIC_OFF");
          }
          break;
```

- [ ] **Step 4: 통과 확인 + 웹 전체 회귀**

Run: `cd web && npm test`
Expected: 전부 PASS (기존 30 + 신규 4).

- [ ] **Step 5: 커밋**

```bash
git add web/js/escalation.js web/tests/escalation.test.js
git commit -m "feat: 에스컬레이션 RESOLVED 전이에 SEND_OK 명령

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: main.js 배선 — 응답 전송·조기 응답 동승

main.js는 DOM·네트워크 배선이라 기존 라운드와 같이 단위 테스트가 없다. 상태머신(Task 2)이 로직을 검증하고, 배선은 Task 7의 수동 검증이 밟는다.

**Files:**
- Modify: `web/js/main.js:52-54` (모듈 상태), `web/js/main.js:134-152` (전송 함수), `web/js/main.js:166-185` (fall payload), `web/js/main.js:190-201` (명령 분배)

**Interfaces:**
- Consumes: Task 2의 `"SEND_OK"` 명령, Task 1의 `voice_ok_at` API 필드, 기존 `postFall`·`queue.enqueue`·`flushQueue`·`lastFallPayload`.
- Produces: 없음 (말단 배선).

- [ ] **Step 1: 모듈 상태 추가**

`let lastFallingAt = null;` 선언(53행) 아래에 추가.

```js
let pendingVoiceOkAt = null; // 이 에피소드의 "괜찮아" 응답 시각 — 원본 전송 전이면 5s 원본에 동승한다
```

- [ ] **Step 2: 전송 함수 추가**

`reportEmergency` 정의 바로 아래에 추가.

```js
  // "괜찮아" 응답 — 원본이 이미 나갔으면 같은 payload에 응답 시각만 붙여 한 번 더 보낸다.
  // 원본 전송 전(5초 이전 조기 응답)이면 시각만 들고 있다가 원본 payload에 동승시킨다 —
  // 즉시 POST하면 "5초 내 회복 = 기록 없음" 동작이 깨진다.
  const sendVoiceOk = (t) => {
    pendingVoiceOkAt = t;
    if (!lastFallPayload) return; // 원본 미전송 — 확정(5s) 시 payload에 실려 나간다
    const payload = {
      ...lastFallPayload,
      voice_ok_at: new Date(performance.timeOrigin + t).toISOString(),
    };
    postFall(payload)
      .then(() => flushQueue())
      .catch(() => {
        // 응답 기록도 같은 큐를 탄다 — 연결이 돌아오면 재전송되고 서버가 병합한다
        queue.enqueue(payload);
        showBanner("전송 실패 — 저장해 두었다가 연결되면 다시 보냅니다");
      });
  };
```

- [ ] **Step 3: fall payload에 조기 응답 동승**

`if (fall)` 블록의 payload 생성을 다음으로 교체.

```js
      const payload = {
        room_name: room.name,
        room_number: room.number,
        occurred_at: new Date(performance.timeOrigin + fall.occurredAt).toISOString(),
        confidence: fall.confidence,
        // 5초 전에 이미 "괜찮아"가 나온 에피소드 — 응답 시각이 원본에 동승한다
        ...(pendingVoiceOkAt != null
          ? { voice_ok_at: new Date(performance.timeOrigin + pendingVoiceOkAt).toISOString() }
          : {}),
      };
```

- [ ] **Step 4: 명령 분배 — MIC_ON 리셋과 SEND_OK 처리**

명령 루프의 `MIC_ON` 분기에 리셋 한 줄을 추가하고, `REPORT` 분기 뒤에 `SEND_OK` 분기를 끼운다.

```js
      if (command === "MIC_ON") {
        lastFallPayload = null; // 새 에피소드 — 이전 낙상의 payload가 신고에 섞이면 안 된다
        pendingVoiceOkAt = null; // 이전 에피소드의 응답 시각도 함께 버린다
        speech.startListening();
      } else if (command === "PLAY_QUESTION") {
        speech.playQuestion();
      } else if (command === "REPORT") {
        reportEmergency(t);
      } else if (command === "SEND_OK") {
        sendVoiceOk(t);
      } else if (command === "MIC_OFF") {
        speech.stopListening();
      }
```

- [ ] **Step 5: 웹 전체 회귀**

Run: `cd web && npm test`
Expected: 전부 PASS (main.js는 테스트 대상이 아니지만 문법 오류가 import 체인으로 걸릴 수 있다).

- [ ] **Step 6: 커밋**

```bash
git add web/js/main.js
git commit -m "feat: 감지 페이지 괜찮음 응답 전송 — 조기 응답은 5초 원본에 동승

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: 앱 모델·알림 문구 — `voiceOkAt` 파싱과 본문 파생

**Files:**
- Modify: `app/lib/models.dart`
- Modify: `app/lib/notifications.dart`
- Test: `app/test/models_test.dart`, `app/test/notifications_test.dart`

**Interfaces:**
- Consumes: Task 1의 응답 JSON 키 `voice_ok_at`.
- Produces: `FallEvent.voiceOkAt`(DateTime?)·`FallEvent.isVoiceOk`(bool)·생성자 선택 인자 `voiceOkAt` — Task 5·6이 쓴다. `Notifications.body(FallEvent) → String`.

- [ ] **Step 1: 실패하는 테스트 추가**

`models_test.dart` — 파일 첫 줄 주석을 `// 서버 JSON → FallEvent 파싱 검증 — reported_119_at·voice_ok_at 유무`로 바꾸고 끝에 추가.

```dart
  test('voice_ok_at 키가 아예 없으면 괜찮음 응답이 없는 상태다', () {
    final e = FallEvent.fromJson(base);

    expect(e.voiceOkAt, isNull);
    expect(e.isVoiceOk, isFalse);
  });

  test('voice_ok_at이 있으면 로컬 시각으로 파싱되고 괜찮음 상태다', () {
    final e = FallEvent.fromJson({...base, 'voice_ok_at': '2026-07-27T03:00:12Z'});

    expect(e.isVoiceOk, isTrue);
    expect(e.voiceOkAt, DateTime.parse('2026-07-27T03:00:12Z').toLocal());
  });
```

`notifications_test.dart` — import에 `package:fall_guardian/models.dart` 추가, `main` 위에 헬퍼, 파일 끝에 테스트 2건.

```dart
FallEvent _event({DateTime? voiceOkAt}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 27, 12),
      createdAt: DateTime(2026, 7, 27, 12),
      confidence: 0.9,
      voiceOkAt: voiceOkAt,
    );
```

```dart
  test('괜찮음 응답이 없으면 확인 필요 문구다', () {
    expect(Notifications.body(_event()), '12:00 발생 · 확인이 필요합니다');
  });

  test('괜찮음 응답이 있으면 괜찮다고 말한 낙상 사고 문구다', () {
    expect(
      Notifications.body(_event(voiceOkAt: DateTime(2026, 7, 27, 12, 0, 12))),
      '12:00 발생 · 낙상자가 괜찮다고 말한 낙상 사고입니다',
    );
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/models_test.dart test/notifications_test.dart`
Expected: 컴파일 에러 (`voiceOkAt`·`isVoiceOk`·`body` 미정의). 컴파일 에러가 곧 RED다.

- [ ] **Step 3: 구현**

`models.dart` `FallEvent` — 필드·생성자·fromJson·getter를 `reported119At`과 나란히 추가.

```dart
  final DateTime? reported119At;
  final DateTime? voiceOkAt;
```

생성자 마지막 인자로 `this.voiceOkAt,` 추가 (`this.reported119At,` 뒤).

`fromJson`의 `reported119At:` 항목 뒤에 추가.

```dart
        voiceOkAt: json['voice_ok_at'] == null
            ? null
            : DateTime.parse(json['voice_ok_at'] as String).toLocal(),
```

`isReported119` getter 아래에 추가.

```dart
  bool get isVoiceOk => voiceOkAt != null;
```

`notifications.dart` — `show`를 다음으로 교체(본문 추출 + 파생).

```dart
  // 알림 본문은 이벤트 상태에서 파생된다 — 괜찮음 응답이 도착한 뒤 같은 id로 다시 부르면
  // 트레이의 알림이 이 문구로 교체된다.
  @visibleForTesting
  static String body(FallEvent event) {
    final t = event.occurredAt;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return event.isVoiceOk
        ? '$time 발생 · 낙상자가 괜찮다고 말한 낙상 사고입니다'
        : '$time 발생 · 확인이 필요합니다';
  }

  static Future<void> show(FallEvent event) async {
    await _plugin.show(
      id: event.id,
      title: '${event.roomLabel}에서 낙상 감지',
      body: body(event),
      notificationDetails: details,
    );
  }
```

- [ ] **Step 4: 통과 확인**

Run: `cd app && flutter test test/models_test.dart test/notifications_test.dart`
Expected: 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/models.dart app/lib/notifications.dart \
  app/test/models_test.dart app/test/notifications_test.dart
git commit -m "feat: 앱 모델·알림 문구에 괜찮음 응답(voice_ok_at)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 트래커 확장 — 괜찮음 도착 감지와 알림 교체

**Files:**
- Modify: `app/lib/poller.dart`
- Modify: `app/lib/screens/fall_list.dart:31-43` (onEvents 배선만)
- Test: `app/test/poller_test.dart`

**Interfaces:**
- Consumes: Task 4의 `FallEvent.isVoiceOk`, 생성자 인자 `voiceOkAt`.
- Produces: `typedef PollDelta = ({List<FallEvent> fresh, List<FallEvent> newlyOk})`, `NewEventTracker.newEvents(List<FallEvent>) → PollDelta`, `FallPoller.onEvents`는 `(all, fresh, newlyOk)` 3인자 — Task 6이 이 화면 상태를 그대로 쓴다.

- [ ] **Step 1: 기존 테스트 수정 + 실패하는 테스트 3건 추가**

`poller_test.dart` — `ev` 헬퍼에 선택 인자 추가.

```dart
FallEvent ev(int id, {DateTime? voiceOkAt}) => FallEvent(
      id: id,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 17, 12),
      createdAt: DateTime(2026, 7, 17, 12),
      confidence: 0.9,
      voiceOkAt: voiceOkAt,
    );
```

기존 4개 테스트의 반환값 사용부를 record 필드로 바꾼다 — `tracker.newEvents([...])`가 `isEmpty`·`.map` 대상이던 곳은 전부 `.fresh`를 붙인다.

```dart
  test('최초 응답은 알림 없이 id만 저장한다', () {
    final tracker = NewEventTracker();

    // 로그인 직후 기존 이벤트 전부에 알림이 쏟아지면 안 된다
    expect(tracker.newEvents([ev(3), ev(2), ev(1)]).fresh, isEmpty);
    expect(tracker.lastSeenId, 3);
  });

  test('같은 응답이 반복되면 새 이벤트가 없다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    expect(tracker.newEvents([ev(3), ev(2), ev(1)]).fresh, isEmpty);
  });

  test('새 이벤트 2건이 오면 2건만 돌려준다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    final fresh = tracker.newEvents([ev(5), ev(4), ev(3), ev(2), ev(1)]).fresh;

    expect(fresh.map((e) => e.id), [5, 4]);
    expect(tracker.lastSeenId, 5);
  });

  test('최초 응답이 비어 있으면 그 다음 첫 이벤트는 새 이벤트다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([]);

    expect(tracker.newEvents([ev(1)]).fresh.map((e) => e.id), [1]);
  });
```

파일 끝에 신규 3건 추가.

```dart
  test('최초 응답의 괜찮음 이벤트는 newlyOk가 아니다', () {
    final tracker = NewEventTracker();

    // 로그인 직후 옛 괜찮음 이벤트로 알림 폭탄이 터지면 안 된다
    final delta = tracker.newEvents([ev(2, voiceOkAt: DateTime(2026, 7, 27, 12, 1)), ev(1)]);

    expect(delta.fresh, isEmpty);
    expect(delta.newlyOk, isEmpty);
  });

  test('이미 알린 이벤트에 괜찮음이 새로 붙으면 newlyOk로 정확히 1회 나온다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(1)]);
    tracker.newEvents([ev(1)]); // 프라이밍 뒤 한 번 더 — 아직 괜찮음 없음

    final delta = tracker.newEvents([ev(1, voiceOkAt: DateTime(2026, 7, 27, 12, 1))]);
    expect(delta.fresh, isEmpty);
    expect(delta.newlyOk.map((e) => e.id), [1]);

    // 다음 폴링에도 그대로 실려 오지만 다시 알리지 않는다
    final again = tracker.newEvents([ev(1, voiceOkAt: DateTime(2026, 7, 27, 12, 1))]);
    expect(again.newlyOk, isEmpty);
  });

  test('처음부터 괜찮음이 실려 온 새 이벤트는 fresh로만 나온다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(1)]);

    final delta = tracker.newEvents([ev(2, voiceOkAt: DateTime(2026, 7, 27, 12, 1)), ev(1)]);

    expect(delta.fresh.map((e) => e.id), [2]);
    expect(delta.newlyOk, isEmpty); // 첫 알림이 곧 괜찮음 문구다 — 두 번 뜨지 않는다
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/poller_test.dart`
Expected: 컴파일 에러 (`.fresh` 미정의 — 반환형이 아직 `List<FallEvent>`).

- [ ] **Step 3: 구현 — poller.dart**

`NewEventTracker`를 다음으로 교체하고, import 아래에 typedef를 둔다.

```dart
/// 폴링 1회분의 알림 대상. fresh는 처음 보는 이벤트, newlyOk는 이미 알린 이벤트에
/// 괜찮음 응답이 새로 도착한 것 — 같은 id로 알림을 다시 띄워 문구를 교체한다.
typedef PollDelta = ({List<FallEvent> fresh, List<FallEvent> newlyOk});

class NewEventTracker {
  int? _lastSeenId;
  bool _primed = false;
  final Set<int> _okSeen = {}; // 괜찮음을 이미 반영해 알린(또는 프라이밍한) 이벤트 id

  int? get lastSeenId => _lastSeenId;

  /// [events]는 서버가 준 최신순 목록이다. 마지막으로 본 id보다 큰 것만 새 이벤트다.
  /// 최초 호출(=로그인 직후)에는 기존 이벤트 알림 폭탄을 막기 위해 id만 저장하고 빈 결과를 준다.
  /// "최초 호출인가"는 id 저장 여부(`_lastSeenId == null`)와 별개로 `_primed`로 추적한다.
  /// 그래야 최초 응답이 마침 빈 목록이었던 경우에도, 그 다음 호출을 다시 최초 호출로
  /// 착각해 진짜 새 이벤트를 삼키지 않는다. 이 경우 lastSeenId는 아직 어떤 id도 보지
  /// 못했다는 뜻으로 null로 남는다.
  /// newlyOk는 이미 알린 이벤트 중 괜찮음이 이번에 처음 보인 것이다. fresh와 겹치지 않는다 —
  /// 처음부터 괜찮음이 실려 온 새 이벤트는 첫 알림이 곧 괜찮음 문구라 fresh로만 나간다.
  PollDelta newEvents(List<FallEvent> events) {
    final isFirstCall = !_primed;
    _primed = true;

    if (events.isEmpty) return (fresh: const [], newlyOk: const []);

    final maxId = events.map((e) => e.id).reduce((a, b) => a > b ? a : b);
    final okIds = events.where((e) => e.isVoiceOk).map((e) => e.id);

    if (isFirstCall) {
      _lastSeenId = maxId;
      _okSeen.addAll(okIds);
      return (fresh: const [], newlyOk: const []);
    }

    final fresh = _lastSeenId == null
        ? events
        : events.where((e) => e.id > _lastSeenId!).toList();
    final freshIds = fresh.map((e) => e.id).toSet();
    final newlyOk = events
        .where((e) => e.isVoiceOk && !_okSeen.contains(e.id) && !freshIds.contains(e.id))
        .toList();
    _lastSeenId = maxId;
    _okSeen.addAll(okIds);
    return (fresh: fresh, newlyOk: newlyOk);
  }
}
```

`FallPoller` — 콜백 타입과 `_tick`의 호출부를 바꾼다.

```dart
  final void Function(List<FallEvent> all, List<FallEvent> fresh, List<FallEvent> newlyOk)
      onEvents;
```

`_tick` 안의 두 줄 교체.

```dart
      final all = await api.listFalls();
      final delta = _tracker.newEvents(all);
      if (_consecutiveFailures >= _failuresBeforeBanner) onRecovered();
      _consecutiveFailures = 0;
      onEvents(all, delta.fresh, delta.newlyOk);
```

`fall_list.dart` — `onEvents` 배선을 3인자로 바꾸고 newlyOk도 같은 show를 호출.

```dart
      onEvents: (all, fresh, newlyOk) {
        for (final e in fresh) {
          Notifications.show(e);
        }
        // 괜찮음이 새로 도착한 이벤트 — 같은 id로 다시 띄워 트레이의 알림 문구를 교체한다
        for (final e in newlyOk) {
          Notifications.show(e);
        }
        if (!mounted) return;
        setState(() {
          _events = all;
          _loading = false;
          _error = null;
        });
      },
```

- [ ] **Step 4: 통과 확인 + 앱 전체 회귀**

Run: `cd app && flutter test`
Expected: 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/poller.dart app/lib/screens/fall_list.dart app/test/poller_test.dart
git commit -m "feat: 폴러가 괜찮음 도착을 감지해 같은 id로 알림 교체

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 목록 trailing·상세 행 — 인앱 표시

**Files:**
- Modify: `app/lib/screens/fall_list.dart:147-155` (trailing)
- Modify: `app/lib/screens/fall_detail.dart:150-152` (상태 행 아래)
- Create: `app/test/fall_list_test.dart`
- Test: `app/test/fall_detail_test.dart`

**Interfaces:**
- Consumes: Task 4의 `isVoiceOk`·`voiceOkAt`, Task 5의 3인자 `onEvents`(FallListScreen이 이미 배선됨).
- Produces: 없음 (말단 화면).

- [ ] **Step 1: 실패하는 테스트 추가**

새 파일 `app/test/fall_list_test.dart`.

```dart
// 목록 trailing 우선순위 검증 — 119 신고됨 > 괜찮다고 말함 > 확인함/미확인

import 'package:fall_guardian/api.dart';
import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/screens/fall_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends Api {
  _FakeApi(this.events);

  final List<FallEvent> events;

  @override
  Future<List<FallEvent>> listFalls() async => events;
}

FallEvent _event({DateTime? voiceOkAt, DateTime? reported119At}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 27, 12),
      createdAt: DateTime(2026, 7, 27, 12),
      confidence: 0.9,
      voiceOkAt: voiceOkAt,
      reported119At: reported119At,
    );

Future<void> _pumpList(WidgetTester tester, FallEvent event) async {
  await tester.pumpWidget(MaterialApp(home: FallListScreen(api: _FakeApi([event]))));
  await tester.pump(); // listFalls 완료
  await tester.pump(); // setState 반영
}

void main() {
  testWidgets('괜찮다고 답한 이벤트는 trailing이 "괜찮다고 말함"이다', (tester) async {
    await _pumpList(tester, _event(voiceOkAt: DateTime(2026, 7, 27, 12, 0, 12)));

    expect(find.text('괜찮다고 말함'), findsOneWidget);
    expect(find.text('미확인'), findsNothing);
  });

  testWidgets('신고와 괜찮음이 둘 다면 119 신고됨이 이긴다', (tester) async {
    // 상태머신 정상 경로엔 없지만, 표시 우선순위는 안전 쪽이 이겨야 한다
    await _pumpList(
      tester,
      _event(
        voiceOkAt: DateTime(2026, 7, 27, 12, 0, 12),
        reported119At: DateTime(2026, 7, 27, 12, 0, 20),
      ),
    );

    expect(find.text('119 신고됨'), findsOneWidget);
    expect(find.text('괜찮다고 말함'), findsNothing);
  });
}
```

`fall_detail_test.dart` — `_event` 헬퍼를 확장하고 테스트 2건 추가. 파일 첫 줄 주석은 `// 상세 화면 검증 — 119 버튼 잠금·괜찮음 음성 확인 행`으로 바꾼다.

```dart
FallEvent _event({DateTime? reported119At, DateTime? voiceOkAt}) => FallEvent(
      id: 1,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 27, 12),
      createdAt: DateTime(2026, 7, 27, 12),
      confidence: 0.9,
      reported119At: reported119At,
      voiceOkAt: voiceOkAt,
    );
```

```dart
  testWidgets('괜찮다고 답한 이벤트는 음성 확인 행이 보인다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FallDetailScreen(
        api: _FakeApi(),
        event: _event(voiceOkAt: DateTime(2026, 7, 27, 12, 0, 12)),
      ),
    ));
    await tester.pump();

    expect(find.text('음성 확인'), findsOneWidget);
    expect(find.text('낙상자가 괜찮다고 말했습니다 (2026년 7월 27일 12:00:12)'), findsOneWidget);
  });

  testWidgets('괜찮음 응답이 없으면 음성 확인 행이 없다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FallDetailScreen(api: _FakeApi(), event: _event()),
    ));
    await tester.pump();

    expect(find.text('음성 확인'), findsNothing);
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/fall_list_test.dart test/fall_detail_test.dart`
Expected: 신규 4건 FAIL (문구 위젯을 찾지 못함 — findsNothing 계열만 우연히 PASS일 수 있다).

- [ ] **Step 3: 구현**

`fall_list.dart` trailing 교체 — 우선순위 119 > 괜찮음 > 확인 여부.

```dart
                                trailing: e.isReported119
                                    ? Text(
                                        '119 신고됨',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : e.isVoiceOk
                                        ? const Text(
                                            '괜찮다고 말함',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : Text(e.isAcknowledged ? '확인함' : '미확인'),
```

`fall_detail.dart` — 상태 `_row` 바로 아래에 추가.

```dart
          if (_event.isVoiceOk)
            _row('음성 확인', '낙상자가 괜찮다고 말했습니다 (${_fmt(_event.voiceOkAt!)})'),
```

- [ ] **Step 4: 통과 확인 + 앱 전체 회귀**

Run: `cd app && flutter test`
Expected: 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/screens/fall_list.dart app/lib/screens/fall_detail.dart \
  app/test/fall_list_test.dart app/test/fall_detail_test.dart
git commit -m "feat: 앱 목록·상세에 괜찮다고 말함 표시

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 수동 검증 문서 + 전 스위트 최종 확인

**Files:**
- Modify: `docs/manual-verification.md` (9절 뒤에 10절 추가)

**Interfaces:**
- Consumes: Task 1~6의 전 구현 (검증 절차가 참조).
- Produces: 없음 (문서).

- [ ] **Step 1: 10절 추가 + 도입부 개수 갱신**

파일 3행의 자동 테스트 요약 `(backend JUnit 43 / web Vitest 30 / app 11)`을 이번 라운드 후의 실측 개수로 갱신한다(Step 2에서 확인한 숫자를 쓴다). 다른 절의 숫자는 각 라운드 당시의 역사 기록이므로 건드리지 않는다.

파일 끝(9절 뒤)에 추가.

````markdown
## 10. 괜찮음 응답 앱 표시 (2026-07-27 라운드)

자동 테스트가 대신 밟는 것 — SEND_OK 전이(web 에스컬레이션 4), voice_ok_at 병합·불변·독립(backend 5), 모델 파싱·알림 문구·트래커·목록·상세(app 11). 남은 것은 실제 알림 교체와 조기 응답 타이밍이다. 9절과 같은 준비(Chrome·마이크·매트리스)로 한다.

- [ ] 넘어진 뒤 앱 알림이 먼저 뜬다 — "HH:MM 발생 · 확인이 필요합니다"
- [ ] 질문("괜찮으세요?") 뒤 "괜찮아"라고 답하면 감지 페이지에 "응답 확인 — 신고 안 함"이 뜬다
- [ ] 5초 안에 **같은 알림이 "낙상자가 괜찮다고 말한 낙상 사고입니다"로 교체**된다 — 트레이의 알림이 2건으로 늘면 안 된다
- [ ] 앱 목록 trailing에 초록 **"괜찮다고 말함"**이 뜬다 ("119 신고됨"이 아니다)
- [ ] **앱 상세를 열어 둔 채** 응답이 도착하면 5초 안에 "음성 확인 — 낙상자가 괜찮다고 말했습니다 (시각)" 행이 나타난다
- [ ] (새 에피소드) 넘어지자마자 "괜찮아" 하고 **누운 채로 있으면** — 5초에 만들어진 기록에 응답이 이미 실려, 첫 알림부터 괜찮음 문구다
- [ ] (새 에피소드) 넘어지자마자 "괜찮아" 하고 **5초 전에 일어나면** — 기록도 알림도 없다 ("5초 내 회복 = 없던 일" 유지)
- [ ] 보호자 페이지 목록은 변화 없다 (이번 범위 밖 — 배지가 생기면 버그다)

DB는 9절 쿼리에 `voice_ok_at`을 더해 본다.

```bash
psql -d fall_detection -c \
  "select id, occurred_at, voice_ok_at, reported_119_at from fall_event order by id desc limit 3;"
```
````

- [ ] **Step 2: 세 스위트 전체 실행**

Run: `cd backend && ./gradlew test && cd ../web && npm test && cd ../app && flutter test`
Expected: 전부 PASS (backend 48 / web 34 / app 20 안팎 — 숫자가 다르면 어디가 늘고 줄었는지 확인).

- [ ] **Step 3: 커밋**

```bash
git add docs/manual-verification.md
git commit -m "docs: 수동 검증에 괜찮음 응답 표시 절차(10절)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
