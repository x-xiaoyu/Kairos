import Foundation

struct TimeBiasInsight: Equatable {
    let taskCategoryOrLoad: String
    let averageUnderestimateMinutes: Int
    let recommendationText: String
    var biasRatio: Double = 1
    var sampleCount: Int = 0
    var typicalMinutes: Int = 0

    var isCalibration: Bool { biasRatio > TimeBiasReflector.underestimateThreshold }

    func message(forEstimatedMinutes minutes: Int) -> String {
        TimeBiasReflector.agentInsightText(
            sampleCount: sampleCount,
            reservedMinutes: TimeBiasReflector.reservedMinutes(estimated: minutes, biasRatio: biasRatio)
        )
    }
}

struct TimeBiasSample: Equatable {
    let taskTitle: String
    let cognitiveLoad: CognitiveLoad
    let estimatedMinutes: Int
    let actualMinutes: Int
    let completedAt: Date

    var biasRatio: Double { Double(actualMinutes) / Double(max(1, estimatedMinutes)) }
    var deltaMinutes: Int { actualMinutes - estimatedMinutes }
}

struct TimeBiasProfile: Equatable {
    static let neutral = TimeBiasProfile(overallRatio: 1, ratioByLoad: [:], insights: [], sampleCount: 0)

    let overallRatio: Double
    let ratioByLoad: [CognitiveLoad: Double]
    let insights: [TimeBiasInsight]
    let sampleCount: Int

    func adjustment(for load: CognitiveLoad) -> Double {
        ratioByLoad[load] ?? overallRatio
    }

    func shouldCalibrate(_ load: CognitiveLoad) -> Bool {
        adjustment(for: load) > TimeBiasReflector.underestimateThreshold
    }
}

enum TimeBiasReflector {
    static let minimumSamples = 2
    static let underestimateThreshold = 1.2
    static let schedulingRatioRange = 0.8...1.8

    static func profile(tasks: [KairosTask], events: [ActivityEvent]) -> TimeBiasProfile {
        let samples = self.samples(from: tasks, events: events)
        guard samples.count >= minimumSamples else { return .neutral }

        let overallRatio = clampedSchedulingRatio(samples.map(\.biasRatio))
        var ratioByLoad: [CognitiveLoad: Double] = [:]
        for load in CognitiveLoad.allCases {
            let group = samples.filter { $0.cognitiveLoad == load }
            guard group.count >= minimumSamples else { continue }
            ratioByLoad[load] = clampedSchedulingRatio(group.map(\.biasRatio))
        }

        return TimeBiasProfile(
            overallRatio: overallRatio,
            ratioByLoad: ratioByLoad,
            insights: insights(from: samples, overallRatio: overallRatio, ratioByLoad: ratioByLoad),
            sampleCount: samples.count
        )
    }

    static func insight(for load: CognitiveLoad, tasks: [KairosTask], events: [ActivityEvent]) -> TimeBiasInsight? {
        profile(tasks: tasks, events: events).insights.first { $0.taskCategoryOrLoad == loadLabel(load) }
    }

    static func samples(from tasks: [KairosTask], events: [ActivityEvent]) -> [TimeBiasSample] {
        events.compactMap { event in
            guard event.action == "Completed" else { return nil }
            guard let actual = parseActualMinutes(in: event.detail), actual > 0 else { return nil }
            let matched = matchingTask(for: event, tasks: tasks)
            guard let estimated = parseEstimatedMinutes(in: event.detail) ?? matched?.estimatedMinutes, estimated > 0 else { return nil }
            let load = parseLoad(in: event.detail) ?? matched?.cognitiveLoad ?? .medium
            return TimeBiasSample(
                taskTitle: event.taskTitle,
                cognitiveLoad: load,
                estimatedMinutes: estimated,
                actualMinutes: actual,
                completedAt: event.timestamp
            )
        }
    }

    static func calibratedDuration(for task: KairosTask, bias: TimeBiasProfile, baseAdjustment: Double = 1, ignoreDecline: Bool = false) -> Int {
        let ratio = bias.adjustment(for: task.cognitiveLoad)
        let applyCalibration: Bool
        if ignoreDecline {
            applyCalibration = ratio > underestimateThreshold
        } else {
            switch task.timeBiasCalibration {
            case .declined, .accepted:
                applyCalibration = false
            case .automatic:
                applyCalibration = ratio > underestimateThreshold
            }
        }
        let multiplier = applyCalibration ? ratio : 1
        let raw = Double(task.estimatedMinutes) * baseAdjustment * multiplier
        return min(720, max(5, Int(raw.rounded())))
    }

    static func adjustedMinutes(for task: KairosTask, bias: TimeBiasProfile, baseAdjustment: Double = 1) -> Int {
        calibratedDuration(for: task, bias: bias, baseAdjustment: baseAdjustment)
    }

    static func reservedMinutes(estimated: Int, biasRatio: Double) -> Int {
        let ratio = biasRatio > underestimateThreshold ? biasRatio : 1
        return min(720, max(5, Int((Double(max(1, estimated)) * ratio).rounded())))
    }

