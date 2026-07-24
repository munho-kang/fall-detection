# 제품 완성도 라운드 구현 계획 — 푸시·오프라인 큐·방/연락처 관리

> **2026-07-24: Android 지원 제거됨.** 이 문서의 Android·FCM 관련 내용은 작성 시점의 이력이다. 현재 앱은 iOS 전용이며 FCM 스택은 저장소에서 제거됐다 — 경위는 루트 context-notes.md "Android 지원 제거".

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 낙상 파이프라인에 백그라운드 푸시(Android FCM + 표준 웹 푸시), 오프라인 전송 큐, 방·연락처 CRUD, 보호자 웹 페이지를 추가한다.

**Architecture:** Django `falls` 앱에 모델 3개(Room·GuardianProfile·PushDevice)와 푸시 발송 모듈을 추가하고, `POST /api/falls/`를 unique 제약 기반 멱등 생성으로 바꾼다. 감지 페이지는 localStorage 큐로 전송 실패를 흡수하고, 신설 보호자 페이지(PWA)가 웹 푸시를 구독한다. Flutter 앱은 Android에서만 FCM을 켜고 폴링 알림을 끈다(알림 발생원 = 플랫폼당 1개).

**Tech Stack:** Django 6 + DRF + `firebase-admin` + `pywebpush` / 바닐라 JS + Vitest / Flutter + `firebase_core` + `firebase_messaging`

**설계 문서:** [docs/superpowers/specs/2026-07-23-product-completeness-design.md](../specs/2026-07-23-product-completeness-design.md)

## Global Constraints

- 기존 엔드포인트의 URL·응답 형식은 바꾸지 않는다. 인증·소유권 규칙은 기존과 동일(본인 것만 보인다).
- 푸시는 best-effort다. **어떤 발송 실패도 API 응답에 영향을 주지 않는다** — 폴링이 안전망이다.
- 환경변수 `FIREBASE_SERVICE_ACCOUNT`·`VAPID_PRIVATE_KEY`·`VAPID_SUBJECT` 미설정이면 해당 채널만 조용히 비활성. 로컬 개발은 키 없이 나머지 전부 동작해야 한다.
- FallEvent의 방 정보는 문자열 스냅샷 유지(Room FK 금지). 방을 삭제·개명해도 과거 기록이 안 깨진다.
- 웹 푸시는 표준 Web Push API + VAPID만 쓴다. 보호자 페이지에 Google SDK를 넣지 않는다.
- GitHub Pages가 `/<repo>/` 하위 경로에 서빙하므로 SW·manifest·아이콘 경로는 전부 **상대 경로**로 쓴다.
- 새 소스 파일 첫 줄에는 역할을 설명하는 한국어 한 줄 주석을 단다(설정 파일 제외).
- 한국어 문장은 콜론(`:`)으로 끝내지 않는다.
- 알림 문구 표준: 제목 "낙상 감지", 본문 "{room_name} {room_number}에서 낙상 감지".
- localStorage 큐 키는 `fall_queue`, 배너 문구는 "전송 실패 — 저장해 두었다가 연결되면 다시 보냅니다".

## 파일 구조

| 파일 | 역할 | 태스크 |
|------|------|--------|
| `backend/falls/models.py` | Room·GuardianProfile·PushDevice 추가, FallEvent 제약 변경 | 1 |
| `backend/falls/migrations/0002_*.py` | 자동 생성 마이그레이션 | 1 |
| `backend/falls/serializers.py` | Room·Profile·PushDevice 시리얼라이저 추가 | 2·3·4 |
| `backend/falls/views.py` | rooms/profile/devices 뷰 + 멱등 POST | 2·3·4·6 |
| `backend/falls/urls.py` | 신규 라우팅 | 2·3·4·5 |
| `backend/falls/push.py` | 푸시 발송 모듈 (신규) | 5 |
| `backend/falls/tests.py` | pytest 추가 (22개, 총 32개) | 1~6 |
| `backend/config/settings.py` | 푸시 환경변수 3개 | 5 |
| `backend/requirements.txt` | firebase-admin·pywebpush | 5 |
| `web/js/queue.js` | 오프라인 큐 순수 모듈 (신규) | 7 |
| `web/tests/queue.test.js` | Vitest 5개 (신규) | 7 |
| `web/js/main.js` | 큐 통합 + 방 선택 연동 | 8·9 |
| `web/js/api.js` | authFetch + rooms/falls/profile/push 함수 | 8·9·10·11 |
| `web/detect.html` | 방 select 동적화 + 인라인 추가 | 9 |
| `web/index.html` | 보호자 페이지 링크 + `next` 리다이렉트 | 10 |
| `web/guardian.html` · `web/js/guardian.js` | 보호자 페이지 (신규) | 10·11 |
| `web/sw.js` · `web/manifest.webmanifest` · `web/icons/` | 웹 푸시·PWA 소품 (신규) | 11 |
| `app/lib/models.dart` · `app/lib/api.dart` | Room·Profile 모델 + API 메서드 | 12 |
| `app/lib/screens/settings.dart` | 설정 화면 (신규) | 13 |
| `app/lib/screens/fall_detail.dart` | `_elderPhone` 상수 제거 → 프로필 | 13 |
| `app/lib/push.dart` | FCM 래퍼 (신규, Android 한정) | 14 |
| `app/lib/main.dart` · `app/lib/notifications.dart` | Firebase 초기화·알림 채널 | 14 |
| `app/lib/poller.dart` | 폴링 무알림 분기 | 15 |
| `app/lib/screens/fall_list.dart` | 설정 진입·푸시 등록/해제·무알림 분기 연결 | 13·14·15 |
| `app/test/poller_test.dart` | 분기 테스트 2개 | 15 |
| `render.yaml` · `docs/DEPLOYMENT.md` · `README.md` | 배포·문서 | 16 |

태스크 순서는 의존 순서다. 백엔드(1~6) → 웹(7~11) → 앱(12~15) → 문서(16). 웹·앱 파트는 백엔드 완료 후라면 서로 독립이다.

## 환경 준비 (모든 백엔드 태스크 공통)

백엔드 테스트 실행 환경이 없다면 처음 한 번만 만든다. venv는 `.gitignore`에 이미 있다.

```bash
cd /Users/munhokang/82107/weniv_project/backend
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m pytest -q   # 기존 10개 통과 확인
```

이후 모든 pytest 명령은 `backend/`에서 `.venv/bin/python -m pytest`로 실행한다.

---

### Task 1: 데이터 모델 — Room·GuardianProfile·PushDevice 신설, FallEvent 제약 변경

**Files:**
- Modify: `backend/falls/models.py`
- Create: `backend/falls/migrations/0002_*.py` (makemigrations 자동 생성)
- Test: `backend/falls/tests.py`

**Interfaces:**
- Consumes: 기존 `FallEvent`
- Produces: `Room(guardian, name, number)` — unique (guardian, name, number) / `GuardianProfile(user, elder_phone)` / `PushDevice(guardian, kind, token, created_at)` — token unique / `FallEvent`에 unique (guardian, room_name, room_number, occurred_at), ROOM_CHOICES 제거

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/falls/tests.py` 상단 import에 `IntegrityError`와 새 모델을 추가하고, 파일 끝에 테스트 4개를 붙인다.

```python
# import 블록에 추가
from django.db import IntegrityError

from falls.models import FallEvent, Room
```

```python
# --- 데이터 모델 (Task 1) ---


def test_fall_event_room_name_is_free_text(guardian):
    # ROOM_CHOICES가 제거되어 임의 문자열이 검증을 통과해야 한다
    e = make_event(guardian, room_name="서재")
    e.full_clean()  # choices가 남아 있으면 ValidationError


def test_fall_event_rejects_exact_duplicate(guardian):
    t = timezone.now()
    FallEvent.objects.create(
        guardian=guardian, room_name="안방", room_number=1, occurred_at=t, confidence=0.9
    )
    with pytest.raises(IntegrityError):
        FallEvent.objects.create(
            guardian=guardian, room_name="안방", room_number=1, occurred_at=t, confidence=0.8
        )


def test_room_unique_per_guardian(guardian):
    Room.objects.create(guardian=guardian, name="안방", number=1)
    with pytest.raises(IntegrityError):
        Room.objects.create(guardian=guardian, name="안방", number=1)


def test_same_room_allowed_for_other_guardian(guardian, other):
    Room.objects.create(guardian=guardian, name="안방", number=1)
    Room.objects.create(guardian=other, name="안방", number=1)  # 예외 없이 저장돼야 한다
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && .venv/bin/python -m pytest falls/tests.py -q`
Expected: FAIL — `ImportError: cannot import name 'Room'`

- [ ] **Step 3: 모델 구현**

`backend/falls/models.py`에서 `FallEvent`의 `ROOM_CHOICES` 줄을 삭제하고 `room_name`을 `models.CharField(max_length=20)`으로 바꾼다. `FallEvent.Meta`에 제약을 추가한다.

```python
    class Meta:
        ordering = ["-id"]  # 목록 API가 최신순이어야 한다
        constraints = [
            # 오프라인 큐 재전송 멱등성의 근거 — 같은 낙상은 두 행이 될 수 없다
            models.UniqueConstraint(
                fields=["guardian", "room_name", "room_number", "occurred_at"],
                name="uniq_fall_dedup",
            )
        ]
```

파일 끝에 모델 3개를 추가한다. 파일 첫 줄 주석도 현실에 맞게 바꾼다(예: `# 낙상 이벤트·방·프로필·푸시 기기 모델`).

```python
class Room(models.Model):
    guardian = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rooms"
    )
    name = models.CharField(max_length=20)
    number = models.PositiveSmallIntegerField()

    class Meta:
        ordering = ["name", "number"]
        constraints = [
            models.UniqueConstraint(
                fields=["guardian", "name", "number"], name="uniq_room_per_guardian"
            )
        ]

    def __str__(self):
        return f"{self.name} {self.number}"


class GuardianProfile(models.Model):
    # "어르신께 전화" 번호의 서버 저장소. 접근 시 get_or_create로 만든다.
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="guardian_profile"
    )
    elder_phone = models.CharField(max_length=20, blank=True, default="")

    def __str__(self):
        return f"{self.user.username} profile"


class PushDevice(models.Model):
    KIND_CHOICES = [("fcm", "fcm"), ("webpush", "webpush")]

    guardian = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="push_devices"
    )
    kind = models.CharField(max_length=10, choices=KIND_CHOICES)
    # FCM 등록 토큰 또는 Web Push 구독 JSON 문자열
    token = models.TextField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.guardian.username} {self.kind}"
```

- [ ] **Step 4: 마이그레이션 생성**

Run: `cd backend && .venv/bin/python manage.py makemigrations falls`
Expected: `0002_...` 생성 — AlterField(room_name), CreateModel ×3, AddConstraint ×3 포함

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd backend && .venv/bin/python -m pytest -q`
Expected: 기존 10 + 신규 4 = 14 passed

- [ ] **Step 6: 커밋**

```bash
git add backend/falls/models.py backend/falls/migrations backend/falls/tests.py
git commit -m "feat: Room·GuardianProfile·PushDevice 모델과 FallEvent 멱등 제약 추가"
```

---

### Task 2: 방 CRUD API — `/api/rooms/`

**Files:**
- Modify: `backend/falls/serializers.py`, `backend/falls/views.py`, `backend/falls/urls.py`
- Test: `backend/falls/tests.py`

**Interfaces:**
- Consumes: Task 1의 `Room`
- Produces: `GET/POST /api/rooms/` (POST body `{name, number}` → 201 `{id, name, number}`), `PATCH/DELETE /api/rooms/<id>/`. 중복 방 → 400, 남의 방 → 404

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/falls/tests.py` 끝에 추가한다.

```python
# --- 방 CRUD (Task 2) ---


def test_room_crud_roundtrip(guardian):
    c = client_for(guardian)
    r = c.post("/api/rooms/", {"name": "안방", "number": 1}, format="json")
    assert r.status_code == 201
    room_id = r.data["id"]

    assert [x["name"] for x in c.get("/api/rooms/").data] == ["안방"]

    r = c.patch(f"/api/rooms/{room_id}/", {"name": "서재"}, format="json")
    assert r.status_code == 200 and r.data["name"] == "서재"

    assert c.delete(f"/api/rooms/{room_id}/").status_code == 204
    assert c.get("/api/rooms/").data == []


def test_room_list_excludes_other_users(guardian, other):
    Room.objects.create(guardian=other, name="부엌", number=1)
    assert client_for(guardian).get("/api/rooms/").data == []


def test_room_patch_other_users_404(guardian, other):
    theirs = Room.objects.create(guardian=other, name="부엌", number=1)
    r = client_for(guardian).patch(f"/api/rooms/{theirs.id}/", {"name": "x"}, format="json")
    assert r.status_code == 404


def test_room_duplicate_create_400(guardian):
    Room.objects.create(guardian=guardian, name="안방", number=1)
    r = client_for(guardian).post("/api/rooms/", {"name": "안방", "number": 1}, format="json")
    assert r.status_code == 400
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && .venv/bin/python -m pytest falls/tests.py -q`
Expected: 신규 4개 FAIL (404 — 라우팅 없음)

- [ ] **Step 3: 구현**

`backend/falls/serializers.py` — import에 `Room` 추가(`from .models import FallEvent, Room`), 끝에 추가.

