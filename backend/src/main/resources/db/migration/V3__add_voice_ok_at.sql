-- 낙상자가 음성으로 "괜찮아"라고 답한 시각 — null이면 응답 없음
ALTER TABLE fall_event ADD COLUMN voice_ok_at TIMESTAMPTZ;
