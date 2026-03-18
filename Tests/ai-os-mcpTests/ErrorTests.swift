import Testing
@testable import ai_os_mcp

@Test func testScriptTimeoutDescription() {
    let error = AIOSError.scriptTimeout(seconds: 30)
    #expect(error.description.contains("30"))
    #expect(error.description.contains("timeout"))
}

@Test func testScriptErrorDescription() {
    let error = AIOSError.scriptError(message: "syntax error")
    #expect(error.description.contains("syntax error"))
}

@Test func testScriptBlockedDescription() {
    let error = AIOSError.scriptBlocked(reason: "do shell script")
    #expect(error.description.contains("do shell script"))
}

@Test func testMenuItemNotFoundDescription() {
    let error = AIOSError.menuItemNotFound(path: "File > Export", available: ["New", "Open", "Save"])
    #expect(error.description.contains("File > Export"))
    #expect(error.description.contains("New"))
}

@Test func testPasteboardEmptyDescription() {
    let error = AIOSError.pasteboardEmpty(format: "html")
    #expect(error.description.contains("html"))
}

@Test func testWindowManagementFailedDescription() {
    let error = AIOSError.windowManagementFailed(app: "Finder", action: "resize", detail: "no window")
    #expect(error.description.contains("Finder"))
    #expect(error.description.contains("resize"))
}

@Test func testInvalidURLDescription() {
    let error = AIOSError.invalidURL(url: "not-a-url")
    #expect(error.description.contains("not-a-url"))
}

@Test func testScreenshotFailedDescription() {
    let error = AIOSError.screenshotFailed(detail: "no window found")
    #expect(error.description.contains("no window found"))
}

@Test func testAppLaunchFailedDescription() {
    let error = AIOSError.appLaunchFailed(name: "FakeApp", detail: "not found")
    #expect(error.description.contains("FakeApp"))
}
