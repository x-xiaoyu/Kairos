import SwiftUI

struct TimeBiasInsightBubble: View {
    let text: String
    var choice: TimeBiasCalibrationChoice = .automatic
    var onReserve: (() -> Void)?
    var onKeepEstimate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.kairosInk)
                .fixedSize(horizontal: false, vertical: true)
            switch choice {
            case .automatic:
                if onReserve != nil || onKeepEstimate != nil {
                    HStack(spacing: 8) {
                        if let onReserve {
                            Button("按建议预留", action: onReserve)
                                .buttonStyle(.borderedProminent)
                        }
                        if let onKeepEstimate {
                            Button("先用我填的时长", action: onKeepEstimate)
                                .buttonStyle(.bordered)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .controlSize(.small)
                }
            case .accepted:
                Text("已按更从容的时长排期。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .declined:
                Text("已按你填写的时长排期；预警会更灵敏，不是责备。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(colors: [.white, Color.kairosSun.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.kairosPurple.opacity(0.22))
        )
        .accessibilityElement(children: .combine)
    }
}
