from __future__ import annotations

from datetime import timedelta

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .agent import advisor
from .models import ActionRequest, AdaptRequest, AgentChatRequest, AgentChatResponse, AgentProposedAction, PlanRequest, PlanResponse, TaskStatus, WorkstyleProfile
from .scheduler import build_plan

app = FastAPI(title="Kairos API", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["http://localhost:3000"], allow_methods=["*"], allow_headers=["*"])


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "ai": "bedrock" if advisor.enabled else "local-fallback"}


@app.post("/plan", response_model=PlanResponse)
def plan(request: PlanRequest) -> PlanResponse:
    return build_plan(request.tasks, request.commitments, request.profile, request.now)


@app.post("/agent/chat", response_model=AgentChatResponse)
def agent_chat(request: AgentChatRequest) -> AgentChatResponse:
    plan_result = build_plan(request.tasks, request.commitments, request.profile, request.now)
    raw, source = advisor.propose(
        request.message,
        [task.model_dump(mode="json") for task in request.tasks],
        request.now,
        request.locale,
        request.counted_task_style,
    )
    actions = [AgentProposedAction.model_validate(item) for item in raw.get("proposed_actions", [])]
    consequences: list[str] = []
    if plan_result.items:
        first = plan_result.items[0]
        if first.latest_safe_start:
            consequences.append(f"“{first.task.title}”最晚应在 {first.latest_safe_start.strftime('%H:%M')} 开始。")
        if len(plan_result.items) > 1:
            consequences.append(f"调整首个任务会影响后续的“{plan_result.items[1].task.title}”。")
    return AgentChatResponse(
        assistant_message=raw.get("assistant_message", "Kairos 已重新评估今天。"),
        proposed_actions=actions,
        plan_summary=plan_result.summary,
        consequences=consequences,
        requires_confirmation=any(action.requires_confirmation for action in actions),
        source=source,
    )


@app.post("/actions", response_model=PlanResponse)
def action(request: ActionRequest) -> PlanResponse:
    task = next((item for item in request.tasks if item.id == request.task_id), None)
    if not task:
        raise HTTPException(404, "Task not found")
    if request.action == "start":
        task.status = TaskStatus.IN_PROGRESS
    elif request.action == "complete":
        task.status = TaskStatus.COMPLETE
    elif request.action == "postpone":
        if not request.value or request.value < 5:
            raise HTTPException(400, "Postpone requires a positive minute value")
        request.now += timedelta(minutes=request.value)
    elif request.action == "change_duration":
        task.estimated_minutes = request.value or task.estimated_minutes
    elif request.action == "change_priority":
        task.priority = request.value or task.priority
    return build_plan(request.tasks, request.commitments, request.profile, request.now)


@app.post("/adapt", response_model=WorkstyleProfile)
def adapt(request: AdaptRequest) -> WorkstyleProfile:
    if not request.history:
        return request.profile
    estimate_ratios = [e.actual_minutes / e.estimated_minutes for e in request.history if e.estimated_minutes]
    focus_ratios = [e.actual_focus_minutes / e.planned_focus_minutes for e in request.history if e.planned_focus_minutes and e.actual_focus_minutes]
    if estimate_ratios:
        observed = sum(estimate_ratios) / len(estimate_ratios)
        request.profile.estimate_adjustment = min(3, max(.5, request.profile.estimate_adjustment * .7 + observed * .3))
    if focus_ratios:
        observed = sum(focus_ratios) / len(focus_ratios)
        request.profile.focus_duration_adjustment = min(2, max(.5, request.profile.focus_duration_adjustment * .7 + observed * .3))
        request.profile.focus_block_minutes = round(request.profile.focus_block_minutes * request.profile.focus_duration_adjustment)
    return request.profile
