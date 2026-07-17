# 노인 낙상 감지 시스템 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 브라우저에서 낙상을 감지해 영상을 밖으로 내보내지 않고 보호자 앱에 알림을 보내는 시스템을 만든다.

**Architecture:** 웹캠 영상은 브라우저 안에서 MediaPipe Pose로 관절 좌표가 되고, 3단계 상태머신(속도 → 자세 → 시간)이 낙상을 판정한다. 확정된 순간에만 텍스트 4개 필드가 Django로 POST된다. Flutter 앱은 5초마다 목록 API를 폴링해 새 id를 발견하면 로컬 알림을 띄운다.

**Tech Stack:** Django 6.0.7 + DRF 3.17.1 + SQLite / 순수 ESM JavaScript + MediaPipe tasks-vision 0.10.35 + Vitest 3 / Flutter 3.44 + Dart 3.12

설계 문서: [docs/superpowers/specs/2026-07-17-fall-detection-design.md](../specs/2026-07-17-fall-detection-design.md)

---

## Global Constraints

모든 태스크의 요구사항에 아래가 암묵적으로 포함된다.

- **영상·이미지·랜드마크는 절대 네트워크로 나가지 않는다.** 서버로 가는 것은 `{room_name, room_number, occurred_at, confidence}` 뿐이다. 이 규칙을 어기는 코드는 리뷰에서 거부한다.
- **화면에 원본 영상을 표시하지 않는다.** 검은 배경 + 스켈레톤만. 디버그용 영상 토글도 넣지 않는다.
- **새 소스 파일의 첫 줄은 역할을 설명하는 한국어 주석 1줄이다.** (`'use client'` 같은 지시문 아래, 설정 파일은 제외)
- **`detector.js`는 브라우저 API를 하나도 쓰지 않는다.** `window`, `document`, `performance`, `fetch`, `localStorage` 전부 금지. Node에서 그대로 테스트된다.
- **Δt는 반드시 실제 타임스탬프 차이로 계산한다.** 고정 프레임 간격(33ms)을 가정하지 않는다. 이것이 오탐지 방어의 실제 근거다 (Task 6 참고).
- **버전 고정** — MediaPipe CDN은 `0.10.35`. `@latest` 금지.
- 방 선택지는 `안방 / 부엌 / 거실 / 화장실` 4개 고정.
- 임계값 초기값 — `FALL_VELOCITY: 0.45`, `TILT_UPRIGHT: 45`, `TILT_FALLEN: 60`, `FALLING_WINDOW: 1000`, `FALLEN_HOLD: 5000`, `EMA_ALPHA: 0.4`, `NO_PERSON_TIMEOUT: 2000`
- 임계값을 조정하면 `context-notes.md`의 튜닝 표에 이유와 함께 기록한다.
- 커밋 메시지는 한국어 한 줄. 한 태스크 = 한 커밋.

### API 계약 (Task 1~4가 만들고 7·11·12가 소비한다)

| 메서드 | 경로 | 요청 | 응답 |
|---|---|---|---|
| POST | `/api/auth/login/` | `{username, password}` | `200 {token}` |
| POST | `/api/falls/` | `{room_name, room_number, occurred_at, confidence}` | `201 <FallEvent>` |
| GET | `/api/falls/` | — | `200 [<FallEvent>, ...]` id 역순 |
| POST | `/api/falls/<id>/acknowledge/` | — | `200 <FallEvent>` / `404` |

`<FallEvent>` = `{id, room_name, room_number, occurred_at, created_at, confidence, acknowledged_at}`

- 인증 헤더는 `Authorization: Token <key>`. `/api/auth/login/` 외 전부 필수, 없으면 `401`.
- `occurred_at`은 ISO 8601 UTC 문자열 (`2026-07-17T07:31:04.123Z`).
- 서버 주소 — 웹 `http://127.0.0.1:8000`, Flutter는 Android `10.0.2.2:8000` / iOS·데스크톱 `127.0.0.1:8000`.

---

## File Structure

```
backend/
├── manage.py
├── pytest.ini
├── requirements.txt
├── config/
│   ├── settings.py      INSTALLED_APPS, DRF, CORS
│   └── urls.py          /api/ → falls.urls
└── falls/
    ├── models.py        FallEvent (유일한 모델)
    ├── serializers.py   FallEventSerializer
    ├── views.py         FallEventListCreate, acknowledge
    ├── urls.py          라우팅
    └── tests.py         pytest 6개

web/
├── package.json         Vitest만 dev 의존성
├── index.html           로그인
├── detect.html          방 선택 + 감지
├── css/style.css
├── js/
│   ├── detector.js      순수 상태머신 (브라우저 API 미사용)
│   ├── pose.js          MediaPipe 초기화 + 웹캠 루프
│   ├── overlay.js       검은 배경 + 스켈레톤
│   ├── api.js           fetch 래퍼 + 토큰
│   └── main.js          조립
└── tests/
    ├── helpers.js       가짜 랜드마크 시퀀스
    └── detector.test.js 7개 시나리오

app/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── api.dart         http + 토큰 + 플랫폼별 baseUrl
│   ├── models.dart      FallEvent
│   ├── notifications.dart
│   ├── poller.dart      NewEventTracker (순수) + FallPoller
│   └── screens/
│       ├── login.dart
│       ├── fall_list.dart
│       └── fall_detail.dart
└── test/
    └── poller_test.dart
```

`detector.js`와 `poller.dart`의 `NewEventTracker`가 이 설계의 두 순수 모듈이다. 나머지는 전부 I/O 껍데기다. 테스트는 이 둘에만 집중한다.

---

## Task 1: Django 골격 + FallEvent 모델

**Files:**
- Create: `backend/requirements.txt`, `backend/manage.py`(생성됨), `backend/config/settings.py`(생성 후 수정), `backend/falls/models.py`

**Interfaces:**
- Produces: `falls.models.FallEvent` — 필드 `guardian(FK User)`, `room_name(str)`, `room_number(int)`, `occurred_at(datetime)`, `created_at(datetime)`, `confidence(float)`, `acknowledged_at(datetime|None)`. `Meta.ordering = ["-id"]`

- [ ] **Step 1: 프로젝트 생성**

```bash
cd /Users/munhokang/82107/weniv_project
mkdir -p backend && cd backend
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install django djangorestframework django-cors-headers pytest pytest-django
.venv/bin/django-admin startproject config .
.venv/bin/python manage.py startapp falls
```

- [ ] **Step 2: 의존성 고정**

실측 검증된 버전이다. `backend/requirements.txt`

```
Django==6.0.7
djangorestframework==3.17.1
django-cors-headers==4.9.0
pytest==9.1.1
pytest-django==4.12.0
```

- [ ] **Step 3: settings.py 수정**

`backend/config/settings.py`에서 `INSTALLED_APPS`와 `MIDDLEWARE`를 아래로 교체하고, 파일 맨 끝에 나머지를 덧붙인다.

```python
INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "rest_framework.authtoken",
    "falls",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]
```

파일 끝에 추가한다.

```python
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework.authentication.TokenAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
}

# 감지 페이지는 Live Server(:5500)에서, Django는 :8000에서 뜨므로 오리진이 다르다.
CORS_ALLOWED_ORIGINS = [
    "http://127.0.0.1:5500",
    "http://localhost:5500",
]
```

- [ ] **Step 4: FallEvent 모델 작성**

`backend/falls/models.py` 전체를 교체한다.

```python
# 낙상 이벤트 1건을 저장하는 유일한 모델 (방 정보를 이벤트에 직접 들고 있다)

from django.conf import settings
from django.db import models


class FallEvent(models.Model):
    ROOM_CHOICES = [("안방", "안방"), ("부엌", "부엌"), ("거실", "거실"), ("화장실", "화장실")]

    guardian = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="fall_events"
    )
    room_name = models.CharField(max_length=20, choices=ROOM_CHOICES)
    room_number = models.PositiveSmallIntegerField()
    occurred_at = models.DateTimeField()  # 클라이언트가 판정한 낙상 시각 (FALLING 진입 시각)
    created_at = models.DateTimeField(auto_now_add=True)
    confidence = models.FloatField()  # 판정 시점 랜드마크 4개의 visibility 평균
    acknowledged_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-id"]  # 목록 API가 최신순이어야 한다

    def __str__(self):
        return f"{self.room_name}{self.room_number} {self.occurred_at:%Y-%m-%d %H:%M:%S}"
```

- [ ] **Step 5: 마이그레이션 생성 및 적용**

```bash
cd backend
.venv/bin/python manage.py makemigrations
.venv/bin/python manage.py migrate
```

Expected: `Create model FallEvent`가 출력되고, `falls.0001_initial... OK`와 `authtoken.0001_initial... OK`가 보인다.

- [ ] **Step 6: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add backend/
git commit -m "Django 프로젝트 골격과 FallEvent 모델 추가"
```

---

## Task 2: 토큰 인증 로그인 API

**Files:**
- Create: `backend/falls/urls.py`, `backend/pytest.ini`, `backend/falls/tests.py`
- Modify: `backend/config/urls.py` (전체 교체)

**Interfaces:**
- Consumes: Task 1의 `FallEvent`
- Produces: `POST /api/auth/login/` → `{token}`. 미인증 요청은 `401`.

- [ ] **Step 1: pytest 설정**

`backend/pytest.ini`

```ini
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = test_*.py tests.py
```

- [ ] **Step 2: 실패하는 테스트 작성**

`backend/falls/tests.py`

```python
# API의 인증·소유권·멱등성을 검증하는 테스트

import pytest
from django.contrib.auth.models import User
from rest_framework.test import APIClient


@pytest.fixture
def guardian(db):
    return User.objects.create_user(username="g1", password="pw12345")


def test_anonymous_gets_401(db):
    assert APIClient().get("/api/falls/").status_code == 401


def test_login_returns_token(guardian):
    r = APIClient().post(
        "/api/auth/login/", {"username": "g1", "password": "pw12345"}, format="json"
    )
    assert r.status_code == 200
    assert "token" in r.data
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd backend && .venv/bin/python -m pytest falls/tests.py -q
```

Expected: FAIL. 두 테스트 모두 `404`를 받는다 (`assert 404 == 401`).

- [ ] **Step 4: 라우팅 작성**

`backend/falls/urls.py`

```python
# /api/ 하위 엔드포인트 라우팅

from django.urls import path
from rest_framework.authtoken.views import obtain_auth_token

urlpatterns = [
    path("auth/login/", obtain_auth_token),
]
```

`backend/config/urls.py` **파일 전체를 아래로 교체한다.** Django 6.0의 생성 템플릿은 홑따옴표(`path('admin/', ...)`)를 쓴다. 부분 치환을 시도하면 조용히 실패해 모든 라우트가 404가 된다.

```python
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("falls.urls")),
]
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd backend && .venv/bin/python -m pytest falls/tests.py -q
```

Expected: `2 passed`

- [ ] **Step 6: 커밋**

```bash
git add backend/
git commit -m "DRF 토큰 인증과 로그인 API 추가"
```

---

## Task 3: 낙상 등록·조회 API

**Files:**
- Create: `backend/falls/serializers.py`
- Modify: `backend/falls/views.py`, `backend/falls/urls.py`, `backend/falls/tests.py`

**Interfaces:**
- Consumes: Task 1의 `FallEvent`, Task 2의 라우팅
- Produces: `POST /api/falls/`(201), `GET /api/falls/`(200, id 역순). `FallEventSerializer`의 필드는 `["id", "room_name", "room_number", "occurred_at", "created_at", "confidence", "acknowledged_at"]`

- [ ] **Step 1: 실패하는 테스트 추가**

`backend/falls/tests.py`의 import를 아래로 바꾸고 픽스처·헬퍼·테스트를 덧붙인다.

```python
# API의 인증·소유권·멱등성을 검증하는 테스트

