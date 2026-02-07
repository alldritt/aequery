import AEQueryLib
import Foundation

struct DynamicTester {
    let dictionary: ScriptingDictionary
    let appName: String
    let maxDepth: Int
    let log: Bool

    private let sender = AppleEventSender()
    private let builder: ObjectSpecifierBuilder

    init(dictionary: ScriptingDictionary, appName: String, maxDepth: Int, log: Bool = false) {
        self.dictionary = dictionary
        self.appName = appName
        self.maxDepth = maxDepth
        self.log = log
        self.builder = ObjectSpecifierBuilder(dictionary: dictionary)
    }

    // MARK: - Apple Event wrappers with logging

    private var appRef: String { "application \"\(appName)\"" }

    @discardableResult
    private func sendGet(
        _ specifier: NSAppleEventDescriptor,
        command: String
    ) throws -> NSAppleEventDescriptor {
        logEvent(command)
        do {
            let result = try sender.sendGetEvent(to: appName, specifier: specifier, timeoutSeconds: 10)
            logResult(describeResult(result))
            return result
        } catch {
            logResult("ERROR: \(error.localizedDescription)")
            throw error
        }
    }

    private func sendCount(
        container: NSAppleEventDescriptor,
        elementCode: FourCharCode,
        command: String
    ) throws -> Int {
        logEvent(command)
        do {
            let count = try sender.sendCountEvent(
                to: appName, container: container, elementCode: elementCode, timeoutSeconds: 10
            )
            logResult("\(count)")
            return count
        } catch {
            logResult("ERROR: \(error.localizedDescription)")
            throw error
        }
    }

    private func sendExists(
        _ specifier: NSAppleEventDescriptor,
        command: String
    ) throws -> Bool {
        logEvent(command)
        do {
            let exists = try sender.sendExistsEvent(to: appName, specifier: specifier, timeoutSeconds: 10)
            logResult("\(exists)")
            return exists
        } catch {
            logResult("ERROR: \(error.localizedDescription)")
            throw error
        }
    }

    private func sendSet(
        _ specifier: NSAppleEventDescriptor,
        value: NSAppleEventDescriptor,
        command: String
    ) throws {
        logEvent(command)
        do {
            try sender.sendSetEvent(to: appName, specifier: specifier, value: value, timeoutSeconds: 10)
            logResult("ok")
        } catch {
            logResult("ERROR: \(error.localizedDescription)")
            throw error
        }
    }

    private func logEvent(_ command: String) {
        guard log else { return }
        FileHandle.standardError.write(Data("  \u{2192} \(command)\n".utf8))
    }

    private func logResult(_ result: String) {
        guard log else { return }
        FileHandle.standardError.write(Data("  \u{2190} \(result)\n".utf8))
    }

    private func describeResult(_ desc: NSAppleEventDescriptor) -> String {
        if desc.descriptorType == AEConstants.typeAEList {
            let count = desc.numberOfItems
            if count == 0 { return "{}" }
            var items: [String] = []
            for i in 1...min(3, count) {
                if let item = desc.atIndex(i) {
                    items.append(describeResult(item))
                }
            }
            if count > 3 { items.append("...") }
            return "{\(items.joined(separator: ", "))} (\(count) items)"
        }
        if desc.descriptorType == AEConstants.typeObjectSpecifier {
            return "<object specifier>"
        }
        if let str = desc.stringValue {
            if str.count > 60 {
                return "\"\(str.prefix(57))...\""
            }
            return "\"\(str)\""
        }
        let dt = desc.descriptorType
        if dt == typeType(for: "bool") || dt == typeType(for: "true") || dt == typeType(for: "fals") {
            return desc.booleanValue ? "true" : "false"
        }
        if dt == typeType(for: "long") || dt == typeType(for: "shor") {
            return "\(desc.int32Value)"
        }
        if dt == typeType(for: "null") {
            return "missing value"
        }
        return "<\(FourCharCode(dt).stringValue)>"
    }

    // MARK: - Test runner

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

        // Test 5: Recursive sub-element exploration
        findings.append(contentsOf: testSubElements())

        // Test 6: Test every-element retrieval
        findings.append(contentsOf: testEveryElementRetrieval())

        // Test 7: Test whose clause filtering
        findings.append(contentsOf: testWhoseClause())

        // Test 8: Test exists event
        findings.append(contentsOf: testExistsEvent())

        // Test 9: Validate property return types against SDEF declarations
        findings.append(contentsOf: testTypeValidation())

        // Test 10: Range access (items 1 thru N)
        findings.append(contentsOf: testRangeAccess())

        // Test 11: Inherited properties
        findings.append(contentsOf: testInheritedProperties())

        // Test 12: Error handling for invalid references
        findings.append(contentsOf: testErrorHandling())

        // Test 13: Set property (read-write)
        findings.append(contentsOf: testSetProperty())

        // Test 14: Properties record (pALL)
        findings.append(contentsOf: testPropertiesRecord())

        // Test 15: Whose clause operators (contains, begins with, ends with)
        findings.append(contentsOf: testWhoseOperators())

