import AudioToolbox
import SwiftUI
import UIKit

struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let availableTasks: [KairosTask]
    let log: (String, KairosTask, String) -> Void
    let onComplete: (KairosTask, Date, Date, Int) -> Void
    @State private var sessions: [FocusCountdown]
    @State private var running = true
    @State private var focusMode: FocusMode?
    @State private var lastTickAt = Date.now
    @State private var showingTaskPicker = false
    @State private var protectedFocusWasInterrupted = false

    init(
        task: KairosTask,
        availableTasks: [KairosTask],
        restored: PersistedFocusState? = nil,
        log: @escaping (String, KairosTask, String) -> Void,
        onComplete: @escaping (KairosTask, Date, Date, Int) -> Void
    ) {
        self.availableTasks = availableTasks
        self.log = log
        self.onComplete = onComplete
        if let restored {
            let restoredSessions = restored.sessions.compactMap { record -> FocusCountdown? in
                guard let match = availableTasks.first(where: { $0.id == record.taskId }) ?? (task.id == record.taskId ? task : nil) else { return nil }
                return FocusCountdown(
                    task: match,
                    startedAt: record.startedAt,
                    secondsRemaining: record.secondsRemaining,
                    focusedSeconds: record.focusedSeconds,
                    isPaused: record.isPaused
                )
            }
            _sessions = State(initialValue: restoredSessions.isEmpty ? [FocusCountdown(task: task)] : restoredSessions)
            _focusMode = State(initialValue: restored.mode)
            _running = State(initialValue: restored.running)
            _lastTickAt = State(initialValue: restored.lastTickAt)
            _protectedFocusWasInterrupted = State(initialValue: restored.interrupted)
        } else {
            _sessions = State(initialValue: [FocusCountdown(task: task)])
        }
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var addableTasks: [KairosTask] {
        let activeIDs = Set(sessions.map(\.id))
        return availableTasks.filter { $0.status != .complete && !activeIDs.contains($0.id) }
    }

    private var anyTicking: Bool {
        sessions.contains { !$0.isPaused && $0.secondsRemaining > 0 }
    }

    var body: some View {
        ZStack {
            KairosTheme.focus.ignoresSafeArea()
            Circle().fill(Color.kairosSun.opacity(0.14)).frame(width: 360).blur(radius: 55).offset(x: 150, y: -280)
            GeometryReader { geometry in
                ScrollView {
                    if geometry.size.width > geometry.size.height {
                        HStack(spacing: 42) {
                            focusReadout(isLandscape: true).frame(maxWidth: .infinity)
                            focusControls.frame(width: min(310, geometry.size.width * 0.32))
                        }
                        .frame(minHeight: geometry.size.height).padding(.horizontal, 52)
                    } else {
                        VStack(spacing: 28) {
                            Spacer(minLength: 34)
                            focusReadout(isLandscape: false)
                            focusControls
                        }
                        .frame(maxWidth: 650, minHeight: max(560, geometry.size.height))
                        .frame(maxWidth: .infinity).padding(.horizontal, 28)
                    }
                }
                .safeAreaPadding(.bottom, 20)
            }
            .foregroundStyle(.white)
            if focusMode == nil { focusModePicker.transition(.opacity.combined(with: .scale)) }
        }
        .onAppear {
            guard focusMode != nil else { return }
            UIApplication.shared.isIdleTimerDisabled = focusMode == .stayOnScreen
            startLiveActivity()
            persist()
        }
        .onReceive(timer) { now in
            guard focusMode != nil, anyTicking else { return }
            consumeElapsed(to: now)
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onChange(of: focusMode) { _, mode in
            UIApplication.shared.isIdleTimerDisabled = mode == .stayOnScreen
            if mode != nil {
                startLiveActivity()
                persist()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            LiveActivityManager.end()
        }
        .sheet(isPresented: $showingTaskPicker) { parallelTaskPicker }
        .alert("专注已暂停", isPresented: $protectedFocusWasInterrupted) {
            Button("继续") { resumeAll() }
            Button("保持暂停", role: .cancel) { persist() }
        } message: { Text("Kairos 被中断或你离开了屏幕。为了保证这次专注，倒计时已自动暂停。") }
    }

    private func focusReadout(isLandscape: Bool) -> some View {
        VStack(spacing: 18) {
            Label(statusLabel, systemImage: anyTicking ? "circle.fill" : "pause.fill")
                .font(.caption.bold()).tracking(2).foregroundStyle(Color.kairosSun)
            if sessions.count == 1, let session = sessions.first {
                Text(session.task.title).font(.system(size: 36, weight: .bold)).multilineTextAlignment(.center).lineLimit(2)
                Text(session.timeText).font(.system(size: isLandscape ? 124 : 98, weight: .medium)).monospacedDigit().minimumScaleFactor(0.55)
                ProgressView(value: session.progress).tint(Color.kairosSun)
                Button(session.isPaused ? "继续这项" : "暂停这项") { togglePause(session) }
                    .buttonStyle(.bordered).tint(.white)
            } else {
                VStack(spacing: 12) { ForEach(sessions) { parallelSessionCard($0) } }
            }
            Text(anyTicking ? "多个任务可以同时计时，也可以单独暂停或完成。" : "进度已为你保留。")
                .foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.center)
        }
    }

    private var statusLabel: String {
        if anyTicking, sessions.contains(where: \.isPaused) { return "部分暂停" }
        return anyTicking ? "专注进行中" : "专注已暂停"
    }

    private func parallelSessionCard(_ session: FocusCountdown) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(session.task.title).font(.headline).lineLimit(2)
                Text(session.isPaused ? "已暂停" : "计时中").font(.caption).foregroundStyle(.white.opacity(0.7))
                ProgressView(value: session.progress).tint(Color.kairosSun)
            }
            Spacer(minLength: 8)
            Text(session.timeText).font(.system(size: 34, weight: .semibold)).monospacedDigit()
            Button { togglePause(session) } label: {
                Image(systemName: session.isPaused ? "play.circle.fill" : "pause.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isPaused ? "继续\(session.task.title)" : "暂停\(session.task.title)")
            Button { complete(session) } label: { Image(systemName: "checkmark.circle.fill").font(.title2) }
                .buttonStyle(.plain).accessibilityLabel("完成\(session.task.title)")
        }
        .padding(16).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
    }

    private var focusControls: some View {
        VStack(spacing: 12) {
            Button(anyTicking ? "暂停全部" : "继续全部") { anyTicking ? pauseAll() : resumeAll() }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Color.kairosIndigo).frame(maxWidth: .infinity)
            Button("添加同时进行的任务") { showingTaskPicker = true }
                .buttonStyle(.bordered).tint(.white).disabled(addableTasks.isEmpty).frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Button("结束全部专注") {
                    sessions.forEach { log("Focus ended", $0.task, "\($0.timeText) remained.") }
                    FocusSessionStore.clear()
                    LiveActivityManager.end()
                    dismiss()
                }.frame(maxWidth: .infinity)
                if sessions.count == 1, let session = sessions.first {
                    Button("完成任务") { complete(session) }.frame(maxWidth: .infinity)
                }
            }.buttonStyle(.bordered).tint(.white)
        }
    }

    private var parallelTaskPicker: some View {
        NavigationStack {
            List(addableTasks) { candidate in
                Button {
                    consumeElapsed(to: .now)
                    sessions.append(FocusCountdown(task: candidate))
                    log("Focus started", candidate, "Added to a concurrent focus session.")
                    lastTickAt = .now
                    running = true
                    showingTaskPicker = false
                    persistAndSync()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.title).foregroundStyle(.primary)
                            Text("\(candidate.estimatedMinutes) 分钟").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("添加并行任务")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showingTaskPicker = false } } }
            .overlay { if addableTasks.isEmpty { ContentUnavailableView("没有其他待办任务", systemImage: "checkmark.circle") } }
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        guard focusMode != nil else { return }
        if phase == .active {
            if focusMode == .standard, anyTicking { consumeElapsed(to: .now) }
            lastTickAt = .now
            persist()
        } else if focusMode == .stayOnScreen, anyTicking {
            consumeElapsed(to: .now)
            pauseAll(reason: "Kairos was left while Keep This Screen was enabled.")
            protectedFocusWasInterrupted = true
        } else {
            persist()
        }
    }

    private func consumeElapsed(to now: Date) {
        let elapsed = max(0, Int(now.timeIntervalSince(lastTickAt)))
        guard elapsed > 0 else { return }
        lastTickAt = lastTickAt.addingTimeInterval(TimeInterval(elapsed))
        for index in sessions.indices {
            let oldValue = sessions[index].secondsRemaining
            sessions[index].consume(elapsed)
            if oldValue > 0, sessions[index].secondsRemaining == 0 {
                log("Focus timer finished", sessions[index].task, "Countdown completed.")
                FocusCue.timerFinished()
            }
        }
        running = anyTicking
        if sessions.allSatisfy({ $0.secondsRemaining == 0 }) {
            running = false
            LiveActivityManager.end()
            FocusSessionStore.clear()
        } else {
            persistAndSync()
        }
    }

    private func pauseAll(reason: String? = nil) {
        consumeElapsed(to: .now)
        for index in sessions.indices { sessions[index].isPaused = true }
        running = false
        sessions.forEach { log("Focus paused", $0.task, reason ?? "\($0.timeText) remaining.") }
        persistAndSync()
    }

    private func resumeAll() {
        lastTickAt = .now
        for index in sessions.indices where sessions[index].secondsRemaining > 0 {
            sessions[index].isPaused = false
        }
        running = anyTicking
        sessions.forEach { log("Focus resumed", $0.task, "\($0.timeText) remaining.") }
        persistAndSync()
    }

    private func togglePause(_ session: FocusCountdown) {
        consumeElapsed(to: .now)
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].isPaused.toggle()
        if sessions[index].isPaused {
            log("Focus paused", sessions[index].task, "\(sessions[index].timeText) remaining.")
        } else {
            lastTickAt = .now
            log("Focus resumed", sessions[index].task, "\(sessions[index].timeText) remaining.")
        }
        running = anyTicking
        persistAndSync()
    }

    private func complete(_ session: FocusCountdown) {
        consumeElapsed(to: .now)
        guard let latest = sessions.first(where: { $0.id == session.id }) else { return }
        latest.task.status = .complete
        let endedAt = Date.now
        log("Completed", latest.task, "Finished from focus mode after \(max(1, latest.focusedSeconds / 60)) minute(s). Estimated \(latest.task.estimatedMinutes) minutes. Load \(latest.task.cognitiveLoad.rawValue).")
        onComplete(latest.task, latest.startedAt, endedAt, latest.focusedSeconds)
        sessions.removeAll { $0.id == latest.id }
        if sessions.isEmpty {
            FocusSessionStore.clear()
            LiveActivityManager.end()
            dismiss()
        } else {
            lastTickAt = .now
            persistAndSync()
        }
    }

    private var focusModePicker: some View {
        ZStack {
            LinearGradient(colors: [.kairosIndigo, .kairosPurple, .kairosBlue], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Color.kairosSun)
                Text("这次怎么专注？").font(.system(size: 38, weight: .bold))
                Text("普通专注允许离开 App 后继续计时。").foregroundStyle(.white.opacity(0.72))
                focusModeButton(title: "保持当前屏幕", detail: "离开 Kairos 时自动暂停", icon: "lock.iphone", mode: .stayOnScreen)
                focusModeButton(title: "普通专注", detail: "锁屏或切换 App，计时继续", icon: "timer", mode: .standard)
            }.frame(maxWidth: 560).padding(28).foregroundStyle(.white)
        }
    }

    private func focusModeButton(title: String, detail: String, icon: String, mode: FocusMode) -> some View {
        Button {
            sessions = sessions.map { FocusCountdown(task: $0.task) }
            lastTickAt = .now
            running = true
            withAnimation(.easeOut(duration: 0.25)) { focusMode = mode }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Image(systemName: "arrow.right")
            }.padding(16).background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func startLiveActivity() {
        guard let session = liveActivitySession() else { return }
        LiveActivityManager.start(task: session.task, secondsRemaining: session.secondsRemaining)
        LiveActivityManager.update(task: session.task, secondsRemaining: session.secondsRemaining, isPaused: session.isPaused || !anyTicking)
    }

    private func persistAndSync() {
        persist()
        syncLiveActivity()
    }

    private func persist() {
        guard let focusMode, !sessions.isEmpty else { return }
        FocusSessionStore.save(
            PersistedFocusState(
                sessions: sessions.map {
                    PersistedFocusSession(
                        taskId: $0.task.id,
                        startedAt: $0.startedAt,
                        secondsRemaining: $0.secondsRemaining,
                        focusedSeconds: $0.focusedSeconds,
                        isPaused: $0.isPaused
                    )
                },
                running: anyTicking,
                mode: focusMode,
                lastTickAt: lastTickAt
            )
        )
    }

    private func syncLiveActivity() {
        guard focusMode != nil, let session = liveActivitySession() else {
            LiveActivityManager.end()
            return
        }
        LiveActivityManager.update(task: session.task, secondsRemaining: session.secondsRemaining, isPaused: session.isPaused || !anyTicking)
    }

    private func liveActivitySession() -> FocusCountdown? {
        sessions.first(where: { !$0.isPaused && $0.secondsRemaining > 0 })
            ?? sessions.first(where: { $0.secondsRemaining > 0 })
            ?? sessions.first
    }
}

struct FocusCountdown: Identifiable {
    let task: KairosTask
    let startedAt: Date
    var secondsRemaining: Int
    var focusedSeconds = 0
    var isPaused = false
    var id: UUID { task.id }

    init(task: KairosTask, startedAt: Date = .now, secondsRemaining: Int? = nil, focusedSeconds: Int = 0, isPaused: Bool = false) {
        self.task = task
        self.startedAt = startedAt
        self.secondsRemaining = secondsRemaining ?? max(0, task.estimatedMinutes * 60)
        self.focusedSeconds = focusedSeconds
        self.isPaused = isPaused
    }

    var timeText: String { String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60) }
    var progress: Double {
        let total = max(1, task.estimatedMinutes * 60)
        return min(1, max(0, Double(total - secondsRemaining) / Double(total)))
    }
    mutating func consume(_ elapsed: Int) {
        guard !isPaused else { return }
        let amount = min(max(0, elapsed), secondsRemaining)
        secondsRemaining -= amount
        focusedSeconds += amount
    }
}

enum FocusCue {
    static func timerFinished() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlayAlertSound(1007)
    }
}
