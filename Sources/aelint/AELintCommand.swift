import ArgumentParser
import AEQueryLib
import Foundation

@main
struct AELintCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aelint",
        abstract: "Validate and test a scriptable application's scripting interface.",
        version: "0.1.0"
    )

    @Argument(help: "The application name to validate, e.g. 'Finder'")
    var appName: String

    @Option(name: .long, help: "Load SDEF from a file path instead of from the application bundle")
    var sdefFile: String? = nil

    @Flag(name: .long, help: "Run dynamic tests (sends Apple Events to the running application)")
    var dynamic: Bool = false

    @Flag(name: .long, help: "Output report as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Maximum containment depth for path enumeration (default 6)")
    var maxDepth: Int = 6

    func run() throws {
        // Load SDEF
        let dictionary: ScriptingDictionary
        if let sdefFile = sdefFile {
            let data = try Data(contentsOf: URL(fileURLWithPath: sdefFile))
            dictionary = try SDEFParser().parse(data: data)
        } else {
            let loader = SDEFLoader()
            let (dict, _) = try loader.loadSDEF(forApp: appName)
            dictionary = dict
        }

        // Run static validation
        let validator = SDEFValidator(dictionary: dictionary, appName: appName)
        var findings = validator.validate()

        // Enumerate paths and check reachability
        let pathFinder = SDEFPathFinder(dictionary: dictionary)
        findings.append(contentsOf: validator.validateReachability(pathFinder: pathFinder, maxDepth: maxDepth))

        // Dynamic tests
        if dynamic {
            let tester = DynamicTester(dictionary: dictionary, appName: appName, maxDepth: maxDepth)
            findings.append(contentsOf: tester.runTests(pathFinder: pathFinder))
        }

        // Output report
        if json {
            printJSONReport(findings)
        } else {
            printTextReport(findings, dictionary: dictionary)
        }

        // Exit with failure if any errors found
        if findings.contains(where: { $0.severity == .error }) {
            throw ExitCode.failure
        }
    }

    private func printTextReport(_ findings: [LintFinding], dictionary: ScriptingDictionary) {
        let errors = findings.filter { $0.severity == .error }
        let warnings = findings.filter { $0.severity == .warning }
        let info = findings.filter { $0.severity == .info }

        let enumCount = dictionary.enumerations.count
        let cmdCount = dictionary.commands.count

        print("aelint report for \(appName)")
        print(String(repeating: "=", count: 40))
        print("Classes: \(dictionary.classes.count), Commands: \(cmdCount), Enumerations: \(enumCount)")
        print("Findings: \(errors.count) errors, \(warnings.count) warnings, \(info.count) info")
        print()

        for severity in [LintSeverity.error, .warning, .info] {
            let group = findings.filter { $0.severity == severity }
            if group.isEmpty { continue }
            print("\(severity.symbol) \(severity.rawValue.uppercased()) (\(group.count))")
            print(String(repeating: "-", count: 40))
            for finding in group {
                print("  \(finding.category): \(finding.message)")
                if let context = finding.context {
                    print("    \(context)")
                }
            }
            print()
        }

        if findings.isEmpty {
            print("No issues found.")
        }
    }

    private func printJSONReport(_ findings: [LintFinding]) {
        let items: [[String: String]] = findings.map { finding in
            var dict: [String: String] = [
                "severity": finding.severity.rawValue,
                "category": finding.category,
                "message": finding.message,
            ]
            if let context = finding.context {
                dict["context"] = context
            }
            return dict
        }
        if let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
