import AEQueryLib
import Foundation

struct SDEFValidator {
    let dictionary: ScriptingDictionary
    let appName: String

    // Types declared by macOS's system-wide SDEF files (Intrinsics, Cocoa
    // Standard, OpenScripting Compatibility). Used to verify, rather than
    // guess, that a dangling type reference is system-defined.
    let systemTypes = SystemTypeRegistry()

    /// Whether an unresolved type name is a raw four-character OSType code
    /// (e.g. Finder's `ICN#`, `il32`) rather than a named type. These are
    /// valid type references even though they have no named definition.
    private func isRawTypeCode(_ name: String) -> Bool {
        name.count == 4 && name.contains { !$0.isLetter }
    }

    // Well-known 4CC codes and their expected standard terms. These are codes
    // Apple reserves ecosystem-wide for a single name, so using the code under
    // a different name is a deviation rather than a legitimate app-specific
    // choice. Sources: the intrinsic AEOM properties every object carries
    // (class, properties) and the Standard Suite application/document/window
    // classes in /System/Library/ScriptingDefinitions/CocoaStandard.sdef.
    private static let wellKnownCodes: [String: String] = [
        // Intrinsic AEOM properties (every object)
        "pcls": "class",
        "pALL": "properties",
        // Standard Suite — application
        "pnam": "name",
        "pisf": "frontmost",
        "vers": "version",
        // Standard Suite — document
        "imod": "modified",
        "file": "file",
        // Standard Suite — window
        "ID  ": "id",
        "pidx": "index",
        "pvis": "visible",
        "pbnd": "bounds",
    ]

    // AppleScript reserved words that shouldn't be used as terms
    private static let reservedWords: Set<String> = [
        "about", "above", "after", "against", "and", "apart from", "around",
        "as", "at", "back", "before", "beginning", "behind", "below",
        "beneath", "beside", "between", "but", "by", "considering",
        "contain", "contains", "continue", "copy", "div", "does", "eighth",
        "else", "end", "equal", "equals", "error", "every", "exit", "false",
        "fifth", "first", "for", "fourth", "from", "front", "get", "given",
        "global", "if", "ignoring", "in", "instead of", "into", "is", "it",
        "its", "last", "local", "me", "middle", "mod", "my", "ninth", "not",
        "of", "on", "onto", "or", "out of", "over", "prop", "property",
        "put", "ref", "reference", "repeat", "return", "returning",
        "script", "second", "set", "seventh", "since", "sixth", "some",
        "tell", "tenth", "that", "the", "then", "third", "through", "thru",
        "timeout", "times", "to", "transaction", "true", "try", "until",
        "where", "while", "whose", "with", "without",
    ]

    // Standard Suite expected commands
    private static let standardSuiteCommands: [String: String] = [
        "open": "aevtodoc",
        "quit": "aevtquit",
        "count": "corecnte",
        "exists": "coredoex",
        "make": "corecrel",
        "get": "coregetd",
        "set": "coresetd",
        "close": "coreclos",
        "delete": "coredelo",
    ]

    // Expected application class properties
    private static let expectedAppProperties: [String: String] = [
        "name": "pnam",
        "frontmost": "pisf",
        "version": "vers",
    ]

    func validate() -> [LintFinding] {
        var findings: [LintFinding] = []

        findings.append(contentsOf: checkTermCodeBijection())
        findings.append(contentsOf: checkElementPropertyNameClashes())
        findings.append(contentsOf: checkInheritanceCycles())
        findings.append(contentsOf: checkUndefinedClassReferences())
        findings.append(contentsOf: checkUndefinedTypeReferences())
        findings.append(contentsOf: checkMissingPluralNames())
        findings.append(contentsOf: checkNonStandardWellKnownTerms())
        findings.append(contentsOf: checkUnusedEnumerations())
        findings.append(contentsOf: checkUnusedValueTypes())
        findings.append(contentsOf: checkReservedWordTerms())
        findings.append(contentsOf: checkCommandValidation())
        findings.append(contentsOf: checkStandardSuiteCompliance())
        findings.append(contentsOf: checkDocumentationQuality())
        findings.append(contentsOf: checkCodeValidity())
        findings.append(contentsOf: checkDeprecatedTypeNames())
        findings.append(contentsOf: checkNameFormat())
        findings.append(contentsOf: checkExtendsTargets())
        findings.append(contentsOf: checkRespondsTo())
        findings.append(contentsOf: checkDuplicateIds())
        findings.append(contentsOf: checkHiddenItems())
        findings.append(contentsOf: checkEmptyClasses())

        return findings
    }

    // MARK: - Term ↔ code bijection

    /// A term the dictionary defines, paired with its code.
    private struct Term {
        let kind: String
        let name: String
        let code: String
    }

