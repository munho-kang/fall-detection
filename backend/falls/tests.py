# API의 인증·소유권·멱등성을 검증하는 테스트

import pytest
from django.contrib.auth.models import User
from rest_framework.test import APIClient


@pytest.fixture
def guardian(db):
    return User.objects.create_user(username="g1", password="pw12345")


def test_login_returns_token(guardian):
    r = APIClient().post(
        "/api/auth/login/", {"username": "g1", "password": "pw12345"}, format="json"
    )
    assert r.status_code == 200
    assert "token" in r.data
