import AEQueryLib
import Foundation

struct DynamicTester {
    let dictionary: ScriptingDictionary
    let appName: String
    let maxDepth: Int

    private let sender = AppleEventSender()
    private let builder: ObjectSpecifierBuilder

    init(dictionary: ScriptingDictionary, appName: String, maxDepth: Int) {
        self.dictionary = dictionary
        self.appName = appName
        self.maxDepth = maxDepth
        self.builder = ObjectSpecifierBuilder(dictionary: dictionary)
    }

    func runTests(pathFinder: SDEFPathFinder) -> [LintFinding] {
        var findings: [LintFinding] = []

        // Verify the app is running and reachable
        guard verifyAppReachable(&findings) else {
            return findings
        }

        // Test 1: Get all application properties
        findings.append(contentsOf: testApplicationProperties())

        // Test 2: Count direct elements of application
        findings.append(contentsOf: testApplicationElements())

        // Test 3: For elements with count > 0, test getting properties of first element
        findings.append(contentsOf: testFirstElementProperties())

        // Test 4: Test access forms (by index, by name) on elements
        findings.append(contentsOf: testAccessForms())

        return findings
    }

    // MARK: - App reachability

    private func verifyAppReachable(_ findings: inout [LintFinding]) -> Bool {
        // Try to get the application's name property
        let nameSpec = builder.buildPropertySpecifier(
            code: "pnam",
            container: NSAppleEventDescriptor.null()
        )
        do {
            _ = try sender.sendGetEvent(to: appName, specifier: nameSpec, timeoutSeconds: 10)
            findings.append(LintFinding(
                .info, category: "dynamic",
                message: "Application '\(appName)' is running and responding to Apple Events"
            ))
            return true
        } catch let error as AEQueryError {
            findings.append(LintFinding(
                .error, category: "dynamic",
                message: "Cannot reach application '\(appName)': \(error.localizedDescription)"
            ))
            return false
        } catch {
            findings.append(LintFinding(
                .error, category: "dynamic",
                message: "Cannot reach application '\(appName)': \(error.localizedDescription)"
            ))
            return false
        }
    }

    // MARK: - Application properties

