import Foundation

public struct ScriptingDictionary {
    public var classes: [String: ClassDef] = [:]     // keyed by lowercase name
    public var enumerations: [String: EnumDef] = [:] // keyed by lowercase name
    private var pluralToSingular: [String: String] = [:]  // lowercase plural → lowercase singular

    public init() {}

    public mutating func addClass(_ classDef: ClassDef) {
        let key = classDef.name.lowercased()
        if let existing = classes[key],
           classDef.inherits?.lowercased() == key {
            // Self-referential inheritance (e.g., app's "application" inherits
            // standard suite's "application"). Merge the base class's
            // properties/elements and continue its inherits chain.
            let baseInherits = existing.inherits?.lowercased() == key ? nil : existing.inherits
            classes[key] = ClassDef(
                name: classDef.name,
                code: classDef.code,
                pluralName: classDef.pluralName ?? existing.pluralName,
                inherits: baseInherits,
                hidden: classDef.hidden,
                properties: existing.properties + classDef.properties,
                elements: existing.elements + classDef.elements
            )
        } else {
            classes[key] = classDef
        }
        if let plural = classes[key]?.pluralName {
            pluralToSingular[plural.lowercased()] = key
        }
    }

    public mutating func mergeExtension(into className: String, properties: [PropertyDef], elements: [ElementDef]) {
        let key = className.lowercased()
        guard var existing = classes[key] else { return }
        existing.properties.append(contentsOf: properties)
        existing.elements.append(contentsOf: elements)
        classes[key] = existing
    }

    public func findClass(_ name: String) -> ClassDef? {
        let lower = name.lowercased()
        if let cls = classes[lower] {
            return cls
        }
        // Try plural → singular lookup
        if let singular = pluralToSingular[lower], let cls = classes[singular] {
            return cls
        }
        return nil
    }

    /// Look up a class by its plural name, returning the singular ClassDef
    public func findClassByPlural(_ plural: String) -> ClassDef? {
        let lower = plural.lowercased()
        if let singular = pluralToSingular[lower], let cls = classes[singular] {
            return cls
        }
        return nil
    }

    /// Check if a name is a known plural form
    public func isPlural(_ name: String) -> Bool {
        pluralToSingular[name.lowercased()] != nil
    }

    /// Get the full set of properties for a class, including inherited ones
    public func allProperties(for classDef: ClassDef) -> [PropertyDef] {
        var visited = Set<String>()
        return collectProperties(for: classDef, visited: &visited)
    }

    private func collectProperties(for classDef: ClassDef, visited: inout Set<String>) -> [PropertyDef] {
        let key = classDef.name.lowercased()
        guard visited.insert(key).inserted else { return [] }
        var props = classDef.properties
        if let inherits = classDef.inherits {
            if let parent = findClass(inherits) {
                props.append(contentsOf: collectProperties(for: parent, visited: &visited))
            }
        }
        return props
    }

    /// Get the full set of elements for a class, including inherited ones
    public func allElements(for classDef: ClassDef) -> [ElementDef] {
        var visited = Set<String>()
        return collectElements(for: classDef, visited: &visited)
    }

    private func collectElements(for classDef: ClassDef, visited: inout Set<String>) -> [ElementDef] {
        let key = classDef.name.lowercased()
        guard visited.insert(key).inserted else { return [] }
        var elems = classDef.elements
        if let inherits = classDef.inherits {
            if let parent = findClass(inherits) {
                elems.append(contentsOf: collectElements(for: parent, visited: &visited))
            }
        }
        return elems
    }

    public func findEnumeration(_ name: String) -> EnumDef? {
        enumerations[name.lowercased()]
    }

    /// Find a class definition by its four-character code
    public func findClassByCode(_ code: String) -> ClassDef? {
        classes.values.first { $0.code == code }
    }

    /// Find a property definition by its four-character code within a given class (including inherited properties)
    public func findPropertyByCode(_ code: String, inClass classDef: ClassDef) -> PropertyDef? {
        allProperties(for: classDef).first { $0.code == code }
    }
}

public struct ClassDef: Equatable {
    public let name: String
    public let code: String
    public let pluralName: String?
    public let inherits: String?
    public let hidden: Bool
    public var properties: [PropertyDef]
    public var elements: [ElementDef]

    public init(name: String, code: String, pluralName: String? = nil, inherits: String? = nil,
                hidden: Bool = false, properties: [PropertyDef] = [], elements: [ElementDef] = []) {
        self.name = name
        self.code = code
        self.pluralName = pluralName
        self.inherits = inherits
        self.hidden = hidden
        self.properties = properties
        self.elements = elements
    }
}

public struct PropertyDef: Equatable {
    public let name: String
    public let code: String
    public let type: String?
    public let access: PropertyAccess?
    public let hidden: Bool

    public init(name: String, code: String, type: String? = nil, access: PropertyAccess? = nil, hidden: Bool = false) {
        self.name = name
        self.code = code
        self.type = type
        self.access = access
        self.hidden = hidden
    }
}

public enum PropertyAccess: String, Equatable {
    case readOnly = "r"
    case readWrite = "rw"
    case writeOnly = "w"
}

public struct ElementDef: Equatable {
    public let type: String   // singular class name
    public let access: String?
    public let hidden: Bool

    public init(type: String, access: String? = nil, hidden: Bool = false) {
        self.type = type
        self.access = access
        self.hidden = hidden
    }
}

public struct EnumDef: Equatable {
    public let name: String
    public let code: String?
    public let enumerators: [Enumerator]

    public init(name: String, code: String? = nil, enumerators: [Enumerator] = []) {
        self.name = name
        self.code = code
        self.enumerators = enumerators
    }
}

public struct Enumerator: Equatable {
    public let name: String
    public let code: String

    public init(name: String, code: String) {
        self.name = name
        self.code = code
    }
}
