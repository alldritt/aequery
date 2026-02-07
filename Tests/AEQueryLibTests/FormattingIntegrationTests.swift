import Testing
import Foundation
@testable import AEQueryLib

/// Integration tests that build real Apple Event descriptors, decode them,
/// and verify all three output formats (JSON/XPath, AppleScript terminology, chevron).
@Suite("FormattingIntegration")
struct FormattingIntegrationTests {

    // MARK: - Helpers

    private let decoder = DescriptorDecoder()

    /// Build a complete SDEF dictionary used across tests.
    private func makeDictionary() -> ScriptingDictionary {
        var dict = ScriptingDictionary()
        dict.addClass(ClassDef(
            name: "application",
            code: "capp",
            properties: [
                PropertyDef(name: "name", code: "pnam", type: "text"),
                PropertyDef(name: "frontmost", code: "pisf", type: "boolean"),
                PropertyDef(name: "version", code: "vers", type: "text"),
                PropertyDef(name: "selection", code: "sele", type: "text"),
            ],
            elements: [
                ElementDef(type: "window"),
                ElementDef(type: "document"),
            ]
        ))
        dict.addClass(ClassDef(
            name: "window",
            code: "cwin",
            pluralName: "windows",
            properties: [
                PropertyDef(name: "name", code: "pnam", type: "text"),
                PropertyDef(name: "index", code: "pidx", type: "integer"),
                PropertyDef(name: "bounds", code: "pbnd", type: "rectangle"),
                PropertyDef(name: "closeable", code: "hclb", type: "boolean"),
                PropertyDef(name: "miniaturized", code: "pmnd", type: "boolean"),
            ],
            elements: []
        ))
        dict.addClass(ClassDef(
            name: "document",
            code: "docu",
            pluralName: "documents",
            properties: [
                PropertyDef(name: "name", code: "pnam", type: "text"),
                PropertyDef(name: "modified", code: "imod", type: "boolean"),
                PropertyDef(name: "file", code: "file", type: "file"),
                PropertyDef(name: "encoding", code: "sDen", type: "encoding options"),
            ],
            elements: []
        ))
        dict.addClass(ClassDef(
            name: "text document",
            code: "TxtD",
            pluralName: "text documents",
            inherits: "document",
            properties: [
                PropertyDef(name: "source language", code: "SrLn", type: "text"),
            ],
            elements: []
        ))
        // Enum for encoding options
        dict.enumerations["encoding options"] = EnumDef(
            name: "encoding options",
            code: "eDen",
            enumerators: [
                Enumerator(name: "UTF-8", code: "utf8"),
                Enumerator(name: "MacRoman", code: "macR"),
            ]
        )
        return dict
    }

    private func jsonFormatter(dictionary: ScriptingDictionary? = nil, appName: String = "TestApp") -> OutputFormatter {
        OutputFormatter(format: .json, dictionary: dictionary, appName: appName)
    }

    private func textFormatter(dictionary: ScriptingDictionary? = nil, appName: String = "TestApp") -> OutputFormatter {
        OutputFormatter(format: .text, dictionary: dictionary, appName: appName)
    }

    private func terminologyFormatter(dictionary: ScriptingDictionary? = nil, appName: String = "TestApp") -> AppleScriptFormatter {
        AppleScriptFormatter(style: .terminology, dictionary: dictionary, appName: appName)
    }

    private func chevronFormatter(dictionary: ScriptingDictionary? = nil, appName: String = "TestApp") -> AppleScriptFormatter {
        AppleScriptFormatter(style: .chevron, dictionary: dictionary, appName: appName)
    }

