import Testing

@testable import ai_os_mcp

@Test func testPressKeyRejectsUnknownKey() {
    let actions = AXActions()
    #expect(throws: (any Error).self) {
        try actions.pressKey(key: "unknownkey123", modifiers: [])
    }
}

@Test func testPressKeyRejectsUnknownModifier() {
    let actions = AXActions()
    #expect(throws: (any Error).self) {
        try actions.pressKey(key: "a", modifiers: ["superkey"])
    }
}

@Test func testPressKeyAcceptsNamedKeys() throws {
    // These should not throw (we can't verify they actually send events in tests
    // without accessibility permission, but the key mapping should succeed)
    let actions = AXActions()
    let namedKeys = [
        "return", "enter", "tab", "space", "delete",
        "escape", "esc", "left", "right", "up", "down",
        "f1", "f12", "home", "end", "pageup", "pagedown",
    ]
    for key in namedKeys {
        // Just verify these don't throw due to unknown key
        // (they may throw for other reasons like CGEvent creation in test env)
        do {
            try actions.pressKey(key: key, modifiers: [])
        } catch let error as AIOSError {
            // Only acceptable error is CGEvent creation failure, not "unknown key"
            if case .invalidArguments = error {
                #expect(Bool(false), "Key '\(key)' should be recognized but got: \(error)")
            }
        }
    }
}

@Test func testPressKeyAcceptsSingleCharacters() throws {
    let actions = AXActions()
    let chars = ["a", "z", "0", "9", ",", "."]
    for char in chars {
        do {
            try actions.pressKey(key: char, modifiers: [])
        } catch let error as AIOSError {
            if case .invalidArguments = error {
                #expect(Bool(false), "Character '\(char)' should be recognized but got: \(error)")
            }
        }
    }
}

@Test func testPressKeyAcceptsModifiers() throws {
    let actions = AXActions()
    let validModifiers = [
        ["command"], ["cmd"], ["shift"], ["option"], ["alt"],
        ["control"], ["ctrl"], ["command", "shift"],
    ]
    for mods in validModifiers {
        do {
            try actions.pressKey(key: "a", modifiers: mods)
        } catch let error as AIOSError {
            if case .invalidArguments = error {
                #expect(Bool(false), "Modifiers \(mods) should be valid but got: \(error)")
            }
        }
    }
}
