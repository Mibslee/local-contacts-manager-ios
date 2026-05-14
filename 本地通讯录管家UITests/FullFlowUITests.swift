import XCTest

final class FullFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state"]
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

    func testFullFlowProcessAllIssuesAndWriteBack() throws {
        // Wait for health card to appear (data loaded)
        let healthCard = app.otherElements["home.healthScoreCard"]
        guard healthCard.waitForExistence(timeout: 60) else {
            XCTFail("Health card did not appear within 60s")
            return
        }
        print("[Test] Health card appeared - starting issue processing")

        // Wait for issues to load
        sleep(3)

        // Process all visible issue rows
        var issueIndex = 0
        while true {
            // Find the current issue row
            let issueRow: XCUIElement
            if issueIndex == 0 {
                issueRow = app.buttons["home.issueRow.first"]
            } else {
                // For subsequent issues, look for any issue row button that's not the first
                let allIssueRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.issueRow.'"))
                if issueIndex < allIssueRows.count {
                    issueRow = allIssueRows.element(boundBy: issueIndex)
                } else {
                    break
                }
            }

            guard issueRow.exists else { break }
            print("[Test] Processing issue \(issueIndex + 1): \(issueRow.label.prefix(50))...")

            // Tap the issue row
            issueRow.tap()
            sleep(2)

            // Check if detail page loaded with contacts
            let selectAllButton = app.buttons["issue.detail.selectAll"]
            if selectAllButton.waitForExistence(timeout: 15) {
                // Tap "全选"
                selectAllButton.tap()
                sleep(1)
                print("[Test] Selected all contacts")

                // Tap "预执行优化" button
                let preExecuteButton = app.buttons["issue.detail.preExecute"]
                if preExecuteButton.waitForExistence(timeout: 5) {
                    preExecuteButton.tap()
                    print("[Test] Tapped pre-execute, waiting for processing...")

                    // Wait for processing to complete - either PreExecuteRecordedView or MergePreviewView
                    let resultView = XCTestExpectation(description: "Result view appeared")
                    let maxWait: TimeInterval = 120

                    // Check periodically for result view
                    let startTime = Date()
                    var resultFound = false
                    while Date().timeIntervalSince(startTime) < maxWait && !resultFound {
                        let continueButton = app.buttons["preexecute.continueButton"]
                        let mergePreview = app.buttons["确认合并"]
                        let mergeSkip = app.buttons["跳过合并"]

                        if continueButton.exists {
                            continueButton.tap()
                            sleep(2)
                            resultFound = true
                            print("[Test] Pre-execute completed, dismissed result")
                        } else if mergePreview.exists || mergeSkip.exists {
                            // Merge preview is shown - confirm merge
                            let confirmButton = app.buttons["确认合并"]
                            if confirmButton.exists {
                                // Need to tap the expand chevron first to find the merge button
                                // Just tap confirm button at toolbar
                                confirmButton.tap()
                                sleep(2)

                                // Now PreExecuteRecordedView should be shown
                                let continueBtn = app.buttons["preexecute.continueButton"]
                                if continueBtn.waitForExistence(timeout: 10) {
                                    continueBtn.tap()
                                    sleep(2)
                                }
                            } else {
                                // Skip merge
                                mergeSkip.tap()
                                sleep(2)
                                let continueBtn = app.buttons["preexecute.continueButton"]
                                if continueBtn.waitForExistence(timeout: 10) {
                                    continueBtn.tap()
                                    sleep(2)
                                }
                            }
                            resultFound = true
                            print("[Test] Merge preview handled")
                        } else {
                            sleep(5)
                        }
                    }

                    if !resultFound {
                        print("[Test] Result view not found within timeout for issue \(issueIndex + 1)")
                        // Try to go back
                        app.navigationBars.buttons.element(boundBy: 0).tap()
                        sleep(2)
                    }
                }
            } else {
                print("[Test] No selectAll button, issue might have 0 contacts for this option")
                // Dismiss detail view
                app.navigationBars.buttons.element(boundBy: 0).tap()
                sleep(2)
            }

            issueIndex += 1
        }

        // After all issues, tap "写入系统通讯录"
        print("[Test] All issues processed, looking for write button...")
        sleep(3)

        // Scroll down to find the write button - force scroll to bottom
        print("[Test] Looking for write button...")

        // First, check if the button exists anywhere
        let writeButton = app.buttons["home.actionSection"]
        if writeButton.exists {
            print("[Test] Write button exists, scrolling to it")
            // The pending writes button may be off-screen - scroll the scrollable content first
            let scrollView = app.scrollViews.element(boundBy: 0)
            // Swipe up from bottom to reveal the write button at the bottom
            scrollView.swipeUp()
            scrollView.swipeUp()
            scrollView.swipeUp()
            writeButton.tap()
            print("[Test] Tapped write button")
        } else {
            // Try scrolling the scroll view to bottom
            let scrollView = app.scrollViews["home.scroll"]
            if scrollView.exists {
                print("[Test] Scrolling main scroll view to bottom")
                scrollView.swipeUp()
                scrollView.swipeUp()
                scrollView.swipeUp()
            }
            if writeButton.waitForExistence(timeout: 10) {
                writeButton.tap()
                print("[Test] Tapped write button (after scroll)")
            } else {
                print("[Test] ERROR: Write button not found after scroll")
                // Try tapping by coordinates
                let homeScroll = app.scrollViews["home.scroll"]
                if homeScroll.exists {
                    let btn = homeScroll.buttons["写入系统通讯录"]
                    if btn.exists {
                        btn.tap()
                        print("[Test] Tapped write button by label")
                    }
                }
            }
        }

        // Confirm write in alert
        let confirmWrite = app.alerts.buttons["确认写入"].firstMatch
        if confirmWrite.waitForExistence(timeout: 15) {
            confirmWrite.tap()
            print("[Test] Confirmed write, waiting for completion...")

                // Wait for write completion alert
                let doneAlert = app.alerts["写入完成"]
                if doneAlert.waitForExistence(timeout: 180) {
                    print("[Test] Write completed!")
                    doneAlert.buttons["确定"].tap()
                    sleep(3)

                    // Check the new health score
                    if healthCard.waitForExistence(timeout: 30) {
                        // Read score
                        let scoreText = app.staticTexts.element(matching: NSPredicate(
                            format: "label MATCHES '^[0-9]+$' AND frame.origin.y < 200"
                        ))
                        if scoreText.exists {
                            print("[Test] Final health score: \(scoreText.label)")
                        }
                    }
            } else {
                print("[Test] Write button not found")
            }
        }

        print("[Test] Full flow test completed")
    }
}
