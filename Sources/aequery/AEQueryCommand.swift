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

    @Flag(name: .long, help: "Output as AppleScript using terminology")
    var applescript: Bool = false

    @Flag(name: .long, help: "Output as AppleScript using chevron syntax")
    var chevron: Bool = false

    @Flag(name: .long, help: "Flatten nested lists into a single list")
    var flatten: Bool = false

    @Flag(name: .long, help: "Remove duplicate values from the result list (use with --flatten)")
    var unique: Bool = false

    @Flag(name: .long, help: "Show verbose debug output on stderr")
    var verbose: Bool = false

    @Flag(name: .long, help: "Parse and resolve only, do not send Apple Events")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Print the SDEF definition for the resolved element or property")
    var sdef: Bool = false

    @Flag(name: .long, help: "Find all valid paths from the application root to the target")
    var findPaths: Bool = false

    @Option(name: .long, help: "Apple Event timeout in seconds (default 120, -1 for no timeout)")
    var timeout: Int = 120

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

        // 3a. Find paths (early exit)
        if findPaths {
            let pathFinder = SDEFPathFinder(dictionary: dictionary)
            let target = query.steps.last?.name ?? "application"
            let paths = pathFinder.findPaths(to: target)
            if paths.isEmpty {
                FileHandle.standardError.write("No paths found to '\(target)'\n")
                throw ExitCode.failure
            }
            var prevWasElementOnly = true
            for path in paths {
                let isElementOnly = path.propertyIntermediateCount == 0
                if !isElementOnly && prevWasElementOnly && paths.count > 1 {
                    print("---")
                }
                prevWasElementOnly = isElementOnly
                if path.expression.isEmpty {
                    print("/\(query.appName)")
                } else {
                    print("/\(query.appName)/\(path.expression)")
                }
            }
            return
        }

        // 4. Resolve
        let resolver = SDEFResolver(dictionary: dictionary)
        let resolved = try resolver.resolve(query)

        if verbose {
            for step in resolved.steps {
                FileHandle.standardError.write("  \(step.kind) \(step.name) → '\(step.code)'\n")
            }
        }

        if sdef {
            let info = try resolver.sdefInfo(for: query)
            print(formatSDEFInfo(info))
            return
        }

        if dryRun {
            FileHandle.standardError.write("Dry run: parsed and resolved successfully.\n")
            return
        }

        // 5. Build specifier
        let builder = ObjectSpecifierBuilder(dictionary: dictionary)
        let specifier = builder.buildSpecifier(from: resolved)

        if verbose {
            FileHandle.standardError.write("Specifier: \(specifier)\n")
        }

        // 6. Send
        let sender = AppleEventSender()
        let reply: NSAppleEventDescriptor
        do {
            reply = try sender.sendGetEvent(to: query.appName, specifier: specifier, timeoutSeconds: timeout)
        } catch let error as AEQueryError {
            if case .appleEventFailed(let code, _, let obj) = error {
                let asFormatter = AppleScriptFormatter(style: .terminology, dictionary: dictionary, appName: query.appName)
                if let obj = obj {
                    let objStr = asFormatter.formatSpecifier(obj)
                    throw AEQueryError.appleEventFailed(code, "Can't get \(objStr).", nil)
                }
            }
            throw error
        }

        // 7. Decode
        let decoder = DescriptorDecoder()
        var value = decoder.decode(reply)

        // 7a. Flatten if requested
        if flatten { value = value.flattened() }

        // 7b. Deduplicate if requested
        if unique { value = value.uniqued() }

        // 8. Format and output
        if applescript || chevron {
            let style: AppleScriptFormatter.Style = applescript ? .terminology : .chevron
            let asFormatter = AppleScriptFormatter(style: style, dictionary: dictionary, appName: query.appName)
            print(asFormatter.format(value))
        } else {
            let formatter = OutputFormatter(format: outputFormat, dictionary: dictionary, appName: query.appName)
            let output = formatter.format(value)
            print(output)
        }
    }
}

func formatSDEFInfo(_ info: SDEFInfo) -> String {
    switch info {
    case .classInfo(let cls):
        var lines: [String] = []
        var header = "class \(cls.name) '\(cls.code)'"
        if let plural = cls.pluralName { header += " (\(plural))" }
        if let inherits = cls.inherits { header += " : \(inherits)" }
        lines.append(header)

        if !cls.properties.isEmpty {
            lines.append("  properties:")
            for prop in cls.properties {
                var line = "    \(prop.name) '\(prop.code)'"
                if let type = prop.type { line += " : \(type)" }
                if let access = prop.access {
                    switch access {
                    case .readOnly: line += " [r]"
                    case .readWrite: line += " [rw]"
                    case .writeOnly: line += " [w]"
                    }
                }
                lines.append(line)
            }
        }

        if !cls.elements.isEmpty {
            lines.append("  elements:")
            for (name, code) in cls.elements {
                lines.append("    \(name) '\(code)'")
            }
        }

        return lines.joined(separator: "\n")

    case .propertyInfo(let prop):
        var line = "property \(prop.name) '\(prop.code)'"
        if let type = prop.type { line += " : \(type)" }
        if let access = prop.access {
            switch access {
            case .readOnly: line += " [r]"
            case .readWrite: line += " [rw]"
            case .writeOnly: line += " [w]"
            }
        }
        line += "  (in class \(prop.inClass))"
        return line
    }
}

extension FileHandle {
    func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.write(data)
        }
    }
}
