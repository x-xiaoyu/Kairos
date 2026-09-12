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
}
