from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path


def healthcheck(request):
    # 서버가 살아 있는지 눈으로 확인하는 용도. 브라우저로 루트를 열면 이 JSON이 보인다.
    return JsonResponse({"status": "ok", "service": "fall-detection-backend"})


urlpatterns = [
    path("", healthcheck),
    # 기본 /admin/ 경로를 노출하지 않아 자동 스캐너를 피한다. 관리자 화면은 /ansgh/로 접속한다.
    path("ansgh/", admin.site.urls),
    path("api/", include("falls.urls")),
]