```python
class RoomSerializer(serializers.ModelSerializer):
    class Meta:
        model = Room
        fields = ["id", "name", "number"]

    def validate(self, attrs):
        # DB의 unique 제약을 IntegrityError(500) 대신 400으로 돌려주기 위한 사전 검사
        user = self.context["request"].user
        name = attrs.get("name", getattr(self.instance, "name", None))
        number = attrs.get("number", getattr(self.instance, "number", None))
        dup = Room.objects.filter(guardian=user, name=name, number=number)
        if self.instance is not None:
            dup = dup.exclude(pk=self.instance.pk)
        if dup.exists():
            raise serializers.ValidationError("같은 이름과 번호의 방이 이미 있습니다.")
        return attrs
```

`backend/falls/views.py` — import 갱신(`from .models import FallEvent, Room`, `from .serializers import FallEventSerializer, RoomSerializer, SignupSerializer`), 끝에 추가.

```python
class RoomListCreate(generics.ListCreateAPIView):
    serializer_class = RoomSerializer

    def get_queryset(self):
        return Room.objects.filter(guardian=self.request.user)

    def perform_create(self, serializer):
        serializer.save(guardian=self.request.user)


class RoomDetail(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = RoomSerializer

    def get_queryset(self):
        # 남의 방은 존재 자체가 드러나지 않고 404가 된다
        return Room.objects.filter(guardian=self.request.user)
```

`backend/falls/urls.py` — urlpatterns에 추가.

```python
    path("rooms/", views.RoomListCreate.as_view()),
    path("rooms/<int:pk>/", views.RoomDetail.as_view()),
```

- [ ] **Step 4: 통과 확인**

Run: `cd backend && .venv/bin/python -m pytest -q`
Expected: 18 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/falls/serializers.py backend/falls/views.py backend/falls/urls.py backend/falls/tests.py
git commit -m "feat: 방 CRUD API 추가"
```

---

### Task 3: 프로필 API — `/api/profile/`

**Files:**
- Modify: `backend/falls/serializers.py`, `backend/falls/views.py`, `backend/falls/urls.py`
- Test: `backend/falls/tests.py`

**Interfaces:**
- Consumes: Task 1의 `GuardianProfile`
- Produces: `GET/PUT /api/profile/` — 응답·요청 body 모두 `{"elder_phone": "..."}`. GET은 없으면 get_or_create

- [ ] **Step 1: 실패하는 테스트 작성**

```python
# --- 프로필 (Task 3) ---


def test_profile_get_creates_empty(guardian):
    r = client_for(guardian).get("/api/profile/")
    assert r.status_code == 200
    assert r.data == {"elder_phone": ""}


def test_profile_put_roundtrip(guardian):
    c = client_for(guardian)
    r = c.put("/api/profile/", {"elder_phone": "01012345678"}, format="json")
    assert r.status_code == 200
    assert c.get("/api/profile/").data == {"elder_phone": "01012345678"}
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && .venv/bin/python -m pytest falls/tests.py -q`
Expected: 신규 2개 FAIL (404)

- [ ] **Step 3: 구현**

`backend/falls/serializers.py` — import에 `GuardianProfile` 추가, 끝에 추가.

```python
class GuardianProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = GuardianProfile
        fields = ["elder_phone"]
