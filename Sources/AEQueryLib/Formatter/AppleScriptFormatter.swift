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
            let formatted = pairs.map { "\($0.0):\(formatValue($0.1))" }.joined(separator: ", ")
            return "{\(formatted)}"
        case .objectSpecifier:
            return formatSpecifier(value)
        }
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
                if let dict = dictionary {
                    // Try to find the property name from any class
                    for cls in dict.classes.values {
                        if let prop = dict.findPropertyByCode(propCode, inClass: cls) {
                            return prop.name
                        }
                    }
                }
                return propCode
            }
            return formatValue(seld)
        }

        // Resolve class name
        let className: String
        if let dict = dictionary, let cls = dict.findClassByCode(want) {
            className = cls.name
        } else {
            className = want
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