import pytest
from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from falls.models import FallEvent


@pytest.fixture
def guardian(db):
    return User.objects.create_user(username="g1", password="pw12345")


@pytest.fixture
def other(db):
    return User.objects.create_user(username="g2", password="pw12345")


def client_for(user):
    c = APIClient()
    token, _ = Token.objects.get_or_create(user=user)
    c.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return c


def make_event(user, room_name="안방", room_number=1):
    return FallEvent.objects.create(
        guardian=user,
        room_name=room_name,
        room_number=room_number,
        occurred_at=timezone.now(),
        confidence=0.9,
    )
```

기존 `test_anonymous_gets_401`, `test_login_returns_token`은 그대로 두고 아래를 덧붙인다.

```python
def test_list_excludes_other_users_events(guardian, other):
    make_event(other)
    mine = make_event(guardian)
    r = client_for(guardian).get("/api/falls/")
    assert r.status_code == 200
    assert [e["id"] for e in r.data] == [mine.id]


def test_list_is_newest_first(guardian):
    first = make_event(guardian)
    second = make_event(guardian)
    r = client_for(guardian).get("/api/falls/")
    assert [e["id"] for e in r.data] == [second.id, first.id]


def test_post_forces_guardian_to_requester(guardian, other):
    r = client_for(guardian).post(
        "/api/falls/",
        {
            "room_name": "부엌",
            "room_number": 2,
            "occurred_at": timezone.now().isoformat(),
            "confidence": 0.88,
            "guardian": other.id,  # 클라이언트가 남의 id를 보내도 무시되어야 한다
        },
        format="json",
    )
    assert r.status_code == 201
    assert FallEvent.objects.get(pk=r.data["id"]).guardian == guardian
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd backend && .venv/bin/python -m pytest falls/tests.py -q
```

Expected: FAIL. 새 테스트 3개가 `404`를 받는다.

- [ ] **Step 3: 시리얼라이저 작성**

`backend/falls/serializers.py`

```python
# FallEvent를 JSON으로 변환하는 시리얼라이저

from rest_framework import serializers

from .models import FallEvent


class FallEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = FallEvent
        fields = [
            "id",
            "room_name",
            "room_number",
            "occurred_at",
            "created_at",
            "confidence",
            "acknowledged_at",
        ]
        # guardian은 필드에 없다. 요청자로 강제되므로 클라이언트가 건드릴 수 없다.
        read_only_fields = ["id", "created_at", "acknowledged_at"]
```

- [ ] **Step 4: 뷰 작성**

`backend/falls/views.py` 전체를 교체한다.

```python
# 낙상 이벤트 등록·조회 API 뷰

from rest_framework import generics

from .models import FallEvent
from .serializers import FallEventSerializer


class FallEventListCreate(generics.ListCreateAPIView):
    serializer_class = FallEventSerializer

    def get_queryset(self):
        # 남의 이벤트가 절대 새어나가지 않도록 요청자로 필터링한다
        return FallEvent.objects.filter(guardian=self.request.user)

    def perform_create(self, serializer):
        serializer.save(guardian=self.request.user)
```

- [ ] **Step 5: 라우팅 추가**

`backend/falls/urls.py` 전체를 교체한다.

```python
# /api/ 하위 엔드포인트 라우팅

from django.urls import path
from rest_framework.authtoken.views import obtain_auth_token

from . import views

urlpatterns = [
    path("auth/login/", obtain_auth_token),
    path("falls/", views.FallEventListCreate.as_view()),
]
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd backend && .venv/bin/python -m pytest falls/tests.py -q
```

Expected: `5 passed`

- [ ] **Step 7: 커밋**

```bash
git add backend/
git commit -m "낙상 등록·조회 API 추가"
```

---

## Task 4: acknowledge API + curl 검증

**Files:**
- Modify: `backend/falls/views.py`, `backend/falls/urls.py`, `backend/falls/tests.py`

**Interfaces:**
- Produces: `POST /api/falls/<id>/acknowledge/` → `200 <FallEvent>`. 남의 이벤트는 `404`. 두 번 호출해도 첫 `acknowledged_at`을 유지한다.

- [ ] **Step 1: 실패하는 테스트 추가**

`backend/falls/tests.py` 끝에 덧붙인다.

```python
def test_acknowledge_other_users_event_404(guardian, other):
    theirs = make_event(other)
    r = client_for(guardian).post(f"/api/falls/{theirs.id}/acknowledge/")
    assert r.status_code == 404


def test_acknowledge_is_idempotent(guardian):
    e = make_event(guardian)
    c = client_for(guardian)
    first = c.post(f"/api/falls/{e.id}/acknowledge/").data["acknowledged_at"]
    assert first is not None
    second = c.post(f"/api/falls/{e.id}/acknowledge/").data["acknowledged_at"]
    assert second == first  # 두 번째 호출이 시각을 덮어쓰면 안 된다
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd backend && .venv/bin/python -m pytest falls/tests.py -q
```

Expected: FAIL. `test_acknowledge_other_users_event_404`는 `assert 404 == 404`가 우연히 통과할 수 있으나, `test_acknowledge_is_idempotent`는 `AttributeError: 'HttpResponseNotFound' object has no attribute 'data'`로 실패한다.

- [ ] **Step 3: 뷰에 acknowledge 추가**

`backend/falls/views.py`의 import를 늘리고 함수를 덧붙인다.

```python
# 낙상 이벤트 등록·조회·확인 API 뷰

from django.utils import timezone
from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .models import FallEvent
from .serializers import FallEventSerializer


