import Foundation

public enum OutputFormat {
    case json
    case text
}

public struct OutputFormatter {
    public let format: OutputFormat
    public let dictionary: ScriptingDictionary?
    public let appName: String?

    public init(format: OutputFormat = .json, dictionary: ScriptingDictionary? = nil, appName: String? = nil) {
        self.format = format
        self.dictionary = dictionary
        self.appName = appName
    }

    public func format(_ value: AEValue) -> String {
        switch format {
        case .json:
            return formatJSON(value)
        case .text:
            return formatText(value)
        }
    }

    // MARK: - JSON

    private func formatJSON(_ value: AEValue) -> String {
        let jsonValue = toJSONValue(value)
        // JSONSerialization only accepts arrays and dictionaries as top-level objects
        if JSONSerialization.isValidJSONObject(jsonValue),
           let data = try? JSONSerialization.data(withJSONObject: jsonValue, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        // Handle scalars that can't be top-level JSON objects
        return formatScalarJSON(value)
    }

    private func formatScalarJSON(_ value: AEValue) -> String {
        switch value {
        case .string(let s):
            // Properly JSON-escape the string
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        case .integer(let n):
            return "\(n)"
        case .double(let d):
            return "\(d)"
        case .bool(let b):
            return b ? "true" : "false"
        case .date(let d):
            return "\"\(ISO8601DateFormatter().string(from: d))\""
        case .null:
            return "null"
        case .objectSpecifier:
            return "\"\(specifierToXPath(value).replacingOccurrences(of: "\"", with: "\\\""))\""
        case .list, .record:
            return "\(value)"  // shouldn't reach here
        }
    }

    private func toJSONValue(_ value: AEValue) -> Any {
        switch value {
        case .string(let s): return s
        case .integer(let n): return n
        case .double(let d): return d
        case .bool(let b): return b
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .list(let items): return items.map { toJSONValue($0) }
        case .record(let pairs):
            var dict: [String: Any] = [:]
            for (key, val) in pairs {
                dict[key] = toJSONValue(val)
            }
            return dict
        case .null: return NSNull()
        case .objectSpecifier:
            return specifierToXPath(value)
        }
    }

    // MARK: - Text

    private func formatText(_ value: AEValue) -> String {
        switch value {
        case .string(let s): return s
        case .integer(let n): return "\(n)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .null: return ""
        case .list(let items):
            return items.map { formatText($0) }.joined(separator: "\n")
        case .record(let pairs):
            return formatJSON(.record(pairs))
        case .objectSpecifier:
            return specifierToXPath(value)
        }
    }

    // MARK: - Object specifier → XPath

    /// Convert an object specifier chain into an XPath-like expression string.
    private func specifierToXPath(_ value: AEValue) -> String {
        // Collect the specifier chain from outermost to innermost
        var steps: [(want: String, form: String, seld: AEValue)] = []
        var current = value
        while case .objectSpecifier(let want, let form, let seld, let from) = current {
            steps.append((want: want, form: form, seld: seld))
            current = from
        }
        // Reverse so we go from container → leaf
        steps.reverse()

        var parts: [String] = []
        if let appName = appName {
            parts.append("/\(appName)")
        }

        for step in steps {
            let name = resolveClassName(step.want, form: step.form, seld: step.seld)
            let predicate = formatPredicate(form: step.form, seld: step.seld)
            parts.append("/\(name)\(predicate)")
        }

        return parts.joined()
    }

    /// Resolve a 4CC want code to a human-readable name using the dictionary.
    private func resolveClassName(_ want: String, form: String, seld: AEValue) -> String {
        if form == "prop" {
            // For properties, resolve the seld code
            if case .string(let propCode) = seld, let dictionary = dictionary {
                for cls in dictionary.classes.values {
                    if let prop = dictionary.findPropertyByCode(propCode, inClass: cls) {
                        return prop.name
                    }
                }
            }
            if case .string(let code) = seld {
                return code
            }
            return want
        }

        if let dictionary = dictionary, let cls = dictionary.findClassByCode(want) {
            // Use plural name for "every" (no predicate or all), singular otherwise
            if case .string(let s) = seld, s == "all " {
                return cls.pluralName ?? cls.name
            }
            return cls.pluralName ?? cls.name
        }
        return want
    }

    /// Format the predicate portion of a step (e.g., `[1]`, `[@name="x"]`, `[#id=42]`).
    private func formatPredicate(form: String, seld: AEValue) -> String {
        switch form {
        case "prop":
            // Properties don't have predicates — the name IS the step
            return ""
        case "indx":
            if case .string(let s) = seld, s == "all " {
                return ""  // "every" — no predicate needed
            }
            if case .integer(let n) = seld {
                return "[\(n)]"
            }
            return ""
        case "name":
            if case .string(let s) = seld {
                return "[@name=\"\(s)\"]"
            }
            return ""
        case "ID  ":
            switch seld {
            case .string(let s):
                return "[#id=\"\(s)\"]"
            case .integer(let n):
                return "[#id=\(n)]"
            default:
                return ""
            }
        default:
            return ""
        }
    }
}