```

`backend/falls/views.py` — import에 `GuardianProfile`·`GuardianProfileSerializer` 추가, 끝에 추가.

```python
@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def profile(request):
    prof, _ = GuardianProfile.objects.get_or_create(user=request.user)
    if request.method == "PUT":
        serializer = GuardianProfileSerializer(prof, data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
    return Response(GuardianProfileSerializer(prof).data)
```

`backend/falls/urls.py` — 추가.

```python
    path("profile/", views.profile),
```

- [ ] **Step 4: 통과 확인**

Run: `cd backend && .venv/bin/python -m pytest -q`
Expected: 20 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/falls/serializers.py backend/falls/views.py backend/falls/urls.py backend/falls/tests.py
git commit -m "feat: 어르신 연락처 프로필 API 추가"
```

---

### Task 4: 푸시 기기 등록·해제 API — `/api/push/devices/`

**Files:**
- Modify: `backend/falls/serializers.py`, `backend/falls/views.py`, `backend/falls/urls.py`
- Test: `backend/falls/tests.py`

**Interfaces:**
- Consumes: Task 1의 `PushDevice`
- Produces: `POST /api/push/devices/` body `{kind: "fcm"|"webpush", token}` → 201 (upsert — 토큰이 다른 계정에 있으면 현 사용자로 이전), `DELETE /api/push/devices/` body `{token}` → 204

- [ ] **Step 1: 실패하는 테스트 작성**

`tests.py` import에 `PushDevice` 추가(`from falls.models import FallEvent, PushDevice, Room`), 끝에 추가.

```python
# --- 푸시 기기 등록 (Task 4) ---


def test_push_device_register(guardian):
    r = client_for(guardian).post(
        "/api/push/devices/", {"kind": "fcm", "token": "tok-1"}, format="json"
    )
    assert r.status_code == 201
    device = PushDevice.objects.get(token="tok-1")
    assert device.guardian == guardian and device.kind == "fcm"


def test_push_device_token_moves_to_current_user(guardian, other):
    # 같은 브라우저/기기에서 계정을 전환한 경우 — 토큰은 마지막 사용자 것이 된다
    client_for(other).post("/api/push/devices/", {"kind": "fcm", "token": "tok-1"}, format="json")
    client_for(guardian).post("/api/push/devices/", {"kind": "fcm", "token": "tok-1"}, format="json")
    assert PushDevice.objects.count() == 1
    assert PushDevice.objects.get(token="tok-1").guardian == guardian


def test_push_device_delete(guardian):
    PushDevice.objects.create(guardian=guardian, kind="fcm", token="tok-1")
    r = client_for(guardian).delete("/api/push/devices/", {"token": "tok-1"}, format="json")
    assert r.status_code == 204
    assert PushDevice.objects.count() == 0


def test_push_device_bad_kind_400(guardian):
    r = client_for(guardian).post(
        "/api/push/devices/", {"kind": "smoke-signal", "token": "t"}, format="json"
    )
    assert r.status_code == 400
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && .venv/bin/python -m pytest falls/tests.py -q`
Expected: 신규 4개 FAIL (404)

- [ ] **Step 3: 구현**

`backend/falls/serializers.py` 끝에 추가 (모델과 무관한 입력 검증이라 `Serializer`).

```python
class PushDeviceSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=["fcm", "webpush"])
    token = serializers.CharField()
```

`backend/falls/views.py` — import에 `PushDevice`·`PushDeviceSerializer` 추가, 끝에 추가.

```python
@api_view(["POST", "DELETE"])
@permission_classes([IsAuthenticated])
def push_devices(request):
    if request.method == "DELETE":
        # 없는 토큰이어도 204 — 로그아웃 흐름을 막을 이유가 없다
        PushDevice.objects.filter(
            guardian=request.user, token=request.data.get("token", "")
        ).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    serializer = PushDeviceSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    # 토큰이 다른 계정에 등록돼 있으면 현 사용자로 이전한다 (계정 전환 케이스)
    PushDevice.objects.update_or_create(
        token=serializer.validated_data["token"],
        defaults={"guardian": request.user, "kind": serializer.validated_data["kind"]},
    )
    return Response(status=status.HTTP_201_CREATED)
```

`backend/falls/urls.py` — 추가.

```python
    path("push/devices/", views.push_devices),
```

- [ ] **Step 4: 통과 확인**

Run: `cd backend && .venv/bin/python -m pytest -q`
Expected: 24 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/falls/serializers.py backend/falls/views.py backend/falls/urls.py backend/falls/tests.py
git commit -m "feat: 푸시 기기 등록·해제 API 추가"
```

---

### Task 5: 푸시 발송 모듈 — `falls/push.py` + VAPID 공개키 API

**Files:**
- Create: `backend/falls/push.py`
- Modify: `backend/config/settings.py`, `backend/requirements.txt`, `backend/falls/views.py`, `backend/falls/urls.py`
- Test: `backend/falls/tests.py`

**Interfaces:**
- Consumes: Task 1의 `PushDevice`, settings의 `FIREBASE_SERVICE_ACCOUNT`·`VAPID_PRIVATE_KEY`·`VAPID_SUBJECT`
- Produces: `push.send_to_guardian(event)` (동기, 예외를 절대 밖으로 내보내지 않음), `push.send_to_guardian_async(event)` (데몬 스레드 발사 후 즉시 반환), `push.vapid_public_key() -> str | None`, `GET /api/push/vapid-key/` → 200 `{"key": ...}` 또는 503

- [ ] **Step 1: 의존성 설치·고정**

```bash
cd backend
.venv/bin/python -m pip install firebase-admin pywebpush
.venv/bin/python -m pip freeze | grep -iE "^(firebase-admin|pywebpush)=="
```

출력된 두 줄(예: `firebase-admin==X.Y.Z`, `pywebpush==A.B.C`)을 그대로 `requirements.txt` 끝에 추가한다. 버전은 반드시 pip freeze 출력값을 쓴다.

- [ ] **Step 2: settings에 환경변수 추가**

`backend/config/settings.py` 끝(CORS 블록 아래)에 추가한다.

```python
# 푸시 발송 설정. 미설정이면 해당 채널만 조용히 비활성화된다 (falls/push.py).
FIREBASE_SERVICE_ACCOUNT = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
VAPID_PRIVATE_KEY = os.environ.get("VAPID_PRIVATE_KEY", "")
VAPID_SUBJECT = os.environ.get("VAPID_SUBJECT", "")
```

- [ ] **Step 3: 실패하는 테스트 작성**

`tests.py` import 블록에 추가.

```python
from unittest import mock

from falls import push
from pywebpush import WebPushException
```

파일 끝에 추가한다. `TEST_VAPID_KEY`는 base64url로 인코딩된 32바이트짜리 유효한 P-256 개인키 스칼라다(0x01 32개 — 테스트 전용).

```python
# --- 푸시 발송 (Task 5) ---

TEST_VAPID_KEY = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"


def test_send_skips_channels_without_keys(guardian, settings):
    settings.FIREBASE_SERVICE_ACCOUNT = ""
    settings.VAPID_PRIVATE_KEY = ""
    PushDevice.objects.create(guardian=guardian, kind="fcm", token="t1")
    PushDevice.objects.create(guardian=guardian, kind="webpush", token='{"endpoint": "e"}')
    with mock.patch("falls.push._send_fcm") as fcm, mock.patch("falls.push._send_webpush") as wp:
        push.send_to_guardian(make_event(guardian))
    fcm.assert_not_called()
    wp.assert_not_called()


def test_webpush_dead_subscription_deleted(guardian, settings):
    settings.VAPID_PRIVATE_KEY = TEST_VAPID_KEY
    settings.VAPID_SUBJECT = "mailto:test@example.com"
    device = PushDevice.objects.create(guardian=guardian, kind="webpush", token='{"endpoint": "e"}')
    gone = WebPushException("gone", response=mock.Mock(status_code=410))
    with mock.patch("pywebpush.webpush", side_effect=gone):
        push.send_to_guardian(make_event(guardian))
    assert not PushDevice.objects.filter(pk=device.pk).exists()


def test_fcm_dead_token_deleted(guardian):
    from firebase_admin import messaging

    device = PushDevice.objects.create(guardian=guardian, kind="fcm", token="dead")
    with (
        mock.patch("falls.push._ensure_firebase", return_value=True),
        mock.patch("firebase_admin.messaging.send", side_effect=messaging.UnregisteredError("x")),
    ):
        push.send_to_guardian(make_event(guardian))
    assert not PushDevice.objects.filter(pk=device.pk).exists()


def test_send_failure_never_raises(guardian, settings):
    settings.VAPID_PRIVATE_KEY = TEST_VAPID_KEY
    settings.VAPID_SUBJECT = "mailto:test@example.com"
    PushDevice.objects.create(guardian=guardian, kind="webpush", token='{"endpoint": "e"}')
    with mock.patch("pywebpush.webpush", side_effect=RuntimeError("boom")):
        push.send_to_guardian(make_event(guardian))  # 예외가 새어나오면 테스트 실패


def test_vapid_key_endpoint(guardian, settings):
    settings.VAPID_PRIVATE_KEY = ""
    assert client_for(guardian).get("/api/push/vapid-key/").status_code == 503

    settings.VAPID_PRIVATE_KEY = TEST_VAPID_KEY
    r = client_for(guardian).get("/api/push/vapid-key/")
    assert r.status_code == 200
    assert len(r.data["key"]) > 40  # base64url 공개키(65바이트 비압축 점)
```

- [ ] **Step 4: 실패 확인**

Run: `cd backend && .venv/bin/python -m pytest falls/tests.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'falls.push'`

- [ ] **Step 5: `falls/push.py` 구현**

```python
# 낙상 이벤트를 FCM·웹 푸시로 발송하는 모듈 — 키 미설정 채널은 조용히 비활성
#
# 푸시는 best-effort다. 여기서 무슨 일이 나도 API 응답에 영향을 주면 안 되므로
# send_to_guardian은 예외를 절대 밖으로 내보내지 않는다 (앱 폴링이 안전망).

import json
import logging
import threading

from django.conf import settings

logger = logging.getLogger(__name__)

_firebase_lock = threading.Lock()
_firebase_ready = False


def _ensure_firebase():
    """FIREBASE_SERVICE_ACCOUNT가 있으면 firebase_admin을 1회 초기화한다. 미설정이면 False."""
    global _firebase_ready
    if _firebase_ready:
        return True
    if not settings.FIREBASE_SERVICE_ACCOUNT:
        return False
    with _firebase_lock:
        if not _firebase_ready:
            import firebase_admin
            from firebase_admin import credentials

            cred = credentials.Certificate(json.loads(settings.FIREBASE_SERVICE_ACCOUNT))
            firebase_admin.initialize_app(cred)
            _firebase_ready = True
    return True


def vapid_public_key():
    """VAPID 개인키에서 브라우저 구독용 공개키(base64url)를 파생한다. 미설정이면 None."""
    if not settings.VAPID_PRIVATE_KEY:
        return None
    from cryptography.hazmat.primitives import serialization
    from py_vapid import Vapid, b64urlencode

    v = Vapid.from_string(private_key=settings.VAPID_PRIVATE_KEY)
    return b64urlencode(
        v.public_key.public_bytes(
            serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
        )
    )


def _payload(event):
    return {
        "type": "fall",
        "id": event.id,
        "room_name": event.room_name,
        "room_number": event.room_number,
        "occurred_at": event.occurred_at.isoformat(),
        "confidence": event.confidence,
    }


def _send_fcm(device, event):
    from firebase_admin import messaging

    try:
        messaging.send(
            messaging.Message(
                token=device.token,
                # notification부는 백그라운드에서 OS가 자동 표시한다
                notification=messaging.Notification(
                    title="낙상 감지",
                    body=f"{event.room_name} {event.room_number}에서 낙상 감지",
                ),
                # data부는 포그라운드 onMessage에서 로컬 알림을 만들 때 쓴다 (값은 전부 문자열이어야 한다)
                data={k: str(v) for k, v in _payload(event).items()},
                android=messaging.AndroidConfig(priority="high"),
            )
        )
    except messaging.UnregisteredError:
        device.delete()  # 앱 삭제 등으로 죽은 토큰은 그 자리에서 정리한다
    except Exception:
        logger.exception("FCM 발송 실패 (device=%s)", device.pk)


def _send_webpush(device, event):
    from pywebpush import WebPushException, webpush

    try:
        webpush(
            subscription_info=json.loads(device.token),
            data=json.dumps(_payload(event)),
            vapid_private_key=settings.VAPID_PRIVATE_KEY,
            vapid_claims={"sub": settings.VAPID_SUBJECT},
        )
    except WebPushException as exc:
        if exc.response is not None and exc.response.status_code in (404, 410):
            device.delete()  # 만료된 구독은 그 자리에서 정리한다
        else:
            logger.exception("웹 푸시 발송 실패 (device=%s)", device.pk)
    except Exception:
        logger.exception("웹 푸시 발송 실패 (device=%s)", device.pk)


def send_to_guardian(event):
    """보호자의 모든 기기로 발송한다. 어떤 실패도 밖으로 새어나가지 않는다."""
    try:
        from .models import PushDevice

        for device in PushDevice.objects.filter(guardian=event.guardian):
            if device.kind == "fcm":
                if _ensure_firebase():
                    _send_fcm(device, event)
            elif settings.VAPID_PRIVATE_KEY:
                _send_webpush(device, event)
    except Exception:
        logger.exception("푸시 발송 중 예상 밖 오류 (event=%s)", event.pk)


def send_to_guardian_async(event):
    """POST 응답이 외부 HTTP를 기다리지 않도록 데몬 스레드에서 발송한다."""
    threading.Thread(target=send_to_guardian, args=(event,), daemon=True).start()
```

- [ ] **Step 6: vapid-key 엔드포인트 구현**

`backend/falls/views.py` — import에 `from . import push` 추가, 끝에 추가.

```python
@api_view(["GET"])
@permission_classes([IsAuthenticated])
def vapid_key(request):
    key = push.vapid_public_key()
    if not key:
        return Response({"detail": "웹 푸시가 설정되지 않았습니다."}, status=503)
    return Response({"key": key})
```

`backend/falls/urls.py` — 추가.

```python
    path("push/vapid-key/", views.vapid_key),
```

- [ ] **Step 7: 통과 확인**

Run: `cd backend && .venv/bin/python -m pytest -q`
Expected: 29 passed

- [ ] **Step 8: 커밋**

```bash
git add backend/falls/push.py backend/falls/views.py backend/falls/urls.py backend/falls/tests.py backend/config/settings.py backend/requirements.txt
git commit -m "feat: FCM·웹 푸시 발송 모듈과 VAPID 공개키 API 추가"
```

---

### Task 6: `POST /api/falls/` 멱등 생성 + 푸시 트리거

**Files:**
- Modify: `backend/falls/views.py`
- Test: `backend/falls/tests.py`

**Interfaces:**
- Consumes: Task 1의 unique 제약, Task 5의 `push.send_to_guardian_async`
- Produces: 동일 (guardian, room_name, room_number, occurred_at) 재전송 → **200** + 기존 행, 신규 → **201** + `send_to_guardian_async` 1회 호출. 경합 IntegrityError → 재조회해 200

- [ ] **Step 1: 실패하는 테스트 작성**

`tests.py`에 autouse 픽스처를 픽스처 구역(`client_for` 위)에 추가한다. 테스트 중 진짜 발송 스레드가 뜨면 테스트 DB에 다른 커넥션으로 접근해 오염되므로 기본은 막고, 발송 로직 테스트는 `send_to_guardian`을 직접 부른다.

```python
@pytest.fixture(autouse=True)
def _no_push_threads(monkeypatch):
    # POST 테스트가 실제 발송 스레드를 띄우지 않게 막는다 (테스트 DB 보호)
    monkeypatch.setattr("falls.push.send_to_guardian_async", lambda event: None)
```

파일 끝에 추가.

```python
# --- 멱등 POST + 푸시 트리거 (Task 6) ---


def fall_payload(**extra):
    return {
        "room_name": "안방",
        "room_number": 1,
        "occurred_at": "2026-07-23T03:00:00Z",
        "confidence": 0.9,
        **extra,
    }


def test_duplicate_post_returns_200_and_no_new_row(guardian):
    c = client_for(guardian)
    first = c.post("/api/falls/", fall_payload(), format="json")
    assert first.status_code == 201

    second = c.post("/api/falls/", fall_payload(confidence=0.5), format="json")
    assert second.status_code == 200
    assert second.data["id"] == first.data["id"]
    assert FallEvent.objects.count() == 1
    assert FallEvent.objects.get().confidence == 0.9  # 기존 행이 그대로여야 한다


def test_created_post_sends_push_once(guardian):
    with mock.patch("falls.push.send_to_guardian_async") as sender:
        r = client_for(guardian).post("/api/falls/", fall_payload(), format="json")
    assert r.status_code == 201
    sender.assert_called_once()
    assert sender.call_args.args[0].id == r.data["id"]


def test_duplicate_post_sends_no_push(guardian):
    c = client_for(guardian)
    c.post("/api/falls/", fall_payload(), format="json")
    with mock.patch("falls.push.send_to_guardian_async") as sender:
        r = c.post("/api/falls/", fall_payload(), format="json")
    assert r.status_code == 200
    sender.assert_not_called()
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && .venv/bin/python -m pytest falls/tests.py -q`
Expected: 신규 3개 FAIL — 중복 POST가 400(IntegrityError→ValidationError 아님, unique 제약 위반으로 500일 수도 있다. 어느 쪽이든 200이 아니면 된다)

- [ ] **Step 3: 구현**

`backend/falls/views.py` — import에 `from django.db import IntegrityError` 추가. `FallEventListCreate`의 `perform_create`를 지우고 `create` 오버라이드로 교체한다.

```python
class FallEventListCreate(generics.ListCreateAPIView):
    serializer_class = FallEventSerializer

    def get_queryset(self):
        # 남의 이벤트가 절대 새어나가지 않도록 요청자로 필터링한다
        return FallEvent.objects.filter(guardian=self.request.user)

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        lookup = {
            "guardian": request.user,
            "room_name": data["room_name"],
            "room_number": data["room_number"],
            "occurred_at": data["occurred_at"],
        }

        # 오프라인 큐 재전송 멱등성 — 같은 낙상이 다시 오면 기존 행을 돌려주고 푸시는 없다
        existing = FallEvent.objects.filter(**lookup).first()
        if existing is None:
            try:
                event = serializer.save(guardian=request.user)
            except IntegrityError:
                existing = FallEvent.objects.get(**lookup)  # 생성 경합 — 재조회해 200 경로로

        if existing is not None:
            return Response(self.get_serializer(existing).data, status=status.HTTP_200_OK)

        # 201일 때만, 응답을 막지 않는 데몬 스레드에서 발송한다
        push.send_to_guardian_async(event)
        return Response(self.get_serializer(event).data, status=status.HTTP_201_CREATED)
```

- [ ] **Step 4: 통과 확인 (기존 테스트 포함 전체)**

Run: `cd backend && .venv/bin/python -m pytest -q`
Expected: 32 passed — 특히 기존 `test_post_forces_guardian_to_requester`가 여전히 201이어야 한다

- [ ] **Step 5: 커밋**

```bash
git add backend/falls/views.py backend/falls/tests.py
git commit -m "feat: 낙상 POST 멱등 생성과 푸시 발송 트리거"
```

---

### Task 7: 오프라인 큐 순수 모듈 — `web/js/queue.js`

**Files:**
- Create: `web/js/queue.js`
- Test: `web/tests/queue.test.js` (신규)

**Interfaces:**
- Consumes: 없음 (브라우저 API 의존은 주입받는 storage뿐)
- Produces: `createFallQueue(storage)` → `{ enqueue(payload), flush(postFn), size() }`. `flush`는 앞에서부터 보내고, postFn이 reject하면 그 자리에서 중단(순서 보존), 재진입 시 즉시 반환

- [ ] **Step 1: 웹 테스트 환경 준비 (없으면)**

```bash
cd /Users/munhokang/82107/weniv_project/web
npm install
npm test   # 기존 detector 10개 통과 확인
```

- [ ] **Step 2: 실패하는 테스트 작성 — `web/tests/queue.test.js`**

```javascript
// queue.js 오프라인 큐의 적재·재전송 규칙 검증

import { describe, expect, it, vi } from "vitest";

import { createFallQueue } from "../js/queue.js";

function fakeStorage() {
  const map = new Map();
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
  };
}

describe("fall queue", () => {
  it("적재한 낙상은 storage에 남아 새 페이지 로드에도 유지된다", () => {
    const storage = fakeStorage();
    createFallQueue(storage).enqueue({ room_name: "안방", room_number: 1 });

    // 같은 storage로 다시 만들어도(새 페이지 로드) 큐가 살아 있어야 한다
    expect(createFallQueue(storage).size()).toBe(1);
  });

  it("flush 성공 시 전부 순서대로 보내고 큐를 비운다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });
    q.enqueue({ id: 2 });

    const sent = [];
    await q.flush(async (p) => sent.push(p.id));

    expect(sent).toEqual([1, 2]);
    expect(q.size()).toBe(0);
  });

  it("postFn이 resolve하면(201 신규든 200 중복이든) 성공으로 보고 제거한다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });

    await q.flush(async () => ({ id: 1 })); // 서버가 중복(200)으로 답한 경우

    expect(q.size()).toBe(0);
  });

  it("실패하면 중단하고 실패 항목부터 순서를 보존한다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });
    q.enqueue({ id: 2 });
    q.enqueue({ id: 3 });

    const postFn = vi.fn(async (p) => {
      if (p.id === 2) throw new Error("서버 다운");
    });
    await q.flush(postFn);

    expect(postFn.mock.calls.map(([p]) => p.id)).toEqual([1, 2]); // 3은 시도조차 안 한다
    expect(q.size()).toBe(2);

    const sent = [];
    await q.flush(async (p) => sent.push(p.id)); // 다음 트리거에서 이어서
    expect(sent).toEqual([2, 3]);
  });

  it("flush가 겹쳐 불려도 이중 전송하지 않는다", async () => {
    const q = createFallQueue(fakeStorage());
    q.enqueue({ id: 1 });

    let release;
    const first = q.flush(() => new Promise((r) => (release = r)));
    await q.flush(async () => {
      throw new Error("재진입이면 불리면 안 된다");
    });

    release();
    await first;
    expect(q.size()).toBe(0);
  });
});
```

- [ ] **Step 3: 실패 확인**

Run: `cd web && npm test`
Expected: FAIL — `Failed to load ../js/queue.js`

- [ ] **Step 4: `web/js/queue.js` 구현**

```javascript
// 전송 실패한 낙상을 localStorage에 쌓아 두었다가 재전송하는 오프라인 큐 (순수 모듈)
//
// 서버의 unique 제약 + 200 응답이 재전송 중복을 흡수하므로, 여기서는 "성공하면 제거,
// 실패하면 순서 보존을 위해 중단"만 지키면 된다.

const KEY = "fall_queue";

