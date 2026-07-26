#!/usr/bin/env python3
"""Datest recurring reminder engine.

Single script used by multiple datest cron jobs.
Behavior is determined by:
- DATEST_REMINDER_MODE env var, or
- script filename (fallback)

Modes:
- daily
- weekly
- monthly
- 2h

Supported file: ~/.hermes/profiles/datest/data/datest_goals_and_schedule.json
Data schema (JSON):
{
  "goals": {
    "daily": ["..."],
    "weekly": ["..."],
    "monthly": ["..."]
  },
  "schedules": [
    {
      "id": "uuid",
      "title": "회의",
      "datetime": "2026-07-26 16:00",      # optional; local time
      "notes": "optional",
      "calendar": "calendar",             # optional: "registered|noted"
      "calendar_ref": "",                  # optional reference (link/id)
      "status": "active|done",
      "next_notify_at": "2026-07-26T10:00:00+09:00"
    }
  ]
}
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List
import re
import os

MODE = os.environ.get("DATEST_REMINDER_MODE") or Path(__file__).name
PROFILE_ROOT = Path.home() / ".hermes" / "profiles" / "datest"
DATA_FILE = PROFILE_ROOT / "data" / "datest_goals_and_schedule.json"
NOW = datetime.now().astimezone()

DEFAULT_DATA: Dict[str, Any] = {
    "goals": {
        "daily": [],
        "weekly": [],
        "monthly": [],
    },
    "schedules": [],
}


def _load_data() -> Dict[str, Any]:
    if not DATA_FILE.exists():
        DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
        DATA_FILE.write_text(json.dumps(DEFAULT_DATA, ensure_ascii=False, indent=2))
        return dict(DEFAULT_DATA)
    try:
        raw = DATA_FILE.read_text(encoding="utf-8")
        data = json.loads(raw or "{}")
    except Exception:
        data = {}

    changed = False
    if not isinstance(data, dict):
        data = {}
    if "goals" not in data or not isinstance(data["goals"], dict):
        data["goals"] = dict(DEFAULT_DATA["goals"])
        changed = True
    for k in ("daily", "weekly", "monthly"):
        if k not in data["goals"] or not isinstance(data["goals"][k], list):
            data["goals"][k] = []
            changed = True
    if "schedules" not in data or not isinstance(data["schedules"], list):
        data["schedules"] = []
        changed = True
    if changed:
        DATA_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    return data


def _save_data(data: Dict[str, Any]) -> None:
    DATA_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2))


def _safe_str(v: Any) -> str:
    return str(v or "").strip()

def _parse_datetime(v: str) -> datetime | None:
    if not v:
        return None
    text = _safe_str(v)
    fmts = [
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d",
    ]
    for fmt in fmts:
        try:
            naive = datetime.strptime(text, fmt)
            return naive.replace(tzinfo=NOW.tzinfo)
        except Exception:
            pass
    m = re.match(r"^(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2})(?::\d{2})?$", text)
    if m:
        try:
            return datetime.fromisoformat(f"{m.group(1)} {m.group(2)}:00").replace(tzinfo=NOW.tzinfo)
        except Exception:
            return None
    return None


def _datetime_has_time(text: str) -> bool:
    t = _safe_str(text)
    return bool(re.search(r"\d{2}:\d{2}", t))


def _contains_deadline_cue(text: str) -> bool:
    t = _safe_str(text)
    if not t:
        return False
    if re.search(r"\b마감\b|기한|데드라인|deadline|due\b|까지", t):
        return True
    if re.search(r"~\s*\d{1,2}(:\d{2})?\s*(?:시)?", t):
        return True
    return False


def _is_physical_task(text: str) -> bool:
    t = _safe_str(text)
    if not t:
        return False

    low = t.lower()
    # 온라인/원격이면 위치 질문 제외
    virtual_only = ["온라인", "화상", "화상회의", "줌", "zoom", "google meet", "teams", "원격", "비대면", "전화", "전화회의", "원격회의", "discord", "webex"]
    if any(k in low for k in virtual_only):
        return False

    physical_markers = [
        "방문", "가야", "가기", "가겠습니다", "가는", "오피스", "사무실", "현장", "출장", "미팅", "면접", "면담",
        "약속", "행사", "워크샵", "대면", "회의실", "호텔", "매장", "카페", "카운터", "병원", "연구실", "클래스", "수업", "지원센터",
        "기관", "복지", "우체국", "은행", "세무서", "행정", "공항", "역", "정류장", "편의점", "학원", "도서관", "도착", "픽업", "이동", "출근", "현지", "탐방", "견학", "면담"
    ]
    return any(k in t for k in physical_markers)


def _needs_clarification(s: Dict[str, Any]) -> list[str]:
    title = _safe_str(s.get("title"))
    notes = _safe_str(s.get("notes"))
    text = f"{title} {notes}"
    asks: list[str] = []

    dt = _safe_str(s.get("datetime"))
    if _contains_deadline_cue(text) and (not dt or not _datetime_has_time(dt)):
        asks.append("정확한 시간")
    if (not _safe_str(s.get("location"))) and _is_physical_task(text):
        asks.append("장소")
    return asks


def _fmt_items(items: List[Dict[str, Any]], prefix: str = ""):
    lines = []
    for idx, item in enumerate(items, start=1):
        title = _safe_str(item.get("title")) or "제목 없음"
        notes = _safe_str(item.get("notes"))
        calendar = _safe_str(item.get("calendar"))
        dt = _safe_str(item.get("datetime"))
        tail = []
        if dt:
            tail.append(f"시간: {dt}")
        if calendar:
            tail.append(f"캘린더: {calendar}")
        tail_text = f" ({'; '.join(tail)})" if tail else ""
        if notes:
            lines.append(f"{prefix}{idx}. {title}{tail_text} — {notes}")
        else:
            lines.append(f"{prefix}{idx}. {title}{tail_text}")
    return lines


def _print_header(title: str) -> str:
    now_str = NOW.strftime("%Y-%m-%d %H:%M")
    return f"[Datest 알림] {title} ({now_str})\n"


def _filter_active(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [x for x in items if _safe_str(x.get("status", "active")) != "done"]


def _run_daily(data: Dict[str, Any]) -> str:
    txt = _print_header("일간 목표 리마인드")
    goals = data["goals"].get("daily", [])
    if goals:
        txt += "오늘의 일간 목표:\n"
        txt += "\n".join(f"- {g}" for g in goals if _safe_str(g))
    else:
        txt += "아직 일간 목표가 등록되지 않았습니다. 예: `일간 목표: 30분 독서 / 2시간 코딩`\n"
    return txt


def _run_weekly(data: Dict[str, Any]) -> str:
    txt = _print_header("주간 목표 리마인드")
    goals = data["goals"].get("weekly", [])
    if goals:
        txt += "이번 주 주간 목표:\n"
        txt += "\n".join(f"- {g}" for g in goals if _safe_str(g))
    else:
        txt += "아직 주간 목표가 등록되지 않았습니다.\n"
    return txt


def _run_monthly(data: Dict[str, Any]) -> str:
    txt = _print_header("월간 목표 리마인드")
    goals = data["goals"].get("monthly", [])
    if goals:
        txt += "이번 달 월간 목표:\n"
        txt += "\n".join(f"- {g}" for g in goals if _safe_str(g))
    else:
        txt += "아직 월간 목표가 등록되지 않았습니다.\n"
    return txt


def _run_2h(data: Dict[str, Any]) -> str:
    # 2시간마다 실행되는 일정 중심 리마인드
    schedules = _filter_active(data.get("schedules", []))
    txt = _print_header("2시간 주기 일정 리마인드")
    if not schedules:
        # No active schedules = no notification output (2h loop stays silent)
        return ""

    changed = False
    due_items = []

    for s in schedules:
        next_notify_raw = _safe_str(s.get("next_notify_at"))
        try:
            next_notify = datetime.fromisoformat(next_notify_raw) if next_notify_raw else None
            if next_notify and next_notify.tzinfo is None:
                next_notify = next_notify.replace(tzinfo=NOW.tzinfo)
        except Exception:
            next_notify = None

        # first-time / stale notifications: notify immediately then update cursor
        if next_notify is None or next_notify <= NOW:
            due_items.append(s)
            next_n = NOW + timedelta(hours=2)
            s["next_notify_at"] = next_n.isoformat(timespec="minutes")
            changed = True

    if changed:
        _save_data(data)

    lines: List[str] = []
    if due_items:
        lines.append("현재 리마인드 대상:")
        lines.extend(_fmt_items(due_items, prefix="- "))
    else:
        lines.append("현재는 다음 알림 시점이 아닙니다.")

    # Clarification queue for deadline/physical schedules with missing time/place.
    clarifications: List[str] = []
    for idx, s in enumerate(due_items, start=1):
        asks = _needs_clarification(s)
        if not asks:
            continue
        title = _safe_str(s.get("title")) or "제목 없음"
        ask_text = "/".join(asks)
        clarifications.append(f"- {idx}. {title}: {ask_text} 알려줄 수 있어?")

    if clarifications:
        lines.append("\n[확인 필요]")
        lines.extend(clarifications)

    # Show closest upcoming 5 schedules for context.
    candidates: List[tuple[datetime | None, Dict[str, Any]]] = []
    for s in schedules:
        dt = _parse_datetime(_safe_str(s.get("datetime")))
        candidates.append((dt, s))
    candidates = sorted(candidates, key=lambda x: x[0] or datetime.max.replace(tzinfo=NOW.tzinfo))

    if candidates:
        lines.append("\n가까운 일정 미리보기:")
        next_items = [s for _, s in candidates[:5] if s not in due_items]
        lines.extend(_fmt_items(next_items, prefix="- "))

    lines.append("\n[캘린더 연동 안내]\n- 데드라인이 있거나 시간이 정해진 일정은 기본 `calendar=registered`로 관리됩니다.\n- 시간/장소가 빠진 일정은 리마인드 타이밍에 먼저 확인 후 캘린더 확정 등록할게요.")
    return txt + "\n".join(lines)


def main() -> int:
    data = _load_data()
    mode = MODE.lower()
    if "daily" in mode:
        out = _run_daily(data)
    elif "weekly" in mode:
        out = _run_weekly(data)
    elif "monthly" in mode:
        out = _run_monthly(data)
    elif "2h" in mode:
        out = _run_2h(data)
    else:
        out = _print_header("Datest 알림") + "실행 모드를 판별할 수 없습니다.\n"

    if out:
        print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
