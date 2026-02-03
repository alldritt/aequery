import ArgumentParser
import AEQueryLib
import Foundation

@main
struct AEQueryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aequery",
        abstract: "Query scriptable applications using XPath-like expressions.",
        version: "0.1.0"
    )

    @Argument(help: "The XPath-like expression to evaluate, e.g. '/Finder/windows/name'")
    var expression: String

    @Flag(name: .long, help: "Output as JSON (default)")
    var json: Bool = false

    @Flag(name: .long, help: "Output as plain text")
    var text: Bool = false

    @Flag(name: .long, help: "Show verbose debug output on stderr")
    var verbose: Bool = false

    @Flag(name: .long, help: "Parse and resolve only, do not send Apple Events")
    var dryRun: Bool = false

    var outputFormat: OutputFormat {
        text ? .text : .json
    }

    func run() throws {
        // 1. Lex
        var lexer = Lexer(expression)
        let tokens = try lexer.tokenize()

        if verbose {
            FileHandle.standardError.write("Tokens: \(tokens.map { "\($0.kind)" }.joined(separator: ", "))\n")
        }

        // 2. Parse
        var parser = Parser(tokens: tokens)
        let query = try parser.parse()

        if verbose {
            FileHandle.standardError.write("AST: app=\(query.appName), steps=\(query.steps.map { "\($0.name)[\($0.predicates.count) preds]" })\n")
        }

        // 3. Load SDEF
        let loader = SDEFLoader()
        let dictionary = try loader.loadSDEF(forApp: query.appName)

        if verbose {
            FileHandle.standardError.write("SDEF: \(dictionary.classes.count) classes loaded\n")
        }

        // 4. Resolve
        let resolver = SDEFResolver(dictionary: dictionary)
        let resolved = try resolver.resolve(query)

        if verbose {
            for step in resolved.steps {
                FileHandle.standardError.write("  \(step.kind) \(step.name) → '\(step.code)'\n")
            }
        }

        if dryRun {
            FileHandle.standardError.write("Dry run: parsed and resolved successfully.\n")
            return
        }

        // 5. Build specifier
        let builder = ObjectSpecifierBuilder()
        let specifier = builder.buildSpecifier(from: resolved)

        if verbose {
            FileHandle.standardError.write("Specifier: \(specifier)\n")
        }

        // 6. Send
        let sender = AppleEventSender()
        let reply = try sender.sendGetEvent(to: query.appName, specifier: specifier)

        // 7. Decode
        let decoder = DescriptorDecoder()
        let value = decoder.decode(reply)

        // 8. Format and output
        let formatter = OutputFormatter(format: outputFormat)
        let output = formatter.format(value)
        print(output)
    }
}

extension FileHandle {
    func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.write(data)
        }
    }
}