    /// Every term that owns a code, paired with it. Hidden items are excluded.
    /// Inherited properties aren't re-collected; each class contributes only its
    /// own declarations, so a property genuinely shared across classes appears
    /// once per declaration and dedups by identity below.
    ///
    /// Enumeration names are user-visible: an enumeration is a type, so its name
    /// can appear as a property, parameter, or command-result type. It takes
    /// part in the bijection like any other term.
    ///
    /// Command *parameters* are deliberately omitted. AppleScript scopes
    /// parameter keyword codes to their command — the Standard Suite every app
    /// inherits reuses `kocl`, `insh`, and others across `make`, `move`, and
    /// `count` by design — so parameters don't take part in the dictionary-wide
    /// bijection. A parameter code duplicated *within* one command is still a
    /// defect and is checked in `checkCommandValidation`.
    private func allTerms() -> [Term] {
        var terms: [Term] = []

        for cls in dictionary.classes.values where !cls.hidden {
            terms.append(Term(kind: "class", name: cls.name, code: cls.code))
            for prop in cls.properties where !prop.hidden {
                terms.append(Term(kind: "property", name: prop.name, code: prop.code))
            }
        }
        for enumDef in dictionary.enumerations.values where !enumDef.hidden {
            if let code = enumDef.code {
                terms.append(Term(kind: "enumeration", name: enumDef.name, code: code))
            }
            for enumerator in enumDef.enumerators {
                terms.append(Term(kind: "enumerator", name: enumerator.name, code: enumerator.code))
            }
        }
        for valueType in dictionary.valueTypes.values where !valueType.hidden {
            terms.append(Term(kind: "value type", name: valueType.name, code: valueType.code))
        }
        for recordType in dictionary.recordTypes.values where !recordType.hidden {
            terms.append(Term(kind: "record type", name: recordType.name, code: recordType.code))
            for prop in recordType.properties where !prop.hidden {
                terms.append(Term(kind: "property", name: prop.name, code: prop.code))
            }
        }
        for cmd in dictionary.commands.values where !cmd.hidden {
            terms.append(Term(kind: "command", name: cmd.name, code: cmd.code))
        }

        return terms
    }

    /// A well-formed dictionary maps user-visible terms to codes one-for-one: a
    /// name resolves to a single code, and a code resolves to a single name.
    /// Either ambiguity breaks AppleScript's compiler/decompiler, so both are
    /// reported as errors:
    ///
    ///   - One code → several names: decompiling a raw Apple Event that carries
    ///     the code has no single term to produce (category `ambiguous-code`).
    ///   - One name → several codes: compiling source that uses the name has no
    ///     single code to emit (category `ambiguous-term`).
    ///
    /// The two checks span every term kind together — classes, properties,
    /// enumerations, enumerators, value-types, record-types, and commands — so
    /// collisions are caught across namespaces, not just within one. A term
    /// declared identically in several places (the same name on the same code)
    /// dedups to a single entry and is not flagged. Four- and eight-character
    /// codes share one map but never collide, since their keys differ in length.
    private func checkTermCodeBijection() -> [LintFinding] {
        var findings: [LintFinding] = []

        // code → lowercased name → display label ("kind 'Name'")
        var namesByCode: [String: [String: String]] = [:]
        // lowercased name → code → display label ("kind 'CODE'")
        var codesByName: [String: [String: String]] = [:]
        // lowercased name → original spelling (for the message)
        var spelling: [String: String] = [:]

        for term in allTerms() {
            let lname = term.name.lowercased()
            namesByCode[term.code, default: [:]][lname] = "\(term.kind) '\(term.name)'"
            codesByName[lname, default: [:]][term.code] = "\(term.kind) '\(term.code)'"
            spelling[lname] = term.name
        }

        for (code, labels) in namesByCode where labels.count > 1 {
            let list = labels.keys.sorted().map { labels[$0]! }.joined(separator: ", ")
            findings.append(LintFinding(
                .error, category: "ambiguous-code",
                message: "Code '\(code)' is used by multiple terms: \(list)",
                context: "AppleScript maps a code to one name when decompiling a raw Apple Event; multiple names are ambiguous"
            ))
        }

        // A name→code collision isn't only theoretical: the compiler picks one
        // term and the others become unreachable by that name. BBEdit defines
        // `document` as both a property and an element, and `document of text
        // window 1` compiles to `get «class docu» of «class TxtW» 1` — the
        // class wins, and the property can't be referred to by name at all.
        for (name, labels) in codesByName where labels.count > 1 {
            let list = labels.keys.sorted().map { labels[$0]! }.joined(separator: ", ")
            findings.append(LintFinding(
                .error, category: "ambiguous-term",
                message: "Term '\(spelling[name] ?? name)' is used by multiple codes: \(list)",
                context: "AppleScript maps a name to one code when compiling source; multiple codes are ambiguous"
            ))
        }

        return findings
    }

    // MARK: - Element/property name clashes

    /// Find classes where an element and property share the same name.
    /// Uses a set to deduplicate clashes that appear identically across inherited classes.
    private func checkElementPropertyNameClashes() -> [LintFinding] {
        var findings: [LintFinding] = []
        var seen = Set<String>()  // "className:clashName" to deduplicate

        for cls in dictionary.classes.values {
            let allProps = dictionary.allProperties(for: cls)
            let allElems = dictionary.allElements(for: cls)

            let propNames = Set(allProps.map { $0.name.lowercased() })
            for elem in allElems {
                if let elemClass = dictionary.findClass(elem.type) {
                    let names = [elemClass.name.lowercased(), elemClass.pluralName?.lowercased()].compactMap { $0 }
                    for name in names {
                        if propNames.contains(name) {
                            let key = "\(cls.name.lowercased()):\(name)"
                            guard seen.insert(key).inserted else { continue }
                            findings.append(LintFinding(
                                .warning, category: "name-clash",
                                message: "'\(name)' is both an element and a property in class '\(cls.name)'"
                            ))
                        }
                    }
                }
            }
        }

        return findings
    }

    // MARK: - Inheritance cycles

    private func checkInheritanceCycles() -> [LintFinding] {
        var findings: [LintFinding] = []

        for cls in dictionary.classes.values {
            var visited = Set<String>()
            var current: ClassDef? = cls
            while let c = current {
                let key = c.name.lowercased()
                if !visited.insert(key).inserted {
                    findings.append(LintFinding(
                        .error, category: "inheritance-cycle",
                        message: "Inheritance cycle detected involving class '\(cls.name)'"
                    ))
                    break
                }
                if let inherits = c.inherits {
                    current = dictionary.findClass(inherits)
                } else {
                    current = nil
                }
            }
        }

        return findings
    }

