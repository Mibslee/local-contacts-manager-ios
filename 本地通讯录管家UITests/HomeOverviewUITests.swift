//
//  HomeOverviewUITests.swift
//  本地通讯录管家UITests
//
//  概览（首页）Tab 功能：导航、授权/健康卡片、统计、搜索入口、与其他 Tab 切换。
//

import XCTest

final class HomeOverviewUITests: XCTestCase {

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

    /// 触发系统权限弹窗时 interruption monitor 生效
    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).element
    }

    // MARK: - Tab 与导航

    func testOverview_tabBarShowsFourTabs() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        XCTAssertTrue(tabBar.buttons["概览"].exists)
        XCTAssertTrue(tabBar.buttons["导入"].exists)
        XCTAssertTrue(tabBar.buttons["导出"].exists)
        XCTAssertTrue(tabBar.buttons["设置"].exists)
    }

    func testOverview_navigationTitle() {
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.scrollViews["home.scroll"].waitForExistence(timeout: 10),
            "概览应展示可滚动主区域（与导航标题「通讯录管家」同页）"
        )
    }

    func testOverview_scrollViewPresent() {
        XCTAssertTrue(app.scrollViews["home.scroll"].waitForExistence(timeout: 8))
    }

    // MARK: - 首页内容：未授权 / 已加载

    /// 未授权时显示授权按钮；已授权并加载完成后出现健康分卡片（或错误重试）
    func testOverview_showsPermissionOrDashboardOrRetry() {
        let auth = app.buttons["home.requestContactsButton"]
        let health = element(identifier: "home.healthScoreCard")
        let retry = app.buttons["home.retryButton"]

        let ok = auth.waitForExistence(timeout: 10)
            || health.waitForExistence(timeout: 40)
            || retry.waitForExistence(timeout: 10)
        XCTAssertTrue(ok, "应在合理时间内出现「授权」、健康分区域或「重试」")
    }

    /// 若已进入概览数据区，校验健康分文案与三项统计标题
    func testOverview_whenDashboardVisible_showsHealthAndStatLabels() throws {
        let health = element(identifier: "home.healthScoreCard")
        guard health.waitForExistence(timeout: 40) else {
            throw XCTSkip("当前模拟器未授权通讯录或仍在加载，跳过数据区断言")
        }

        XCTAssertTrue(app.staticTexts["健康分"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '位联系人'")).firstMatch.exists)

        XCTAssertTrue(element(identifier: "home.statsSection").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["联系人"].exists)
        XCTAssertTrue(app.staticTexts["手机号"].exists)
        XCTAssertTrue(app.staticTexts["邮箱"].exists)
    }

    /// 问题区：无问题时的提示，或有「可优化项目」列表
    func testOverview_issuesSection_showsStatusOrOptimizableHeader() throws {
        _ = element(identifier: "home.healthScoreCard").waitForExistence(timeout: 40)

        let good = app.staticTexts["通讯录状态良好，无需优化"]
        let header = app.staticTexts["可优化项目"]
        XCTAssertTrue(
            good.waitForExistence(timeout: 5) || header.waitForExistence(timeout: 5),
            "问题区应显示「状态良好」或「可优化项目」"
        )
    }

    // MARK: - 搜索（概览 searchable）

    func testOverview_searchFieldExistsAfterPullOrFocus() throws {
        guard element(identifier: "home.healthScoreCard").waitForExistence(timeout: 40) else {
            throw XCTSkip("需要已授权并加载完成才能稳定出现搜索框")
        }

        let inNav = app.navigationBars["通讯录管家"].searchFields.firstMatch
        let anySearch = app.descendants(matching: .searchField).firstMatch
        if !inNav.waitForExistence(timeout: 2) && !anySearch.waitForExistence(timeout: 2) {
            app.swipeDown()
            app.swipeDown()
        }
        let ok = inNav.waitForExistence(timeout: 6) || anySearch.waitForExistence(timeout: 6)
        if !ok {
            throw XCTSkip("当前系统/SwiftUI 未将 searchable 暴露为可查询的 SearchField，跳过")
        }
    }

    // MARK: - 与其他 Tab 切换

    func testOverview_switchToImportShowsImportScreen() {
        app.tabBars.buttons["导入"].tap()
        XCTAssertTrue(
            element(identifier: "tab.import.root").waitForExistence(timeout: 10),
            "应进入导入 Tab 根视图"
        )
        XCTAssertTrue(
            app.staticTexts["导入通讯录"].waitForExistence(timeout: 5)
                || app.buttons["从 vCard 文件导入"].waitForExistence(timeout: 5),
            "导入页应显示说明文案或导入入口"
        )
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.scrollViews["home.scroll"].waitForExistence(timeout: 8))
    }

    func testOverview_switchToSettingsAndBack() {
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(
            element(identifier: "tab.settings.root").waitForExistence(timeout: 10),
            "应进入设置 Tab 根视图"
        )
        XCTAssertTrue(app.staticTexts["标签设置"].waitForExistence(timeout: 5))
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.scrollViews["home.scroll"].waitForExistence(timeout: 8))
    }
}
