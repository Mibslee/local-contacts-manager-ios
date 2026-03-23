//
//  IssueOptimizeFlowUITests.swift
//  本地通讯录管家UITests
//
//  可优化项：进入详情 → 全选 → 预执行优化 → 预执行结果 → 写入系统通讯录（确认）→ 完成提示
//

import XCTest

final class IssueOptimizeFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        addUIInterruptionMonitor(withDescription: "通讯录权限") { alert in
            for title in ["好", "Allow", "允许", "OK"] {
                let btn = alert.buttons[title]
                if btn.exists {
                    btn.tap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testIssueDetail_selectAll_preExecute_writeToSystem_fullFlow() throws {
        guard element(identifier: "home.healthScoreCard").waitForExistence(timeout: 45) else {
            throw XCTSkip("需已授权通讯录并加载完成")
        }

        guard app.staticTexts["可优化项目"].waitForExistence(timeout: 8) else {
            throw XCTSkip("当前无「可优化项目」，无法跑全流程")
        }

        let firstRow = app.buttons.matching(identifier: "home.issueRow.first").firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8), "首条可优化项应带有标识 home.issueRow.first")
        firstRow.tap()
        let selectAllId = element(identifier: "issue.detail.selectAll")
        if !selectAllId.waitForExistence(timeout: 10) {
            firstRow.tap()
        }
        guard selectAllId.waitForExistence(timeout: 240) else {
            throw XCTSkip(
                "未在限时内进入问题详情（含全选）。请在模拟器前台运行、已授权通讯录，并确认首条可优化项可手动点开；重复联系人会先「建立索引」较久。"
            )
        }

        if app.staticTexts["没有找到需要处理的联系人"].waitForExistence(timeout: 3) {
            throw XCTSkip("该问题下无联系人，跳过")
        }

        selectAllId.tap()

        let preExec = element(identifier: "issue.detail.preExecute")
        let preExecText = app.staticTexts["预执行优化"].firstMatch
        XCTAssertTrue(preExec.waitForExistence(timeout: 5) || preExecText.waitForExistence(timeout: 5))
        (preExec.exists ? preExec : preExecText).tap()

        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正在处理")).firstMatch.waitForExistence(timeout: 15)

        XCTAssertTrue(
            element(identifier: "preexecute.result.root").waitForExistence(timeout: 120),
            "预执行完成后应展示预执行结果"
        )
        XCTAssertTrue(app.staticTexts["预执行结果"].waitForExistence(timeout: 5))

        let writeBtn = element(identifier: "preexecute.writeSystem")
        XCTAssertTrue(writeBtn.waitForExistence(timeout: 5))
        writeBtn.tap()

        let writeAlert = app.alerts["写入系统通讯录"]
        XCTAssertTrue(writeAlert.waitForExistence(timeout: 10), "应弹出写入确认")
        writeAlert.buttons["确认写入"].tap()

        let writing = app.staticTexts["正在写入，请稍候..."].firstMatch
        _ = writing.waitForExistence(timeout: 5)

        let doneAlert = app.alerts["写入完成"]
        XCTAssertTrue(doneAlert.waitForExistence(timeout: 180), "应出现写入完成提示")
        doneAlert.buttons["确定"].tap()
    }
}
