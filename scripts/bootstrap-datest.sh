#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

usage() {
  cat <<'EOF'
사용법:
  # 아래 3개는 반드시 실제 값으로 설정
  export TELEGRAM_BOT_TOKEN=<bot token>
  export TELEGRAM_ALLOWED_USERS=<user_id[,user_id...]>
  export TELEGRAM_HOME_CHANNEL=<chat_id>

  # 옵션(선택)
  export CREATE_PROFILE=1          # datest 프로필 생성/유지 (기본: 1)
  export CREATE_CRON=1             # cron 4개 등록 (기본: 1)
  export START_GATEWAY=0           # bootstrap에서 gateway 시작 (기본: 0)
  export AUTO_VERIFY=1             # 기본 검증 실행 (기본: 1)
  export AUTO_INSTALL_DEPS=1       # 누락된 패키지 자동 설치 (기본: 1)
  export DRY_RUN=0                 # 실제 반영 없이 점검만 수행

  bash scripts/bootstrap-datest.sh

주의:
  실 토큰/ID는 입력하지 말고 환경변수 값으로만 넣으세요.
  PATH=$HOME/.local/bin:$PATH는 필수입니다.
EOF
  exit 0
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
fi

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

run_path() { PATH="$HOME/.local/bin:$PATH" "$@"; }
run_hermes() { run_path hermes "$@"; }
run_dtest() { run_path datest "$@"; }

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_missing_pkgs() {
  local -a pkgs=("$@")
  (( ${#pkgs[@]} == 0 )) && return 0

  local -a _runner=()
  if (( EUID != 0 )); then
    if ! has_cmd sudo; then
      err "root 권한이 없고 sudo가 없어 패키지를 설치할 수 없습니다: ${pkgs[*]}"
      return 1
    fi
    _runner=("sudo")
  fi

  if has_cmd apt-get; then
    log "apt-get로 누락 패키지 설치: ${pkgs[*]}"
    if (( ${#_runner[@]} > 0 )); then
      DEBIAN_FRONTEND=noninteractive "${_runner[@]}" apt-get update -y
      DEBIAN_FRONTEND=noninteractive "${_runner[@]}" apt-get install -y "${pkgs[@]}"
    else
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    fi
    return 0
  fi

  if has_cmd dnf; then
    log "dnf로 누락 패키지 설치: ${pkgs[*]}"
    if (( ${#_runner[@]} > 0 )); then
      run_path "${_runner[@]}" dnf install -y "${pkgs[@]}"
    else
      run_path dnf install -y "${pkgs[@]}"
    fi
    return 0
  fi

  if has_cmd yum; then
    log "yum으로 누락 패키지 설치: ${pkgs[*]}"
    if (( ${#_runner[@]} > 0 )); then
      run_path "${_runner[@]}" yum install -y "${pkgs[@]}"
    else
      run_path yum install -y "${pkgs[@]}"
    fi
    return 0
  fi

  warn "지원되는 패키지 관리자가 없어 자동 설치를 건너뜁니다. 누락 의존성: ${pkgs[*]}"
}

ensure_required_deps() {
  local -a missing=()

  if ! has_cmd git; then missing+=(git); fi
  if ! has_cmd curl; then missing+=(curl); fi
  if ! has_cmd python3; then missing+=(python3); fi
  if ! has_cmd ca-certificates; then
    # ubuntu/ubuntu-like에서는 ca-certificates가 별도 패키지명이 맞고, 일부 환경에서는 이미 내장됨
    if has_cmd apt-get; then
      missing+=(ca-certificates)
    fi
  fi

  if (( ${#missing[@]} > 0 )); then
    if [[ "${AUTO_INSTALL_DEPS:-1}" == "1" ]]; then
      install_missing_pkgs "${missing[@]}"
    else
      err "의존성 누락: ${missing[*]}"
      err "AUTO_INSTALL_DEPS=1로 재실행하거나, 먼저 패키지를 설치하세요."
      return 1
    fi
  fi

  if ! has_cmd python3; then
    err "python3를 사용할 수 없습니다."
    return 1
  fi

  if ! has_cmd datest; then
    warn "datest가 아직 없습니다. 아래 자동 설치 단계에서 보정합니다."
  fi
}

ensure_datest_command() {
  if has_cmd datest; then
    return 0
  fi

  if has_cmd hermes; then
    # 설치 직후 command path가 갱신되지 않아 재설치처럼 보일 수 있으므로 한 번만 시도
    run_path datest --version >/dev/null 2>&1 || true
  fi

  if has_cmd datest; then
    return 0
  fi

  err "datest 명령을 찾을 수 없습니다."
  err "해결: PATH=$HOME/.local/bin:$PATH 적용 + Hermes 재설치 확인"
  return 1
}

install_hermes_if_needed() {
  if has_cmd datest; then
    return 0
  fi

  if ! has_cmd curl; then
    err "curl이 없어 Hermes 설치를 진행할 수 없습니다."
    return 1
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN=1: Hermes 설치 생략"
    return 0
  fi

  log "Hermes CLI가 없어 보입니다. 설치를 진행합니다."
  run_path curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

  export PATH="$HOME/.local/bin:$PATH"
  if ! ensure_datest_command; then
    err "설치 후에도 datest가 보이지 않습니다. 터미널 재실행 후 재시도하세요."
    return 1
  fi
}

validate_token_inputs() {
  if [[ -z "${BOT_TOKEN-}" || "$BOT_TOKEN" == "<TELEGRAM_BOT_TOKEN>" ]]; then
    err "TELEGRAM_BOT_TOKEN이 비어있거나 placeholder입니다."
    return 1
  fi

  if [[ -z "${ALLOWED_USERS-}" || "$ALLOWED_USERS" == "<USER_ID_OR_IDS_COMMA_SEPARATED>" ]]; then
    err "TELEGRAM_ALLOWED_USERS가 비어있거나 placeholder입니다."
    return 1
  fi

  if [[ -z "${HOME_CHANNEL-}" || "$HOME_CHANNEL" == "<CHAT_OR_CHANNEL_ID>" ]]; then
    err "TELEGRAM_HOME_CHANNEL이 비어있거나 placeholder입니다."
    return 1
  fi

  return 0
}

preflight() {
  log "사전 점검 시작"

  if [[ ! -d "${BASE_REPO_DIR}" ]]; then
    err "스크립트 위치를 확인할 수 없습니다: ${BASE_REPO_DIR}"
    return 1
  fi

  if [[ ! -d "$BASE_REPO_DIR/scripts" ]]; then
    err "scripts 디렉터리가 없습니다: $BASE_REPO_DIR/scripts"
    return 1
  fi

  if ! ensure_required_deps; then
    return 1
  fi

  if [[ "${DRY_RUN}" != "1" ]]; then
    run_path mkdir -p "$PROFILE_ROOT"
  fi

  return 0
}

replace_cron_if_exists() {
  local schedule="$1"
  local prompt="$2"
  local name="$3"
  local script="$4"

  run_dtest datest cron remove "$name" >/dev/null 2>&1 || true
  run_dtest datest cron create "$schedule" "$prompt" \
    --name "$name" \
    --deliver "telegram:$HOME_CHANNEL" \
    --script "$script" \
    --no-agent
}

run_or_warn() {
  local label="$1"
  shift
  if "$@"; then
    log "$label: OK"
  else
    warn "$label: FAILED"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
  fi
}

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-1}"
DRY_RUN="${DRY_RUN:-0}"
VERIFY_FAIL=0

if ! validate_token_inputs; then
  usage
fi

if ! preflight; then
  exit 1
fi

if ! install_hermes_if_needed; then
  exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  if ! has_cmd datest; then
    warn "DRY_RUN=1: datest 미설치 상태(현재 환경 기준). 실제 실행에서는 설치 후 검증됩니다."
  fi
else
  if ! ensure_datest_command; then
    exit 1
  fi
fi

log "1) datest 경로 및 권한 준비 완료"

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY_RUN=1: 변경 사항 미반영(점검만 수행)"
fi

if [[ "$CREATE_PROFILE" == "1" || "$CREATE_PROFILE" == "true" ]]; then
  log "2) datest 프로필 준비"
  if [[ "$DRY_RUN" != "1" ]]; then
    if run_hermes profile show datest >/dev/null 2>&1; then
      log "기존 datest 프로필이 존재합니다. 덮어쓰기 없이 유지합니다."
    else
      log "datest 프로필 생성 중..."
      run_hermes profile create datest --clone
    fi
  else
    log "DRY_RUN: 프로필 생성 단계 생략"
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
    log "3) cron 네 개 등록(동일 이름 기존 삭제 후 재등록)"
    replace_cron_if_exists "0 9 * * *" "" "datest-daily-goal" "datest_goal_daily.py"
    replace_cron_if_exists "0 9 * * 0" "" "datest-weekly-goal" "datest_goal_weekly.py"
    replace_cron_if_exists "0 9 1 * *" "" "datest-monthly-goal" "datest_goal_monthly.py"
    replace_cron_if_exists "every 120m" "" "datest-2h-schedule" "datest_goal_2h.py"
  else
    log "DRY_RUN: cron 등록 단계 생략"
  fi
fi

if [[ "$AUTO_VERIFY" == "1" || "$AUTO_VERIFY" == "true" ]]; then
  log "4) 기본 검증 실행"
  if [[ "$DRY_RUN" != "1" ]]; then
    run_or_warn "hermes profile show datest" run_hermes profile show datest
    run_or_warn "datest send --list telegram" run_dtest datest send --list telegram
    run_or_warn "datest cron list" run_dtest datest cron list
    run_or_warn "datest cron run: daily" run_dtest datest cron run datest-daily-goal
    run_or_warn "datest cron run: weekly" run_dtest datest cron run datest-weekly-goal
    run_or_warn "datest cron run: monthly" run_dtest datest cron run datest-monthly-goal
    run_or_warn "datest cron run: 2h" run_dtest datest cron run datest-2h-schedule
  else
    log "DRY_RUN: 검증 단계 스킵"
  fi
fi

if [[ "$START_GATEWAY" == "1" || "$START_GATEWAY" == "true" ]]; then
  if [[ "$DRY_RUN" != "1" ]]; then
    log "5) gateway 시작 시도"
    run_or_warn "datest gateway start" run_dtest datest gateway start
    run_or_warn "datest gateway status" run_dtest datest gateway status
  else
    log "DRY_RUN: gateway 시작 단계 생략"
  fi
fi

log "완료 요약"
echo "- datest 프로필: ${CREATE_PROFILE}"
echo "- cron 등록: ${CREATE_CRON}"
echo "- gateway 자동시작: ${START_GATEWAY}"
echo "- 자동검증: ${AUTO_VERIFY}"
echo "- DRY_RUN: ${DRY_RUN}"

echo
log "검증 실패 건수: ${VERIFY_FAIL}"

if [[ "$AUTO_VERIFY" == "1" || "$AUTO_VERIFY" == "true" ]]; then
  if (( VERIFY_FAIL > 0 )); then
    warn "일부 검증이 실패했습니다. 실행 로그를 확인하고 06-문제-해결-체크리스트.md 항목을 적용하세요."
  else
    log "검증 모두 통과"
  fi
fi

echo
log "후속 명령"
echo "export PATH=\"$HOME/.local/bin:$PATH\""
echo "datest send --list telegram"
echo "datest cron list"
echo "datest cron runs datest-2h-schedule --limit 3"

if [[ "$START_GATEWAY" == "0" || "$START_GATEWAY" == "false" ]]; then
  echo "datest gateway start   # 안정 확인 후 1회 실행 권장"
fi

if (( VERIFY_FAIL > 0 )); then
  exit 2
fi

exit 0
