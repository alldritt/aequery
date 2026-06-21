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

    /// Run only the reachability pass (which needs an `SDEFPathFinder`, so it's
    /// invoked separately from `validate()`).
    private func lintReachability(_ sdef: String, maxDepth: Int = 6) throws -> [LintFinding] {
        let dict = try SDEFParser().parse(xmlString: sdef)
        let validator = SDEFValidator(dictionary: dict, appName: "TestApp")
        let pathFinder = SDEFPathFinder(dictionary: dict)
        return validator.validateReachability(pathFinder: pathFinder, maxDepth: maxDepth)
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

    // MARK: - ambiguous-code

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
        let dup = try categories(lint(sdef), "ambiguous-code")
        #expect(dup.count == 1)
        #expect(dup.first?.severity == .error)
        #expect(dup.first?.message.contains("dupe") == true)
    }

    @Test func duplicateEnumeratorCodeIsError() throws {
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
        let dup = try categories(lint(sdef), "ambiguous-code")
        #expect(dup.count == 1)
        #expect(dup.first?.severity == .error)
        #expect(dup.first?.message.contains("shrd") == true)
    }

    @Test func duplicateCommandCodeIsError() throws {
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
        let dup = try categories(lint(sdef), "ambiguous-code")
        #expect(dup.count == 1)
        #expect(dup.first?.severity == .error)
        #expect(dup.first?.message.contains("MyApfrob") == true)
    }

    /// The decompiler ambiguity isn't special to the standard Apple Event
    /// codes: a custom property code mapped to different names across two
    /// classes is just as ambiguous, and is reported as an error.
    @Test func crossClassPropertyCodeConflictIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="hue" code="cust" type="text"/>
                </class>
                <class name="window" code="cwin">
                    <property name="shade" code="cust" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let ambiguous = try categories(lint(sdef), "ambiguous-code")
        #expect(ambiguous.count == 1)
        #expect(ambiguous.first?.severity == .error)
        #expect(ambiguous.first?.message.contains("cust") == true)
    }

    /// The same property code used with the *same* name across classes is the
    /// normal case (e.g. `pnam` is "name" everywhere) and must not be flagged.
    @Test func samePropertyCodeSameNameAcrossClassesIsClean() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="name" code="pnam" type="text"/>
                </class>
                <class name="window" code="cwin">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "ambiguous-code").isEmpty)
    }

    /// Parameter keyword codes are scoped to their command (the Standard Suite
    /// reuses `kocl`, `insh`, and others across commands by design), so they
    /// don't take part in the dictionary-wide bijection. Reuse across commands
    /// isn't flagged.
    @Test func parameterCodeReusedAcrossCommandsIsClean() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <command name="resize" code="MyAprsiz">
                    <parameter name="width" code="dimn" type="integer"/>
                </command>
                <command name="grow" code="MyApgrow">
                    <parameter name="height" code="dimn" type="integer"/>
                </command>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "ambiguous-code").isEmpty)
        #expect(try categories(lint(sdef), "ambiguous-term").isEmpty)
    }

    /// The same parameter (same name and code) reused across commands is one
    /// term, not a collision.
    @Test func parameterSameNameAndCodeAcrossCommandsIsClean() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <command name="save" code="coresave">
                    <parameter name="in" code="kfil" type="text"/>
                </command>
                <command name="export" code="MyApexpt">
                    <parameter name="in" code="kfil" type="text"/>
                </command>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "ambiguous-code").isEmpty)
        #expect(try categories(lint(sdef), "ambiguous-term").isEmpty)
    }

    // MARK: - ambiguous-term (one name → several codes)

    /// A name that resolves to two different codes is ambiguous when AppleScript
    /// compiles source. Here a class and a command share the name "print" but
    /// carry different codes.
    @Test func nameMappedToMultipleCodesIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="print" code="prnt"/>
                <command name="print" code="aevtpdoc"/>
            </suite>
        </dictionary>
        """
        let ambiguous = try categories(lint(sdef), "ambiguous-term")
        #expect(ambiguous.count == 1)
        #expect(ambiguous.first?.severity == .error)
        #expect(ambiguous.first?.message.contains("print") == true)
    }

    /// A class and a property may legitimately share both a name and a code —
    /// that's a single term, so neither direction is flagged.
    @Test func classAndPropertySharingNameAndCodeIsClean() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="color" code="colr"/>
                <class name="document" code="docu">
                    <property name="color" code="colr" type="color"/>
                </class>
            </suite>
        </dictionary>
        """
        let findings = try lint(sdef)
        #expect(categories(findings, "ambiguous-code").isEmpty)
        #expect(categories(findings, "ambiguous-term").isEmpty)
    }

    /// Collisions are caught across namespaces: a class and an enumerator that
    /// share a code but not a name is an error even though they're different
    /// kinds of term.
    @Test func crossNamespaceCodeCollisionIsError() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="widget" code="shrd"/>
                <enumeration name="mode" code="emod">
                    <enumerator name="fast" code="shrd"/>
                </enumeration>
            </suite>
        </dictionary>
        """
        let ambiguous = try categories(lint(sdef), "ambiguous-code")
        #expect(ambiguous.count == 1)
        #expect(ambiguous.first?.severity == .error)
        #expect(ambiguous.first?.message.contains("shrd") == true)
    }

    /// An enumeration is a type, so its name can be used as a property,
    /// parameter, or result type. A property sharing that name under a different
    /// code is therefore a genuine name collision.
    @Test func enumerationNameCollidesAsTerm() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="image quality" code="iqEn">
                    <enumerator name="best" code="iqBs"/>
                </enumeration>
                <class name="document" code="docu">
                    <property name="image quality" code="pImq" type="integer"/>
                </class>
            </suite>
        </dictionary>
        """
        let ambiguous = try categories(lint(sdef), "ambiguous-term")
        #expect(ambiguous.count == 1)
        #expect(ambiguous.first?.severity == .error)
        #expect(ambiguous.first?.message.contains("image quality") == true)
    }

    /// An enumeration's code must also be unique: if it collides with
    /// another term's code under a different name, that's an error.
    @Test func enumerationCodeStillCollides() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="format options" code="fmt1">
                    <enumerator name="plain" code="fmtP"/>
                </enumeration>
                <class name="document" code="docu">
                    <property name="format" code="fmt1" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let ambiguous = try categories(lint(sdef), "ambiguous-code")
        #expect(ambiguous.count == 1)
        #expect(ambiguous.first?.severity == .error)
        #expect(ambiguous.first?.message.contains("fmt1") == true)
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

    /// A standard code given a single non-standard name throughout the
    /// dictionary is a consistent (if unconventional) convention — it
    /// decompiles unambiguously, so it's only informational.
    @Test func wellKnownCodeWithConsistentNonStandardNameIsInfo() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="title" code="pnam" type="text"/>
                </class>
                <class name="window" code="cwin">
                    <property name="title" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let findings = try lint(sdef)
        let nonStd = categories(findings, "non-standard-term")
        #expect(nonStd.count == 2)
        #expect(nonStd.allSatisfy { $0.severity == .info })
        #expect(nonStd.allSatisfy { $0.message.contains("pnam") })
        // A consistent name is not ambiguous.
        #expect(categories(findings, "ambiguous-code").isEmpty)
    }

    /// A standard code mapped to *different* names is ambiguous for the
    /// decompiler: reported as an error by the ambiguous-code check, and not
    /// duplicated as a non-standard-term finding.
    @Test func wellKnownCodeMappedInconsistentlyIsAmbiguousError() throws {
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
        let findings = try lint(sdef)
        let ambiguous = categories(findings, "ambiguous-code")
        #expect(ambiguous.count == 1)
        #expect(ambiguous.first?.severity == .error)
        #expect(ambiguous.first?.message.contains("pnam") == true)
        // The ambiguity check owns this case; don't also flag non-standard-term.
        #expect(categories(findings, "non-standard-term").isEmpty)
    }

    /// The Standard Suite application/document property codes are well-known:
    /// renaming `vers` (version) or `imod` (modified) is flagged.
    @Test func standardSuiteApplicationDocumentCodesAreWellKnown() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp">
                    <property name="build" code="vers" type="text"/>
                </class>
                <class name="document" code="docu">
                    <property name="dirty" code="imod" type="boolean"/>
                </class>
            </suite>
        </dictionary>
        """
        let nonStd = try categories(lint(sdef), "non-standard-term")
        #expect(nonStd.count == 2)
        #expect(nonStd.allSatisfy { $0.severity == .info })
        #expect(nonStd.contains { $0.message.contains("vers") && $0.message.contains("version") })
        #expect(nonStd.contains { $0.message.contains("imod") && $0.message.contains("modified") })
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

    /// A code in hexadecimal form (`0x…`) decodes to four bytes and is valid —
    /// it must not be mistaken for an over-long literal.
    @Test func hexFormCodeIsValid() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="widget" code="0x00000001"/>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "invalid-code").isEmpty)
    }

    /// Code validity now covers enumerators, value-types, record-types, and
    /// parameters too, not just classes, properties, and commands.
    @Test func invalidEnumeratorAndValueTypeCodesAreErrors() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <enumeration name="mode" code="emod">
                    <enumerator name="fast" code="toolong"/>
                </enumeration>
                <value-type name="swatch" code="xy"><cocoa class="NSData"/></value-type>
            </suite>
        </dictionary>
        """
        let invalid = try categories(lint(sdef), "invalid-code")
        #expect(invalid.count == 2)
        #expect(invalid.allSatisfy { $0.severity == .error })
        #expect(invalid.contains { $0.message.contains("fast") })
        #expect(invalid.contains { $0.message.contains("swatch") })
    }

    // MARK: - deprecated-type

    @Test func deprecatedPrimitiveTypeNamesAreWarnings() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="document" code="docu">
                    <property name="title" code="ptit" type="string"/>
                    <property name="target" code="ptgt" type="object"/>
                </class>
                <command name="reveal" code="MyAprevl">
                    <parameter name="at" code="patt" type="location"/>
                </command>
            </suite>
        </dictionary>
        """
        let deprecated = try categories(lint(sdef), "deprecated-type")
        #expect(deprecated.count == 3)
        #expect(deprecated.allSatisfy { $0.severity == .warning })
        #expect(deprecated.contains { $0.message.contains("'string'") && $0.message.contains("'text'") })
        #expect(deprecated.contains { $0.message.contains("'object'") && $0.message.contains("'specifier'") })
        #expect(deprecated.contains { $0.message.contains("'location'") && $0.message.contains("'location specifier'") })
    }

    // MARK: - invalid-name

    /// Names with characters that can't be tokenized as a term — a hyphen, '#',
    /// or '&' — are flagged.
    @Test func malformedNamesAreWarnings() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="trash-object" code="ctrs"/>
                <value-type name="ICN#" code="ICN#"><cocoa class="NSData"/></value-type>
                <enumeration name="panel" code="epnl">
                    <enumerator name="Name &amp; Extension panel" code="pnex"/>
                </enumeration>
            </suite>
        </dictionary>
        """
        let invalid = try categories(lint(sdef), "invalid-name")
        #expect(invalid.count == 3)
        #expect(invalid.allSatisfy { $0.severity == .warning })
        #expect(invalid.contains { $0.message.contains("trash-object") })
        #expect(invalid.contains { $0.message.contains("ICN#") })
        #expect(invalid.contains { $0.message.contains("Name & Extension panel") })
    }

    /// Words that start with a digit are permitted — Apple's dictionaries use
    /// them pervasively (e.g. `large 8 bit mask`, `band 1`) and they're valid in
    /// practice — so a multi-word name like this is not flagged.
    @Test func digitLeadingWordsAreNotFlagged() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="icon family" code="ifam">
                    <property name="large 8 bit mask" code="l8mk" type="data"/>
                    <property name="band 1" code="bnd1" type="integer"/>
                </class>
            </suite>
        </dictionary>
        """
        #expect(try categories(lint(sdef), "invalid-name").isEmpty)
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

    // MARK: - reachability (unreachable / inferred-reachable)

    @Test func reachableViaContainmentIsNotFlagged() throws {
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
        let findings = try lintReachability(sdef)
        #expect(categories(findings, "unreachable").isEmpty)
        #expect(categories(findings, "inferred-reachable").isEmpty)
    }

    @Test func disconnectedClassIsUnreachable() throws {
        // 'island' is defined but nothing contains it, it's not a command/
        // property type, and it has no inheritance link to a reachable class.
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="island" code="isld">
                    <property name="size" code="psiz" type="integer"/>
                </class>
            </suite>
        </dictionary>
        """
        let unreachable = try categories(lintReachability(sdef), "unreachable")
        #expect(unreachable.count == 1)
        #expect(unreachable.first?.severity == .warning)
        #expect(unreachable.first?.message.contains("island") == true)
    }

    @Test func subclassOfReachableParentIsInferredReachable() throws {
        // 'project document' has no containment path of its own, but its parent
        // 'document' is reachable, so it is presumed reachable through the
        // parent's element accessor — reported as inferred-reachable, not
        // unreachable.
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
                <class name="project document" code="pdoc" inherits="document">
                    <property name="root" code="prot" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let findings = try lintReachability(sdef)
        #expect(categories(findings, "unreachable").isEmpty)
        let inferred = categories(findings, "inferred-reachable")
        #expect(inferred.count == 1)
        #expect(inferred.first?.severity == .info)
        #expect(inferred.first?.message.contains("project document") == true)
        #expect(inferred.first?.message.contains("document") == true)
    }

    @Test func classReferencedAsCommandResultTypeIsExempt() throws {
        // 'swatch color' is reachable only as a command result type (not through
        // any element/property containment), so the type-reference exemption
        // keeps it from being flagged unreachable.
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <command name="make swatch" code="MyApmksw">
                    <result type="swatch color"/>
                </command>
                <class name="swatch color" code="swcl">
                    <property name="name" code="pnam" type="text"/>
                </class>
            </suite>
        </dictionary>
        """
        let findings = try lintReachability(sdef)
        #expect(categories(findings, "unreachable").isEmpty)
        #expect(categories(findings, "inferred-reachable").isEmpty)
    }

    @Test func hiddenClassIsNeverUnreachable() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary>
            <suite name="Standard Suite" code="core">
                <class name="application" code="capp"/>
                <class name="secret" code="scrt" hidden="yes">
                    <property name="size" code="psiz" type="integer"/>
                </class>
            </suite>
        </dictionary>
        """
        #expect(try categories(lintReachability(sdef), "unreachable").isEmpty)
    }
}
