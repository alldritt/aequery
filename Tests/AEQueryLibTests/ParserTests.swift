import Testing
@testable import AEQueryLib

@Suite("Parser")
struct ParserTests {
    private func parse(_ input: String) throws -> AEQuery {
        var lexer = Lexer(input)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return try parser.parse()
    }

    @Test func testSimplePath() throws {
        let q = try parse("/Finder/windows/name")
        #expect(q.appName == "Finder")
        #expect(q.steps.count == 2)
        #expect(q.steps[0].name == "windows")
        #expect(q.steps[0].predicates.isEmpty)
        #expect(q.steps[1].name == "name")
    }

    @Test func testSingleStep() throws {
        let q = try parse("/Finder/windows")
        #expect(q.appName == "Finder")
        #expect(q.steps.count == 1)
        #expect(q.steps[0].name == "windows")
    }

    @Test func testAppNameOnly() throws {
        let q = try parse("/Finder")
        #expect(q.appName == "Finder")
        #expect(q.steps.isEmpty)
    }

    @Test func testQuotedAppName() throws {
        let q = try parse("/\"Script Debugger\"/windows")
        #expect(q.appName == "Script Debugger")
    }

    @Test func testByIndex() throws {
        let q = try parse("/TextEdit/documents[1]/paragraphs")
        #expect(q.steps[0].predicates == [.byIndex(1)])
    }

    @Test func testByNegativeIndex() throws {
        let q = try parse("/Finder/windows[-1]")
        #expect(q.steps[0].predicates == [.byIndex(-1)])
    }

    @Test func testByRange() throws {
        let q = try parse("/TextEdit/documents[1]/paragraphs[1:5]")
        #expect(q.steps[1].predicates == [.byRange(1, 5)])
    }

    @Test func testByName() throws {
        let q = try parse("/Finder/windows[@name=\"Desktop\"]")
        #expect(q.steps[0].predicates == [.byName("Desktop")])
    }

    @Test func testByID() throws {
        let q = try parse("/Finder/windows[#id=42]")
        #expect(q.steps[0].predicates == [.byID(.integer(42))])
    }

    @Test func testByIDString() throws {
        let q = try parse("/Finder/windows[#id=\"abc\"]")
        #expect(q.steps[0].predicates == [.byID(.string("abc"))])
    }

    @Test func testWhoseClause() throws {
        let q = try parse("/Finder/files[size > 1000]/name")
        if case .test(let expr) = q.steps[0].predicates[0] {
            #expect(expr.path == ["size"])
            #expect(expr.op == .greaterThan)
            #expect(expr.value == .integer(1000))
        } else {
            Issue.record("Expected .test predicate")
        }
    }

    @Test func testWhoseWithSubpath() throws {
        let q = try parse("/TextEdit/windows[name = \"Readme\"]")
        if case .test(let expr) = q.steps[0].predicates[0] {
            #expect(expr.path == ["name"])
            #expect(expr.op == .equal)
            #expect(expr.value == .string("Readme"))
        } else {
            Issue.record("Expected .test predicate")
        }
    }

    @Test func testCompoundAnd() throws {
        let q = try parse("/Mail/messages[size > 100 and read = 1]")
        if case .compound(let left, let op, let right) = q.steps[0].predicates[0] {
            #expect(op == .and)
            if case .test(let l) = left {
                #expect(l.path == ["size"])
                #expect(l.op == .greaterThan)
            } else {
                Issue.record("Expected .test for left")
            }
            if case .test(let r) = right {
                #expect(r.path == ["read"])
                #expect(r.op == .equal)
            } else {
                Issue.record("Expected .test for right")
            }
        } else {
            Issue.record("Expected .compound predicate")
        }
    }

    @Test func testCompoundOr() throws {
        let q = try parse("/Finder/files[size > 100 or name = \"test\"]")
        if case .compound(_, let op, _) = q.steps[0].predicates[0] {
            #expect(op == .or)
        } else {
            Issue.record("Expected .compound predicate")
        }
    }

    @Test func testMultiplePredicates() throws {
        let q = try parse("/Finder/windows[1][@name=\"Desktop\"]")
        #expect(q.steps[0].predicates.count == 2)
        #expect(q.steps[0].predicates[0] == .byIndex(1))
        #expect(q.steps[0].predicates[1] == .byName("Desktop"))
    }

    @Test func testMissingLeadingSlash() throws {
        #expect(throws: ParserError.self) {
            try parse("Finder/windows")
        }
    }

    @Test func testUnclosedBracket() throws {
        #expect(throws: (any Error).self) {
            try parse("/Finder/windows[1")
        }
    }

    @Test func testEmptyPredicate() throws {
        #expect(throws: ParserError.self) {
            try parse("/Finder/windows[]")
        }
    }
}
