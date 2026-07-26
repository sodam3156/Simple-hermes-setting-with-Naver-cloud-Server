# 04. Datest 프로필 설정: 목표/일정 리마인더 구성

`datest`에서 실제 동작하는 핵심은 4개 파일입니다.

1. `~/.hermes/profiles/datest/scripts/datest_reminder_engine.py`
2. `~/.hermes/profiles/datest/scripts/datest_goal_daily.py`
3. `~/.hermes/profiles/datest/scripts/datest_goal_weekly.py`
4. `~/.hermes/profiles/datest/scripts/datest_goal_monthly.py`
5. `~/.hermes/profiles/datest/scripts/datest_goal_2h.py`

그리고 상태 저장:

- `~/.hermes/profiles/datest/data/datest_goals_and_schedule.json`

---

## 1) SOUL.md(행동 규칙) 템플릿 배치

```bash
cat > ~/.hermes/profiles/datest/SOUL.md <<'EOF'
# Datest 역할 프롬프트
너는 Datest 전용 Telegram 일정/목표 리마인더다.
기본 봇(default)와 분리 운영한다.

- 일간/주간/월간 목표를 텍스트로 저장하고 주기 알림한다.
- 2시간마다 일정 리마인드한다.
- 기본 동작은 데이터파일(`datest_goals_and_schedule.json`) 기반이다.
- 개인정보 및 토큰은 출력하지 않는다.
- 출력은 짧고 실행형으로 한다.
EOF
```

## 2) 스크립트 배치

이 저장소의 `scripts/` 폴더에 샘플 엔진/래퍼가 들어있습니다.
로컬 경로는 예시입니다.

```bash
mkdir -p ~/.hermes/profiles/datest/scripts
cp -v /tmp/Simple-hermes-setting-with-Naver-cloud-Server/scripts/datest_goal_daily.py \
      /tmp/Simple-hermes-setting-with-Naver-cloud-Server/scripts/datest_goal_weekly.py \
      /tmp/Simple-hermes-setting-with-Naver-cloud-Server/scripts/datest_goal_monthly.py \
      /tmp/Simple-hermes-setting-with-Naver-cloud-Server/scripts/datest_goal_2h.py \
      /tmp/Simple-hermes-setting-with-Naver-cloud-Server/scripts/datest_reminder_engine.py \
      ~/.hermes/profiles/datest/scripts/

chmod +x ~/.hermes/profiles/datest/scripts/datest_goal_*.py
```

## 3) 데이터 파일 초기화

```bash
mkdir -p ~/.hermes/profiles/datest/data
cp -v /tmp/Simple-hermes-setting-with-Naver-cloud-Server/scripts/datest_data_template.json \
      ~/.hermes/profiles/datest/data/datest_goals_and_schedule.json
```

파일 구조(요약):

```json
{
  "goals": {
    "daily": ["..."],
    "weekly": ["..."],
    "monthly": ["..."]
  },
  "schedules": [
    {
      "title": "예시",
      "datetime": "2026-07-26 14:30",
      "notes": "메모",
      "calendar": "noted|registered",
      "status": "active",
      "next_notify_at": "2026-07-26T15:00:00+09:00",
      "calendar_ref": "",
      "location": ""
    }
  ]
}
```

- `status` 기본값: `active`
- 완료 처리 시 `done`
- `calendar`: `noted`(메모리만) / `registered`(캘린더 연동 의도)

## 4) 2시간 모드 동작 포인트

- 오늘 일정이 없을 때는 스팸 최소화를 위해 빈 출력(no-op)
- `next_notify_at`이 지난 항목만 이번 주기에서 재알림
- 처리 후 다음 2시간으로 갱신