    // MARK: - Undefined class references in containment

    private func checkUndefinedClassReferences() -> [LintFinding] {
        var findings: [LintFinding] = []

        for cls in dictionary.classes.values {
            for elem in cls.elements {
                if dictionary.findClass(elem.type) == nil {
                    findings.append(LintFinding(
                        .error, category: "undefined-class",
                        message: "Element type '\(elem.type)' in class '\(cls.name)' is not defined"
                    ))
                }
            }
            if let inherits = cls.inherits, dictionary.findClass(inherits) == nil {
                findings.append(LintFinding(
                    .warning, category: "undefined-class",
                    message: "Class '\(cls.name)' inherits from undefined class '\(inherits)'"
                ))
            }
        }

        return findings
    }

    // MARK: - Undefined type references on properties

    private func checkUndefinedTypeReferences() -> [LintFinding] {
        var findings: [LintFinding] = []

        // Built-in types that don't need SDEF definitions
        let builtinTypes: Set<String> = [
            "text", "integer", "real", "number", "boolean", "date",
            "file", "point", "rectangle", "color", "rgb color",
            "alias", "any", "specifier", "location specifier",
            "record", "list", "type", "missing value", "data",
            "property", "reference", "handler",
        ]

        for cls in dictionary.classes.values {
            for prop in cls.properties {
                guard let type = prop.type else { continue }
                // Decompose `list of X` and `A | B` / `A / B` composite types
                // into their base names before checking each one.
                for name in ScriptingDictionary.componentTypeNames(of: type) {
                    let lower = name.lowercased()
                    if builtinTypes.contains(lower) { continue }
                    // Deprecated primitive names are reported by
                    // checkDeprecatedTypeNames(), not as undefined types.
                    if Self.deprecatedTypeNames[lower] != nil { continue }
                    if dictionary.findClass(name) != nil { continue }
                    if dictionary.findEnumeration(name) != nil { continue }
                    if dictionary.findRecordType(name) != nil { continue }
                    if dictionary.findValueType(name) != nil { continue }
                    if systemTypes.isSystemType(name) { continue }
                    // A raw four-character OSType code (e.g. Finder's "ICN#",
                    // "il32") is a valid type reference with no named class, so
                    // it isn't a defect.
                    if isRawTypeCode(name) { continue }
                    findings.append(LintFinding(
                        .info, category: "undefined-type",
                        message: "Property '\(prop.name)' in class '\(cls.name)' has type '\(name)' which is not defined in the SDEF",
                        context: "Not defined in this SDEF or any system SDEF"
                    ))
                }
            }
        }

        return findings
    }

    // MARK: - Missing plural names

    private func checkMissingPluralNames() -> [LintFinding] {
        var findings: [LintFinding] = []

        // Find classes that are used as elements
        var usedAsElement = Set<String>()
        for cls in dictionary.classes.values {
            for elem in cls.elements {
                usedAsElement.insert(elem.type.lowercased())
            }
        }

        for cls in dictionary.classes.values {
            guard usedAsElement.contains(cls.name.lowercased()) && cls.pluralName == nil else { continue }

            // SDEF defaults to appending "s" when no plural is specified.
            // Only warn when that naive default would produce incorrect English.
            let name = cls.name.lowercased()
            if naiveAppendSIsCorrect(name) {
                findings.append(LintFinding(
                    .info, category: "missing-plural",
                    message: "Class '\(cls.name)' has no explicit plural (defaults to '\(cls.name)s')"
                ))
            } else {
                findings.append(LintFinding(
                    .warning, category: "missing-plural",
                    message: "Class '\(cls.name)' is used as an element but has no plural name; default '\(cls.name)s' is likely incorrect"
                ))
            }
        }

        return findings
    }

    /// Check whether simply appending "s" to a name produces a reasonable English plural.
    /// Returns false for names where the naive rule would be wrong.
    private func naiveAppendSIsCorrect(_ name: String) -> Bool {
        // Only check the last word for multi-word names (e.g. "settings set" → check "set")
        let lastWord = name.components(separatedBy: " ").last ?? name

        // Irregular nouns where appending "s" is wrong
        let irregulars: Set<String> = [
            "child", "person", "man", "woman", "mouse", "goose",
            "foot", "tooth", "ox", "die", "index", "matrix",
            "vertex", "axis", "crisis", "thesis", "datum", "medium",
            "criterion", "phenomenon", "stimulus", "focus", "cactus",
            "radius", "fungus", "nucleus", "syllabus", "analysis",
            "basis", "diagnosis", "synopsis",
        ]
        if irregulars.contains(lastWord) { return false }

        // Words ending in s, x, z, ch, sh need "es" not just "s"
        if lastWord.hasSuffix("s") || lastWord.hasSuffix("x") || lastWord.hasSuffix("z")
            || lastWord.hasSuffix("ch") || lastWord.hasSuffix("sh") {
            return false
        }

        // Words ending in consonant + "y" need "ies" (e.g. "reply" → "replies")
        // But vowel + "y" is fine (e.g. "key" → "keys", "day" → "days")
        if lastWord.hasSuffix("y") && lastWord.count >= 2 {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let beforeY = lastWord[lastWord.index(lastWord.endIndex, offsetBy: -2)]
            if !vowels.contains(beforeY) {
                return false
            }
        }

        // Words ending in "f" or "fe" often need "ves" (e.g. "leaf" → "leaves")
        if lastWord.hasSuffix("fe") || (lastWord.hasSuffix("f") && !lastWord.hasSuffix("ff")) {
            return false
        }

        // Words ending in "o" preceded by a consonant often need "es"
        // (e.g. "hero" → "heroes") but many exceptions exist (photo, piano)
        // Too ambiguous to flag — let it pass

        // Default: appending "s" is likely correct
        return true
    }