export function createFallQueue(storage) {
  const read = () => {
    try {
      const items = JSON.parse(storage.getItem(KEY) ?? "[]");
      return Array.isArray(items) ? items : [];
    } catch {
      return []; // 깨진 값은 빈 큐로 취급한다
    }
  };
  const write = (items) => storage.setItem(KEY, JSON.stringify(items));

  let flushing = false;

  return {
    size: () => read().length,

    enqueue(payload) {
      write([...read(), payload]);
    },

    // 앞에서부터 하나씩 보낸다. postFn이 resolve하면(201 신규·200 중복 모두) 제거하고,
    // reject하면 그 자리에서 중단한다 — 다음 트리거(online·60초 주기 등)에서 재개된다.
    async flush(postFn) {
      if (flushing) return; // 트리거가 겹쳐도 이중 전송하지 않는다
      flushing = true;
      try {
        while (read().length > 0) {
          const [head, ...rest] = read();
          try {
            await postFn(head);
          } catch {
            return;
          }
          write(rest);
        }
      } finally {
        flushing = false;
      }
    },
  };
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd web && npm test`
Expected: 기존 10 + 신규 5 = 15 passed

- [ ] **Step 6: 커밋**

```bash
git add web/js/queue.js web/tests/queue.test.js
git commit -m "feat: 낙상 오프라인 전송 큐 모듈 추가 (TDD)"
```

---

### Task 8: 감지 페이지 큐 통합 — `main.js`

**Files:**
- Modify: `web/js/main.js`, `web/js/api.js`

**Interfaces:**
- Consumes: Task 7의 `createFallQueue`, 기존 `postFall(payload, attempts)`
- Produces: postFall 3회 실패 → 큐 적재 + 배너. flush 트리거 4개(페이지 로드·`online`·60초 주기·새 낙상 전송 성공 직후)

- [ ] **Step 1: `web/js/api.js`의 낡은 주석 갱신**

`postFall` 위의 주석(78~79행 "3회 실패하면 이 낙상은 유실된다. 실제 제품이라면 localStorage 큐가 필요하지만 과제 범위에서는 배너로 알리고 포기한다.")을 현실에 맞게 바꾼다.

```javascript
// 최대 3회 시도, 사이에 지수 백오프(0.5s → 1s)를 둔다. 3회 실패하면 호출자(main.js)가
// localStorage 큐에 적재해 두었다가 연결이 돌아오면 재전송한다. 서버의 unique 제약이
// 재전송 중복을 200으로 흡수하므로 여러 번 보내져도 행이 늘지 않는다.
```

- [ ] **Step 2: `web/js/main.js`에 큐 연결**

import에 추가.

```javascript
import { createFallQueue } from "./queue.js";
```

`let sentCount = 0;` 아래에 추가.

```javascript
const queue = createFallQueue(localStorage);
// flush 개별 항목은 1회만 시도한다 — 실패하면 어차피 다음 트리거가 다시 부른다
const flushQueue = () => queue.flush((payload) => postFall(payload, 1));

flushQueue(); // 페이지 로드 시
window.addEventListener("online", flushQueue);
setInterval(flushQueue, 60_000);
```

기존 `postFall(payload).then(...).catch(...)` 블록을 교체한다.

```javascript
      postFall(payload)
        .then(() => {
          sentCount += 1;
          el.sent.textContent = `전송된 낙상 ${sentCount}건`;
          flushQueue(); // 방금 성공했으니 밀려 있던 것도 지금 보낸다
        })
        .catch(() => {
          // 401 로그아웃 중이어도 적재해 둔다 — 재로그인 후 flush가 되살리므로 손해가 없다
          queue.enqueue(payload);
          showBanner("전송 실패 — 저장해 두었다가 연결되면 다시 보냅니다");
        });
```

- [ ] **Step 3: 회귀 확인**

Run: `cd web && npm test`
Expected: 15 passed

- [ ] **Step 4: 수동 확인 — 오프라인 → 온라인 재전송**

1. `cd backend && .venv/bin/python manage.py runserver` + `web/`을 Live Server(5500)로 연다.
2. 로그인 → 감지 페이지에서 DevTools 콘솔로 가짜 항목을 적재한다.

```javascript
localStorage.setItem("fall_queue", JSON.stringify([
  { room_name: "안방", room_number: 1, occurred_at: new Date().toISOString(), confidence: 0.9 },
]));
```

3. 새로고침(=페이지 로드 flush) → Network 탭에 `POST /api/falls/` 201, `localStorage.getItem("fall_queue")`가 `[]`.
4. 같은 항목을 다시 적재하고 새로고침 → 이번엔 200(중복 흡수), 큐는 역시 비워진다.

- [ ] **Step 5: 커밋**

```bash
git add web/js/main.js web/js/api.js
git commit -m "feat: 감지 페이지에 오프라인 큐 연결 — 실패 시 적재, 4개 트리거로 재전송"
```

---

### Task 9: 감지 페이지 방 선택 연동 — `detect.html` + rooms API

**Files:**
- Modify: `web/js/api.js`, `web/detect.html`, `web/js/main.js`

**Interfaces:**
- Consumes: Task 2의 `/api/rooms/`
- Produces: api.js에 `authFetch(path, options)`(내부), `listRooms()`, `createRoom(name, number)`. detect.html의 고정 4개 select → 서버 방 목록. 방 0개면 인라인 추가 UI가 펼쳐지고 감지 시작 버튼 비활성

- [ ] **Step 1: `web/js/api.js`에 공통 fetch와 rooms 함수 추가**

`signup` 안의 에러 파싱을 헬퍼로 추출하고(중복 방지), 파일 끝에 추가한다.

```javascript
// DRF 검증 에러({필드: [메시지, ...]})의 첫 메시지를 꺼낸다. 한국어로 내려온다.
async function firstErrorMessage(res, fallback) {
  try {
    const first = Object.values(await res.json()).flat()[0];
    if (typeof first === "string") return first;
  } catch {
    // 본문이 JSON이 아니면 기본 문구를 쓴다
  }
  return fallback;
}

// 토큰을 붙여 호출하고 401이면 로그아웃까지 처리하는 공통 래퍼
async function authFetch(path, options = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Token ${getToken()}`,
      ...(options.headers ?? {}),
    },
  });
  if (res.status === 401) {
    logoutAndRedirect();
    throw new UnauthorizedError();
  }
  return res;
}

export async function listRooms() {
  const res = await authFetch("/api/rooms/");
  if (!res.ok) throw new Error(`방 목록을 불러오지 못했습니다 (${res.status}).`);
  return res.json();
}

export async function createRoom(name, number) {
  const res = await authFetch("/api/rooms/", {
    method: "POST",
    body: JSON.stringify({ name, number }),
  });
  if (!res.ok) throw new Error(await firstErrorMessage(res, "방을 추가하지 못했습니다."));
  return res.json();
}
```

`signup`의 인라인 파싱 try/catch 블록은 `throw new Error(await firstErrorMessage(res, "회원가입에 실패했습니다."));` 한 줄로 교체한다.

- [ ] **Step 2: `web/detect.html`의 setup 카드 교체**

기존 `<label for="roomName">…<input id="roomNumber" …>` 블록(15~23행)을 다음으로 교체한다.

```html
      <label for="roomSelect">방</label>
      <select id="roomSelect"></select>
      <p class="error hidden" id="noRooms">등록된 방이 없습니다. 아래에서 먼저 추가하세요.</p>
      <details id="addRoom">
        <summary>새 방 추가</summary>
        <label for="newRoomName">방 이름</label>
        <input id="newRoomName" maxlength="20" placeholder="안방" />
        <label for="newRoomNumber">방 번호</label>
        <input id="newRoomNumber" type="number" value="1" min="1" max="99" />
        <button type="button" id="addRoomBtn">추가</button>
      </details>
```

- [ ] **Step 3: `web/js/main.js` 연동**

import를 `import { createRoom, listRooms, postFall, requireToken } from "./api.js";`로 바꾼다. `el`에서 `roomName`·`roomNumber`를 지우고 추가한다.

```javascript
  roomSelect: document.getElementById("roomSelect"),
  noRooms: document.getElementById("noRooms"),
  addRoom: document.getElementById("addRoom"),
  newRoomName: document.getElementById("newRoomName"),
  newRoomNumber: document.getElementById("newRoomNumber"),
  addRoomBtn: document.getElementById("addRoomBtn"),
```

`el.start.addEventListener` 앞에 방 로딩 로직을 추가한다.

```javascript
let rooms = [];

async function refreshRooms(selectId) {
  rooms = await listRooms();
  el.roomSelect.innerHTML = "";
  for (const room of rooms) {
    const opt = document.createElement("option");
    opt.value = String(room.id);
    opt.textContent = `${room.name} ${room.number}`;
    el.roomSelect.append(opt);
  }
  if (selectId != null) el.roomSelect.value = String(selectId);
  const empty = rooms.length === 0;
  el.noRooms.classList.toggle("hidden", !empty);
  el.start.disabled = empty; // 방 없이는 감지를 시작할 수 없다
  if (empty) el.addRoom.open = true; // 설치 흐름이 안 끊기게 추가 폼을 바로 펼친다
}

refreshRooms().catch((err) => {
  el.error.textContent = err.message;
});

el.addRoomBtn.addEventListener("click", async () => {
  el.error.textContent = "";
  try {
    const room = await createRoom(el.newRoomName.value.trim(), Number(el.newRoomNumber.value));
    el.newRoomName.value = "";
    await refreshRooms(room.id); // 방금 만든 방을 선택해 둔다
  } catch (err) {
    el.error.textContent = err.message;
  }
});
```

start 핸들러 안의 `const room = { name: el.roomName.value, number: Number(el.roomNumber.value) };`를 교체한다.

```javascript
  const selected = rooms.find((r) => String(r.id) === el.roomSelect.value);
  const room = { name: selected.name, number: selected.number };
```

- [ ] **Step 4: 회귀 + 수동 확인**

Run: `cd web && npm test` — 15 passed.
수동: 새 계정으로 로그인 → 감지 페이지에 "등록된 방이 없습니다" + 추가 폼 펼쳐짐 + 시작 버튼 비활성 → 이름 "안방"·번호 1로 추가 → select에 "안방 1"이 선택돼 있고 시작 버튼 활성 → 감지 시작이 기존처럼 동작.

- [ ] **Step 5: 커밋**

```bash
git add web/js/api.js web/detect.html web/js/main.js
git commit -m "feat: 감지 페이지 방 선택을 서버 목록으로 교체, 인라인 방 추가"
```

---

### Task 10: 보호자 페이지 골격 — `guardian.html` + `guardian.js` + 로그인 `next` 연동

**Files:**
- Create: `web/guardian.html`, `web/js/guardian.js`
- Modify: `web/js/api.js`, `web/index.html`

**Interfaces:**
- Consumes: 기존 `/api/falls/`·acknowledge, Task 2·3의 rooms·profile API
- Produces: api.js에 `listFalls()`, `acknowledgeFall(id)`, `renameRoom(id, name)`, `deleteRoomById(id)`, `getProfile()`, `updateProfile(elderPhone)`, `requireToken(next)`. index.html 로그인 후 `next` 화이트리스트(guardian.html·detect.html) 리다이렉트

- [ ] **Step 1: `web/js/api.js` 확장**

`requireToken`을 교체한다.

```javascript
export function requireToken(next) {
  const token = getToken();
  // 로그인 후 원래 가려던 페이지로 돌아올 수 있게 next를 남긴다 (index.html이 화이트리스트 검사)
  if (!token) location.href = next ? `index.html?next=${encodeURIComponent(next)}` : "index.html";
  return token;
}
```

파일 끝에 추가한다.

```javascript
export async function listFalls() {
  const res = await authFetch("/api/falls/");
  if (!res.ok) throw new Error(`목록을 불러오지 못했습니다 (${res.status}).`);
  return res.json();
}

export async function acknowledgeFall(id) {
  const res = await authFetch(`/api/falls/${id}/acknowledge/`, { method: "POST" });
  if (!res.ok) throw new Error(`확인 처리에 실패했습니다 (${res.status}).`);
  return res.json();
}

export async function renameRoom(id, name) {
  const res = await authFetch(`/api/rooms/${id}/`, {
    method: "PATCH",
    body: JSON.stringify({ name }),
  });
  if (!res.ok) throw new Error(await firstErrorMessage(res, "이름을 바꾸지 못했습니다."));
  return res.json();
}

export async function deleteRoomById(id) {
  const res = await authFetch(`/api/rooms/${id}/`, { method: "DELETE" });
  if (!res.ok) throw new Error(`방을 삭제하지 못했습니다 (${res.status}).`);
}

export async function getProfile() {
  const res = await authFetch("/api/profile/");
  if (!res.ok) throw new Error(`연락처를 불러오지 못했습니다 (${res.status}).`);
  return res.json();
}

export async function updateProfile(elderPhone) {
  const res = await authFetch("/api/profile/", {
    method: "PUT",
    body: JSON.stringify({ elder_phone: elderPhone }),
  });
  if (!res.ok) throw new Error(await firstErrorMessage(res, "연락처를 저장하지 못했습니다."));
  return res.json();
}
```

- [ ] **Step 2: `web/index.html` — next 리다이렉트 + 보호자 페이지 링크**

로그인 성공부 `location.href = "detect.html";`을 교체한다.

```javascript
          const next = new URLSearchParams(location.search).get("next");
          // 오픈 리다이렉트 방지 — 우리 페이지 2개만 허용한다
          const target = ["guardian.html", "detect.html"].includes(next) ? next : "detect.html";
          setToken(await login(form.username.value, form.password.value));
          location.href = target;
```

(`setToken(await login(...))` 줄은 기존 그대로 두고 리다이렉트만 바꿔도 된다.) 회원가입 링크 아래에 추가한다.

```html
      <p class="alt-link">보호자이신가요? <a href="guardian.html">보호자 페이지</a></p>
```

- [ ] **Step 3: `web/guardian.html` 생성**

```html
<!doctype html>
<!-- 보호자용 페이지 — 낙상 목록·알림 구독·방/연락처 관리 -->
<html lang="ko">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>낙상 감지 — 보호자</title>
    <link rel="stylesheet" href="css/style.css" />
  </head>
  <body>
    <div id="banner" class="banner hidden"></div>

    <div class="card">
      <h1>보호자 페이지</h1>

      <section id="pushSection">
        <button id="enablePush" type="button">알림 켜기</button>
        <p class="metric" id="pushStatus"></p>
      </section>

      <h2>낙상 알림</h2>
      <p class="metric hidden" id="fallEmpty">아직 감지된 낙상이 없습니다.</p>
      <ul id="fallList" class="plain-list"></ul>

      <h2>방 관리</h2>
      <ul id="roomList" class="plain-list"></ul>
      <label for="newRoomName">방 이름</label>
      <input id="newRoomName" maxlength="20" placeholder="안방" />
      <label for="newRoomNumber">방 번호</label>
      <input id="newRoomNumber" type="number" value="1" min="1" max="99" />
      <button id="addRoomBtn" type="button">방 추가</button>

      <h2>어르신 연락처</h2>
      <label for="elderPhone">전화번호</label>
      <input id="elderPhone" maxlength="20" placeholder="01012345678" />
      <button id="savePhone" type="button">저장</button>

      <p class="error" id="error"></p>
      <button id="logout" type="button">로그아웃</button>
    </div>

    <script type="module" src="js/guardian.js"></script>
  </body>
</html>
```

`web/css/style.css` 끝에 목록용 스타일을 추가한다.

```css
/* 보호자 페이지 목록 */
.plain-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.plain-list li {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 0;
  border-bottom: 1px solid #2b3040;
  font-size: 14px;
}

.plain-list li span {
  flex: 1;
}

.plain-list button {
  width: auto;
  margin: 0;
  padding: 6px 10px;
  font-size: 13px;
}

h2 {
  font-size: 15px;
  margin: 24px 0 8px;
}
```

- [ ] **Step 4: `web/js/guardian.js` 생성**

알림 켜기(`enablePush`)는 Task 11에서 붙인다 — 이 태스크에서는 버튼만 비활성으로 둔다.

```javascript
// 보호자 페이지 조립 — 낙상 목록 폴링·확인, 방/연락처 관리, 로그아웃

import {
  acknowledgeFall,
  createRoom,
  deleteRoomById,
  getProfile,
  listFalls,
  listRooms,
  logoutAndRedirect,
  renameRoom,
  requireToken,
  updateProfile,
} from "./api.js";

requireToken("guardian.html");

const el = {};
for (const id of [
  "banner", "enablePush", "pushStatus", "fallEmpty", "fallList",
  "roomList", "newRoomName", "newRoomNumber", "addRoomBtn",
  "elderPhone", "savePhone", "error", "logout",
]) {
  el[id] = document.getElementById(id);
}

el.enablePush.disabled = true; // Task 11에서 켠다

function showError(err) {
  el.error.textContent = err.message ?? String(err);
}

const two = (n) => String(n).padStart(2, "0");
const fmt = (iso) => {
  const t = new Date(iso);
  return `${t.getMonth() + 1}월 ${t.getDate()}일 ${two(t.getHours())}:${two(t.getMinutes())}`;
};

// --- 낙상 목록 (5초 폴링, 앱 fall_list와 동등) ---

async function refreshFalls() {
  const falls = await listFalls();
  el.fallEmpty.classList.toggle("hidden", falls.length > 0);
  el.fallList.innerHTML = "";
  for (const f of falls) {
    const li = document.createElement("li");
    const label = document.createElement("span");
    label.textContent =
      `${f.room_name} ${f.room_number} · ${fmt(f.occurred_at)} · ` +
      (f.acknowledged_at ? "확인함" : "미확인");
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
  }
}

// --- 방 관리 ---

async function refreshRooms() {
  const rooms = await listRooms();
  el.roomList.innerHTML = "";
  for (const room of rooms) {
    const li = document.createElement("li");
    const label = document.createElement("span");
    label.textContent = `${room.name} ${room.number}`;

    const rename = document.createElement("button");
    rename.textContent = "이름 변경";
    rename.addEventListener("click", () => {
      const name = prompt("새 이름", room.name);
      if (name) renameRoom(room.id, name.trim()).then(refreshRooms).catch(showError);
    });

    const del = document.createElement("button");
    del.textContent = "삭제";
    del.addEventListener("click", () => {
      // 과거 낙상 기록은 문자열 스냅샷이라 방을 지워도 깨지지 않는다
      if (confirm(`${room.name} ${room.number} 방을 삭제할까요?`)) {
        deleteRoomById(room.id).then(refreshRooms).catch(showError);
      }
    });

    li.append(label, rename, del);
    el.roomList.append(li);
  }
}

el.addRoomBtn.addEventListener("click", () => {
  el.error.textContent = "";
  createRoom(el.newRoomName.value.trim(), Number(el.newRoomNumber.value))
    .then(() => {
      el.newRoomName.value = "";
      refreshRooms();
    })
    .catch(showError);
});

// --- 어르신 연락처 ---

el.savePhone.addEventListener("click", () => {
  el.error.textContent = "";
  updateProfile(el.elderPhone.value.trim())
    .then(() => {
      el.banner.textContent = "저장했습니다.";
      el.banner.classList.remove("hidden");
      setTimeout(() => el.banner.classList.add("hidden"), 2000);
    })
    .catch(showError);
});

// --- 로그아웃 ---

el.logout.addEventListener("click", () => logoutAndRedirect());

// --- 초기화 ---

refreshFalls().catch(showError);
setInterval(() => refreshFalls().catch(() => {}), 5000); // 폴링 실패는 다음 주기가 흡수한다
refreshRooms().catch(showError);
getProfile()
  .then((p) => {
    el.elderPhone.value = p.elder_phone;
  })
  .catch(showError);
```

- [ ] **Step 5: 회귀 + 수동 확인**

Run: `cd web && npm test` — 15 passed.
수동: 로그아웃 상태에서 `guardian.html` 접속 → `index.html?next=guardian.html`로 이동 → 로그인 → 보호자 페이지로 복귀. 낙상 목록·확인 버튼, 방 추가/이름 변경/삭제, 연락처 저장, 로그아웃 각 1회씩. `index.html?next=https://evil.example`로 로그인해도 detect.html로 가는지 확인.

- [ ] **Step 6: 커밋**

```bash
git add web/guardian.html web/js/guardian.js web/js/api.js web/index.html web/css/style.css
git commit -m "feat: 보호자 웹 페이지 신설 — 낙상 목록·방/연락처 관리, next 리다이렉트"
```

---

### Task 11: 웹 푸시 — `sw.js`·manifest·아이콘·알림 켜기

**Files:**
- Create: `web/sw.js`, `web/manifest.webmanifest`, `web/icons/icon-192.png`, `web/icons/icon-512.png`
- Modify: `web/js/api.js`, `web/js/guardian.js`, `web/guardian.html`

**Interfaces:**
- Consumes: Task 4의 `/api/push/devices/`, Task 5의 `/api/push/vapid-key/`
- Produces: api.js에 `getVapidKey()`, `registerPushDevice(kind, token)`, `deletePushDevice(token)`. 알림 켜기 = permission → subscribe → 서버 등록. 로그아웃 시 구독 해제. iOS 16.4+ 홈 화면 PWA에서 동작

- [ ] **Step 1: `web/js/api.js`에 푸시 함수 추가**

```javascript
export async function getVapidKey() {
  const res = await authFetch("/api/push/vapid-key/");
  if (res.status === 503) throw new Error("서버에 웹 푸시 키가 설정되지 않았습니다.");
  if (!res.ok) throw new Error(`푸시 키를 가져오지 못했습니다 (${res.status}).`);
  return res.json(); // { key }
}

export async function registerPushDevice(kind, token) {
  const res = await authFetch("/api/push/devices/", {
    method: "POST",
    body: JSON.stringify({ kind, token }),
  });
  if (!res.ok) throw new Error(`알림 등록에 실패했습니다 (${res.status}).`);
}

export async function deletePushDevice(token) {
  const res = await authFetch("/api/push/devices/", {
    method: "DELETE",
    body: JSON.stringify({ token }),
  });
  if (!res.ok) throw new Error(`알림 해제에 실패했습니다 (${res.status}).`);
}
```

- [ ] **Step 2: `web/sw.js` 생성 (바닐라 JS, import 없음)**

```javascript
// 웹 푸시 수신 서비스 워커 — 알림 표시와 클릭 시 보호자 페이지 열기만 한다

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    // JSON이 아니면 기본 문구로 표시한다
  }
  const body =
    data.room_name != null
      ? `${data.room_name} ${data.room_number}에서 낙상 감지`
      : "낙상이 감지되었습니다";
  event.waitUntil(
    self.registration.showNotification("낙상 감지", {
      body,
      tag: data.id != null ? `fall-${data.id}` : undefined, // 같은 낙상 재수신은 하나로 합친다
      icon: "icons/icon-192.png",
      data,
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((wins) => {
      const existing = wins.find((w) => w.url.includes("guardian.html"));
      return existing ? existing.focus() : self.clients.openWindow("./guardian.html");
    })
  );
});
```

- [ ] **Step 3: `web/manifest.webmanifest` 생성 (경로 전부 상대)**

```json
{
  "name": "낙상 알림 보호자 페이지",
  "short_name": "낙상 알림",
  "start_url": "./guardian.html",
  "scope": "./",
  "display": "standalone",
  "background_color": "#12141a",
  "theme_color": "#4c8dff",
  "icons": [
    { "src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

- [ ] **Step 4: 아이콘 생성 (표준 라이브러리만 쓰는 일회성 스크립트)**

```bash
mkdir -p /Users/munhokang/82107/weniv_project/web/icons
cd /Users/munhokang/82107/weniv_project
python3 - <<'EOF'
# 테마색 단색 PWA 아이콘 PNG 2개를 생성한다 (외부 라이브러리 불필요)
import struct, zlib

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(
        ">I", zlib.crc32(tag + data) & 0xFFFFFFFF
    )

def solid_png(size, rgb):
    row = b"\x00" + bytes(rgb) * size
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(row * size))
        + chunk(b"IEND", b"")
    )