class FallEventListCreate(generics.ListCreateAPIView):
    serializer_class = FallEventSerializer

    def get_queryset(self):
        # 남의 이벤트가 절대 새어나가지 않도록 요청자로 필터링한다
        return FallEvent.objects.filter(guardian=self.request.user)

    def perform_create(self, serializer):
        serializer.save(guardian=self.request.user)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def acknowledge(request, pk):
    # guardian까지 걸어서 조회하므로 남의 이벤트는 존재 자체가 드러나지 않고 404가 된다
    try:
        event = FallEvent.objects.get(pk=pk, guardian=request.user)
    except FallEvent.DoesNotExist:
        return Response({"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND)

    if event.acknowledged_at is None:  # 첫 확인 시각을 보존한다
        event.acknowledged_at = timezone.now()
        event.save(update_fields=["acknowledged_at"])

    return Response(FallEventSerializer(event).data)
```

- [ ] **Step 4: 라우팅 추가**

`backend/falls/urls.py`의 `urlpatterns`에 한 줄을 더한다.

```python
urlpatterns = [
    path("auth/login/", obtain_auth_token),
    path("falls/", views.FallEventListCreate.as_view()),
    path("falls/<int:pk>/acknowledge/", views.acknowledge),
]
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd backend && .venv/bin/python -m pytest falls/tests.py -q
```

Expected: `7 passed`

- [ ] **Step 6: 시연용 계정 생성 후 curl로 전 구간 확인**

```bash
cd backend
.venv/bin/python manage.py createsuperuser --username guardian --email a@b.c --noinput
.venv/bin/python manage.py shell -c "from django.contrib.auth.models import User; u=User.objects.get(username='guardian'); u.set_password('pw12345'); u.save()"
.venv/bin/python manage.py runserver 8000 &
sleep 3
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/api/auth/login/ \
  -H 'Content-Type: application/json' \
  -d '{"username":"guardian","password":"pw12345"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
echo "TOKEN=$TOKEN"
curl -s -X POST http://127.0.0.1:8000/api/falls/ \
  -H "Authorization: Token $TOKEN" -H 'Content-Type: application/json' \
  -d '{"room_name":"거실","room_number":1,"occurred_at":"2026-07-17T07:00:00Z","confidence":0.91}'
echo
curl -s http://127.0.0.1:8000/api/falls/ -H "Authorization: Token $TOKEN"
```

Expected: `TOKEN=`에 40자 문자열, POST가 `{"id":1,...,"acknowledged_at":null}`, GET이 그 이벤트 1건의 배열.

확인 후 `kill %1`로 서버를 내린다.

- [ ] **Step 7: 커밋**

```bash
git add backend/
git commit -m "낙상 확인(acknowledge) API 추가"
```

---

## Task 5: web 프로젝트 설정 + detector 상태머신 happy path

이 태스크와 Task 6이 이 프로젝트에서 가장 중요하다. 웹캠 없이 상태머신을 완성해두면, 감지 페이지에서 문제가 생겼을 때 원인이 판정 로직이 아니라 랜드마크 품질임을 바로 안다.

**Files:**
- Create: `web/package.json`, `web/tests/helpers.js`, `web/tests/detector.test.js`, `web/js/detector.js`

**Interfaces:**
- Produces:
  - `CONFIG` — 임계값 객체 (Global Constraints의 7개 키)
  - `LM` — `{L_SHOULDER: 11, R_SHOULDER: 12, L_HIP: 23, R_HIP: 24}`
  - `createDetector(config = CONFIG)` → `{ update(landmarks, t), state }`
  - `update(landmarks, t)` — `landmarks`는 33개 `{x, y, z, visibility}` 배열 또는 빈 배열, `t`는 ms. 반환 `{state, fall, tilt, hipVelocity}`
  - `state` ∈ `"NO_PERSON" | "STANDING" | "FALLING" | "FALLEN" | "ALERTED"`, 초기값 `"NO_PERSON"`
  - `fall` — 낙상 확정 프레임에서만 `{occurredAt, confidence}`, 그 외 `null`

- [ ] **Step 1: npm 프로젝트 생성**

```bash
cd /Users/munhokang/82107/weniv_project
mkdir -p web/js web/tests web/css && cd web
```

`web/package.json`

```json
{
  "name": "fall-detection-web",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "devDependencies": {
    "vitest": "^3.2.7"
  }
}
```

```bash
cd web && npm install
```

- [ ] **Step 2: 테스트 헬퍼 작성**

`web/tests/helpers.js`. `poseAt`은 `tilt`를 그대로 만들어내는 역함수다 — 엉덩이 중점에서 `tilt`만큼 기울어진 방향으로 몸통 길이만큼 떨어진 곳에 어깨 중점을 놓으면, `detector`가 계산한 tilt가 정확히 입력값이 된다.

```js
// 가짜 랜드마크 시퀀스를 만들어 detector를 구동하는 테스트 헬퍼

const TORSO = 0.25; // 정규화 좌표계에서의 몸통 길이

export function poseAt({ hipY, tilt, visibility = 0.9 }) {
  const rad = (tilt * Math.PI) / 180;
  const hip = { x: 0.5, y: hipY };
  const sh = { x: hip.x + TORSO * Math.sin(rad), y: hip.y - TORSO * Math.cos(rad) };
  const lm = Array.from({ length: 33 }, () => ({ x: 0, y: 0, z: 0, visibility: 0 }));
  lm[11] = { x: sh.x - 0.1, y: sh.y, z: 0, visibility };
  lm[12] = { x: sh.x + 0.1, y: sh.y, z: 0, visibility };
  lm[23] = { x: hip.x - 0.08, y: hip.y, z: 0, visibility };
  lm[24] = { x: hip.x + 0.08, y: hip.y, z: 0, visibility };
  return lm;
}

const lerp = (a, b, p) => a + (b - a) * p;

export function segment({ startT, durationMs, from, to, fps = 30 }) {
  const step = 1000 / fps;
  const frames = [];
  for (let t = 0; t <= durationMs; t += step) {
    const p = durationMs === 0 ? 1 : t / durationMs;
    frames.push({
      t: startT + t,
      landmarks: poseAt({ hipY: lerp(from.hipY, to.hipY, p), tilt: lerp(from.tilt, to.tilt, p) }),
    });
  }
  return frames;
}

export function gap({ startT, durationMs, fps = 30 }) {
  const step = 1000 / fps;
  const frames = [];
  for (let t = 0; t <= durationMs; t += step) frames.push({ t: startT + t, landmarks: [] });
  return frames;
}

export function run(detector, frames) {
  const falls = [];
  const states = [];
  let firstFallingAt = null;
  for (const f of frames) {
    const r = detector.update(f.landmarks, f.t);
    states.push(r.state);
    if (r.state === "FALLING" && firstFallingAt === null) firstFallingAt = f.t;
    if (r.fall) falls.push(r.fall);
  }
  return { falls, states, firstFallingAt, saw: (s) => states.includes(s) };
}

export const STAND = { hipY: 0.5, tilt: 5 };
export const FLOOR = { hipY: 0.8, tilt: 80 };
export const SEATED = { hipY: 0.75, tilt: 10 };
```

- [ ] **Step 3: 실패하는 테스트 작성 (낙상 확정 시나리오)**

happy path를 먼저 쓴다. 오탐지 방어 시나리오를 먼저 쓰면 "아무것도 안 하는 detector"로도 통과해버려 테스트가 무의미해진다.

`web/tests/detector.test.js`

```js
// detector.js 상태머신의 낙상 시나리오 검증

import { describe, it, expect } from "vitest";

import { createDetector } from "../js/detector.js";
import { segment, run, STAND, FLOOR } from "./helpers.js";

const standing = (startT, durationMs) => segment({ startT, durationMs, from: STAND, to: STAND });
const holdFloor = (startT, durationMs) => segment({ startT, durationMs, from: FLOOR, to: FLOOR });
const fastFall = (startT) => segment({ startT, durationMs: 300, from: STAND, to: FLOOR });

describe("detector", () => {
  it("빠르게 넘어져 5초 유지 → 낙상 1건, occurred_at은 FALLING 진입 시각", () => {
    const frames = [...standing(0, 1000), ...fastFall(1000), ...holdFloor(1300, 6700)];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
    expect(r.falls[0].occurredAt).toBe(r.firstFallingAt);
    expect(r.falls[0].occurredAt).toBeLessThan(1400); // 확정 시각(~6250)이 아니라 넘어진 시각이다
    expect(r.falls[0].confidence).toBeCloseTo(0.9, 5);
  });
});
```

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd web && npx vitest run
```

Expected: FAIL — `Failed to load url ../js/detector.js`

- [ ] **Step 5: detector.js 구현**

`web/js/detector.js`

```js
// 랜드마크 시퀀스로 낙상을 판정하는 순수 상태머신 (브라우저 API 미사용)

export const CONFIG = {
  FALL_VELOCITY: 0.45, // 정규화 y단위/초 — 이 위면 낙하 중
  TILT_UPRIGHT: 45, // ° — 이 아래면 서 있음
  TILT_FALLEN: 60, // ° — 이 위면 수평
  FALLING_WINDOW: 1000, // ms — FALLING 유효 시간
  FALLEN_HOLD: 5000, // ms — 미회복 확정 시간
  EMA_ALPHA: 0.4,
  NO_PERSON_TIMEOUT: 2000, // ms — 이만큼 미검출이면 NO_PERSON
};

export const LM = { L_SHOULDER: 11, R_SHOULDER: 12, L_HIP: 23, R_HIP: 24 };

const REQUIRED = [LM.L_SHOULDER, LM.R_SHOULDER, LM.L_HIP, LM.R_HIP];

const mid = (a, b) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });

function hasRequired(landmarks) {
  if (!landmarks || landmarks.length === 0) return false;
  return REQUIRED.every((i) => landmarks[i] != null);
}

export function createDetector(config = CONFIG) {
  const c = { ...CONFIG, ...config };

  let state = "NO_PERSON";
  let tilt = null;
  let hipVelocity = 0;
  let prevHip = null;
  let prevT = null;
  let lastSeenAt = null;
  let fallingAt = null;
  let fallenAt = null;

  // 설계에 명시된 심층 방어다. 다만 오탐지를 실제로 막는 것은 아래 Δt 계산이지
  // 이 초기화가 아니다 — NO_PERSON은 2초 이상 미검출일 때만 발동하므로
  // 복귀 시 Δt가 항상 2000ms 이상이고 가짜 속도는 임계값에 못 미친다.
  const resetMotion = () => {
    tilt = null;
    hipVelocity = 0;
    prevHip = null;
    prevT = null;
  };

  const ema = (prev, raw) => (prev === null ? raw : c.EMA_ALPHA * raw + (1 - c.EMA_ALPHA) * prev);

  function update(landmarks, t) {
    if (!hasRequired(landmarks)) {
      if (lastSeenAt === null || t - lastSeenAt > c.NO_PERSON_TIMEOUT) {
        state = "NO_PERSON";
        resetMotion();
      }
      // 미검출 유예 구간에서는 판정할 지표가 없으므로 상태를 유지한다
      return { state, fall: null, tilt, hipVelocity };
    }

    lastSeenAt = t;
    const shoulderMid = mid(landmarks[LM.L_SHOULDER], landmarks[LM.R_SHOULDER]);
    const hipMid = mid(landmarks[LM.L_HIP], landmarks[LM.R_HIP]);

    const dx = shoulderMid.x - hipMid.x;
    const dy = shoulderMid.y - hipMid.y;
    tilt = ema(tilt, (Math.atan2(Math.abs(dx), Math.abs(dy)) * 180) / Math.PI);

    // Δt는 반드시 실제 타임스탬프 차이다. 고정 프레임 간격을 가정하면
    // 미검출 복귀 시 좌표 점프가 임계값의 20배짜리 가짜 속도로 잡힌다.
    let rawVelocity = 0;
    if (prevHip !== null && t > prevT) {
      rawVelocity = (hipMid.y - prevHip.y) / ((t - prevT) / 1000);
    }
    hipVelocity = ema(hipVelocity, rawVelocity);
    prevHip = hipMid;
    prevT = t;

    let fall = null;

    // 위에서부터 평가하고 처음 일치하는 규칙 하나만 적용한다
    switch (state) {
      case "NO_PERSON":
        state = "STANDING";
        break;

      case "STANDING":
        if (hipVelocity > c.FALL_VELOCITY) {
          state = "FALLING"; // 1차 관문: 속도 — 천천히 눕기를 거른다
          fallingAt = t;
        }
        break;

      case "FALLING":
        if (tilt > c.TILT_FALLEN) {
          state = "FALLEN"; // 2차 관문: 자세 — 급히 앉기를 거른다
          fallenAt = t;
        } else if (t - fallingAt > c.FALLING_WINDOW) {
          state = "STANDING";
        }
        break;

      case "FALLEN":
        if (tilt < c.TILT_UPRIGHT) {
          state = "STANDING"; // 오탐지 취소, 전송 안 함
        } else if (t - fallenAt > c.FALLEN_HOLD) {
          state = "ALERTED"; // 3차 관문: 시간 — 자가 회복을 거른다
          fall = {
            occurredAt: fallingAt, // 확정 시각이 아니라 실제로 넘어진 순간
            confidence:
              REQUIRED.reduce((s, i) => s + (landmarks[i].visibility ?? 0), 0) / REQUIRED.length,
          };
        }
        break;

      case "ALERTED":
        // 다시 일어나야만 재무장된다. 누워 있는 동안 중복 전송이 없는 이유다.
        if (tilt < c.TILT_UPRIGHT) state = "STANDING";
        break;
    }

    return { state, fall, tilt, hipVelocity };
  }

  return {
    update,
    get state() {
      return state;
    },
  };
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd web && npx vitest run
```

Expected: `Tests  1 passed (1)`

- [ ] **Step 7: 커밋**

```bash
git add web/
git commit -m "detector 상태머신의 낙상 확정 경로 추가"
```

---

## Task 6: detector 오탐지 방어 시나리오

Task 5의 detector는 이미 전체 상태머신을 담고 있다. 이 태스크는 **오탐지 방어 논리가 실제로 작동하는지 증명하는** 테스트를 채우고, 뮤테이션으로 테스트에 이빨이 있는지 확인한다. 테스트가 먼저 통과해도 놀라지 말고, Step 3의 뮤테이션 검증을 반드시 수행한다.

**Files:**
- Modify: `web/tests/detector.test.js`

**Interfaces:**
- Consumes: Task 5의 `createDetector`, `web/tests/helpers.js`의 `segment`/`gap`/`run`/`STAND`/`FLOOR`/`SEATED`

- [ ] **Step 1: 나머지 6개 시나리오 작성**

`web/tests/detector.test.js` 전체를 아래로 교체한다.

```js
// detector.js 상태머신의 7개 낙상 시나리오 검증

import { describe, it, expect } from "vitest";

import { createDetector } from "../js/detector.js";
import { segment, gap, run, STAND, FLOOR, SEATED } from "./helpers.js";

const standing = (startT, durationMs) => segment({ startT, durationMs, from: STAND, to: STAND });
const holdFloor = (startT, durationMs) => segment({ startT, durationMs, from: FLOOR, to: FLOOR });
const fastFall = (startT) => segment({ startT, durationMs: 300, from: STAND, to: FLOOR });
const getUp = (startT) => segment({ startT, durationMs: 500, from: FLOOR, to: STAND });

describe("detector", () => {
  it("천천히 눕기 → 알림 없음 (FALLING 미진입)", () => {
    const frames = [
      ...standing(0, 1000),
      ...segment({ startT: 1000, durationMs: 4000, from: STAND, to: FLOOR }),
      ...holdFloor(5000, 8000),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLING")).toBe(false); // 1차 관문에서 걸러진다
  });

  it("빠르게 주저앉기 → 알림 없음 (tilt 미달)", () => {
    const frames = [
      ...standing(0, 1000),
      ...segment({ startT: 1000, durationMs: 300, from: STAND, to: SEATED }),
      ...segment({ startT: 1300, durationMs: 3000, from: SEATED, to: SEATED }),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLING")).toBe(true); // 속도는 넘었지만
    expect(r.saw("FALLEN")).toBe(false); // 2차 관문에서 걸러진다
  });

  it("빠르게 넘어져 3초 만에 일어남 → 알림 없음 (자가 회복)", () => {
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 3000),
      ...getUp(4300),
      ...standing(4800, 2000),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLEN")).toBe(true); // 넘어진 것은 맞지만
    expect(r.saw("ALERTED")).toBe(false); // 3차 관문에서 걸러진다
  });

  it("빠르게 넘어져 5초 유지 → 낙상 1건, occurred_at은 FALLING 진입 시각", () => {
    const frames = [...standing(0, 1000), ...fastFall(1000), ...holdFloor(1300, 6700)];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
    expect(r.falls[0].occurredAt).toBe(r.firstFallingAt);
    expect(r.falls[0].occurredAt).toBeLessThan(1400); // 확정 시각(~6250)이 아니라 넘어진 시각이다
    expect(r.falls[0].confidence).toBeCloseTo(0.9, 5);
  });

  it("넘어진 채 10초 더 유지 → 여전히 1건 (중복 없음)", () => {
    const frames = [...standing(0, 1000), ...fastFall(1000), ...holdFloor(1300, 16700)];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(1);
  });

  it("넘어졌다 일어났다 다시 넘어짐 → 2건", () => {
    const frames = [
      ...standing(0, 1000),
      ...fastFall(1000),
      ...holdFloor(1300, 6700),
      ...getUp(8000), // ALERTED → STANDING 재무장
      ...standing(8500, 1500),
      ...fastFall(10000),
      ...holdFloor(10300, 6700),
    ];
    const r = run(createDetector(), frames);

    expect(r.falls).toHaveLength(2);
  });

  it("2초 이상 미검출 후 바닥에서 재검출 → NO_PERSON을 거쳐 오탐지 없음", () => {
    const frames = [
      ...standing(0, 1000),
      ...gap({ startT: 1033, durationMs: 3000 }),
      ...segment({ startT: 4033, durationMs: 2000, from: FLOOR, to: FLOOR }),
    ];
    const r = run(createDetector(), frames);

    expect(r.saw("NO_PERSON")).toBe(true);
    expect(r.falls).toHaveLength(0);
    expect(r.saw("FALLING")).toBe(false); // 재검출 시 좌표 점프가 가짜 속도로 잡히면 안 된다
  });
});
```

- [ ] **Step 2: 7개 전부 통과 확인**

```bash
cd web && npx vitest run
```

Expected: `Tests  7 passed (7)`

- [ ] **Step 3: 뮤테이션으로 테스트에 이빨이 있는지 검증**

통과하는 테스트는 구현이 맞아서 통과한 것일 수도, 아무것도 검사하지 않아서 통과한 것일 수도 있다. 구현을 일부러 망가뜨려 테스트가 깨지는지 확인한다.

```bash
cd web
cp js/detector.js /tmp/detector.bak

# 뮤테이션 1: 속도 관문 제거 → "천천히 눕기"가 깨져야 한다
sed -i '' 's/if (hipVelocity > c.FALL_VELOCITY) {/if (true) {/' js/detector.js
npx vitest run 2>&1 | grep "Tests  "
cp /tmp/detector.bak js/detector.js

# 뮤테이션 2: occurred_at을 확정 시각으로 → "occurred_at" 테스트가 깨져야 한다
sed -i '' 's/occurredAt: fallingAt,/occurredAt: t,/' js/detector.js
npx vitest run 2>&1 | grep "Tests  "
cp /tmp/detector.bak js/detector.js

# 뮤테이션 3: ALERTED 미전이 → "중복 없음"이 깨져야 한다
sed -i '' 's/state = "ALERTED";/state = "FALLEN"; fallenAt = t;/' js/detector.js
npx vitest run 2>&1 | grep "Tests  "
cp /tmp/detector.bak js/detector.js

# 뮤테이션 4: NO_PERSON 타임아웃 무력화 → "NO_PERSON" 테스트가 깨져야 한다
sed -i '' 's/NO_PERSON_TIMEOUT: 2000/NO_PERSON_TIMEOUT: 999999/' js/detector.js
npx vitest run 2>&1 | grep "Tests  "
cp /tmp/detector.bak js/detector.js

npx vitest run 2>&1 | grep "Tests  "
```

Expected: 뮤테이션 1은 `3 failed | 4 passed`, 뮤테이션 2·3·4는 각각 `1 failed | 6 passed`, 마지막 복원 후 `7 passed`.

**어느 뮤테이션에서도 7개가 전부 통과한다면 그 테스트는 아무것도 검증하지 않는 것이다.** 그 경우 멈추고 테스트를 고친다.

- [ ] **Step 4: 커밋**

```bash
git add web/
git commit -m "detector 오탐지 방어 시나리오 6개 추가"
```

---

## Task 7: api.js + 로그인 페이지

**Files:**
- Create: `web/js/api.js`, `web/index.html`, `web/css/style.css`

**Interfaces:**
- Consumes: Task 2의 `POST /api/auth/login/`
- Produces:
  - `API_BASE` — `"http://127.0.0.1:8000"`
  - `getToken()` / `setToken(t)` / `clearToken()` — localStorage 키 `"fall_token"`
  - `login(username, password)` → `string` (토큰). 실패 시 `throw new Error(메시지)`
  - `requireToken()` → `string`. 토큰 없으면 `index.html`로 이동
  - `logoutAndRedirect()` — 토큰 폐기 후 `index.html`로 이동

- [ ] **Step 1: api.js 작성**

`web/js/api.js`

```js
// Django API 호출 래퍼와 토큰 보관

export const API_BASE = "http://127.0.0.1:8000";

const TOKEN_KEY = "fall_token";

export const getToken = () => localStorage.getItem(TOKEN_KEY);
export const setToken = (t) => localStorage.setItem(TOKEN_KEY, t);
export const clearToken = () => localStorage.removeItem(TOKEN_KEY);

export function logoutAndRedirect() {
  clearToken();
  location.href = "index.html";
}

export function requireToken() {
  const token = getToken();
  if (!token) location.href = "index.html";
  return token;
}

export async function login(username, password) {
  const res = await fetch(`${API_BASE}/api/auth/login/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error("아이디 또는 비밀번호가 올바르지 않습니다.");
  const { token } = await res.json();
  return token;
}
```

- [ ] **Step 2: 스타일 작성**

`web/css/style.css`

```css
/* 감지 클라이언트 공용 스타일 */

:root {
  --bg: #12141a;
  --fg: #e8eaf0;
  --muted: #8b93a7;
  --accent: #4c8dff;
  --danger: #e5484d;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  padding: 24px;
  background: var(--bg);
  color: var(--fg);
  font: 15px/1.6 -apple-system, "Apple SD Gothic Neo", sans-serif;
}

h1 {
  font-size: 20px;
  margin: 0 0 20px;
}

.card {
  max-width: 380px;
  margin: 64px auto;
  padding: 28px;
  background: #1a1d26;
  border-radius: 12px;
}

label {
  display: block;
  margin: 14px 0 6px;
  color: var(--muted);
  font-size: 13px;
}

input,
select,
button {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid #2b3040;
  border-radius: 8px;
  background: #12141a;
  color: var(--fg);
  font-size: 15px;
}

button {
  margin-top: 20px;
  background: var(--accent);
  border: 0;
  font-weight: 600;
  cursor: pointer;
}

button:disabled {
  opacity: 0.5;
  cursor: default;
}

.error {
  margin-top: 14px;
  color: var(--danger);
  font-size: 13px;
  min-height: 20px;
}

.banner {
  padding: 12px 16px;
  margin-bottom: 16px;
  border-radius: 8px;
  background: var(--danger);
  color: #fff;
  font-size: 14px;
}

.hidden {
  display: none;
}

#stage {
  display: flex;
  gap: 24px;
  align-items: flex-start;
  flex-wrap: wrap;
}

