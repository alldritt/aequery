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

    @Option(name: .long, help: "Minimum severity to display: error, warning, or info (default: info)")
    var severity: String = "info"

    @Flag(name: .long, help: "Output report as HTML")
    var html: Bool = false

    @Option(name: .long, help: "Slow event threshold in seconds (default 1.0); events above this are flagged as warnings")
    var slowThreshold: Double = 1.0

    @Flag(name: .long, help: "Print SDEF dictionary summary and exit")
    var summary: Bool = false

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

        // Summary mode: print SDEF outline and exit
        if summary {
            printSDEFSummary(dictionary)
            return
        }

        // Run static validation
        let validator = SDEFValidator(dictionary: dictionary, appName: appName)
        var findings = validator.validate()

        // Enumerate paths and check reachability
        let pathFinder = SDEFPathFinder(dictionary: dictionary)
        findings.append(contentsOf: validator.validateReachability(pathFinder: pathFinder, maxDepth: maxDepth))

        // Dynamic tests
        var eventTimer: EventTimer? = nil
        var coverageTracker: CoverageTracker? = nil
        if dynamic {
            let timer = EventTimer()
            eventTimer = timer
            let tester = DynamicTester(dictionary: dictionary, appName: appName, maxDepth: maxDepth, log: log, timer: timer, timeout: timeout)
            findings.append(contentsOf: tester.runTests(pathFinder: pathFinder))
            coverageTracker = tester.coverage

            // Flag slow events above threshold
            for event in timer.events where event.duration >= slowThreshold && !event.isTimeout {
                findings.append(LintFinding(
                    .warning, category: "dynamic-slow",
                    message: "Slow event (\(String(format: "%.3f", event.duration))s >= \(String(format: "%.1f", slowThreshold))s threshold)",
                    context: event.command
                ))
            }
        }

        // Apply severity filter
        let minSeverity = parseSeverity(severity)
        let filteredFindings = findings.filter { severityRank($0.severity) >= severityRank(minSeverity) }

        // Output report
        if json {
            printJSONReport(filteredFindings, timer: eventTimer, coverage: coverageTracker)
        } else if html {
            printHTMLReport(filteredFindings, dictionary: dictionary, timer: eventTimer, coverage: coverageTracker)
        } else {
            printTextReport(filteredFindings, dictionary: dictionary, timer: eventTimer, coverage: coverageTracker)
        }

        // Exit with failure if any errors found
        if findings.contains(where: { $0.severity == .error }) {
            throw ExitCode.failure
        }
    }

    private func printTextReport(_ findings: [LintFinding], dictionary: ScriptingDictionary, timer: EventTimer? = nil, coverage: CoverageTracker? = nil) {
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
            if let coverage = coverage {
                printCoverageReport(coverage)
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
            ("dynamic-ordinal", "Ordinal access"),
            ("dynamic-cmd", "Command testing"),
            ("dynamic-timing", "Timing"),
            ("dynamic-slow", "Slow events"),
            ("dynamic-coverage", "Test coverage"),
        ]

        for (prefix, label) in categories {
            let catFindings = dynamicFindings.filter { $0.category == prefix }
            guard !catFindings.isEmpty else { continue }

            let hasWarnings = catFindings.contains { $0.severity == .warning }
            let hasErrors = catFindings.contains { $0.severity == .error }
            let symbol = hasErrors ? "X" : (hasWarnings ? "!" : ".")
            // Find the summary finding (first info for timing/coverage, last info for others)
            if let summary = (prefix == "dynamic-timing" || prefix == "dynamic-coverage")
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

    private func printCoverageReport(_ coverage: CoverageTracker) {
        print(String(repeating: "=", count: 40))
        print("Test Coverage")
        print(String(repeating: "-", count: 40))
        print("  Classes tested: \(coverage.testedClasses.count)")
        print("  Properties tested: \(coverage.testedProperties.count)")
        print("  Elements tested: \(coverage.testedElements.count)")
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

    private func printJSONReport(_ findings: [LintFinding], timer: EventTimer? = nil, coverage: CoverageTracker? = nil) {
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

        if let coverage = coverage {
            report["coverage"] = [
                "classesTestedCount": coverage.testedClasses.count,
                "propertiesTestedCount": coverage.testedProperties.count,
                "elementsTestedCount": coverage.testedElements.count,
            ] as [String: Any]
        }

        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    // MARK: - Severity filtering

    private func parseSeverity(_ str: String) -> LintSeverity {
        switch str.lowercased() {
        case "error": return .error
        case "warning": return .warning
        default: return .info
        }
    }

    private func severityRank(_ severity: LintSeverity) -> Int {
        switch severity {
        case .error: return 3
        case .warning: return 2
        case .info: return 1
        }
    }

    // MARK: - HTML report

    private func printHTMLReport(_ findings: [LintFinding], dictionary: ScriptingDictionary, timer: EventTimer? = nil, coverage: CoverageTracker? = nil) {
        let errors = findings.filter { $0.severity == .error }
        let warnings = findings.filter { $0.severity == .warning }
        let info = findings.filter { $0.severity == .info }
        let (score, grade) = computeQualityScore(findings)

        let enumCount = dictionary.enumerations.count
        let cmdCount = dictionary.commands.count

        var h = ""
        h += "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        h += "<title>aelint report — \(escapeHTML(appName))</title>\n"
        h += "<style>\n"
        h += """
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 2em; background: #fafafa; color: #222; }
        h1 { border-bottom: 2px solid #333; padding-bottom: 0.3em; }
        h2 { margin-top: 1.5em; color: #444; }
        .summary { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 1em 1.5em; margin-bottom: 1.5em; }
        .score { font-size: 2em; font-weight: bold; display: inline-block; margin-right: 0.5em; }
        .grade-A { color: #2a7; } .grade-B { color: #5a5; } .grade-C { color: #da5; } .grade-D { color: #d85; } .grade-F { color: #d44; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 1em; }
        th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #eee; }
        th { background: #f5f5f5; font-weight: 600; }
        .sev-error { color: #c33; font-weight: bold; }
        .sev-warning { color: #b80; }
        .sev-info { color: #48a; }
        .context { color: #888; font-size: 0.9em; font-style: italic; }
        .phase-ok { color: #2a7; } .phase-warn { color: #b80; } .phase-err { color: #c33; }
        .timing-table td:first-child { text-align: right; font-variant-numeric: tabular-nums; }
        footer { margin-top: 2em; color: #999; font-size: 0.85em; }
        """
        h += "\n</style>\n</head>\n<body>\n"

        // Header
        h += "<h1>aelint report for \(escapeHTML(appName))</h1>\n"

        // Summary box
        h += "<div class=\"summary\">\n"
        h += "<span class=\"score grade-\(grade)\">\(score)/100 (\(grade))</span>\n"
        h += "<br>Classes: \(dictionary.classes.count), Commands: \(cmdCount), Enumerations: \(enumCount)<br>\n"
        h += "Findings: <span class=\"sev-error\">\(errors.count) errors</span>, "
        h += "<span class=\"sev-warning\">\(warnings.count) warnings</span>, "
        h += "<span class=\"sev-info\">\(info.count) info</span>\n"
        h += "</div>\n"

        // Findings table
        if !findings.isEmpty {
            h += "<h2>Findings</h2>\n"
            h += "<table>\n<tr><th>Severity</th><th>Category</th><th>Message</th></tr>\n"
            for finding in findings {
                let sevClass = "sev-\(finding.severity.rawValue)"
                h += "<tr>"
                h += "<td class=\"\(sevClass)\">\(finding.severity.symbol) \(finding.severity.rawValue)</td>"
                h += "<td>\(escapeHTML(finding.category))</td>"
                h += "<td>\(escapeHTML(finding.message))"
                if let ctx = finding.context {
                    h += "<br><span class=\"context\">\(escapeHTML(ctx))</span>"
                }
                h += "</td></tr>\n"
            }
            h += "</table>\n"
        } else {
            h += "<p>No issues found.</p>\n"
        }

        // Dynamic test summary
        if dynamic {
            let dynamicFindings = findings.filter { $0.category.hasPrefix("dynamic") }
            if !dynamicFindings.isEmpty {
                h += "<h2>Dynamic Test Summary</h2>\n"
                h += "<table>\n<tr><th>Phase</th><th>Result</th></tr>\n"

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
                    ("dynamic-ordinal", "Ordinal access"),
                    ("dynamic-cmd", "Command testing"),
                    ("dynamic-timing", "Timing"),
                ]

                for (prefix, label) in categories {
                    let catFindings = dynamicFindings.filter { $0.category == prefix }
                    guard !catFindings.isEmpty else { continue }

                    let hasErrors = catFindings.contains { $0.severity == .error }
                    let hasWarnings = catFindings.contains { $0.severity == .warning }
                    let phaseClass = hasErrors ? "phase-err" : (hasWarnings ? "phase-warn" : "phase-ok")

                    if let summary = prefix == "dynamic-timing"
                        ? catFindings.first(where: { $0.severity == .info })
                        : catFindings.last(where: { $0.severity == .info }) {
                        let msg = stripLabelPrefix(summary.message, label: label)
                        h += "<tr><td class=\"\(phaseClass)\">\(escapeHTML(label))</td><td>\(escapeHTML(msg))</td></tr>\n"
                    } else if let first = catFindings.first {
                        h += "<tr><td class=\"\(phaseClass)\">\(escapeHTML(label))</td><td>\(escapeHTML(first.message))</td></tr>\n"
                    }
                }
                h += "</table>\n"
            }
        }

        // Timing
        if let timer = timer, !timer.events.isEmpty {
            let total = timer.totalDuration
            let avg = total / Double(timer.events.count)

            h += "<h2>Event Timing</h2>\n"
            h += "<p>Events: \(timer.events.count), Total: \(String(format: "%.1f", total))s, "
            h += "Avg: \(String(format: "%.3f", avg))s"
            if timer.timeoutCount > 0 {
                h += ", <span class=\"sev-error\">Timeouts: \(timer.timeoutCount)</span>"
            }
            h += "</p>\n"

            let slowest = timer.slowestEvents.prefix(10)
            h += "<table class=\"timing-table\">\n<tr><th>Time</th><th>Event</th></tr>\n"
            for event in slowest {
                let marker = event.isTimeout ? " <span class=\"sev-error\">TIMEOUT</span>" : ""
                h += "<tr><td>\(String(format: "%.3f", event.duration))s\(marker)</td>"
                h += "<td>\(escapeHTML(event.command))</td></tr>\n"
            }
            h += "</table>\n"
        }

        // Coverage
        if let coverage = coverage {
            h += "<h2>Test Coverage</h2>\n"
            h += "<table>\n<tr><th>Metric</th><th>Count</th></tr>\n"
            h += "<tr><td>Classes tested</td><td>\(coverage.testedClasses.count)</td></tr>\n"
            h += "<tr><td>Properties tested</td><td>\(coverage.testedProperties.count)</td></tr>\n"
            h += "<tr><td>Elements tested</td><td>\(coverage.testedElements.count)</td></tr>\n"
            h += "</table>\n"
        }

        // Footer
        h += "<footer>Generated by aelint \(AELintCommand.configuration.version)</footer>\n"
        h += "</body>\n</html>\n"

        print(h)
    }

    // MARK: - SDEF Summary

    private func printSDEFSummary(_ dictionary: ScriptingDictionary) {
        print("SDEF Summary for \(appName)")
        print(String(repeating: "=", count: 50))

        // Suites
        if !dictionary.suiteNames.isEmpty {
            print("\nSuites: \(dictionary.suiteNames.joined(separator: ", "))")
        }

        // Classes
        let sortedClasses = dictionary.classes.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        print("\nClasses (\(sortedClasses.count)):")
        print(String(repeating: "-", count: 50))
        for cls in sortedClasses {
            let hiddenTag = cls.hidden ? " [hidden]" : ""
            let inheritsTag = cls.inherits.map { " : \($0)" } ?? ""
            let plural = cls.pluralName.map { " (plural: \($0))" } ?? ""
            print("  \(cls.name) [\(cls.code)]\(inheritsTag)\(plural)\(hiddenTag)")

            if let desc = cls.description {
                print("    \(desc)")
            }

            let props = dictionary.allProperties(for: cls).filter { !$0.hidden }
            if !props.isEmpty {
                for prop in props {
                    let typeStr = prop.type.map { ": \($0)" } ?? ""
                    let accessStr = prop.access.map { " (\($0.rawValue))" } ?? ""
                    print("    . \(prop.name)\(typeStr)\(accessStr)")
                }
            }

            let elems = dictionary.allElements(for: cls).filter { !$0.hidden }
            if !elems.isEmpty {
                let elemNames = elems.map(\.type).joined(separator: ", ")
                print("    > elements: \(elemNames)")
            }
        }

        // Commands
        let sortedCommands = dictionary.commands.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        print("\nCommands (\(sortedCommands.count)):")
        print(String(repeating: "-", count: 50))
        for cmd in sortedCommands {
            let hiddenTag = cmd.hidden ? " [hidden]" : ""
            let suiteTag = cmd.suiteName.map { " (\($0))" } ?? ""
            print("  \(cmd.name) [\(cmd.code)]\(suiteTag)\(hiddenTag)")

            if let desc = cmd.description {
                print("    \(desc)")
            }

            if let dp = cmd.directParameter {
                let typeStr = dp.type ?? "any"
                let optStr = dp.optional ? " (optional)" : ""
                print("    direct: \(typeStr)\(optStr)")
            }

            for param in cmd.parameters {
                let nameStr = param.name ?? "?"
                let typeStr = param.type ?? "any"
                let optStr = param.optional ? " (optional)" : ""
                print("    \(nameStr): \(typeStr)\(optStr)")
            }

            if let result = cmd.result {
                let typeStr = result.type ?? "any"
                print("    -> \(typeStr)")
            }
        }

        // Enumerations
        let sortedEnums = dictionary.enumerations.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        print("\nEnumerations (\(sortedEnums.count)):")
        print(String(repeating: "-", count: 50))
        for enumDef in sortedEnums {
            let codeTag = enumDef.code.map { " [\($0)]" } ?? ""
            print("  \(enumDef.name)\(codeTag)")
            for e in enumDef.enumerators {
                print("    \(e.name) [\(e.code)]")
            }
        }
    }

    private func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
