# Kairos

**Know when it’s time to start.**

Kairos is an adaptive personal execution agent for people who know what they need to do but struggle to choose what to do now. It creates a realistic daily path, calculates each task’s Latest Safe Start Time, and replans calmly when the day changes.

This hackathon-ready monorepo pairs a Next.js UI with a FastAPI planning service. Time arithmetic stays deterministic; optional Strands Agents + Amazon Bedrock support is reserved for judgment-heavy assistance and falls back gracefully without AWS credentials.

Kairos also includes a native SwiftUI iPhone app in `apps/ios`. The native app is the primary path for personal use: it stores real tasks and routines with SwiftData, schedules local Latest Safe Start notifications, records a timestamped day history, and provides a full-screen focus countdown.

## MVP features

- Goals and richly described tasks: deadline, duration, priority, status, cognitive load, interruptibility, and deadline type
- Workstyle-aware planning and peak-energy placement
- Latest Safe Start calculations and safe/warning/high/critical risk levels
- Interactive focus countdown
- Start, complete, postpone, duration, and priority action support with replanning
- History-based adjustment of focus length and estimates
- Local heuristic fallback when the API or AWS is unavailable
- Focused scheduling and replanning tests

## Structure

```text
apps/
  api/   FastAPI, deterministic scheduler, adaptation, Strands/Bedrock adapter
  ios/   Native SwiftUI app with SwiftData and local notifications
  web/   Next.js dashboard and local demo fallback
```

## Run locally

Requirements: Node.js 20+, Python 3.11+, and npm.

Start the API:

```bash
cd apps/api
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn kairos.main:app --reload --port 8000
```

Then start the web app in another terminal:

```bash
cd apps/web
npm install
npm run dev
```

Open `http://localhost:3000`; API docs are at `http://localhost:8000/docs`. Sample deadlines are relative to the current time. If the API is offline, the UI automatically uses its local scheduler.

## Enable Amazon Bedrock

Copy `.env.example` to `.env`, set `KAIROS_AI_ENABLED=true`, and provide AWS credentials through the normal AWS credential chain. The default is Amazon Nova Lite. Initialization or inference errors fall back to local heuristics. The adapter currently supplies cognitive-load classification; agent judgment never owns deadline arithmetic.

## Verify

```bash
cd apps/api && pytest
cd apps/web && npm run build
```

Key endpoints are `POST /plan`, `POST /actions`, `POST /adapt`, `POST /agent/chat`, and `GET /health`.

## Run the native iPhone app

Requirements: macOS with full Xcode installed, iOS 17 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd apps/ios
brew install xcodegen
xcodegen generate
open Kairos.xcodeproj
```

In Xcode, select the **Kairos** target, open **Signing & Capabilities**, choose your Apple ID team, change the bundle identifier if Xcode reports a conflict, and select your connected iPhone as the run destination. Press Run. A free Apple ID can be used for direct personal-device development; Xcode will explain any provisioning limitations.

The first launch starts empty—add your own tasks with the `+` button. Allow notifications when prompted so Kairos can alert you at each task’s Latest Safe Start. Local notifications are scheduled on the phone and do not require the Python server. Daily routines and the timestamped Review My Day history are stored on-device with SwiftData.

Ask Kairos uses `http://127.0.0.1:8000` by default in the iOS Simulator and automatically falls back to its on-device intent parser if the API is unavailable. For a physical iPhone, open Kairos Settings and use the Mac's LAN address (for example `http://192.168.1.10:8000`) while developing. AWS credentials always stay on the backend, never in the app.

The Agent picker also offers **My AI** for personal OpenAI API usage. The user creates an API key in OpenAI Platform and Kairos stores it in the iOS Keychain with this-device-only protection; it is never stored in SwiftData or logs. This is an advanced personal-use option. A public release should replace long-lived client credentials with a short-lived authorization flow or a user-controlled secure proxy.

For the demo, start the highlighted task, pause/resume its timer, postpone it to see the plan reorder, then complete the next task. The Latest Safe Start panel explains why timing matters without guilt or alarmist language.

## License

MIT
