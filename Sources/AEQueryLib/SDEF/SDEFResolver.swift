import Foundation

public struct ResolvedQuery {
    public let appName: String
    public let steps: [ResolvedStep]

    public init(appName: String, steps: [ResolvedStep]) {
        self.appName = appName
        self.steps = steps
    }
}

public struct ResolvedStep: Equatable {
    public enum Kind: Equatable {
        case element
        case property
    }

    public let name: String
    public let kind: Kind
    public let code: String           // 4-char code
    public let predicates: [Predicate]
    public let className: String?     // the class this element refers to, for chaining
    public let usedPluralForm: Bool   // true when the user wrote the plural name (e.g. "windows" vs "window")

    public init(name: String, kind: Kind, code: String, predicates: [Predicate] = [], className: String? = nil, usedPluralForm: Bool = false) {
        self.name = name
        self.kind = kind
        self.code = code
        self.predicates = predicates
        self.className = className
        self.usedPluralForm = usedPluralForm
    }
}

public struct SDEFResolver {
    private let dictionary: ScriptingDictionary

    public init(dictionary: ScriptingDictionary) {
        self.dictionary = dictionary
    }

    public func resolve(_ query: AEQuery) throws -> ResolvedQuery {
        // Start from "application" class
        guard let appClass = dictionary.findClass("application") else {
            throw ResolverError.missingApplicationClass
        }

        var currentClass = appClass
        var resolvedSteps: [ResolvedStep] = []

        for (index, step) in query.steps.enumerated() {
            let isLast = (index == query.steps.count - 1)
            let resolved = try resolveStep(step, inClass: currentClass, isLast: isLast)
            resolvedSteps.append(resolved)

            // Update current class context for next step
            if let nextClassName = resolved.className {
                if let nextClass = dictionary.findClass(nextClassName) {
                    currentClass = nextClass
                } else if !isLast {
                    throw ResolverError.unknownElement(step.name, inClass: currentClass.name)
                }
            }
        }

        return ResolvedQuery(appName: query.appName, steps: resolvedSteps)
    }

    private func resolveStep(_ step: Step, inClass classDef: ClassDef, isLast: Bool) throws -> ResolvedStep {
        let name = step.name.lowercased()

        // Check elements first (including plural names)
        let allElems = dictionary.allElements(for: classDef)
        for elem in allElems {
            let elemClass = dictionary.findClass(elem.type)
            if let elemClass = elemClass {
                // Match by singular name, plural name, type name, or default plural
                let singularMatch = elemClass.name.lowercased() == name
                let explicitPluralMatch = elemClass.pluralName?.lowercased() == name
                let defaultPluralMatch = dictionary.defaultPlural(for: elemClass.name).lowercased() == name
                let typeMatch = elem.type.lowercased() == name
                let isPlural = explicitPluralMatch || (!singularMatch && !typeMatch && defaultPluralMatch)
                if singularMatch || explicitPluralMatch || defaultPluralMatch || typeMatch {
                    return ResolvedStep(
                        name: step.name,
                        kind: .element,
                        code: elemClass.code,
                        predicates: step.predicates,
                        className: elemClass.name,
                        usedPluralForm: isPlural
                    )
                }
            }
        }

        // Check properties
        let allProps = dictionary.allProperties(for: classDef)
        for prop in allProps {
            if prop.name.lowercased() == name {
                // If property has a type that is a known class, allow chaining
                var className: String? = nil
                if let propType = prop.type, dictionary.findClass(propType) != nil {
                    className = propType
                }
                return ResolvedStep(
                    name: step.name,
                    kind: .property,
                    code: prop.code,
                    predicates: step.predicates,
                    className: className
                )
            }
        }

        // Also check if the name matches a class that has a plural form
        if let cls = dictionary.findClassByPlural(name) {
            return ResolvedStep(
                name: step.name,
                kind: .element,
                code: cls.code,
                predicates: step.predicates,
                className: cls.name,
                usedPluralForm: true
            )
        }

        // Check default pluralization (append "s") for classes without explicit plural
        if let cls = dictionary.findClassByDefaultPlural(name) {
            return ResolvedStep(
                name: step.name,
                kind: .element,
                code: cls.code,
                predicates: step.predicates,
                className: cls.name,
                usedPluralForm: true
            )
        }

        // "properties" → pALL (get all properties of the object)
        if name == "properties" {
            return ResolvedStep(
                name: step.name,
                kind: .property,
                code: "pALL",
                predicates: step.predicates,
                className: nil
            )
        }

        // Nothing found
        let availableElements = allElems.compactMap { dictionary.findClass($0.type)?.name }
        let availableProperties = allProps.map(\.name)
        throw ResolverError.unknownName(
            step.name,
            inClass: classDef.name,
            availableElements: availableElements,
            availableProperties: availableProperties
        )
    }

