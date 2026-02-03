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
}
