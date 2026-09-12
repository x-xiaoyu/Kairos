from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from kairos.main import app


client = TestClient(app)


def payload():
    now = datetime(2026, 9, 10, 9, tzinfo=timezone.utc)
    return {
        "now": now.isoformat(),
        "tasks": [{
            "id": "draft", "title": "Draft proposal", "deadline": (now + timedelta(hours=3)).isoformat(),
            "estimated_minutes": 60, "priority": 5, "cognitive_load": "high",
            "interruptible": False, "deadline_type": "hard", "status": "todo",
        }],
        "commitments": [],
    }


def test_complete_action_replans_without_task():
    body = payload() | {"task_id": "draft", "action": "complete"}
    response = client.post("/actions", json=body)
    assert response.status_code == 200
    assert response.json()["items"] == []


def test_adaptation_learns_underestimation():
    response = client.post("/adapt", json={
        "profile": {},
        "history": [{"estimated_minutes": 30, "actual_minutes": 60, "planned_focus_minutes": 45, "actual_focus_minutes": 35}],
    })
    assert response.status_code == 200
    assert response.json()["estimate_adjustment"] > 1


def test_agent_chat_returns_confirmable_chinese_action():
    body = payload() | {"message": "把 Draft proposal 推迟 20 分钟", "locale": "zh-CN"}
    response = client.post("/agent/chat", json=body)
    assert response.status_code == 200
    result = response.json()
    assert result["source"] == "local-fallback"
    assert result["requires_confirmation"] is True
    assert result["proposed_actions"][0] == {
        "action": "postpone_task", "task_id": "draft", "task_title": "Draft proposal",
        "value": 20, "deadline": None, "requires_confirmation": True,
    }


def test_agent_chat_creates_chinese_task():
    body = payload() | {"tasks": [], "message": "我想明天做模拟面试，半小时", "locale": "zh-CN"}
    response = client.post("/agent/chat", json=body)
    assert response.status_code == 200
    action = response.json()["proposed_actions"][0]
    assert action["action"] == "create_task"
    assert action["task_title"] == "做模拟面试"
    assert action["value"] == 30
    assert action["deadline"] is not None


def test_agent_chat_treats_bare_title_as_new_task_when_day_is_empty():
    body = payload() | {"tasks": [], "message": "Leetcode", "locale": "zh-CN"}
    response = client.post("/agent/chat", json=body)
    assert response.status_code == 200
    result = response.json()
    assert result["assistant_message"].startswith("我会把")
    assert result["proposed_actions"][0]["action"] == "create_task"
    assert result["proposed_actions"][0]["task_title"] == "Leetcode"
    assert result["proposed_actions"][0]["deadline"] is not None


def test_agent_chat_splits_counted_tasks_and_uses_local_today():
    body = payload() | {
        "tasks": [],
        "message": "晚上8点刷两个算法题，40分钟",
        "locale": "zh-CN",
        "counted_task_style": "split",
    }
    response = client.post("/agent/chat", json=body)
    assert response.status_code == 200
    actions = response.json()["proposed_actions"]
    assert len(actions) == 2
    assert [action["value"] for action in actions] == [20, 20]
    assert [action["task_title"] for action in actions] == ["刷算法题（1/2）", "刷算法题（2/2）"]
    assert all(action["deadline"].startswith("2026-09-10T20:00:00") for action in actions)
