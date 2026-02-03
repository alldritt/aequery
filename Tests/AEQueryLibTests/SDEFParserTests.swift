import Testing
@testable import AEQueryLib

@Suite("SDEFParser")
struct SDEFParserTests {
    private let minimalSDEF = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
    <dictionary>
        <suite name="Standard Suite" code="core">
            <class name="application" code="capp" plural="applications">
                <property name="name" code="pnam" type="text" access="r"/>
                <element type="window"/>
            </class>
            <class name="window" code="cwin" plural="windows">
                <property name="name" code="pnam" type="text"/>
                <property name="index" code="pidx" type="integer"/>
            </class>
        </suite>
    </dictionary>
    """

    @Test func testParseMinimalSDEF() throws {
        let dict = try SDEFParser().parse(xmlString: minimalSDEF)
        #expect(dict.findClass("application") != nil)
        #expect(dict.findClass("window") != nil)
    }

    @Test func testPropertyParsing() throws {
        let dict = try SDEFParser().parse(xmlString: minimalSDEF)
        let winClass = dict.findClass("window")!
        let nameProp = winClass.properties.first { $0.name == "name" }
        #expect(nameProp != nil)
        #expect(nameProp?.code == "pnam")
        #expect(nameProp?.type == "text")
    }

    @Test func testPropertyAccess() throws {
        let dict = try SDEFParser().parse(xmlString: minimalSDEF)
        let appClass = dict.findClass("application")!
        let nameProp = appClass.properties.first { $0.name == "name" }
        #expect(nameProp?.access == .readOnly)
    }

    @Test func testElementParsing() throws {
        let dict = try SDEFParser().parse(xmlString: minimalSDEF)
        let appClass = dict.findClass("application")!
        #expect(appClass.elements.contains { $0.type == "window" })
    }

    @Test func testPluralNameLookup() throws {
        let dict = try SDEFParser().parse(xmlString: minimalSDEF)
        let cls = dict.findClass("windows")
        #expect(cls != nil)
        #expect(cls?.name == "window")
    }

    @Test func testInheritance() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="item" code="cobj">
                    <property name="name" code="pnam" type="text"/>
                    <property name="id" code="ID  " type="integer"/>
                </class>
                <class name="file" code="file" inherits="item" plural="files">
                    <property name="size" code="ptsz" type="integer"/>
                </class>
                <class name="application" code="capp">
                    <element type="file"/>
                </class>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        let fileClass = dict.findClass("file")!
        let allProps = dict.allProperties(for: fileClass)
        #expect(allProps.contains { $0.name == "name" })
        #expect(allProps.contains { $0.name == "id" })
        #expect(allProps.contains { $0.name == "size" })
    }

    @Test func testClassExtension() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="document" code="docu" plural="documents">
                    <property name="name" code="pnam" type="text"/>
                </class>
                <class name="application" code="capp">
                    <element type="document"/>
                </class>
                <class-extension extends="document">
                    <property name="path" code="ppth" type="text"/>
                </class-extension>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        let docClass = dict.findClass("document")!
        #expect(docClass.properties.contains { $0.name == "name" })
        #expect(docClass.properties.contains { $0.name == "path" })
    }

    @Test func testMultipleSuites() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp">
                    <element type="window"/>
                </class>
                <class name="window" code="cwin" plural="windows">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
            <suite name="Text Suite" code="text">
                <class name="paragraph" code="cpar" plural="paragraphs">
                    <property name="text" code="ctxt" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        #expect(dict.findClass("window") != nil)
        #expect(dict.findClass("paragraph") != nil)
    }

    @Test func testCaseInsensitiveLookup() throws {
        let dict = try SDEFParser().parse(xmlString: minimalSDEF)
        #expect(dict.findClass("Window") != nil)
        #expect(dict.findClass("WINDOW") != nil)
    }

    @Test func testEnumeration() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="save options" code="savo">
                    <enumerator name="yes" code="yes "/>
                    <enumerator name="no" code="no  "/>
                    <enumerator name="ask" code="ask "/>
                </enumeration>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        let enumDef = dict.findEnumeration("save options")
        #expect(enumDef != nil)
        #expect(enumDef?.enumerators.count == 3)
        #expect(enumDef?.enumerators[0].name == "yes")
        #expect(enumDef?.enumerators[0].code == "yes ")
    }

    @Test func testMissingPluralName() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp">
                    <element type="tab"/>
                </class>
                <class name="tab" code="bTab">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        // Should be findable by singular name
        #expect(dict.findClass("tab") != nil)
    }
}