canvas {
  background: #000; /* 원본 영상은 절대 표시하지 않는다 */
  border-radius: 12px;
}

#status {
  min-width: 220px;
}

#state {
  font-size: 28px;
  font-weight: 700;
  letter-spacing: 0.02em;
}

.metric {
  color: var(--muted);
  font-size: 13px;
  font-variant-numeric: tabular-nums;
}

.privacy {
  margin-top: 20px;
  padding: 12px 14px;
  border: 1px solid #2b3040;
  border-radius: 8px;
  color: var(--muted);
  font-size: 12px;
}
```

- [ ] **Step 3: 로그인 페이지 작성**

`web/index.html`

```html
<!doctype html>
<!-- 보호자 계정으로 로그인해 토큰을 받는 화면 -->
<html lang="ko">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>낙상 감지 — 로그인</title>
    <link rel="stylesheet" href="css/style.css" />
  </head>
  <body>
    <div class="card">
      <h1>낙상 감지 시스템</h1>
      <form id="form">
        <label for="username">아이디</label>
        <input id="username" name="username" autocomplete="username" required />
        <label for="password">비밀번호</label>
        <input id="password" name="password" type="password" autocomplete="current-password" required />
        <button type="submit">로그인</button>
      </form>
      <p class="error" id="error"></p>
      <p class="privacy">
        이 페이지는 웹캠 영상을 브라우저 안에서만 처리합니다. 영상과 관절 좌표는 서버로 전송되지
        않습니다.
      </p>
    </div>

    <script type="module">
      import { login, setToken } from "./js/api.js";

      const form = document.getElementById("form");
      const error = document.getElementById("error");

      form.addEventListener("submit", async (e) => {
        e.preventDefault();
        error.textContent = "";
        const button = form.querySelector("button");
        button.disabled = true;
        try {
          setToken(await login(form.username.value, form.password.value));
          location.href = "detect.html";
        } catch (err) {
          error.textContent = err.message;
          button.disabled = false;
        }
      });
    </script>
  </body>
</html>
```

- [ ] **Step 4: 브라우저에서 로그인 확인**

터미널 1에서 Django를 띄운다.

```bash
cd backend && .venv/bin/python manage.py runserver 8000
```

터미널 2에서 정적 서버를 띄운다 (VS Code Live Server를 써도 되지만 포트가 5500이어야 CORS가 통과한다).

```bash
cd web && npx --yes serve -l 5500 .
```

브라우저에서 `http://127.0.0.1:5500` → `guardian` / `pw12345`로 로그인.

Expected: `detect.html`로 이동한다 (아직 404이거나 빈 화면이어도 정상). DevTools 콘솔에 CORS 에러가 없어야 하고, Application → Local Storage에 `fall_token`이 보인다. 틀린 비밀번호로는 빨간 에러 문구가 뜬다.

- [ ] **Step 5: 커밋**

```bash
git add web/
git commit -m "감지 클라이언트 로그인 화면과 API 래퍼 추가"
```

---

## Task 8: pose.js — MediaPipe 초기화 + 웹캠 루프

**Files:**
- Create: `web/js/pose.js`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `createPoseLandmarker()` → `Promise<PoseLandmarker>`. 실패 시 `throw`
  - `startCamera(video)` → `Promise<MediaStream>`. 권한 거부 시 `throw`
  - `runLoop(landmarker, video, onFrame)` → `stop()` 함수. `onFrame(landmarks, t)`에서 `landmarks`는 33개 배열 또는 빈 배열, `t`는 `performance.now()` 기준 ms

- [ ] **Step 1: pose.js 작성**

CDN 버전 `0.10.35`는 세 URL 모두 실측 확인했다. `@latest`로 바꾸면 브레이킹 체인지에 시연이 깨질 수 있다.