for size in (192, 512):
    with open(f"web/icons/icon-{size}.png", "wb") as f:
        f.write(solid_png(size, (0x4C, 0x8D, 0xFF)))  # --accent #4c8dff
print("done")
EOF
```

- [ ] **Step 5: `web/guardian.html` head에 PWA 메타 추가**

```html
    <link rel="manifest" href="manifest.webmanifest" />
    <meta name="theme-color" content="#4c8dff" />
    <link rel="apple-touch-icon" href="icons/icon-192.png" />
```

- [ ] **Step 6: `web/js/guardian.js`에 알림 켜기·해제 연결**

import에 `deletePushDevice, getVapidKey, registerPushDevice`를 추가한다. `el.enablePush.disabled = true;` 줄을 지우고 아래를 추가한다.

```javascript
// --- 웹 푸시 ---

function urlBase64ToUint8Array(base64) {
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const raw = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (ch) => ch.charCodeAt(0));
}

const pushSupported = () => "serviceWorker" in navigator && "PushManager" in window;

async function initPushUi() {
  if (!pushSupported()) {
    el.enablePush.disabled = true;
    el.pushStatus.textContent =
      "이 브라우저는 웹 푸시를 지원하지 않습니다. iPhone은 홈 화면에 추가한 뒤 열면 켤 수 있습니다 (iOS 16.4+).";
    return;
  }
  // GitHub Pages 하위 경로에서도 동작하도록 반드시 상대 경로로 등록한다 (스코프 = web/)
  const reg = await navigator.serviceWorker.register("./sw.js");
  const sub = await reg.pushManager.getSubscription();
  if (sub) {
    el.enablePush.disabled = true;
    el.pushStatus.textContent = "알림이 켜져 있습니다.";
  }
}

el.enablePush.addEventListener("click", async () => {
  el.pushStatus.textContent = "";
  try {
    const reg = await navigator.serviceWorker.register("./sw.js");
    if ((await Notification.requestPermission()) !== "granted") {
      throw new Error("알림 권한이 거부되었습니다. 브라우저 설정에서 허용해 주세요.");
    }
    const { key } = await getVapidKey();
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key),
    });
    await registerPushDevice("webpush", JSON.stringify(sub));
    el.enablePush.disabled = true;
    el.pushStatus.textContent = "알림이 켜졌습니다.";
  } catch (err) {
    el.pushStatus.textContent = err.message;
  }
});

initPushUi().catch(() => {});
```

로그아웃 핸들러를 교체한다.

```javascript
el.logout.addEventListener("click", async () => {
  try {
    // 이 브라우저 구독을 서버에서 지운다. 실패해도 로그아웃은 진행한다 —
    // 남은 구독은 다음 발송 때 404/410으로 서버가 정리한다.
    const reg = await navigator.serviceWorker.getRegistration();
    const sub = await reg?.pushManager.getSubscription();
    if (sub) {
      await deletePushDevice(JSON.stringify(sub));
      await sub.unsubscribe();
    }
  } catch {
    // 무시
  }
  logoutAndRedirect();
});
```

- [ ] **Step 7: 수동 확인 — 데스크톱 브라우저 엔드투엔드**

1. VAPID 키 생성(아직 없으면).

```bash
cd backend && .venv/bin/python - <<'EOF'
# VAPID 키쌍 생성 — 출력된 개인키를 환경변수로 쓴다
import base64
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

