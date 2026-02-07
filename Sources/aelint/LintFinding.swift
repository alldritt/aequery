import Foundation

enum LintSeverity: String {
    case error
    case warning
    case info

    var symbol: String {
        switch self {
        case .error:   return "X"
        case .warning: return "!"
        case .info:    return "i"
        }
    }
}

struct LintFinding {
    let severity: LintSeverity
    let category: String
    let message: String
    let context: String?

    init(_ severity: LintSeverity, category: String, message: String, context: String? = nil) {
        self.severity = severity
        self.category = category
        self.message = message
        self.context = context
    }
}