    // MARK: - Non-standard terms for well-known codes

    private func checkNonStandardWellKnownTerms() -> [LintFinding] {
        var findings: [LintFinding] = []

        // This check is only about a *consistent* non-standard choice: a
        // standard Apple Event code given a single non-standard name throughout
        // the dictionary (e.g. always calling `pnam` "title"). That's an
        // internally coherent convention — unconventional, but it decompiles
        // unambiguously — so it's reported as informational.
        //
        // The harmful case, where one code is mapped to several names, is
        // ambiguous for AppleScript's decompiler and is reported as an error by
        // checkAmbiguousCodeNames(). We skip those codes here to avoid
        // double-reporting.
        //
        // Names are gathered case-insensitively (AppleScript terms are
        // case-insensitive) while preserving the dictionary's own spelling.
        var namesByCode: [String: [String: String]] = [:]
        for cls in dictionary.classes.values {
            for prop in cls.properties {
                guard Self.wellKnownCodes[prop.code] != nil else { continue }
                namesByCode[prop.code, default: [:]][prop.name.lowercased()] = prop.name
            }
        }

        for cls in dictionary.classes.values {
            for prop in cls.properties {
                guard let expectedName = Self.wellKnownCodes[prop.code] else { continue }
                if prop.name.lowercased() == expectedName.lowercased() { continue }
                // Ambiguous mappings are handled (as errors) elsewhere.
                if (namesByCode[prop.code]?.count ?? 0) > 1 { continue }

                findings.append(LintFinding(
                    .info, category: "non-standard-term",
                    message: "Property code '\(prop.code)' in class '\(cls.name)' uses name '\(prop.name)' instead of standard '\(expectedName)'"
                ))
            }
        }

        return findings
    }

    // MARK: - Unused enumerations and value-types

    /// Every type-name component referenced anywhere a type may appear: class
    /// and record-type properties, and command direct-parameters, parameters,
    /// and results. Composite forms (`list of X`, `A | B` / `A / B`) are
    /// decomposed so a type referenced only via such a form is still counted.
    /// Returned strings may be names or four-character codes; the caller
    /// resolves them through the code-aware `find…` helpers.
    private func referencedTypeComponents() -> [String] {
        var components: [String] = []
        func record(_ type: String?) {
            guard let type else { return }
            components.append(contentsOf: ScriptingDictionary.componentTypeNames(of: type))
        }
        for cls in dictionary.classes.values {
            for prop in cls.properties { record(prop.type) }
        }
        for rec in dictionary.recordTypes.values {
            for prop in rec.properties { record(prop.type) }
        }
        for cmd in dictionary.commands.values {
            record(cmd.directParameter?.type)
            for param in cmd.parameters { record(param.type) }
            record(cmd.result?.type)
        }
        return components
    }

    private func checkUnusedEnumerations() -> [LintFinding] {
        var findings: [LintFinding] = []

        // Resolve each referenced component through `findEnumeration`, which
        // follows both name and four-character-code references (see sdef(5)),
        // so an enum referenced solely by its code still counts as used.
        var referencedEnums = Set<String>()
        for name in referencedTypeComponents() {
            if let enumDef = dictionary.findEnumeration(name) {
                referencedEnums.insert(enumDef.name.lowercased())
            }
        }

        for enumDef in dictionary.enumerations.values {
            if enumDef.hidden { continue }
            if !referencedEnums.contains(enumDef.name.lowercased()) {
                findings.append(LintFinding(
                    .info, category: "unused-enum",
                    message: "Enumeration '\(enumDef.name)' is not referenced by any property or command"
                ))
            }
        }

        return findings
    }

    private func checkUnusedValueTypes() -> [LintFinding] {
        var findings: [LintFinding] = []

        // As with enumerations, resolve references through the code-aware
        // `findValueType` so a value-type referenced only by its code counts.
        var referencedValueTypes = Set<String>()
        for name in referencedTypeComponents() {
            if let valueDef = dictionary.findValueType(name) {
                referencedValueTypes.insert(valueDef.name.lowercased())
            }
        }

        for valueDef in dictionary.valueTypes.values {
            if valueDef.hidden { continue }
            if !referencedValueTypes.contains(valueDef.name.lowercased()) {
                findings.append(LintFinding(
                    .info, category: "unused-value-type",
                    message: "Value type '\(valueDef.name)' is not referenced by any property or command"
                ))
            }
        }

        return findings
    }

    // MARK: - Reserved word terms

    private func checkReservedWordTerms() -> [LintFinding] {
        var findings: [LintFinding] = []

        for cls in dictionary.classes.values {
            if Self.reservedWords.contains(cls.name.lowercased()) {
                findings.append(LintFinding(
                    .warning, category: "reserved-word",
                    message: "Class name '\(cls.name)' is an AppleScript reserved word"
                ))
            }
            for prop in cls.properties {
                if Self.reservedWords.contains(prop.name.lowercased()) {
                    findings.append(LintFinding(
                        .info, category: "reserved-word",
                        message: "Property '\(prop.name)' in class '\(cls.name)' is an AppleScript reserved word",
                        context: "May require 'of' syntax to disambiguate"
                    ))
                }
            }
        }

        return findings
    }

