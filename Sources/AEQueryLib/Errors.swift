import Foundation

public enum AEQueryError: Error, LocalizedError {
    case appNotFound(String)
    case sdefLoadFailed(String, String)
    case appleEventFailed(Int, String)
    case noReply
    case invalidExpression(String)

    public var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            return "Application '\(name)' not found"
        case .sdefLoadFailed(let path, let detail):
            return "Failed to load SDEF from '\(path)': \(detail)"
        case .appleEventFailed(let code, let msg):
            return "Apple Event error \(code): \(msg)"
        case .noReply:
            return "No reply received from application"
        case .invalidExpression(let detail):
            return "Invalid expression: \(detail)"
        }
    }
}
