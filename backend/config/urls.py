from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path


def healthcheck(request):
    # Render 헬스체크와 "배포가 살아 있나" 눈 확인용. 브라우저로 루트를 열면 이 JSON이 보인다.
    return JsonResponse({"status": "ok", "service": "fall-detection-backend"})


urlpatterns = [
    path("", healthcheck),
    path("admin/", admin.site.urls),
    path("api/", include("falls.urls")),
]