`web/js/pose.js`

```js
// MediaPipe PoseLandmarker 초기화와 웹캠 프레임 루프

import {
  FilesetResolver,
  PoseLandmarker,
} from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/vision_bundle.mjs";

const WASM_BASE = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/wasm";
const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";

export async function createPoseLandmarker() {
  const fileset = await FilesetResolver.forVisionTasks(WASM_BASE);
  return PoseLandmarker.createFromOptions(fileset, {
    baseOptions: { modelAssetPath: MODEL_URL, delegate: "GPU" },
    runningMode: "VIDEO",
    numPoses: 1, // 독거 전제
  });
}

export async function startCamera(video) {
  const stream = await navigator.mediaDevices.getUserMedia({
    video: { width: 640, height: 480 },
    audio: false,
  });
  video.srcObject = stream;
  await video.play();
  return stream;
}

export function runLoop(landmarker, video, onFrame) {
  let stopped = false;
  let lastVideoTime = -1;

  const tick = () => {
    if (stopped) return;
    // 같은 프레임을 두 번 넣으면 MediaPipe가 타임스탬프 역행으로 던진다
    if (video.currentTime !== lastVideoTime) {
      lastVideoTime = video.currentTime;
      const t = performance.now();
      const result = landmarker.detectForVideo(video, t);
      onFrame(result.landmarks?.[0] ?? [], t);
    }
    requestAnimationFrame(tick);
  };

  requestAnimationFrame(tick);
  return () => {
    stopped = true;
  };
}
```

- [ ] **Step 2: 커밋**

이 파일은 Task 10에서 조립되어야 눈으로 확인할 수 있다. 단독 실행 확인은 Task 10의 Step 5에서 한다.

```bash
git add web/js/pose.js
git commit -m "MediaPipe 초기화와 웹캠 루프 추가"
```

---

## Task 9: overlay.js — 검은 배경 + 스켈레톤

**Files:**
- Create: `web/js/overlay.js`

**Interfaces:**
- Consumes: 없음
- Produces: `drawSkeleton(ctx, landmarks, state)` — 캔버스를 검게 칠하고 스켈레톤만 그린다. `landmarks`가 비면 배경만 칠한다.

- [ ] **Step 1: overlay.js 작성**

`web/js/overlay.js`

```js
// 검은 배경 위에 스켈레톤만 그린다 (원본 영상은 절대 그리지 않는다)

const CONNECTIONS = [
  [11, 12], // 어깨
  [11, 23],
  [12, 24], // 몸통
  [23, 24], // 골반
  [11, 13],
  [13, 15], // 왼팔
  [12, 14],
  [14, 16], // 오른팔
  [23, 25],
  [25, 27], // 왼다리
  [24, 26],
  [26, 28], // 오른다리
];

const STATE_COLOR = {
  NO_PERSON: "#8b93a7",
  STANDING: "#4c8dff",
  FALLING: "#f5a524",
  FALLEN: "#f5a524",
  ALERTED: "#e5484d",
};

export function drawSkeleton(ctx, landmarks, state) {
  const { width, height } = ctx.canvas;

  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, width, height);

  if (!landmarks || landmarks.length === 0) return;

  const color = STATE_COLOR[state] ?? "#8b93a7";
  const px = (lm) => [lm.x * width, lm.y * height];

  ctx.strokeStyle = color;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  for (const [a, b] of CONNECTIONS) {
    if (!landmarks[a] || !landmarks[b]) continue;
    ctx.beginPath();
    ctx.moveTo(...px(landmarks[a]));
    ctx.lineTo(...px(landmarks[b]));
    ctx.stroke();
  }

  ctx.fillStyle = color;
  for (const lm of landmarks) {
    if (!lm) continue;
    const [x, y] = px(lm);
    ctx.beginPath();
    ctx.arc(x, y, 4, 0, Math.PI * 2);
    ctx.fill();
  }
}
```

- [ ] **Step 2: 커밋**

```bash
git add web/js/overlay.js
git commit -m "스켈레톤 렌더링 추가"
```

---

## Task 10: detect.html 조립 + 상태 표시

이 태스크 끝에 처음으로 웹캠 앞에서 넘어져보며 상태 전이를 눈으로 볼 수 있다.

**Files:**
- Create: `web/detect.html`, `web/js/main.js`

**Interfaces:**
- Consumes: `createDetector`(T5), `requireToken`(T7), `createPoseLandmarker`/`startCamera`/`runLoop`(T8), `drawSkeleton`(T9)
- Produces: 방 선택 후 감지가 도는 화면. 낙상 확정 시 `console.log`만 한다 — POST는 Task 11에서 붙인다.

- [ ] **Step 1: detect.html 작성**

`<video>`는 MediaPipe에 프레임을 넣기 위해 필요하지만 `hidden`으로 숨긴다. 화면에 보이는 것은 캔버스뿐이다.

`web/detect.html`

```html
<!doctype html>
<!-- 방을 선택하고 웹캠으로 낙상을 감지하는 화면 -->
<html lang="ko">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>낙상 감지 — 감지 중</title>
    <link rel="stylesheet" href="css/style.css" />
  </head>
  <body>
    <div id="banner" class="banner hidden"></div>

    <div id="setup" class="card">
      <h1>감지할 방 선택</h1>
      <label for="roomName">방 이름</label>
      <select id="roomName">
        <option>안방</option>
        <option>부엌</option>
        <option>거실</option>
        <option>화장실</option>
      </select>
      <label for="roomNumber">방 번호</label>
      <input id="roomNumber" type="number" value="1" min="1" max="99" />
      <button id="start">감지 시작</button>
      <p class="error" id="error"></p>
    </div>

    <div id="stage" class="hidden">
      <!-- MediaPipe 입력용. 화면에는 절대 표시하지 않는다. -->
      <video id="video" playsinline hidden></video>
      <canvas id="canvas" width="640" height="480"></canvas>
      <div id="status">
        <h1 id="room"></h1>
        <div id="state">—</div>
        <p class="metric" id="metrics"></p>
        <p class="metric" id="sent">전송된 낙상 0건</p>
        <div class="privacy">
          검은 배경 위 스켈레톤이 전부입니다. 영상과 관절 좌표는 이 브라우저를 벗어나지 않습니다.
        </div>
      </div>
    </div>

    <script type="module" src="js/main.js"></script>
  </body>
</html>
```

- [ ] **Step 2: main.js 작성 (POST 없이)**

`web/js/main.js`

```js
// 감지 페이지 조립 — 방 선택 → 웹캠 → MediaPipe → 상태머신 → 화면

import { requireToken } from "./api.js";
import { createDetector } from "./detector.js";
import { drawSkeleton } from "./overlay.js";
import { createPoseLandmarker, runLoop, startCamera } from "./pose.js";

requireToken();

const el = {
  setup: document.getElementById("setup"),
  stage: document.getElementById("stage"),
  start: document.getElementById("start"),
  error: document.getElementById("error"),
  banner: document.getElementById("banner"),
  roomName: document.getElementById("roomName"),
  roomNumber: document.getElementById("roomNumber"),
  room: document.getElementById("room"),
  state: document.getElementById("state"),
  metrics: document.getElementById("metrics"),
  sent: document.getElementById("sent"),
  video: document.getElementById("video"),
  canvas: document.getElementById("canvas"),
};

const ctx = el.canvas.getContext("2d");
const detector = createDetector();
let sentCount = 0;

el.start.addEventListener("click", async () => {
  el.error.textContent = "";
  el.start.disabled = true;

  let landmarker;
  try {
    landmarker = await createPoseLandmarker();
  } catch (err) {
    el.error.textContent = `모델을 불러오지 못했습니다. 네트워크를 확인하고 새로고침하세요. (${err.message})`;
    el.start.disabled = false;
    return;
  }

  try {
    await startCamera(el.video);
  } catch (err) {
    el.error.textContent = `웹캠을 사용할 수 없습니다. 브라우저 주소창의 카메라 권한을 허용한 뒤 다시 시도하세요. (${err.name})`;
    el.start.disabled = false;
    return;
  }

  const room = { name: el.roomName.value, number: Number(el.roomNumber.value) };
  el.room.textContent = `${room.name} ${room.number}`;
  el.setup.classList.add("hidden");
  el.stage.classList.remove("hidden");

  runLoop(landmarker, el.video, (landmarks, t) => {
    const { state, fall, tilt, hipVelocity } = detector.update(landmarks, t);

    drawSkeleton(ctx, landmarks, state);
    el.state.textContent = state;
    el.metrics.textContent = `tilt ${(tilt ?? 0).toFixed(1)}°  ·  hipV ${hipVelocity.toFixed(2)}/s`;

    if (fall) {
      sentCount += 1;
      el.sent.textContent = `전송된 낙상 ${sentCount}건`;
      console.log("낙상 확정", { room, fall });
    }
  });
});
```

- [ ] **Step 3: 서버 두 개 실행**

```bash
# 터미널 1
cd backend && .venv/bin/python manage.py runserver 8000
# 터미널 2
cd web && npx --yes serve -l 5500 .
```

- [ ] **Step 4: 브라우저에서 상태 전이 관찰**

`http://127.0.0.1:5500` → 로그인 → 방 선택 → 감지 시작 → 카메라 권한 허용.

Expected:
- 캔버스에 **검은 배경과 스켈레톤만** 보인다. 원본 영상이 보이면 버그다.
- 카메라 앞에 서면 `STANDING`(파랑), 프레임을 벗어나 2초 지나면 `NO_PERSON`(회색).
- `tilt`가 서 있을 때 0~15° 근처, 누우면 70~90° 근처.
- 천천히 눕는다 → `FALLING`으로 가지 않는다.
- 빠르게 눕고 5초 버틴다 → `FALLING` → `FALLEN` → `ALERTED`(빨강), 콘솔에 `낙상 확정` 로그, "전송된 낙상 1건".

전이가 전혀 안 일어나면 임계값 문제일 수 있다. 여기서 튜닝하지 말고 Task 16에서 한다. 다만 `tilt`/`hipV` 실측값은 메모해둔다.

- [ ] **Step 5: 권한 거부 처리 확인**

브라우저 주소창의 카메라 권한을 "차단"으로 바꾸고 새로고침 → 감지 시작.

Expected: "웹캠을 사용할 수 없습니다..." 문구가 뜨고 버튼이 다시 활성화된다.

- [ ] **Step 6: 커밋**

```bash
git add web/
git commit -m "감지 화면 조립과 상태 표시 추가"
```

---

## Task 11: 낙상 POST + 재시도 + 배너 + 401 처리

**Files:**
- Modify: `web/js/api.js`, `web/js/main.js`

**Interfaces:**
- Consumes: Task 3의 `POST /api/falls/`
- Produces: `postFall({ room_name, room_number, occurred_at, confidence })` → `Promise<FallEvent>`. 지수 백오프로 최대 3회 시도. 401이면 재시도 없이 `logoutAndRedirect()`.

- [ ] **Step 1: api.js에 postFall 추가**

`web/js/api.js` 끝에 덧붙인다.

