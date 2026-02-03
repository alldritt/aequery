import Testing
@testable import AEQueryLib

@Suite("Lexer")
struct LexerTests {
    private func tokenize(_ input: String) throws -> [Token] {
        var lexer = Lexer(input)
        return try lexer.tokenize()
    }

    private func kinds(_ input: String) throws -> [TokenKind] {
        try tokenize(input).map(\.kind)
    }

    @Test func testSimplePath() throws {
        let k = try kinds("/Finder/windows/name")
        #expect(k == [.slash, .name("Finder"), .slash, .name("windows"), .slash, .name("name"), .eof])
    }

    @Test func testQuotedAppName() throws {
        let k = try kinds("/\"Script Debugger\"/windows")
        #expect(k == [.slash, .quotedString("Script Debugger"), .slash, .name("windows"), .eof])
    }

    @Test func testNameWithSpaces() throws {
        let k = try kinds("/Finder/alias files")
        #expect(k == [.slash, .name("Finder"), .slash, .name("alias files"), .eof])
    }

    @Test func testByIndexTokens() throws {
        let k = try kinds("[1]")
        #expect(k == [.leftBracket, .integer(1), .rightBracket, .eof])
    }

    @Test func testByRangeTokens() throws {
        let k = try kinds("[1:3]")
        #expect(k == [.leftBracket, .integer(1), .colon, .integer(3), .rightBracket, .eof])
    }

    @Test func testByNameTokens() throws {
        let k = try kinds("[@name=\"Desktop\"]")
        #expect(k == [.leftBracket, .at, .name("name"), .equals, .quotedString("Desktop"), .rightBracket, .eof])
    }

    @Test func testByIDTokens() throws {
        let k = try kinds("[#id=42]")
        #expect(k == [.leftBracket, .hash, .name("id"), .equals, .integer(42), .rightBracket, .eof])
    }

    @Test func testComparisonTokens() throws {
        let k = try kinds("[size > 1000]")
        #expect(k == [.leftBracket, .name("size"), .greaterThan, .integer(1000), .rightBracket, .eof])
    }

    @Test func testAllComparisonOps() throws {
        let k = try kinds("= != < > <= >=")
        #expect(k == [.equals, .notEquals, .lessThan, .greaterThan, .lessOrEqual, .greaterOrEqual, .eof])
    }

    @Test func testBooleanKeywords() throws {
        let k = try kinds("[x = 1 and y = 2]")
        #expect(k == [
            .leftBracket, .name("x"), .equals, .integer(1),
            .and,
            .name("y"), .equals, .integer(2), .rightBracket, .eof
        ])
    }

    @Test func testNegativeIndex() throws {
        let k = try kinds("[-1]")
        #expect(k == [.leftBracket, .integer(-1), .rightBracket, .eof])
    }

    @Test func testSingleQuotedString() throws {
        let k = try kinds("[@name='Desktop']")
        #expect(k == [.leftBracket, .at, .name("name"), .equals, .quotedString("Desktop"), .rightBracket, .eof])
    }

    @Test func testEmptyInput() throws {
        let k = try kinds("")
        #expect(k == [.eof])
    }

    @Test func testContainsKeyword() throws {
        let k = try kinds("[name contains \"test\"]")
        #expect(k == [
            .leftBracket, .name("name"), .contains, .quotedString("test"), .rightBracket, .eof
        ])
    }

    @Test func testInvalidCharacter() throws {
        #expect(throws: LexerError.self) {
            try kinds("/Finder/windows!")
        }
    }
}