    // MARK: - Command validation

    private func checkCommandValidation() -> [LintFinding] {
        var findings: [LintFinding] = []

        // Built-in types that are valid for command parameters
        let builtinTypes: Set<String> = [
            "text", "integer", "real", "number", "boolean", "date",
            "file", "point", "rectangle", "color", "rgb color",
            "alias", "any", "specifier", "location specifier",
            "record", "list", "type", "missing value", "data",
            "property", "reference", "handler",
        ]

        // Cross-term code/name collisions — including command codes and
        // parameter codes — are reported by checkTermCodeBijection(). The check
        // below additionally catches a parameter code repeated *within* a single
        // command (a literal duplicate parameter), which the bijection's
        // identity dedup would otherwise pass over.

        // Check command parameter codes for duplicates within a command
        for cmd in dictionary.commands.values {
            if cmd.hidden { continue }
            var paramCodes: [String: [String]] = [:]
            for param in cmd.parameters {
                if let code = param.code {
                    paramCodes[code, default: []].append(param.name ?? "(unnamed)")
                }
            }
            for (code, names) in paramCodes where names.count > 1 {
                findings.append(LintFinding(
                    .error, category: "duplicate-param-code",
                    message: "Parameter code '\(code)' used multiple times in command '\(cmd.name)': \(names.joined(separator: ", "))"
                ))
            }

            // Check for undefined parameter types
            let allParamTypes = cmd.parameters.compactMap(\.type) +
                [cmd.directParameter?.type, cmd.result?.type].compactMap { $0 }
            for type in allParamTypes {
                // Decompose `list of X` and `A | B` / `A / B` composite types
                // into their base names before checking each one.
                for name in ScriptingDictionary.componentTypeNames(of: type) {
                    let lower = name.lowercased()
                    if builtinTypes.contains(lower) { continue }
                    // Deprecated primitive names are reported by
                    // checkDeprecatedTypeNames(), not as undefined types.
                    if Self.deprecatedTypeNames[lower] != nil { continue }
                    if dictionary.findClass(name) != nil { continue }
                    if dictionary.findEnumeration(name) != nil { continue }
                    if dictionary.findRecordType(name) != nil { continue }
                    if dictionary.findValueType(name) != nil { continue }
                    if systemTypes.isSystemType(name) { continue }
                    // A raw four-character OSType code is a valid type
                    // reference with no named class, so it isn't a defect.
                    if isRawTypeCode(name) { continue }
                    findings.append(LintFinding(
                        .info, category: "undefined-command-type",
                        message: "Command '\(cmd.name)' references type '\(name)' which is not defined in the SDEF",
                        context: "Not defined in this SDEF or any system SDEF"
                    ))
                }
            }
        }

        return findings
    }

    // MARK: - Standard Suite compliance

    private func checkStandardSuiteCompliance() -> [LintFinding] {
        var findings: [LintFinding] = []

        // Check for application class
        guard let appClass = dictionary.findClass("application") else {
            findings.append(LintFinding(
                .error, category: "standard-suite",
                message: "No 'application' class defined"
            ))
            return findings
        }

        // Check expected application properties
        let allProps = dictionary.allProperties(for: appClass)
        for (propName, expectedCode) in Self.expectedAppProperties {
            if let prop = allProps.first(where: { $0.name.lowercased() == propName }) {
                if prop.code != expectedCode {
                    findings.append(LintFinding(
                        .warning, category: "standard-suite",
                        message: "Application property '\(propName)' has code '\(prop.code)' instead of expected '\(expectedCode)'"
                    ))
                }
            } else {
                findings.append(LintFinding(
                    .info, category: "standard-suite",
                    message: "Application class is missing standard property '\(propName)' (\(expectedCode))"
                ))
            }
        }

        // Check expected application elements (window, document). Only expect
        // an element when the app actually defines the corresponding class — an
        // app with no 'document' class (e.g. a browser like Google Chrome) is
        // not expected to expose 'document' elements.
        let allElems = dictionary.allElements(for: appClass)
        let elemTypes = Set(allElems.map { $0.type.lowercased() })
        for typeName in ["window", "document"] {
            guard dictionary.findClass(typeName) != nil else { continue }
            if !elemTypes.contains(typeName) {
                findings.append(LintFinding(
                    .info, category: "standard-suite",
                    message: "Application class does not declare '\(typeName)' elements"
                ))
            }
        }

        // Check for standard commands
        for (cmdName, expectedCode) in Self.standardSuiteCommands {
            if let cmd = dictionary.commands[cmdName] {
                if cmd.code != expectedCode {
                    findings.append(LintFinding(
                        .warning, category: "standard-suite",
                        message: "Command '\(cmdName)' has code '\(cmd.code)' instead of expected '\(expectedCode)'"
                    ))
                }
            }
            // Not all apps need all standard commands, so missing ones are not flagged
        }

        return findings
    }

    // MARK: - Documentation quality

