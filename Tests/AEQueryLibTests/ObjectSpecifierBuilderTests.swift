import Testing
import Foundation
@testable import AEQueryLib

@Suite("ObjectSpecifierBuilder")
struct ObjectSpecifierBuilderTests {
    private let builder = ObjectSpecifierBuilder()

    @Test func testPropertyOfApplication() throws {
        let step = ResolvedStep(name: "name", kind: .property, code: "pnam")
        let spec = builder.buildStep(step, container: .null())

        // Should be an object specifier
        #expect(spec.descriptorType == FourCharCode("obj "))

        // Check form = formPropertyID
        let form = spec.forKeyword(AEConstants.keyAEKeyForm)
        #expect(form != nil)
    }

    @Test func testEveryElement() throws {
        let step = ResolvedStep(name: "windows", kind: .element, code: "cwin")
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    @Test func testElementByIndex() throws {
        let step = ResolvedStep(name: "windows", kind: .element, code: "cwin", predicates: [.byIndex(1)])
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    @Test func testElementByName() throws {
        let step = ResolvedStep(name: "windows", kind: .element, code: "cwin", predicates: [.byName("Desktop")])
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    @Test func testElementByID() throws {
        let step = ResolvedStep(name: "windows", kind: .element, code: "cwin", predicates: [.byID(.integer(42))])
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    @Test func testElementByRange() throws {
        let step = ResolvedStep(name: "paragraphs", kind: .element, code: "cpar", predicates: [.byRange(1, 3)])
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    @Test func testNestedSpecifier() throws {
        let resolved = ResolvedQuery(
            appName: "Finder",
            steps: [
                ResolvedStep(name: "windows", kind: .element, code: "cwin", predicates: [.byName("Desktop")]),
                ResolvedStep(name: "files", kind: .element, code: "file"),
                ResolvedStep(name: "name", kind: .property, code: "pnam"),
            ]
        )
        let spec = builder.buildSpecifier(from: resolved)

        // The outermost specifier should be an object specifier
        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    @Test func testWhoseClause() throws {
        let test = TestExpr(path: ["size"], op: .greaterThan, value: .integer(1000))
        let step = ResolvedStep(name: "files", kind: .element, code: "file", predicates: [.test(test)])
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    @Test func testCompoundWhose() throws {
        let test1 = TestExpr(path: ["size"], op: .greaterThan, value: .integer(100))
        let test2 = TestExpr(path: ["name"], op: .equal, value: .string("test"))
        let compound = Predicate.compound(.test(test1), .and, .test(test2))
        let step = ResolvedStep(name: "files", kind: .element, code: "file", predicates: [compound])
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
    }

    /// Reads back the four-char ordinal code from a `.byOrdinal` specifier.
    private func ordinalCode(of predicate: AEQueryLib.Predicate) throws -> String {
        let step = ResolvedStep(name: "windows", kind: .element, code: "cwin", predicates: [predicate])
        let spec = builder.buildStep(step, container: .null())

        #expect(spec.descriptorType == FourCharCode("obj "))
        // Key form must be absolute position for an ordinal specifier.
        let form = try #require(spec.forKeyword(AEConstants.keyAEKeyForm))
        #expect(form.enumCodeValue == AEConstants.formAbsolutePosition)

        let keyData = try #require(spec.forKeyword(AEConstants.keyAEKeyData))
        #expect(keyData.descriptorType == AEConstants.typeAbsoluteOrdinal)
        let bytes = keyData.data
        #expect(bytes.count == 4)
        // typeAbsoluteOrdinal stores the code as a native-endian OSType (the AE
        // Manager byte-swaps it on the wire), so read it back the same way.
        let value = bytes.withUnsafeBytes { $0.load(as: FourCharCode.self) }
        return value.stringValue
    }

    // Regression: AppleScript's `some <element>` maps to Apple's kAEAny ordinal,
    // whose code is 'any ' (a-n-y-space). It was previously mis-defined as 'sran',
    // which every app rejects — so dynamic `some` access always falsely failed.
    @Test func testSomeOrdinalUsesKAEAny() throws {
        let code = try ordinalCode(of: AEQueryLib.Predicate.byOrdinal(.some))
        #expect(code == "any ")
    }

    @Test func testMiddleOrdinalCode() throws {
        let code = try ordinalCode(of: AEQueryLib.Predicate.byOrdinal(.middle))
        #expect(code == "midd")
    }
}
