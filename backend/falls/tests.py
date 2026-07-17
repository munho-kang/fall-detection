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
