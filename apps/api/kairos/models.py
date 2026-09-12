from __future__ import annotations

from datetime import datetime, time
from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field


class TaskStatus(str, Enum):
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    COMPLETE = "complete"


class Task(BaseModel):
    id: str
    title: str
    goal: str | None = None
    deadline: datetime | None = None
    estimated_minutes: int = Field(ge=5, le=720)
    priority: int = Field(ge=1, le=5)
    status: TaskStatus = TaskStatus.TODO
    cognitive_load: Literal["low", "medium", "high"] = "medium"
    interruptible: bool = True
    deadline_type: Literal["hard", "soft", "none"] = "soft"


class WorkstyleProfile(BaseModel):
    wake_time: time = time(7, 30)
    sleep_time: time = time(23, 0)
    focus_block_minutes: int = Field(default=45, ge=15, le=120)
    peak_energy_start: time = time(9, 0)
    peak_energy_end: time = time(12, 0)
    focus_duration_adjustment: float = Field(default=1.0, ge=0.5, le=2.0)
    estimate_adjustment: float = Field(default=1.0, ge=0.5, le=3.0)


class Commitment(BaseModel):
    title: str
    start: datetime
    end: datetime


class PlanRequest(BaseModel):
    now: datetime
    tasks: list[Task]
    commitments: list[Commitment] = Field(default_factory=list)
    profile: WorkstyleProfile = Field(default_factory=WorkstyleProfile)


class PlanItem(BaseModel):
    task: Task
    start: datetime
    end: datetime
    latest_safe_start: datetime | None
    risk: Literal["safe", "warning", "high", "critical"]
    explanation: str


class PlanResponse(BaseModel):
    generated_at: datetime
    items: list[PlanItem]
    summary: str
    displaced_task_ids: list[str] = Field(default_factory=list)


class ActionRequest(PlanRequest):
    task_id: str
    action: Literal["start", "complete", "postpone", "change_duration", "change_priority"]
    value: int | None = None


class HistoryEvent(BaseModel):
    estimated_minutes: int
    actual_minutes: int
    planned_focus_minutes: int | None = None
    actual_focus_minutes: int | None = None


class AdaptRequest(BaseModel):
    profile: WorkstyleProfile
    history: list[HistoryEvent]


AgentAction = Literal[
    "create_task", "postpone_task", "change_duration", "change_priority",
    "complete_task", "replan", "start_focus", "no_action",
]


class AgentChatRequest(PlanRequest):
    message: str = Field(min_length=1, max_length=2000)
    locale: str = "zh-CN"
    counted_task_style: Literal["split", "combined"] = "split"


class AgentProposedAction(BaseModel):
    action: AgentAction
    task_id: str | None = None
    task_title: str | None = None
    value: int | None = None
    deadline: datetime | None = None
    requires_confirmation: bool = True


class AgentChatResponse(BaseModel):
    assistant_message: str
    proposed_actions: list[AgentProposedAction] = Field(default_factory=list)
    plan_summary: str
    consequences: list[str] = Field(default_factory=list)
    requires_confirmation: bool = False
    source: Literal["bedrock", "local-fallback"]
