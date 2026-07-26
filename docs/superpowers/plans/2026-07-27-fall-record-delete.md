# 낙상 기록 삭제 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 보호자가 이미 확인한 낙상 기록을 보호자 페이지(웹)와 앱(iOS) 양쪽에서 완전 삭제할 수 있게 한다.

**Architecture:** 서버에 `DELETE /api/falls/{id}/` 엔드포인트 하나를 만들고 웹과 앱이 같이 쓴다. 소유권 조회(`findByIdAndGuardianId`)를 먼저 해 남의 기록은 확인 여부와 무관하게 404를 주고, 그 다음 확인 여부를 봐서 미확인이면 400으로 거절한다. DB 행을 실제로 지우므로 스키마 변경(Flyway 마이그레이션)은 없다.

**Tech Stack:** Spring Boot 3(Java, JUnit 5 + MockMvc + AssertJ, 실 PostgreSQL), 바닐라 ES 모듈(웹), Flutter/Dart(iOS 앱).

설계 근거는 `docs/superpowers/specs/2026-07-27-fall-record-delete-design.md`에 있다. 판단이 갈리면 그 문서가 기준이다.

## Global Constraints

- **한국어** — 사용자에게 보이는 문구와 새로 쓰는 주석은 전부 한국어다. 한국어 문장은 마침표로 끝낸다(뒤에 목록이 와도 콜론으로 끝내지 않는다).
- **완전 삭제** — `deleted_at` 같은 컬럼을 만들지 않는다. Flyway 마이그레이션 파일을 추가하지 않는다. `backend/src/main/resources/db/migration/`은 이번 작업에서 건드리지 않는다.
- **404가 400보다 먼저다** — 소유권 조회 → 확인 여부 검사 순서. 뒤집으면 남의 기록의 존재 여부와 확인 상태가 새어나간다.
- **경로 끝 슬래시** — 기존 계약 그대로 `/api/falls/{id}/`. 슬래시를 빼면 안 된다.
- **에러 문구 원문** — 서버가 한국어 문구를 내리고 클라이언트는 그대로 보여준다. 클라이언트에서 문구를 새로 지어내지 않는다.
- **에러 메시지 상수** — `FallService.UNACKNOWLEDGED_DELETE_MESSAGE = "확인하지 않은 낙상은 삭제할 수 없습니다."` 테스트는 문자열을 다시 쓰지 말고 이 상수를 참조한다.
- **새 파일 없음** — 이번 작업은 기존 파일 수정만 한다. 따라서 "새 소스 파일 첫 줄 한국어 헤더 주석" 규칙은 적용될 일이 없다.
- **수술적 변경** — 내 변경이 틀리게 만든 주석만 고친다. 그 외 인접 코드·주석·포맷은 손대지 않는다.
- **커밋** — 태스크당 1커밋. 한국어 semantic commit 메시지에 아래 트레일러를 붙인다.
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  ```

**사전 조건.** 백엔드 테스트는 실제 PostgreSQL을 쓴다. 없으면 만든다.

```bash
createdb fall_detection_test   # 이미 있으면 "already exists"가 나고 그냥 넘어가면 된다
```

---

## File Structure

| 파일 | 역할 | 태스크 |
|---|---|---|
| `backend/src/main/java/com/weniv/falls/service/FallService.java` | 소유권·확인 여부 판정 후 행 삭제. 에러 문구 상수 보유. | 1 |
| `backend/src/main/java/com/weniv/falls/controller/FallController.java` | `DELETE` 매핑과 204 응답. | 1 |
| `backend/src/test/java/com/weniv/falls/FallApiTest.java` | 삭제 계약 3종 검증. | 1 |
| `web/js/api.js` | `deleteFall(id)` — 400 본문의 서버 문구를 살려 던진다. | 2 |
| `web/js/guardian.js` | 확인 상태에 따라 "확인"/"삭제" 버튼을 갈라 붙인다. | 2 |
| `app/lib/api.dart` | `deleteFall(int id)` — 400 본문의 서버 문구를 살려 던진다. | 3 |
| `app/lib/screens/fall_detail.dart` | 삭제 버튼·확인 다이얼로그. 성공 시 `pop()`. | 3 |
| `app/lib/screens/fall_list.dart` | `pop` 결과가 null이면 서버에서 다시 받아 그린다. | 3 |
| `docs/backend-architecture.html` | 엔드포인트 표에 한 행 추가. | 4 |
| `docs/manual-verification.md` | 웹·앱 수동 검증 절차. | 4 |
| `README.md` | 백엔드 테스트 개수 36 → 39. | 4 |
| `checklist.md`, `context-notes.md` | 라운드 기록과 결정 근거. | 4 |

태스크 1이 계약을 만들고, 2와 3이 그 계약의 소비자다. 2와 3은 서로 독립이라 순서를 바꿔도 되지만 둘 다 1에 의존한다.

---

## Task 1: 서버 — `DELETE /api/falls/{id}/`

**Files:**
- Modify: `backend/src/main/java/com/weniv/falls/service/FallService.java`
- Modify: `backend/src/main/java/com/weniv/falls/controller/FallController.java`
- Test: `backend/src/test/java/com/weniv/falls/FallApiTest.java`

**Interfaces:**
- Consumes: `FallEventRepository.findByIdAndGuardianId(Long id, Long guardianId) → Optional<FallEvent>` (이미 있음), `FallEvent.getAcknowledgedAt() → Instant` (이미 있음), `NotFoundException`, `FieldValidationException(Map<String, List<String>>)`.
- Produces:
  - `FallService.UNACKNOWLEDGED_DELETE_MESSAGE` — `public static final String`, 값은 `"확인하지 않은 낙상은 삭제할 수 없습니다."`
  - `FallService.delete(Guardian guardian, Long id) → void`
  - HTTP 계약 — `DELETE /api/falls/{id}/` → 204(성공, 본문 없음) / 400(`{"non_field_errors": ["…"]}`) / 404(`{"detail": "찾을 수 없습니다."}`) / 401(토큰 없음). 태스크 2·3이 이 계약에 의존한다.

- [ ] **Step 1: 실패하는 테스트 3개를 쓴다**

`FallApiTest.java`의 import 블록에 두 줄을 더한다. 정적 import는 알파벳 순서라 `delete`가 `get`보다 앞이다.

```java
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
```

그리고 일반 import 블록에 하나 더한다. `com.weniv.falls.service.PushService` 바로 위가 자리다.

```java
import com.weniv.falls.service.FallService;
```

파일 첫 줄 헤더 주석에 삭제를 더한다. 기존 줄을 통째로 바꾼다.

```java
// 낙상 API 계약 테스트 — 목록 격리·최신순·guardian 강제·acknowledge 멱등·중복 POST 200·푸시 1회/0회·삭제 204/400/404
```

클래스 맨 끝(`post_accepts_offset_and_stores_utc` 다음, 닫는 `}` 앞)에 테스트 3개를 붙인다.

```java
    @Test
    void delete_acknowledged_event_204_and_disappears_from_list() throws Exception {
        FallEvent event = makeEvent(guardian);
        mockMvc.perform(authed(post("/api/falls/" + event.getId() + "/acknowledge/"), guardian))
            .andExpect(status().isOk());

        mockMvc.perform(authed(delete("/api/falls/" + event.getId() + "/"), guardian))
            .andExpect(status().isNoContent());

        assertThat(fallEventRepository.findById(event.getId())).isEmpty();
        mockMvc.perform(authed(get("/api/falls/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void delete_unacknowledged_event_400_and_row_kept() throws Exception {
        FallEvent event = makeEvent(guardian);

        mockMvc.perform(authed(delete("/api/falls/" + event.getId() + "/"), guardian))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.non_field_errors[0]")
                .value(FallService.UNACKNOWLEDGED_DELETE_MESSAGE));

        assertThat(fallEventRepository.findById(event.getId())).isPresent();
    }

    @Test
    void delete_other_users_event_is_404_regardless_of_acknowledgement() throws Exception {
        // 확인 여부를 소유권보다 먼저 보면, 남의 미확인 기록에 400이 나가면서
        // "그 id는 존재하고 아직 미확인"이라는 사실이 새어나간다. 둘 다 404여야 한다.
        FallEvent theirsAcked = makeEvent(other, "안방", 1);
        mockMvc.perform(authed(post("/api/falls/" + theirsAcked.getId() + "/acknowledge/"), other))
            .andExpect(status().isOk());
        FallEvent theirsUnacked = makeEvent(other, "부엌", 2);

        mockMvc.perform(authed(delete("/api/falls/" + theirsAcked.getId() + "/"), guardian))
            .andExpect(status().isNotFound());
        mockMvc.perform(authed(delete("/api/falls/" + theirsUnacked.getId() + "/"), guardian))
            .andExpect(status().isNotFound());

        assertThat(fallEventRepository.count()).isEqualTo(2);   // 남의 기록은 하나도 안 지워졌다
    }
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd backend && ./gradlew test --tests 'com.weniv.falls.FallApiTest'
```

기대하는 결과.

- `delete_acknowledged_event_204_and_disappears_from_list` — **FAIL.** `Status expected:<204> but was:<404>`
- `delete_unacknowledged_event_400_and_row_kept` — **FAIL.** `Status expected:<400> but was:<404>`
- `delete_other_users_event_is_404_regardless_of_acknowledgement` — **PASS.** 이건 정상이다. `DELETE /api/falls/{id}/`를 받을 핸들러가 아직 없어서 `DispatcherServlet`이 404를 내고, 테스트가 우연히 통과한다. 구현이 들어간 뒤에야 이 테스트가 진짜 소유권을 검증하게 된다. 지금 통과한다고 건너뛰면 안 된다.

- [ ] **Step 3: `FallService`에 삭제를 구현한다**

import 두 줄을 더한다. 둘 다 알파벳 순서를 지킨다 — `java.util.Map`은 `java.util.List`와 `java.util.Optional` **사이**에, `FieldValidationException`은 같은 패키지의 `NotFoundException` **위**에 넣는다.

```java
import java.util.Map;
```

```java
import com.weniv.falls.error.FieldValidationException;
```

클래스 안, `CreateResult` 레코드 선언 바로 아래에 상수를 둔다.

```java
    public static final String UNACKNOWLEDGED_DELETE_MESSAGE = "확인하지 않은 낙상은 삭제할 수 없습니다.";
```

`acknowledge` 메서드 바로 아래에 `delete`를 더한다.

```java
    public void delete(Guardian guardian, Long id) {
        // 소유권을 먼저 본다 — 확인 여부를 먼저 보면 남의 미확인 기록에 400이 나가면서
        // "그 id는 존재하고 아직 미확인"이라는 사실이 새어나간다.
        FallEvent event = fallEventRepository.findByIdAndGuardianId(id, guardian.getId())
            .orElseThrow(NotFoundException::new);
        if (event.getAcknowledgedAt() == null) {
            throw new FieldValidationException(
                Map.of("non_field_errors", List.of(UNACKNOWLEDGED_DELETE_MESSAGE)));
        }
        fallEventRepository.delete(event);
    }
```

파일 첫 줄 헤더 주석에 삭제를 더한다. 기존 줄을 통째로 바꾼다.

```java
// 낙상 등록·조회·확인·삭제 — 오프라인 큐 재전송 멱등성 (같은 낙상 재수신 → 기존 행, 푸시 없음)
```

- [ ] **Step 4: `FallController`에 매핑을 더한다**

import 한 줄을 더한다(`GetMapping` 위가 `DeleteMapping`의 자리다).

```java
import org.springframework.web.bind.annotation.DeleteMapping;
```

`acknowledge` 메서드 아래, 클래스 닫는 `}` 앞에 더한다.

```java
    @DeleteMapping("/api/falls/{id}/")
    public ResponseEntity<Void> delete(@AuthenticationPrincipal Guardian guardian,
                                       @PathVariable Long id) {
        fallService.delete(guardian, id);
        return ResponseEntity.noContent().build();   // 204 — 방 삭제와 같은 모양
    }
```

- [ ] **Step 5: 테스트를 돌려 통과를 확인한다**

```bash
cd backend && ./gradlew test --tests 'com.weniv.falls.FallApiTest'
```

기대: 12개 전부 PASS(기존 9 + 신규 3).

- [ ] **Step 6: 백엔드 전체를 돌려 회귀가 없는지 본다**

```bash
cd backend && ./gradlew test
```

기대: 39개 PASS. 이전이 36개였으므로 정확히 3개가 늘어야 한다. 숫자가 다르면 멈추고 원인을 본다.

- [ ] **Step 7: 커밋**

```bash
git add backend/src/main/java/com/weniv/falls/service/FallService.java \
        backend/src/main/java/com/weniv/falls/controller/FallController.java \
        backend/src/test/java/com/weniv/falls/FallApiTest.java
git commit -F - <<'EOF'
feat: 낙상 기록 삭제 API — 확인한 기록만, 소유권 판정이 확인 여부보다 먼저

DELETE /api/falls/{id}/ 를 더한다. 소유권 조회를 먼저 해 남의 기록은 확인
여부와 무관하게 404다. 확인 여부를 먼저 보면 400이 나가면서 그 id의 존재와
확인 상태가 새어나간다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 2: 보호자 페이지 — 확인한 기록에 삭제 버튼

**Files:**
- Modify: `web/js/api.js`
- Modify: `web/js/guardian.js`

**Interfaces:**
- Consumes: 태스크 1의 HTTP 계약. `web/js/api.js`의 기존 `authFetch(path, options)`와 `firstErrorMessage(res, fallback)`(둘 다 모듈 내부 함수, export 아님).
- Produces: `export async function deleteFall(id) → Promise<void>` — 204면 정상 반환, 그 밖에는 서버 문구를 담은 `Error`를 던진다.

**이 태스크에 자동 테스트는 없다.** `web/tests/`는 순수 로직(`detector`·`queue`·`pollBanner`)만 다루고 `guardian.js`는 DOM·네트워크 코드라 테스트 하네스가 없다. 설계 문서 7절에서 정한 대로 새 DOM 테스트를 만들지 않는다. 검증은 회귀(`npm test`)와 태스크 4의 수동 절차로 한다.

- [ ] **Step 1: `web/js/api.js`에 `deleteFall`을 더한다**

`acknowledgeFall` 바로 아래에 붙인다(낙상 관련 함수끼리 모아 둔 자리다).

```js
export async function deleteFall(id) {
  const res = await authFetch(`/api/falls/${id}/`, { method: "DELETE" });
  // 미확인 기록 삭제는 서버가 400 + 한국어 문구로 거절한다. 문구를 새로 짓지 말고 그대로 올린다.
  if (!res.ok) {
    throw new Error(await firstErrorMessage(res, `기록을 삭제하지 못했습니다 (${res.status}).`));
  }
}
```

- [ ] **Step 2: `web/js/guardian.js`에서 `deleteFall`을 import 한다**

기존 import 블록은 알파벳 순서다. `deletePushDevice` 위가 `deleteFall`의 자리다.

```js
  deleteFall,
```

- [ ] **Step 3: 버튼 분기를 갈래로 바꾼다**

`refreshFalls()` 안의 기존 블록을 바꾼다. 바꿀 대상은 이 부분이다.

```js
    li.append(label);
    if (!f.acknowledged_at) {
      const btn = document.createElement("button");
      btn.textContent = "확인";
      btn.addEventListener("click", () =>
        acknowledgeFall(f.id).then(refreshFalls).catch(showError)
      );
      li.append(btn);
    }
    el.fallList.append(li);
```

바꾼 뒤 모습이다. 한 항목에 버튼은 항상 하나다 — 미확인이면 "확인", 확인했으면 "삭제".

```js
    li.append(label);
    if (f.acknowledged_at) {
      const del = document.createElement("button");
      del.textContent = "삭제";
      del.addEventListener("click", () => {
        // 완전 삭제라 되돌릴 수 없다. 방 삭제와 같은 무게로 확인을 받는다.
        if (confirm(`${fmt(f.occurred_at)} ${f.room_name} ${f.room_number} 낙상 기록을 삭제할까요?`)) {
          deleteFall(f.id).then(refreshFalls).catch(showError);
        }
      });
      li.append(del);
    } else {
      const btn = document.createElement("button");
      btn.textContent = "확인";
      btn.addEventListener("click", () =>
        acknowledgeFall(f.id).then(refreshFalls).catch(showError)
      );
      li.append(btn);
    }
    el.fallList.append(li);
```

- [ ] **Step 4: 웹 테스트로 회귀를 확인한다**

```bash
cd web && npm test
```

기대: 기존 테스트 전부 PASS. 이 태스크는 `detector`·`queue`·`pollBanner` 어느 것도 건드리지 않으므로 개수와 결과가 그대로여야 한다. 하나라도 깨지면 멈추고 원인을 본다.

- [ ] **Step 5: 구문 오류가 없는지 확인한다**

`api.js`와 `guardian.js`는 브라우저 전역(`location`, `localStorage`, `document`)에 의존해서 Node로 실행할 수 없다. 파싱만 확인한다.

```bash
cd web && node --check js/api.js && node --check js/guardian.js && echo "구문 OK"
```

`web/package.json`에 `"type": "module"`이 있어서 `node --check`가 ES 모듈로 파싱한다(Node 25.8에서 확인). 기대: `구문 OK`. `SyntaxError`가 나오면 고친다.

- [ ] **Step 6: 커밋**

```bash
git add web/js/api.js web/js/guardian.js
git commit -F - <<'EOF'
feat: 보호자 페이지 낙상 기록 삭제 — 확인한 항목에만 삭제 버튼

한 항목에 버튼은 항상 하나다. 미확인이면 확인, 확인했으면 삭제.
되돌릴 수 없어 방 삭제와 같이 confirm()을 거친다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 3: 앱 — 상세 화면 삭제 버튼

**Files:**
- Modify: `app/lib/api.dart`
- Modify: `app/lib/screens/fall_detail.dart`
- Modify: `app/lib/screens/fall_list.dart`

**Interfaces:**
- Consumes: 태스크 1의 HTTP 계약. `Api._headers`, `Api._firstErrorMessage(http.Response) → String?`, `UnauthorizedException` (전부 이미 있음). `FallEvent.id`, `FallEvent.isAcknowledged`, `FallEvent.occurredAt`, `FallEvent.roomLabel` (전부 이미 있음).
- Produces: `Api.deleteFall(int id) → Future<void>` — 204면 정상 반환, 401이면 `UnauthorizedException`, 그 밖에는 서버 문구를 담은 `Exception`.

**이 태스크에도 자동 테스트는 없다.** `app/test/`에는 `poller_test.dart` 하나뿐이고 순수 로직만 다루는 관례다. 삭제는 위젯·네트워크 경로라 여기에 맞지 않는다. 검증은 `flutter analyze`(정적 검사)와 `flutter test`(회귀), 그리고 태스크 4의 수동 절차로 한다.

- [ ] **Step 1: `app/lib/api.dart`에 `deleteFall`을 더한다**

`acknowledge` 메서드 바로 아래에 붙인다(낙상 관련 메서드끼리 모아 둔 자리다).

```dart
  Future<void> deleteFall(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/falls/$id/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    // 미확인 기록 삭제는 서버가 400 + 한국어 문구로 거절한다. 문구를 새로 짓지 말고 그대로 올린다.
    if (res.statusCode != 204) {
      throw Exception(_firstErrorMessage(res) ?? '기록을 삭제하지 못했습니다 (${res.statusCode}).');
    }
  }
```

- [ ] **Step 2: `fall_detail.dart`에 `_delete`를 더한다**

`_acknowledge` 메서드 바로 아래에 붙인다.

```dart
  Future<void> _delete() async {
    // 완전 삭제라 되돌릴 수 없다. 웹의 confirm()과 같은 무게로 확인을 받는다.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록을 삭제할까요?'),
        content: Text('${_event.roomLabel} · ${_fmt(_event.occurredAt)}\n\n삭제하면 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;   // 다이얼로그가 열려 있는 사이 화면이 사라졌으면 setState가 터진다

    setState(() => _busy = true);
    try {
      await widget.api.deleteFall(_event.id);
      if (!mounted) return;
      // 결과 없이 pop 한다. 목록이 null 경로에서 서버 상태로 다시 그린다.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
```

- [ ] **Step 3: 삭제 버튼을 화면 맨 아래에 붙인다**

`build`의 `ListView` `children` 맨 끝, 119 버튼 다음에 붙인다. 되돌릴 수 없는 동작이라 119 버튼과 붙여 두지 않고 간격을 24로 벌린다(나머지 버튼 사이는 12다).

```dart
          const SizedBox(height: 24),
          OutlinedButton.icon(
            // 서버가 400으로 막는 규칙(확인한 기록만 삭제)을 화면이 미리 설명한다.
            onPressed: _busy || !_event.isAcknowledged ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(_event.isAcknowledged ? '기록 삭제' : '확인한 뒤 삭제할 수 있습니다'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
```

- [ ] **Step 4: `fall_detail.dart`의 낡아진 주석을 고친다**

`AppBar`의 `leading` 위 주석이 지금은 "스와이프 백으로 나가면 null이 되지만, 5초 폴링이 곧 목록을 새로 고친다"라고 되어 있다. 다음 스텝에서 null 경로가 즉시 새로 고치게 바뀌므로 이 주석이 틀리게 된다. 두 줄을 통째로 바꾼다.

바꾸기 전.

```dart
        // 목록이 확인 상태를 즉시 반영할 수 있도록 갱신된 이벤트를 돌려준다.
        // iOS 스와이프 백으로 나가면 null이 되지만, 5초 폴링이 곧 목록을 새로 고친다.
```

바꾼 뒤.

```dart
        // 목록이 확인 상태를 즉시 반영할 수 있도록 갱신된 이벤트를 돌려준다.
        // 삭제와 iOS 스와이프 백은 null이 되고, 목록이 그때 서버에서 다시 받아 그린다.
```

- [ ] **Step 5: `fall_list.dart`의 null 경로에 `_refresh()`를 붙인다**

`ListTile`의 `onTap` 안이다. 바꾸기 전.

```dart
                                  if (updated != null) {
                                    final idx = _events.indexWhere((x) => x.id == updated.id);
                                    if (idx != -1) setState(() => _events[idx] = updated);
                                  }
```

바꾼 뒤.

```dart
                                  if (updated != null) {
                                    final idx = _events.indexWhere((x) => x.id == updated.id);
                                    if (idx != -1) setState(() => _events[idx] = updated);
                                  } else {
                                    // 삭제했거나 스와이프 백으로 나왔다 — 서버 상태로 다시 그린다.
                                    await _refresh();
                                  }
```

- [ ] **Step 6: 정적 검사를 돌린다**

```bash
cd app && flutter analyze
```

기대: `No issues found!`. `use_build_context_synchronously` 경고가 나오면 무시하지 말고 본다 — `_delete`의 `await` 뒤에 `mounted` 검사가 들어 있는지 확인한다. Step 2 코드에는 들어 있다.

- [ ] **Step 7: 앱 테스트로 회귀를 확인한다**

```bash
cd app && flutter test
```

기대: 4개 PASS. 이 태스크는 `poller.dart`를 건드리지 않으므로 개수와 결과가 그대로여야 한다.

- [ ] **Step 8: 커밋**

```bash
git add app/lib/api.dart app/lib/screens/fall_detail.dart app/lib/screens/fall_list.dart
git commit -F - <<'EOF'
feat: 앱 낙상 기록 삭제 — 상세 화면, 확인한 기록만

목록 스와이프 삭제 대신 상세 화면에 둔다. 목록은 5초 폴링이 통째로 갈아치우는
자리라 스와이프 애니메이션 도중 리스트가 교체되면 상태가 꼬인다.

삭제는 pop(null)이고, 목록이 null 경로에서 서버 상태로 다시 그린다. 같은 경로를
타는 스와이프 백도 이제 즉시 반영된다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 4: 문서 — 엔드포인트 표·수동 검증·기록

**Files:**
- Modify: `docs/backend-architecture.html`
- Modify: `docs/manual-verification.md`
- Modify: `README.md:112`
- Modify: `checklist.md`
- Modify: `context-notes.md`

**Interfaces:**
- Consumes: 태스크 1·2·3의 완성된 동작.
- Produces: 없음(문서).

- [ ] **Step 1: `docs/backend-architecture.html` 엔드포인트 표에 한 행을 더한다**

`acknowledge` 행 바로 아래에 넣는다. 이 문서의 pill 클래스는 `del`이고 표시 문자열은 `DEL`이다(`put`·`get`·`post`·`del` 넷만 CSS에 있다).

```html
    <tr><td><span class="pill del">DEL</span><code>/api/falls/{id}/</code></td><td>기록 삭제. 확인한 기록만 — 미확인 400, 남의 기록은 확인 여부와 무관하게 404.</td></tr>
```

- [ ] **Step 2: `README.md:112`의 백엔드 테스트 개수를 고친다**

`36개`를 `39개`로 바꾸고, 항목 나열에 삭제를 더한다.

```
cd backend && ./gradlew test    # 39개 — 인증·소유권·방·프로필·푸시·전송 멱등성·기록 삭제 (fall_detection_test DB 필요: createdb fall_detection_test)
```

같은 블록의 웹·앱 개수는 건드리지 않는다. 실제 개수와 달라 보이더라도 이번 변경이 만든 차이가 아니므로 고치지 말고 보고만 한다.

- [ ] **Step 3: `docs/manual-verification.md`에 검증 절차를 더한다**

파일 맨 끝에 새 절로 붙인다. 기존 절들이 체크박스를 쓰므로 같은 형식이다.

```markdown
## 7. 낙상 기록 삭제 (2026-07-27 라운드)

낙상을 1건 만든 상태에서 시작한다. 감지 페이지로 실제 낙상을 내거나, 아래로 직접 넣는다.

```bash
TOKEN=<로그인 응답의 token>
curl -X POST http://127.0.0.1:8000/api/falls/ \
  -H "Authorization: Token $TOKEN" -H 'Content-Type: application/json' \
  -d '{"room_name":"안방","room_number":1,"occurred_at":"2026-07-27T03:00:00Z","confidence":0.9}'
```

### 보호자 페이지 (웹)

- [ ] 미확인 기록에 **"확인" 버튼만** 있고 삭제 버튼이 없다
- [ ] "확인"을 누르면 상태가 `확인함`이 되고, 버튼이 **"삭제"로 바뀐다**(버튼은 항상 하나다)
- [ ] "삭제"를 누르면 확인창이 뜨고, **취소하면 기록이 그대로다**
- [ ] 확인창에서 확인하면 목록에서 사라지고, **새로고침해도 돌아오지 않는다**

### 앱 (iOS)

- [ ] 미확인 기록의 상세 화면에서 삭제 버튼이 **비활성**이고 라벨이 `확인한 뒤 삭제할 수 있습니다`이다
- [ ] "확인함으로 표시"를 누르면 삭제 버튼이 **활성**되고 라벨이 `기록 삭제`가 된다
- [ ] "기록 삭제" → 확인 다이얼로그에서 **취소하면 상세 화면에 그대로 머문다**
- [ ] 다이얼로그에서 삭제하면 목록으로 돌아가고 **그 항목이 즉시 사라진다**(5초를 기다리지 않는다)
- [ ] 상세 화면을 **스와이프 백**으로 나와도 목록이 정상이다(같은 null 경로를 탄다)

### 양쪽 동기화

- [ ] 웹에서 삭제한 기록이 앱 목록에서도 **5초 안에** 사라진다
- [ ] 앱에서 삭제한 기록이 웹 목록에서도 **5초 안에** 사라진다
- [ ] 삭제 후 새 낙상이 오면 **알림이 정상으로 뜬다**(삭제가 `NewEventTracker`를 망가뜨리지 않는다)

### 소유권

- [ ] 다른 계정(g2)으로 로그인해 남의 기록 id로 `DELETE`를 직접 호출하면 **404**다

```bash
curl -i -X DELETE http://127.0.0.1:8000/api/falls/<남의_id>/ -H "Authorization: Token $OTHER_TOKEN"
```
```

- [ ] **Step 4: `checklist.md`에 라운드 기록을 더한다**

파일 맨 끝에 새 절로 붙인다. 앞 절들과 같은 번호 체계라 `## 17`이다(마지막이 `## 16`인지 먼저 확인하고, 다르면 다음 번호를 쓴다).

```markdown
## 17. 낙상 기록 삭제 (2026-07-27)

- [x] 설계 — 완전 삭제 채택(소프트 삭제 기각), 확인한 기록만, 웹·앱 공용 엔드포인트 1개
- [x] 서버 — `DELETE /api/falls/{id}/` 204/400/404, 소유권 판정이 확인 여부보다 먼저
- [x] 서버 테스트 3종 — 확인한 기록 204·목록에서 소멸 / 미확인 400·행 보존 / 남의 기록은 확인 여부 무관 404
- [x] 보호자 페이지 — 확인 상태에 따라 버튼 하나만(확인 또는 삭제), `confirm()` 경유
- [x] 앱 — 상세 화면 삭제 버튼(미확인이면 비활성), `showDialog` 경유, `pop(null)` → 목록 재조회
- [x] 앱 부수 개선 — 스와이프 백도 같은 null 경로를 타 목록이 즉시 갱신된다
- [x] 문서 — 엔드포인트 표, 수동 검증 7절, README 테스트 개수 36→39
- [x] 검증 — 서버 39 통과, 웹 회귀 통과, `flutter analyze` 무경고·앱 4 통과
```

- [ ] **Step 5: `context-notes.md`에 결정 근거를 더한다**

파일 맨 끝에 붙인다. 이 파일은 "왜 그렇게 했는가"를 남기는 곳이다.

```markdown
## 낙상 기록 삭제 — 완전 삭제와 판정 순서 (2026-07-27)

**소프트 삭제를 기각했다.** `deleted_at` 컬럼과 전 조회 경로의 필터를 더하는 대신 행을 지운다.
방 삭제(`RoomService.delete`)가 이미 완전 삭제라 한 프로젝트 안에서 삭제의 의미가 갈리면 안 되고,
"영상도 좌표도 남기지 않는다"는 이 프로젝트 기조와도 맞는다. Flyway 마이그레이션이 필요 없어진 것은
덤이다. 대가는 되돌릴 수 없다는 것이고, 그래서 웹은 `confirm()`, 앱은 `showDialog`로 확인을 받는다.

**미확인 삭제를 서버가 막는다.** "보호자가 확인하지 않은 낙상은 사라지지 않는다"는 안전 규칙이다.
UI에서 버튼만 숨기면 규칙이 아니라 장식이다. 비용은 `if` 한 줄과 테스트 하나였다.

**소유권 판정이 확인 여부보다 먼저다.** 순서를 뒤집으면 남의 미확인 기록에 400이 나가면서
"그 id는 존재하고 아직 미확인"이라는 사실이 새어나간다. `acknowledge`가 이미 쓰는
`findByIdAndGuardianId` 패턴을 그대로 따라 확인 여부와 무관하게 404를 준다.
테스트 `delete_other_users_event_is_404_regardless_of_acknowledgement`가 이 순서를 고정한다.

**앱 삭제는 목록 스와이프가 아니라 상세 화면에 뒀다.** 목록은 5초 폴링이 `_events`를 통째로
갈아치우는 자리다. `Dismissible`의 사라지는 애니메이션 도중 리스트가 교체되면 상태가 꼬인다.
상세 화면은 폴링 대상이 아니라 이 문제가 없고, 웹의 "확인 → 삭제" 순서와도 같아진다.

**삭제 신호는 새 타입 없이 `pop(null)`로 보냈다.** 상세 화면은 원래 `pop(_event)`로 갱신된 이벤트를
돌려주고 목록이 그 자리만 교체한다. 삭제를 알리려고 sealed 결과 타입을 만드는 대신, 목록의 null 경로에
`_refresh()`를 붙였다. 세 줄이고, 덤으로 "스와이프 백은 5초 폴링을 기다려야 한다"던 기존 아쉬움
(`fall_detail.dart`의 주석에 적혀 있던)도 같이 사라졌다.

**되살아나는 경우를 알면서 두었다.** 감지 페이지 오프라인 큐가 같은 낙상을 재전송하면 중복 조회가
실패해 새 행으로 살아난다. 다만 큐에 들어가려면 POST가 3회 실패해야 하고 그러면 서버에 행이 없어
삭제할 것도 없다. "행은 저장됐는데 응답만 유실된" 경우에만 성립한다. 막으려면 삭제한 조합의 묘비를
남겨야 하는데 완전 삭제를 택한 이유와 정면으로 어긋나서 대응하지 않았다.
```

- [ ] **Step 6: 커밋**

```bash
git add docs/backend-architecture.html docs/manual-verification.md README.md checklist.md context-notes.md
git commit -F - <<'EOF'
docs: 낙상 기록 삭제 라운드 기록 — 엔드포인트 표·수동 검증 7절·결정 근거

완전 삭제를 택한 이유, 소유권 판정이 확인 여부보다 먼저인 이유, 앱 삭제를
목록 스와이프가 아니라 상세 화면에 둔 이유를 context-notes에 남겼다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## 최종 검증

네 태스크가 끝난 뒤 한 번에 돌린다.

```bash
cd backend && ./gradlew test          # 39개 PASS
cd ../web  && npm test                # 기존 개수 그대로 PASS
cd ../app  && flutter analyze         # No issues found!
cd app     && flutter test            # 4개 PASS
```

그다음 `docs/manual-verification.md` 7절을 실제로 한 번 밟는다. 특히 **양쪽 동기화**의 마지막 항목 — 삭제 후 새 낙상 알림이 정상으로 뜨는지 — 는 자동 테스트가 못 잡는 자리다. `NewEventTracker`가 최대 id만 기억하므로 이론상 안전하지만, 실제로 한 번 확인한다.