    static func agentInsightText(sampleCount: Int, reservedMinutes: Int) -> String {
        "💡 Kairos 洞察：基于过去 \(sampleCount) 次专注记录，这类任务预留 \(reservedMinutes) 分钟会更从容。"
    }

    private static func insights(from samples: [TimeBiasSample], overallRatio: Double, ratioByLoad: [CognitiveLoad: Double]) -> [TimeBiasInsight] {
        var result: [TimeBiasInsight] = []
        if let overall = insight(
            category: "全部已完成任务",
            samples: samples,
            ratio: overallRatio
        ) {
            result.append(overall)
        }
        for load in [CognitiveLoad.high, .medium, .low] {
            let group = samples.filter { $0.cognitiveLoad == load }
            guard let ratio = ratioByLoad[load], let item = insight(category: loadLabel(load), samples: group, ratio: ratio) else { continue }
            result.append(item)
        }
        return result
    }

    private static func insight(category: String, samples: [TimeBiasSample], ratio: Double) -> TimeBiasInsight? {
        guard samples.count >= minimumSamples else { return nil }
        let averageDelta = Int((Double(samples.map(\.deltaMinutes).reduce(0, +)) / Double(samples.count)).rounded())
        let typicalMinutes = Int((Double(samples.map(\.actualMinutes).reduce(0, +)) / Double(samples.count)).rounded())
        return TimeBiasInsight(
            taskCategoryOrLoad: category,
            averageUnderestimateMinutes: averageDelta,
            recommendationText: recommendation(category: category, averageDelta: averageDelta, sampleCount: samples.count, typicalMinutes: typicalMinutes, ratio: ratio),
            biasRatio: ratio,
            sampleCount: samples.count,
            typicalMinutes: typicalMinutes
        )
    }

    private static func recommendation(category: String, averageDelta: Int, sampleCount: Int, typicalMinutes: Int, ratio: Double) -> String {
        if ratio > underestimateThreshold {
            return agentInsightText(sampleCount: sampleCount, reservedMinutes: max(5, typicalMinutes))
        }
        let subject = category == "全部已完成任务" ? "这类任务" : category
        if averageDelta <= -5 {
            return "\(subject)你通常比预估少花 \(abs(averageDelta)) 分钟。排期可以稍微收紧，不是要你加快。"
        }
        return "根据最近 \(sampleCount) 次完成记录，\(subject)的预估已经比较贴近真实耗时，先保持现在的缓冲。"
    }

    static func loadLabel(_ load: CognitiveLoad) -> String {
        switch load {
        case .high: "高认知负荷任务"
        case .medium: "中等认知负荷任务"
        case .low: "低认知负荷任务"
        }
    }

    private static func clampedSchedulingRatio(_ ratios: [Double]) -> Double {
        guard !ratios.isEmpty else { return 1 }
        let clipped = ratios.map { min(max($0, 0.5), 2.5) }
        let mean = clipped.reduce(0, +) / Double(clipped.count)
        if abs(mean - 1) < 0.1 { return 1 }
        return min(max(mean, schedulingRatioRange.lowerBound), schedulingRatioRange.upperBound)
    }

    private static func matchingTask(for event: ActivityEvent, tasks: [KairosTask]) -> KairosTask? {
        let matches = tasks.filter { $0.title == event.taskTitle }
        let completed = matches.filter { $0.status == .complete }
        let pool = completed.isEmpty ? matches : completed
        return pool.min { lhs, rhs in
            abs(lhs.createdAt.timeIntervalSince(event.timestamp)) < abs(rhs.createdAt.timeIntervalSince(event.timestamp))
        }
    }

    private static func parseActualMinutes(in text: String) -> Int? {
        firstInt(matching: #"after\s+([0-9]+)\s+minute"#, in: text)
            ?? firstInt(matching: #"Focused for\s+([0-9]+)\s+minute"#, in: text)
            ?? firstInt(matching: #"实际[^\d]*([0-9]+)\s*分钟"#, in: text)
    }

    private static func parseEstimatedMinutes(in text: String) -> Int? {
        firstInt(matching: #"Estimated(?: at)?\s+([0-9]+)\s+minutes?"#, in: text)
            ?? firstInt(matching: #"预估[^\d]*([0-9]+)\s*分钟"#, in: text)
    }

    private static func parseLoad(in text: String) -> CognitiveLoad? {
        if let range = text.range(of: #"Load\s+(low|medium|high)"#, options: [.regularExpression, .caseInsensitive]) {
            let token = text[range].split(separator: " ").last.map(String.init)?.lowercased()
            return token.flatMap(CognitiveLoad.init(rawValue:))
        }
        if text.contains("高认知") { return .high }
        if text.contains("低认知") { return .low }
        if text.contains("中等认知") { return .medium }
        return nil
    }

    private static func firstInt(matching pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[capture])
    }
}