```js
class UnauthorizedError extends Error {}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function postFallOnce(payload) {
  const res = await fetch(`${API_BASE}/api/falls/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Token ${getToken()}`,
    },
    body: JSON.stringify(payload),
  });
  if (res.status === 401) throw new UnauthorizedError();
  if (!res.ok) throw new Error(`서버가 ${res.status}를 반환했습니다.`);
  return res.json();
}

// 최대 3회 지수 백오프(0.5s → 1s → 2s). 3회 실패하면 이 낙상은 유실된다.
// 실제 제품이라면 localStorage 큐가 필요하지만 과제 범위에서는 배너로 알리고 포기한다.
export async function postFall(payload, attempts = 3) {
  for (let i = 0; i < attempts; i += 1) {
    try {
      return await postFallOnce(payload);
    } catch (err) {
      if (err instanceof UnauthorizedError) {
        logoutAndRedirect(); // 토큰이 죽었으면 재시도는 무의미하다
        throw err;
      }
      if (i === attempts - 1) throw err;
      await sleep(500 * 2 ** i);
    }
  }
}
```

- [ ] **Step 2: main.js에서 POST 호출**

`web/js/main.js`의 import 줄을 바꾼다.

```js
import { postFall, requireToken } from "./api.js";
```

`const ctx = ...` 위 아무 곳에 배너 함수를 추가한다. Task 10에서 만든 `#banner`를 처음 쓰는 곳이다.

```js
function showBanner(message) {
  el.banner.textContent = message;
  el.banner.classList.remove("hidden");
}
```

그리고 `runLoop` 콜백 안의 `if (fall) { ... }` 블록 전체를 아래로 교체한다.

`detector`의 타임스탬프는 `performance.now()` 기준(페이지 로드 후 경과 ms)이다. 그대로 보내면 1970년이 찍히므로 `performance.timeOrigin`을 더해 벽시계 시각으로 바꾼다.

```js
    if (fall) {
      const payload = {
        room_name: room.name,
        room_number: room.number,
        occurred_at: new Date(performance.timeOrigin + fall.occurredAt).toISOString(),
        confidence: fall.confidence,
      };
      postFall(payload)
        .then(() => {
          sentCount += 1;
          el.sent.textContent = `전송된 낙상 ${sentCount}건`;
        })
        .catch((err) => showBanner(`낙상 전송에 실패했습니다. ${err.message}`));
    }
```

- [ ] **Step 3: 실제로 넘어져 DB에 행이 생기는지 확인**

서버 두 개를 띄우고 감지를 시작한 뒤, 빠르게 눕고 5초 버틴다.

```bash
cd backend && .venv/bin/python manage.py shell -c "
from falls.models import FallEvent
for e in FallEvent.objects.all()[:5]:
    print(e.id, e.room_name, e.room_number, e.occurred_at, round(e.confidence, 3))
"
```

Expected: 방금 넘어진 이벤트 1행. `occurred_at`이 **오늘 날짜의 현재 시각 근처**여야 한다. 1970년이면 `performance.timeOrigin` 변환이 빠진 것이다. 화면의 "전송된 낙상"이 1건으로 는다.

- [ ] **Step 4: 전송 실패 배너 확인**

Django를 끈 상태(`Ctrl+C`)에서 다시 넘어진다.

Expected: 약 3.5초(0.5+1+2) 뒤 화면 상단에 빨간 배너가 뜬다.

- [ ] **Step 5: 401 처리 확인**

DevTools 콘솔에서 토큰을 망가뜨린 뒤 넘어진다.

```js
localStorage.setItem("fall_token", "broken");
```

Expected: 재시도 없이 즉시 `index.html`로 튕기고 `fall_token`이 사라진다.

- [ ] **Step 6: 커밋**

```bash
git add web/
git commit -m "낙상 전송과 재시도·배너·401 처리 추가"
```

---

## Task 12: Flutter 골격 + 모델 + API 클라이언트

**Files:**
- Create: `app/` (생성됨), `app/lib/models.dart`, `app/lib/api.dart`
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Consumes: Task 2~4의 API 계약
- Produces:
  - `FallEvent` — `{int id, String roomName, int roomNumber, DateTime occurredAt, DateTime createdAt, double confidence, DateTime? acknowledgedAt}`, `FallEvent.fromJson(Map)`, `bool get isAcknowledged`
  - `Api` — `Future<String> login(String, String)`, `Future<List<FallEvent>> listFalls()`, `Future<FallEvent> acknowledge(int id)`, `Future<void> saveToken(String)`, `Future<String?> loadToken()`, `Future<void> clearToken()`
  - `Api.baseUrl` — Android면 `http://10.0.2.2:8000`, 그 외 `http://127.0.0.1:8000`
  - `UnauthorizedException`

- [ ] **Step 1: 프로젝트 생성**

```bash
cd /Users/munhokang/82107/weniv_project
flutter create --project-name fall_guardian --platforms=ios,android app
```

- [ ] **Step 2: 의존성 추가**

```bash
cd app
flutter pub add http flutter_local_notifications shared_preferences url_launcher
flutter pub get
```

Expected: `pubspec.yaml`의 `dependencies:`에 4개가 추가된다.

- [ ] **Step 3: 모델 작성**

`app/lib/models.dart`

```dart
// 서버가 내려주는 낙상 이벤트 1건

class FallEvent {
  final int id;
  final String roomName;
  final int roomNumber;
  final DateTime occurredAt;
  final DateTime createdAt;
  final double confidence;
  final DateTime? acknowledgedAt;

  const FallEvent({
    required this.id,
    required this.roomName,
    required this.roomNumber,
    required this.occurredAt,
    required this.createdAt,
    required this.confidence,
    this.acknowledgedAt,
  });

  factory FallEvent.fromJson(Map<String, dynamic> json) => FallEvent(
        id: json['id'] as int,
        roomName: json['room_name'] as String,
        roomNumber: json['room_number'] as int,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        confidence: (json['confidence'] as num).toDouble(),
        acknowledgedAt: json['acknowledged_at'] == null
            ? null
            : DateTime.parse(json['acknowledged_at'] as String).toLocal(),
      );

  bool get isAcknowledged => acknowledgedAt != null;

  String get roomLabel => '$roomName $roomNumber';
}
```

- [ ] **Step 4: API 클라이언트 작성**

`app/lib/api.dart`

```dart
// Django API 호출과 토큰 보관

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class UnauthorizedException implements Exception {}

class Api {
  static const _tokenKey = 'fall_token';

  // Android 에뮬레이터는 호스트를 10.0.2.2로 본다. iOS 시뮬레이터와 데스크톱은
  // 호스트 네트워크를 그대로 공유하므로 127.0.0.1이다.
  static String get baseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';

  String? _token;

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    return _token;
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Token $_token',
      };

  Future<String> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw Exception('아이디 또는 비밀번호가 올바르지 않습니다.');
    }
    final token = jsonDecode(utf8.decode(res.bodyBytes))['token'] as String;
    await saveToken(token);
    return token;
  }

  Future<List<FallEvent>> listFalls() async {
    final res = await http.get(Uri.parse('$baseUrl/api/falls/'), headers: _headers);
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('목록을 불러오지 못했습니다 (${res.statusCode}).');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => FallEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FallEvent> acknowledge(int id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/falls/$id/acknowledge/'),
      headers: _headers,
    );
    if (res.statusCode == 401) throw UnauthorizedException();
    if (res.statusCode != 200) throw Exception('확인 처리에 실패했습니다 (${res.statusCode}).');
    return FallEvent.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
```

- [ ] **Step 5: 분석 통과 확인**

```bash
cd app && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add app/
git commit -m "Flutter 골격과 모델·API 클라이언트 추가"
```

---

## Task 13: 로그인 + 목록 + 상세 화면

**Files:**
- Create: `app/lib/screens/login.dart`, `app/lib/screens/fall_list.dart`, `app/lib/screens/fall_detail.dart`
- Modify: `app/lib/main.dart` (전체 교체)

**Interfaces:**
- Consumes: `Api`, `FallEvent`(T12)
- Produces: `LoginScreen(api:)`, `FallListScreen(api:)`, `FallDetailScreen(api:, event:)`. 상세 화면은 변경된 `FallEvent`를 `Navigator.pop`으로 돌려준다.

- [ ] **Step 1: main.dart 교체**

`app/lib/main.dart`

```dart
// 앱 진입점 — 저장된 토큰 유무로 첫 화면을 정한다

import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/fall_list.dart';
import 'screens/login.dart';

void main() {
  runApp(const FallGuardianApp());
}

class FallGuardianApp extends StatefulWidget {
  const FallGuardianApp({super.key});

  @override
  State<FallGuardianApp> createState() => _FallGuardianAppState();
}

class _FallGuardianAppState extends State<FallGuardianApp> {
  final _api = Api();
  bool _loading = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _api.loadToken().then((token) {
      setState(() {
        _loggedIn = token != null;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '낙상 알림',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4C8DFF), useMaterial3: true),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _loggedIn
              ? FallListScreen(api: _api)
              : LoginScreen(api: _api),
    );
  }
}
```

- [ ] **Step 2: 로그인 화면 작성**

`app/lib/screens/login.dart`

```dart
// 보호자 로그인 화면

import 'package:flutter/material.dart';

import '../api.dart';
import 'fall_list.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});

  final Api api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.login(_username.text, _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => FallListScreen(api: widget.api)),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('낙상 알림', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: '아이디', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('로그인'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 목록 화면 작성 (폴링 없이)**

폴링과 알림은 Task 14·15에서 붙인다.

`app/lib/screens/fall_list.dart`

```dart
// 낙상 이벤트 목록 화면

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'fall_detail.dart';
import 'login.dart';

class FallListScreen extends StatefulWidget {
  const FallListScreen({super.key, required this.api});

  final Api api;

  @override
  State<FallListScreen> createState() => _FallListScreenState();
}

