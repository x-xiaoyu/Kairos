from __future__ import annotations

from datetime import date, datetime, time, timedelta

from .models import Commitment, PlanItem, PlanResponse, Task, TaskStatus, WorkstyleProfile


def _at(day: date, value: time, tzinfo) -> datetime:
    return datetime.combine(day, value, tzinfo=tzinfo)


def _merge_busy(commitments: list[Commitment]) -> list[tuple[datetime, datetime]]:
    spans = sorted((c.start, c.end) for c in commitments)
    merged: list[tuple[datetime, datetime]] = []
    for start, end in spans:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    return merged


def _next_free(start: datetime, minutes: int, busy: list[tuple[datetime, datetime]]) -> tuple[datetime, datetime]:
    cursor = start
    duration = timedelta(minutes=minutes)
    while True:
        end = cursor + duration
        overlap = next(((a, b) for a, b in busy if cursor < b and end > a), None)
        if not overlap:
            return cursor, end
        cursor = overlap[1]


def latest_safe_start(task: Task, tasks: list[Task], now: datetime, profile: WorkstyleProfile) -> datetime | None:
    if not task.deadline or task.deadline_type == "none":
        return None
    competing = sum(
        round(other.estimated_minutes * profile.estimate_adjustment)
        for other in tasks
        if other.id != task.id
        and other.status != TaskStatus.COMPLETE
        and other.deadline
        and other.deadline <= task.deadline
        and (other.priority > task.priority or other.deadline < task.deadline)
    )
    own = round(task.estimated_minutes * profile.estimate_adjustment)
    buffer = 15 if task.deadline_type == "hard" else 5
    return task.deadline - timedelta(minutes=own + competing + buffer)


def risk_level(now: datetime, latest: datetime | None, estimated_minutes: int = 30) -> str:
    if latest is None:
        return "safe"
    delta = (latest - now).total_seconds() / 60
    if delta <= 0:
        return "critical"
    if delta <= max(30, estimated_minutes * 0.5):
        return "high"
    if delta <= max(90, estimated_minutes * 1.5):
        return "warning"
    return "safe"


def _score(task: Task, now: datetime, profile: WorkstyleProfile) -> tuple:
    latest = latest_safe_start(task, [], now, profile)
    deadline = task.deadline or datetime.max.replace(tzinfo=now.tzinfo)
    load_match = 1 if task.cognitive_load == "high" and profile.peak_energy_start <= now.timetz().replace(tzinfo=None) <= profile.peak_energy_end else 0
    hard = 1 if task.deadline_type == "hard" else 0
    return (hard, task.priority, load_match, -deadline.timestamp(), -(latest.timestamp() if latest else deadline.timestamp()))


def build_plan(tasks: list[Task], commitments: list[Commitment], profile: WorkstyleProfile, now: datetime) -> PlanResponse:
    active = [t for t in tasks if t.status != TaskStatus.COMPLETE]
    active.sort(key=lambda t: _score(t, now, profile), reverse=True)
    busy = _merge_busy(commitments)
    cursor = now
    sleep = _at(now.date(), profile.sleep_time, now.tzinfo)
    if sleep <= now:
        sleep += timedelta(days=1)
    items: list[PlanItem] = []
    displaced: list[str] = []
    for task in active:
        minutes = round(task.estimated_minutes * profile.estimate_adjustment)
        start, end = _next_free(cursor, minutes, busy)
        if end > sleep:
            displaced.append(task.id)
            continue
        latest = latest_safe_start(task, active, now, profile)
        risk = risk_level(now, latest, minutes)
        if risk == "critical":
            explanation = "Start now to protect the deadline; lower-priority work may need to move."
        elif risk == "high":
            explanation = "This is close to its latest safe start, so it leads the plan."
        elif task.cognitive_load == "high" and profile.peak_energy_start <= start.time() <= profile.peak_energy_end:
            explanation = "Placed in your peak-energy window while the work is still flexible."
        else:
            explanation = "Scheduled by deadline, priority, and the time still available today."
        items.append(PlanItem(task=task, start=start, end=end, latest_safe_start=latest, risk=risk, explanation=explanation))
        cursor = end + timedelta(minutes=5)
    summary = "Your day is protected." if not displaced else f"{len(displaced)} lower-priority task(s) no longer fit today."
    return PlanResponse(generated_at=now, items=items, summary=summary, displaced_task_ids=displaced)
