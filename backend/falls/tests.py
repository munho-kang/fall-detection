# API의 인증·소유권·멱등성을 검증하는 테스트

from unittest import mock

import pytest
from django.contrib.auth.models import User
from django.db import IntegrityError
from django.utils import timezone
from pywebpush import WebPushException
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from falls import push
from falls.models import FallEvent, PushDevice, Room


@pytest.fixture
def guardian(db):
    return User.objects.create_user(username="g1", password="pw12345")


@pytest.fixture
def other(db):
    return User.objects.create_user(username="g2", password="pw12345")


@pytest.fixture(autouse=True)
def _no_push_threads(monkeypatch):
    # POST 테스트가 실제 발송 스레드를 띄우지 않게 막는다 (테스트 DB 보호)
    monkeypatch.setattr("falls.push.send_to_guardian_async", lambda event: None)


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


def test_anonymous_gets_401(db):
    assert APIClient().get("/api/falls/").status_code == 401


def test_login_returns_token(guardian):
    r = APIClient().post(
        "/api/auth/login/", {"username": "g1", "password": "pw12345"}, format="json"
    )
    assert r.status_code == 200
    assert "token" in r.data


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


def test_signup_returns_token_and_logs_in(db):
    r = APIClient().post(
        "/api/auth/signup/", {"username": "new1", "password": "tough-pass-9x"}, format="json"
    )
    assert r.status_code == 201
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Token {r.data['token']}")
    assert c.get("/api/falls/").status_code == 200  # 발급된 토큰이 곧바로 유효해야 한다


def test_signup_duplicate_username_400(guardian):
    r = APIClient().post(
        "/api/auth/signup/", {"username": "g1", "password": "tough-pass-9x"}, format="json"
    )
    assert r.status_code == 400
    assert "username" in r.data


def test_signup_weak_password_400(db):
    # AUTH_PASSWORD_VALIDATORS(8자 미만·흔한 비밀번호·숫자만)가 가입에도 적용되어야 한다
    r = APIClient().post(
        "/api/auth/signup/", {"username": "new2", "password": "1234"}, format="json"
    )
    assert r.status_code == 400
    assert "password" in r.data


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


@pytest.mark.django_db(transaction=True)
def test_room_duplicate_race_returns_400(guardian, monkeypatch):
    # validate의 사전 검사를 우회해 경합 시 안전망(IntegrityError → 400)을 직접 검증한다
    monkeypatch.setattr("falls.serializers.RoomSerializer.validate", lambda self, attrs: attrs)
    Room.objects.create(guardian=guardian, name="안방", number=1)
    r = client_for(guardian).post("/api/rooms/", {"name": "안방", "number": 1}, format="json")
    assert r.status_code == 400
    assert r.data == {"non_field_errors": ["같은 이름과 번호의 방이 이미 있습니다."]}


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


# --- 푸시 기기 등록 (Task 4) ---


def test_push_device_register(guardian):
    r = client_for(guardian).post(
        "/api/push/devices/", {"kind": "webpush", "token": "tok-1"}, format="json"
    )
    assert r.status_code == 201
    device = PushDevice.objects.get(token="tok-1")
    assert device.guardian == guardian and device.kind == "webpush"


def test_push_device_token_moves_to_current_user(guardian, other):
    # 같은 브라우저/기기에서 계정을 전환한 경우 — 토큰은 마지막 사용자 것이 된다
    client_for(other).post(
        "/api/push/devices/", {"kind": "webpush", "token": "tok-1"}, format="json"
    )
    client_for(guardian).post(
        "/api/push/devices/", {"kind": "webpush", "token": "tok-1"}, format="json"
    )
    assert PushDevice.objects.count() == 1
    assert PushDevice.objects.get(token="tok-1").guardian == guardian


def test_push_device_delete(guardian):
    PushDevice.objects.create(guardian=guardian, kind="webpush", token="tok-1")
    r = client_for(guardian).delete("/api/push/devices/", {"token": "tok-1"}, format="json")
    assert r.status_code == 204
    assert PushDevice.objects.count() == 0


def test_push_device_bad_kind_400(guardian):
    c = client_for(guardian)
    for kind in ("smoke-signal", "fcm"):  # fcm은 Android 지원 제거로 더 이상 유효하지 않다
        r = c.post("/api/push/devices/", {"kind": kind, "token": "t"}, format="json")
        assert r.status_code == 400


# --- 푸시 발송 (Task 5) ---

TEST_VAPID_KEY = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"


def test_send_skips_when_vapid_unset(guardian, settings):
    settings.VAPID_PRIVATE_KEY = ""
    PushDevice.objects.create(guardian=guardian, kind="webpush", token='{"endpoint": "e"}')
    with mock.patch("falls.push._send_webpush") as wp:
        push.send_to_guardian(make_event(guardian))
    wp.assert_not_called()


def test_webpush_dead_subscription_deleted(guardian, settings):
    settings.VAPID_PRIVATE_KEY = TEST_VAPID_KEY
    settings.VAPID_SUBJECT = "mailto:test@example.com"
    device = PushDevice.objects.create(guardian=guardian, kind="webpush", token='{"endpoint": "e"}')
    gone = WebPushException("gone", response=mock.Mock(status_code=410))
    with mock.patch("pywebpush.webpush", side_effect=gone):
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
