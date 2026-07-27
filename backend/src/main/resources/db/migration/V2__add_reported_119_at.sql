-- 음성 무응답 시 119 자동 신고 시각 — null이면 신고 없음
ALTER TABLE fall_event ADD COLUMN reported_119_at TIMESTAMPTZ;
