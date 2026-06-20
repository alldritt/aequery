import Foundation

public struct ScriptingDictionary {
    public var classes: [String: ClassDef] = [:]     // keyed by lowercase name
    public var recordTypes: [String: ClassDef] = [:] // keyed by lowercase name (SDEF <record-type>)
    public var valueTypes: [String: ClassDef] = [:]  // keyed by lowercase name (SDEF <value-type>)
    public var enumerations: [String: EnumDef] = [:] // keyed by lowercase name
    public var commands: [String: CommandDef] = [:]   // keyed by lowercase name
    public var suiteNames: [String] = []              // suite names in order
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
                description: classDef.description ?? existing.description,
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
        // A type/class reference may use a four-character code in place of a
        // name (see sdef(5): the `type` attribute resolves against the name OR
        // code of a class). Fall back to a code lookup when the name misses.
        return findClassByCode(name)
    }

    /// Look up a class by its plural name, returning the singular ClassDef
    public func findClassByPlural(_ plural: String) -> ClassDef? {
        let lower = plural.lowercased()
        if let singular = pluralToSingular[lower], let cls = classes[singular] {
            return cls
        }
        return nil
    }

    /// Check if a name is a known plural form (explicit or default)
    public func isPlural(_ name: String) -> Bool {
        let lower = name.lowercased()
        if pluralToSingular[lower] != nil { return true }
        // Check default pluralization: if removing trailing "s" yields a known class
        if lower.hasSuffix("s") {
            let singular = String(lower.dropLast())
            if classes[singular] != nil { return true }
        }
        return false
    }

    /// Compute the default plural for a class name (AppleScript's heuristic: append "s")
    public func defaultPlural(for className: String) -> String {
        if let cls = classes[className.lowercased()], let plural = cls.pluralName {
            return plural
        }
        return className + "s"
    }

    /// Find a class by its default plural form (name + "s") when no explicit plural is defined
    public func findClassByDefaultPlural(_ plural: String) -> ClassDef? {
        let lower = plural.lowercased()
        guard lower.hasSuffix("s") else { return nil }
        let singular = String(lower.dropLast())
        // Only match if the class exists AND has no explicit plural (otherwise findClassByPlural handles it)
        if let cls = classes[singular], cls.pluralName == nil {
            return cls
        }
        return nil
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
        if let enumDef = enumerations[name.lowercased()] {
            return enumDef
        }
        // A type reference may name an enumeration by its four-character code
        // instead of its name (see sdef(5)).
        return findEnumerationByCode(name)
    }

    /// Find a record-type definition by name. SDEF `<record-type>` elements
    /// (e.g. Numbers' "print settings", "export options") declare record
    /// structures that commands and properties may reference as a type.
    public func findRecordType(_ name: String) -> ClassDef? {
        if let recordDef = recordTypes[name.lowercased()] {
            return recordDef
        }
        // As with classes and enumerations, a record-type may be referenced by
        // its four-character code.
        return findRecordTypeByCode(name)
    }

    /// Find a value-type definition by name. SDEF `<value-type>` elements
    /// declare simple basic types (e.g. an "image" backed by NSData) that
    /// properties and commands may reference as a type.
    public func findValueType(_ name: String) -> ClassDef? {
        if let valueDef = valueTypes[name.lowercased()] {
            return valueDef
        }
        // A value-type may likewise be referenced by its four-character code.
        return findValueTypeByCode(name)
    }

    /// Decompose a composite type string into its constituent base type names.
    ///
    /// Real-world SDEFs use two compound forms that a single type lookup can't
    /// resolve directly:
    ///   - `list of <type>` — the older syntax for a typed list, still common.
    ///   - `A | B` or `A / B` — alternative-type lists used by some apps (e.g.
    ///     Apple's Pages and Keynote) to declare several acceptable types. The
    ///     SDEF parser itself also joins multiple nested `<type>` elements with
    ///     `" / "`.
    ///
    /// Returns the trimmed base type names with any `list of ` prefix removed,
    /// so each can be checked against `findClass`/`findEnumeration`. A plain
    /// type like `text` returns `["text"]`.
    public static func componentTypeNames(of type: String) -> [String] {
        let parts = type.components(separatedBy: CharacterSet(charactersIn: "|/"))
        var names: [String] = []
        for raw in parts {
            var t = raw.trimmingCharacters(in: .whitespaces)
            // Strip any leading `list of ` (the legacy typed-list syntax).
            while t.lowercased().hasPrefix("list of ") {
                t = String(t.dropFirst("list of ".count)).trimmingCharacters(in: .whitespaces)
            }
            if !t.isEmpty { names.append(t) }
        }
        return names.isEmpty ? [type.trimmingCharacters(in: .whitespaces)] : names
    }

    /// Whether a (possibly composite) type string refers only to a typed list,
    /// e.g. `list of paragraph` or `list of text | list of file`.
    public static func isListType(_ type: String) -> Bool {
        type.lowercased().contains("list of ")
    }

    /// Canonicalize a four-character (or eight-character) OSType code so the two
    /// spellings sdef(5) permits compare equal: a literal Mac OS Roman string
    /// such as `"eGrT"`, and its hexadecimal form such as `"0x65477254"`. A
    /// string without a `0x` prefix is returned unchanged; codes are
    /// case-sensitive, so no case folding is applied.
    public static func canonicalCode(_ code: String) -> String {
        guard code.hasPrefix("0x") || code.hasPrefix("0X") else { return code }
        let hex = code.dropFirst(2)
        guard !hex.isEmpty, hex.count % 2 == 0 else { return code }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return code }
            bytes.append(byte)
            idx = next
        }
        // Mac OS Roman maps every byte value, so decoding never fails.
        return String(bytes: bytes, encoding: .macOSRoman) ?? code
    }

    /// Find a class definition by its four-character code (accepting either the
    /// literal or `0x…` hexadecimal spelling).
    public func findClassByCode(_ code: String) -> ClassDef? {
        let canon = Self.canonicalCode(code)
        return classes.values.first { Self.canonicalCode($0.code) == canon }
    }

    /// Find an enumeration by its four-character code.
    public func findEnumerationByCode(_ code: String) -> EnumDef? {
        let canon = Self.canonicalCode(code)
        return enumerations.values.first { enumDef in
            guard let enumCode = enumDef.code else { return false }
            return Self.canonicalCode(enumCode) == canon
        }
    }

    /// Find a record-type by its four-character code.
    public func findRecordTypeByCode(_ code: String) -> ClassDef? {
        let canon = Self.canonicalCode(code)
        return recordTypes.values.first { Self.canonicalCode($0.code) == canon }
    }

    /// Find a value-type by its four-character code.
    public func findValueTypeByCode(_ code: String) -> ClassDef? {
        let canon = Self.canonicalCode(code)
        return valueTypes.values.first { Self.canonicalCode($0.code) == canon }
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
    public let description: String?
    public var properties: [PropertyDef]
    public var elements: [ElementDef]

    public init(name: String, code: String, pluralName: String? = nil, inherits: String? = nil,
                hidden: Bool = false, description: String? = nil, properties: [PropertyDef] = [], elements: [ElementDef] = []) {
        self.name = name
        self.code = code
        self.pluralName = pluralName
        self.inherits = inherits
        self.hidden = hidden
        self.description = description
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
    public let description: String?

    public init(name: String, code: String, type: String? = nil, access: PropertyAccess? = nil, hidden: Bool = false, description: String? = nil) {
        self.name = name
        self.code = code
        self.type = type
        self.access = access
        self.hidden = hidden
        self.description = description
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
    public let hidden: Bool

    public init(name: String, code: String? = nil, enumerators: [Enumerator] = [], hidden: Bool = false) {
        self.name = name
        self.code = code
        self.enumerators = enumerators
        self.hidden = hidden
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

public struct CommandDef: Equatable {
    public let name: String
    public let code: String           // 8-char event code (class + ID, e.g. "aevtodoc")
    public let description: String?
    public let hidden: Bool
    public let directParameter: CommandParam?
    public let parameters: [CommandParam]
    public let result: CommandResult?
    public let suiteName: String?

    public init(name: String, code: String, description: String? = nil, hidden: Bool = false,
                directParameter: CommandParam? = nil, parameters: [CommandParam] = [],
                result: CommandResult? = nil, suiteName: String? = nil) {
        self.name = name
        self.code = code
        self.description = description
        self.hidden = hidden
        self.directParameter = directParameter
        self.parameters = parameters
        self.result = result
        self.suiteName = suiteName
    }
}

public struct CommandParam: Equatable {
    public let name: String?          // nil for direct parameter
    public let code: String?          // nil for direct parameter
    public let type: String?
    public let optional: Bool
    public let description: String?

    public init(name: String? = nil, code: String? = nil, type: String? = nil, optional: Bool = false, description: String? = nil) {
        self.name = name
        self.code = code
        self.type = type
        self.optional = optional
        self.description = description
    }
}

public struct CommandResult: Equatable {
    public let type: String?
    public let description: String?

    public init(type: String? = nil, description: String? = nil) {
        self.type = type
        self.description = description
    }
}
