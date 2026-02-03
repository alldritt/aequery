import Testing
import Foundation
@testable import AEQueryLib

@Suite("AppleScriptFormatter")
struct AppleScriptFormatterTests {

    // MARK: - Helpers

    private func makeFormatter(style: AppleScriptFormatter.Style, dictionary: ScriptingDictionary? = nil) -> AppleScriptFormatter {
        AppleScriptFormatter(style: style, dictionary: dictionary, appName: "Finder")
    }

    private func makeDictionary() -> ScriptingDictionary {
        var dict = ScriptingDictionary()
        dict.addClass(ClassDef(
            name: "window",
            code: "cwin",
            pluralName: "windows",
            properties: [
                PropertyDef(name: "name", code: "pnam", type: "text"),
                PropertyDef(name: "index", code: "pidx", type: "integer"),
            ],
            elements: []
        ))
        dict.addClass(ClassDef(
            name: "document",
            code: "docu",
            pluralName: "documents",
            properties: [
                PropertyDef(name: "name", code: "pnam", type: "text"),
            ],
            elements: []
        ))
        return dict
    }

    // MARK: - Scalar tests

    @Test func testScalarString() {
        let f = makeFormatter(style: .terminology)
        let output = f.formatValue(.string("hello"))
        #expect(output == "\"hello\"")
    }

    @Test func testScalarStringWithQuotes() {
        let f = makeFormatter(style: .terminology)
        let output = f.formatValue(.string("he said \"hi\""))
        #expect(output == "\"he said \\\"hi\\\"\"")
    }

    @Test func testScalarInteger() {
        let f = makeFormatter(style: .terminology)
        let output = f.formatValue(.integer(42))
        #expect(output == "42")
    }

    @Test func testScalarBool() {
        let f = makeFormatter(style: .terminology)
        #expect(f.formatValue(.bool(true)) == "true")
        #expect(f.formatValue(.bool(false)) == "false")
    }

    @Test func testScalarNull() {
        let f = makeFormatter(style: .terminology)
        let output = f.formatValue(.null)
        #expect(output == "missing value")
    }

    @Test func testList() {
        let f = makeFormatter(style: .terminology)
        let output = f.formatValue(.list([.string("a"), .integer(1)]))
        #expect(output == "{\"a\", 1}")
    }

    // MARK: - Object specifier terminology tests

    @Test func testObjectSpecifierTerminology() {
        let dict = makeDictionary()
        let f = makeFormatter(style: .terminology, dictionary: dict)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(1), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("window 1"))
        #expect(output.contains("tell application \"Finder\""))
        #expect(output.contains("end tell"))
    }

    @Test func testObjectSpecifierChevron() {
        let f = makeFormatter(style: .chevron)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(1), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("\u{00AB}class cwin\u{00BB} 1"))
        #expect(output.contains("application \"Finder\""))
    }

    @Test func testNestedSpecifierTerminology() {
        let dict = makeDictionary()
        let f = makeFormatter(style: .terminology, dictionary: dict)
        let inner = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(1), from: .null
        )
        let outer = AEValue.objectSpecifier(
            want: "cwin", form: "prop", seld: .string("pnam"), from: inner
        )
        let output = f.format(outer)
        #expect(output.contains("name of window 1"))
    }

    @Test func testNestedSpecifierChevron() {
        let f = makeFormatter(style: .chevron)
        let inner = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(1), from: .null
        )
        let outer = AEValue.objectSpecifier(
            want: "cwin", form: "prop", seld: .string("pnam"), from: inner
        )
        let output = f.format(outer)
        #expect(output.contains("\u{00AB}property pnam\u{00BB} of \u{00AB}class cwin\u{00BB} 1"))
    }

    @Test func testEveryElementTerminology() {
        let dict = makeDictionary()
        let f = makeFormatter(style: .terminology, dictionary: dict)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .string("all "), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("every window"))
    }

    @Test func testEveryElementChevron() {
        let f = makeFormatter(style: .chevron)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .string("all "), from: .null
        )
        let output = f.format(value)
        #expect(output.contains("every \u{00AB}class cwin\u{00BB}"))
    }

    @Test func testPropertyTerminology() {
        let dict = makeDictionary()
        let f = makeFormatter(style: .terminology, dictionary: dict)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "prop", seld: .string("pnam"), from: .null
        )
        let output = f.formatSpecifier(value)
        #expect(output == "name")
    }

    @Test func testPropertyChevron() {
        let f = makeFormatter(style: .chevron)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "prop", seld: .string("pnam"), from: .null
        )
        let output = f.formatSpecifier(value)
        #expect(output == "\u{00AB}property pnam\u{00BB}")
    }

    @Test func testNameFormTerminology() {
        let dict = makeDictionary()
        let f = makeFormatter(style: .terminology, dictionary: dict)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "name", seld: .string("Desktop"), from: .null
        )
        let output = f.formatSpecifier(value)
        #expect(output == "window \"Desktop\"")
    }

    @Test func testNameFormChevron() {
        let f = makeFormatter(style: .chevron)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "name", seld: .string("Desktop"), from: .null
        )
        let output = f.formatSpecifier(value)
        #expect(output == "\u{00AB}class cwin\u{00BB} \"Desktop\"")
    }

    @Test func testIdFormTerminology() {
        let dict = makeDictionary()
        let f = makeFormatter(style: .terminology, dictionary: dict)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "ID  ", seld: .integer(42), from: .null
        )
        let output = f.formatSpecifier(value)
        #expect(output == "window id 42")
    }

    @Test func testLastElementTerminology() {
        let dict = makeDictionary()
        let f = makeFormatter(style: .terminology, dictionary: dict)
        let value = AEValue.objectSpecifier(
            want: "cwin", form: "indx", seld: .integer(-1), from: .null
        )
        let output = f.formatSpecifier(value)
        #expect(output == "last window")
    }
}
