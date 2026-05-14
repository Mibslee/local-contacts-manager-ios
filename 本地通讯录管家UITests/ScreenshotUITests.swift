//
//  ScreenshotUITests.swift
//  本地通讯录管家UITests
//
//  End-to-end screenshot test
//

import XCTest
import Contacts

final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!
    private static var screenshotsDir: URL = URL(fileURLWithPath: "/tmp/E2EScreenshots")

    override class func setUp() {
        super.setUp()
        let dir = URL(fileURLWithPath: "/tmp/E2EScreenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Self.screenshotsDir = dir
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--reset-on-next-launch"]

        // Monitor for permission dialogs
        addUIInterruptionMonitor(withDescription: "ContactsAuth") { alert in
            for title in ["好", "Allow", "允许", "OK", "允许访问"] {
                let btn = alert.buttons[title]
                if btn.exists {
                    btn.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        Thread.sleep(forTimeInterval: 2)

        // Request contacts if needed
        if app.buttons["home.requestContactsButton"].firstMatch.exists {
            app.buttons["home.requestContactsButton"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 4)
        }

        // Wait for health card
        _ = app.descendants(matching: .any).matching(identifier: "home.healthScoreCard").firstMatch.waitForExistence(timeout: 90)

        // Add test contacts
        try? addTestContacts()

        // Refresh
        app.swipeDown()
        Thread.sleep(forTimeInterval: 3)
    }

    private func addTestContacts() throws {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            NSLog("[Setup] Contacts not authorized: \(status.rawValue)")
            return
        }

        let fetchReq = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        try store.enumerateContacts(with: fetchReq) { contact, _ in
            if let mutable = contact.mutableCopy() as? CNMutableContact {
                let delReq = CNSaveRequest()
                delReq.delete(mutable)
                try? store.execute(delReq)
            }
        }

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
            req.add( contact, toContainerWithIdentifier: nil)
            try store.execute(req)
        }
    }

    override func tearDown() {
        if let files = try? FileManager.default.contentsOfDirectory(at: Self.screenshotsDir, includingPropertiesForKeys: nil) {
            NSLog("=== Screenshots: \(files.count) ===")
            files.forEach { NSLog("  \($0.lastPathComponent)") }
        }
        app = nil
    }

    private func takeScreenshot(named name: String) {
        let count = (try? FileManager.default.contentsOfDirectory(atPath: Self.screenshotsDir.path).count) ?? 0
        let filename = String(format: "%02d_%@.png", count, name)
        let destURL = Self.screenshotsDir.appendingPathComponent(filename)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
        let data = screenshot.pngRepresentation
        try? data.write(to: destURL)
        NSLog("[Screenshot] \(filename)")
    }

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testEndToEnd() throws {
        // Step 1: Home page
        NSLog("STEP 1: Home page")
        takeScreenshot(named: "01_home")

        // Step 2: Tap first issue row
        NSLog("STEP 2: Tap first issue row")
        let firstRow = el("home.issueRow.first")
        if firstRow.waitForExistence(timeout: 8) {
            firstRow.tap()
        } else {
            app.staticTexts["姓名需标准化"].firstMatch.tap()
        }

        // Step 3: Wait 5s, screenshot detail
        NSLog("STEP 3: Wait 5s for detail")
        Thread.sleep(forTimeInterval: 5)
        takeScreenshot(named: "03_issue_detail")

        // Step 4: Tap select all
        NSLog("STEP 4: Tap 全选")
        let selectAll = el("issue.detail.selectAll")
        if selectAll.waitForExistence(timeout: 5) {
            selectAll.tap()
        } else {
            app.buttons["全选"].firstMatch.tap()
        }

        // Step 5: Wait 1s
        NSLog("STEP 5: Wait 1s")
        Thread.sleep(forTimeInterval: 1)
        takeScreenshot(named: "05_after_select_all")

        // Step 6: Tap pre-execute
        NSLog("STEP 6: Tap 预执行优化")
        takeScreenshot(named: "06_before_preexecute")
        let preExec = el("issue.detail.preExecute")
        if preExec.waitForExistence(timeout: 10) {
            preExec.tap()
        } else {
            app.buttons["预执行优化"].firstMatch.tap()
        }

        // Step 7: Wait for pre-execution to complete
        NSLog("STEP 7: Waiting for pre-execute to complete")
        // Wait for "正在处理" to appear
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正在处理")).firstMatch.waitForExistence(timeout: 30)
        // Wait for result view (can take up to 2 minutes for large datasets)
        let resultView = el("preexecute.recorded.root")
        if resultView.waitForExistence(timeout: 180) {
            NSLog("STEP 7: Pre-execute completed, result view appeared")
        } else {
            NSLog("STEP 7: Pre-execute result view not found within timeout")
        }
        takeScreenshot(named: "07_pre_execute_result")
        takeScreenshot(named: "07_pre_execute_result")

        // Step 8: Dismiss pre-execute result
        NSLog("STEP 8: Dismiss pre-execute result")
        let continueBtn = el("preexecute.continueButton")
        if continueBtn.waitForExistence(timeout: 10) {
            continueBtn.tap()
            NSLog("STEP 8: Tapped continueButton")
        } else {
            let dismissBtn = el("preexecute.dismissButton")
            if dismissBtn.waitForExistence(timeout: 5) {
                dismissBtn.tap()
                NSLog("STEP 8: Tapped dismissButton")
            } else {
                // Try tapping by text
                app.buttons["继续处理其他问题"].firstMatch.tap()
                NSLog("STEP 8: Tapped by text")
            }
        }

        Thread.sleep(forTimeInterval: 1)
        takeScreenshot(named: "08_after_dismiss_preexecute")

        // Step 9: Tap write to system (pending write button)
        NSLog("STEP 9: Tap write button")
        let writePending = el("home.writePendingButton")
        if writePending.waitForExistence(timeout: 5) {
            writePending.tap()
        } else {
            let writeNormal = el("home.writeToSystemButton")
            if writeNormal.waitForExistence(timeout: 3) {
                writeNormal.tap()
            } else {
                app.buttons["确认写入"].firstMatch.tap()
            }
        }

        // Step 10: Wait for confirm alert
        Thread.sleep(forTimeInterval: 1)
        takeScreenshot(named: "10_write_confirm_alert")

        // Step 10b: Confirm write
        NSLog("STEP 10b: Tap 确认写入")
        let confirmAlert = app.alerts["写入系统通讯录"]
        if confirmAlert.waitForExistence(timeout: 5) {
            confirmAlert.buttons["确认写入"].tap()
        } else {
            app.buttons["确认写入"].firstMatch.tap()
        }

        // Step 11: Wait 5s
        NSLog("STEP 11: Wait 5s for write")
        Thread.sleep(forTimeInterval: 5)
        takeScreenshot(named: "11_write_result")

        // Step 12: Check for completion
        NSLog("STEP 12: Check completion")
        let doneAlert = app.alerts["写入完成"]
        if doneAlert.waitForExistence(timeout: 5) {
            takeScreenshot(named: "12_write_complete_alert")
            NSLog("Write completed successfully!")
            // Dismiss the alert
            doneAlert.buttons["确定"].tap()
        } else {
            NSLog("Write result alert not found - checking current state")
            takeScreenshot(named: "12_write_result_final")
        }

        NSLog("=== TEST COMPLETE ===")
    }
}