        return findings
    }

    // MARK: - App reachability

    private func verifyAppReachable(_ findings: inout [LintFinding]) -> Bool {
        let nameSpec = builder.buildPropertySpecifier(
            code: "pnam",
            container: NSAppleEventDescriptor.null()
        )
        let cmd = "get name of \(appRef)"
        do {
            _ = try sendGet(nameSpec, command: cmd)
            findings.append(LintFinding(
                .info, category: "dynamic",
                message: "Application '\(appName)' is running and responding to Apple Events"
            ))
            return true
        } catch {
            findings.append(LintFinding(
                .error, category: "dynamic",
                message: "Cannot reach application '\(appName)': \(error.localizedDescription)",
                context: cmd
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
            if prop.access == .writeOnly { continue }

            let specifier = builder.buildPropertySpecifier(
                code: prop.code,
                container: NSAppleEventDescriptor.null()
            )
            let cmd = "get \(prop.name) of \(appRef)"

            do {
                _ = try sendGet(specifier, command: cmd)
                successCount += 1
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-property",
                    message: "Cannot get application property '\(prop.name)' (\(prop.code)): \(error.localizedDescription)",
                    context: cmd
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
            let cmd = "count every \(elemClass.name) of \(appRef)"

            do {
                let count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: cmd
                )
                successCount += 1
                findings.append(LintFinding(
                    .info, category: "dynamic-count",
                    message: "count of \(elemClass.pluralName ?? elemClass.name): \(count)"
                ))
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-count",
                    message: "Cannot count '\(elemClass.name)' elements (\(elemClass.code)): \(error.localizedDescription)",
                    context: cmd
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

            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }

            guard count > 0 else { continue }

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
                let cmd = "get \(prop.name) of \(elemClass.name) 1 of \(appRef)"

                do {
                    _ = try sendGet(propSpec, command: cmd)
                    propSuccess += 1
                } catch {
                    propFail += 1
                    findings.append(LintFinding(
                        .warning, category: "dynamic-element-prop",
                        message: "Cannot get property '\(prop.name)' of first \(elemClass.name): \(error.localizedDescription)",
                        context: cmd
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

            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
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
                if let nameReply = try? sendGet(nameSpec, command: "get name of \(elemClass.name) 1 of \(appRef)"),
                   let name = nameReply.stringValue, !name.isEmpty {
                    let byNameSpec = builder.buildElementWithPredicate(
                        code: elemClass.code,
                        predicate: .byName(name),
                        container: NSAppleEventDescriptor.null()
                    )
                    let byNamePropSpec = builder.buildPropertySpecifier(
                        code: "pnam",
                        container: byNameSpec
                    )
                    if let _ = try? sendGet(byNamePropSpec, command: "get name of \(elemClass.name) \"\(name)\" of \(appRef)") {
                        forms.append("by name")
                    }
                }
            }

            // Test by-ID
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
                if let idReply = try? sendGet(idSpec, command: "get id of \(elemClass.name) 1 of \(appRef)") {
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
                    let idStr = idValue == .integer(Int(idReply.int32Value)) ? "\(idReply.int32Value)" : "\"\(idReply.stringValue ?? "")\""
                    if let _ = try? sendGet(byIDPropSpec, command: "get name of \(elemClass.name) id \(idStr) of \(appRef)") {
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

    // MARK: - Sub-element exploration

    private func testSubElements() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        var visited = Set<String>()
        visited.insert("application")

        let allElems = dictionary.allElements(for: appClass)
        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            let firstElemSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )

            exploreObject(
                specifier: firstElemSpec,
                className: elemClass.name,
                path: "first \(elemClass.name)",
                depth: 1,
                visited: &visited,
                findings: &findings
            )
        }

        return findings
    }

    private func exploreObject(
        specifier: NSAppleEventDescriptor,
        className: String,
        path: String,
        depth: Int,
        visited: inout Set<String>,
        findings: inout [LintFinding]
    ) {
        guard depth < maxDepth else { return }

        let classKey = className.lowercased()
        guard visited.insert(classKey).inserted else {
            findings.append(LintFinding(
                .info, category: "dynamic-explore",
                message: "Skipping '\(className)' at depth \(depth) (already explored)"
            ))
            return
        }

        guard let classDef = dictionary.findClass(className) else { return }

        testPropertyChaining(classDef: classDef, container: specifier, path: path, findings: &findings)

        let allElems = dictionary.allElements(for: classDef)
        var subElemSuccess = 0
        var subElemFail = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let cmd = "count every \(elemClass.name) of \(path) of \(appRef)"
            let count: Int
            do {
                count = try sendCount(
                    container: specifier,
                    elementCode: elementCode,
                    command: cmd
                )
                subElemSuccess += 1
            } catch {
                subElemFail += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-explore",
                    message: "Cannot count \(elemClass.name) elements of \(path): \(error.localizedDescription)",
                    context: cmd
                ))
                continue
            }

            findings.append(LintFinding(
                .info, category: "dynamic-explore",
                message: "count of \(elemClass.pluralName ?? elemClass.name) of \(path): \(count)"
            ))

            guard count > 0 else { continue }

            let firstSubSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: specifier
            )

            exploreObject(
                specifier: firstSubSpec,
                className: elemClass.name,
                path: "first \(elemClass.name) of \(path)",
                depth: depth + 1,
                visited: &visited,
                findings: &findings
            )
        }

        if subElemSuccess > 0 || subElemFail > 0 {
            findings.append(LintFinding(
                .info, category: "dynamic-explore",
                message: "\(className) sub-element counting: \(subElemSuccess) succeeded, \(subElemFail) failed"
            ))
        }
    }

    // MARK: - Property chaining (object specifier and list results)

    private func testPropertyChaining(
        classDef: ClassDef,
        container: NSAppleEventDescriptor,
        path: String,
        findings: inout [LintFinding]
    ) {
        let allProps = dictionary.allProperties(for: classDef)

        for prop in allProps {
            if prop.hidden { continue }
            if prop.access == .writeOnly { continue }

            let propSpec = builder.buildPropertySpecifier(code: prop.code, container: container)
            let cmd = "get \(prop.name) of \(path) of \(appRef)"

            let reply: NSAppleEventDescriptor
            do {
                reply = try sendGet(propSpec, command: cmd)
            } catch {
                continue
            }

            if reply.descriptorType == AEConstants.typeObjectSpecifier {
                testPropertyOfProperty(
                    propName: prop.name, propType: prop.type, propSpec: propSpec,
                    path: path, findings: &findings
                )
                testElementOfProperty(
                    propName: prop.name, propType: prop.type, propSpec: propSpec,
                    path: path, findings: &findings
                )
            } else if reply.descriptorType == AEConstants.typeAEList {
                testListAccess(
                    propName: prop.name, propSpec: propSpec, listReply: reply,
                    path: path, findings: &findings
                )
            }
        }
    }

    // MARK: - Property-of-property

    private func testPropertyOfProperty(
        propName: String,
        propType: String?,
        propSpec: NSAppleEventDescriptor,
        path: String,
        findings: inout [LintFinding]
    ) {
        let nameOfPropSpec = builder.buildPropertySpecifier(code: "pnam", container: propSpec)
        let cmd = "get name of \(propName) of \(path) of \(appRef)"

        do {
            let result = try sendGet(nameOfPropSpec, command: cmd)
            let nameStr = result.stringValue ?? "(non-string)"
            findings.append(LintFinding(
                .info, category: "dynamic-chain",
                message: "property-of-property: name of \(propName) of \(path) = \(nameStr)"
            ))
        } catch {
            findings.append(LintFinding(
                .warning, category: "dynamic-chain",
                message: "property-of-property unsupported: name of \(propName) of \(path): \(error.localizedDescription)",
                context: cmd
            ))
        }
    }

    // MARK: - Element-of-property

    private func testElementOfProperty(
        propName: String,
        propType: String?,
        propSpec: NSAppleEventDescriptor,
        path: String,
        findings: inout [LintFinding]
    ) {
        guard let typeName = propType,
              let targetClass = dictionary.findClass(typeName) else {
            return
        }

        let targetElems = dictionary.allElements(for: targetClass)
        guard !targetElems.isEmpty else { return }

        for elem in targetElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let cmd = "count every \(elemClass.name) of \(propName) of \(path) of \(appRef)"
            do {
                let count = try sendCount(
                    container: propSpec,
                    elementCode: elementCode,
                    command: cmd
                )
                findings.append(LintFinding(
                    .info, category: "dynamic-chain",
                    message: "element-of-property: count of \(elemClass.pluralName ?? elemClass.name) of \(propName) of \(path) = \(count)"
                ))
            } catch {
                findings.append(LintFinding(
                    .warning, category: "dynamic-chain",
                    message: "element-of-property unsupported: count \(elemClass.name) of \(propName) of \(path): \(error.localizedDescription)",
                    context: cmd
                ))
            }
            break
        }
    }

    // MARK: - List access forms

    private func testListAccess(
        propName: String,
        propSpec: NSAppleEventDescriptor,
        listReply: NSAppleEventDescriptor,
        path: String,
        findings: inout [LintFinding]
    ) {
        let listCount = listReply.numberOfItems
        guard listCount > 0 else { return }

        let itemCode = "cobj"
        let listPath = "\(propName) of \(path) of \(appRef)"

        var supported: [String] = []
        var unsupported: [String] = []

        // item 1
        let item1Spec = builder.buildElementWithPredicate(
            code: itemCode, predicate: .byIndex(1), container: propSpec
        )
        if testGetItemQuietly(spec: item1Spec, command: "get item 1 of \(listPath)") {
            supported.append("item 1")
        } else {
            unsupported.append("item 1")
        }

        // item -1 (negative index)
        let itemNeg1Spec = buildNegativeIndexElement(code: itemCode, index: -1, container: propSpec)
        if testGetItemQuietly(spec: itemNeg1Spec, command: "get item -1 of \(listPath)") {
            supported.append("item -1")
        } else {
            unsupported.append("item -1")
        }

        // every item
        let everySpec = builder.buildEveryElement(code: itemCode, container: propSpec)
        if testGetItemQuietly(spec: everySpec, command: "get every item of \(listPath)") {
            supported.append("every item")
        } else {
            unsupported.append("every item")
        }

        // first item
        let firstSpec = buildOrdinalElement(code: itemCode, ordinal: AEConstants.kAEFirst, container: propSpec)
        if testGetItemQuietly(spec: firstSpec, command: "get first item of \(listPath)") {
            supported.append("first item")
        } else {
            unsupported.append("first item")
        }

        // last item
        let lastSpec = buildOrdinalElement(code: itemCode, ordinal: AEConstants.kAELast, container: propSpec)
        if testGetItemQuietly(spec: lastSpec, command: "get last item of \(listPath)") {
            supported.append("last item")
        } else {
            unsupported.append("last item")
        }

        // middle item
        let middleSpec = builder.buildElementWithPredicate(
            code: itemCode, predicate: .byOrdinal(.middle), container: propSpec
        )
        if testGetItemQuietly(spec: middleSpec, command: "get middle item of \(listPath)") {
            supported.append("middle item")
        } else {
            unsupported.append("middle item")
        }

        // some item
        let someSpec = builder.buildElementWithPredicate(
            code: itemCode, predicate: .byOrdinal(.some), container: propSpec
        )
        if testGetItemQuietly(spec: someSpec, command: "get some item of \(listPath)") {
            supported.append("some item")
        } else {
            unsupported.append("some item")
        }

        findings.append(LintFinding(
            .info, category: "dynamic-list",
            message: "\(propName) of \(path) (list of \(listCount)): supported: \(supported.joined(separator: ", "))"
        ))
        if !unsupported.isEmpty {
            findings.append(LintFinding(
                .warning, category: "dynamic-list",
                message: "\(propName) of \(path): unsupported item access: \(unsupported.joined(separator: ", "))"
            ))
        }

        // Test property access on list items that are object specifiers
        if let firstItem = listReply.atIndex(1),
           firstItem.descriptorType == AEConstants.typeObjectSpecifier {
            testPropertyOfListItem(
                itemSpec: item1Spec, propName: propName, path: path, findings: &findings
            )
        }
    }

    private func testPropertyOfListItem(
        itemSpec: NSAppleEventDescriptor,
        propName: String,
        path: String,
        findings: inout [LintFinding]
    ) {
        let nameOfItemSpec = builder.buildPropertySpecifier(code: "pnam", container: itemSpec)
        let cmd = "get name of item 1 of \(propName) of \(path) of \(appRef)"

        do {
            let result = try sendGet(nameOfItemSpec, command: cmd)
            let nameStr = result.stringValue ?? "(non-string)"
            findings.append(LintFinding(
                .info, category: "dynamic-list",
                message: "name of item 1 of \(propName) of \(path) = \(nameStr)"
            ))
        } catch {
            findings.append(LintFinding(
                .warning, category: "dynamic-list",
                message: "Cannot get property of list item: name of item 1 of \(propName) of \(path): \(error.localizedDescription)",
                context: cmd
            ))
        }
    }

    // MARK: - Helpers

    private func testGetItemQuietly(spec: NSAppleEventDescriptor, command: String) -> Bool {
        (try? sendGet(spec, command: command)) != nil
    }

    private func buildOrdinalElement(
        code: String,
        ordinal: FourCharCode,
        container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()
        let fourCC = FourCharCode(code)

        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: fourCC),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formAbsolutePosition),
            forKeyword: AEConstants.keyAEKeyForm
        )

        var ordCode = ordinal
        let data = Data(bytes: &ordCode, count: 4)
        let ordDesc = NSAppleEventDescriptor(descriptorType: AEConstants.typeAbsoluteOrdinal, data: data)!
        specifier.setDescriptor(ordDesc, forKeyword: AEConstants.keyAEKeyData)

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    private func buildNegativeIndexElement(
        code: String,
        index: Int,
        container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()
        let fourCC = FourCharCode(code)

        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: fourCC),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formAbsolutePosition),
            forKeyword: AEConstants.keyAEKeyForm
        )
        specifier.setDescriptor(
            NSAppleEventDescriptor(int32: Int32(index)),
            forKeyword: AEConstants.keyAEKeyData
        )

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - Every element retrieval

    private func testEveryElementRetrieval() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)
        var successCount = 0
        var failCount = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)

            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            let everySpec = builder.buildEveryElement(
                code: elemClass.code,
                container: NSAppleEventDescriptor.null()
            )
            let cmd = "get every \(elemClass.name) of \(appRef)"

            do {
                let result = try sendGet(everySpec, command: cmd)
                let resultCount: Int
                if result.descriptorType == AEConstants.typeAEList {
                    resultCount = result.numberOfItems
                } else {
                    resultCount = 1
                }
                successCount += 1
                if resultCount != count {
                    findings.append(LintFinding(
                        .warning, category: "dynamic-every",
                        message: "every \(elemClass.name): count returned \(count) but get every returned \(resultCount) items",
                        context: cmd
                    ))
                }
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-every",
                    message: "Cannot get every \(elemClass.name): \(error.localizedDescription)",
                    context: cmd
                ))
            }
        }

        findings.append(LintFinding(
            .info, category: "dynamic-every",
            message: "Every-element retrieval: \(successCount) succeeded, \(failCount) failed"
        ))

        return findings
    }

    // MARK: - Whose clause testing

    private func testWhoseClause() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)

            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            let allProps = dictionary.allProperties(for: elemClass)
            guard allProps.contains(where: { $0.code == "pnam" }) else { continue }

            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )
            let nameSpec = builder.buildPropertySpecifier(code: "pnam", container: firstSpec)

            guard let nameReply = try? sendGet(nameSpec, command: "get name of \(elemClass.name) 1 of \(appRef)"),
                  let name = nameReply.stringValue, !name.isEmpty else {
                continue
            }

            let testExpr = TestExpr(path: ["name"], op: .equal, value: .string(name))
            let whoseSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .test(testExpr),
                container: NSAppleEventDescriptor.null()
            )

            let elemPlural = elemClass.pluralName ?? elemClass.name
            let whoseNameSpec = builder.buildPropertySpecifier(code: "pnam", container: whoseSpec)
            let cmd = "get name of (every \(elemClass.name) whose name = \"\(name)\") of \(appRef)"
            do {
                let result = try sendGet(whoseNameSpec, command: cmd)
                let resultNames: [String]
                if result.descriptorType == AEConstants.typeAEList {
                    resultNames = (1...result.numberOfItems).compactMap {
                        result.atIndex($0)?.stringValue
                    }
                } else {
                    resultNames = [result.stringValue].compactMap { $0 }
                }

                let matched = resultNames.contains(name)
                if matched {
                    findings.append(LintFinding(
                        .info, category: "dynamic-whose",
                        message: "\(elemPlural) whose name = \"\(name)\": found \(resultNames.count) match(es)"
                    ))
                } else {
                    findings.append(LintFinding(
                        .warning, category: "dynamic-whose",
                        message: "\(elemClass.name) whose clause returned unexpected results for name = \"\(name)\"",
                        context: cmd
                    ))
                }
            } catch {
                findings.append(LintFinding(
                    .warning, category: "dynamic-whose",
                    message: "\(elemClass.name) whose clause not supported: \(error.localizedDescription)",
                    context: cmd
                ))
            }
        }

        return findings
    }

    // MARK: - Exists event testing

    private func testExistsEvent() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)
        var successCount = 0
        var failCount = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            // exists <first element> — should return true
            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )
            let existsCmd = "exists \(elemClass.name) 1 of \(appRef)"

            do {
                let exists = try sendExists(firstSpec, command: existsCmd)
                if exists {
                    successCount += 1
                } else {
                    failCount += 1
                    findings.append(LintFinding(
                        .warning, category: "dynamic-exists",
                        message: "exists \(elemClass.name) 1 returned false (expected true, count = \(count))",
                        context: existsCmd
                    ))
                }
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-exists",
                    message: "exists \(elemClass.name) 1 failed: \(error.localizedDescription)",
                    context: existsCmd
                ))
            }

            // exists <element by impossible name> — should return false
            let bogusName = "__aelint_nonexistent_\(UUID().uuidString)__"
            let bogusSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byName(bogusName),
                container: NSAppleEventDescriptor.null()
            )
            let bogusCmd = "exists \(elemClass.name) \"\(bogusName)\" of \(appRef)"

            do {
                let exists = try sendExists(bogusSpec, command: bogusCmd)
                if exists {
                    findings.append(LintFinding(
                        .warning, category: "dynamic-exists",
                        message: "exists \(elemClass.name) with bogus name returned true (expected false)",
                        context: bogusCmd
                    ))
                }
            } catch {
                // Some apps throw instead of returning false — acceptable
            }
        }

        findings.append(LintFinding(
            .info, category: "dynamic-exists",
            message: "Exists event: \(successCount) succeeded, \(failCount) failed"
        ))

        return findings
    }

    // MARK: - Type validation

    private func testTypeValidation() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allProps = dictionary.allProperties(for: appClass)
        var matchCount = 0
        var mismatchCount = 0
        var uncheckCount = 0

        for prop in allProps {
            if prop.hidden { continue }
            if prop.access == .writeOnly { continue }
            guard let declaredType = prop.type else {
                uncheckCount += 1
                continue
            }

            let propSpec = builder.buildPropertySpecifier(
                code: prop.code,
                container: NSAppleEventDescriptor.null()
            )
            let cmd = "get \(prop.name) of \(appRef)"

            let reply: NSAppleEventDescriptor
            do {
                reply = try sendGet(propSpec, command: cmd)
            } catch {
                continue
            }

            let actualType = reply.descriptorType
            if isTypeCompatible(declaredType: declaredType, actualDescType: actualType) {
                matchCount += 1
            } else {
                mismatchCount += 1
                let actualStr = descTypeString(actualType)
                findings.append(LintFinding(
                    .info, category: "dynamic-type",
                    message: "Property '\(prop.name)' declared as '\(declaredType)' but returned descriptor type '\(actualStr)'",
                    context: cmd
                ))
            }
        }

        if matchCount > 0 || mismatchCount > 0 {
            findings.append(LintFinding(
                .info, category: "dynamic-type",
                message: "Application property types: \(matchCount) match, \(mismatchCount) mismatch, \(uncheckCount) untyped"
            ))
        }

        return findings
    }

    private func isTypeCompatible(declaredType: String, actualDescType: DescType) -> Bool {
        let lower = declaredType.lowercased()
        let actual = FourCharCode(actualDescType)
        let actualStr = actual.stringValue

        switch lower {
        case "text", "string":
            return ["utxt", "TEXT", "ctxt", "utf8", "itxt"].contains(actualStr)
        case "integer":
            return ["long", "shor", "comp", "magn"].contains(actualStr)
        case "real":
            return ["doub", "sing", "exte", "ldbl"].contains(actualStr)
        case "number":
            return ["long", "shor", "comp", "magn", "doub", "sing"].contains(actualStr)
        case "boolean":
            return ["bool", "true", "fals"].contains(actualStr)
        case "date":
            return actualStr == "ldt "
        case "file", "alias":
            return ["alis", "furl", "bmrk", "fss "].contains(actualStr)
        case "type", "type class":
            return actualStr == "type"
        case "record":
            return actualStr == "reco"
        case "list":
            return actualStr == "list"
        case "point":
            return actualStr == "QDpt"
        case "rectangle":
            return actualStr == "qdrt"
        case "rgb color", "color":
            return ["cRGB", "tr16"].contains(actualStr)
        case "specifier", "reference", "location specifier":
            return actualStr == "obj "
        case "any", "missing value":
            return true
        default:
            if dictionary.findClass(declaredType) != nil {
                return actualStr == "obj "
            }
            if dictionary.findEnumeration(declaredType) != nil {
                return actualStr == "enum"
            }
            return true
        }
    }

    private func descTypeString(_ dt: DescType) -> String {
        FourCharCode(dt).stringValue
    }

    // MARK: - Range access testing

    private func testRangeAccess() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)
        var successCount = 0
        var failCount = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)

            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count >= 2 else { continue }

            // Test range: elements 1 thru min(count, 3)
            let rangeEnd = min(count, 3)
            let rangeSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byRange(1, rangeEnd),
                container: NSAppleEventDescriptor.null()
            )
            let plural = elemClass.pluralName ?? "\(elemClass.name)s"
            let cmd = "get \(plural) 1 thru \(rangeEnd) of \(appRef)"

            do {
                let result = try sendGet(rangeSpec, command: cmd)
                let resultCount: Int
                if result.descriptorType == AEConstants.typeAEList {
                    resultCount = result.numberOfItems
                } else {
                    resultCount = 1
                }
                successCount += 1
                if resultCount != rangeEnd {
                    findings.append(LintFinding(
                        .warning, category: "dynamic-range",
                        message: "\(plural) 1 thru \(rangeEnd): expected \(rangeEnd) items but got \(resultCount)",
                        context: cmd
                    ))
                }
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-range",
                    message: "Range access not supported for \(elemClass.name): \(error.localizedDescription)",
                    context: cmd
                ))
            }
        }

        if successCount > 0 || failCount > 0 {
            findings.append(LintFinding(
                .info, category: "dynamic-range",
                message: "Range access: \(successCount) succeeded, \(failCount) failed"
            ))
        }

        return findings
    }

    // MARK: - Inherited properties testing

    private func testInheritedProperties() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }
            guard let parentName = elemClass.inherits else { continue }
            guard let parentClass = dictionary.findClass(parentName) else { continue }

            // Only test classes that actually inherit from something other than "item"
            // and where the parent has properties
            let parentProps = parentClass.properties.filter { !$0.hidden && $0.access != .writeOnly }
            guard !parentProps.isEmpty else { continue }

            let elementCode = FourCharCode(elemClass.code)
            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )

            var inheritedSuccess = 0
            var inheritedFail = 0

            // Test parent-defined properties on the child instance
            for prop in parentProps {
                // Skip properties that the child also declares directly (not purely inherited)
                if elemClass.properties.contains(where: { $0.code == prop.code }) { continue }

                let propSpec = builder.buildPropertySpecifier(code: prop.code, container: firstSpec)
                let cmd = "get \(prop.name) of \(elemClass.name) 1 of \(appRef)"

                do {
                    _ = try sendGet(propSpec, command: cmd)
                    inheritedSuccess += 1
                } catch {
                    inheritedFail += 1
                    findings.append(LintFinding(
                        .warning, category: "dynamic-inherit",
                        message: "Inherited property '\(prop.name)' (from \(parentName)) failed on \(elemClass.name): \(error.localizedDescription)",
                        context: cmd
                    ))
                }
            }

            if inheritedSuccess > 0 || inheritedFail > 0 {
                findings.append(LintFinding(
                    .info, category: "dynamic-inherit",
                    message: "\(elemClass.name) inherited properties (from \(parentName)): \(inheritedSuccess) readable, \(inheritedFail) failed"
                ))
            }
        }

        return findings
    }

    // MARK: - Error handling validation

    private func testErrorHandling() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)
        var properErrorCount = 0
        var badErrorCount = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            // Test 1: Access element at impossibly high index
            let bogusIndex = 99999
            let bogusSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(bogusIndex),
                container: NSAppleEventDescriptor.null()
            )
            let nameOfBogus = builder.buildPropertySpecifier(code: "pnam", container: bogusSpec)
            let cmd = "get name of \(elemClass.name) \(bogusIndex) of \(appRef)"

            do {
                _ = try sendGet(nameOfBogus, command: cmd)
                // If it succeeds, the app has 99999+ elements — unlikely but not an error
            } catch let error as AEQueryError {
                if case .appleEventFailed(let code, _, _) = error {
                    // Expected errors: -1719 (invalid index), -1728 (no such object)
                    if code == -1719 || code == -1728 {
                        properErrorCount += 1
                    } else {
                        badErrorCount += 1
                        findings.append(LintFinding(
                            .info, category: "dynamic-error",
                            message: "\(elemClass.name) \(bogusIndex): unexpected error code \(code) (expected -1719 or -1728)",
                            context: cmd
                        ))
                    }
                }
            } catch {
                badErrorCount += 1
                findings.append(LintFinding(
                    .info, category: "dynamic-error",
                    message: "\(elemClass.name) \(bogusIndex): non-AE error: \(error.localizedDescription)",
                    context: cmd
                ))
            }

            // Test 2: Access element by impossible name
            let bogusName = "__aelint_\(elemClass.code)_nonexistent__"
            let bogusNameSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byName(bogusName),
                container: NSAppleEventDescriptor.null()
            )
            let nameOfBogusName = builder.buildPropertySpecifier(code: "pnam", container: bogusNameSpec)
            let cmd2 = "get name of \(elemClass.name) \"\(bogusName)\" of \(appRef)"

            do {
                _ = try sendGet(nameOfBogusName, command: cmd2)
                // Unexpected success — app returned something for a bogus name
                findings.append(LintFinding(
                    .warning, category: "dynamic-error",
                    message: "\(elemClass.name) with bogus name returned data instead of error",
                    context: cmd2
                ))
            } catch let error as AEQueryError {
                if case .appleEventFailed(let code, _, _) = error {
                    if code == -1728 || code == -1719 {
                        properErrorCount += 1
                    } else {
                        badErrorCount += 1
                        findings.append(LintFinding(
                            .info, category: "dynamic-error",
                            message: "\(elemClass.name) by bogus name: error code \(code) (expected -1728)",
                            context: cmd2
                        ))
                    }
                }
            } catch {
                badErrorCount += 1
            }
        }

        if properErrorCount > 0 || badErrorCount > 0 {
            findings.append(LintFinding(
                .info, category: "dynamic-error",
                message: "Error handling: \(properErrorCount) proper errors, \(badErrorCount) unexpected"
            ))
        }

        return findings
    }

    // MARK: - Set property testing

    private func testSetProperty() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        var successCount = 0
        var failCount = 0
        var readOnlyCount = 0

        // Test application-level read-write properties
        testSetPropertiesOn(
            container: NSAppleEventDescriptor.null(),
            containerPath: appRef,
            classDef: appClass,
            successCount: &successCount,
            failCount: &failCount,
            readOnlyCount: &readOnlyCount,
            findings: &findings
        )

        // Test element-level read-write properties (first element of each type)
        let allElems = dictionary.allElements(for: appClass)
        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )
            let elemPath = "\(elemClass.name) 1 of \(appRef)"

            testSetPropertiesOn(
                container: firstSpec,
                containerPath: elemPath,
                classDef: elemClass,
                successCount: &successCount,
                failCount: &failCount,
                readOnlyCount: &readOnlyCount,
                findings: &findings
            )
        }

        if successCount > 0 || failCount > 0 || readOnlyCount > 0 {
            findings.append(LintFinding(
                .info, category: "dynamic-set",
                message: "Set property: \(successCount) writable, \(failCount) failed, \(readOnlyCount) effectively read-only"
            ))
        }

        return findings
    }

    private func testSetPropertiesOn(
        container: NSAppleEventDescriptor,
        containerPath: String,
        classDef: ClassDef,
        successCount: inout Int,
        failCount: inout Int,
        readOnlyCount: inout Int,
        findings: inout [LintFinding]
    ) {
        let allProps = dictionary.allProperties(for: classDef)

        // Known read-only property codes that should never be set
        let knownReadOnlyCodes: Set<String> = [
            "pnam", "pcls", "ID  ", "pALL", "pisf", "vers", "pbnd",
        ]

        for prop in allProps {
            if prop.hidden { continue }
            // Test properties that are explicitly read-write or have unspecified access (default = read-write)
            if prop.access == .readOnly || prop.access == .writeOnly { continue }
            // Skip known read-only properties that apps often don't mark as such
            if knownReadOnlyCodes.contains(prop.code) { continue }

            let propSpec = builder.buildPropertySpecifier(code: prop.code, container: container)
            let getCmd = "get \(prop.name) of \(containerPath)"

            let currentValue: NSAppleEventDescriptor
            do {
                currentValue = try sendGet(propSpec, command: getCmd)
            } catch {
                continue
            }

            // Skip object specifiers and lists — setting those back is unreliable
            if currentValue.descriptorType == AEConstants.typeObjectSpecifier { continue }
            if currentValue.descriptorType == AEConstants.typeAEList { continue }

            let setCmd = "set \(prop.name) of \(containerPath) to \(describeResult(currentValue))"
            do {
                try sendSet(propSpec, value: currentValue, command: setCmd)
                successCount += 1
            } catch let error as AEQueryError {
                if case .appleEventFailed(let code, _, _) = error {
                    // -10000: generic AE error (often means property not settable in current state)
                    // -10002: handler not found for set
                    // -10003: read-only object
                    // -10004: privilege violation
                    // -10006: permission denied
                    if [-10000, -10002, -10003, -10004, -10006].contains(code) {
                        readOnlyCount += 1
                        findings.append(LintFinding(
                            .info, category: "dynamic-set",
                            message: "'\(prop.name)' of \(classDef.name) declared read-write but set is denied (error \(code))",
                            context: setCmd
                        ))
                    } else {
                        failCount += 1
                        findings.append(LintFinding(
                            .warning, category: "dynamic-set",
                            message: "Cannot set '\(prop.name)' of \(classDef.name): \(error.localizedDescription)",
                            context: setCmd
                        ))
                    }
                }
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-set",
                    message: "Cannot set '\(prop.name)' of \(classDef.name): \(error.localizedDescription)",
                    context: setCmd
                ))
            }
        }
    }

    // MARK: - Properties record (pALL)

    private func testPropertiesRecord() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        // Test get properties of application
        let appPropSpec = builder.buildPropertySpecifier(
            code: "pALL",
            container: NSAppleEventDescriptor.null()
        )
        let appCmd = "get properties of \(appRef)"
        var appRecordKeys = 0

        do {
            let result = try sendGet(appPropSpec, command: appCmd)
            if result.descriptorType == typeType(for: "reco") {
                appRecordKeys = result.numberOfItems
                findings.append(LintFinding(
                    .info, category: "dynamic-pall",
                    message: "properties of application: record with \(appRecordKeys) keys"
                ))
            } else {
                findings.append(LintFinding(
                    .info, category: "dynamic-pall",
                    message: "properties of application: returned \(descTypeString(result.descriptorType)) (expected record)"
                ))
            }
        } catch {
            findings.append(LintFinding(
                .warning, category: "dynamic-pall",
                message: "Cannot get properties of application: \(error.localizedDescription)",
                context: appCmd
            ))
        }

        // Test get properties of first element of each type
        let allElems = dictionary.allElements(for: appClass)
        var elemSuccess = 0
        var elemFail = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )
            let propSpec = builder.buildPropertySpecifier(code: "pALL", container: firstSpec)
            let cmd = "get properties of \(elemClass.name) 1 of \(appRef)"

            do {
                let result = try sendGet(propSpec, command: cmd)
                elemSuccess += 1
                if result.descriptorType == typeType(for: "reco") {
                    let keys = result.numberOfItems
                    let expected = dictionary.allProperties(for: elemClass).filter { !$0.hidden }.count
                    if keys < expected / 2 {
                        findings.append(LintFinding(
                            .info, category: "dynamic-pall",
                            message: "\(elemClass.name) properties record has \(keys) keys but SDEF declares \(expected) properties"
                        ))
                    }
                }
            } catch {
                elemFail += 1
            }
        }

        if elemSuccess > 0 || elemFail > 0 {
            findings.append(LintFinding(
                .info, category: "dynamic-pall",
                message: "Properties record: application + \(elemSuccess) element types succeeded, \(elemFail) failed"
            ))
        }

        return findings
    }

    // MARK: - Whose clause operators

    private func testWhoseOperators() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let count: Int
            do {
                count = try sendCount(
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    command: "count every \(elemClass.name) of \(appRef)"
                )
            } catch {
                continue
            }
            guard count > 0 else { continue }

            let allProps = dictionary.allProperties(for: elemClass)
            guard allProps.contains(where: { $0.code == "pnam" }) else { continue }

            // Get the name of the first element to use as test data
            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )
            let nameSpec = builder.buildPropertySpecifier(code: "pnam", container: firstSpec)
            guard let nameReply = try? sendGet(nameSpec, command: "get name of \(elemClass.name) 1 of \(appRef)"),
                  let name = nameReply.stringValue, name.count >= 2 else {
                continue
            }

            let elemPlural = elemClass.pluralName ?? elemClass.name
            var supported: [String] = []
            var unsupported: [String] = []

            // Test "contains" — use a substring of the name
            let substring = String(name.prefix(max(1, name.count / 2)))
            let containsTest = TestExpr(path: ["name"], op: .contains, value: .string(substring))
            let containsSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .test(containsTest),
                container: NSAppleEventDescriptor.null()
            )
            let containsNameSpec = builder.buildPropertySpecifier(code: "pnam", container: containsSpec)
            let containsCmd = "get name of (every \(elemClass.name) whose name contains \"\(substring)\") of \(appRef)"

            do {
                let result = try sendGet(containsNameSpec, command: containsCmd)
                let names: [String]
                if result.descriptorType == AEConstants.typeAEList {
                    names = (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
                } else {
                    names = [result.stringValue].compactMap { $0 }
                }
                if names.contains(where: { $0.localizedCaseInsensitiveContains(substring) }) {
                    supported.append("contains")
                } else {
                    unsupported.append("contains")
                }
            } catch {
                unsupported.append("contains")
            }

            // Test "begins with" — use the first few characters
            let prefix = String(name.prefix(max(1, name.count / 3)))
            let beginsTest = TestExpr(path: ["name"], op: .beginsWith, value: .string(prefix))
            let beginsSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .test(beginsTest),
                container: NSAppleEventDescriptor.null()
            )
            let beginsNameSpec = builder.buildPropertySpecifier(code: "pnam", container: beginsSpec)
            let beginsCmd = "get name of (every \(elemClass.name) whose name begins with \"\(prefix)\") of \(appRef)"

            do {
                let result = try sendGet(beginsNameSpec, command: beginsCmd)
                let names: [String]
                if result.descriptorType == AEConstants.typeAEList {
                    names = (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
                } else {
                    names = [result.stringValue].compactMap { $0 }
                }
                if names.contains(where: { $0.localizedCaseInsensitiveCompare(prefix) == .orderedSame ||
                    $0.lowercased().hasPrefix(prefix.lowercased()) }) {
                    supported.append("begins with")
                } else {
                    unsupported.append("begins with")
                }
            } catch {
                unsupported.append("begins with")
            }

            // Test "ends with" — use the last few characters
            let suffix = String(name.suffix(max(1, name.count / 3)))
            let endsTest = TestExpr(path: ["name"], op: .endsWith, value: .string(suffix))
            let endsSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .test(endsTest),
                container: NSAppleEventDescriptor.null()
            )
            let endsNameSpec = builder.buildPropertySpecifier(code: "pnam", container: endsSpec)
            let endsCmd = "get name of (every \(elemClass.name) whose name ends with \"\(suffix)\") of \(appRef)"

            do {
                let result = try sendGet(endsNameSpec, command: endsCmd)
                let names: [String]
                if result.descriptorType == AEConstants.typeAEList {
                    names = (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
                } else {
                    names = [result.stringValue].compactMap { $0 }
                }
                if names.contains(where: { $0.lowercased().hasSuffix(suffix.lowercased()) }) {
                    supported.append("ends with")
                } else {
                    unsupported.append("ends with")
                }
            } catch {
                unsupported.append("ends with")
            }

            if !supported.isEmpty || !unsupported.isEmpty {
                findings.append(LintFinding(
                    .info, category: "dynamic-whose-ops",
                    message: "\(elemPlural) whose operators: \(supported.isEmpty ? "none" : supported.joined(separator: ", "))"
                ))
                if !unsupported.isEmpty {
                    findings.append(LintFinding(
                        .warning, category: "dynamic-whose-ops",
                        message: "\(elemPlural) unsupported whose operators: \(unsupported.joined(separator: ", "))"
                    ))
                }
            }
        }

        return findings
    }
}
