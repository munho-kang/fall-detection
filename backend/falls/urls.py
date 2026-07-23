# /api/ 하위 엔드포인트 라우팅

from django.urls import path
from rest_framework.authtoken.views import obtain_auth_token

from . import views

urlpatterns = [
    path("auth/login/", obtain_auth_token),
    path("auth/signup/", views.signup),
    path("falls/", views.FallEventListCreate.as_view()),
    path("falls/<int:pk>/acknowledge/", views.acknowledge),
    path("rooms/", views.RoomListCreate.as_view()),
    path("rooms/<int:pk>/", views.RoomDetail.as_view()),
    path("profile/", views.profile),
]
