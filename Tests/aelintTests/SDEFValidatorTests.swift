import Testing
@testable import aelint
@testable import AEQueryLib

/// Tests for the static SDEF lint checks in `SDEFValidator`. Each test parses a
/// small SDEF, runs validation, and inspects the findings by category.
@Suite("SDEFValidator")
struct SDEFValidatorTests {

    /// Parse an SDEF string and return all lint findings.
    private func lint(_ sdef: String, appName: String = "TestApp") throws -> [LintFinding] {
        let dict = try SDEFParser().parse(xmlString: sdef)
        return SDEFValidator(dictionary: dict, appName: appName).validate()
    }

    private func categories(_ findings: [LintFinding], _ category: String) -> [LintFinding] {
        findings.filter { $0.category == category }
    }

    // MARK: - unused-enum

    @Test func unusedEnumFlagsUnreferencedEnumeration() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="orphan mode" code="orph">
                    <enumerator name="a" code="aaaa"/>
                </enumeration>
            </suite>
        </dictionary>
        """
        let findings = try lint(sdef)
        let unused = categories(findings, "unused-enum")
        #expect(unused.count == 1)
        #expect(unused.first?.message.contains("orphan mode") == true)
    }

    @Test func unusedEnumIgnoresEnumReferencedByName() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="gradient drawing type" code="eGrT">
                    <enumerator name="linear" code="eGrL"/>
                </enumeration>
                <class name="document" code="docu">
                    <property name="gradient type" code="GrdT" type="gradient drawing type"/>
                </class>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "unused-enum").isEmpty)
    }

    /// Regression for issue #7: an enum referenced only by its four-character
    /// code must not be reported unused (nor as an undefined type).
    @Test func unusedEnumFollowsCodeReference() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="gradient drawing type" code="eGrT">
                    <enumerator name="linear" code="eGrL"/>
                </enumeration>
                <class name="document" code="docu">
                    <property name="gradient type" code="GrdT" type="eGrT"/>
                </class>
            </suite>
        </dictionary>
        """
        let findings = try lint(sdef)
        #expect(categories(findings, "unused-enum").isEmpty)
        #expect(categories(findings, "undefined-type").isEmpty)
    }

    @Test func unusedEnumCountsCommandParameterReference() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="save options" code="savo">
                    <enumerator name="yes" code="yes "/>
                </enumeration>
                <command name="close" code="coreclos">
                    <parameter name="saving" code="savo" type="save options"/>
                </command>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "unused-enum").isEmpty)
    }

    // MARK: - unused-value-type

    @Test func unusedValueTypeFlagsUnreferencedValueType() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <value-type name="orphan" code="orph"><cocoa class="NSData"/></value-type>
            </suite>
        </dictionary>
        """
        let unused = try categories(lint(sdef), "unused-value-type")
        #expect(unused.count == 1)
        #expect(unused.first?.message.contains("orphan") == true)
    }

    @Test func unusedValueTypeFollowsNameAndCodeReferences() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <value-type name="swatch" code="swch"><cocoa class="NSData"/></value-type>
                <value-type name="palette" code="pltt"><cocoa class="NSData"/></value-type>
                <class name="document" code="docu">
                    <property name="fill" code="pfil" type="swatch"/>
                    <property name="theme" code="pthm" type="pltt"/>
                </class>
            </suite>
        </dictionary>
        """
        let findings = try lint(sdef)
        #expect(categories(findings, "unused-value-type").isEmpty)
        #expect(categories(findings, "undefined-type").isEmpty)
    }

    @Test func valueTypeReferencedByRecordTypePropertyCounts() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <value-type name="swatch" code="swch"><cocoa class="NSData"/></value-type>
                <record-type name="theme settings" code="thms">
                    <property name="accent" code="accn" type="swatch"/>
                </record-type>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "unused-value-type").isEmpty)
    }

    // MARK: - duplicate-code

    @Test func duplicateClassCodeIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="widget" code="dupe"/>
                <class name="gadget" code="dupe"/>
            </suite>
        </dictionary>
        """
        let dup = try categories(lint(sdef), "duplicate-code")
        #expect(dup.count == 1)
        #expect(dup.first?.severity == .error)
        #expect(dup.first?.message.contains("dupe") == true)
    }

    @Test func duplicateEnumeratorCodeIsWarning() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="alpha" code="enmA">
                    <enumerator name="one" code="shrd"/>
                </enumeration>
                <enumeration name="beta" code="enmB">
                    <enumerator name="two" code="shrd"/>
                </enumeration>
            </suite>
        </dictionary>
        """
        let dup = try categories(lint(sdef), "duplicate-code")
        #expect(dup.count == 1)
        #expect(dup.first?.severity == .warning)
    }

    // MARK: - name-clash

    @Test func elementPropertyNameClashIsWarning() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu" plural="documents">
                    <property name="document" code="pdoc" type="text"/>
                    <element type="document"/>
                </class>
            </suite>
        </dictionary>
        """
        let clash = try categories(lint(sdef), "name-clash")
        #expect(clash.count == 1)
        #expect(clash.first?.severity == .warning)
        #expect(clash.first?.message.contains("document") == true)
    }

    // MARK: - inheritance-cycle

    @Test func inheritanceCycleIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="a" code="clsa" inherits="b"/>
                <class name="b" code="clsb" inherits="a"/>
            </suite>
        </dictionary>
        """
        let cycle = try categories(lint(sdef), "inheritance-cycle")
        #expect(!cycle.isEmpty)
        #expect(cycle.allSatisfy { $0.severity == .error })
    }

    // MARK: - undefined-class

    @Test func undefinedElementTypeIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp">
                    <element type="phantom"/>
                </class>
            </suite>
        </dictionary>
        """
        let undef = try categories(lint(sdef), "undefined-class")
        #expect(undef.count == 1)
        #expect(undef.first?.severity == .error)
        #expect(undef.first?.message.contains("phantom") == true)
    }

    @Test func inheritsUndefinedClassIsWarning() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu" inherits="ghost">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let undef = try categories(lint(sdef), "undefined-class")
        #expect(undef.count == 1)
        #expect(undef.first?.severity == .warning)
        #expect(undef.first?.message.contains("ghost") == true)
    }

    // MARK: - undefined-type

    @Test func undefinedPropertyTypeIsInfo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="shade" code="shad" type="nonesuch"/>
                </class>
            </suite>
        </dictionary>
        """
        let undef = try categories(lint(sdef), "undefined-type")
        #expect(undef.count == 1)
        #expect(undef.first?.severity == .info)
        #expect(undef.first?.message.contains("nonesuch") == true)
    }

    @Test func rawFourCharTypeCodeIsNotUndefined() throws {
        // A raw OSType code with a non-letter (e.g. "ICN#") is a valid type
        // reference with no named definition, so it must not be flagged.
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="icon" code="iimg" type="ICN#"/>
                </class>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "undefined-type").isEmpty)
    }

    // MARK: - missing-plural

    @Test func missingPluralNaiveCorrectIsInfo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp">
                    <element type="document"/>
                </class>
                <class name="document" code="docu">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let plural = try categories(lint(sdef), "missing-plural")
        #expect(plural.count == 1)
        #expect(plural.first?.severity == .info)
    }

    @Test func missingPluralNaiveWrongIsWarning() throws {
        // "box" → naive "boxs" is wrong (needs "boxes"), so this escalates.
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp">
                    <element type="box"/>
                </class>
                <class name="box" code="cbox">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let plural = try categories(lint(sdef), "missing-plural")
        #expect(plural.count == 1)
        #expect(plural.first?.severity == .warning)
    }

    // MARK: - non-standard-term

    @Test func wellKnownCodeWithNonStandardNameIsWarning() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="title" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let nonStd = try categories(lint(sdef), "non-standard-term")
        #expect(nonStd.count == 1)
        #expect(nonStd.first?.severity == .warning)
        #expect(nonStd.first?.message.contains("pnam") == true)
    }

    @Test func wellKnownCodeMappedInconsistentlyIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="title" code="pnam" type="text"/>
                </class>
                <class name="window" code="cwin">
                    <property name="label" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let nonStd = try categories(lint(sdef), "non-standard-term")
        #expect(nonStd.count == 2)
        #expect(nonStd.allSatisfy { $0.severity == .error })
    }

    // MARK: - reserved-word

    @Test func reservedWordClassIsWarningPropertyIsInfo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="script" code="scpt">
                    <property name="property" code="pprp" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let reserved = try categories(lint(sdef), "reserved-word")
        #expect(reserved.contains { $0.severity == .warning && $0.message.contains("script") })
        #expect(reserved.contains { $0.severity == .info && $0.message.contains("property") })
    }

    // MARK: - command validation

    @Test func duplicateCommandCodeIsWarning() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <command name="frobnicate" code="MyApfrob"/>
                <command name="frobnicate twice" code="MyApfrob"/>
            </suite>
        </dictionary>
        """
        let dup = try categories(lint(sdef), "duplicate-command-code")
        #expect(dup.count == 1)
        #expect(dup.first?.severity == .warning)
    }

    @Test func duplicateParameterCodeIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <command name="configure" code="MyApconf">
                    <parameter name="width" code="dupp" type="integer"/>
                    <parameter name="height" code="dupp" type="integer"/>
                </command>
            </suite>
        </dictionary>
        """
        let dup = try categories(lint(sdef), "duplicate-param-code")
        #expect(dup.count == 1)
        #expect(dup.first?.severity == .error)
    }

    @Test func undefinedCommandTypeIsInfo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <command name="configure" code="MyApconf">
                    <parameter name="mode" code="pmod" type="phantom mode"/>
                </command>
            </suite>
        </dictionary>
        """
        let undef = try categories(lint(sdef), "undefined-command-type")
        #expect(undef.count == 1)
        #expect(undef.first?.severity == .info)
        #expect(undef.first?.message.contains("phantom mode") == true)
    }

    // MARK: - standard-suite

    @Test func missingApplicationClassIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="document" code="docu">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let std = try categories(lint(sdef), "standard-suite")
        #expect(std.contains { $0.severity == .error && $0.message.contains("application") })
    }

    @Test func missingStandardAppPropertyIsInfo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
            </suite>
        </dictionary>
        """
        let std = try categories(lint(sdef), "standard-suite")
        // name, frontmost, version all missing.
        #expect(std.filter { $0.severity == .info }.count == 3)
    }

    // MARK: - invalid-code

    @Test func invalidClassCodeIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="widget" code="toolong"/>
            </suite>
        </dictionary>
        """
        let invalid = try categories(lint(sdef), "invalid-code")
        #expect(invalid.count == 1)
        #expect(invalid.first?.severity == .error)
        #expect(invalid.first?.message.contains("toolong") == true)
    }

    // MARK: - documentation

    @Test func missingDescriptionsReported() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="name" code="pnam" type="text"/>
                </class>
                <command name="frobnicate" code="MyApfrob"/>
            </suite>
        </dictionary>
        """
        let docs = try categories(lint(sdef), "documentation")
        // One finding for classes, one for commands (none have descriptions).
        #expect(docs.count == 2)
        #expect(docs.allSatisfy { $0.severity == .info })
    }

    // MARK: - hidden-items

    @Test func hiddenItemsAreCounted() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="secret" code="scrt" hidden="yes">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let hidden = try categories(lint(sdef), "hidden-items")
        #expect(hidden.count == 1)
        #expect(hidden.first?.severity == .info)
    }

    // MARK: - empty-class

    @Test func emptyClassIsInfo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="hollow" code="holw"/>
            </suite>
        </dictionary>
        """
        let empty = try categories(lint(sdef), "empty-class")
        #expect(empty.count == 1)
        #expect(empty.first?.message.contains("hollow") == true)
    }
}
