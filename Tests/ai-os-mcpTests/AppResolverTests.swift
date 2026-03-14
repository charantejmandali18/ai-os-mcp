import Testing

@testable import ai_os_mcp

@Test func testListRunningAppsReturnsNonEmpty() {
    let resolver = AppResolver()
    let apps = resolver.listRunningApps()
    #expect(!apps.isEmpty, "Should have at least one running GUI app")

    // All apps should have valid PIDs
    for app in apps {
        #expect(app.pid > 0)
        #expect(!app.name.isEmpty)
    }
}

@Test func testFrontmostAppReturnsValue() {
    let resolver = AppResolver()
    let app = resolver.frontmostApp()
    #expect(app != nil, "Should have a frontmost app")
    if let app = app {
        #expect(app.isActive)
        #expect(app.pid > 0)
    }
}

@Test func testResolveFinderByName() throws {
    let resolver = AppResolver()
    // Finder is always running on macOS
    let (pid, name) = try resolver.resolve(appName: "Finder")
    #expect(pid > 0)
    #expect(name == "Finder")
}

@Test func testResolveCaseInsensitive() throws {
    let resolver = AppResolver()
    let (pid, _) = try resolver.resolve(appName: "finder")
    #expect(pid > 0)
}

@Test func testResolvePartialMatch() throws {
    let resolver = AppResolver()
    // "Find" should match "Finder"
    let (pid, name) = try resolver.resolve(appName: "Find")
    #expect(pid > 0)
    #expect(name == "Finder")
}

@Test func testResolveUnknownAppThrows() {
    let resolver = AppResolver()
    #expect(throws: (any Error).self) {
        try resolver.resolve(appName: "NonExistentApp12345XYZ")
    }
}
