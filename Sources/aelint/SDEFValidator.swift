import AEQueryLib
import Foundation

struct SDEFValidator {
    let dictionary: ScriptingDictionary
    let appName: String

    // Well-known 4CC codes and their expected standard terms
    private static let wellKnownCodes: [String: String] = [
        "pnam": "name",
        "pcls": "class",
        "ID  ": "id",
        "pALL": "properties",
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

        findings.append(contentsOf: checkDuplicateCodes())
        findings.append(contentsOf: checkElementPropertyNameClashes())
        findings.append(contentsOf: checkInheritanceCycles())
        findings.append(contentsOf: checkUndefinedClassReferences())
        findings.append(contentsOf: checkUndefinedTypeReferences())
        findings.append(contentsOf: checkMissingPluralNames())
        findings.append(contentsOf: checkNonStandardWellKnownTerms())
        findings.append(contentsOf: checkUnusedEnumerations())
        findings.append(contentsOf: checkReservedWordTerms())
        findings.append(contentsOf: checkCommandValidation())
        findings.append(contentsOf: checkStandardSuiteCompliance())
        findings.append(contentsOf: checkDocumentationQuality())
        findings.append(contentsOf: checkCodeValidity())
        findings.append(contentsOf: checkHiddenItems())
        findings.append(contentsOf: checkEmptyClasses())

        return findings
    }

    // MARK: - Duplicate 4CC codes