key = ec.generate_private_key(ec.SECP256R1())
raw = key.private_numbers().private_value.to_bytes(32, "big")
enc = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
print("VAPID_PRIVATE_KEY =", enc(raw))
EOF
```

2. `VAPID_PRIVATE_KEY=<출력값> VAPID_SUBJECT=mailto:k01072387124@gmail.com .venv/bin/python manage.py runserver`로 서버 실행.
3. Chrome에서 guardian.html → 알림 켜기 → 권한 허용 → "알림이 켜졌습니다."
4. 탭을 백그라운드로 두고 curl로 낙상 등록 → OS 알림 "낙상 감지 / 안방 1에서 낙상 감지" 확인.

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/api/auth/login/ -H "Content-Type: application/json" -d '{"username":"<계정>","password":"<비번>"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -s -X POST http://127.0.0.1:8000/api/falls/ -H "Content-Type: application/json" -H "Authorization: Token $TOKEN" -d '{"room_name":"안방","room_number":1,"occurred_at":"2026-07-23T04:00:00Z","confidence":0.9}'
```

5. 알림 클릭 → guardian.html 포커스. 로그아웃 → DB에서 PushDevice가 사라졌는지 확인(`.venv/bin/python manage.py shell -c "from falls.models import PushDevice; print(PushDevice.objects.count())"`).

- [ ] **Step 8: 커밋**

```bash
git add web/sw.js web/manifest.webmanifest web/icons web/js/api.js web/js/guardian.js web/guardian.html
git commit -m "feat: 표준 웹 푸시 구독과 PWA 소품 추가 — 알림 켜기·서비스 워커·manifest"
```

---

### Task 12: Flutter — Room·Profile 모델과 API 클라이언트

**Files:**
- Modify: `app/lib/models.dart`
- Modify: `app/lib/api.dart`

**Interfaces:**
- Consumes: Task 2 `/api/rooms/`(GET 200 목록, POST `{name, number}` → 201, PATCH `/api/rooms/<id>/` → 200, DELETE → 204), Task 3 `/api/profile/`(GET/PUT — body·응답 모두 `{"elder_phone": "..."}`), Task 4 `/api/push/devices/`(POST `{kind, token}` → 201, DELETE `{token}` → 204)
- Produces: `Room {int id, String name, int number, String get label}`, `Profile {String elderPhone}`, `Api.listRooms() → Future<List<Room>>`, `Api.createRoom(String name, int number) → Future<Room>`, `Api.renameRoom(int id, String name, int number) → Future<Room>`, `Api.deleteRoom(int id) → Future<void>`, `Api.getProfile() → Future<Profile>`, `Api.updateProfile(String elderPhone) → Future<Profile>`, `Api.registerPushDevice(String token) → Future<void>`(kind는 내부에서 `'fcm'` 고정), `Api.deletePushDevice(String token) → Future<void>`

HTTP 래퍼는 이 저장소의 기존 관례(`listFalls`·`acknowledge`와 동일)대로 단위 테스트를 두지 않는다 — http 모킹 인프라가 없고 순수 로직도 아니다. 검증은 `flutter analyze`와 기존 테스트 유지로 한다. 새 순수 로직(알림 소스 규칙)은 Task 15에서 TDD로 다룬다.

- [ ] **Step 1: models.dart에 Room·Profile 추가**

`app/lib/models.dart`의 첫 줄 헤더 주석을 바꾼다.

```dart
// 서버가 내려주는 낙상 이벤트 1건
```

→

```dart
// 서버가 내려주는 데이터 모델 — 낙상 이벤트·방·보호자 프로필
```

같은 파일 끝(FallEvent 클래스 뒤)에 추가한다.

```dart

// 방 1건. 감지 페이지가 이 목록에서 카메라 위치를 고른다.
class Room {
  final int id;
  final String name;
  final int number;

  const Room({required this.id, required this.name, required this.number});

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as int,
        name: json['name'] as String,
        number: json['number'] as int,
      );

  String get label => '$name $number';
}

// 보호자 프로필 — 지금은 어르신 전화번호 하나다.
class Profile {
  final String elderPhone;

  const Profile({required this.elderPhone});

  factory Profile.fromJson(Map<String, dynamic> json) =>
      Profile(elderPhone: (json['elder_phone'] as String?) ?? '');
}
```

- [ ] **Step 2: api.dart에 메서드 8개 추가**

`app/lib/api.dart`의 `acknowledge` 메서드 뒤, `Api` 클래스 닫는 중괄호 앞에 추가한다.

```dart

  Future<List<Room>> listRooms() async {
    final res = await http.get(Uri.parse('$baseUrl/api/rooms/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('방 목록을 불러오지 못했습니다 (${res.statusCode}).');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Room> createRoom(String name, int number) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/'),
      headers: _headers,
      body: jsonEncode({'name': name, 'number': number}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 201) {
      throw Exception(_firstErrorMessage(res) ?? '방을 추가하지 못했습니다.');
    }
    return Room.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Room> renameRoom(int id, String name, int number) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/rooms/$id/'),
      headers: _headers,
      body: jsonEncode({'name': name, 'number': number}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) {
      throw Exception(_firstErrorMessage(res) ?? '방 정보를 바꾸지 못했습니다.');
    }
    return Room.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteRoom(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/rooms/$id/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 204) throw Exception('방을 삭제하지 못했습니다 (${res.statusCode}).');
  }

  Future<Profile> getProfile() async {
    final res = await http.get(Uri.parse('$baseUrl/api/profile/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('프로필을 불러오지 못했습니다 (${res.statusCode}).');
    return Profile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Profile> updateProfile(String elderPhone) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/profile/'),
      headers: _headers,
      body: jsonEncode({'elder_phone': elderPhone}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) {
      throw Exception(_firstErrorMessage(res) ?? '전화번호를 저장하지 못했습니다.');
    }
    return Profile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  // FCM 전용이다. 웹 푸시 구독(kind=webpush)은 보호자 페이지가 등록한다.
  Future<void> registerPushDevice(String token) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/push/devices/'),
      headers: _headers,
      body: jsonEncode({'kind': 'fcm', 'token': token}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 201) throw Exception('푸시 기기 등록에 실패했습니다 (${res.statusCode}).');
  }

  Future<void> deletePushDevice(String token) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/push/devices/'),
      headers: _headers,
      body: jsonEncode({'token': token}),
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 204) throw Exception('푸시 기기 해제에 실패했습니다 (${res.statusCode}).');
  }
```

- [ ] **Step 3: 정적 분석**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 기존 테스트 유지 확인**

Run: `cd app && flutter test`
Expected: `All tests passed!` (4개)

- [ ] **Step 5: 커밋**

```bash
git add app/lib/models.dart app/lib/api.dart
git commit -m "feat: 앱에 방·프로필·푸시 기기 API 클라이언트 추가"
```

---

### Task 13: 앱 설정 화면 — 방 관리·어르신 번호, 상세 화면 연락처 연동

**Files:**
- Create: `app/lib/screens/settings.dart`
- Modify: `app/lib/screens/fall_list.dart`
- Modify: `app/lib/screens/fall_detail.dart`

**Interfaces:**
- Consumes: Task 12의 `Room`/`Profile` 모델과 `Api.listRooms/createRoom/renameRoom/deleteRoom/getProfile/updateProfile`
- Produces: `SettingsScreen({required Api api})` 화면. `fall_detail.dart`의 "어르신께 전화" 버튼이 프로필 번호를 쓴다(미등록이면 비활성)

- [ ] **Step 1: settings.dart 생성**

`app/lib/screens/settings.dart`를 만든다.

```dart
// 설정 화면 — 방 등록·수정·삭제와 어르신 전화번호 관리

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final Api api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Room> _rooms = [];
  bool _loading = true;
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rooms = await widget.api.listRooms();
      final profile = await widget.api.getProfile();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _phone.text = profile.elderPhone;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e);
    }
  }

  void _snack(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  // room이 null이면 추가, 아니면 수정 다이얼로그다.
  Future<void> _editRoom([Room? room]) async {
    final name = TextEditingController(text: room?.name ?? '');
    final number = TextEditingController(text: room?.number.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(room == null ? '방 추가' : '방 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '이름 (예: 안방)'),
              autofocus: true,
            ),
            TextField(
              controller: number,
              decoration: const InputDecoration(labelText: '번호 (예: 1)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
        ],
      ),
    );
    if (saved != true) return;

    final n = int.tryParse(number.text.trim());
    if (name.text.trim().isEmpty || n == null) {
      _snack(Exception('이름과 숫자 번호를 모두 입력하세요.'));
      return;
    }
    try {
      if (room == null) {
        await widget.api.createRoom(name.text.trim(), n);
      } else {
        await widget.api.renameRoom(room.id, name.text.trim(), n);
      }
      await _load(); // 서버 기준으로 다시 그린다
    } catch (e) {
      _snack(e);
    }
  }

  Future<void> _deleteRoom(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${room.label} 삭제'),
        content: const Text('이미 기록된 낙상 이력은 지워지지 않습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteRoom(room.id);
      await _load();
    } catch (e) {
      _snack(e);
    }
  }

  Future<void> _savePhone() async {
    try {
      await widget.api.updateProfile(_phone.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다.')));
    } catch (e) {
      _snack(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('방 관리', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('감지 페이지가 이 목록에서 방을 고른다.', style: TextStyle(color: Colors.grey)),
                if (_rooms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('등록된 방이 없습니다. 방을 추가하세요.'),
                  ),
                for (final room in _rooms)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(room.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editRoom(room)),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRoom(room)),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _editRoom(),
                  icon: const Icon(Icons.add),
                  label: const Text('방 추가'),
                ),
                const SizedBox(height: 32),
                Text('어르신 전화번호', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('상세 화면의 "어르신께 전화" 버튼이 이 번호로 건다.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '01012345678', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _savePhone, child: const Text('저장')),
              ],
            ),
    );
  }
}
```

- [ ] **Step 2: fall_list.dart에 설정 진입 버튼**

`app/lib/screens/fall_list.dart`의 import에 추가한다.

```dart
import 'login.dart';
```

→

```dart
import 'login.dart';
import 'settings.dart';
```

appBar actions를 바꾼다.

```dart
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
```

→

```dart
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(api: widget.api)),
            ),
            icon: const Icon(Icons.settings),
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
```

- [ ] **Step 3: fall_detail.dart의 상수 번호를 프로필 조회로 교체**

`app/lib/screens/fall_detail.dart`에서 상수와 그 주석을 지우고 상태 필드로 바꾼다.

```dart
  // 연락처 관리 화면은 범위 밖이므로 상수로 둔다.
  static const _elderPhone = '01012345678';
```

→

```dart
  // null = 아직 불러오는 중, '' = 미등록. 설정 화면에서 등록한 번호를 쓴다.
  String? _elderPhone;
```

`bool _busy = false;` 바로 아래에 initState를 추가한다.

```dart
  late FallEvent _event = widget.event;
  bool _busy = false;
```

→

```dart
  late FallEvent _event = widget.event;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.getProfile().then((p) {
      if (mounted) setState(() => _elderPhone = p.elderPhone);
    }).catchError((_) {
      // 못 불러오면 미등록으로 취급한다. 버튼만 비활성화되고 화면은 정상 동작한다.
      if (mounted) setState(() => _elderPhone = '');
    });
  }
```

"어르신께 전화" 버튼을 바꾼다.

```dart
          OutlinedButton.icon(
            onPressed: () => _dial(_elderPhone),
            icon: const Icon(Icons.phone),
            label: const Text('어르신께 전화'),
          ),
```

→

```dart
          OutlinedButton.icon(
            // 로딩 중(null)이거나 미등록('')이면 누를 수 없다.
            onPressed: _elderPhone == null || _elderPhone!.isEmpty ? null : () => _dial(_elderPhone!),
            icon: const Icon(Icons.phone),
            label: Text(_elderPhone == '' ? '어르신께 전화 — 설정에서 번호 등록' : '어르신께 전화'),
          ),
```

- [ ] **Step 4: 정적 분석**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 기존 테스트 유지 확인**

Run: `cd app && flutter test`
Expected: `All tests passed!` (4개)

- [ ] **Step 6: 수동 확인 — 시뮬레이터 왕복**

1. 백엔드 실행. `cd backend && .venv/bin/python manage.py runserver`
2. 앱 실행. `cd app && flutter run` (iOS 시뮬레이터)
3. 로그인 → 앱바 톱니 → 방 추가 "안방 1" → 목록에 표시 → 수정으로 "거실 1" 변경 → 삭제.
4. 전화번호 입력 → 저장 → "저장했습니다." 스낵바.
5. 낙상 상세 화면(기존 이벤트가 없으면 감지 페이지나 curl로 1건 등록)에서 "어르신께 전화" 버튼이 활성화됐는지, 설정에서 번호를 지우면(빈 값 저장) 비활성 + "설정에서 번호 등록" 문구로 바뀌는지 확인.

- [ ] **Step 7: 커밋**

