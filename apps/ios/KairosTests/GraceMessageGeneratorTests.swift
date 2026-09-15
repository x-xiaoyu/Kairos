import XCTest
@testable import Kairos

final class GraceMessageGeneratorTests: XCTestCase {
    func testGeneratesThreeAudienceDrafts() {
        let task = KairosTask(title: "提交设计评审", estimatedMinutes: 40)
        let messages = GraceMessageGenerator.messages(for: task, trigger: .postponed)
        XCTAssertEqual(messages.map(\.scenarioTitle), ["向同事/团队说明", "向教授/导师说明", "给朋友解释"])
        XCTAssertTrue(messages.allSatisfy { $0.messageBody.contains("提交设计评审") })
    }

    func testAcademicTitlePrefersAdvisorFirst() {
        let task = KairosTask(title: "交论文初稿", estimatedMinutes: 90)
        let order = GraceMessageGenerator.preferredAudiences(for: task)
        XCTAssertEqual(order.first, .advisor)
        XCTAssertEqual(GraceMessageGenerator.messages(for: task, trigger: .overdue).first?.scenarioTitle, "向教授/导师说明")
    }

    func testDraftsAvoidShameLanguage() {
        let task = KairosTask(title: "周会材料", deadline: Date.now.addingTimeInterval(3_600), estimatedMinutes: 30)
        let combined = GraceMessageGenerator.messages(for: task, trigger: .overdue).map(\.messageBody).joined()
        ["我又拖延", "我忘了", "对不起我是废物", "必须马上", "我搞砸了"].forEach {
            XCTAssertFalse(combined.contains($0))
        }
        XCTAssertTrue(combined.contains("周会材料"))
    }

    func testPostponedDraftIncludesRevisedTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let revised = now.addingTimeInterval(45 * 60)
        let task = KairosTask(title: "接口联调", estimatedMinutes: 30)
        let body = GraceMessageGenerator.messages(for: task, trigger: .postponed, now: now, revisedStart: revised)[0].messageBody
        XCTAssertTrue(body.contains(revised.formatted(date: .omitted, time: .shortened)))
        XCTAssertTrue(body.contains("微调一下") || body.contains("顺序"))
    }
}