class _FallListScreenState extends State<FallListScreen> {
  List<FallEvent> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final events = await widget.api.listFalls();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
        _error = null;
      });
    } on UnauthorizedException {
      await _logout();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _logout() async {
    await widget.api.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
    );
  }

  String _fmt(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('낙상 알림'),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: Column(
                children: [
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.errorContainer,
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  Expanded(
                    child: _events.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('아직 감지된 낙상이 없습니다.')),
                            ],
                          )
                        : ListView.separated(
                            itemCount: _events.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final e = _events[i];
                              return ListTile(
                                leading: Icon(
                                  e.isAcknowledged ? Icons.check_circle : Icons.warning_amber,
                                  color: e.isAcknowledged
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.error,
                                ),
                                title: Text(e.roomLabel),
                                subtitle: Text(_fmt(e.occurredAt)),
                                trailing: Text(e.isAcknowledged ? '확인함' : '미확인'),
                                onTap: () async {
                                  final updated = await Navigator.of(context).push<FallEvent>(
                                    MaterialPageRoute(
                                      builder: (_) => FallDetailScreen(api: widget.api, event: e),
                                    ),
                                  );
                                  if (updated != null) {
                                    setState(() => _events[i] = updated);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
```

- [ ] **Step 4: 상세 화면 작성 (확인 버튼만)**

전화·신고는 Task 15에서 붙인다.

`app/lib/screens/fall_detail.dart`

```dart
// 낙상 이벤트 상세 화면

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

class FallDetailScreen extends StatefulWidget {
  const FallDetailScreen({super.key, required this.api, required this.event});

  final Api api;
  final FallEvent event;

  @override
  State<FallDetailScreen> createState() => _FallDetailScreenState();
}

class _FallDetailScreenState extends State<FallDetailScreen> {
  late FallEvent _event = widget.event;
  bool _busy = false;

  Future<void> _acknowledge() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.api.acknowledge(_event.id);
      if (!mounted) return;
      setState(() {
        _event = updated;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  String _fmt(DateTime t) =>
      '${t.year}년 ${t.month}월 ${t.day}일 '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_event.roomLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('발생 시각', _fmt(_event.occurredAt)),
          _row('감지 신뢰도', '${(_event.confidence * 100).toStringAsFixed(0)}%'),
          _row('상태', _event.isAcknowledged ? '확인함 (${_fmt(_event.acknowledgedAt!)})' : '미확인'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy || _event.isAcknowledged ? null : _acknowledge,
            icon: const Icon(Icons.check),
            label: Text(_event.isAcknowledged ? '확인함' : '확인함으로 표시'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
          ],
        ),
      );
}
```

- [ ] **Step 5: 앱에서 DB의 이벤트가 보이는지 확인**

Django를 띄우고 iOS 시뮬레이터로 실행한다. Android 에뮬레이터가 있으면 그쪽도 된다.

```bash
cd backend && .venv/bin/python manage.py runserver 8000   # 터미널 1
cd app && flutter run -d "iPhone 17 Pro"                   # 터미널 2
```

Expected: 로그인 후 Task 11에서 만들어진 이벤트가 목록에 뜬다. 항목을 누르면 상세로 가고, "확인함으로 표시"를 누르면 버튼이 비활성화되며 상태가 "확인함"으로 바뀐다. 뒤로 가면 목록의 아이콘도 초록 체크로 바뀐다.

`flutter analyze`도 통과해야 한다.

```bash
cd app && flutter analyze
```

- [ ] **Step 6: 커밋**

```bash
git add app/
git commit -m "Flutter 로그인·목록·상세 화면 추가"
```

---

## Task 14: poller.dart + 새 id 판별 단위 테스트

**Files:**
- Create: `app/lib/poller.dart`, `app/test/poller_test.dart`
- Delete: `app/test/widget_test.dart` (기본 생성물, 우리 앱과 무관하고 컴파일이 깨진다)

**Interfaces:**
- Consumes: `FallEvent`(T12)
- Produces:
  - `NewEventTracker` — `List<FallEvent> newEvents(List<FallEvent> events)`. 순수 클래스, 네트워크·타이머 없음
  - `int? get lastSeenId`

- [ ] **Step 1: 실패하는 테스트 작성**

폴링에서 유일하게 틀리기 쉬운 것은 "무엇이 새 이벤트인가"다. 타이머와 http는 테스트하지 않고 이 판별 로직만 순수 클래스로 떼어내 테스트한다.

`app/test/poller_test.dart`

```dart
// 새 이벤트 판별 로직 단위 테스트

import 'package:fall_guardian/models.dart';
import 'package:fall_guardian/poller.dart';
import 'package:flutter_test/flutter_test.dart';

FallEvent ev(int id) => FallEvent(
      id: id,
      roomName: '안방',
      roomNumber: 1,
      occurredAt: DateTime(2026, 7, 17, 12),
      createdAt: DateTime(2026, 7, 17, 12),
      confidence: 0.9,
    );

void main() {
  test('최초 응답은 알림 없이 id만 저장한다', () {
    final tracker = NewEventTracker();

    // 로그인 직후 기존 이벤트 전부에 알림이 쏟아지면 안 된다
    expect(tracker.newEvents([ev(3), ev(2), ev(1)]), isEmpty);
    expect(tracker.lastSeenId, 3);
  });

  test('같은 응답이 반복되면 새 이벤트가 없다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    expect(tracker.newEvents([ev(3), ev(2), ev(1)]), isEmpty);
  });

  test('새 이벤트 2건이 오면 2건만 돌려준다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([ev(3), ev(2), ev(1)]);

    final fresh = tracker.newEvents([ev(5), ev(4), ev(3), ev(2), ev(1)]);

    expect(fresh.map((e) => e.id), [5, 4]);
    expect(tracker.lastSeenId, 5);
  });

  test('최초 응답이 비어 있으면 그 다음 첫 이벤트는 새 이벤트다', () {
    final tracker = NewEventTracker();
    tracker.newEvents([]);

    expect(tracker.newEvents([ev(1)]).map((e) => e.id), [1]);
  });
}
```

- [ ] **Step 2: 기본 위젯 테스트 삭제 후 테스트 실패 확인**

```bash
cd app
rm -f test/widget_test.dart
flutter test
```

Expected: FAIL — `Error: Couldn't resolve the package 'fall_guardian'` 또는 `poller.dart` 없음 오류.

- [ ] **Step 3: poller.dart 구현**

`app/lib/poller.dart`

```dart
// 폴링 응답에서 새 이벤트를 골라내는 로직과 5초 타이머

import 'dart:async';

import 'models.dart';

class NewEventTracker {
  int? _lastSeenId;

  int? get lastSeenId => _lastSeenId;

  /// [events]는 서버가 준 최신순 목록이다. 마지막으로 본 id보다 큰 것만 새 이벤트다.
  /// 최초 호출(=로그인 직후)에는 기존 이벤트 알림 폭탄을 막기 위해 id만 저장하고 빈 목록을 준다.
  List<FallEvent> newEvents(List<FallEvent> events) {
    if (events.isEmpty) return const [];

    final maxId = events.map((e) => e.id).reduce((a, b) => a > b ? a : b);

    if (_lastSeenId == null) {
      _lastSeenId = maxId;
      return const [];
    }

    final fresh = events.where((e) => e.id > _lastSeenId!).toList();
    _lastSeenId = maxId;
    return fresh;
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test
```

Expected: `All tests passed!` (4개)

- [ ] **Step 5: 커밋**

```bash
git add app/
git commit -m "새 이벤트 판별 로직과 단위 테스트 추가"
```

---

## Task 15: 폴링 + 로컬 알림 + 전화·신고

**Files:**
- Create: `app/lib/notifications.dart`
- Modify: `app/lib/poller.dart`, `app/lib/main.dart`, `app/lib/screens/fall_list.dart`, `app/lib/screens/fall_detail.dart`
- Modify: `app/ios/Runner/Info.plist`

**Interfaces:**
- Consumes: `NewEventTracker`(T14), `Api`(T12)
- Produces:
  - `Notifications.init()`, `Notifications.show(FallEvent)`
  - `FallPoller({api, onEvents, onConnectionLost, onRecovered})` — `start()` / `stop()`. 5초 주기, 3회 연속 실패 시 `onConnectionLost`

- [ ] **Step 1: 알림 래퍼 작성**

`app/lib/notifications.dart`

```dart
// flutter_local_notifications 래퍼

import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'falls',
      '낙상 알림',
      channelDescription: '낙상이 감지되면 즉시 알립니다',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> show(FallEvent event) async {
    final t = event.occurredAt;
    await _plugin.show(
      event.id,
      '${event.roomLabel}에서 낙상 감지',
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} 발생 · 확인이 필요합니다',
      _details,
    );
  }
}
```

- [ ] **Step 2: poller.dart에 타이머 추가**

`app/lib/poller.dart`의 import를 늘리고 파일 끝에 `FallPoller`를 덧붙인다. `NewEventTracker`는 그대로 둔다.

```dart
// 폴링 응답에서 새 이벤트를 골라내는 로직과 5초 타이머

import 'dart:async';

import 'api.dart';
import 'models.dart';
```

```dart
class FallPoller {
  FallPoller({
    required this.api,
    required this.onEvents,
    required this.onConnectionLost,
    required this.onRecovered,
    required this.onUnauthorized,
  });

  static const _interval = Duration(seconds: 5);
  static const _failuresBeforeBanner = 3;

  final Api api;
  final void Function(List<FallEvent> all, List<FallEvent> fresh) onEvents;
  final void Function() onConnectionLost;
  final void Function() onRecovered;
  final void Function() onUnauthorized;

  final _tracker = NewEventTracker();
  Timer? _timer;
  int _consecutiveFailures = 0;

  void start() {
    _tick();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final all = await api.listFalls();
      final fresh = _tracker.newEvents(all);
      if (_consecutiveFailures >= _failuresBeforeBanner) onRecovered();
      _consecutiveFailures = 0;
      onEvents(all, fresh);
    } on UnauthorizedException {
      stop();
      onUnauthorized();
    } catch (_) {
      // 조용히 다음 주기에 재시도한다. 3회 연속 실패해야 사용자에게 알린다.
      _consecutiveFailures += 1;
      if (_consecutiveFailures == _failuresBeforeBanner) onConnectionLost();
    }
  }
}
```

- [ ] **Step 3: main.dart에서 알림 초기화**

`app/lib/main.dart`의 `main()`을 아래로 바꾸고 import를 추가한다.

```dart
import 'notifications.dart';
```

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  runApp(const FallGuardianApp());
}
```

- [ ] **Step 4: 목록 화면에 폴링 연결**

`app/lib/screens/fall_list.dart`의 import에 두 줄을 더한다.

```dart
import '../notifications.dart';
import '../poller.dart';
```

`_FallListScreenState`의 클래스 선언부터 `_refresh` 끝까지(필드 + `initState` + `_refresh`)를 아래로 교체한다. `dispose`는 Task 13에 없었으므로 새로 생기는 것이다. 나머지(`_logout`, `_fmt`, `build`)는 그대로 둔다.

```dart
class _FallListScreenState extends State<FallListScreen> {
  List<FallEvent> _events = [];
  bool _loading = true;
  String? _error;
  late final FallPoller _poller;

  @override
  void initState() {
    super.initState();
    _poller = FallPoller(
      api: widget.api,
      onEvents: (all, fresh) {
        for (final e in fresh) {
          Notifications.show(e);
        }
        if (!mounted) return;
        setState(() {
          _events = all;
          _loading = false;
          _error = null;
        });
      },
      onConnectionLost: () {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '연결 끊김 — 서버에 닿지 않습니다.';
        });
      },
      onRecovered: () {
        if (!mounted) return;
        setState(() => _error = null);
      },
      onUnauthorized: _logout,
    );
    _poller.start();
  }

  @override
  void dispose() {
    _poller.stop();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final events = await widget.api.listFalls();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
        _error = null;
      });
    } on UnauthorizedException {
      await _logout();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
```

- [ ] **Step 5: 상세 화면에 전화·신고 추가**

`app/lib/screens/fall_detail.dart`의 import에 한 줄을 더한다.

```dart
import 'package:url_launcher/url_launcher.dart';
```

`_FallDetailScreenState` 안에 상수와 메서드를 덧붙인다.

```dart
  // 연락처 관리 화면은 범위 밖이므로 상수로 둔다.
  static const _elderPhone = '01012345678';

  // 시연 중 실수로 119에 실제 신고가 나가면 안 되므로 더미 번호다.
  // 실제 제품에서는 '119'로 바꾼다.
  static const _emergencyPhone = '01000000119';

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    // 다이얼러에 번호를 띄우는 데까지만 한다. 실제 발신은 사용자가 누른다.
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화 앱을 열 수 없습니다.')),
      );
    }
  }
