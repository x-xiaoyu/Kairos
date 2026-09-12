from datetime import datetime, timedelta, timezone

from kairos.models import Commitment, Task, WorkstyleProfile
from kairos.scheduler import build_plan, latest_safe_start, risk_level


NOW = datetime(2026, 9, 10, 9, 0, tzinfo=timezone.utc)


def task(id: str, minutes: int, deadline_hours: int, priority: int = 3) -> Task:
    return Task(id=id, title=id, estimated_minutes=minutes, deadline=NOW + timedelta(hours=deadline_hours), priority=priority, deadline_type="hard")


def test_latest_safe_start_reserves_competing_work():
    first = task("first", 60, 3, 5)
    second = task("second", 30, 4, 3)
    latest = latest_safe_start(second, [first, second], NOW, WorkstyleProfile())
    assert latest == second.deadline - timedelta(minutes=105)


def test_risk_escalates_after_latest_start():
    assert risk_level(NOW, NOW - timedelta(minutes=1)) == "critical"
    assert risk_level(NOW, NOW + timedelta(minutes=20)) == "high"
    assert risk_level(NOW, NOW + timedelta(minutes=60)) == "warning"


def test_plan_works_around_commitment():
    meeting = Commitment(title="Standup", start=NOW + timedelta(minutes=30), end=NOW + timedelta(minutes=60))
    plan = build_plan([task("ship", 45, 5)], [meeting], WorkstyleProfile(), NOW)
    assert plan.items[0].start == meeting.end


def test_replanning_removes_completed_tasks():
    done = task("done", 30, 2)
    done.status = "complete"
    result = build_plan([done, task("next", 30, 3)], [], WorkstyleProfile(), NOW)
    assert [item.task.id for item in result.items] == ["next"]
