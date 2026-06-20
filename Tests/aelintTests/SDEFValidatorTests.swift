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
}
