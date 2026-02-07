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
    private func checkElementPropertyNameClashes() -> [LintFinding] {
        var findings: [LintFinding] = []

        for cls in dictionary.classes.values {
            let allProps = dictionary.allProperties(for: cls)
            let allElems = dictionary.allElements(for: cls)

            let propNames = Set(allProps.map { $0.name.lowercased() })
            for elem in allElems {
                // Element type name or plural name
                if let elemClass = dictionary.findClass(elem.type) {
                    let names = [elemClass.name.lowercased(), elemClass.pluralName?.lowercased()].compactMap { $0 }
                    for name in names {
                        if propNames.contains(name) {
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
            if usedAsElement.contains(cls.name.lowercased()) && cls.pluralName == nil {
                findings.append(LintFinding(
                    .warning, category: "missing-plural",
                    message: "Class '\(cls.name)' is used as an element but has no plural name"
                ))
            }
        }

        return findings
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

        // Collect all types referenced by properties
        var referencedTypes = Set<String>()
        for cls in dictionary.classes.values {
            for prop in cls.properties {
                if let type = prop.type {
                    referencedTypes.insert(type.lowercased())
                }
            }
        }

        for enumDef in dictionary.enumerations.values {
            if !referencedTypes.contains(enumDef.name.lowercased()) {
                findings.append(LintFinding(
                    .info, category: "unused-enum",
                    message: "Enumeration '\(enumDef.name)' is not referenced by any property"
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
