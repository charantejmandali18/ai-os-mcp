import Testing
@testable import ai_os_mcp

@Test func testMouseClickAtCreatesEvent() {
    let actions = AXActions()
    // Should not throw for valid coordinates
    // (actual click may not work in test env without permissions)
    do {
        try actions.mouseClick(x: 100, y: 100, button: .left, clickType: .single)
    } catch let error as AIOSError {
        if case .invalidArguments = error {
            #expect(Bool(false), "Valid coordinates should not cause invalidArguments: \(error)")
        }
        // Other errors (permissions, etc.) are acceptable in test env
    } catch {
        // Non-AIOSError errors are acceptable in test env
    }
}

@Test func testScrollDirectionValidation() {
    let actions = AXActions()
    let validDirections = ["up", "down", "left", "right"]
    for dir in validDirections {
        do {
            try actions.scroll(direction: dir, amount: 3, atX: 100, atY: 100)
        } catch let error as AIOSError {
            if case .invalidArguments = error {
                #expect(Bool(false), "Direction '\(dir)' should be valid: \(error)")
            }
        } catch {
            // Non-AIOSError errors are acceptable in test env
        }
    }
}

@Test func testScrollRejectsInvalidDirection() {
    let actions = AXActions()
    #expect(throws: (any Error).self) {
        try actions.scroll(direction: "diagonal", amount: 3, atX: 100, atY: 100)
    }
}

@Test func testMouseDragValidCoordinates() {
    let actions = AXActions()
    do {
        try actions.mouseDrag(fromX: 100, fromY: 100, toX: 200, toY: 200, duration: 0.1)
    } catch let error as AIOSError {
        if case .invalidArguments = error {
            #expect(Bool(false), "Valid coordinates should not cause invalidArguments: \(error)")
        }
    } catch {
        // Non-AIOSError errors are acceptable in test env
    }
}
