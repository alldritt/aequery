import Testing
@testable import AEQueryLib

@Suite("SDEFResolver")
struct SDEFResolverTests {
    private let sdef = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
    <dictionary>
        <suite name="Standard Suite" code="core">
            <class name="application" code="capp" plural="applications">
                <property name="name" code="pnam" type="text"/>
                <element type="window"/>
                <element type="document"/>
                <element type="file"/>
            </class>
            <class name="window" code="cwin" plural="windows">
                <property name="name" code="pnam" type="text"/>
                <property name="index" code="pidx" type="integer"/>
                <element type="document"/>
            </class>
            <class name="document" code="docu" plural="documents">
                <property name="name" code="pnam" type="text"/>
                <property name="path" code="ppth" type="text"/>
            </class>
            <class name="item" code="cobj">
                <property name="name" code="pnam" type="text"/>
                <property name="id" code="ID  " type="integer"/>
            </class>
            <class name="file" code="file" plural="files" inherits="item">
                <property name="size" code="ptsz" type="integer"/>
            </class>
        </suite>
    </dictionary>
    """

    private func resolve(_ expression: String) throws -> ResolvedQuery {
        var lexer = Lexer(expression)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let query = try parser.parse()
        let dict = try SDEFParser().parse(xmlString: sdef)
        return try SDEFResolver(dictionary: dict).resolve(query)
    }

    @Test func testResolveElementThenProperty() throws {
        let r = try resolve("/App/windows/name")
        #expect(r.steps.count == 2)
        #expect(r.steps[0].kind == .element)
        #expect(r.steps[0].code == "cwin")
        #expect(r.steps[1].kind == .property)
        #expect(r.steps[1].code == "pnam")
    }

    @Test func testResolveElementOnly() throws {
        let r = try resolve("/App/windows")
        #expect(r.steps.count == 1)
        #expect(r.steps[0].kind == .element)
        #expect(r.steps[0].code == "cwin")
    }

    @Test func testResolvePropertyOnly() throws {
        let r = try resolve("/App/name")
        #expect(r.steps.count == 1)
        #expect(r.steps[0].kind == .property)
        #expect(r.steps[0].code == "pnam")
    }

    @Test func testResolvePluralName() throws {
        let r = try resolve("/App/windows")
        #expect(r.steps[0].kind == .element)
        #expect(r.steps[0].code == "cwin")
    }

    @Test func testResolveSingularName() throws {
        let r = try resolve("/App/window")
        #expect(r.steps[0].kind == .element)
        #expect(r.steps[0].code == "cwin")
    }

    @Test func testResolveNestedElements() throws {
        let r = try resolve("/App/windows/documents")
        #expect(r.steps.count == 2)
        #expect(r.steps[0].kind == .element)
        #expect(r.steps[0].code == "cwin")
        #expect(r.steps[1].kind == .element)
        #expect(r.steps[1].code == "docu")
    }

    @Test func testResolveInheritedProperty() throws {
        let r = try resolve("/App/files/name")
        #expect(r.steps.count == 2)
        #expect(r.steps[0].kind == .element)
        #expect(r.steps[0].code == "file")
        #expect(r.steps[1].kind == .property)
        #expect(r.steps[1].code == "pnam")
    }

    @Test func testUnknownElementError() throws {
        #expect(throws: ResolverError.self) {
            try resolve("/App/foobar")
        }
    }

    @Test func testUnknownPropertyError() throws {
        #expect(throws: ResolverError.self) {
            try resolve("/App/windows/foobar")
        }
    }

    @Test func testPredicatesCarriedThrough() throws {
        let r = try resolve("/App/windows[1]/name")
        #expect(r.steps[0].predicates == [.byIndex(1)])
    }
}
