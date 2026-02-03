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

    // MARK: - Flatten tests

    @Test func testFlattenNestedLists() {
        let value = AEValue.list([
            .list([.string("a"), .string("b")]),
            .list([]),
            .list([.string("c")])
        ])
        let flat = value.flattened()
        #expect(flat == .list([.string("a"), .string("b"), .string("c")]))
    }

    @Test func testFlattenEmptyLists() {
        let value = AEValue.list([
            .list([]),
            .list([]),
            .list([])
        ])
        let flat = value.flattened()
        #expect(flat == .list([]))
    }

    @Test func testFlattenDeeplyNested() {
        let value = AEValue.list([
            .list([.list([.string("deep")])]),
            .string("shallow")
        ])
        let flat = value.flattened()
        #expect(flat == .list([.string("deep"), .string("shallow")]))
    }

    @Test func testFlattenNonList() {
        let value = AEValue.string("hello")
        let flat = value.flattened()
        #expect(flat == .string("hello"))
    }

    // MARK: - Object specifier JSON/text tests

    @Test func testJsonObjectSpecifier() {
        let f = OutputFormatter(format: .json)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(1), from: .null
        )
        let output = f.format(value)
        // Without a dictionary, uses raw code as class name
        #expect(output.contains("/cwin[1]"))
    }

    @Test func testTextObjectSpecifier() {
        let f = OutputFormatter(format: .text)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(1), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("/cwin[1]"))
    }

    @Test func testJsonObjectSpecifierWithDictionary() {
        var dict = ScriptingDictionary()
        dict.addClass(ClassDef(name: "window", code: "cwin", pluralName: "windows"))
        let f = OutputFormatter(format: .json, dictionary: dict, appName: "Finder")
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(1), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("/Finder/windows[1]"))
    }

    @Test func testJsonObjectSpecifierByID() {
        let f = OutputFormatter(format: .json, appName: "Contacts")
        let value = AEValue.objectSpecifier(
            want: "azf4", form: "ID  ", seld: .string("ABC-123"), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("/Contacts/azf4[#id=\\\"ABC-123\\\"]"))
    }

    @Test func testJsonObjectSpecifierByName() {
        var dict = ScriptingDictionary()
        dict.addClass(ClassDef(name: "window", code: "cwin", pluralName: "windows"))
        let f = OutputFormatter(format: .json, dictionary: dict, appName: "Finder")
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "name", seld: .string("Desktop"), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("/Finder/windows[@name=\\\"Desktop\\\"]"))
    }
}