```

`build`의 `ListView` `children` 끝(확인 버튼 아래)에 덧붙인다.

```dart
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _dial(_elderPhone),
            icon: const Icon(Icons.phone),
            label: const Text('어르신께 전화'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _dial(_emergencyPhone),
            icon: const Icon(Icons.local_hospital),
            label: const Text('119 신고 (시연용 더미 번호)'),
          ),
```

- [ ] **Step 6: iOS에서 tel: 스킴 허용**

`app/ios/Runner/Info.plist`의 최상위 `<dict>` 안에 덧붙인다.

```xml
	<key>LSApplicationQueriesSchemes</key>
	<array>
		<string>tel</string>
	</array>
```

- [ ] **Step 7: 분석·테스트 통과 확인**

```bash
cd app && flutter analyze && flutter test
```

Expected: `No issues found!` 그리고 `All tests passed!`

- [ ] **Step 8: 넘어지면 5초 내 알림이 뜨는지 확인**

터미널 3개를 띄운다.

```bash
cd backend && .venv/bin/python manage.py runserver 8000   # 터미널 1
cd web && npx --yes serve -l 5500 .                        # 터미널 2
cd app && flutter run -d "iPhone 17 Pro"                   # 터미널 3
```

앱에 로그인해 목록 화면을 띄운 채(알림 권한 허용), 브라우저 감지 페이지에서 빠르게 눕고 5초 버틴다.

Expected:
- 로그인 직후에는 기존 이벤트가 있어도 **알림이 뜨지 않는다**. 뜨면 최초 id 저장 로직이 깨진 것이다.
- 낙상 확정 후 5초 안에 "안방 1에서 낙상 감지" 알림이 뜬다. 목록 맨 위에 새 항목이 생긴다.
- 상세에서 "어르신께 전화"를 누르면 다이얼러가 뜨고 **자동 발신되지 않는다**.

- [ ] **Step 9: 연결 끊김 배너 확인**

Django를 끈다(`Ctrl+C`).

Expected: 약 15초(5초 × 3회) 뒤 목록 상단에 "연결 끊김 — 서버에 닿지 않습니다." 배너가 뜬다. Django를 다시 띄우면 배너가 사라진다.

- [ ] **Step 10: 커밋**

```bash
git add app/
git commit -m "폴링·로컬 알림·전화·신고 추가"
```

---

## Task 16: 임계값 튜닝 + README

**Files:**
- Create: `README.md`
- Modify: `web/js/detector.js` (튜닝 결과에 따라 `CONFIG`만), `context-notes.md`, `checklist.md`

- [ ] **Step 1: 실측값 수집**

감지 페이지를 띄우고 화면의 `tilt` / `hipV` 표시를 보며 아래를 기록한다.

| 동작 | 관찰할 값 |
|---|---|
| 가만히 서 있기 | `tilt` 범위, `hipV` 노이즈 폭 |
| 침대에 천천히 눕기 | `hipV` 최대치 → 이보다 **커야** `FALL_VELOCITY`가 안전하다 |
| 의자에 급히 앉기 | `hipV` 최대치, `tilt` 최대치 |
| 빠르게 넘어지기 | `hipV` 최대치 → 이보다 **작아야** `FALL_VELOCITY`가 감지한다 |
| 바닥에 누워 있기 | `tilt` 범위 |

`FALL_VELOCITY`는 "천천히 눕기 최대치"와 "빠르게 넘어지기 최대치" 사이에 둔다. 두 구간이 겹치면 카메라 각도가 문제다 — 카메라를 방 모서리 높은 곳에 두고 몸 전체가 프레임에 들어오게 다시 잡는다.

- [ ] **Step 2: 임계값 조정 후 Vitest 재실행**

`web/js/detector.js`의 `CONFIG` 값만 바꾼다. 상태머신 구조는 건드리지 않는다.

```bash
cd web && npx vitest run
```

Expected: `7 passed`. 임계값을 바꿔 테스트가 깨지면 그 값은 시나리오 가정과 충돌하는 것이다. 헬퍼의 `STAND`/`FLOOR`/`SEATED` 자세값을 실측에 맞게 조정하고 다시 돌린다.

- [ ] **Step 3: 오탐지 없이 3회 연속 감지 성공 확인**

3회 연속 아래를 수행한다.

1. 빠르게 넘어져 5초 버틴다 → 알림이 뜬다
2. 일어나서 침대에 천천히 눕는다 → 알림이 뜨지 않는다
3. 의자에 급히 앉는다 → 알림이 뜨지 않는다

3회 모두 통과해야 완료다. 실패하면 Step 1로 돌아간다.

- [ ] **Step 4: 튜닝 결과를 context-notes.md에 기록**

`context-notes.md`의 "임계값 튜닝 기록" 표에 조정값과 이유를 채운다. 조정하지 않은 항목은 "유지"로 적고 왜 초기값이 맞았는지 한 줄 남긴다.

- [ ] **Step 5: README 작성**

`README.md`

````markdown
# 노인 낙상 감지 시스템

혼자 사는 노인의 낙상을 카메라로 감지해 보호자 앱에 알린다. **영상은 기기를 벗어나지 않는다.**

과제 제출용 프로젝트이며 실제 배포하지 않는다.

## 사생활 보호

이 프로젝트의 출발점은 "감시 카메라를 집 안에 두는 거부감"이다. 그래서 영상을 서버로 보내지 않는 것을 구조로 보장했다.

- MediaPipe Pose를 **브라우저에서** 실행한다. 웹캠 영상은 브라우저 안에서 관절 좌표가 된다.
- **관절 좌표조차 서버로 보내지 않는다.** 낙상이 확정된 순간에만 `{room_name, room_number, occurred_at, confidence}` 4개 필드가 1회 전송된다.
- 화면에도 원본 영상을 표시하지 않는다. 검은 배경 위 스켈레톤만 그린다. 디버그용 영상 토글도 없다.

## 구조

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

## 감지 알고리즘 — 세 관문

낙상 감지의 진짜 난제는 **"넘어짐"과 "그냥 누움"의 구분**이다. "몸통이 수평이면 낙상"이라는 단순 임계값은 침대에 눕는 것도 전부 잡는다.

```
STANDING ──속도──▶ FALLING ──자세──▶ FALLEN ──시간──▶ ALERTED ──▶ POST 1회
```

1. **속도** (`hipVelocity > 0.45/s`) — 천천히 눕거나 앉으면 하강 속도가 임계값에 못 미쳐 진입조차 안 한다. 오탐지 방어의 1차 관문이다.
2. **자세** (`tilt > 60°`) — 빠르게 내려갔어도 몸통이 서 있으면 급히 앉은 것이다. 1초 안에 수평이 돼야 넘어진 것으로 본다.
3. **시간** (`5초 미회복`) — 5초 안에 일어나면 아무것도 보내지 않는다. 스스로 일어난 사람 때문에 보호자를 깨우지 않는다.

`TILT_UPRIGHT`(45°)와 `TILT_FALLEN`(60°) 사이 15°는 **의도적인 히스테리시스 밴드**다. 하나로 합치면 경계에서 상태가 진동한다.

`occurred_at`은 확정 시각이 아니라 **FALLING 진입 시각**이다. 보호자에게 실제로 넘어진 순간이 표시되어야 한다.

## 실행 방법

터미널 3개가 필요하다.

### 1. Django (`:8000`)

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python manage.py migrate
.venv/bin/python manage.py createsuperuser   # 보호자 계정 (회원가입 화면은 범위 밖)
.venv/bin/python manage.py runserver 8000
```

### 2. 감지 페이지 (`:5500`)

```bash
cd web
npx serve -l 5500 .
```

`http://127.0.0.1:5500`에서 로그인 → 방 선택 → 감지 시작 → 카메라 권한 허용.

포트가 **5500이어야 한다.** Django의 `CORS_ALLOWED_ORIGINS`가 이 포트만 허용한다. `getUserMedia`는 보안 컨텍스트를 요구하지만 `localhost`는 예외라 HTTPS는 불필요하다.

### 3. Flutter 앱

```bash
cd app
flutter pub get
flutter run
```

서버 주소는 플랫폼에 따라 자동으로 갈린다 — Android 에뮬레이터는 `10.0.2.2:8000`, iOS 시뮬레이터는 `127.0.0.1:8000`.

## 테스트

```bash
cd backend && .venv/bin/python -m pytest    # 7개 — 인증·소유권·멱등성
cd web     && npm test                       # 7개 — 상태머신 시나리오
cd app     && flutter test                   # 4개 — 새 이벤트 판별
```

상태머신 테스트가 이 프로젝트 테스트의 핵심이다. 가짜 랜드마크 시퀀스로 "천천히 눕기 → 알림 없음", "3초 만에 일어남 → 알림 없음", "5초 유지 → 1건" 같은 시나리오를 웹캠 없이 검증한다.

## 알려진 한계

의도적으로 범위 밖에 둔 것들이다.

- **백그라운드 알림 불가** — 폴링 방식이라 앱이 백그라운드로 가면 멈춘다. 실제 제품이라면 FCM이 필요하다. Firebase 설정에서 깨질 지점이 많아 시연 안정성을 택했다.
- **프레임 밖 낙상** — 넘어지며 화면을 벗어나면 `NO_PERSON`이 되어 감지되지 않는다.
- **다중 인물** — `numPoses: 1`, 독거 전제다.
- **낙상 전송 유실** — POST 3회 재시도 후 포기하고 배너만 띄운다. 실제 제품이라면 localStorage 큐가 필요하다.
- **회원가입·방 등록·연락처 관리 화면 없음** — 계정은 `createsuperuser`, 방은 고정 선택지 4개, 연락처는 상수다.
- **119는 더미 번호** — 시연 중 실제 발신을 막기 위함이다. `fall_detail.dart`의 `_emergencyPhone` 참고.
- **실시간 방 상태 대시보드 없음** — 웹캠이 하나라 의미가 없다.

## 문서

- [설계](docs/superpowers/specs/2026-07-17-fall-detection-design.md)
- [구현 계획](docs/superpowers/plans/2026-07-17-fall-detection.md)
- [결정 기록](context-notes.md)
````

- [ ] **Step 6: 체크리스트 정리**

`checklist.md`의 완료 항목을 전부 `[x]`로 바꾼다.

- [ ] **Step 7: 전체 테스트 재실행**

```bash
cd backend && .venv/bin/python -m pytest -q
cd ../web && npx vitest run
cd ../app && flutter analyze && flutter test
```

Expected: 7 passed / 7 passed / No issues found + All tests passed.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "임계값 튜닝 결과와 README 추가"
```

---

## 완료 기준

- [ ] `backend` pytest 7개 통과
- [ ] `web` Vitest 7개 통과 + 뮤테이션 4종이 각각 테스트를 깨뜨림
- [ ] `app` flutter test 4개 통과 + `flutter analyze` 무결
- [ ] 브라우저에서 넘어지면 5초 내 앱에 알림
- [ ] 천천히 눕기 · 급히 앉기에서 오탐지 없음 (3회 연속)
- [ ] 감지 화면에 원본 영상이 어디에도 표시되지 않음
- [ ] DevTools Network 탭에 영상·랜드마크 요청이 없고 `POST /api/falls/`만 있음
- [ ] README에 한계가 명시됨
