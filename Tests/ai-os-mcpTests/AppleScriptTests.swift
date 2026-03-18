import Testing
@testable import ai_os_mcp

@Test func testBlocksDoShellScript() {
    #expect(isScriptBlocked("tell application \"Finder\" to do shell script \"ls\""))
    #expect(isScriptBlocked("do shell script \"rm -rf /\""))
}

@Test func testBlocksRunShellScript() {
    #expect(isScriptBlocked("run shell script \"echo hi\""))
}

@Test func testAllowsSafeScripts() {
    #expect(!isScriptBlocked("tell application \"Finder\" to get name of every file of desktop"))
    #expect(!isScriptBlocked("tell application \"Safari\" to get URL of current tab of front window"))
}
