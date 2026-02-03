import Foundation

public struct Lexer {
    private let input: [Character]
    private var position: Int = 0

    public init(_ input: String) {
        self.input = Array(input)
    }

    public mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        while position < input.count {
            let ch = input[position]
            switch ch {
            case " ", "\t":
                position += 1
            case "/":
                tokens.append(Token(kind: .slash, position: position))
                position += 1
            case "[":
                tokens.append(Token(kind: .leftBracket, position: position))
                position += 1
            case "]":
                tokens.append(Token(kind: .rightBracket, position: position))
                position += 1
            case "(":
                tokens.append(Token(kind: .leftParen, position: position))
                position += 1
            case ")":
                tokens.append(Token(kind: .rightParen, position: position))
                position += 1
            case "@":
                tokens.append(Token(kind: .at, position: position))
                position += 1
            case "#":
                tokens.append(Token(kind: .hash, position: position))
                position += 1
            case ":":
                tokens.append(Token(kind: .colon, position: position))
                position += 1
            case "=":
                tokens.append(Token(kind: .equals, position: position))
                position += 1
            case "!":
                let start = position
                position += 1
                if position < input.count && input[position] == "=" {
                    position += 1
                    tokens.append(Token(kind: .notEquals, position: start))
                } else {
                    throw LexerError.invalidCharacter(ch, position: start)
                }
            case "<":
                let start = position
                position += 1
                if position < input.count && input[position] == "=" {
                    position += 1
                    tokens.append(Token(kind: .lessOrEqual, position: start))
                } else {
                    tokens.append(Token(kind: .lessThan, position: start))
                }
            case ">":
                let start = position
                position += 1
                if position < input.count && input[position] == "=" {
                    position += 1
                    tokens.append(Token(kind: .greaterOrEqual, position: start))
                } else {
                    tokens.append(Token(kind: .greaterThan, position: start))
                }
            case "\"", "'":
                tokens.append(try scanQuotedString(quote: ch))
            case "-" where position + 1 < input.count && input[position + 1].isNumber:
                tokens.append(scanNumber())
            case _ where ch.isNumber:
                tokens.append(scanNumber())
            case _ where ch.isLetter || ch == "_":
                tokens.append(scanName())
            default:
                throw LexerError.invalidCharacter(ch, position: position)
            }
        }
        tokens.append(Token(kind: .eof, position: position))
        return tokens
    }

    private mutating func scanQuotedString(quote: Character) throws -> Token {
        let start = position
        position += 1 // skip opening quote
        var value: [Character] = []
        while position < input.count && input[position] != quote {
            if input[position] == "\\" && position + 1 < input.count {
                position += 1
                value.append(input[position])
            } else {
                value.append(input[position])
            }
            position += 1
        }
        guard position < input.count else {
            throw LexerError.unterminatedString(position: start)
        }
        position += 1 // skip closing quote
        return Token(kind: .quotedString(String(value)), position: start)
    }

    private mutating func scanNumber() -> Token {
        let start = position
        var numStr = ""
        if input[position] == "-" {
            numStr.append("-")
            position += 1
        }
        while position < input.count && input[position].isNumber {
            numStr.append(input[position])
            position += 1
        }
        return Token(kind: .integer(Int(numStr)!), position: start)
    }

    private static let keywords: Set<String> = ["and", "or"]

    private mutating func scanName() -> Token {
        let start = position
        var chars: [Character] = []
        // Greedily consume letters, digits, underscores, and spaces (for multi-word SDEF names)
        while position < input.count {
            let ch = input[position]
            if ch.isLetter || ch.isNumber || ch == "_" {
                chars.append(ch)
                position += 1
            } else if ch == " " {
                // Peek ahead: only consume space if followed by a letter/digit/underscore
                // (i.e., it's part of a multi-word name)
                if position + 1 < input.count {
                    let next = input[position + 1]
                    if next.isLetter || next == "_" {
                        chars.append(ch)
                        position += 1
                    } else {
                        break
                    }
                } else {
                    break
                }
            } else {
                break
            }
        }
        let name = String(chars).trimmingCharacters(in: .whitespaces)

        // Check if the entire name is a keyword
        if Self.keywords.contains(name.lowercased()) {
            return keywordToken(name.lowercased(), position: start)
        }

        // Check if the name starts with a keyword followed by a space
        // e.g., "or name" should be split into keyword "or" and leave "name" for next scan
        for kw in Self.keywords {
            if name.lowercased().hasPrefix(kw),
               name.count > kw.count,
               name[name.index(name.startIndex, offsetBy: kw.count)] == " " {
                // Reset position to just after the keyword
                position = start + kw.count
                return keywordToken(kw, position: start)
            }
        }

        return Token(kind: .name(name), position: start)
    }

    private func keywordToken(_ keyword: String, position: Int) -> Token {
        switch keyword {
        case "and": return Token(kind: .and, position: position)
        case "or": return Token(kind: .or, position: position)
        default: return Token(kind: .name(keyword), position: position)
        }
    }
}

public enum LexerError: Error, Equatable, LocalizedError {
    case invalidCharacter(Character, position: Int)
    case unterminatedString(position: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCharacter(let ch, let pos):
            return "Invalid character '\(ch)' at position \(pos)"
        case .unterminatedString(let pos):
            return "Unterminated string starting at position \(pos)"
        }
    }
}
