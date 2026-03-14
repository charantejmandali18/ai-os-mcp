import Foundation
import Testing

@testable import ai_os_mcp

@Test func testAXNodeSerializationSkipsNils() throws {
    let node = AXNode(
        role: "AXButton",
        title: "Play",
        actions: ["AXPress"],
        enabled: true
    )
    let json = try node.toJSON()
    #expect(json.contains("\"role\":\"AXButton\""))
    #expect(json.contains("\"title\":\"Play\""))
    // Nil fields should not appear in output
    #expect(!json.contains("\"identifier\""))
    #expect(!json.contains("\"position\""))
    #expect(!json.contains("\"selected\""))
}

@Test func testAXNodeWithChildren() throws {
    let child = AXNode(role: "AXStaticText", title: "Hello")
    var parent = AXNode(role: "AXGroup")
    parent.children = [child]

    let json = try parent.toJSON()
    #expect(json.contains("\"children\""))
    #expect(json.contains("AXStaticText"))
    #expect(json.contains("Hello"))
}

@Test func testAXNodeValueStringEncoding() throws {
    let val = AXNodeValue.string("hello")
    let encoder = JSONEncoder()
    let data = try encoder.encode(val)
    #expect(String(data: data, encoding: .utf8) == "\"hello\"")
}

@Test func testAXNodeValueNumberEncoding() throws {
    let val = AXNodeValue.number(42.0)
    let encoder = JSONEncoder()
    let data = try encoder.encode(val)
    #expect(String(data: data, encoding: .utf8) == "42")
}

@Test func testAXNodeValueBoolEncoding() throws {
    let val = AXNodeValue.bool(true)
    let encoder = JSONEncoder()
    let data = try encoder.encode(val)
    #expect(String(data: data, encoding: .utf8) == "true")
}

@Test func testAXNodeValueDecoding() throws {
    let decoder = JSONDecoder()

    let strData = "\"world\"".data(using: .utf8)!
    let strVal = try decoder.decode(AXNodeValue.self, from: strData)
    if case .string(let s) = strVal {
        #expect(s == "world")
    } else {
        #expect(Bool(false), "Expected string variant")
    }

    let numData = "99.5".data(using: .utf8)!
    let numVal = try decoder.decode(AXNodeValue.self, from: numData)
    if case .number(let n) = numVal {
        #expect(n == 99.5)
    } else {
        #expect(Bool(false), "Expected number variant")
    }
}

@Test func testAXNodeDescriptionCodingKey() throws {
    var node = AXNode(role: "AXButton")
    node.nodeDescription = "A play button"

    let json = try node.toJSON()
    // Should serialize as "description", not "nodeDescription"
    #expect(json.contains("\"description\":\"A play button\""))
    #expect(!json.contains("nodeDescription"))
}

@Test func testAppInfoEncoding() throws {
    let app = AppInfo(name: "Finder", pid: 123, bundleId: "com.apple.finder", isActive: true)
    let encoder = JSONEncoder()
    let data = try encoder.encode(app)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"name\":\"Finder\""))
    #expect(json.contains("\"pid\":123"))
    #expect(json.contains("\"bundleId\":\"com.apple.finder\""))
    #expect(json.contains("\"isActive\":true"))
}