```bash
git add app/lib/screens/settings.dart app/lib/screens/fall_list.dart app/lib/screens/fall_detail.dart
git commit -m "feat: 앱 설정 화면 추가 — 방 관리·어르신 번호, 상세 화면 연락처 연동"
```

---

### Task 14: Android FCM — 백그라운드 푸시 수신

**Files:**
- Modify: `app/pubspec.yaml` (`flutter pub add`가 자동 수정)
- Modify: `app/android/settings.gradle.kts`
- Modify: `app/android/app/build.gradle.kts`
- Create(수동 준비물): `app/android/app/google-services.json`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/lib/notifications.dart`
- Create: `app/lib/push.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/screens/fall_list.dart`

**Interfaces:**
- Consumes: Task 12의 `Api.registerPushDevice(token)`/`Api.deletePushDevice(token)`, Task 5 백엔드가 보내는 FCM 메시지 — notification부(제목 "낙상 감지", 본문 "{room_name} {room_number}에서 낙상 감지") + data부 `{type: "fall", id, room_name, room_number, occurred_at, confidence}` 값은 전부 문자열
- Produces: `Push.register(Api api) → Future<void>`, `Push.unregister(Api api) → Future<void>` — 둘 다 Android가 아니면 즉시 반환하고, 어떤 실패도 밖으로 던지지 않는다

알림 경로 설계. 백그라운드에서는 OS가 notification부를 자동 표시하고(AndroidManifest의 기본 채널 지정 필요), 포그라운드에서는 `onMessage`가 data부로 로컬 알림을 띄운다(id=이벤트 id). 포그라운드 로컬 알림은 기존 `Notifications.show` 문구를 그대로 쓴다 — iOS 폴링 알림과 문구가 같다. 폴링의 Android 알림은 Task 15에서 끈다.

- [ ] **Step 1: Firebase 콘솔 준비물 (사용자 수동 작업)**

이 단계만 브라우저 작업이다. 파일이 아직 없어도 Step 2~9의 코드 작업과 analyze·test는 전부 통과하니, 파일을 못 받은 상태라면 Step 10(apk 빌드)만 보류하고 진행한다.

1. [Firebase 콘솔](https://console.firebase.google.com) → 프로젝트 추가(이름 자유, 애널리틱스 불필요).
2. 프로젝트 개요 → Android 아이콘 → 앱 등록. 패키지 이름은 정확히 `com.example.fall_guardian`.
3. `google-services.json`을 내려받아 `app/android/app/google-services.json`에 둔다. 이 파일은 식별자라 커밋해도 된다.
4. (백엔드 발송용 — Task 5의 환경변수) 프로젝트 설정(톱니) → 서비스 계정 → 새 비공개 키 생성 → JSON 다운로드. 이 파일은 **비밀이므로 절대 커밋하지 않는다.** 로컬 확인·Render 설정에만 쓴다.

- [ ] **Step 2: 의존성 추가**

Run: `cd app && flutter pub add firebase_core firebase_messaging`
Expected: `pubspec.yaml`의 dependencies에 `firebase_core`, `firebase_messaging` 두 항목이 추가되고 `Got dependencies!` 출력.

- [ ] **Step 3: settings.gradle.kts에 google-services 플러그인 선언**

`app/android/settings.gradle.kts`의 plugins 블록을 바꾼다.

```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
```

→

```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // google-services.json을 읽어 FCM 설정을 빌드에 주입한다
    id("com.google.gms.google-services") version "4.4.4" apply false
}
```

버전 `4.4.4`가 레지스트리에서 해석되지 않으면 `4.4.3`으로 낮춘다.

- [ ] **Step 4: app/build.gradle.kts에 플러그인 적용**

`app/android/app/build.gradle.kts`의 plugins 블록을 바꾼다.

```kotlin
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
```

→

```kotlin
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
```

- [ ] **Step 5: AndroidManifest — 알림 권한과 기본 채널**

`app/android/app/src/main/AndroidManifest.xml`에서 권한 부분을 바꾼다.

```xml
    <!-- 릴리즈 빌드에서 배포 서버 API 호출에 필요하다. 디버그 빌드는 Flutter 도구가 자동으로 넣어준다. -->
    <uses-permission android:name="android.permission.INTERNET"/>
```

→

```xml
    <!-- 릴리즈 빌드에서 배포 서버 API 호출에 필요하다. 디버그 빌드는 Flutter 도구가 자동으로 넣어준다. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <!-- Android 13+ 알림 표시 권한. 런타임 요청은 Notifications.init이 한다. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

flutterEmbedding meta-data 앞에 기본 채널 지정을 추가한다.

```xml
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
```

→

```xml
        <!-- 백그라운드 FCM 알림을 Notifications.init이 만든 'falls' 채널로 띄운다 -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="falls" />
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
```

- [ ] **Step 6: notifications.dart — 'falls' 채널을 미리 생성**

`app/lib/notifications.dart`의 `init()` 안 Android 분기를 바꾼다.

```dart
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
```

→

```dart
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      // 백그라운드 FCM 알림이 이 채널로 뜬다(AndroidManifest의 default_notification_channel_id).
      // show()가 쓰는 채널 id와 같아야 사용자 알림 설정이 한 곳에 모인다.
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'falls',
        '낙상 알림',
        description: '낙상이 감지되면 즉시 알립니다',
        importance: Importance.max,
      ));
    }
```

- [ ] **Step 7: push.dart 생성**

`app/lib/push.dart`를 만든다.

```dart
// Android FCM 등록·해제와 포그라운드 수신 (Android 전용 — iOS 앱은 폴링만 쓴다)

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'api.dart';
import 'models.dart';
import 'notifications.dart';

class Push {
  // 로그아웃 → 재로그인을 반복해도 스트림 리스너는 한 번만 건다.
  static bool _wired = false;

  /// 로그인 상태에서 호출한다. FCM 토큰을 서버에 등록하고 토큰 갱신·포그라운드 수신을 구독한다.
  /// 푸시는 부가 기능이고 폴링이 항상 백업이므로, 실패해도 절대 던지지 않는다.
  static Future<void> register(Api api) async {
    if (!Platform.isAndroid) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await api.registerPushDevice(token);

      if (!_wired) {
        _wired = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((t) {
          // 로그아웃 상태에서 갱신되면 401로 실패하지만, 다음 로그인의 register가 다시 등록한다.
          api.registerPushDevice(t).catchError((e) => debugPrint('토큰 갱신 등록 실패. $e'));
        });
        // 포그라운드에서는 OS가 notification부를 표시하지 않으므로 data부로 직접 띄운다.
        // 알림 id=이벤트 id라 어떤 경로로든 같은 낙상은 알림 1개로 합쳐진다.
        FirebaseMessaging.onMessage.listen(_showForeground);
      }
    } catch (e) {
      debugPrint('FCM 등록 실패 — 폴링만으로 동작한다. $e');
    }
  }

  /// 로그아웃 직전에 호출한다. 이 기기의 토큰을 서버에서 지워 로그아웃 뒤 알림을 막는다.
  static Future<void> unregister(Api api) async {
    if (!Platform.isAndroid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await api.deletePushDevice(token);
    } catch (e) {
      // 실패해도 로그아웃은 진행한다. 죽은 토큰은 다음 발송 때 서버가 정리한다.
      debugPrint('푸시 기기 해제 실패. $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final d = message.data;
    if (d['type'] != 'fall') return;
    final id = int.tryParse('${d['id']}');
    final occurredAt = DateTime.tryParse('${d['occurred_at']}');
    if (id == null || occurredAt == null) return;
    await Notifications.show(FallEvent(
      id: id,
      roomName: '${d['room_name'] ?? ''}',
      roomNumber: int.tryParse('${d['room_number']}') ?? 0,
      occurredAt: occurredAt.toLocal(),
      createdAt: occurredAt.toLocal(),
      confidence: double.tryParse('${d['confidence']}') ?? 0,
    ));
  }
}
```

- [ ] **Step 8: main.dart — Android에서만 Firebase 초기화**

`app/lib/main.dart`의 상단을 바꾼다.

```dart
// 앱 진입점 — 저장된 토큰 유무로 첫 화면을 정한다

import 'package:flutter/material.dart';

import 'api.dart';
import 'notifications.dart';
import 'screens/fall_list.dart';
import 'screens/login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  runApp(const FallGuardianApp());
}
```

→

```dart
// 앱 진입점 — 저장된 토큰 유무로 첫 화면을 정한다

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'notifications.dart';
import 'screens/fall_list.dart';
import 'screens/login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // FCM 준비. 실패(google-services.json 누락 등)해도 앱은 폴링만으로 동작해야 하므로 죽이지 않는다.
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase 초기화 실패 — 푸시 없이 계속한다. $e');
    }
  }
  await Notifications.init();
  runApp(const FallGuardianApp());
}
```

- [ ] **Step 9: fall_list.dart — 로그인 시 등록, 로그아웃 시 해제**

import에 추가한다.

```dart
import '../poller.dart';
import 'fall_detail.dart';
```

→

```dart
import '../poller.dart';
import '../push.dart';
import 'fall_detail.dart';
```

initState 첫머리에 등록을 건다.

```dart
  @override
  void initState() {
    super.initState();
    _poller = FallPoller(
```

→

```dart
  @override
  void initState() {
    super.initState();
    Push.register(widget.api); // Android면 FCM 토큰을 서버에 등록한다. 실패해도 폴링이 백업이다.
    _poller = FallPoller(
```

_logout에서 토큰 정리를 먼저 한다.

```dart
  Future<void> _logout() async {
    await widget.api.clearToken();
```

→

```dart
  Future<void> _logout() async {
    // 인증 토큰을 지우기 전에 서버의 푸시 등록부터 지운다. 로그아웃 뒤 알림이 오면 안 된다.
    await Push.unregister(widget.api);
    await widget.api.clearToken();
```

- [ ] **Step 10: 정적 분석과 테스트**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` / `All tests passed!` (4개)

- [ ] **Step 11: Android 빌드 확인 (google-services.json 배치 후)**

Run: `cd app && flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

파일이 아직 없으면 이 단계와 Step 12만 보류하고 커밋 후 다음 태스크로 진행한다(google-services 플러그인은 파일이 없으면 Android 빌드에서만 실패하고 analyze·test에는 영향이 없다).

- [ ] **Step 12: 수동 확인 — Android 기기·에뮬레이터 E2E**

주의. Task 6의 멱등 제약 때문에 **같은 occurred_at을 다시 보내면 200으로 흡수되고 푸시가 안 나간다.** 확인할 때마다 occurred_at을 바꾼다.

1. 서비스 계정 키로 백엔드 실행.

```bash
cd backend && FIREBASE_SERVICE_ACCOUNT="$(cat ~/Downloads/serviceAccountKey.json)" .venv/bin/python manage.py runserver
```

2. 에뮬레이터(또는 USB 기기)에 앱 설치 후 로그인. `cd app && flutter run`
3. 홈 버튼으로 앱을 백그라운드로 보낸다.
4. curl로 낙상 등록 → 상태바에 "낙상 감지 / 안방 1에서 낙상 감지" 알림 확인.

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/api/auth/login/ -H "Content-Type: application/json" -d '{"username":"<계정>","password":"<비번>"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -s -X POST http://127.0.0.1:8000/api/falls/ -H "Content-Type: application/json" -H "Authorization: Token $TOKEN" -d '{"room_name":"안방","room_number":1,"occurred_at":"2026-07-23T05:00:00Z","confidence":0.9}'
```

5. 앱을 다시 연 채(포그라운드) occurred_at을 `05:01:00Z`로 바꿔 한 번 더 등록 → 로컬 알림 1개 확인.
6. 로그아웃 → occurred_at을 `05:02:00Z`로 바꿔 등록 → 알림이 **안 오는지** 확인(unregister가 토큰을 지웠다).

- [ ] **Step 13: 커밋**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/settings.gradle.kts app/android/app/build.gradle.kts app/android/app/src/main/AndroidManifest.xml app/lib/notifications.dart app/lib/push.dart app/lib/main.dart app/lib/screens/fall_list.dart
git commit -m "feat: Android FCM 수신 — 토큰 등록·포그라운드 로컬 알림·기본 채널"
```

`google-services.json`을 받아 둔 상태라면 함께 커밋한다. `git add app/android/app/google-services.json`

---

### Task 15: 알림 소스 단일화 — Android는 폴링 알림을 끈다 (TDD)

**Files:**
- Modify: `app/test/poller_test.dart`
- Modify: `app/lib/poller.dart`
- Modify: `app/lib/screens/fall_list.dart`

**Interfaces:**
- Consumes: `FallEvent`(기존)
- Produces: `notifiableFromPolling(List<FallEvent> fresh, {required bool isAndroid}) → List<FallEvent>` — `poller.dart` 최상위 함수

규칙은 하나다. **플랫폼마다 알림 소스는 정확히 하나다** — Android는 FCM(Task 14), iOS는 폴링. 이 규칙이 없으면 Android 백그라운드 복귀 직후 같은 낙상에 OS 알림(FCM notification부)과 폴링 로컬 알림이 둘 다 뜰 수 있다. 판별을 순수 함수로 빼서 테스트한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/poller_test.dart`의 `main()` 마지막 테스트 뒤에 추가한다.

```dart

  test('Android에서는 폴링 새 이벤트로 알리지 않는다 — 알림은 FCM 한 소스에서만 온다', () {
    expect(notifiableFromPolling([ev(2), ev(1)], isAndroid: true), isEmpty);
  });

  test('iOS에서는 FCM이 없으므로 폴링 새 이벤트가 그대로 알림 대상이다', () {
    expect(notifiableFromPolling([ev(2), ev(1)], isAndroid: false).map((e) => e.id), [2, 1]);
  });
