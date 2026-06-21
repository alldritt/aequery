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

    @Test func testRecordType() throws {
        // Mirrors Numbers, where commands reference record-types (e.g. "print
        // settings", "export options") as parameter types. These must be parsed
        // and resolvable so they aren't reported as undefined type references.
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <record-type name="print settings" code="pset">
                    <property name="copies" code="lwcp" type="integer"/>
                    <property name="collating" code="lwcl" type="boolean"/>
                </record-type>
                <command name="print" code="aevtpdoc">
                    <direct-parameter type="any"/>
                    <parameter name="with properties" code="prdt" type="print settings"/>
                </command>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        let record = dict.findRecordType("print settings")
        #expect(record != nil)
        #expect(record?.code == "pset")
        #expect(record?.properties.count == 2)
        // Case-insensitive lookup, matching class/enumeration behaviour.
        #expect(dict.findRecordType("PRINT SETTINGS") != nil)
        // Record-types are kept separate from classes.
        #expect(dict.findClass("print settings") == nil)
    }

    @Test func testTypeReferenceByCode() throws {
        // sdef(5): a type reference resolves against a class, enumeration, or
        // record-type by its name OR its four-character code. A property/
        // parameter may therefore reference a type by code (e.g. type="eGrT")
        // rather than by name. See aequery issue #7.
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="gradient drawing type" code="eGrT">
                    <enumerator name="linear" code="eGrL"/>
                    <enumerator name="radial" code="eGrR"/>
                </enumeration>
                <record-type name="print settings" code="pset">
                    <property name="copies" code="lwcp" type="integer"/>
                </record-type>
                <class name="document" code="docu"/>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)

        // Lookups by name still work, and resolve to the same definition as the
        // by-code lookup.
        #expect(dict.findEnumeration("gradient drawing type")?.code == "eGrT")
        #expect(dict.findEnumeration("eGrT")?.name == "gradient drawing type")
        #expect(dict.findEnumerationByCode("eGrT")?.name == "gradient drawing type")
        #expect(dict.findClass("docu")?.name == "document")
        #expect(dict.findRecordType("pset")?.name == "print settings")

        // The hexadecimal spelling of a code is equivalent to the literal one
        // ("eGrT" == 0x65477254).
        #expect(dict.findEnumeration("0x65477254")?.name == "gradient drawing type")
        #expect(ScriptingDictionary.canonicalCode("0x65477254") == "eGrT")
        #expect(ScriptingDictionary.canonicalCode("eGrT") == "eGrT")

        // Codes are case-sensitive, unlike names; a wrong-case code does not match.
        #expect(dict.findEnumeration("egrt") == nil)
        // A code that matches nothing resolves to nil rather than a stray hit.
        #expect(dict.findEnumeration("zzzz") == nil)
    }

    @Test func testValueType() throws {
        // sdef(5) <value-type>: a simple basic type (no scriptable properties or
        // elements), e.g. an "image" backed by NSData. Properties/commands may
        // reference it as a type, by name or by code.
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <value-type name="RGB color" code="cRGB">
                    <cocoa class="NSColor"/>
                </value-type>
                <class name="document" code="docu">
                    <property name="background" code="pbkg" type="RGB color"/>
                    <property name="tint" code="ptnt" type="cRGB"/>
                </class>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        let valueType = dict.findValueType("RGB color")
        #expect(valueType != nil)
        #expect(valueType?.code == "cRGB")
        // Resolvable by name (case-insensitive) and by code.
        #expect(dict.findValueType("rgb color") != nil)
        #expect(dict.findValueType("cRGB")?.name == "RGB color")
        #expect(dict.findValueTypeByCode("cRGB")?.name == "RGB color")
        // Kept separate from classes, record-types, and enumerations.
        #expect(dict.findClass("RGB color") == nil)
        #expect(dict.findRecordType("RGB color") == nil)
    }

    @Test func testHiddenSuitePropagates() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="save options" code="savo">
                    <enumerator name="yes" code="yes "/>
                </enumeration>
                <command name="open" code="aevtodoc"/>
            </suite>
            <suite name="Private" code="prv1" hidden="yes">
                <class name="secret" code="scrt"/>
                <enumeration name="internal mode" code="imod">
                    <enumerator name="alpha" code="alfa"/>
                </enumeration>
                <command name="do secret thing" code="prv1dsth"/>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)

        // Visible suite contents are not hidden.
        #expect(dict.findClass("application")?.hidden == false)
        #expect(dict.findEnumeration("save options")?.hidden == false)
        #expect(dict.commands["open"]?.hidden == false)

        // Hidden suite contents inherit the suite's hidden flag.
        #expect(dict.findClass("secret")?.hidden == true)
        #expect(dict.findEnumeration("internal mode")?.hidden == true)
        #expect(dict.commands["do secret thing"]?.hidden == true)
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

    // MARK: - id, synonym, responds-to, class-extension (Phase 1 model fields)

    @Test func testParsesIdAndSynonyms() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp" id="app-class">
                    <synonym name="app"/>
                    <property name="name" code="pnam" type="text">
                        <synonym code="pnaM"/>
                    </property>
                </class>
                <enumeration name="save options" code="savo" id="save-enum">
                    <enumerator name="yes" code="yes ">
                        <synonym name="true"/>
                    </enumerator>
                </enumeration>
                <command name="open" code="aevtodoc" id="open-cmd">
                    <synonym name="launch"/>
                </command>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)

        let app = dict.findClass("application")!
        #expect(app.id == "app-class")
        #expect(app.synonyms.contains { $0.name == "app" && $0.isNameOnly })

        let nameProp = app.properties.first { $0.name == "name" }!
        #expect(nameProp.synonyms.contains { $0.code == "pnaM" && $0.isCodeOnly })

        let saveEnum = dict.enumerations["save options"]!
        #expect(saveEnum.id == "save-enum")
        #expect(saveEnum.enumerators.first?.synonyms.contains { $0.name == "true" } == true)

        let open = dict.commands["open"]!
        #expect(open.id == "open-cmd")
        #expect(open.synonyms.contains { $0.name == "launch" })
    }

    @Test func testParsesRespondsTo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp">
                    <responds-to command="open"/>
                    <responds-to command="quit"/>
                </class>
                <command name="open" code="aevtodoc"/>
                <command name="quit" code="aevtquit"/>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        #expect(dict.findClass("application")!.respondsTo == ["open", "quit"])
    }

    @Test func testCapturesClassExtension() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="document" code="docu">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
            <suite name="App Suite" code="Myap">
                <class-extension extends="document" id="doc-ext">
                    <property name="path" code="ppth" type="text"/>
                </class-extension>
            </suite>
        </dictionary>
        """
        let dict = try SDEFParser().parse(xmlString: sdef)
        // The extension is recorded with its target...
        #expect(dict.classExtensions.contains { $0.extends == "document" && $0.id == "doc-ext" })
        // ...and its members are merged into the target class.
        #expect(dict.findClass("document")!.properties.contains { $0.name == "path" })
    }
}
