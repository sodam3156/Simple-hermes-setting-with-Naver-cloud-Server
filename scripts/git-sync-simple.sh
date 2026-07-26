#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE="origin"
BRANCH="${1:-$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)}"

log_info() {
  echo "[INFO] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

require_remote() {
  if ! git -C "$REPO_ROOT" remote get-url "$REMOTE" >/dev/null 2>&1; then
    log_error "origin remote가 없습니다. 먼저 git clone 또는 git remote 설정을 확인하세요."
    exit 1
  fi
}

normalize_repo_path() {
  local url
  local path

  url="$(git -C "$REPO_ROOT" remote get-url "$REMOTE")"
  case "$url" in
    git@*)
      path="${url#*:}"
      path="${path%.git}"
      ;;
    https://*)
      path="${url#https://github.com/}"
      path="${path%.git}"
      ;;
    *)
      path=""
      ;;
  esac

  echo "$path"
}

push_with_gh() {
  local branch="${1}"
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      log_info "gh 인증 감지 -> gh 경로로 push 시도"
      if git -C "$REPO_ROOT" push "$REMOTE" "$branch"; then
        return 0
      fi
    fi
  fi
  return 1
}

push_with_remote_ssh() {
  local branch="${1}"
  local remote_url
  remote_url="$(git -C "$REPO_ROOT" remote get-url "$REMOTE")"

  if [[ "$remote_url" != git@* ]]; then
    return 1
  fi

  log_info "SSH remote로 push 시도: $remote_url"
  GIT_TERMINAL_PROMPT=0 git -C "$REPO_ROOT" push "$REMOTE" "$branch"
}
push_with_token() {
  local branch="${1}"
  local token="${GIT_PUSH_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
  local token_file="$HOME/.config/simple-hermes/github-token"
  local repo_path
  local https_url
  local basic_payload
  local basic_auth

  if [[ -z "$token" && -f "$token_file" ]]; then
    token="$(sed -E 's/[\r\n]+$//' "$token_file" | tr -d '[:space:]')"
  fi

  if [[ -z "$token" ]]; then
    return 1
  fi

  repo_path="$(normalize_repo_path)"
  if [[ -z "$repo_path" ]]; then
    return 1
  fi

  https_url="https://github.com/${repo_path}.git"

  basic_payload="x-access-token:${token}"
  basic_auth="$(printf '%s' "$basic_payload" | base64 | tr -d '\n')"

  log_info "토큰 기반 push 시도 (Authorization: Basic)"
  if git -C "$REPO_ROOT" -c "http.extraheader=Authorization: Basic ${basic_auth}" push "$https_url" "$branch"; then
    return 0
  fi

  return 1
}

push_with_https_credential() {
  local branch="${1}"
  local orig_url
  local path

  orig_url="$(git -C "$REPO_ROOT" remote get-url "$REMOTE")"
  path="$(normalize_repo_path)"

  if [[ -z "$path" ]]; then
    return 1
  fi

  log_info "원격을 HTTPS로 강제 후 일반 push 시도 (저장된 자격증명 자동 사용)"
  git -C "$REPO_ROOT" remote set-url "$REMOTE" "https://github.com/${path}.git"
  if git -C "$REPO_ROOT" push "$REMOTE" "$branch"; then
    return 0
  fi

  git -C "$REPO_ROOT" remote set-url "$REMOTE" "$orig_url"
  return 1
}

require_remote

log_info "원격 동기화 시작: $(git -C "$REPO_ROOT" remote get-url "$REMOTE")"

if push_with_remote_ssh "$BRANCH"; then
  log_info "push 완료"
  exit 0
fi

if push_with_gh "$BRANCH"; then
  log_info "push 완료"
  exit 0
fi

if push_with_token "$BRANCH"; then
  log_info "push 완료"
  exit 0
fi

if push_with_https_credential "$BRANCH"; then
  log_info "push 완료"
  exit 0
fi

log_error "자동 푸시가 실패했습니다."
log_error "다음 중 하나로 1회만 설정하세요:"
log_error "1) 환경변수로 토큰 주입: export GIT_PUSH_TOKEN=..."
log_error "2) gh auth login"
log_error "3) HTTPS 토큰을 저장: ~/.config/simple-hermes/github-token"
exit 1
