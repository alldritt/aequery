import Testing
import Foundation
@testable import AEQueryLib

/// Integration tests that require live applications.
/// Finder is always running on macOS, so these tests should work on any Mac.
@Suite("Integration", .tags(.integration))
struct IntegrationTests {
    /// Full pipeline: lex → parse → load SDEF → resolve → build → send → decode
    private func query(_ expression: String, dryRun: Bool = false) throws -> AEValue {
        var lexer = Lexer(expression)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let aeQuery = try parser.parse()

        let loader = SDEFLoader()
        let (dictionary, _) = try loader.loadSDEF(forApp: aeQuery.appName)
        let resolver = SDEFResolver(dictionary: dictionary)
        let resolved = try resolver.resolve(aeQuery)

        if dryRun {
            return .null
        }

        let builder = ObjectSpecifierBuilder()
        let specifier = builder.buildSpecifier(from: resolved)
        let sender = AppleEventSender()
        let reply = try sender.sendGetEvent(to: aeQuery.appName, specifier: specifier)
        return DescriptorDecoder().decode(reply)
    }

    @Test func testFinderDesktopName() throws {
        let result = try query("/Finder/desktop/name")
        #expect(result == .string("Desktop"))
    }

    @Test func testDryRunDoesNotSend() throws {
        let result = try query("/Finder/windows/name", dryRun: true)
        #expect(result == .null)
    }

    @Test func testInvalidAppError() throws {
        #expect(throws: (any Error).self) {
            try query("/NonExistentApp12345/windows")
        }
    }

    @Test func testInvalidPathError() throws {
        #expect(throws: (any Error).self) {
            try query("/Finder/foobar")
        }
    }

    @Test func testFinderSDEFLoads() throws {
        let loader = SDEFLoader()
        let (dict, _) = try loader.loadSDEF(forApp: "Finder")
        #expect(dict.findClass("application") != nil)
        #expect(dict.findClass("window") != nil)
    }

    @Test func testFinderResolveWindowsName() throws {
        var lexer = Lexer("/Finder/windows/name")
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let aeQuery = try parser.parse()
        let loader = SDEFLoader()
        let (dict, _) = try loader.loadSDEF(forApp: "Finder")
        let resolved = try SDEFResolver(dictionary: dict).resolve(aeQuery)
        #expect(resolved.steps.count == 2)
        #expect(resolved.steps[0].kind == .element)
        #expect(resolved.steps[1].kind == .property)
        #expect(resolved.steps[1].code == "pnam")
    }
}

extension Tag {
    @Tag static var integration: Self
}