    private func testApplicationProperties() -> [LintFinding] {
        var findings: [LintFinding] = []

        guard let appClass = dictionary.findClass("application") else {
            findings.append(LintFinding(
                .warning, category: "dynamic",
                message: "No 'application' class found in SDEF, skipping property tests"
            ))
            return findings
        }

        let allProps = dictionary.allProperties(for: appClass)
        var successCount = 0
        var failCount = 0

        for prop in allProps {
            if prop.hidden { continue }
            // Skip write-only properties
            if prop.access == .writeOnly { continue }

            let specifier = builder.buildPropertySpecifier(
                code: prop.code,
                container: NSAppleEventDescriptor.null()
            )

            do {
                _ = try sender.sendGetEvent(to: appName, specifier: specifier, timeoutSeconds: 10)
                successCount += 1
            } catch let error as AEQueryError {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-property",
                    message: "Cannot get application property '\(prop.name)' (\(prop.code)): \(error.localizedDescription)"
                ))
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-property",
                    message: "Cannot get application property '\(prop.name)' (\(prop.code)): \(error.localizedDescription)"
                ))
            }
        }

        findings.append(LintFinding(
            .info, category: "dynamic-property",
            message: "Application properties: \(successCount) readable, \(failCount) failed"
        ))

        return findings
    }

    // MARK: - Application elements (count)

    private func testApplicationElements() -> [LintFinding] {
        var findings: [LintFinding] = []

        guard let appClass = dictionary.findClass("application") else {
            return findings
        }

        let allElems = dictionary.allElements(for: appClass)
        var successCount = 0
        var failCount = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }

            let elementCode = FourCharCode(elemClass.code)

            do {
                let count = try sender.sendCountEvent(
                    to: appName,
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    timeoutSeconds: 10
                )
                successCount += 1
                findings.append(LintFinding(
                    .info, category: "dynamic-count",
                    message: "count of \(elemClass.pluralName ?? elemClass.name): \(count)"
                ))
            } catch let error as AEQueryError {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-count",
                    message: "Cannot count '\(elemClass.name)' elements (\(elemClass.code)): \(error.localizedDescription)"
                ))
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-count",
                    message: "Cannot count '\(elemClass.name)' elements (\(elemClass.code)): \(error.localizedDescription)"
                ))
            }
        }

        findings.append(LintFinding(
            .info, category: "dynamic-count",
            message: "Element counting: \(successCount) succeeded, \(failCount) failed"
        ))

        return findings
    }

    // MARK: - First element properties

    /// For each countable element type of application with count > 0,
    /// get the first element and test reading its properties.
    private func testFirstElementProperties() -> [LintFinding] {
        var findings: [LintFinding] = []

        guard let appClass = dictionary.findClass("application") else {
            return findings
        }

        let allElems = dictionary.allElements(for: appClass)

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)

            // First check if there are any elements
            let count: Int
            do {
                count = try sender.sendCountEvent(
                    to: appName,
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    timeoutSeconds: 10
                )
            } catch {
                continue  // already reported in testApplicationElements
            }

            guard count > 0 else { continue }

            // Get properties of first element
            let firstElemSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )

            let allProps = dictionary.allProperties(for: elemClass)
            var propSuccess = 0
            var propFail = 0

            for prop in allProps {
                if prop.hidden { continue }
                if prop.access == .writeOnly { continue }

                let propSpec = builder.buildPropertySpecifier(
                    code: prop.code,
                    container: firstElemSpec
                )

                do {
                    _ = try sender.sendGetEvent(to: appName, specifier: propSpec, timeoutSeconds: 10)
                    propSuccess += 1
                } catch {
                    propFail += 1
                    findings.append(LintFinding(
                        .warning, category: "dynamic-element-prop",
                        message: "Cannot get property '\(prop.name)' of first \(elemClass.name): \(error.localizedDescription)"
                    ))
                }
            }

            if propFail > 0 || propSuccess > 0 {
                findings.append(LintFinding(
                    .info, category: "dynamic-element-prop",
                    message: "\(elemClass.name) properties: \(propSuccess) readable, \(propFail) failed"
                ))
            }
        }

        return findings
    }

    // MARK: - Access form testing

    /// Test different access forms (by index, by name, by ID) on elements that have instances.
    private func testAccessForms() -> [LintFinding] {
        var findings: [LintFinding] = []

        guard let appClass = dictionary.findClass("application") else {
            return findings
        }

        let allElems = dictionary.allElements(for: appClass)

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)

            // Check if there are any elements
            let count: Int
            do {
                count = try sender.sendCountEvent(
                    to: appName,
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    timeoutSeconds: 10
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            var forms: [String] = []

            // Test by-index (already known to work from testFirstElementProperties)
            forms.append("by index")

            // Test by-name: get name of first, then access by that name
            let allProps = dictionary.allProperties(for: elemClass)
            let hasNameProp = allProps.contains { $0.code == "pnam" }

            if hasNameProp {
                let firstElemSpec = builder.buildElementWithPredicate(
                    code: elemClass.code,
                    predicate: .byIndex(1),
                    container: NSAppleEventDescriptor.null()
                )
                let nameSpec = builder.buildPropertySpecifier(
                    code: "pnam",
                    container: firstElemSpec
                )
                if let nameReply = try? sender.sendGetEvent(to: appName, specifier: nameSpec, timeoutSeconds: 10),
                   let name = nameReply.stringValue, !name.isEmpty {
                    // Now try to access by that name
                    let byNameSpec = builder.buildElementWithPredicate(
                        code: elemClass.code,
                        predicate: .byName(name),
                        container: NSAppleEventDescriptor.null()
                    )
                    let byNamePropSpec = builder.buildPropertySpecifier(
                        code: "pnam",
                        container: byNameSpec
                    )
                    if let _ = try? sender.sendGetEvent(to: appName, specifier: byNamePropSpec, timeoutSeconds: 10) {
                        forms.append("by name")
                    }
                }
            }

            // Test by-ID: check if class has an 'id' property (ID  )
            let hasIDProp = allProps.contains { $0.code == "ID  " }
            if hasIDProp {
                let firstElemSpec = builder.buildElementWithPredicate(
                    code: elemClass.code,
                    predicate: .byIndex(1),
                    container: NSAppleEventDescriptor.null()
                )
                let idSpec = builder.buildPropertySpecifier(
                    code: "ID  ",
                    container: firstElemSpec
                )
                if let idReply = try? sender.sendGetEvent(to: appName, specifier: idSpec, timeoutSeconds: 10) {
                    // Try to use the ID to access the element
                    let idValue: Value
                    if idReply.descriptorType == typeType(for: "long") || idReply.descriptorType == typeType(for: "shor") {
                        idValue = .integer(Int(idReply.int32Value))
                    } else if let str = idReply.stringValue {
                        idValue = .string(str)
                    } else {
                        idValue = .integer(Int(idReply.int32Value))
                    }

                    let byIDSpec = builder.buildElementWithPredicate(
                        code: elemClass.code,
                        predicate: .byID(idValue),
                        container: NSAppleEventDescriptor.null()
                    )
                    let byIDPropSpec = builder.buildPropertySpecifier(
                        code: "pnam",
                        container: byIDSpec
                    )
                    if let _ = try? sender.sendGetEvent(to: appName, specifier: byIDPropSpec, timeoutSeconds: 10) {
                        forms.append("by ID")
                    }
                }
            }

            findings.append(LintFinding(
                .info, category: "dynamic-access",
                message: "\(elemClass.name): supported access forms: \(forms.joined(separator: ", "))"
            ))
        }

        return findings
    }

    private func typeType(for code: String) -> DescType {
        let chars = Array(code.utf8)
        guard chars.count == 4 else { return 0 }
        return DescType(chars[0]) << 24 | DescType(chars[1]) << 16 | DescType(chars[2]) << 8 | DescType(chars[3])
    }
}
