#!/usr/bin/env bash
# Render 빌드 스크립트 — 의존성 설치와 정적 파일 수집. 마이그레이션은 시작 명령에서 실행한다.
set -o errexit

pip install -r requirements.txt
python manage.py collectstatic --noinput
