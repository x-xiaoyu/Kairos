import SwiftUI

struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let task: KairosTask
    let log: (String, String) -> Void
    let onComplete: (Date, Date, Int) -> Void
    @State private var secondsRemaining: Int
    @State private var focusedSeconds = 0
    @State private var startedAt = Date.now
    @State private var running = true
    @State private var focusMode: FocusMode?
    @State private var protectedFocusWasInterrupted = false

    init(task: KairosTask, log: @escaping (String, String) -> Void, onComplete: @escaping (Date, Date, Int) -> Void) {
        self.task = task; self.log = log; self.onComplete = onComplete
        _secondsRemaining = State(initialValue: task.estimatedMinutes * 60)
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var time: String { String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60) }
    private var progress: Double {
        let total = max(1, task.estimatedMinutes * 60)
        return min(1, max(0, Double(total - secondsRemaining) / Double(total)))
    }

    var body: some View {
        ZStack {
            KairosTheme.focus.ignoresSafeArea()
            Circle().fill(Color.kairosSun.opacity(0.14)).frame(width: 360).blur(radius: 55).offset(x: 150, y: -280)
            GeometryReader { geometry in
                ScrollView {
                    if geometry.size.width > geometry.size.height {
                        HStack(spacing: 56) {
                            focusReadout(isLandscape: true)
                                .frame(maxWidth: .infinity)
                            focusControls(vertical: true)
                                .frame(width: min(300, geometry.size.width * 0.3))
                        }
                        .frame(minHeight: geometry.size.height)
                        .padding(.horizontal, 64)
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 40)
                            focusReadout(isLandscape: false)
                            Spacer(minLength: 36)
                            focusControls(vertical: false)
                        }
                        .frame(maxWidth: 620, minHeight: max(500, geometry.size.height))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                    }
                }
                .safeAreaPadding(.bottom, 20)
            }
            .foregroundStyle(.white)
            if focusMode == nil { focusModePicker.transition(.opacity.combined(with: .scale)) }
        }
        .onReceive(timer) { _ in if running && focusMode != nil && secondsRemaining > 0 { secondsRemaining -= 1; focusedSeconds += 1; if secondsRemaining == 0 { running = false; log("Focus timer finished", "Countdown completed.") } } }
        .onChange(of: scenePhase) { _, phase in
            guard focusMode == .stayOnScreen, phase != .active, running else { return }
            running = false
            protectedFocusWasInterrupted = true
            log("Focus paused", "Kairos was left while Keep This Screen was enabled.")
        }
        .onChange(of: focusMode) { _, mode in
            UIApplication.shared.isIdleTimerDisabled = mode == .stayOnScreen
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert("专注已暂停", isPresented: $protectedFocusWasInterrupted) {
            Button("继续") { running = true }
            Button("保持暂停", role: .cancel) {}
        } message: {
            Text("你离开了 Kairos。为了保证专注记录准确，倒计时已自动暂停。")
        }
    }

    private func focusReadout(isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            Label(running ? "专注进行中" : "专注已暂停", systemImage: running ? "circle.fill" : "pause.fill")
                .font(.caption.bold()).tracking(2).foregroundStyle(Color.kairosSun)
            Text(task.title)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Text(time)
                .font(.system(size: isLandscape ? 118 : 92, weight: .medium))
                .monospacedDigit().foregroundStyle(.white).minimumScaleFactor(0.55)
                .padding(.top, isLandscape ? 4 : 12)
            ProgressView(value: progress)
                .tint(Color.kairosSun)
                .background(Color.white.opacity(0.16))
                .clipShape(Capsule())
                .padding(.horizontal, 20)
                .padding(.top, 20)
            Text(running ? "只专注这一件事，其余的稍后再说。" : "进度已为你保留。")
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.top, 20)
        }
    }

    private func focusControls(vertical: Bool) -> some View {
        VStack(spacing: 12) {
            Button(running ? "暂停" : "继续") {
                running.toggle()
                log(running ? "Focus resumed" : "Focus paused", "\(time) remaining.")
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Color.kairosIndigo)
            .frame(maxWidth: .infinity)

            Group {
                if vertical {
                    VStack(spacing: 12) { secondaryFocusButtons }
                } else {
                    HStack(spacing: 12) { secondaryFocusButtons }
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    @ViewBuilder private var secondaryFocusButtons: some View {
        Button("结束专注") { log("Focus ended", "\(time) remained."); dismiss() }
            .frame(maxWidth: .infinity)
        Button("完成任务") {
            task.status = .complete
            let endedAt = Date.now
            log("Completed", "Finished from focus mode after \(max(1, focusedSeconds / 60)) minute(s).")
            onComplete(startedAt, endedAt, focusedSeconds)
            dismiss()
        }
        .frame(maxWidth: .infinity)
    }

    private var focusModePicker: some View {
        ZStack {
            LinearGradient(colors: [.kairosIndigo, .kairosPurple, .kairosBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            ScrollView {
              VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(Color.kairosSun)
                Text("这次怎么专注？")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                Text("选择是否在倒计时期间保持 Kairos 屏幕。")
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    focusModeButton(
                        title: "保持当前屏幕",
                        detail: "保持屏幕常亮；离开 Kairos 时自动暂停",
                        icon: "lock.iphone",
                        mode: .stayOnScreen
                    )
                    focusModeButton(
                        title: "普通专注",
                        detail: "允许锁屏或切换到其他 App，计时继续",
                        icon: "timer",
                        mode: .standard
                    )
                }
                .padding(.top, 8)
              }
              .frame(maxWidth: 560, minHeight: 400)
              .frame(maxWidth: .infinity)
              .padding(28)
            }
            .foregroundStyle(.white)
        }
    }

    private func focusModeButton(title: String, detail: String, icon: String, mode: FocusMode) -> some View {
        Button {
            startedAt = .now
            running = true
            withAnimation(.easeOut(duration: 0.25)) { focusMode = mode }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Image(systemName: "arrow.right")
            }
            .padding(16)
            .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private enum FocusMode {
    case standard
    case stayOnScreen
}
