# 02. Hermes 설치와 기본 프로필 구성

> 이 문서는 이미 Hermes가 설치된 환경을 기준으로, 신규 서버에서도 바로 실행 가능한 순서를 함께 적어둔 체크리스트입니다.

## A. Hermes 설치 (신규 서버)

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
hermes --version
```

## B. `default` 프로필 상태 확인

```bash
hermes profile list
hermes gateway list
hermes model
```

예상: `default`가 기본(현재)으로 보이며 동작 중이어야 함.

## C. `datest` 프로필 생성 (기본 봇 분리 운영용)

### 추천 1) 기존 설정 복제 후 `.env` 교체 방식

```bash
hermes profile create datest --clone
```

- `default`의 설정/스킬/SOUL을 기반으로 복제
- **중요**: 생성 직후 곧바로 `~/.hermes/profiles/datest/.env`를 봇별 토큰/허용 사용자로 다시 작성해야 함

### 추천 2) 빈 프로필부터 시작

```bash
hermes profile create datest
```

- 완전히 분리된 시작점
- 아래 `datest .env`, `SOUL.md`, 스크립트는 수동으로 채움

## D. 프로필 확인

```bash
hermes profile show datest
```

확인 포인트
- `Profile: datest`
- `Path: /root/.hermes/profiles/datest`
- `Gateway: stopped` 또는 `running`
- `Alias: datest` 또는 사용자 정의 alias

## E. 실행 alias 점검

터미널에서 `datest`가 보이는지 확인:

```bash
PATH=$HOME/.local/bin:$PATH
which datest
```

> 경고: PATH에 `~/.local/bin`이 빠지면 `datest: command not found`가 잘 발생합니다.

---

## F. 기본 구성 디렉터리(참고)

- `~/.hermes/profiles/datest/.env`
- `~/.hermes/profiles/datest/SOUL.md`
- `~/.hermes/profiles/datest/scripts/`
- `~/.hermes/profiles/datest/data/datest_goals_and_schedule.json`
- `~/.hermes/cron/jobs.json`

