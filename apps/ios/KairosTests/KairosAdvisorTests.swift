import XCTest
@testable import Kairos

final class KairosAdvisorTests: XCTestCase {
    func testParsesPostponeRequest() {
        let task = KairosTask(title: "Write proposal", estimatedMinutes: 45)
        let result = KairosAdvisor.interpret("推迟 20 分钟", tasks: [task])
        XCTAssertEqual(result.action, .postpone)
        XCTAssertEqual(result.value, 20)
        XCTAssertEqual(result.taskID, task.id)
    }

    func testParsesChineseTaskCreation() {
        let result = KairosAdvisor.interpret("今晚添加刷两道 LeetCode，40 分钟", tasks: [])
        XCTAssertEqual(result.action, .createTask)
        XCTAssertEqual(result.operations.count, 2)
        XCTAssertEqual(result.operations.map(\.value), [20, 20])
        XCTAssertEqual(result.taskTitle, "刷 LeetCode（1/2）")
        XCTAssertNotNil(result.deadline)
    }

    func testNaturalCountedTaskUsesTodayAndSplitsWithoutAddKeyword() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let result = KairosAdvisor.interpret("晚上八点刷两个算法题", tasks: [], now: now)
        XCTAssertEqual(result.operations.count, 2)
        XCTAssertEqual(result.operations.map(\.value), [30, 30])
        XCTAssertEqual(Calendar.current.component(.hour, from: result.deadline!), 20)
    }

    func testChangingDurationRequiresConfirmation() {
        let task = KairosTask(title: "Review interviews", estimatedMinutes: 45)
        let result = KairosAdvisor.interpret("这个任务时长改成 20 分钟", tasks: [task])
        XCTAssertEqual(result.action, .changeDuration)
        XCTAssertEqual(result.value, 20)
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testUnderstandsNaturalChineseCreation() {
        let result = KairosAdvisor.interpret("我想明天做模拟面试，半小时", tasks: [])
        XCTAssertEqual(result.action, .createTask)
        XCTAssertEqual(result.value, 30)
        XCTAssertEqual(result.taskTitle, "做模拟面试")
        XCTAssertNotNil(result.deadline)
    }

    func testBareTitleCreatesTaskWhenPlanIsEmpty() {
        let result = KairosAdvisor.interpret("Leetcode", tasks: [])
        XCTAssertEqual(result.action, .createTask)
        XCTAssertEqual(result.taskTitle, "Leetcode")
        XCTAssertEqual(result.value, 30)
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testAgentResponseAcceptsFractionalSecondDeadline() throws {
        let json = """
        {
          "assistant_message": "我可以安排它。",
          "proposed_actions": [{
            "action": "create_task",
            "task_id": null,
            "task_title": "刷 LeetCode",
            "value": 40,
            "deadline": "2026-09-11T22:00:00.123-04:00",
            "requires_confirmation": true
          }],
          "plan_summary": "今晚完成。",
          "consequences": [],
          "requires_confirmation": true,
          "source": "personal-openai"
        }
        """
        let response = try JSONDecoder().decode(AgentChatResponseDTO.self, from: Data(json.utf8))
        XCTAssertNotNil(response.proposedActions.first?.deadline)
        XCTAssertEqual(response.makeProposal().taskTitle, "刷 LeetCode")
    }

    func testAgentResponseKeepsRecommendationWhenDeadlineIsDateOnly() throws {
        let json = """
        {
          "assistant_message": "已理解。",
          "proposed_actions": [{
            "action": "create_task",
            "task_id": null,
            "task_title": "准备面试",
            "value": 30,
            "deadline": "2026-09-12",
            "requires_confirmation": true
          }],
          "plan_summary": "明天完成。",
          "consequences": [],
          "requires_confirmation": true,
          "source": "personal-openai"
        }
        """
        let response = try JSONDecoder().decode(AgentChatResponseDTO.self, from: Data(json.utf8))
        XCTAssertNotNil(response.proposedActions.first?.deadline)
    }

    func testLocalStartNudgeAvoidsAlarmLanguage() {
        let task = KairosTask(title: "写项目文档", estimatedMinutes: 45, cognitiveLoad: .high)
        let nudge = KairosAdvisor.generateLocalNudge(for: task, stage: .start)
        let combined = [nudge.title, nudge.subtitle, nudge.body, nudge.microStep, nudge.primaryActionTitle, nudge.secondaryActionTitle].joined()
        XCTAssertFalse(NudgeEngine.isJudgmental(combined))
        XCTAssertTrue(nudge.primaryActionTitle.contains("试水"))
        XCTAssertTrue(nudge.microStep.contains("标题") || nudge.microStep.contains("打开"))
        XCTAssertEqual(nudge.source, .local)
        XCTAssertEqual(nudge.trialMinutes, 15)
    }

    func testHighLoadTransitionIsWarmupNotStart() {
        let task = KairosTask(title: "系统设计复习", estimatedMinutes: 90, cognitiveLoad: .high)
        let nudge = KairosAdvisor.generateLocalNudge(for: task, stage: .transition)
        XCTAssertEqual(nudge.title, "先不用开始")
        XCTAssertTrue(nudge.microStep.contains("还不用正式开始"))
        XCTAssertEqual(nudge.trialMinutes, 0)
        XCTAssertEqual(nudge.microStepLabel, "预热动作")
    }

    func testGraceRescueOffersGuiltFreeDowngrade() {
        let task = KairosTask(title: "刷 LeetCode", estimatedMinutes: 40, cognitiveLoad: .medium)
        let nudge = KairosAdvisor.generateLocalNudge(for: task, stage: .graceRescue)
        XCTAssertTrue(nudge.primaryActionTitle.contains("随时可以停"))
        XCTAssertTrue(nudge.secondaryActionTitle.contains("任务还在"))
        XCTAssertTrue(nudge.microStep.contains("打开题目"))
        XCTAssertEqual(nudge.trialMinutes, 5)
        XCTAssertFalse(NudgeEngine.isJudgmental(nudge.title + nudge.body))
    }

    func testCognitiveLoadChangesStartCopy() {
        let high = KairosTask(title: "准备面试", estimatedMinutes: 60, cognitiveLoad: .high)
        let low = KairosTask(title: "准备面试", estimatedMinutes: 60, cognitiveLoad: .low)
        let highNudge = KairosAdvisor.generateLocalNudge(for: high, stage: .start)
        let lowNudge = KairosAdvisor.generateLocalNudge(for: low, stage: .start)
        XCTAssertNotEqual(highNudge.title, lowNudge.title)
        XCTAssertTrue(highNudge.title.contains("第一步很小"))
    }

    func testPostponedTaskResolvesToGraceRescue() {
        let task = KairosTask(title: "写周报", estimatedMinutes: 30)
        task.dayOrder = 2
        XCTAssertEqual(KairosAdvisor.resolveNudgeStage(for: task, latestSafeStart: nil), .graceRescue)
    }

    func testModelMergeFallsBackWhenCopyIsJudgmental() {
        let task = KairosTask(title: "写周报", estimatedMinutes: 30)
        let local = KairosAdvisor.generateLocalNudge(for: task, stage: .start)
        let merged = NudgeEngine.merging(
            model: ("到时间了", "必须开始", "该开始了", "立即开始认真做", "立即开始", "关闭"),
            onto: local
        )
        XCTAssertEqual(merged, local)
        XCTAssertEqual(merged.source, .local)
    }

    func testModelMergeKeepsEmpathicCopy() {
        let task = KairosTask(title: "写周报", estimatedMinutes: 30)
        let local = KairosAdvisor.generateLocalNudge(for: task, stage: .start)
        let merged = NudgeEngine.merging(
            model: ("先坐下就好", "打开文档敲个标题", "不需要一次写完", "打开页面，写下“周报”两个字", "我已经坐好，开始 15 分钟试水", "这次先路过，不算放弃"),
            onto: local
        )
        XCTAssertEqual(merged.source, .model)
        XCTAssertEqual(merged.title, "先坐下就好")
        XCTAssertEqual(merged.microStep, "打开页面，写下“周报”两个字")
        XCTAssertEqual(merged.stage, .start)
    }

    @MainActor
    func testTimeShortRecommendationAsksToConfirmSinglePriority() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 22, minute: 0))!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 23, minute: 0))!
        let laundry = KairosTask(title: "洗衣服", deadline: deadline, estimatedMinutes: 30, priority: 2, cognitiveLoad: .low)
        laundry.createdAt = now
        let interview = KairosTask(title: "准备面试", deadline: deadline, estimatedMinutes: 30, priority: 5, cognitiveLoad: .high)
        interview.createdAt = now.addingTimeInterval(1)
        let dishes = KairosTask(title: "洗碗", deadline: deadline, estimatedMinutes: 30, priority: 1, cognitiveLoad: .low)
        dishes.createdAt = now.addingTimeInterval(2)
        let shopping = KairosTask(title: "采购", deadline: deadline, estimatedMinutes: 30, priority: 3, cognitiveLoad: .low)
        shopping.createdAt = now.addingTimeInterval(3)
        let plan = Planner.makePlan(tasks: [laundry, interview, dishes, shopping], now: now)
        let recommendation = KairosAdvisor.recommendation(for: plan, presence: .atHome, now: now, calendar: calendar)

        XCTAssertEqual(recommendation?.isTimeShort, true)
        XCTAssertEqual(recommendation?.pickID, interview.id)
        XCTAssertTrue(recommendation?.headline.contains("准备面试") == true)
        XCTAssertTrue(recommendation?.confirmPrompt.contains("准备面试") == true)
        XCTAssertTrue(recommendation?.primaryActionTitle.contains("准备面试") == true)
        XCTAssertEqual(recommendation?.secondaryActionTitle, "稍后再说")
    }

    @MainActor
    func testPriorityQuestionProposesConfirmedStartFocus() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 22, minute: 0))!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 23, minute: 0))!
        let a = KairosTask(title: "洗衣", deadline: deadline, estimatedMinutes: 30, priority: 2)
        a.createdAt = now
        let b = KairosTask(title: "准备面试", deadline: deadline, estimatedMinutes: 30, priority: 5)
        b.createdAt = now.addingTimeInterval(1)
        let c = KairosTask(title: "洗碗", deadline: deadline, estimatedMinutes: 30, priority: 1)
        c.createdAt = now.addingTimeInterval(2)
        let d = KairosTask(title: "采购", deadline: deadline, estimatedMinutes: 30, priority: 3)
        d.createdAt = now.addingTimeInterval(3)

        let result = KairosAdvisor.interpret("时间不够，先做哪个最重要？", tasks: [a, b, c, d], now: now)
        XCTAssertEqual(result.action, .startFocus)
        XCTAssertEqual(result.taskTitle, "准备面试")
        XCTAssertTrue(result.requiresConfirmation)
        XCTAssertTrue(result.explanation.contains("时间不够") || result.explanation.contains("剩下"))
    }
}
