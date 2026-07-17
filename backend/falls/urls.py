# /api/ 하위 엔드포인트 라우팅

from django.urls import path
from rest_framework.authtoken.views import obtain_auth_token

urlpatterns = [
    path("auth/login/", obtain_auth_token),
]
