import AppKit
import Testing
@testable import ai_os_mcp

@Suite(.serialized)
struct PasteboardTests {
    @Test func testWriteAndReadPasteboard() throws {
        // Write to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("test-ai-os-mcp", forType: .string)

        // Read it back
        let result = try readPasteboardContent(format: "text")
        #expect(result == "test-ai-os-mcp")
    }

    @Test func testReadPasteboardEmptyFormat() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)

        // HTML should not be available
        #expect(throws: (any Error).self) {
            try readPasteboardContent(format: "html")
        }
    }

    @Test func testWritePasteboardText() throws {
        writePasteboardContent(content: "write-test-123", format: "text")
        let pasteboard = NSPasteboard.general
        #expect(pasteboard.string(forType: .string) == "write-test-123")
    }
}