    private func checkDocumentationQuality() -> [LintFinding] {
        var findings: [LintFinding] = []

        var classesWithoutDesc = 0
        var classesTotal = 0
        for cls in dictionary.classes.values {
            if cls.hidden { continue }
            classesTotal += 1
            if cls.description == nil || cls.description!.isEmpty {
                classesWithoutDesc += 1
            }
        }

        var commandsWithoutDesc = 0
        var commandsTotal = 0
        for cmd in dictionary.commands.values {
            if cmd.hidden { continue }
            commandsTotal += 1
            if cmd.description == nil || cmd.description!.isEmpty {
                commandsWithoutDesc += 1
            }
        }

        if classesTotal > 0 && classesWithoutDesc > 0 {
            let pct = (classesWithoutDesc * 100) / classesTotal
            findings.append(LintFinding(
                .info, category: "documentation",
                message: "\(classesWithoutDesc) of \(classesTotal) classes (\(pct)%) have no description"
            ))
        }

        if commandsTotal > 0 && commandsWithoutDesc > 0 {
            let pct = (commandsWithoutDesc * 100) / commandsTotal
            findings.append(LintFinding(
                .info, category: "documentation",
                message: "\(commandsWithoutDesc) of \(commandsTotal) commands (\(pct)%) have no description"
            ))
        }

        return findings
    }

    // MARK: - Code validity

    /// Check that every code is the right length: four bytes for terms, eight
    /// for command (verb) codes. The hexadecimal `0x…` spelling the spec allows
    /// (e.g. `0x00000001`, used when a byte isn't printable) is decoded first,
    /// so it isn't mistaken for an over-long literal.
    private func checkCodeValidity() -> [LintFinding] {
        var findings: [LintFinding] = []

        func check(_ code: String, expected: Int, _ describe: () -> String) {
            let canonical = ScriptingDictionary.canonicalCode(code)
            guard let data = canonical.data(using: .macOSRoman), data.count != expected else { return }
            findings.append(LintFinding(
                .error, category: "invalid-code",
                message: "\(describe()) has invalid code '\(code)' (\(data.count) bytes, expected \(expected))"
            ))
        }

        for cls in dictionary.classes.values {
            check(cls.code, expected: 4) { "Class '\(cls.name)'" }
            for prop in cls.properties {
                check(prop.code, expected: 4) { "Property '\(prop.name)' in class '\(cls.name)'" }
            }
        }
        for enumDef in dictionary.enumerations.values {
            if let code = enumDef.code {
                check(code, expected: 4) { "Enumeration '\(enumDef.name)'" }
            }
            for enumerator in enumDef.enumerators {
                check(enumerator.code, expected: 4) { "Enumerator '\(enumerator.name)' in enumeration '\(enumDef.name)'" }
            }
        }
        for valueType in dictionary.valueTypes.values {
            check(valueType.code, expected: 4) { "Value type '\(valueType.name)'" }
        }
        for recordType in dictionary.recordTypes.values {
            check(recordType.code, expected: 4) { "Record type '\(recordType.name)'" }
            for prop in recordType.properties {
                check(prop.code, expected: 4) { "Property '\(prop.name)' in record type '\(recordType.name)'" }
            }
        }
        for cmd in dictionary.commands.values {
            if cmd.hidden { continue }
            check(cmd.code, expected: 8) { "Command '\(cmd.name)'" }
            for param in cmd.parameters {
                if let name = param.name, let code = param.code {
                    check(code, expected: 4) { "Parameter '\(name)' of command '\(cmd.name)'" }
                }
            }
        }

        return findings
    }

    // MARK: - Deprecated primitive type names

    /// Primitive types renamed in Mac OS X 10.4 (see sdef(5) History). The old
    /// names are deprecated; a modern dictionary should use the new ones.
    private static let deprecatedTypeNames: [String: String] = [
        "string": "text",
        "object": "specifier",
        "location": "location specifier",
    ]

    private func checkDeprecatedTypeNames() -> [LintFinding] {
        var findings: [LintFinding] = []

        func check(_ type: String?, _ describe: () -> String) {
            guard let type else { return }
            for component in ScriptingDictionary.componentTypeNames(of: type) {
                guard let modern = Self.deprecatedTypeNames[component.lowercased()] else { continue }
                findings.append(LintFinding(
                    .warning, category: "deprecated-type",
                    message: "\(describe()) uses deprecated type '\(component)'; use '\(modern)' instead",
                    context: "Primitive type renamed in Mac OS X 10.4"
                ))
            }
        }

        for cls in dictionary.classes.values {
            for prop in cls.properties {
                check(prop.type) { "Property '\(prop.name)' in class '\(cls.name)'" }
            }
        }
        for recordType in dictionary.recordTypes.values {
            for prop in recordType.properties {
                check(prop.type) { "Property '\(prop.name)' in record type '\(recordType.name)'" }
            }
        }
        for cmd in dictionary.commands.values {
            check(cmd.directParameter?.type) { "Direct parameter of command '\(cmd.name)'" }
            for param in cmd.parameters {
                check(param.type) { "Parameter '\(param.name ?? "(unnamed)")' of command '\(cmd.name)'" }
            }
            check(cmd.result?.type) { "Result of command '\(cmd.name)'" }
        }

        return findings
    }

    // MARK: - Terminology name format

    /// sdef(5) says a terminology name is one or more C identifiers
    /// (`[A-Za-z_][A-Za-z0-9_]*`) separated by single spaces. Taken literally
    /// that bars a word from starting with a digit — but Apple's own
    /// dictionaries use such words pervasively and AppleScript accepts them
    /// (Finder's `large 8 bit mask`, Music's `band 1`, `Numbers 09`). Flagging
    /// those is noise, so we relax the rule to permit digit-leading words: a
    /// name must begin with a letter or underscore and otherwise consist of
    /// space-separated alphanumeric/underscore words. What this still catches is
    /// a name with a character that can't be tokenized as a term at all — a
    /// hyphen (`desktop-object`), `#` (`ICN#`), or `&` (`Name & Extension`).
    private static let nameFormat = try! NSRegularExpression(
        pattern: "^[A-Za-z_][A-Za-z0-9_]*( [A-Za-z0-9_]+)*$"
    )