    /// Find cases where the same 4CC code maps to different terms.
    private func checkDuplicateCodes() -> [LintFinding] {
        var findings: [LintFinding] = []

        // Check class codes
        var classCodes: [String: [String]] = [:]  // code → [class names]
        for cls in dictionary.classes.values {
            classCodes[cls.code, default: []].append(cls.name)
        }
        for (code, names) in classCodes where names.count > 1 {
            findings.append(LintFinding(
                .error, category: "duplicate-code",
                message: "Class code '\(code)' used by multiple classes: \(names.joined(separator: ", "))"
            ))
        }

        // Check property codes within each class
        for cls in dictionary.classes.values {
            let allProps = dictionary.allProperties(for: cls)
            var propCodes: [String: [String]] = [:]
            for prop in allProps {
                propCodes[prop.code, default: []].append(prop.name)
            }
            for (code, names) in propCodes {
                let unique = Array(Set(names))
                if unique.count > 1 {
                    findings.append(LintFinding(
                        .error, category: "duplicate-code",
                        message: "Property code '\(code)' maps to different names in class '\(cls.name)': \(unique.joined(separator: ", "))"
                    ))
                }
            }
        }

        // Check enumerator codes across all enumerations
        var enumCodes: [String: [(enumName: String, valueName: String)]] = [:]
        for enumDef in dictionary.enumerations.values {
            for enumerator in enumDef.enumerators {
                enumCodes[enumerator.code, default: []].append((enumDef.name, enumerator.name))
            }
        }
        for (code, entries) in enumCodes {
            let uniqueNames = Set(entries.map(\.valueName))
            if uniqueNames.count > 1 {
                let detail = entries.map { "\($0.enumName).\($0.valueName)" }.joined(separator: ", ")
                findings.append(LintFinding(
                    .warning, category: "duplicate-code",
                    message: "Enumerator code '\(code)' used with different names: \(detail)"
                ))
            }
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
                let lower = type.lowercased()
                if builtinTypes.contains(lower) { continue }
                if dictionary.findClass(type) != nil { continue }
                if dictionary.findEnumeration(type) != nil { continue }
                findings.append(LintFinding(
                    .info, category: "undefined-type",
                    message: "Property '\(prop.name)' in class '\(cls.name)' has type '\(type)' which is not defined in the SDEF",
                    context: "May be a system-defined type"
                ))
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

        for cls in dictionary.classes.values {
            let allProps = dictionary.allProperties(for: cls)
            for prop in allProps {
                if let expectedName = Self.wellKnownCodes[prop.code] {
                    if prop.name.lowercased() != expectedName.lowercased() {
                        findings.append(LintFinding(
                            .warning, category: "non-standard-term",
                            message: "Property code '\(prop.code)' in class '\(cls.name)' uses name '\(prop.name)' instead of standard '\(expectedName)'"
                        ))
                    }
                }
            }
        }

        return findings
    }

    // MARK: - Unused enumerations

    private func checkUnusedEnumerations() -> [LintFinding] {
        var findings: [LintFinding] = []

        // Collect all types referenced by properties and command parameters
        var referencedTypes = Set<String>()
        for cls in dictionary.classes.values {
            for prop in cls.properties {
                if let type = prop.type {
                    referencedTypes.insert(type.lowercased())
                }
            }
        }
        for cmd in dictionary.commands.values {
            if let type = cmd.directParameter?.type {
                referencedTypes.insert(type.lowercased())
            }
            for param in cmd.parameters {
                if let type = param.type {
                    referencedTypes.insert(type.lowercased())
                }
            }
            if let type = cmd.result?.type {
                referencedTypes.insert(type.lowercased())
            }
        }

        for enumDef in dictionary.enumerations.values {
            if !referencedTypes.contains(enumDef.name.lowercased()) {
                findings.append(LintFinding(
                    .info, category: "unused-enum",
                    message: "Enumeration '\(enumDef.name)' is not referenced by any property or command"
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

        // Check for duplicate command codes
        var commandCodes: [String: [String]] = [:]  // code → [command names]
        for cmd in dictionary.commands.values {
            if cmd.hidden { continue }
            commandCodes[cmd.code, default: []].append(cmd.name)
        }
        for (code, names) in commandCodes where names.count > 1 {
            findings.append(LintFinding(
                .warning, category: "duplicate-command-code",
                message: "Command code '\(code)' used by multiple commands: \(names.joined(separator: ", "))"
            ))
        }

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
                let lower = type.lowercased()
                if builtinTypes.contains(lower) { continue }
                if dictionary.findClass(type) != nil { continue }
                if dictionary.findEnumeration(type) != nil { continue }
                findings.append(LintFinding(
                    .info, category: "undefined-command-type",
                    message: "Command '\(cmd.name)' references type '\(type)' which is not defined in the SDEF",
                    context: "May be a system-defined type"
                ))
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

        // Check expected application elements (window, document)
        let allElems = dictionary.allElements(for: appClass)
        let elemTypes = Set(allElems.map { $0.type.lowercased() })
        if !elemTypes.contains("window") {
            findings.append(LintFinding(
                .info, category: "standard-suite",
                message: "Application class does not declare 'window' elements"
            ))
        }
        if !elemTypes.contains("document") {
            findings.append(LintFinding(
                .info, category: "standard-suite",
                message: "Application class does not declare 'document' elements"
            ))
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

    /// Check that 4CC codes have exactly 4 bytes and command codes have 8.
    private func checkCodeValidity() -> [LintFinding] {
        var findings: [LintFinding] = []

        for cls in dictionary.classes.values {
            if let data = cls.code.data(using: .macOSRoman), data.count != 4 {
                findings.append(LintFinding(
                    .error, category: "invalid-code",
                    message: "Class '\(cls.name)' has invalid code '\(cls.code)' (\(data.count) bytes, expected 4)"
                ))
            }
            for prop in cls.properties {
                if let data = prop.code.data(using: .macOSRoman), data.count != 4 {
                    findings.append(LintFinding(
                        .error, category: "invalid-code",
                        message: "Property '\(prop.name)' in class '\(cls.name)' has invalid code '\(prop.code)' (\(data.count) bytes, expected 4)"
                    ))
                }
            }
        }

        for cmd in dictionary.commands.values {
            if cmd.hidden { continue }
            if let data = cmd.code.data(using: .macOSRoman), data.count != 8 {
                findings.append(LintFinding(
                    .error, category: "invalid-code",
                    message: "Command '\(cmd.name)' has invalid event code '\(cmd.code)' (\(data.count) bytes, expected 8)"
                ))
            }
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

        for cls in dictionary.classes.values {
            if cls.hidden { continue }
            if cls.name.lowercased() == "application" { continue }

            let paths = pathFinder.findPaths(to: cls.name, maxDepth: maxDepth)
            if paths.isEmpty {
                findings.append(LintFinding(
                    .warning, category: "unreachable",
                    message: "Class '\(cls.name)' is not reachable from the application root",
                    context: "No containment path found within depth \(maxDepth)"
                ))
            }
        }

        return findings
    }
}
