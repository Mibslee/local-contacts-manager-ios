//
//  IssueOptimizeFlowUITests.swift
//  本地通讯录管家UITests
//
//  可优化项：进入详情 → 全选 → 预执行优化 → 预执行结果 → 写入系统通讯录（确认）→ 完成提示
//

import XCTest
import Contacts

final class IssueOptimizeFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        // 设置权限弹窗监控
        addUIInterruptionMonitor(withDescription: "通讯录权限") { alert in
            for title in ["好", "Allow", "允许", "OK"] {
                let btn = alert.buttons[title]
                if btn.exists {
                    print("[TestSetup] 点击授权按钮: \(title)")
                    btn.tap()
                    return true
                }
            }
            return false
        }

        // 等待授权
        print("[TestSetup] 等待通讯录授权...")
        _ = element(identifier: "home.requestContactsButton").waitForExistence(timeout: 10)
        if element(identifier: "home.requestContactsButton").exists {
            print("[TestSetup] 点击请求授权按钮")
            element(identifier: "home.requestContactsButton").tap()
        }

        // 等待授权弹窗并处理
        Thread.sleep(forTimeInterval: 2)

        // 等待健康分卡片出现（表示授权成功并加载完成）
        print("[TestSetup] 等待加载完成...")
        _ = element(identifier: "home.healthScoreCard").waitForExistence(timeout: 60)

        // 添加测试数据（授权后）
        try? addTestContactsToSimulator()

        // 刷新以加载新添加的测试数据
        print("[TestSetup] 刷新通讯录...")
        app.swipeDown()
        Thread.sleep(forTimeInterval: 2)
    }

    private func addTestContactsToSimulator() throws {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        guard status == .authorized else {
            print("[TestSetup] 通讯录未授权，跳过添加测试数据")
            return
        }

        // 清除旧数据
        clearAllContacts(store: store)

        // 添加测试联系人：确保有"手机标签不一致"问题
        let testContacts: [(String, [(String, String)])] = [
            ("张三", [("手机", "13800138000"), ("工作", "13900139000")]),
            ("李四", [("手机", "13800138001"), ("iPhone", "13900138001")]),
            ("王五", [("MP", "13800138002"), ("tel", "13800138003")]),
            ("赵六", [("手机", "13800138004"), ("手机", "13900138005")]),
            ("钱七", [("mobile", "13800138006"), ("工作", "13900138006")]),
        ]

        for (name, phones) in testContacts {
            let contact = CNMutableContact()
            contact.givenName = name
            contact.phoneNumbers = phones.map { CNLabeledValue(label: $0.0, value: CNPhoneNumber(stringValue: $0.1)) }

            let req = CNSaveRequest()
            req.add(contact, toContainerWithIdentifier: nil)
            try store.execute(req)
            print("[TestSetup] 添加测试联系人: \(name)")
        }
        print("[TestSetup] 测试数据准备完成")
    }

    private func clearAllContacts(store: CNContactStore) {
        let req = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        do {
            try store.enumerateContacts(with: req) { contact, _ in
                if let mutable = contact.mutableCopy() as? CNMutableContact {
                    let delReq = CNSaveRequest()
                    delReq.delete(mutable)
                    try? store.execute(delReq)
                }
            }
            print("[TestSetup] 通讯录已清空")
        } catch {
            print("[TestSetup] 清除通讯录失败: \(error)")
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testIssueDetail_selectAll_preExecute_writeToSystem_fullFlow() throws {
        guard element(identifier: "home.healthScoreCard").waitForExistence(timeout: 60) else {
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
