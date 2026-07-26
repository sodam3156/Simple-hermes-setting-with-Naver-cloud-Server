#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
사용법:
  export TELEGRAM_BOT_TOKEN=<bot token>
  export TELEGRAM_ALLOWED_USERS=<user_id[,user_id...]>
  export TELEGRAM_HOME_CHANNEL=<chat_id>
  
  [CREATE_PROFILE=1|0] [CREATE_CRON=1|0] [START_GATEWAY=1|0] [AUTO_VERIFY=1|0]
  PATH=$HOME/.local/bin:$PATH
  bash scripts/bootstrap-datest.sh

필수(빈 값이면 대화형 입력):
  TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, TELEGRAM_HOME_CHANNEL

옵션:
  CREATE_PROFILE=1 (기본)  - datest 프로필 생성/보존
  CREATE_CRON=1 (기본)     - cron 4개 등록
  START_GATEWAY=1           - 데몬 자동 시작(기본 미시작)
  AUTO_VERIFY=1 (기본)     - 핵심 send/cron 등록/실행 확인
  DRY_RUN=1                - 실제 반영 없이 체크/메시지 시뮬레이션

예시:
  TELEGRAM_BOT_TOKEN=<TOKEN> \
  TELEGRAM_ALLOWED_USERS=123456789 \
  TELEGRAM_HOME_CHANNEL=<CHAT_ID> \
  PATH=$HOME/.local/bin:$PATH \
  bash scripts/bootstrap-datest.sh

EOF
  exit 0
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
fi

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

run_path() {
  PATH="$HOME/.local/bin:$PATH" "$@"
}

run_hermes() { run_path hermes "$@"; }
run_dtest() { run_path datest "$@"; }

ensure_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    return 1
  fi
}

ensure_datest_command() {
  if ! ensure_cmd datest; then
    if ensure_cmd hermes; then
      run_path datest --version >/dev/null 2>&1 || true
    fi
  fi
  if ! ensure_cmd datest; then
    echo
    err "datest 명령을 찾을 수 없습니다."
    err "해결: PATH=$HOME/.local/bin:$PATH 을 우선 적용하고 hermes 재설치 확인"
    return 1
  fi
}

install_hermes_if_needed() {
  if ensure_cmd hermes && ensure_datest_command; then
    return 0
  fi

  if ! ensure_cmd curl; then
    err "curl이 없어 Hermes 설치를 진행할 수 없습니다. 먼저 curl을 설치하세요."
    return 1
  fi

  log "Hermes CLI가 없어 보입니다. 설치를 진행합니다."
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN=1: 설치를 건너뜁니다."
    return 0
  fi

  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

  if ! ensure_datest_command; then
    warn "hermes 설치 후 datest 경로 미검출. 현재 세션에서 PATH를 갱신합니다."
    export PATH="$HOME/.local/bin:$PATH"
    if ! ensure_datest_command; then
      err "설치 후에도 datest가 보이지 않습니다. 터미널 재실행 후 다시 시도하세요."
      return 1
    fi
  fi
}

ask_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local __result_var="$3"
  local value="${!var_name-}"

  if [[ -z "$value" ]]; then
    read -r -p "$prompt" value
    printf -v "$__result_var" '%s' "$value"
  else
    printf -v "$__result_var" '%s' "$value"
  fi
}

validate_token_inputs() {
  if [[ "$BOT_TOKEN" == "<TELEGRAM_BOT_TOKEN>" || -z "$BOT_TOKEN" ]]; then
    err "TELEGRAM_BOT_TOKEN이 비어있거나 placeholder입니다."
    return 1
  fi

  if [[ "$ALLOWED_USERS" == "<USER_ID_OR_IDS_COMMA_SEPARATED>" || -z "$ALLOWED_USERS" ]]; then
    err "TELEGRAM_ALLOWED_USERS가 비어있거나 placeholder입니다."
    return 1
  fi

  if [[ "$HOME_CHANNEL" == "<CHAT_OR_CHANNEL_ID>" || -z "$HOME_CHANNEL" ]]; then
    err "TELEGRAM_HOME_CHANNEL이 비어있거나 placeholder입니다."
    return 1
  fi
}

preflight() {
  log "1) 선행 체크 시작"

  if [[ ! -d "${BASE_REPO_DIR}" ]]; then
    err "리포지토리 경로가 없습니다: ${BASE_REPO_DIR}"
    return 1
  fi

  if ! ensure_cmd git; then
    err "git 없음: apt install -y git"
    return 1
  fi

  if ! ensure_cmd jq; then
    warn "jq가 없어도 핵심 셋팅은 가능하지만, jq는 설치해두는 걸 권장합니다."
  fi

  if ! ensure_cmd python3; then
    err "python3 없음: apt install -y python3"
    return 1
  fi

  if [[ ! -d "$BASE_REPO_DIR/scripts" ]]; then
    err "스크립트 폴더가 없습니다: $BASE_REPO_DIR/scripts"
    return 1
  fi
}

replace_cron_if_exists() {
  local schedule="$1"; shift
  local prompt="$1"; shift
  local name="$1"; shift
  local script="$1"

  run_dtest datest cron remove "$name" >/dev/null 2>&1 || true
  run_dtest datest cron create "$schedule" "$prompt" \
    --name "$name" \
    --deliver "telegram:$HOME_CHANNEL" \
    --script "$script" \
    --no-agent
}

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_REPO_DIR="$BASE_DIR"
PROFILE_ROOT="$HOME/.hermes/profiles/datest"
DATAPATH="$PROFILE_ROOT/data"
SCRIPTPATH="$PROFILE_ROOT/scripts"

