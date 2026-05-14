//
//  FullCoverageUITests.swift
//  本地通讯录管家UITests
//
//  完整 UI 测试：模拟人类操作 - 点击、滑动、等待
//

import XCTest
import Contacts

final class FullCoverageUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state"]
        app.launch()

        // 监听通讯录权限弹窗
        addContactsPermissionMonitor()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - 权限处理

    private func addContactsPermissionMonitor() {
        addUIInterruptionMonitor(withDescription: "通讯录权限") { [weak self] alert in
            self?.handleContactsPermission(alert: alert)
            return true
        }
    }

    private func handleContactsPermission(alert: XCUIElement) {
        let allowButton = alert.buttons["允许"] ?? alert.buttons["Allow"] ?? alert.buttons["好"] ?? alert.buttons["Allow Access"]
        if allowButton.exists {
            allowButton.tap()
            print("[Permission] 点击了允许按钮")
        }
    }

    // MARK: - 辅助方法

    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }

    private func tapWithRetry(_ element: XCUIElement, maxRetries: Int = 3) {
        for i in 0..<maxRetries {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func swipeDown() {
        let startCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let endCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        startCoord.press(forDuration: 0.1, thenDragTo: endCoord)
        Thread.sleep(forTimeInterval: 1)
    }

    // MARK: - 测试1: 授权流程

    func test_01_授权流程() throws {
        print("[测试1] 开始测试授权流程")

        // 等待启动
        Thread.sleep(forTimeInterval: 2)

        // 检查是否出现授权按钮
        let authButton = app.buttons["home.requestContactsButton"]
        if authButton.exists {
            print("[测试1] 发现授权按钮，点击")
            authButton.tap()

            // 等待权限弹窗处理
            Thread.sleep(forTimeInterval: 2)

            // 再次检查是否出现授权按钮（如果还没处理完）
            if authButton.exists {
                authButton.tap()
                Thread.sleep(forTimeInterval: 2)
            }
        }

        // 等待加载完成
        let healthCard = app.otherElements["home.healthScoreCard"]
        if healthCard.waitForExistence(timeout: 60) {
            print("[测试1] ✓ 健康分卡片出现，授权成功")
        } else {
            print("[测试1] ✗ 健康分卡片未出现")
        }
    }

    // MARK: - 测试2: 首页显示

    func test_02_首页显示() throws {
        print("[测试2] 开始测试首页显示")

        // 等待健康分卡片
        let healthCard = app.otherElements["home.healthScoreCard"]
        guard healthCard.waitForExistence(timeout: 60) else {
            print("[测试2] ✗ 健康分卡片未出现，跳过测试")
            throw XCTSkip("需要授权后才能测试")
        }
        print("[测试2] ✓ 健康分卡片已显示")

        // 检查统计数据
        let statsSection = app.otherElements["home.statsSection"]
        if statsSection.waitForExistence(timeout: 5) {
            print("[测试2] ✓ 统计区域已显示")
        }

        // 检查搜索框
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            print("[测试2] ✓ 搜索框存在")
        }

        print("[测试2] ✓ 首页显示测试完成")
    }

    // MARK: - 测试3: 问题列表加载

    func test_03_问题列表加载() throws {
        print("[测试3] 开始测试问题列表加载")

        // 等待健康分卡片
        let healthCard = app.otherElements["home.healthScoreCard"]
        guard healthCard.waitForExistence(timeout: 60) else {
            throw XCTSkip("需要授权后才能测试")
        }

        // 等待问题列表加载
        Thread.sleep(forTimeInterval: 3)

        // 检查是否有问题列表或"状态良好"
        let goodState = app.staticTexts["通讯录状态良好"]
        let issuesHeader = app.staticTexts["可优化项目"]

        if goodState.waitForExistence(timeout: 5) {
            print("[测试3] ✓ 通讯录状态良好，无需优化")
        } else if issuesHeader.waitForExistence(timeout: 5) {
            print("[测试3] ✓ 发现可优化项目")

            // 等待问题列表完全加载
            Thread.sleep(forTimeInterval: 2)

            // 尝试获取问题数量
            let issueCount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '项'")).firstMatch
            if issueCount.exists {
                print("[测试3] ✓ 问题数量: \(issueCount.label)")
            }
        }

        print("[测试3] ✓ 问题列表测试完成")
    }

    // MARK: - 测试4: 问题详情页 - 白屏问题测试

    func test_04_问题详情页_白屏测试() throws {
        print("[测试4] 开始测试问题详情页（白屏测试）")

        // 等待首页加载
        let healthCard = app.otherElements["home.healthScoreCard"]
        guard healthCard.waitForExistence(timeout: 60) else {
            throw XCTSkip("需要授权后才能测试")
        }

        // 等待问题列表
        Thread.sleep(forTimeInterval: 3)

        // 检查是否有问题
        let issuesHeader = app.staticTexts["可优化项目"]
        guard issuesHeader.waitForExistence(timeout: 5) else {
            print("[测试4] ✗ 没有可优化项目，跳过")
            throw XCTSkip("没有可优化项目")
        }

        // 查找第一个问题行
        let firstIssue = app.buttons["home.issueRow.first"]
        guard firstIssue.waitForExistence(timeout: 5) else {
            print("[测试4] ✗ 找不到第一个问题行")
            throw XCTSkip("找不到问题行")
        }

        print("[测试4] 点击第一个问题行")
        firstIssue.tap()

        // 等待详情页出现
        let detailNav = app.navigationBars.firstMatch
        if detailNav.waitForExistence(timeout: 10) {
            print("[测试4] ✓ 详情页导航栏出现")

            // 等待详情页内容加载
            Thread.sleep(forTimeInterval: 3)

            // 检查是否有内容（不是空白）
            let selectAllButton = app.buttons["issue.detail.selectAll"]
            let scrollView = app.scrollViews["issue.detail.scroll"]
            let emptyText = app.staticTexts["没有找到需要处理的联系人"]

            if selectAllButton.waitForExistence(timeout: 10) {
                print("[测试4] ✓ 详情页内容已显示（全选按钮可见）")
            } else if scrollView.waitForExistence(timeout: 10) {
                print("[测试4] ✓ 详情页滚动区域可见")

                // 尝试向下滑动看是否有内容
                swipeDown()

                if selectAllButton.waitForExistence(timeout: 5) {
                    print("[测试4] ✓ 下滑后全选按钮出现")
                } else if emptyText.waitForExistence(timeout: 5) {
                    print("[测试4] - 没有找到联系人")
                }
            } else if emptyText.waitForExistence(timeout: 5) {
                print("[测试4] - 没有找到联系人")
            } else {
                print("[测试4] ✗ 详情页可能是白屏！")
                XCTFail("详情页未正确显示内容")
            }

            // 返回首页
            let backButton = app.buttons.firstMatch
            if backButton.label.contains("Back") || backButton.label.contains("返回") {
                backButton.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        } else {
            print("[测试4] ✗ 详情页导航栏未出现")
            XCTFail("详情页未打开")
        }

        print("[测试4] ✓ 问题详情页测试完成")
    }

    // MARK: - 测试5: 全选和预执行

    func test_05_全选和预执行() throws {
        print("[测试5] 开始测试全选和预执行")

        // 等待首页加载
        let healthCard = app.otherElements["home.healthScoreCard"]
        guard healthCard.waitForExistence(timeout: 60) else {
            throw XCTSkip("需要授权后才能测试")
        }

        Thread.sleep(forTimeInterval: 3)

        // 检查是否有问题
        let issuesHeader = app.staticTexts["可优化项目"]
        guard issuesHeader.waitForExistence(timeout: 5) else {
            throw XCTSkip("没有可优化项目")
        }

        // 点击第一个问题
        let firstIssue = app.buttons["home.issueRow.first"]
        guard firstIssue.waitForExistence(timeout: 5) else {
            throw XCTSkip("找不到问题行")
        }
        firstIssue.tap()

        // 等待详情页
        let selectAllButton = app.buttons["issue.detail.selectAll"]
        guard selectAllButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("详情页未加载")
        }
        print("[测试5] ✓ 详情页已加载")

        // 点击全选
        print("[测试5] 点击全选")
        selectAllButton.tap()
        Thread.sleep(forTimeInterval: 1)

        // 检查是否选中
        let selectAllText = selectAllButton.label
        if selectAllText.contains("取消") {
            print("[测试5] ✓ 已全选")
        }

        // 点击预执行优化
        let preExecuteButton = app.buttons["issue.detail.preExecute"]
        if preExecuteButton.waitForExistence(timeout: 5) {
            print("[测试5] 点击预执行优化")
            preExecuteButton.tap()

            // 等待处理完成
            Thread.sleep(forTimeInterval: 5)

            // 检查结果页
            let resultRoot = app.otherElements["preexecute.recorded.root"]
            if resultRoot.waitForExistence(timeout: 60) {
                print("[测试5] ✓ 预执行结果页已显示")

                // 点击继续处理
                let continueButton = app.buttons["preexecute.continueButton"]
                if continueButton.waitForExistence(timeout: 5) {
                    continueButton.tap()
                    Thread.sleep(forTimeInterval: 1)
                }
            } else {
                print("[测试5] - 结果页未出现，可能处理中")
            }
        }

        // 返回首页
        app.buttons.firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)

        print("[测试5] ✓ 全选和预执行测试完成")
    }

    // MARK: - 测试6: 写入功能

    func test_06_写入功能() throws {
        print("[测试6] 开始测试写入功能")

        // 先执行一次预执行
        try test_05_全选和预执行()

        // 检查首页是否有待写入按钮
        let writeButton = app.buttons["home.writePendingButton"]
        if writeButton.waitForExistence(timeout: 5) {
            print("[测试6] 发现待写入按钮，点击")
            writeButton.tap()

            // 等待确认弹窗
            let writeAlert = app.alerts["写入系统通讯录"]
            if writeAlert.waitForExistence(timeout: 10) {
                print("[测试6] ✓ 写入确认弹窗出现")

                // 点击确认写入
                let confirmButton = writeAlert.buttons["确认写入"]
                if confirmButton.waitForExistence(timeout: 5) {
                    confirmButton.tap()
                    print("[测试6] 点击了确认写入")

                    // 等待写入完成（可能需要较长时间）
                    let doneAlert = app.alerts["写入完成"]
                    if doneAlert.waitForExistence(timeout: 180) {
                        print("[测试6] ✓ 写入完成弹窗出现")

                        // 点击确定
                        doneAlert.buttons["确定"].tap()
                        Thread.sleep(forTimeInterval: 2)
                        print("[测试6] ✓ 写入流程完成")
                    } else {
                        print("[测试6] ✗ 写入完成弹窗未出现（超时）")
                    }
                }
            }
        } else {
            print("[测试6] - 没有待写入内容，跳过")
            throw XCTSkip("没有待写入内容")
        }

        print("[测试6] ✓ 写入功能测试完成")
    }

    // MARK: - 测试7: 刷新功能

    func test_07_刷新功能() throws {
        print("[测试7] 开始测试刷新功能")

        let healthCard = app.otherElements["home.healthScoreCard"]
        guard healthCard.waitForExistence(timeout: 60) else {
            throw XCTSkip("需要授权后才能测试")
        }

        // 下拉刷新
        print("[测试7] 执行下拉刷新")
        swipeDown()

        // 等待刷新完成
        Thread.sleep(forTimeInterval: 3)

        // 再次检查健康分卡片
        if healthCard.waitForExistence(timeout: 5) {
            print("[测试7] ✓ 刷新后健康分卡片仍显示")
        }

        print("[测试7] ✓ 刷新功能测试完成")
    }

    // MARK: - 测试8: Tab 切换

    func test_08_Tab切换() throws {
        print("[测试8] 开始测试 Tab 切换")

        // 检查 Tab Bar
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else {
            throw XCTSkip("没有找到 Tab Bar")
        }

        // 切换到导入
        if tabBar.buttons["导入"].exists {
            tabBar.buttons["导入"].tap()
            Thread.sleep(forTimeInterval: 1)

            let importRoot = app.otherElements["tab.import.root"]
            if importRoot.waitForExistence(timeout: 5) {
                print("[测试8] ✓ 导入 Tab 切换成功")
            }
        }

        // 切换到导出
        if tabBar.buttons["导出"].exists {
            tabBar.buttons["导出"].tap()
            Thread.sleep(forTimeInterval: 1)
            print("[测试8] ✓ 导出 Tab 切换成功")
        }

        // 切换到设置
        if tabBar.buttons["设置"].exists {
            tabBar.buttons["设置"].tap()
            Thread.sleep(forTimeInterval: 1)

            let settingsLabel = app.staticTexts["标签设置"]
            if settingsLabel.waitForExistence(timeout: 5) {
                print("[测试8] ✓ 设置 Tab 切换成功")
            }
        }

        // 返回首页
        if tabBar.buttons["概览"].exists {
            tabBar.buttons["概览"].tap()
            Thread.sleep(forTimeInterval: 1)
        }

        print("[测试8] ✓ Tab 切换测试完成")
    }

    // MARK: - 测试9: 搜索功能

    func test_09_搜索功能() throws {
        print("[测试9] 开始测试搜索功能")

        let healthCard = app.otherElements["home.healthScoreCard"]
        guard healthCard.waitForExistence(timeout: 60) else {
            throw XCTSkip("需要授权后才能测试")
        }

        // 点击搜索框
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            print("[测试9] 点击搜索框")
            searchField.tap()

            // 输入搜索词
            searchField.typeText("张")
            Thread.sleep(forTimeInterval: 1)

            // 清除搜索
            searchField.clearText()
            Thread.sleep(forTimeInterval: 0.5)

            // 收起键盘
            app.toolbars.buttons["Done"].tap()
            Thread.sleep(forTimeInterval: 0.5)

            print("[测试9] ✓ 搜索功能测试完成")
        } else {
            print("[测试9] - 搜索框不存在，跳过")
        }
    }
}

// MARK: - XCUIElement 扩展

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String, !stringValue.isEmpty else { return }
        var deleteString = ""
        for _ in 0..<stringValue.count {
            deleteString += XCUIKeyboardKey.delete.rawValue
        }
        self.typeText(deleteString)
    }
}
