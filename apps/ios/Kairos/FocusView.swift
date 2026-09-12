import SwiftUI

struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    let task: KairosTask
    let log: (String, String) -> Void
    let onComplete: (Date, Date, Int) -> Void
    @State private var secondsRemaining: Int
    @State private var focusedSeconds = 0
    @State private var startedAt = Date.now
    @State private var running = true
    @State private var showStart = true

    init(task: KairosTask, log: @escaping (String, String) -> Void, onComplete: @escaping (Date, Date, Int) -> Void) {
        self.task = task; self.log = log; self.onComplete = onComplete
        _secondsRemaining = State(initialValue: task.estimatedMinutes * 60)
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var time: String { String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60) }

    var body: some View {
        ZStack {
            KairosTheme.focus.ignoresSafeArea()
            Circle().fill(Color.kairosSun.opacity(0.16)).frame(width: 430).blur(radius: 30).offset(y: -90)
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 1).frame(width: 350).scaleEffect(running ? 1.05 : 0.95).animation(.easeInOut(duration: 2).repeatForever(), value: running)
            VStack(spacing: 24) {
                Label(running ? "FOCUSING NOW" : "FOCUS PAUSED", systemImage: running ? "circle.fill" : "pause.circle.fill").font(.caption.bold()).tracking(2).foregroundStyle(Color.kairosSun)
                Text(task.title).font(.system(size: 34, weight: .bold, design: .serif)).multilineTextAlignment(.center)
                Text(time).font(.system(size: 86, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white).minimumScaleFactor(0.6)
                Text(running ? "Stay with this one thing. Everything else can wait." : "Your time is saved.").font(.system(.body, design: .serif).italic()).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack { Button(running ? "Pause" : "Resume") { running.toggle(); log(running ? "Focus resumed" : "Focus paused", "\(time) remaining.") }.buttonStyle(.borderedProminent); Button("End focus") { log("Focus ended", "\(time) remained."); dismiss() }.buttonStyle(.bordered); Button("Complete") { task.status = .complete; let endedAt = Date.now; log("Completed", "Finished from focus mode after \(max(1, focusedSeconds / 60)) minute(s)."); onComplete(startedAt, endedAt, focusedSeconds); dismiss() }.buttonStyle(.bordered) }
            }.padding(24).foregroundStyle(.white)
            if showStart { ZStack { LinearGradient(colors: [.kairosIndigo, .kairosPurple, .kairosBlue], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea(); VStack(spacing: 14) { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Color.kairosSun); Text("Focus starts!").font(.system(size: 52, weight: .bold, design: .serif)) }.foregroundStyle(.white) }.transition(.opacity.combined(with: .scale)) }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { withAnimation(.easeOut(duration: 0.35)) { showStart = false } } }
        .onReceive(timer) { _ in if running && !showStart && secondsRemaining > 0 { secondsRemaining -= 1; focusedSeconds += 1; if secondsRemaining == 0 { running = false; log("Focus timer finished", "Countdown completed.") } } }
    }
}
