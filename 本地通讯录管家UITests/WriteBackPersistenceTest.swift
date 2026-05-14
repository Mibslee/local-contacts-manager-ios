import XCTest

/// 专门测试写入持久化：写入后重新读取系统通讯录，验证数据是否真正改变
final class WriteBackPersistenceTest: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // 不使用 --reset-state，避免每次重建状态导致加载慢
        app.launch()

        addUIInterruptionMonitor(withDescription: "Contacts permission") { alert in
            let allowButton = alert.buttons["允许"] ?? alert.buttons["Allow"] ?? alert.buttons["好"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }
    }

    /// 测试：手机标签统一 → 写入 → 退出 App → 重新进入 → 验证问题减少
    func testPhoneLabelWriteBackPersistence() throws {
        func log(_ msg: String) {
            print("[Test] \(msg)")
        }

        log("步骤1: 等待首页加载")
        let healthCard = app.otherElements["home.healthScoreCard"]
        // 不等待健康卡，直接检查通讯录是否已加载
        // 等待任意一个可优化项出现，说明数据已加载
        let firstIssue = app.buttons["home.issueRow.first"]
        XCTAssert(firstIssue.waitForExistence(timeout: 120), "可优化项未出现（120秒超时，可能是通讯录加载慢）")
        log("首页已加载，问题列表已出现")

        log("步骤2: 读取初始问题数")
        let initialCount = extractIssueCount(for: "手机标签")
        log("初始手机标签问题数: \(initialCount)")

        log("步骤3: 进入手机标签详情页")
        let phoneLabelRow = app.buttons["home.issueRow.手机标签不统一"]
        XCTAssert(phoneLabelRow.waitForExistence(timeout: 5), "手机标签问题行不存在")
        phoneLabelRow.tap()
        sleep(3)

        log("步骤4: 全选联系人")
        let selectAll = app.buttons["issue.detail.selectAll"]
        XCTAssert(selectAll.waitForExistence(timeout: 5), "全选按钮不存在")
        selectAll.tap()
        sleep(1)

        log("步骤5: 点击预执行优化")
        let scrollView = app.scrollViews.firstMatch
        scrollView.swipeUp()
        scrollView.swipeUp()

        let preExecuteBtn = app.buttons["issue.detail.preExecute"]
        XCTAssert(preExecuteBtn.waitForExistence(timeout: 5), "预执行按钮不存在")
        preExecuteBtn.tap()
        log("已点击预执行")

        log("等待预执行结果...")
        let continueBtn = app.buttons["preexecute.continueButton"]

        var preExecuteDone = false
        for i in 0..<30 {
            if continueBtn.exists {
                preExecuteDone = true
                log("预执行完成！（耗时 \(i) 秒）")
                break
            }
            sleep(1)
        }
        XCTAssert(preExecuteDone, "预执行超时（30秒）")

        continueBtn.tap()
        sleep(3)

        log("步骤6: 滚动并点击写入按钮")
        for _ in 0..<5 {
            scrollView.swipeUp()
        }

        let writePendingBtn = app.buttons["home.writePendingButton"]
        log("等待待写入按钮出现...")
        if writePendingBtn.waitForExistence(timeout: 30) {
            log("找到待写入按钮！")
            writePendingBtn.tap()
        } else {
            log("待写入按钮未找到，检查页面元素...")
            printSnapshotInfo()
            XCTFail("写入按钮未找到")
        }

        log("等待写入确认弹窗...")
        let confirmBtn = app.alerts.buttons["确认写入"]
        if confirmBtn.waitForExistence(timeout: 10) {
            log("确认写入")
            confirmBtn.tap()
        } else {
            log("警告：未找到确认按钮，尝试其他按钮")
            app.alerts.buttons.allElementsBoundByIndex.first?.tap()
        }

        log("等待写入完成...")
        let doneAlert = app.alerts["写入完成"]
        XCTAssert(doneAlert.waitForExistence(timeout: 120), "写入完成弹窗未出现（120秒超时）")
        log("写入完成！")

        doneAlert.buttons["确定"].tap()
        sleep(2)

        log("步骤7: 重启 App 验证持久化")
        app.terminate()
        sleep(2)
        app.launch()

        XCTAssert(healthCard.waitForExistence(timeout: 60), "重启后健康卡片未出现")
        sleep(3)

        let finalCount = extractIssueCount(for: "手机标签")
        log("最终手机标签问题数: \(finalCount)")

        if finalCount < initialCount {
            log("✅ 写入持久化成功！问题数从 \(initialCount) 减少到 \(finalCount)")
        } else if finalCount == initialCount {
            log("❌ 写入持久化失败！问题数未改变")
            XCTFail("写入持久化失败：问题数未减少 (\(initialCount) → \(finalCount))")
        } else {
            log("❌ 问题数异常增加（\(initialCount) → \(finalCount)）")
            XCTFail("问题数异常增加")
        }
    }

    /// 从界面上提取特定类型问题的数量
    private func extractIssueCount(for keyword: String) -> Int {
        // 查找包含关键字的问题行
        let issueRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.issueRow.'"))
        for i in 0..<issueRows.count {
            let row = issueRows.element(boundBy: i)
            let label = row.label
            if label.contains(keyword) {
                // 从标签中提取数字，例如 "手机标签待统一 - 6人" → 6
                let numbers = label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let count = Int(numbers) {
                    return count
                }
            }
        }
        return -1
    }

    /// 打印当前界面的关键 accessibility 信息（用于调试）
    private func printSnapshotInfo() {
        let issueRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.issueRow.'"))
        print("[Debug] 发现 \(issueRows.count) 个问题行:")
        for i in 0..<min(issueRows.count, 10) {
            let row = issueRows.element(boundBy: i)
            print("[Debug]   行\(i): \(row.label) | \(row.identifier)")
        }
    }
}
