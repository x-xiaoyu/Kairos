# Kairos: AI-Powered Executive Function & Action Agent

> **Know when it's time to start — and break the friction to get there.**

Kairos is a proactive, ADHD-tailored personal execution AI Agent for people who know *what* they need to do, but struggle with **executive dysfunction, time blindness, and task paralysis**.

Unlike conventional to-do apps and passive calendar alarms (which rely on guilt-inducing notifications that users ignore), Kairos acts as an empathetic, context-aware **AI Body Double**. It pairs deterministic deadline-risk calculation with LLM reasoning to deconstruct overwhelming tasks into friction-free micro-steps right when intervention matters most.

---

## The Core Philosophy: Why an Agent, Not an Alarm?

- **Passive Timers vs. Contextual Nudges**: Alarms say "Task X is due now" (panic or freeze). The Kairos Agent runs a **3-tier pre-flight nudge pipeline** (`Transition` → `Micro-step Kickoff` → `Friction Grace Rescue`), preparing attention and the physical environment before the clock strikes.
- **Micro-Step Activation (Zero-Friction Ignition)**: Reduces startup paralysis by decomposing high-cognitive tasks into non-threatening physical actions (for example: *"Open the page and type a title."*).
- **Non-Judgmental Dynamic Replanning**: Postponing a task triggers instant, localized re-orchestration — adjacent swap within the same day — without guilt-laden red badges.

---

## Agentic System Architecture

Kairos follows a **Constrained Execution & Dual-Core Architecture**, prioritizing verifiable time math over end-to-end LLM scheduling:

```text
       [ User Actions / Speech / iOS Sensors / Calendar Events ]
                                  │
                                  ▼
      ┌────────────────────────────────────────────────────────┐
      │   Layer 1: Perception & Intent Router (Local / FastAPI) │
      │   • On-device intent parsing and Agent chat            │
      │   • Task Cognitive Load (Low / Med / High)             │
      └───────────────────────────┬────────────────────────────┘
                                  ▼
      ┌────────────────────────────────────────────────────────┐
      │   Layer 2: Deterministic Planner & State Machine        │
      │   • Latest Safe Start (Safe by) hard boundary math     │
      │   • Localized cascade postponement (adjacent swap)     │
      │   • Real wall-clock elapsed background reconciliation  │
      └───────────────────────────┬────────────────────────────┘
                                  ▼
      ┌────────────────────────────────────────────────────────┐
      │   Layer 3: Agentic Reasoning & Adaptive Persona        │
      │   • CBT-informed micro-step copy (local + optional LLM)│
      │   • Safe-by friction detection & Grace Rescue          │
      │   • Body-doubling interactive full-screen launchpad    │
      └────────────────────────────────────────────────────────┘
```

**Deterministic Scheduling Core (zero math hallucination):** Deadlines, buffers, and Latest Safe Start are computed in Swift/Python engines — never guessed by the LLM.

**Cognitive Agent Layer:** Local heuristics, a personal OpenAI key (Keychain-protected), or the FastAPI backend (Amazon Bedrock when enabled). The Agent handles intent, cognitive-load-aware micro-steps, and suggested replans. It never owns deadline arithmetic.

---

## Key Features

- **Dynamic Latest Safe Start (Safe by):** Real-time calculation of the latest moment a task can begin without collapsing the rest of the day.
- **3-Phase Adaptive Pre-flight Interventions:**
  - **Transition buffer (~10 minutes before start, High cognitive load):** Gentle context-switching, not a demand to begin.
  - **T-0 Micro-step ignition:** One minimal physical kickoff cue.
  - **Grace Rescue (near Safe by, postpone, or overdue):** Self-compassionate downgrade, including a 5-minute micro-focus option.
- **Friction-Free Parallel Focus:** True background elapsed-time tracking; concurrent activities can be paused independently; sessions survive force-quit.
- **Live Activities:** In-progress focus, a system countdown, and the current Agent micro-step stay on Dynamic Island and the lock screen so leaving the app does not drop the cue.
- **Apple Calendar write-back:** Saves validated real-focus intervals for reflection.
- **Zero cloud lock-in:** SwiftData local persistence, WidgetKit glances, and on-device intent fallback when offline.

---

## Repository Layout

```text
apps/
  api/          FastAPI orchestration, deterministic scheduler,
                ADHD-aware adaptation tools, Bedrock adapters
  ios/          Native SwiftUI app (SwiftData, wall-clock timers,
                Keychain-backed Agent settings, WidgetKit)
  web/          Next.js dashboard and local fallback playground
```

---

## Getting Started

### 1. Backend orchestration (FastAPI)

Requirements: Python 3.11+ and a virtual environment.

```bash
cd apps/api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn kairos.main:app --reload --port 8000
```

Interactive API docs: [http://localhost:8000/docs](http://localhost:8000/docs).

Optional Amazon Bedrock: copy `.env.example` to `.env`, set `KAIROS_AI_ENABLED=true`, and provide AWS credentials through the normal AWS chain. Init or inference errors fall back to local heuristics. The adapter never owns deadline arithmetic.

### 2. Web dashboard (Next.js)

Requirements: Node.js 20+ and npm.

```bash
cd apps/web
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). If the API is offline, the UI uses its local scheduler.

### 3. Native iOS client (SwiftUI)

Requirements: macOS with Xcode 16+, iOS 17+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd apps/ios
brew install xcodegen
xcodegen generate
open Kairos.xcodeproj
```

In Xcode, select target **Kairos**, configure **Signing & Capabilities** (Personal Team is supported), and pick a device or simulator.

**Agent configuration:** In Settings, connect to a local Mac backend (`http://<YOUR_LOCAL_IP>:8000`) or store a personal OpenAI key in the iOS Keychain. Simulator default is `http://127.0.0.1:8000`; the on-device parser is used if the API is unavailable. AWS credentials stay on the backend, never in the app.

---

## Verification & Test Suites

```bash
# Python scheduler and agent endpoints
cd apps/api && pytest

# Web dashboard
cd apps/web && npm run build
```

iOS: open the **Kairos** scheme in Xcode and run tests on the iOS Simulator. Key API endpoints are `POST /plan`, `POST /actions`, `POST /adapt`, `POST /agent/chat`, and `GET /health`.

---

## License

MIT