```

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test`
Expected: FAIL — `notifiableFromPolling`이 정의되지 않았다는 컴파일 오류.

- [ ] **Step 3: 구현**

`app/lib/poller.dart`의 import 아래(클래스들 앞)에 추가한다.

```dart

/// 폴링이 발견한 새 이벤트 중 로컬 알림을 띄울 대상을 고른다.
/// 플랫폼마다 알림 소스는 정확히 하나다 — Android는 FCM이 전담하므로(백그라운드는 OS,
/// 포그라운드는 onMessage) 폴링은 알리지 않는다. iOS는 FCM이 없으니 폴링이 알린다.
List<FallEvent> notifiableFromPolling(List<FallEvent> fresh, {required bool isAndroid}) =>
    isAndroid ? const [] : fresh;
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd app && flutter test`
Expected: `All tests passed!` (6개)

- [ ] **Step 5: fall_list.dart 연결**

import 첫머리에 추가한다.

```dart
import 'package:flutter/material.dart';

import '../api.dart';
```

→

```dart
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../api.dart';
```

onEvents의 알림 루프를 바꾼다.

```dart
      onEvents: (all, fresh) {
        for (final e in fresh) {
          Notifications.show(e);
        }
```

→

```dart
      onEvents: (all, fresh) {
        for (final e in notifiableFromPolling(fresh, isAndroid: Platform.isAndroid)) {
          Notifications.show(e);
        }
```

- [ ] **Step 6: 정적 분석과 테스트**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` / `All tests passed!` (6개)

- [ ] **Step 7: 커밋**

```bash
git add app/test/poller_test.dart app/lib/poller.dart app/lib/screens/fall_list.dart
git commit -m "feat: 플랫폼별 알림 소스 단일화 — Android는 폴링 알림을 끈다"
```

---

### Task 16: 배포 설정과 문서 갱신

**Files:**
- Modify: `render.yaml`
- Modify: `docs/DEPLOYMENT.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: 이번 라운드 전체 — 환경변수 3개(Task 5), 오프라인 큐(Task 7~8), 방·프로필 관리(Task 2~3·9~10·13), 푸시 채널 2종(Task 11·14)
- Produces: 없음 (문서)

- [ ] **Step 1: render.yaml에 푸시 환경변수 3개 추가**

`render.yaml`의 envVars 끝(`DJANGO_SUPERUSER_PASSWORD` 항목 뒤)에 추가한다.

```yaml
      # ── 푸시 알림(선택). 셋 다 비우면 푸시만 꺼진 채 정상 동작한다.
      # 설정 방법은 docs/DEPLOYMENT.md "푸시 알림 설정" 참고.
      # Firebase 서비스 계정 JSON 전체를 한 줄로 넣는다 (Android FCM).
      - key: FIREBASE_SERVICE_ACCOUNT
        sync: false
      # VAPID 개인키, base64url 32바이트 (웹 푸시). 공개키는 서버가 계산한다.
      - key: VAPID_PRIVATE_KEY
        sync: false
      # 웹 푸시 연락처. 예: mailto:본인이메일
      - key: VAPID_SUBJECT
        sync: false
```

- [ ] **Step 2: DEPLOYMENT.md — 푸시 알림 설정 절 추가**

`docs/DEPLOYMENT.md`에서 네 군데를 고친다.

(a) 상단 표의 web 행을 바꾼다.

```markdown
| `web/` (감지 페이지) | GitHub Pages | `https://<아이디>.github.io/<저장소>/` |
```

→

```markdown
| `web/` (감지·보호자 페이지) | GitHub Pages | `https://<아이디>.github.io/<저장소>/` — 보호자 페이지는 `guardian.html` |
```

(b) 2번 절의 환경변수 표 아래 문단 앞에 한 줄을 추가한다.

```markdown
서버가 처음 뜰 때 이 계정이 자동 생성된다(`createsuperuser --noinput`).
```

→

```markdown
푸시 알림용 변수 3개(`FIREBASE_SERVICE_ACCOUNT`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`)도 함께 뜨는데, 지금은 비워 두어도 된다 — 아래 6번 절에서 채운다.

서버가 처음 뜰 때 이 계정이 자동 생성된다(`createsuperuser --noinput`).
```

(c) 절 번호를 민다. `## 7. 문제 해결`을 `## 8. 문제 해결`로 바꾼 뒤, `## 6. 운영할 때 알아둘 것` 자리에 새 6번 절을 끼워 넣고 운영 절을 7번으로 민다.

```markdown
## 6. 운영할 때 알아둘 것
```

→

```markdown
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
```

(d) 운영 절의 첫 항목과 문제 해결 표의 알림 행을 바꾼다.

```markdown
- **알림은 앱이 떠 있을 때만 온다.** 폴링 구조라 앱이 백그라운드로 가면 멈춘다(README "알려진 한계"). 보호자 폰은 앱을 화면에 켠 채 두는 운용을 권장한다.
```

→

```markdown
- **백그라운드 알림은 6번 절 설정에 달려 있다.** 설정했다면 Android 앱은 FCM으로, 아이폰·데스크톱은 보호자 페이지 푸시로 화면이 꺼져 있어도 알림이 온다. iOS 네이티브 앱만은 여전히 폴링이라 떠 있을 때만 알린다(README "알려진 한계"). 푸시를 설정하지 않았다면 예전처럼 앱을 화면에 켠 채 두는 운용을 권장한다.
```

```markdown
| 폰에 알림이 안 옴 | 앱이 화면에 떠 있는지, iOS 알림 권한을 허용했는지 확인 |
```

→

```markdown
| 폰에 알림이 안 옴 | iOS 앱은 화면에 떠 있어야 한다. Android 앱은 `FIREBASE_SERVICE_ACCOUNT` 설정 여부, 아이폰 PWA는 `VAPID_*` 설정 여부와 "홈 화면 아이콘으로 열었는지"를 확인 |
```

- [ ] **Step 3: README.md 갱신**

`README.md`에서 여섯 군데를 고친다.

(a) 구조도를 바꾼다.

```
[웹캠] → 브라우저 (web/)
           │  MediaPipe로 랜드마크 추출 → 상태머신 판정
           │  ※ 영상·랜드마크 전부 브라우저 밖으로 안 나감
           │
           └─ 낙상 확정 시에만 1회
              POST /api/falls/  (Token 헤더)
                      │
                 [Django + SQLite]  (backend/)
                      │
              GET /api/falls/  ← 5초마다 폴링
                      │
                 [Flutter] → 새 id 발견 시 로컬 알림  (app/)
```

→

```
[웹캠] → 브라우저 (web/) — 감지 페이지
           │  MediaPipe로 랜드마크 추출 → 상태머신 판정
           │  ※ 영상·랜드마크 전부 브라우저 밖으로 안 나감
           │  ※ 전송 실패분은 localStorage 큐에 보관했다가 재전송
           │
           └─ 낙상 확정 시에만 1회
              POST /api/falls/  (Token 헤더, 재전송 중복은 서버가 흡수)
                      │
                 [Django + SQLite]  (backend/)
                      │
        ┌─────────────┼──────────────┐
   FCM 푸시(즉시)   웹 푸시(즉시)   GET /api/falls/ ← 5초 폴링
        │             │              │
  [Flutter 앱      [보호자 페이지   [Flutter 앱 iOS]
   Android]         PWA·브라우저]    새 id 발견 시 로컬 알림  (app/)
```

(b) 실행 방법 2번의 접속 안내를 바꾼다.

```markdown
`http://127.0.0.1:5500`에서 로그인(첫 사용이면 회원가입) → 방 선택 → 감지 시작 → 카메라 권한 허용.
```

→

```markdown
`http://127.0.0.1:5500`에서 로그인(첫 사용이면 회원가입) → 방 선택(없으면 그 자리에서 추가) → 감지 시작 → 카메라 권한 허용.

보호자 페이지는 `http://127.0.0.1:5500/guardian.html`이다. 같은 계정으로 로그인하면 낙상 목록 확인, 방·연락처 관리, 브라우저 푸시 구독을 할 수 있다.
```

(c) 테스트 블록을 바꾼다.

```bash
cd backend && .venv/bin/python -m pytest    # 7개 — 인증·소유권·멱등성
cd web     && npm test                       # 10개 — 상태머신 시나리오
cd app     && flutter test                   # 4개 — 새 이벤트 판별
```

→

```bash
cd backend && .venv/bin/python -m pytest    # 32개 — 인증·소유권·방·프로필·푸시·전송 멱등성
cd web     && npm test                       # 15개 — 상태머신 시나리오 + 오프라인 큐
cd app     && flutter test                   # 6개 — 새 이벤트 판별 + 알림 소스 규칙
```

(d) 알려진 한계의 세 항목을 바꾼다.

```markdown
- **백그라운드 알림 불가** — 폴링 방식이라 앱이 백그라운드로 가면 멈춘다. 실제 제품이라면 FCM이 필요하다. Firebase 설정에서 깨질 지점이 많아 시연 안정성을 택했다.
```

→

```markdown
- **iOS 네이티브 앱만 백그라운드 알림이 없다** — Android 앱은 FCM으로, 브라우저·아이폰은 보호자 페이지(guardian.html)를 홈 화면에 추가한 PWA의 표준 웹 푸시로 백그라운드에서도 알림을 받는다(2026-07-23 추가, iOS 16.4+). iOS 네이티브 푸시(APNs)는 유료 개발자 계정이 필요해 범위 밖에 남겼다 — 아이폰 보호자는 PWA를 쓰면 된다.
```

```markdown
- **낙상 전송 유실** — POST 3회 재시도 후 포기하고 배너만 띄운다. 실제 제품이라면 localStorage 큐가 필요하다.
```

→

```markdown
- **전송 큐는 감지 브라우저 안에만 있다** — 전송 실패분은 localStorage 큐(`fall_queue`)에 보관했다가 페이지 재접속·온라인 복귀·60초 주기마다 재전송하고, 재전송 중복은 서버의 유니크 제약이 흡수한다(2026-07-23 추가). 다만 감지 기기의 브라우저 데이터를 지우면 대기분도 함께 사라진다.
```

```markdown
- **방 등록·연락처 관리 화면 없음** — 방은 고정 선택지 4개, 연락처는 상수다. 회원가입은 웹·앱 양쪽에 있다(2026-07-18 추가). 가입이 공개라 임의 계정 생성은 막지 않지만, 낙상 데이터는 계정별로 격리된다.
```

→

```markdown
- **보호자는 계정당 한 명 전제다** — 방 등록·수정·삭제와 어르신 연락처는 보호자 페이지·앱 설정에서 관리한다(2026-07-23 추가 — 고정 4개 선택지와 하드코딩 번호를 대체). 다중 보호자는 범위 밖이라 필요하면 계정을 공유한다. 회원가입은 웹·앱 양쪽에 있고(2026-07-18 추가) 가입이 공개라 임의 계정 생성은 막지 않지만, 낙상 데이터는 계정별로 격리된다.
```

(e) 문서 목록을 바꾼다.

```markdown
- [배포 가이드](docs/DEPLOYMENT.md) ([HTML판](docs/deploy-guide.html))
- [설계](docs/superpowers/specs/2026-07-17-fall-detection-design.md)
- [구현 계획](docs/superpowers/plans/2026-07-17-fall-detection.md)
- [결정 기록](context-notes.md)
```

→

```markdown
- [배포 가이드](docs/DEPLOYMENT.md) ([HTML판](docs/deploy-guide.html))
- [설계 — 감지 파이프라인 (2026-07-17)](docs/superpowers/specs/2026-07-17-fall-detection-design.md)
- [구현 계획 — 감지 파이프라인 (2026-07-17)](docs/superpowers/plans/2026-07-17-fall-detection.md)
- [설계 — 제품 완성도 라운드 (2026-07-23)](docs/superpowers/specs/2026-07-23-product-completeness-design.md)
- [구현 계획 — 제품 완성도 라운드 (2026-07-23)](docs/superpowers/plans/2026-07-23-product-completeness.md)
- [결정 기록](context-notes.md)
```

(f) README 상단 요약(4개 필드 1회 전송 문구)은 그대로 두되, 큐 문구와 어긋나지 않는지 눈으로 확인만 한다 — "낙상이 확정된 순간에만 전송"은 큐 재전송과 모순되지 않는다(같은 4개 필드를 다시 보낼 뿐이다).

- [ ] **Step 4: 링크·경로 실재 확인과 전체 테스트**

Run: `ls docs/superpowers/specs/2026-07-23-product-completeness-design.md docs/superpowers/plans/2026-07-23-product-completeness.md web/guardian.html web/manifest.webmanifest`
Expected: 4개 경로 모두 출력(없는 파일이 있으면 해당 태스크가 미완이다).

Run: `cd backend && .venv/bin/python -m pytest -q && cd ../web && npm test && cd ../app && flutter test`
Expected: `32 passed` / `Tests  15 passed` / `All tests passed!` (6개)

- [ ] **Step 5: 커밋**

```bash
git add render.yaml docs/DEPLOYMENT.md README.md
git commit -m "docs: 푸시·오프라인 큐·방 관리 반영 — 배포 가이드와 README 갱신"
```