BOT_TOKEN="${TELEGRAM_BOT_TOKEN-}"
ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS-}"
HOME_CHANNEL="${TELEGRAM_HOME_CHANNEL-}"
CREATE_PROFILE="${CREATE_PROFILE:-1}"
CREATE_CRON="${CREATE_CRON:-1}"
START_GATEWAY="${START_GATEWAY:-0}"
AUTO_VERIFY="${AUTO_VERIFY:-1}"
DRY_RUN="${DRY_RUN:-0}"

ask_if_empty TELEGRAM_BOT_TOKEN "텔레그램 봇 토큰(예: 123456:ABC...)를 입력하세요: " BOT_TOKEN
ask_if_empty TELEGRAM_ALLOWED_USERS "허용 사용자 ID(콤마 구분)를 입력하세요: " ALLOWED_USERS
ask_if_empty TELEGRAM_HOME_CHANNEL "기본 알림 채널/챗ID를 입력하세요: " HOME_CHANNEL

if ! validate_token_inputs; then
  usage
fi

if ! preflight; then
  exit 1
fi

if ! install_hermes_if_needed; then
  exit 1
fi

if ! ensure_datest_command; then
  exit 1
fi

log "1) datest 경로 및 권한 준비 완료"

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY_RUN=1: 변경을 적용하지 않고 플랜만 검증합니다."
fi

if [[ "$CREATE_PROFILE" == "1" || "$CREATE_PROFILE" == "true" ]]; then
  log "2) datest 프로필 준비"
  if [[ "$DRY_RUN" != "1" ]]; then
    mkdir -p "$PROFILE_ROOT"
    if run_hermes profile show datest >/dev/null 2>&1; then
      log "이미 datest 프로필이 존재합니다. 기존 설정을 덮어쓰지 않습니다."
    else
      log "datest 프로필 생성 중..."
      run_hermes profile create datest --clone
    fi
  else
    log "DRY_RUN: datest 프로필 생성/확인 생략"
  fi
fi

if [[ "$DRY_RUN" != "1" ]]; then
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
- `default`와 분리된 보조 리마인더 프로필
- 일간/주간/월간 목표 리마인더 + 2시간 단위 일정 알림 운영
- 민감정보(토큰/ID)는 노출하지 않음
EOF

  cp -f "$BASE_REPO_DIR/scripts/datest_goal_*.py" "$SCRIPTPATH/"
  cp -f "$BASE_REPO_DIR/scripts/datest_reminder_engine.py" "$SCRIPTPATH/"
  cp -f "$BASE_REPO_DIR/scripts/datest_data_template.json" "$DATAPATH/datest_goals_and_schedule.json"
  chmod +x "$SCRIPTPATH"/datest_goal_*.py
  chmod +x "$SCRIPTPATH/datest_reminder_engine.py"
fi

if [[ "$CREATE_CRON" == "1" || "$CREATE_CRON" == "true" ]]; then
  if [[ "$DRY_RUN" != "1" ]]; then
    log "3) cron 네 개 등록(재등록 방식)"
    replace_cron_if_exists "0 9 * * *" "" "datest-daily-goal" "datest_goal_daily.py"
    replace_cron_if_exists "0 9 * * 0" "" "datest-weekly-goal" "datest_goal_weekly.py"
    replace_cron_if_exists "0 9 1 * *" "" "datest-monthly-goal" "datest_goal_monthly.py"
    replace_cron_if_exists "every 120m" "" "datest-2h-schedule" "datest_goal_2h.py"
  else
    log "DRY_RUN: cron 등록 생략"
  fi
fi

if [[ "$AUTO_VERIFY" == "1" || "$AUTO_VERIFY" == "true" ]]; then
  log "4) 사후 검증 (문제 시 경고로 계속 진행)"

  if [[ "$DRY_RUN" != "1" ]]; then
    run_dtest datest send --list telegram || warn "send --list telegram 실패(권한/네트워크 이슈)"
    run_dtest datest cron list || warn "cron list 실패"
    run_dtest datest cron run datest-daily-goal || warn "daily cron 수동 실행 실패"
    run_dtest datest cron run datest-weekly-goal || warn "weekly cron 수동 실행 실패"
    run_dtest datest cron run datest-monthly-goal || warn "monthly cron 수동 실행 실패"
    run_dtest datest cron run datest-2h-schedule || warn "2h cron 수동 실행 실패"
  fi
fi

if [[ "$START_GATEWAY" == "1" || "$START_GATEWAY" == "true" ]]; then
  if [[ "$DRY_RUN" != "1" ]]; then
    log "5) gateway 시작 시도"
    run_dtest datest gateway start || warn "datest gateway start 실패(로그 확인 필요)"
    run_dtest datest gateway status || warn "gateway status 실패"
  else
    log "DRY_RUN: gateway 시작 생략"
  fi
fi

log "완료 요약"
echo "- datest 프로필: ${CREATE_PROFILE}"
echo "- cron 등록: ${CREATE_CRON}"
echo "- gateway 자동시작: ${START_GATEWAY}"
echo "- 자동검증: ${AUTO_VERIFY}"
echo "- DRY_RUN: ${DRY_RUN}"

log "다음 단계(다음 줄만 그대로 실행하면 검증 가능):"
echo "export PATH=\"$HOME/.local/bin:$PATH\""
echo "datest send --list telegram"
echo "datest cron list"
echo "datest cron runs datest-2h-schedule --limit 3"

if [[ "$START_GATEWAY" == "0" || "$START_GATEWAY" == "false" ]]; then
  echo "datest gateway start   # 원하면 나중에 1회 실행"
fi

exit 0
