#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
사용법: TELEGRAM_BOT_TOKEN=<토큰> TELEGRAM_ALLOWED_USERS=<ID[,ID...]> TELEGRAM_HOME_CHANNEL=<채널ID> \
  [CREATE_CRON=1] [CREATE_PROFILE=1] [START_GATEWAY=0] \
  /tmp/.../bootstrap-datest.sh

필수 항목(필요 시 read로 입력 가능):
  TELEGRAM_BOT_TOKEN      Telegram 봇 토큰
  TELEGRAM_ALLOWED_USERS   허용 사용자 ID(쉼표 구분)
  TELEGRAM_HOME_CHANNEL    기본 알림 채널/챗ID

옵션:
  CREATE_CRON=true         cron 등록 단계 실행 (기본 true)
  CREATE_PROFILE=true       datest 프로필 생성(복제) 단계 실행 (기본 true)
  START_GATEWAY=false       데몬 실행까지 자동 시작 (기본 false)
EOF
  exit 0
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
fi

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$BASE_DIR"
PROFILE_ROOT="$HOME/.hermes/profiles/datest"
DATAPATH="$PROFILE_ROOT/data"
SCRIPTPATH="$PROFILE_ROOT/scripts"

BOT_TOKEN="${TELEGRAM_BOT_TOKEN-}"
ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS-}"
HOME_CHANNEL="${TELEGRAM_HOME_CHANNEL-}"
CREATE_CRON="${CREATE_CRON:-1}"
CREATE_PROFILE="${CREATE_PROFILE:-1}"
START_GATEWAY="${START_GATEWAY:-0}"

if [[ -z "$BOT_TOKEN" ]]; then
  read -r -p "텔레그램 봇 토큰을 입력하세요: " BOT_TOKEN
fi
if [[ -z "$ALLOWED_USERS" ]]; then
  read -r -p "허용 사용자 ID를 입력하세요(쉼표 구분): " ALLOWED_USERS
fi
if [[ -z "$HOME_CHANNEL" ]]; then
  read -r -p "기본 알림 채널(챗/채널 ID)을 입력하세요: " HOME_CHANNEL
fi

run_datest() {
  PATH="$HOME/.local/bin:$PATH" "$@"
}

if [[ ! -x "$HOME/.local/bin/datest" ]]; then
  echo "ERROR: datest 명령을 찾을 수 없습니다."
  echo "     먼저 PATH를 확인하세요: export PATH=\"$HOME/.local/bin:$PATH\""
  exit 1
fi

if [[ "$CREATE_PROFILE" == "1" || "$CREATE_PROFILE" == "true" ]]; then
  if hermes profile show datest >/dev/null 2>&1; then
    echo "[INFO] datest 프로필이 이미 존재합니다. 기존 설정을 유지합니다."
  else
    echo "[INFO] datest 프로필을 생성합니다."
    hermes profile create datest --clone
  fi
fi

mkdir -p "$DATAPATH" "$SCRIPTPATH"

cat > "$PROFILE_ROOT/.env" <<EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
TELEGRAM_ALLOWED_USERS=$ALLOWED_USERS
TELEGRAM_HOME_CHANNEL=$HOME_CHANNEL
TELEGRAM_HOME_CHANNEL_NAME="Datest Home"
TELEGRAM_ALLOW_ALL_USERS=false
TZ=Asia/Seoul
EOF
chmod 600 "$PROFILE_ROOT/.env"

cat > "$PROFILE_ROOT/SOUL.md" <<'EOF'
# Datest 역할
- `default`와 완전히 분리된 리마인더 프로필입니다.
- 일간/주간/월간 목표(텍스트)와 2시간 단위 일정 알림을 보냅니다.
- 개인정보 및 토큰은 출력/로그에 남기지 않습니다.
EOF

cp -f "$REPO_DIR/scripts/datest_goal_*.py" "$SCRIPTPATH/"
cp -f "$REPO_DIR/scripts/datest_reminder_engine.py" "$SCRIPTPATH/"
cp -f "$REPO_DIR/scripts/datest_data_template.json" "$DATAPATH/datest_goals_and_schedule.json"
chmod +x "$SCRIPTPATH"/datest_goal_*.py
chmod +x "$SCRIPTPATH/datest_reminder_engine.py"

if [[ "$CREATE_CRON" == "1" || "$CREATE_CRON" == "true" ]]; then
  echo "[INFO] 기존 datest cron 이름(동명) 삭제 후 재등록"
  run_datest datest cron remove datest-daily-goal >/dev/null 2>&1 || true
  run_datest datest cron remove datest-weekly-goal >/dev/null 2>&1 || true
  run_datest datest cron remove datest-monthly-goal >/dev/null 2>&1 || true
  run_datest datest cron remove datest-2h-schedule >/dev/null 2>&1 || true

  run_datest datest cron create "0 9 * * *" "" \
    --name datest-daily-goal \
    --deliver "telegram:$HOME_CHANNEL" \
    --script datest_goal_daily.py --no-agent

  run_datest datest cron create "0 9 * * 0" "" \
    --name datest-weekly-goal \
    --deliver "telegram:$HOME_CHANNEL" \
    --script datest_goal_weekly.py --no-agent

  run_datest datest cron create "0 9 1 * *" "" \
    --name datest-monthly-goal \
    --deliver "telegram:$HOME_CHANNEL" \
    --script datest_goal_monthly.py --no-agent

  run_datest datest cron create "every 120m" "" \
    --name datest-2h-schedule \
    --deliver "telegram:$HOME_CHANNEL" \
    --script datest_goal_2h.py --no-agent
fi

echo
hermes profile show datest || true
echo
run_datest datest send --list telegram
run_datest datest cron list || true

if [[ "$START_GATEWAY" == "1" || "$START_GATEWAY" == "true" ]]; then
  echo "[INFO] 게이트웨이 시작 시도"
  run_datest datest gateway start || run_datest hermes gateway start || true
  run_datest datest gateway status || true
  echo "[INFO] gateway 시작을 시도했습니다. 실패 시 로그와 상태를 확인하세요."
fi

echo
cat <<EOF2
[완료]
- datest 프로필(.env/SOUL/scripts/data): 설정 완료
- cron: $(if [[ "$CREATE_CRON" == "1" || "$CREATE_CRON" == "true" ]]; then echo "등록 완료"; else echo "미등록"; fi)
- gateway 자동시작: $(if [[ "$START_GATEWAY" == "1" || "$START_GATEWAY" == "true" ]]; then echo "시도"; else echo "보류"; fi)

다음 확인:
- PATH=$HOME/.local/bin:$PATH datest send --list telegram
- PATH=$HOME/.local/bin:$PATH datest cron run datest-daily-goal
EOF2
