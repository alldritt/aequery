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

    @Flag(name: .long, help: "Log each Apple Event sent and its result to stderr")
    var log: Bool = false

    @Option(name: .long, help: "Maximum containment depth for path enumeration (default 6)")
    var maxDepth: Int = 6

    @Option(name: .long, help: "Per-event timeout in seconds for dynamic tests (default 10)")
    var timeout: Int = 10

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
        var eventTimer: EventTimer? = nil
        if dynamic {
            let timer = EventTimer()
            eventTimer = timer
            let tester = DynamicTester(dictionary: dictionary, appName: appName, maxDepth: maxDepth, log: log, timer: timer, timeout: timeout)
            findings.append(contentsOf: tester.runTests(pathFinder: pathFinder))
        }

        // Output report
        if json {
            printJSONReport(findings, timer: eventTimer)
        } else {
            printTextReport(findings, dictionary: dictionary, timer: eventTimer)
        }

        // Exit with failure if any errors found
        if findings.contains(where: { $0.severity == .error }) {
            throw ExitCode.failure
        }
    }

    private func printTextReport(_ findings: [LintFinding], dictionary: ScriptingDictionary, timer: EventTimer? = nil) {
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

        // Dynamic test summary
        if dynamic {
            printDynamicSummary(findings)
            if let timer = timer {
                printTimingReport(timer)
            }
        }

        // Quality score
        printQualityScore(findings)
    }

    private func printDynamicSummary(_ findings: [LintFinding]) {
        let dynamicFindings = findings.filter { $0.category.hasPrefix("dynamic") }
        guard !dynamicFindings.isEmpty else { return }

        print(String(repeating: "=", count: 40))
        print("Dynamic Test Summary")
        print(String(repeating: "-", count: 40))

        // Collect categories and their summary findings
        let categories: [(prefix: String, label: String)] = [
            ("dynamic-property", "Application properties"),
            ("dynamic-count", "Element counting"),
            ("dynamic-element-prop", "Element properties"),
            ("dynamic-access", "Access forms"),
            ("dynamic-explore", "Sub-element exploration"),
            ("dynamic-every", "Every-element retrieval"),
            ("dynamic-whose", "Whose clause (equals)"),
            ("dynamic-whose-ops", "Whose clause operators"),
            ("dynamic-exists", "Exists event"),
            ("dynamic-type", "Type validation"),
            ("dynamic-range", "Range access"),
            ("dynamic-inherit", "Inherited properties"),
            ("dynamic-error", "Error handling"),
            ("dynamic-set", "Set property"),
            ("dynamic-pall", "Properties record"),
            ("dynamic-whose-num", "Numeric whose operators"),
            ("dynamic-crud", "Make/delete round-trip"),
            ("dynamic-timing", "Timing"),
        ]

        for (prefix, label) in categories {
            let catFindings = dynamicFindings.filter { $0.category == prefix }
            guard !catFindings.isEmpty else { continue }

            let hasWarnings = catFindings.contains { $0.severity == .warning }
            let hasErrors = catFindings.contains { $0.severity == .error }
            let symbol = hasErrors ? "X" : (hasWarnings ? "!" : ".")
            // Find the summary finding (first info for timing, last info for others)
            if let summary = prefix == "dynamic-timing"
                ? catFindings.first(where: { $0.severity == .info })
                : catFindings.last(where: { $0.severity == .info }) {
                // Strip redundant label prefix from message (e.g. "Set property: 23 writable..." → "23 writable...")
                let msg = stripLabelPrefix(summary.message, label: label)
                print("  \(symbol) \(label): \(msg)")
            } else if let first = catFindings.first {
                print("  \(symbol) \(label): \(first.message)")
            }
        }
        print()
    }

    private func stripLabelPrefix(_ message: String, label: String) -> String {
        // Try stripping "Label: " prefix from messages like "Set property: 23 writable..."
        let prefixes = [
            "\(label): ",
            "\(label.lowercased()): ",
        ]
        for prefix in prefixes {
            if message.hasPrefix(prefix) {
                return String(message.dropFirst(prefix.count))
            }
        }
        return message
    }

    private func printTimingReport(_ timer: EventTimer) {
        let events = timer.events
        guard !events.isEmpty else { return }

        print(String(repeating: "=", count: 40))
        print("Event Timing")
        print(String(repeating: "-", count: 40))

        let total = timer.totalDuration
        let avg = total / Double(events.count)
        print("  Events: \(events.count), Total: \(String(format: "%.1f", total))s, Avg: \(String(format: "%.3f", avg))s")
        if timer.timeoutCount > 0 {
            print("  Timeouts: \(timer.timeoutCount)")
        }
        print()

        let slowest = timer.slowestEvents.prefix(10)
        print("  Slowest events:")
        for (i, event) in slowest.enumerated() {
            let marker = event.isTimeout ? " TIMEOUT" : ""
            print("    \(i + 1). \(String(format: "%.3f", event.duration))s\(marker) — \(event.command)")
        }
        print()
    }

    private func computeQualityScore(_ findings: [LintFinding]) -> (score: Int, grade: String) {
        let errors = findings.filter { $0.severity == .error }.count
        let warnings = findings.filter { $0.severity == .warning }.count

        // Start at 100, deduct for issues (with caps to prevent floor-out)
        let errorPenalty = min(40, errors * 5)
        let warningPenalty = min(30, warnings)
        var score = 100 - errorPenalty - warningPenalty
        score = max(0, min(100, score))

        let grade: String
        switch score {
        case 90...100: grade = "A"
        case 80..<90: grade = "B"
        case 70..<80: grade = "C"
        case 60..<70: grade = "D"
        default: grade = "F"
        }

        return (score, grade)
    }

    private func printQualityScore(_ findings: [LintFinding]) {
        let (score, grade) = computeQualityScore(findings)

        print(String(repeating: "=", count: 40))
        print("Quality Score: \(score)/100 (\(grade))")
        print(String(repeating: "=", count: 40))
    }

    private func printJSONReport(_ findings: [LintFinding], timer: EventTimer? = nil) {
        var report: [String: Any] = [:]

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
        report["findings"] = items

        let (score, grade) = computeQualityScore(findings)
        report["qualityScore"] = ["score": score, "grade": grade] as [String: Any]

        if let timer = timer {
            var timing: [String: Any] = [
                "eventCount": timer.events.count,
                "totalSeconds": Double(String(format: "%.3f", timer.totalDuration))!,
                "timeoutCount": timer.timeoutCount,
            ]
            if !timer.events.isEmpty {
                timing["averageSeconds"] = Double(String(format: "%.3f", timer.totalDuration / Double(timer.events.count)))!
            }
            let slowest: [[String: Any]] = timer.slowestEvents.prefix(10).map { event in
                [
                    "command": event.command,
                    "seconds": Double(String(format: "%.3f", event.duration))!,
                    "timeout": event.isTimeout,
                ]
            }
            timing["slowest"] = slowest
            report["timing"] = timing
        }

        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