    private static func isWellFormedName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return nameFormat.firstMatch(in: name, range: range) != nil
    }

    private func checkNameFormat() -> [LintFinding] {
        var findings: [LintFinding] = []

        func check(_ name: String, _ describe: () -> String) {
            guard !name.isEmpty, !Self.isWellFormedName(name) else { return }
            findings.append(LintFinding(
                .warning, category: "invalid-name",
                message: "\(describe()) name '\(name)' is not a valid AppleScript term",
                context: "sdef(5), Common Attributes \u{2192} name: \"Names must be one or more C identifiers (i.e., [A-Za-z_][A-Za-z0-9_]*) separated by a space.\""
            ))
        }

        for cls in dictionary.classes.values {
            check(cls.name) { "Class" }
            for prop in cls.properties { check(prop.name) { "Property in class '\(cls.name)':" } }
        }
        for recordType in dictionary.recordTypes.values {
            check(recordType.name) { "Record type" }
            for prop in recordType.properties { check(prop.name) { "Property in record type '\(recordType.name)':" } }
        }
        for valueType in dictionary.valueTypes.values {
            check(valueType.name) { "Value type" }
        }
        for enumDef in dictionary.enumerations.values {
            check(enumDef.name) { "Enumeration" }
            for enumerator in enumDef.enumerators { check(enumerator.name) { "Enumerator in '\(enumDef.name)':" } }
        }
        for cmd in dictionary.commands.values {
            check(cmd.name) { "Command" }
            for param in cmd.parameters {
                if let name = param.name { check(name) { "Parameter of command '\(cmd.name)':" } }
            }
        }

        return findings
    }

    // MARK: - class-extension targets

    /// Every `class-extension` must extend a class defined somewhere in the
    /// dictionary. A dangling `extends` silently drops the extension's members
    /// (the merge no-ops), so the added properties and elements simply vanish.
    /// The target is resolved against the fully-parsed dictionary, so an
    /// extension that textually precedes its target class isn't a false
    /// positive.
    private func checkExtendsTargets() -> [LintFinding] {
        var findings: [LintFinding] = []
        for ext in dictionary.classExtensions {
            if dictionary.findClass(ext.extends) == nil {
                findings.append(LintFinding(
                    .error, category: "undefined-extends",
                    message: "Class-extension extends undefined class '\(ext.extends)'",
                    context: "Its added properties and elements are silently dropped"
                ))
            }
        }
        return findings
    }

    // MARK: - responds-to verbs

    /// A class's `responds-to` must name a verb (command) defined in the
    /// dictionary, by name or by id. A dangling reference documents a command
    /// the application doesn't actually declare.
    private func checkRespondsTo() -> [LintFinding] {
        var findings: [LintFinding] = []
        for cls in dictionary.classes.values where !cls.hidden {
            for verb in cls.respondsTo {
                if dictionary.findCommand(byNameOrId: verb) == nil {
                    findings.append(LintFinding(
                        .error, category: "undefined-responds-to",
                        message: "Class '\(cls.name)' responds-to undefined command '\(verb)'"
                    ))
                }
            }
        }
        return findings
    }

    // MARK: - id uniqueness

    /// sdef(5): an `id` is "a unique identifier for the element." A duplicate
    /// breaks the disambiguation `responds-to` and `xref` rely on.
    private func checkDuplicateIds() -> [LintFinding] {
        var findings: [LintFinding] = []

        // id → labels of the elements carrying it.
        var byId: [String: [String]] = [:]
        func record(_ id: String?, _ label: String) {
            guard let id else { return }
            byId[id, default: []].append(label)
        }

        for cls in dictionary.classes.values { record(cls.id, "class '\(cls.name)'") }
        for recordType in dictionary.recordTypes.values { record(recordType.id, "record type '\(recordType.name)'") }
        for valueType in dictionary.valueTypes.values { record(valueType.id, "value type '\(valueType.name)'") }
        for enumDef in dictionary.enumerations.values { record(enumDef.id, "enumeration '\(enumDef.name)'") }
        for cmd in dictionary.commands.values { record(cmd.id, "command '\(cmd.name)'") }
        for ext in dictionary.classExtensions { record(ext.id, "class-extension of '\(ext.extends)'") }

        for (id, labels) in byId where labels.count > 1 {
            findings.append(LintFinding(
                .error, category: "duplicate-id",
                message: "id '\(id)' is used by multiple elements: \(labels.sorted().joined(separator: ", "))",
                context: "sdef(5): an id must be unique"
            ))
        }
        return findings
    }

    // MARK: - Hidden items audit

    private func checkHiddenItems() -> [LintFinding] {
        var findings: [LintFinding] = []

        let hiddenClasses = dictionary.classes.values.filter(\.hidden)
        let hiddenCommands = dictionary.commands.values.filter(\.hidden)

        var hiddenPropCount = 0
        for cls in dictionary.classes.values {
            hiddenPropCount += cls.properties.filter(\.hidden).count
        }

        if !hiddenClasses.isEmpty || hiddenPropCount > 0 || !hiddenCommands.isEmpty {
            var parts: [String] = []
            if !hiddenClasses.isEmpty { parts.append("\(hiddenClasses.count) classes") }
            if hiddenPropCount > 0 { parts.append("\(hiddenPropCount) properties") }
            if !hiddenCommands.isEmpty { parts.append("\(hiddenCommands.count) commands") }
            findings.append(LintFinding(
                .info, category: "hidden-items",
                message: "Hidden items: \(parts.joined(separator: ", "))"
            ))
        }

        return findings
    }

    // MARK: - Empty classes

    private func checkEmptyClasses() -> [LintFinding] {
        var findings: [LintFinding] = []

        for cls in dictionary.classes.values {
            if cls.hidden { continue }
            if cls.name.lowercased() == "application" { continue }

            let allProps = dictionary.allProperties(for: cls).filter { !$0.hidden }
            let allElems = dictionary.allElements(for: cls).filter { !$0.hidden }

            if allProps.isEmpty && allElems.isEmpty {
                findings.append(LintFinding(
                    .info, category: "empty-class",
                    message: "Class '\(cls.name)' has no visible properties or elements"
                ))
            }
        }

        return findings
    }

    // MARK: - Reachability

    /// Check that all non-hidden classes are reachable from the application root.
    func validateReachability(pathFinder: SDEFPathFinder, maxDepth: Int) -> [LintFinding] {
        var findings: [LintFinding] = []

        // Classes referenced as a command's result/parameter type, or as the
        // type of another class's property, are reached by invoking a command
        // or reading a property rather than through element containment, so the
        // path finder wouldn't locate them. Collect them as exempt.
        var typeReferenced = Set<String>()
        func recordType(_ type: String?) {
            guard let type else { return }
            for name in ScriptingDictionary.componentTypeNames(of: type) {
                typeReferenced.insert(name.lowercased())
            }
        }
        for cmd in dictionary.commands.values {
            recordType(cmd.result?.type)
            recordType(cmd.directParameter?.type)
            for param in cmd.parameters { recordType(param.type) }
        }
        for cls in dictionary.classes.values {
            for prop in cls.properties { recordType(prop.type) }
        }

        // Track why each class is reachable so we can surface the one inference
        // that is a genuine presumption: a subclass reached only through a
        // parent's accessor (see the downward case below). The first reason a
        // class is reached wins.
        enum ReachReason {
            case direct                          // path finder, root, or type reference
            case inheritedDown(parent: String)   // subclass reached via a reachable parent's accessor
            case inheritedUp                     // superclass reached via a reachable subclass instance
            case containment                     // element/property of a reachable class
        }
        var reason: [String: ReachReason] = [:]
        @discardableResult
        func mark(_ name: String, _ r: ReachReason) -> Bool {
            let key = name.lowercased()
            if reason[key] != nil { return false }
            reason[key] = r
            return true
        }
        func isReachable(_ name: String) -> Bool { reason[name.lowercased()] != nil }

        // Seed with the application root, classes referenced as command/property
        // types, and every class the path finder can locate via element/property
        // containment within the depth limit.
        mark("application", .direct)
        for name in typeReferenced { mark(name, .direct) }
        for cls in dictionary.classes.values where !cls.hidden {
            if !pathFinder.findPaths(to: cls.name, maxDepth: maxDepth).isEmpty {
                mark(cls.name, .direct)
            }
        }

        // Close over relationships the literal path finder doesn't follow:
        //   - inheritance down: a parent's element/accessor returns subclass
        //     instances at runtime, so a subclass of a reachable class is
        //     reachable (e.g. BBEdit's 'documents' element yields 'project
        //     document'). This is the presumption we report below.
        //   - inheritance up: an instance of a reachable subclass is also an
        //     instance of each ancestor, so a superclass is reachable too
        //     (e.g. every 'project item' is an 'item').
        //   - containment from a newly-reachable class: the path finder can't
        //     reach a subclass container like 'project document', so it never
        //     indexed the elements/properties it holds ('project item',
        //     'project collection'). Once the container is reachable, they are.
        var changed = true
        while changed {
            changed = false
            for cls in dictionary.classes.values where !cls.hidden {
                if isReachable(cls.name) { continue }
                if let parent = cls.inherits, isReachable(parent) {
                    if mark(cls.name, .inheritedDown(parent: parent)) { changed = true }
                }
            }
            for cls in dictionary.classes.values where isReachable(cls.name) {
                if let parentName = cls.inherits, let parent = dictionary.findClass(parentName) {
                    if mark(parent.name, .inheritedUp) { changed = true }
                }
            }
            for cls in dictionary.classes.values where isReachable(cls.name) {
                for elem in dictionary.allElements(for: cls) where !elem.hidden {
                    if let t = dictionary.findClass(elem.type), !t.hidden, mark(t.name, .containment) {
                        changed = true
                    }
                }
                for prop in dictionary.allProperties(for: cls) where !prop.hidden {
                    guard let pt = prop.type, let t = dictionary.findClass(pt), !t.hidden else { continue }
                    if mark(t.name, .containment) { changed = true }
                }
            }
        }

        for cls in dictionary.classes.values {
            if cls.hidden { continue }
            switch reason[cls.name.lowercased()] {
            case nil:
                findings.append(LintFinding(
                    .warning, category: "unreachable",
                    message: "Class '\(cls.name)' is not reachable from the application root",
                    context: "No containment path found within depth \(maxDepth)"
                ))
            case .inheritedDown(let parent):
                // The class has no accessor of its own; we presume it is obtained
                // through its parent's element, which can return subclass
                // instances at runtime. Worth noting in case the app never
                // actually returns this subclass.
                findings.append(LintFinding(
                    .info, category: "inferred-reachable",
                    message: "Class '\(cls.name)' has no direct containment path; assumed reachable via parent class '\(parent)'",
                    context: "Subclass instances are obtained through the parent's element accessor"
                ))
            default:
                break
            }
        }

        return findings
    }
}
