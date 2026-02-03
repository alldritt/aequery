import Foundation

public enum OutputFormat {
    case json
    case text
}

public struct OutputFormatter {
    public let format: OutputFormat

    public init(format: OutputFormat = .json) {
        self.format = format
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
           let data = try? JSONSerialization.data(withJSONObject: jsonValue, options: [.prettyPrinted, .sortedKeys]),
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
            // For records in text mode, fall back to JSON
            return formatJSON(.record(pairs))
        }
    }
}
