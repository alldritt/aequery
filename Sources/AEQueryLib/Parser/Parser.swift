import Foundation

public struct Parser {
    private let tokens: [Token]
    private var position: Int = 0

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    // MARK: - Helpers

    private var current: Token {
        tokens[position]
    }

    private var currentKind: TokenKind {
        current.kind
    }

    private mutating func advance() {
        if position < tokens.count - 1 {
            position += 1
        }
    }

    private mutating func expect(_ kind: TokenKind) throws {
        guard currentKind == kind else {
            throw ParserError.unexpectedToken(expected: kind, got: current)
        }
        advance()
    }

    private func peek() -> TokenKind {
        currentKind
    }

    // MARK: - Parsing

    /// Parse: "/" AppName ("/" Step)*
    public mutating func parse() throws -> AEQuery {
        try expect(.slash)

        let appName = try parseAppName()
        var steps: [Step] = []

        while currentKind == .slash {
            advance() // consume "/"
            guard case .name(_) = currentKind else {
                if currentKind == .eof {
                    break
                }
                throw ParserError.unexpectedToken(expected: .name(""), got: current)
            }
            steps.append(try parseStep())
        }

        if currentKind != .eof {
            throw ParserError.unexpectedToken(expected: .eof, got: current)
        }

        return AEQuery(appName: appName, steps: steps)
    }

    private mutating func parseAppName() throws -> String {
        switch currentKind {
        case .name(let n):
            advance()
            return n
        case .quotedString(let s):
            advance()
            return s
        default:
            throw ParserError.unexpectedToken(expected: .name(""), got: current)
        }
    }

    private mutating func parseStep() throws -> Step {
        guard case .name(let name) = currentKind else {
            throw ParserError.unexpectedToken(expected: .name(""), got: current)
        }
        advance()

        var predicates: [Predicate] = []
        while currentKind == .leftBracket {
            if !predicates.isEmpty {
                throw ParserError.multiplePredicates(position: current.position)
            }
            predicates.append(try parsePredicate())
        }

        return Step(name: name, predicates: predicates)
    }

    /// Parse: "[" PredicateExpr "]"
    private mutating func parsePredicate() throws -> Predicate {
        try expect(.leftBracket)

        guard currentKind != .rightBracket else {
            throw ParserError.invalidPredicate(position: current.position)
        }

        let pred = try parsePredicateExpr()
        try expect(.rightBracket)
        return pred
    }

    /// PredicateExpr = AtomicPredicate (("and"|"or") AtomicPredicate)*
    private mutating func parsePredicateExpr() throws -> Predicate {
        var left = try parseAtomicPredicate()

        while currentKind == .and || currentKind == .or {
            let op: BoolOp = currentKind == .and ? .and : .or
            advance()
            let right = try parseAtomicPredicate()
            left = .compound(left, op, right)
        }

        return left
    }

    /// AtomicPredicate = Integer (":" Integer)?
    ///                  | "#" Name "=" Value
    ///                  | "@" Name "=" Value
    ///                  | Path CompOp Value
    private mutating func parseAtomicPredicate() throws -> Predicate {
        switch currentKind {
        case .integer(let n):
            advance()
            if currentKind == .colon {
                advance()
                guard case .integer(let end) = currentKind else {
                    throw ParserError.unexpectedToken(expected: .integer(0), got: current)
                }
                advance()
                return .byRange(n, end)
            }
            return .byIndex(n)

        case .hash:
            advance()
            guard case .name(let idName) = currentKind, idName.lowercased() == "id" else {
                throw ParserError.unexpectedToken(expected: .name("id"), got: current)
            }
            advance()
            try expect(.equals)
            let val = try parseValue()
            return .byID(val)

        case .at:
            advance()
            guard case .name(_) = currentKind else {
                throw ParserError.unexpectedToken(expected: .name(""), got: current)
            }
            advance()
            try expect(.equals)
            let val = try parseValue()
            guard case .string(let s) = val else {
                throw ParserError.invalidPredicate(position: current.position)
            }
            return .byName(s)

        case .middle:
            advance()
            return .byOrdinal(.middle)

        case .some:
            advance()
            return .byOrdinal(.some)

        case .name(_):
            // Could be a whose clause: path compOp value
            let path = try parsePath()
            let op = try parseComparisonOp()
            let val = try parseValue()
            return .test(TestExpr(path: path, op: op, value: val))

        default:
            throw ParserError.invalidPredicate(position: current.position)
        }
    }

    /// Parse a property path like "name" or "documents[1]/name"
    private mutating func parsePath() throws -> [String] {
        var path: [String] = []
        guard case .name(let first) = currentKind else {
            throw ParserError.unexpectedToken(expected: .name(""), got: current)
        }
        path.append(first)
        advance()

        // Skip over predicates within the path (e.g., documents[1])
        while currentKind == .leftBracket {
            // Skip the entire bracketed section — it's part of the path context
            var depth = 0
            while position < tokens.count {
                if currentKind == .leftBracket { depth += 1 }
                if currentKind == .rightBracket { depth -= 1 }
                advance()
                if depth == 0 { break }
            }
        }

        while currentKind == .slash {
            advance()
            guard case .name(let next) = currentKind else {
                throw ParserError.unexpectedToken(expected: .name(""), got: current)
            }
            path.append(next)
            advance()

            // Skip over predicates within the path segment
            while currentKind == .leftBracket {
                var depth = 0
                while position < tokens.count {
                    if currentKind == .leftBracket { depth += 1 }
                    if currentKind == .rightBracket { depth -= 1 }
                    advance()
                    if depth == 0 { break }
                }
            }
        }

        return path
    }

    private mutating func parseComparisonOp() throws -> ComparisonOp {
        let op: ComparisonOp
        switch currentKind {
        case .equals: op = .equal
        case .notEquals: op = .notEqual
        case .lessThan: op = .lessThan
        case .greaterThan: op = .greaterThan
        case .lessOrEqual: op = .lessOrEqual
        case .greaterOrEqual: op = .greaterOrEqual
        case .contains: op = .contains
        case .begins: op = .beginsWith
        case .ends: op = .endsWith
        default:
            throw ParserError.unexpectedToken(expected: .equals, got: current)
        }
        advance()
        return op
    }

    private mutating func parseValue() throws -> Value {
        switch currentKind {
        case .integer(let n):
            advance()
            return .integer(n)
        case .quotedString(let s):
            advance()
            return .string(s)
        case .name(let s):
            advance()
            return .string(s)
        default:
            throw ParserError.unexpectedToken(expected: .quotedString(""), got: current)
        }
    }
}

public enum ParserError: Error, LocalizedError {
    case unexpectedToken(expected: TokenKind, got: Token)
    case unexpectedEnd
    case invalidPredicate(position: Int)
    case multiplePredicates(position: Int)

    public var errorDescription: String? {
        switch self {
        case .unexpectedToken(let expected, let got):
            return "Expected \(expected) but got \(got.kind) at position \(got.position)"
        case .unexpectedEnd:
            return "Unexpected end of input"
        case .invalidPredicate(let pos):
            return "Invalid predicate at position \(pos)"
        case .multiplePredicates(let pos):
            return "Multiple predicates are not supported at position \(pos). Use 'and'/'or' to combine conditions in a single predicate."
        }
    }
}
