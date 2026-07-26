# 03. Telegram 봇 생성 및 `datest` 프로필 연동

이 단계가 핵심입니다. `default`와 완전히 분리되어 있으니 `datest`만 건드립니다.

## 1) Telegram Bot 생성

1. Telegram에서 `@BotFather` 접속
2. `/newbot` 실행
3. 봇 이름/유저네임 입력(유저네임은 `..._bot` 끝)
4. 토큰 발급

⚠️ 토큰 노출 금지: 토큰은 절대 공유 채팅/저장소/캡처에 남기지 않습니다.

## 2) 사용자 ID 확인

`@userinfobot`에 DM를 보내서 숫자형 사용자 ID 획득.

## 3) datest 프로필 `.env` 작성

```bash
cat > ~/.hermes/profiles/datest/.env <<'EOF'
# Datest profile telegram settings (예시)
# 값은 본인 값으로 교체
TELEGRAM_BOT_TOKEN=<TELEGRAM_BOT_TOKEN>
TELEGRAM_ALLOWED_USERS=<USER_ID>

# (권장) cron 알림은 이 채널로 고정
TELEGRAM_HOME_CHANNEL=<TELEGRAM_CHAT_ID_OR_USER_ID>
TELEGRAM_HOME_CHANNEL_NAME="Datest Home"

# 그룹/채널 운영 시:
# TELEGRAM_GROUP_ALLOWED_CHATS=<GROUP_CHAT_ID>
# TELEGRAM_REQUIRE_MENTION=true
# TELEGRAM_ALLOW_ALL_USERS=false

# 기본 시간대 (권장)
TZ=Asia/Seoul
EOF
```

> 다중 사용자 허용은 `TELEGRAM_ALLOWED_USERS=111,222` 형태로 쉼표 구분.

## 4) 홈 채널/대상 확인

```bash
PATH=$HOME/.local/bin:$PATH datest gateway list
PATH=$HOME/.local/bin:$PATH datest send --list telegram
```

`send --list telegram`에서 `telegram:<display_name> [chat_id]`로 등록된 채널이 보여야 합니다.

## 5) 봇 연동 테스트 메시지

```bash
PATH=$HOME/.local/bin:$PATH datest send --to telegram:<CHAT_ID_OR_USER_ID> "datest 연결 테스트 입니다"
```

Telegram에서 실제 수신되면 토큰/채널 설정은 정상이거나 거의 완료된 상태입니다.

## 6) gateway 실행

```bash
# 1회 설치
hermes gateway install

# 프로필별 실행 (데몬)
PATH=$HOME/.local/bin:$PATH datest gateway start   # datest 프로필에서 실행

# 또는 이미 기본 profile을 사용 중이라면
PATH=$HOME/.local/bin:$PATH hermes gateway start
```

> 기존 데몬이 떠있는 환경에서는 profile 전환/재시작 정책이 다를 수 있습니다.
> 운영 중인 환경에서 가장 안전한 방식: `datest gateway status` 또는 `hermes gateway list`에서 `datest` 상태를 확인하는 것입니다.

## 7) 실패 시 체크

- `command not found`:
  - `PATH=$HOME/.local/bin:$PATH`로 재시도
- 토큰이 맞는지 의심:
  - BotFather에서 토큰 재발급 후 재설정
  - 과거 토큰은 바로 폐기
- 메시지 미수신:
  - 챗방/개인ID 정확도, 봇 차단/차단 해제, allowlist 설정 점검

