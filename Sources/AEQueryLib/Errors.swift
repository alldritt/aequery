import Foundation

public enum AEQueryError: Error, LocalizedError {
    case appNotFound(String)
    case sdefLoadFailed(String, String)
    case appleEventFailed(Int, String, AEValue?)
    case noReply
    case invalidExpression(String)

    public var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            return "Application '\(name)' not found"
        case .sdefLoadFailed(let path, let detail):
            return "Failed to load SDEF from '\(path)': \(detail)"
        case .appleEventFailed(let code, let msg, _):
            if msg.isEmpty {
                return "Apple Event error \(code): \(Self.errorCodeDescription(code))"
            }
            return "\(msg) (\(code))"
        case .noReply:
            return "No reply received from application"
        case .invalidExpression(let detail):
            return "Invalid expression: \(detail)"
        }
    }

    public var offendingObject: AEValue? {
        if case .appleEventFailed(_, _, let obj) = self { return obj }
        return nil
    }

    public static func errorCodeDescription(_ code: Int) -> String {
        switch code {
        case -1700: return "Can't make some data into the expected type"
        case -1708: return "Event not handled"
        case -1712: return "Apple Event timed out"
        case -1719: return "Invalid index"
        case -1728: return "No such object"
        case -1731: return "User canceled"
        case -1750: return "Object is not the right type"
        case -1751: return "Can't handle the Apple Event"
        case -600: return "Application is not running"
        case -10004: return "A privilege violation occurred"
        default: return "Error \(code)"
        }
    }
}
