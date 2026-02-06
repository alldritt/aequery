import Foundation

public struct AppleScriptFormatter {
    public enum Style {
        case terminology   // human-readable SDEF names
        case chevron       // raw «class xxxx» codes
    }

    public let style: Style
    public let dictionary: ScriptingDictionary?
    public let appName: String

    public init(style: Style, dictionary: ScriptingDictionary?, appName: String) {
        self.style = style
        self.dictionary = dictionary
        self.appName = appName
    }

    public func format(_ value: AEValue) -> String {
        switch value {
        case .objectSpecifier:
            let specStr = formatSpecifier(value)
            if style == .terminology {
                return "tell application \"\(appName)\"\n    \(specStr)\nend tell"
            } else {
                return "\(specStr) of application \"\(appName)\""
            }
        default:
            return formatValue(value)
        }
    }

    // MARK: - Scalar formatting

    public func formatValue(_ value: AEValue) -> String {
        switch value {
        case .string(let s):
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .integer(let n):
            return "\(n)"
        case .double(let d):
            return "\(d)"
        case .bool(let b):
            return b ? "true" : "false"
        case .date(let d):
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
            formatter.locale = Locale(identifier: "en_US")
            return "date \"\(formatter.string(from: d))\""
        case .null:
            return "missing value"
        case .list(let items):
            let formatted = items.map { formatValue($0) }.joined(separator: ", ")
            return "{\(formatted)}"
        case .record(let pairs):
            return formatRecord(pairs)
        case .objectSpecifier:
            return formatSpecifier(value)
        }
    }

    // MARK: - Record formatting

    private static let wellKnownProperties: [String: String] = [
        "pcls": "class",
        "pALL": "properties",
        "ID  ": "id",
    ]

    private func formatRecord(_ pairs: [(String, AEValue)]) -> String {
        let classDef = classDefFromRecord(pairs)
        let formatted = pairs.map { (key, val) in
            let fmtKey = formatRecordKey(key, inClass: classDef)
            let fmtVal = formatRecordValue(val, forPropertyCode: key, inClass: classDef)
            return "\(fmtKey):\(fmtVal)"
        }.joined(separator: ", ")
        return "{\(formatted)}"
    }

    private func classDefFromRecord(_ pairs: [(String, AEValue)]) -> ClassDef? {
        guard let dictionary = dictionary else { return nil }
        for (key, val) in pairs {
            if key == "pcls", case .string(let code) = val {
                return dictionary.findClassByCode(code)
            }
        }
        return nil
    }

    private func formatRecordKey(_ code: String, inClass classDef: ClassDef?) -> String {
        switch style {
        case .terminology:
            if let name = resolvePropertyName(code, inClass: classDef) {
                return name
            }
            return "\u{00AB}property \(code)\u{00BB}"
        case .chevron:
            return "\u{00AB}property \(code)\u{00BB}"
        }
    }

    private func formatRecordValue(_ val: AEValue, forPropertyCode code: String, inClass classDef: ClassDef?) -> String {
        guard case .string(let strVal) = val else { return formatValue(val) }

        // missing value
        if strVal == "msng" {
            return "missing value"
        }

        // pcls: format as class reference
        if code == "pcls" {
            if style == .terminology, let dict = dictionary, let cls = dict.findClassByCode(strVal) {
                return cls.name
            }
            return "\u{00AB}class \(strVal)\u{00BB}"
        }

        // Enum-typed properties: resolve enumerator
        if let propDef = findPropertyDef(forCode: code, inClass: classDef),
           let propType = propDef.type,
           let dict = dictionary,
           let enumDef = dict.findEnumeration(propType),
           let enumerator = enumDef.enumerators.first(where: { $0.code == strVal }) {
            if style == .terminology {
                return enumerator.name
            }
            return "\u{00AB}constant \(strVal)\u{00BB}"
        }

        return formatValue(val)
    }

