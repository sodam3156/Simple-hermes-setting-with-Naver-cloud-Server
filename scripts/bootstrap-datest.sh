#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$BASE_DIR/.." && pwd)"

read -r -p "텔레그램 봇 토큰 입력: " BOT_TOKEN
read -r -p "허용 사용자 ID 입력 (쉼표 구분): " ALLOWED_USERS
read -r -p "홈 채널 ID 입력(개인ID 또는 그룹ID): " HOME_CHANNEL

read -r -p "이미 datest 프로필을 만들어 둔 경우 이 단계는 생략해주세요. 지금 생성할까요? [y/N]: " CREATE_PROFILE
if [[ "${CREATE_PROFILE,,}" == "y" ]]; then
  hermes profile create datest --clone
fi

mkdir -p "$HOME/.hermes/profiles/datest/scripts" "$HOME/.hermes/profiles/datest/data"

cat > "$HOME/.hermes/profiles/datest/.env" <<EOF
TELEGRAM_BOT_TOKEN=${BOT_TOKEN}
TELEGRAM_ALLOWED_USERS=${ALLOWED_USERS}
TELEGRAM_HOME_CHANNEL=${HOME_CHANNEL}
TELEGRAM_HOME_CHANNEL_NAME="Datest Home"
TELEGRAM_ALLOW_ALL_USERS=false
TZ=Asia/Seoul
EOF

cat > "$HOME/.hermes/profiles/datest/SOUL.md" <<'EOF'
# Datest 역할
일간/주간/월간 목표와 2시간 단위 일정 알림만 처리하는 보조 프로필입니다.
기본 default 봇과 동작을 분리해서 운영합니다.
필요한 경우에만 간결하고 행동형 메시지를 출력합니다.
EOF

cp -f "$REPO_DIR/scripts"/datest_goal_*.py "$HOME/.hermes/profiles/datest/scripts/"
cp -f "$REPO_DIR/scripts/datest_reminder_engine.py" "$HOME/.hermes/profiles/datest/scripts/"
cp -f "$REPO_DIR/scripts/datest_data_template.json" "$HOME/.hermes/profiles/datest/data/datest_goals_and_schedule.json"
chmod +x "$HOME/.hermes/profiles/datest/scripts"/datest_goal_*.py

cat <<'EOF'

초기 배포가 끝났습니다.
확인:
  hermes profile show datest
  PATH=$HOME/.local/bin:$PATH datest send --list telegram
EOF
