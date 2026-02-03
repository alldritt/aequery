import Testing
import Foundation
@testable import AEQueryLib

@Suite("OutputFormatter")
struct OutputFormatterTests {
    @Test func testJsonScalar() {
        let f = OutputFormatter(format: .json)
        let output = f.format(.string("hello"))
        #expect(output.contains("hello"))
    }

    @Test func testJsonList() {
        let f = OutputFormatter(format: .json)
        let output = f.format(.list([.string("a"), .string("b")]))
        #expect(output.contains("a"))
        #expect(output.contains("b"))
        // Should be valid JSON
        let data = output.data(using: .utf8)!
        let json = try? JSONSerialization.jsonObject(with: data)
        #expect(json != nil)
    }

    @Test func testJsonRecord() {
        let f = OutputFormatter(format: .json)
        let output = f.format(.record([("name", .string("x"))]))
        #expect(output.contains("name"))
        #expect(output.contains("x"))
        let data = output.data(using: .utf8)!
        let json = try? JSONSerialization.jsonObject(with: data)
        #expect(json != nil)
    }

    @Test func testTextScalar() {
        let f = OutputFormatter(format: .text)
        let output = f.format(.string("hello"))
        #expect(output == "hello")
    }

    @Test func testTextList() {
        let f = OutputFormatter(format: .text)
        let output = f.format(.list([.string("a"), .string("b")]))
        #expect(output == "a\nb")
    }

    @Test func testTextInteger() {
        let f = OutputFormatter(format: .text)
        let output = f.format(.integer(42))
        #expect(output == "42")
    }

    @Test func testJsonInteger() {
        let f = OutputFormatter(format: .json)
        let output = f.format(.integer(42))
        #expect(output == "42")
    }

    @Test func testJsonBool() {
        let f = OutputFormatter(format: .json)
        let output = f.format(.bool(true))
        #expect(output == "true")
    }

    @Test func testTextBool() {
        let f = OutputFormatter(format: .text)
        let output = f.format(.bool(false))
        #expect(output == "false")
    }

    @Test func testJsonNull() {
        let f = OutputFormatter(format: .json)
        let output = f.format(.null)
        #expect(output == "null")
    }

    @Test func testTextNull() {
        let f = OutputFormatter(format: .text)
        let output = f.format(.null)
        #expect(output == "")
    }
}