    /// Look up the SDEF definition for the final step in a query.
    /// Returns a description of the property or class at the end of the path.
    public func sdefInfo(for query: AEQuery) throws -> SDEFInfo {
        guard let appClass = dictionary.findClass("application") else {
            throw ResolverError.missingApplicationClass
        }

        // With no steps, describe the application class
        guard !query.steps.isEmpty else {
            return .classInfo(classDetail(appClass))
        }

        var currentClass = appClass

        for (index, step) in query.steps.enumerated() {
            let name = step.name.lowercased()
            let isLast = (index == query.steps.count - 1)

            // Check elements (including default plurals)
            let allElems = dictionary.allElements(for: currentClass)
            var foundAsElement = false
            for elem in allElems {
                if let elemClass = dictionary.findClass(elem.type) {
                    let match = elemClass.name.lowercased() == name
                        || elemClass.pluralName?.lowercased() == name
                        || dictionary.defaultPlural(for: elemClass.name).lowercased() == name
                        || elem.type.lowercased() == name
                    if match {
                        if isLast {
                            return .classInfo(classDetail(elemClass))
                        }
                        currentClass = elemClass
                        foundAsElement = true
                        break
                    }
                }
            }
            if foundAsElement { continue }

            // Check plural lookup (explicit and default)
            if let cls = dictionary.findClassByPlural(name) {
                if isLast {
                    return .classInfo(classDetail(cls))
                }
                currentClass = cls
                continue
            }
            if let cls = dictionary.findClassByDefaultPlural(name) {
                if isLast {
                    return .classInfo(classDetail(cls))
                }
                currentClass = cls
                continue
            }

            // Check properties
            let allProps = dictionary.allProperties(for: currentClass)
            for prop in allProps {
                if prop.name.lowercased() == name {
                    if isLast {
                        return .propertyInfo(PropertyDetail(
                            name: prop.name,
                            code: prop.code,
                            type: prop.type,
                            access: prop.access,
                            inClass: currentClass.name
                        ))
                    }
                    if let propType = prop.type, let nextClass = dictionary.findClass(propType) {
                        currentClass = nextClass
                    }
                    break
                }
            }
        }

        // Shouldn't reach here if resolve() succeeded, but just in case
        return .classInfo(classDetail(currentClass))
    }

    private func classDetail(_ cls: ClassDef) -> ClassDetail {
        let allProps = dictionary.allProperties(for: cls)
        let allElems = dictionary.allElements(for: cls)
        let elementNames = allElems.compactMap { elem -> (String, String)? in
            guard let elemClass = dictionary.findClass(elem.type) else { return nil }
            return (elemClass.pluralName ?? elemClass.name, elemClass.code)
        }
        return ClassDetail(
            name: cls.name,
            code: cls.code,
            pluralName: cls.pluralName,
            inherits: cls.inherits,
            properties: allProps,
            elements: elementNames
        )
    }
}

public enum SDEFInfo {
    case classInfo(ClassDetail)
    case propertyInfo(PropertyDetail)
}

public struct ClassDetail {
    public let name: String
    public let code: String
    public let pluralName: String?
    public let inherits: String?
    public let properties: [PropertyDef]
    public let elements: [(String, String)]  // (name, code)
}

public struct PropertyDetail {
    public let name: String
    public let code: String
    public let type: String?
    public let access: PropertyAccess?
    public let inClass: String
}

public enum ResolverError: Error, LocalizedError, Equatable {
    case missingApplicationClass
    case unknownElement(String, inClass: String)
    case unknownProperty(String, inClass: String)
    case unknownName(String, inClass: String, availableElements: [String], availableProperties: [String])

    public var errorDescription: String? {
        switch self {
        case .missingApplicationClass:
            return "SDEF dictionary has no 'application' class"
        case .unknownElement(let name, let cls):
            return "Unknown element '\(name)' in class '\(cls)'"
        case .unknownProperty(let name, let cls):
            return "Unknown property '\(name)' in class '\(cls)'"
        case .unknownName(let name, let cls, let elements, let properties):
            var msg = "Unknown name '\(name)' in class '\(cls)'."
            if !elements.isEmpty {
                msg += " Available elements: \(elements.joined(separator: ", "))."
            }
            if !properties.isEmpty {
                msg += " Available properties: \(properties.joined(separator: ", "))."
            }
            return msg
        }
    }
}
