# Simple-hermes-setting-with-Naver-cloud-Server

이 저장소는 **네이버클라우드 서버 생성 → SSH 접속 → Hermes 설치 → Telegram 봇 연동 → datest 프로필 운영**까지,
초보자도 따라 할 수 있게 정리한 실전 공유 가이드입니다.

> 핵심 원칙: 기존 `default` 봇을 대체하지 않고 `datest` 프로필로만 목표/일정 리마인더를 분리 운영합니다.

---

## 목표

- 네이버 클라우드에서 Ubuntu 서버를 처음 생성할 때 필요한 셋업부터 운영까지 정리
- 텔레그램 봇 생성/연동이 끝난 상태까지 원클릭 가깝게 진행
- 일간·주간·월간 목표 리마인드 + 2시간 단위 일정 리마인드 자동화
- 크론 실행, 수동 테스트, 트러블슈팅까지 실행 로그 기반으로 기록
- 민감정보(`TELEGRAM_BOT_TOKEN` 등)는 저장소에 노출하지 않음

---

## 폴더 구조

- `README.md`: 이 파일 (빠른 진입점)
- `docs/`: 단계별 가이드
  - `01-서버-준비-및-초기-접속.md`
  - `02-Hermes-설치와-프로필-구성.md`
  - `03-Telegram-봇-생성-및-채널-연동.md`
  - `04-datest-프로필-설정-리마인더-구축.md`
  - `05-크론-등록-및-검증.md`
  - `06-문제-해결-체크리스트.md`
  - `07-처음-시작자-체크리스트.md`
- `scripts/`: 샘플 코드
  - `datest_goal_daily.py`
  - `datest_goal_weekly.py`
  - `datest_goal_monthly.py`
  - `datest_goal_2h.py`
  - `datest_reminder_engine.py`
  - `datest_data_template.json`
  - `bootstrap-datest.sh`
- `templates/`
  - `datest.env.example`

---

## 한눈에 실행 순서

```bash
# 1) 서버 접속 후 기본 업데이트
sudo apt update && sudo apt install -y git curl

# 2) Hermes 설치
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
hermes --version

# 3) 저장소에서 템플릿 가져오기
cd /tmp
git clone https://github.com/sodam3156/Simple-hermes-setting-with-Naver-cloud-Server.git
cd Simple-hermes-setting-with-Naver-cloud-Server

# 4) datest 자동 설정(대화형 일부 입력)
chmod +x scripts/bootstrap-datest.sh
# 필요한 값 입력
./scripts/bootstrap-datest.sh

# 5) cron 4개 등록 후 수동 실행 체크(필수)
PATH=$HOME/.local/bin:$PATH datest cron create ...
PATH=$HOME/.local/bin:$PATH datest cron list
PATH=$HOME/.local/bin:$PATH datest cron run datest-daily-goal
PATH=$HOME/.local/bin:$PATH datest cron run datest-weekly-goal
PATH=$HOME/.local/bin:$PATH datest cron run datest-monthly-goal
PATH=$HOME/.local/bin:$PATH datest cron run datest-2h-schedule

# 6) gateway 실행
hermes gateway install
PATH=$HOME/.local/bin:$PATH hermes gateway start
```

`...` 부분은 아래 문서의 상세 가이드를 그대로 복사해 채워주세요.

---

## 핵심 체크리스트

- `datest` 실행은 항상 `PATH=$HOME/.local/bin:$PATH`로 시작
- 2시간 알림은 일정이 없으면 무음(no-op) 동작
- `send --list telegram`과 cron 수동 실행 결과가 동작 확인 기준
- `default` 프로필은 그대로 두고 `datest`로만 일정/리마인더 분리

---

## 보안 원칙

- 토큰, API 키, 자격증명은 절대 저장소에 넣지 않기
- 운영용 값은 `~/.hermes/profiles/datest/.env`에만 저장하고 퍼블릭 채널에 공유 금지
- 로그에 민감값이 없는지 점검 후 배포

---

## 라이선스/공유 주의

이 가이드는 팀 공유를 위한 운영 문서이며, 환경별로 값/도메인/권한 정책을 바꿔서 사용하세요.
