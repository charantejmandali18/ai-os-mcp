import Testing
@testable import ai_os_mcp

@Test func testParseMenuPath() {
    let segments = parseMenuPath("File > Export > PDF")
    #expect(segments == ["File", "Export", "PDF"])
}

@Test func testParseMenuPathSingleItem() {
    let segments = parseMenuPath("Edit")
    #expect(segments == ["Edit"])
}

@Test func testNormalizeMenuTitle() {
    #expect(normalizeMenuTitle("Save As...") == "save as")
    #expect(normalizeMenuTitle("Save As\u{2026}") == "save as")
    #expect(normalizeMenuTitle("  Open  ") == "open")
}

@Test func testMenuTitleMatches() {
    #expect(menuTitleMatches("Save As...", query: "Save As"))
    #expect(menuTitleMatches("save as\u{2026}", query: "Save As"))
    #expect(!menuTitleMatches("Save", query: "Save As"))
}