    private func resolvePropertyName(_ code: String, inClass classDef: ClassDef?) -> String? {
        if let dictionary = dictionary {
            if let classDef = classDef {
                if let prop = dictionary.findPropertyByCode(code, inClass: classDef) {
                    return prop.name
                }
            }
            for cls in dictionary.classes.values {
                if let prop = dictionary.findPropertyByCode(code, inClass: cls) {
                    return prop.name
                }
            }
        }
        return Self.wellKnownProperties[code]
    }

    private func findPropertyDef(forCode code: String, inClass classDef: ClassDef?) -> PropertyDef? {
        guard let dictionary = dictionary else { return nil }
        if let classDef = classDef {
            if let prop = dictionary.findPropertyByCode(code, inClass: classDef) {
                return prop
            }
        }
        for cls in dictionary.classes.values {
            if let prop = dictionary.findPropertyByCode(code, inClass: cls) {
                return prop
            }
        }
        return nil
    }

    // MARK: - Object specifier formatting

    public func formatSpecifier(_ value: AEValue) -> String {
        guard case .objectSpecifier(let want, let form, let seld, let from) = value else {
            return formatValue(value)
        }

        let element = formatElement(want: want, form: form, seld: seld)
        let container = formatContainer(from)

        if let container = container {
            return "\(element) of \(container)"
        }
        return element
    }

    private func formatElement(want: String, form: String, seld: AEValue) -> String {
        switch style {
        case .terminology:
            return formatElementTerminology(want: want, form: form, seld: seld)
        case .chevron:
            return formatElementChevron(want: want, form: form, seld: seld)
        }
    }

    private func formatElementTerminology(want: String, form: String, seld: AEValue) -> String {
        // Property access
        if form == "prop" {
            if case .string(let propCode) = seld {
                if let name = resolvePropertyName(propCode, inClass: nil) {
                    return name
                }
                return "\u{00AB}property \(propCode)\u{00BB}"
            }
            return formatValue(seld)
        }

        // Resolve class name
        let className: String
        if let dict = dictionary, let cls = dict.findClassByCode(want) {
            className = cls.name
        } else {
            className = "\u{00AB}class \(want)\u{00BB}"
        }

        // Index form
        if form == "indx" {
            // Check for "every" (kAEAll = 'all ')
            if case .string(let s) = seld, s == "all " {
                return "every \(className)"
            }
            if case .integer(let n) = seld {
                if n == -1 {
                    return "last \(className)"
                }
                return "\(className) \(n)"
            }
            return "\(className) \(formatValue(seld))"
        }

        // Name form
        if form == "name" {
            return "\(className) \(formatValue(seld))"
        }

        // ID form
        if form == "ID  " {
            return "\(className) id \(formatValue(seld))"
        }

        return "\(className) \(formatValue(seld))"
    }

    private func formatElementChevron(want: String, form: String, seld: AEValue) -> String {
        // Property access
        if form == "prop" {
            if case .string(let propCode) = seld {
                return "\u{00AB}property \(propCode)\u{00BB}"
            }
            return "\u{00AB}property \(formatValue(seld))\u{00BB}"
        }

        let classRef = "\u{00AB}class \(want)\u{00BB}"

        // Index form
        if form == "indx" {
            if case .string(let s) = seld, s == "all " {
                return "every \(classRef)"
            }
            if case .integer(let n) = seld {
                if n == -1 {
                    return "last \(classRef)"
                }
                return "\(classRef) \(n)"
            }
            return "\(classRef) \(formatValue(seld))"
        }

        // Name form
        if form == "name" {
            return "\(classRef) \(formatValue(seld))"
        }

        // ID form
        if form == "ID  " {
            return "\(classRef) id \(formatValue(seld))"
        }

        return "\(classRef) \(formatValue(seld))"
    }

    private func formatContainer(_ value: AEValue) -> String? {
        switch value {
        case .null:
            return nil
        case .objectSpecifier:
            return formatSpecifier(value)
        default:
            return formatValue(value)
        }
    }
}
