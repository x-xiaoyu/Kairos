from __future__ import annotations

import os
import json
import re
from datetime import datetime, timedelta


class KairosAdvisor:
    """Optional Strands/Bedrock judgment layer; deterministic fallbacks keep the demo local."""

    def __init__(self) -> None:
        self.enabled = os.getenv("KAIROS_AI_ENABLED", "false").lower() == "true"
        self._agent = None
        if self.enabled:
            try:
                from strands import Agent
                from strands.models import BedrockModel

                model = BedrockModel(model_id=os.getenv("BEDROCK_MODEL_ID", "us.amazon.nova-lite-v1:0"))
                self._agent = Agent(model=model, system_prompt="You are Kairos. Be concise, practical, calm, and never shame the user.")
            except Exception:
                self.enabled = False

    def classify_load(self, title: str) -> str:
        if self._agent:
            try:
                answer = str(self._agent(f"Classify cognitive load as only low, medium, or high: {title}")).lower()
                return next(level for level in ("low", "medium", "high") if level in answer)
            except Exception:
                pass
        text = title.lower()
        if any(word in text for word in ("design", "write", "analyze", "strategy", "code")):
            return "high"
        if any(word in text for word in ("email", "book", "submit", "call")):
            return "low"
        return "medium"

    def propose(self, message: str, tasks: list[dict], now: datetime, locale: str, counted_task_style: str = "split") -> tuple[dict, str]:
        """Return a typed action proposal. Mutations are never executed here."""
        if self._agent:
            try:
                prompt = f"""The user locale is {locale}. Current time: {now.isoformat()}.
Current tasks: {json.dumps(tasks, ensure_ascii=False, default=str)}
User message: {message}
User's learned counted-task style: {counted_task_style}.
Return JSON only with keys assistant_message and proposed_actions. proposed_actions must be a list using only:
create_task, postpone_task, change_duration, change_priority, complete_task, replan, start_focus, no_action.
Each action may contain task_id, task_title, value (integer minutes or priority), deadline (ISO 8601), and requires_confirmation.
Never perform an action. Use calm concise Chinese when locale starts with zh.
Use defaults without asking: no date means today in the timezone of Current time; no frequency means once; no duration means 30 minutes per task; no clock means 23:59 today.
For N questions/items, return N create_task actions in order unless the learned style is combined. If one total duration is given, divide it evenly; if it says per item, use that duration for each. Keep the response concise."""
                text = str(self._agent(prompt)).strip()
                text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text, flags=re.I)
                result = json.loads(text)
                allowed = {"create_task", "postpone_task", "change_duration", "change_priority", "complete_task", "replan", "start_focus", "no_action"}
                actions = result.get("proposed_actions") if isinstance(result, dict) else None
                if isinstance(actions, list) and all(isinstance(item, dict) and item.get("action") in allowed for item in actions):
                    return result, "bedrock"
            except Exception:
                pass
        return self._local_proposal(message, tasks, now, locale, counted_task_style), "local-fallback"

    def _local_proposal(self, message: str, tasks: list[dict], now: datetime, locale: str, counted_task_style: str = "split") -> dict:
        text = message.strip()
        lower = text.lower()
        active = [task for task in tasks if task.get("status") != "complete"]
        target = next((task for task in active if str(task.get("title", "")).lower() in lower), active[0] if active else None)
        value = self._minutes(lower)
        zh = locale.lower().startswith("zh")

        if any(word in lower for word in ("累", "没状态", "没精神", "tired", "low energy")):
            low = next((task for task in active if task.get("cognitive_load") == "low"), target)
            title = low.get("title") if low else ("先休息几分钟" if zh else "take a short reset")
            return {"assistant_message": f"没关系。建议先做“{title}”，把高认知任务留到状态更好的时间。" if zh else f"Start with {title} and protect demanding work for a better window.", "proposed_actions": [{"action": "replan", "task_id": low.get("id") if low else None, "requires_confirmation": False}]}

        if any(word in lower for word in ("该做", "先做哪", "先做什么", "现在做什么", "来得及", "时间不够", "优先做", "哪个最重要", "what should i do", "which first")):
            return self._priority_proposal(active, now, zh)

        if any(word in lower for word in ("推迟", "延后", "晚点", "postpone", "delay")):
            if not target:
                return self._no_task(zh)
            minutes = max(5, value or 30)
            clock = (now + timedelta(minutes=minutes)).strftime("%H:%M")
            return {"assistant_message": f"我可以把“{target['title']}”推迟 {minutes} 分钟到 {clock}，然后重新计算今天。" if zh else f"I can postpone {target['title']} by {minutes} minutes and rebuild today.", "proposed_actions": [{"action": "postpone_task", "task_id": target["id"], "task_title": target["title"], "value": minutes, "requires_confirmation": True}]}

        creation_words = ("添加", "新建", "记下", "我要", "我想", "想做", "安排", "提醒我", "加一个", "add", "create", "need to", "remind me")
        count = self._counted_task_count(lower)
        counted_creation = count > 1 and any(word in lower for word in ("刷", "做", "练", "solve", "finish"))
        if any(word in lower for word in creation_words) or counted_creation:
            provided_minutes = self._duration_minutes(lower)
            minutes = min(720, max(5, provided_minutes or 30))
            title = self._clean_title(text) or ("新任务" if zh else "New task")
            deadline = self._deadline(lower, now)
            if count > 1 and counted_task_style != "combined":
                per_item = minutes if provided_minutes is None or "每题" in lower or "每个" in lower else max(5, minutes // count)
                base_title = self._remove_count(title)
                actions = [{"action": "create_task", "task_title": f"{base_title}（{index}/{count}）", "value": per_item, "deadline": deadline.isoformat(), "requires_confirmation": True} for index in range(1, count + 1)]
                return {"assistant_message": f"已按今天的本地时间拆成 {count} 条任务，每条约 {per_item} 分钟。" if zh else f"Prepared {count} tasks for today.", "proposed_actions": actions}
            return {"assistant_message": f"我会添加“{title}”，默认今天执行一次，预计 {minutes} 分钟。" if zh else f"I’ll add {title} once today, estimated at {minutes} minutes.", "proposed_actions": [{"action": "create_task", "task_title": title, "value": minutes, "deadline": deadline.isoformat(), "requires_confirmation": True}]}

        if any(word in lower for word in ("时长", "改成", "需要多久", "duration", "take")) and value:
            if not target:
                return self._no_task(zh)
            minutes = min(720, max(5, value))
            return {"assistant_message": f"我可以把“{target['title']}”改为 {minutes} 分钟，并重算所有安全开始时间。" if zh else f"I can change {target['title']} to {minutes} minutes.", "proposed_actions": [{"action": "change_duration", "task_id": target["id"], "task_title": target["title"], "value": minutes, "requires_confirmation": True}]}

        if any(word in lower for word in ("优先级", "priority")) and value:
            if not target:
                return self._no_task(zh)
            priority = min(5, max(1, value))
            return {"assistant_message": f"把“{target['title']}”的优先级调整为 {priority}？" if zh else f"Change {target['title']} priority to {priority}?", "proposed_actions": [{"action": "change_priority", "task_id": target["id"], "task_title": target["title"], "value": priority, "requires_confirmation": True}]}

        if any(word in lower for word in ("完成", "做完", "done", "complete")):
            if not target:
                return self._no_task(zh)
            return {"assistant_message": f"把“{target['title']}”标记为已完成？完成后我会释放这段时间。" if zh else f"Mark {target['title']} complete?", "proposed_actions": [{"action": "complete_task", "task_id": target["id"], "task_title": target["title"], "requires_confirmation": True}]}

        if any(word in lower for word in ("重排", "重新安排", "重新规划", "replan")):
            return {"assistant_message": "我会根据最新任务重新计算今天的顺序和风险。" if zh else "I’ll recalculate today’s order and risk.", "proposed_actions": [{"action": "replan", "requires_confirmation": False}]}

        if not active and text:
            title = text.strip(" ,，。.!！")
            deadline = self._deadline(lower, now)
            return {"assistant_message": f"我会把“{title}”加入今天，默认执行一次、预计 30 分钟。" if zh else f"I’ll add {title} once today, estimated at 30 minutes.", "proposed_actions": [{"action": "create_task", "task_title": title, "value": 30, "deadline": deadline.isoformat(), "requires_confirmation": True}]}

        return {"assistant_message": "我还没有完全理解。你可以告诉我要新增、推迟、改时长、改优先级、完成或重新安排哪个任务。" if zh else "I didn’t fully understand. Tell me which task to add, postpone, resize, complete, or replan.", "proposed_actions": [{"action": "no_action", "requires_confirmation": False}]}

    @staticmethod
    def _minutes(text: str) -> int | None:
        if "半小时" in text:
            return 30
        if "两小时" in text or "两个小时" in text:
            return 120
        if "一小时" in text or "一个小时" in text:
            return 60
        match = re.search(r"\d+", text)
        if not match:
            return None
        value = int(match.group())
        return value * 60 if "小时" in text or "hour" in text else value

    @staticmethod
    def _duration_minutes(text: str) -> int | None:
        if "半小时" in text:
            return 30
        match = re.search(r"(\d+)\s*(分钟|min|minutes|小时|hours?)", text, re.I)
        if not match:
            return None
        value = int(match.group(1))
        return value * 60 if "小时" in match.group(2) or "hour" in match.group(2).lower() else value

    @staticmethod
    def _counted_task_count(text: str) -> int:
        match = re.search(r"(\d+)\s*(?:道|个)?\s*(?:题|questions?)", text, re.I)
        if match:
            return min(20, max(1, int(match.group(1))))
        for word, count in (("十", 10), ("九", 9), ("八", 8), ("七", 7), ("六", 6), ("五", 5), ("四", 4), ("三", 3), ("两", 2), ("二", 2)):
            if f"{word}道" in text or f"{word}个" in text:
                return count
        return 1

    @staticmethod
    def _deadline(text: str, now: datetime) -> datetime:
        clock = re.search(r"(?:晚上|下午)?\s*(\d{1,2})(?::(\d{2})|点(半)?)", text)
        if clock:
            hour = int(clock.group(1))
            if ("晚上" in clock.group(0) or "下午" in clock.group(0)) and hour < 12:
                hour += 12
            minute = 30 if clock.group(3) else int(clock.group(2) or 0)
            base = now + timedelta(days=1) if "明天" in text or "tomorrow" in text else now
            return base.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if "今晚" in text or "tonight" in text:
            return now.replace(hour=22, minute=0, second=0, microsecond=0)
        if "明天" in text or "tomorrow" in text:
            return (now + timedelta(days=1)).replace(hour=23, minute=59, second=0, microsecond=0)
        return now.replace(hour=23, minute=59, second=0, microsecond=0)

    @staticmethod
    def _clean_title(text: str) -> str:
        result = text
        for word in ("请帮我", "帮我", "添加", "新建", "记下", "我要", "我想", "想做", "需要", "安排", "提醒我", "加一个", "今天", "今晚", "明天", "add", "create", "need to", "remind me to"):
            result = re.sub(re.escape(word), "", result, flags=re.I)
        result = re.sub(r"[,，]?\s*(半|一|一个|两|两个)小时.*$", "", result)
        result = re.sub(r"[,，]?\s*\d+\s*(分钟|min|minutes|小时|hours?).*$", "", result, flags=re.I)
        result = re.sub(r"(?:上午|下午|晚上)?\s*(?:\d{1,2}|一|二|两|三|四|五|六|七|八|九|十|十一|十二)\s*[点时](?:半|[0-5]?\d分?)?", "", result)
        return result.strip(" ,，。.!！")

    @staticmethod
    def _remove_count(title: str) -> str:
        return re.sub(r"(?:\d+|二|两|三|四|五|六|七|八|九|十)\s*(?:道|个)", "", title).strip()

    @staticmethod
    def _priority_proposal(active: list[dict], now: datetime, zh: bool) -> dict:
        if not active:
            return KairosAdvisor._no_task(zh)
        end_of_day = now.replace(hour=23, minute=59, second=0, microsecond=0)
        deadlines = []
        for task in active:
            raw = task.get("deadline")
            if not raw:
                continue
            try:
                deadline = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
            except ValueError:
                continue
            if deadline.date() == now.date():
                deadlines.append(deadline)
        horizon = min(max(deadlines), end_of_day) if deadlines else end_of_day
        remaining = max(0, int((horizon - now).total_seconds() // 60))
        needed = sum(max(0, int(task.get("estimated_minutes") or 0)) for task in active)
        ranked = sorted(
            active,
            key=lambda task: (
                0 if task.get("deadline_type") == "hard" else 1 if task.get("deadline") else 2,
                str(task.get("deadline") or "9999"),
                -int(task.get("priority") or 0),
            ),
        )
        pick = ranked[0]
        short = len(active) >= 2 and needed > remaining
        title = pick.get("title") or ("这项任务" if zh else "this task")
        if short:
            message = (
                f"剩下大约 {remaining} 分钟，这 {len(active)} 项大约需要 {needed} 分钟。时间不够一次做完，建议先做“{title}”。要先做它吗？"
                if zh
                else f"About {remaining} minutes left for {needed} minutes of work. Start {title} first?"
            )
        else:
            message = (
                f"综合截止时间和优先级，现在最合适先做“{title}”。要先做它吗？"
                if zh
                else f"Based on deadlines and priority, start {title} first?"
            )
        return {
            "assistant_message": message,
            "proposed_actions": [{
                "action": "start_focus",
                "task_id": pick.get("id"),
                "task_title": title,
                "requires_confirmation": True,
            }],
        }

    @staticmethod
    def _no_task(zh: bool) -> dict:
        return {"assistant_message": "目前没有待办任务。先告诉我要添加什么。" if zh else "There is no active task yet.", "proposed_actions": [{"action": "no_action", "requires_confirmation": False}]}


advisor = KairosAdvisor()
