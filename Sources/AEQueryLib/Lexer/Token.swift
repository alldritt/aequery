import Foundation

public enum TokenKind: Equatable {
    // Structural
    case slash           // /
    case leftBracket     // [
    case rightBracket    // ]
    case leftParen       // (
    case rightParen      // )
    case at              // @
    case hash            // #
    case colon           // :

    // Comparison
    case equals          // =
    case notEquals       // !=
    case lessThan        // <
    case greaterThan     // >
    case lessOrEqual     // <=
    case greaterOrEqual  // >=

    // Keywords
    case and
    case or
    case contains

    // Values
    case name(String)
    case quotedString(String)
    case integer(Int)

    case eof
}

public struct Token: Equatable {
    public let kind: TokenKind
    public let position: Int

    public init(kind: TokenKind, position: Int) {
        self.kind = kind
        self.position = position
    }
}