    /// Build an object specifier NSAppleEventDescriptor.
    private func buildObjSpec(want: String, form: String, seld: NSAppleEventDescriptor, from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record()
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: FourCharCode(want)), forKeyword: FourCharCode("want"))
        spec.setDescriptor(from, forKeyword: FourCharCode("from"))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: FourCharCode(form)), forKeyword: FourCharCode("form"))
        spec.setDescriptor(seld, forKeyword: FourCharCode("seld"))
        return spec.coerce(toDescriptorType: FourCharCode("obj "))!
    }

    /// Build a property specifier descriptor.
    private func buildPropSpec(propCode: String, from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        buildObjSpec(want: "prop", form: "prop", seld: NSAppleEventDescriptor(typeCode: FourCharCode(propCode)), from: from)
    }

    /// Build a "by index" element specifier.
    private func buildIndexSpec(want: String, index: Int32, from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        buildObjSpec(want: want, form: "indx", seld: NSAppleEventDescriptor(int32: index), from: from)
    }

    /// Build a "by name" element specifier.
    private func buildNameSpec(want: String, name: String, from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        buildObjSpec(want: want, form: "name", seld: NSAppleEventDescriptor(string: name), from: from)
    }

    /// Build a "by ID" element specifier.
    private func buildIDSpec(want: String, id: NSAppleEventDescriptor, from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        buildObjSpec(want: want, form: "ID  ", seld: id, from: from)
    }

    /// Build an "every element" specifier.
    private func buildEverySpec(want: String, from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        var allCode = FourCharCode("all ")
        let allData = Data(bytes: &allCode, count: 4)
        let allDesc = NSAppleEventDescriptor(descriptorType: FourCharCode("abso"), data: allData)!
        return buildObjSpec(want: want, form: "indx", seld: allDesc, from: from)
    }

    /// Build a "last" element specifier.
    private func buildLastSpec(want: String, from: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        var lastCode = FourCharCode("last")
        let lastData = Data(bytes: &lastCode, count: 4)
        let lastDesc = NSAppleEventDescriptor(descriptorType: FourCharCode("abso"), data: lastData)!
        return buildObjSpec(want: want, form: "indx", seld: lastDesc, from: from)
    }

    /// Build a file URL descriptor.
    private func buildFileURL(_ path: String) -> NSAppleEventDescriptor {
        let urlString = URL(fileURLWithPath: path).absoluteString
        let data = urlString.data(using: .utf8)!
        return NSAppleEventDescriptor(descriptorType: 0x6675726C, data: data)!  // 'furl'
    }

    /// Build a record with a Mac Roman keyword.
    private func macRomanKeyword(_ byte0: UInt8, _ byte1: UInt8, _ byte2: UInt8, _ byte3: UInt8) -> UInt32 {
        UInt32(byte0) << 24 | UInt32(byte1) << 16 | UInt32(byte2) << 8 | UInt32(byte3)
    }

    // MARK: - Object Specifier Decoding + Formatting

    @Test func testWindowByIndex() {
        let dict = makeDictionary()
        let desc = buildIndexSpec(want: "cwin", index: 3)
        let value = decoder.decode(desc)

        // JSON (XPath)
        let json = jsonFormatter(dictionary: dict, appName: "Finder").format(value)
        #expect(json.contains("/Finder/windows[3]"))

        // AppleScript terminology
        let asTerminology = terminologyFormatter(dictionary: dict, appName: "Finder").format(value)
        #expect(asTerminology.contains("window 3"))
        #expect(asTerminology.contains("tell application \"Finder\""))

        // Chevron
        let asChevron = chevronFormatter(appName: "Finder").format(value)
        #expect(asChevron.contains("\u{00AB}class cwin\u{00BB} 3"))
    }

    @Test func testWindowByName() {
        let dict = makeDictionary()
        let desc = buildNameSpec(want: "cwin", name: "Main Window")
        let value = decoder.decode(desc)

        let json = jsonFormatter(dictionary: dict, appName: "App").format(value)
        #expect(json.contains("/App/windows[@name=\\\"Main Window\\\"]"))

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "window \"Main Window\"")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "\u{00AB}class cwin\u{00BB} \"Main Window\"")
    }

    @Test func testDocumentByID() {
        let dict = makeDictionary()
        let desc = buildIDSpec(want: "docu", id: NSAppleEventDescriptor(int32: 42))
        let value = decoder.decode(desc)

        let json = jsonFormatter(dictionary: dict, appName: "App").format(value)
        #expect(json.contains("/App/documents[#id=42]"))

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "document id 42")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "\u{00AB}class docu\u{00BB} id 42")
    }

    @Test func testDocumentByStringID() {
        let dict = makeDictionary()
        let desc = buildIDSpec(want: "docu", id: NSAppleEventDescriptor(string: "ABC-123"))
        let value = decoder.decode(desc)

        let json = jsonFormatter(dictionary: dict, appName: "App").format(value)
        #expect(json.contains("/App/documents[#id=\\\"ABC-123\\\"]"))

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "document id \"ABC-123\"")
    }

    @Test func testEveryWindow() {
        let dict = makeDictionary()
        let desc = buildEverySpec(want: "cwin")
        let value = decoder.decode(desc)

        let json = jsonFormatter(dictionary: dict, appName: "App").format(value)
        #expect(json.contains("/App/windows"))
        #expect(!json.contains("["))  // no predicate for "every"

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "every window")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "every \u{00AB}class cwin\u{00BB}")
    }

    @Test func testLastDocument() {
        let dict = makeDictionary()
        let desc = buildLastSpec(want: "docu")
        let value = decoder.decode(desc)

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "last document")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "last \u{00AB}class docu\u{00BB}")
    }

    @Test func testPropertySpecifier() {
        let dict = makeDictionary()
        let desc = buildPropSpec(propCode: "pnam")
        let value = decoder.decode(desc)

        let json = jsonFormatter(dictionary: dict, appName: "App").format(value)
        #expect(json.contains("/App/name"))

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "name")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "\u{00AB}property pnam\u{00BB}")
    }

    @Test func testNestedSpecifier_PropertyOfElement() {
        let dict = makeDictionary()
        let win = buildIndexSpec(want: "cwin", index: 1)
        let prop = buildPropSpec(propCode: "pnam", from: win)
        let value = decoder.decode(prop)

        let json = jsonFormatter(dictionary: dict, appName: "App").format(value)
        #expect(json.contains("/App/windows[1]/name"))

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "name of window 1")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "\u{00AB}property pnam\u{00BB} of \u{00AB}class cwin\u{00BB} 1")
    }

    @Test func testDeepNestedSpecifier() {
        let dict = makeDictionary()
        let app = NSAppleEventDescriptor.null()
        let win = buildNameSpec(want: "cwin", name: "Main", from: app)
        let doc = buildIndexSpec(want: "docu", index: 2, from: win)
        let prop = buildPropSpec(propCode: "imod", from: doc)
        let value = decoder.decode(prop)

        let json = jsonFormatter(dictionary: dict, appName: "App").format(value)
        #expect(json.contains("/App/windows[@name=\\\"Main\\\"]/documents[2]/modified"))

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "modified of document 2 of window \"Main\"")
    }

    @Test func testUnresolvedClassCode() {
        // Class code not in dictionary — should fall back to chevron in terminology
        let dict = makeDictionary()
        let desc = buildIndexSpec(want: "XXXX", index: 1)
        let value = decoder.decode(desc)

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "\u{00AB}class XXXX\u{00BB} 1")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "\u{00AB}class XXXX\u{00BB} 1")
    }

    @Test func testUnresolvedPropertyCode() {
        let dict = makeDictionary()
        let desc = buildPropSpec(propCode: "ZZZZ")
        let value = decoder.decode(desc)

        let asTerm = terminologyFormatter(dictionary: dict, appName: "App").formatSpecifier(value)
        #expect(asTerm == "\u{00AB}property ZZZZ\u{00BB}")

        let asChev = chevronFormatter(appName: "App").formatSpecifier(value)
        #expect(asChev == "\u{00AB}property ZZZZ\u{00BB}")
    }

    // MARK: - File URL Descriptors

    @Test func testFileURLDecoding() {
        let desc = buildFileURL("/Users/test/Documents/readme.txt")
        let value = decoder.decode(desc)
        #expect(value == .string("/Users/test/Documents/readme.txt"))
    }

    @Test func testFileURLWithSpaces() {
        let desc = buildFileURL("/Users/test/My Documents/my file.txt")
        let value = decoder.decode(desc)
        #expect(value == .string("/Users/test/My Documents/my file.txt"))
    }

    @Test func testFileURLInRecord() {
        let dict = makeDictionary()
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(string: "readme.txt"), forKeyword: FourCharCode("pnam"))
        record.setDescriptor(buildFileURL("/Users/test/readme.txt"), forKeyword: FourCharCode("file"))
        let value = decoder.decode(record)

        // JSON — file should appear as a path string
        let json = jsonFormatter(dictionary: dict).format(value)
        #expect(json.contains("/Users/test/readme.txt"))
        #expect(json.contains("name"))
    }

    // MARK: - Mac Roman Keywords

    @Test func testMacRomanKeywordDecoding() {
        // Simulate BBEdit-style codes: 0xA6 = ¶ in Mac Roman
        let record = NSAppleEventDescriptor.record()
        let paraFcn = macRomanKeyword(0xA6, 0x46, 0x63, 0x6E)  // ¶Fcn
        record.setDescriptor(NSAppleEventDescriptor(string: "functions list"), forKeyword: paraFcn)
        let value = decoder.decode(record)

        guard case .record(let pairs) = value else {
            Issue.record("Expected .record")
            return
        }
        #expect(pairs.count == 1)
        #expect(pairs[0].0 == "\u{00B6}Fcn")  // ¶Fcn in Unicode
        #expect(pairs[0].1 == .string("functions list"))
    }

    @Test func testMacRomanKeywordChevronFormat() {
        let value = AEValue.record([("\u{00B6}Fcn", .string("functions list"))])

        let asChev = chevronFormatter().formatValue(value)
        #expect(asChev.contains("\u{00AB}property \u{00B6}Fcn\u{00BB}"))
        #expect(asChev.contains("\"functions list\""))
    }

    @Test func testMultipleMacRomanKeys() {
        let record = NSAppleEventDescriptor.record()
        let paraFcn = macRomanKeyword(0xA6, 0x46, 0x63, 0x6E)  // ¶Fcn
        let paraJmp = macRomanKeyword(0xA6, 0x4A, 0x6D, 0x70)  // ¶Jmp
        let tmCSS   = macRomanKeyword(0xAA, 0x43, 0x53, 0x53)  // ™CSS
        record.setDescriptor(NSAppleEventDescriptor(string: "func"), forKeyword: paraFcn)
        record.setDescriptor(NSAppleEventDescriptor(string: "jump"), forKeyword: paraJmp)
        record.setDescriptor(NSAppleEventDescriptor(string: "css"), forKeyword: tmCSS)
        let value = decoder.decode(record)

        guard case .record(let pairs) = value else {
            Issue.record("Expected .record")
            return
        }
        #expect(pairs.count == 3)
        // Each key should be unique — not ????
        let keys = pairs.map(\.0)
        #expect(!keys.contains("????"))
        #expect(keys.contains("\u{00B6}Fcn"))
        #expect(keys.contains("\u{00B6}Jmp"))
        #expect(keys.contains("\u{2122}CSS"))  // ™ is U+2122
    }

    @Test func testMacRomanKeyRoundTrip() {
        // Verify FourCharCode init/stringValue round-trip for Mac Roman codes
        let code: UInt32 = macRomanKeyword(0xAA, 0x4D, 0x61, 0x6E)  // ™Man
        let str = code.stringValue
        #expect(str == "\u{2122}Man")

        // Round-trip back through init
        let rebuilt = FourCharCode(str)
        #expect(rebuilt == code)
    }

    // MARK: - User Record Fields (usrf)

    @Test func testUserRecordFieldsDecoding() {
        let record = NSAppleEventDescriptor.record()
        // Build usrf list: ["Scripts", "/path/to/scripts", "Logs", "/path/to/logs"]
        let usrfList = NSAppleEventDescriptor.list()
        usrfList.insert(NSAppleEventDescriptor(string: "Scripts"), at: 1)
        usrfList.insert(NSAppleEventDescriptor(string: "/Library/Scripts"), at: 2)
        usrfList.insert(NSAppleEventDescriptor(string: "Logs"), at: 3)
        usrfList.insert(NSAppleEventDescriptor(string: "/Library/Logs"), at: 4)
        record.setDescriptor(usrfList, forKeyword: 0x75737266)  // 'usrf'

        let value = decoder.decode(record)
        guard case .record(let pairs) = value else {
            Issue.record("Expected .record")
            return
        }
        #expect(pairs.count == 2)
        #expect(pairs[0] == ("Scripts", .string("/Library/Scripts")))
        #expect(pairs[1] == ("Logs", .string("/Library/Logs")))
    }

    @Test func testUserRecordFieldsMixedWithKeywords() {
        let record = NSAppleEventDescriptor.record()
        // Standard keyword field
        record.setDescriptor(NSAppleEventDescriptor(string: "MyApp"), forKeyword: FourCharCode("pnam"))
        // usrf list
        let usrfList = NSAppleEventDescriptor.list()
        usrfList.insert(NSAppleEventDescriptor(string: "custom key"), at: 1)
        usrfList.insert(NSAppleEventDescriptor(int32: 42), at: 2)
        record.setDescriptor(usrfList, forKeyword: 0x75737266)

        let value = decoder.decode(record)
        guard case .record(let pairs) = value else {
            Issue.record("Expected .record")
            return
        }
        #expect(pairs.count == 2)
        // Standard keyword first
        #expect(pairs[0] == ("pnam", .string("MyApp")))
        // User field
        #expect(pairs[1] == ("custom key", .integer(42)))
    }

    @Test func testUserRecordFieldsOddCount() {
        // Odd number of items — last unpaired item should be skipped
        let record = NSAppleEventDescriptor.record()
        let usrfList = NSAppleEventDescriptor.list()
        usrfList.insert(NSAppleEventDescriptor(string: "key1"), at: 1)
        usrfList.insert(NSAppleEventDescriptor(string: "val1"), at: 2)
        usrfList.insert(NSAppleEventDescriptor(string: "orphan"), at: 3)
        record.setDescriptor(usrfList, forKeyword: 0x75737266)

        let value = decoder.decode(record)
        guard case .record(let pairs) = value else {
            Issue.record("Expected .record")
            return
        }
        #expect(pairs.count == 1)
        #expect(pairs[0] == ("key1", .string("val1")))
    }

    @Test func testUserRecordFieldsWithFileURLValues() {
        let record = NSAppleEventDescriptor.record()
        let usrfList = NSAppleEventDescriptor.list()
        usrfList.insert(NSAppleEventDescriptor(string: "Scripts"), at: 1)
        usrfList.insert(buildFileURL("/Users/test/Scripts"), at: 2)
        usrfList.insert(NSAppleEventDescriptor(string: "Logs"), at: 3)
        usrfList.insert(buildFileURL("/Users/test/Logs"), at: 4)
        record.setDescriptor(usrfList, forKeyword: 0x75737266)

        let value = decoder.decode(record)
        guard case .record(let pairs) = value else {
            Issue.record("Expected .record")
            return
        }
        #expect(pairs.count == 2)
        #expect(pairs[0] == ("Scripts", .string("/Users/test/Scripts")))
        #expect(pairs[1] == ("Logs", .string("/Users/test/Logs")))
    }

    @Test func testUserRecordFieldsJSONFormat() {
        let value = AEValue.record([
            ("Application Support", .string("/Library/Application Support/App")),
            ("Scripts", .string("/Library/Scripts")),
        ])

        let json = jsonFormatter().format(value)
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj != nil)
        #expect(obj?["Application Support"] as? String == "/Library/Application Support/App")
        #expect(obj?["Scripts"] as? String == "/Library/Scripts")
    }

    @Test func testUserRecordFieldsChevronFormat() {
        // User field keys are plain names, not 4CC codes — no chevron wrapping
        let value = AEValue.record([
            ("Scripts", .string("/Library/Scripts")),
        ])
        let asChev = chevronFormatter().formatValue(value)
        #expect(asChev.contains("Scripts:\"/Library/Scripts\""))
        #expect(!asChev.contains("\u{00AB}property Scripts\u{00BB}"))
    }

    // MARK: - Record Key/Value Resolution

    @Test func testRecordWithPclsResolvesClassName() {
        let dict = makeDictionary()
        let value = AEValue.record([
            ("pcls", .string("docu")),
            ("pnam", .string("readme.txt")),
            ("imod", .bool(true)),
        ])

        // JSON — pcls should resolve to class name, pnam to "name"
        let json = jsonFormatter(dictionary: dict).format(value)
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["class"] as? String == "document")
        #expect(obj?["name"] as? String == "readme.txt")
        #expect(obj?["modified"] as? Bool == true)
    }

    @Test func testRecordPclsTerminologyFormat() {
        let dict = makeDictionary()
        let value = AEValue.record([
            ("pcls", .string("docu")),
            ("pnam", .string("test.txt")),
        ])
        let asTerm = terminologyFormatter(dictionary: dict).formatValue(value)
        #expect(asTerm.contains("class:document"))
        #expect(asTerm.contains("name:\"test.txt\""))
    }

    @Test func testRecordPclsChevronFormat() {
        let value = AEValue.record([
            ("pcls", .string("docu")),
            ("pnam", .string("test.txt")),
        ])
        let asChev = chevronFormatter().formatValue(value)
        #expect(asChev.contains("\u{00AB}property pcls\u{00BB}:\u{00AB}class docu\u{00BB}"))
        #expect(asChev.contains("\u{00AB}property pnam\u{00BB}:\"test.txt\""))
    }

    @Test func testRecordMissingValueResolution() {
        let dict = makeDictionary()
        let value = AEValue.record([
            ("pnam", .string("test")),
            ("file", .string("msng")),
        ])

        // JSON — msng should become null
        let json = jsonFormatter(dictionary: dict).format(value)
        #expect(json.contains("null"))

        // AppleScript — msng should become "missing value"
        let asTerm = terminologyFormatter(dictionary: dict).formatValue(value)
        #expect(asTerm.contains("missing value"))
    }

    @Test func testRecordEnumResolution() {
        let dict = makeDictionary()
        let value = AEValue.record([
            ("pcls", .string("docu")),
            ("sDen", .string("utf8")),
        ])

        // JSON — enum code should resolve to enumerator name
        let json = jsonFormatter(dictionary: dict).format(value)
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["encoding"] as? String == "UTF-8")

        // AppleScript terminology — enum should resolve
        let asTerm = terminologyFormatter(dictionary: dict).formatValue(value)
        #expect(asTerm.contains("encoding:UTF-8"))
    }

    @Test func testWellKnownPropertyCodes() {
        // Well-known codes (pcls, pALL, ID) should resolve even without dictionary
        let value = AEValue.record([
            ("pcls", .string("cwin")),
            ("ID  ", .integer(42)),
        ])

        let json = jsonFormatter().format(value)
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["class"] != nil)
        #expect(obj?["id"] as? Int == 42)
    }

    // MARK: - Lists of Specifiers

    @Test func testListOfObjectSpecifiers() {
        let dict = makeDictionary()
        let win1 = decoder.decode(buildIndexSpec(want: "cwin", index: 1))
        let win2 = decoder.decode(buildIndexSpec(want: "cwin", index: 2))
        let list = AEValue.list([win1, win2])

        let json = jsonFormatter(dictionary: dict, appName: "App").format(list)
        #expect(json.contains("/App/windows[1]"))
        #expect(json.contains("/App/windows[2]"))
    }

    @Test func testListWithMixedTypes() {
        let dict = makeDictionary()
        let winSpec = decoder.decode(buildIndexSpec(want: "cwin", index: 1))
        let list = AEValue.list([.string("hello"), .integer(42), winSpec, .bool(true)])

        let json = jsonFormatter(dictionary: dict, appName: "App").format(list)
        #expect(json.contains("hello"))
        #expect(json.contains("42"))
        #expect(json.contains("/App/windows[1]"))
        #expect(json.contains("true"))
    }

    // MARK: - Nested Records

    @Test func testNestedRecords() {
        let dict = makeDictionary()
        let inner = AEValue.record([
            ("pnam", .string("search term")),
        ])
        let outer = AEValue.record([
            ("pnam", .string("MyApp")),
            ("CSOp", .record([("pnam", .string("search term"))])),
        ])

        let json = jsonFormatter(dictionary: dict).format(outer)
        #expect(json.contains("\"name\""))
        // Inner record should also have resolved key
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["name"] as? String == "MyApp")
    }

    // MARK: - FourCharCode Mac Roman round-trip

    @Test func testFourCharCodeASCII() {
        let code = FourCharCode("pnam")
        #expect(code.stringValue == "pnam")
        #expect(FourCharCode(code.stringValue) == code)
    }

    @Test func testFourCharCodeWithSpaces() {
        let code = FourCharCode("ID  ")
        #expect(code.stringValue == "ID  ")
        #expect(FourCharCode(code.stringValue) == code)
    }

    @Test func testFourCharCodeSpecialChars() {
        let code = FourCharCode("----")
        #expect(code.stringValue == "----")

        let code2 = FourCharCode("=   ")
        #expect(code2.stringValue == "=   ")
    }

    @Test func testFourCharCodeMacRomanParagraph() {
        // 0xA6 = ¶ in Mac Roman (U+00B6 in Unicode)
        let code: UInt32 = 0xA646636E  // ¶Fcn
        #expect(code.stringValue == "\u{00B6}Fcn")
        #expect(FourCharCode(code.stringValue) == code)
    }

    @Test func testFourCharCodeMacRomanTrademark() {
        // 0xAA = ™ in Mac Roman (U+2122 in Unicode)
        let code: UInt32 = 0xAA435353  // ™CSS
        #expect(code.stringValue == "\u{2122}CSS")
        #expect(FourCharCode(code.stringValue) == code)
    }

    @Test func testFourCharCodeMacRomanSection() {
        // 0xA4 = § in Mac Roman (U+00A7 in Unicode)
        let code: UInt32 = 0xA46C7374  // §lst
        #expect(code.stringValue == "\u{00A7}lst")
        #expect(FourCharCode(code.stringValue) == code)
    }

    @Test func testFourCharCodeAllHighBytes() {
        // All bytes > 127 — should still produce unique 4-char Mac Roman string
        let code: UInt32 = 0xA6A6A6A6
        let str = code.stringValue
        #expect(str.count == 4)
        #expect(str != "????")
        #expect(FourCharCode(str) == code)
    }

    // MARK: - Complex Scenario: BBEdit-like record

    @Test func testBBEditLikeRecord() {
        let dict = makeDictionary()
        // Simulate a BBEdit-style application properties record
        let paraFcn = macRomanKeyword(0xA6, 0x46, 0x63, 0x6E)  // ¶Fcn
        let tmCSS = macRomanKeyword(0xAA, 0x43, 0x53, 0x53)    // ™CSS

        // Build the raw descriptor
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: FourCharCode("ID  "))
        record.setDescriptor(NSAppleEventDescriptor(string: "BBEdit"), forKeyword: FourCharCode("pnam"))
        record.setDescriptor(NSAppleEventDescriptor(boolean: false), forKeyword: FourCharCode("pisf"))
        record.setDescriptor(NSAppleEventDescriptor(string: "15.5"), forKeyword: FourCharCode("vers"))
        // Mac Roman keys
        let funcObj = buildIndexSpec(want: "cwin", index: 5)
        record.setDescriptor(funcObj, forKeyword: paraFcn)
        let cssObj = buildIndexSpec(want: "cwin", index: 8)
        record.setDescriptor(cssObj, forKeyword: tmCSS)
        // usrf user fields
        let usrfList = NSAppleEventDescriptor.list()
        usrfList.insert(NSAppleEventDescriptor(string: "Scripts"), at: 1)
        usrfList.insert(buildFileURL("/Users/test/Scripts"), at: 2)
        usrfList.insert(NSAppleEventDescriptor(string: "Logs"), at: 3)
        usrfList.insert(buildFileURL("/Users/test/Logs"), at: 4)
        record.setDescriptor(usrfList, forKeyword: 0x75737266)

        let value = decoder.decode(record)
        guard case .record(let pairs) = value else {
            Issue.record("Expected .record")
            return
        }

        // Should have: ID, pnam, pisf, vers, ¶Fcn, ™CSS, Scripts, Logs = 8 entries
        #expect(pairs.count == 8)

        // No ???? keys
        let keys = pairs.map(\.0)
        #expect(!keys.contains("????"))

        // Standard keys present
        #expect(keys.contains("ID  "))
        #expect(keys.contains("pnam"))

        // Mac Roman keys decoded correctly
        #expect(keys.contains("\u{00B6}Fcn"))
        #expect(keys.contains("\u{2122}CSS"))

        // User record fields unpacked
        #expect(keys.contains("Scripts"))
        #expect(keys.contains("Logs"))

        // File URL values decoded to paths
        if let scriptsIdx = keys.firstIndex(of: "Scripts") {
            #expect(pairs[scriptsIdx].1 == .string("/Users/test/Scripts"))
        }

        // JSON output — all keys should be present and valid
        let json = jsonFormatter(dictionary: dict, appName: "BBEdit").format(value)
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj != nil)
        #expect(obj?["name"] as? String == "BBEdit")
        #expect(obj?["frontmost"] as? Bool == false)
        #expect(obj?["Scripts"] as? String == "/Users/test/Scripts")
        #expect(obj?["Logs"] as? String == "/Users/test/Logs")

        // Chevron output — Mac Roman keys in chevron syntax, user fields as plain names
        let asChev = chevronFormatter(appName: "BBEdit").formatValue(value)
        #expect(asChev.contains("\u{00AB}property \u{00B6}Fcn\u{00BB}"))
        #expect(asChev.contains("\u{00AB}property \u{2122}CSS\u{00BB}"))
        // User field keys should NOT be wrapped in «property ...»
        #expect(asChev.contains("Scripts:"))
        #expect(!asChev.contains("\u{00AB}property Scripts\u{00BB}"))
    }
}
