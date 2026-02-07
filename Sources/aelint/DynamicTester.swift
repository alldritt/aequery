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

    // MARK: - Sub-element exploration

    /// Recursively explore sub-elements, testing property chaining and list access forms.
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
                count = try sender.sendCountEvent(
                    to: appName,
                    container: NSAppleEventDescriptor.null(),
                    elementCode: elementCode,
                    timeoutSeconds: 10
                )
            } catch {
                continue  // already reported in earlier tests
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

    /// Recursively explore an object's properties and sub-elements.
    /// - Parameters:
    ///   - specifier: The object specifier for the current object
    ///   - className: The SDEF class name of this object
    ///   - path: Human-readable path description for reporting
    ///   - depth: Current recursion depth
    ///   - visited: Set of class names already explored (cycle detection)
    ///   - findings: Accumulated lint findings
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

        // Test properties that return object specifiers or lists
        testPropertyChaining(classDef: classDef, container: specifier, path: path, findings: &findings)

        // Explore sub-elements
        let allElems = dictionary.allElements(for: classDef)
        var subElemSuccess = 0
        var subElemFail = 0

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            let count: Int
            do {
                count = try sender.sendCountEvent(
                    to: appName,
                    container: specifier,
                    elementCode: elementCode,
                    timeoutSeconds: 10
                )
                subElemSuccess += 1
            } catch {
                subElemFail += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-explore",
                    message: "Cannot count \(elemClass.name) elements of \(path): \(error.localizedDescription)"
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

    /// For each readable property, check if the result is an object specifier or a list,
    /// and test chained access patterns.
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

            let reply: NSAppleEventDescriptor
            do {
                reply = try sender.sendGetEvent(to: appName, specifier: propSpec, timeoutSeconds: 10)
            } catch {
                continue  // property read failures already reported in earlier tests
            }

            if reply.descriptorType == AEConstants.typeObjectSpecifier {
                // Property returns an object specifier — test chained access
                testPropertyOfProperty(
                    propName: prop.name, propType: prop.type, propSpec: propSpec,
                    path: path, findings: &findings
                )
                testElementOfProperty(
                    propName: prop.name, propType: prop.type, propSpec: propSpec,
                    path: path, findings: &findings
                )
            } else if reply.descriptorType == AEConstants.typeAEList {
                // Property returns a list — test item access forms
                testListAccess(
                    propName: prop.name, propSpec: propSpec, listReply: reply,
                    path: path, findings: &findings
                )
            }
        }
    }

    // MARK: - Property-of-property

    /// Test whether `name of <property> of <container>` works (property-of-property resolution).
    private func testPropertyOfProperty(
        propName: String,
        propType: String?,
        propSpec: NSAppleEventDescriptor,
        path: String,
        findings: inout [LintFinding]
    ) {
        // Try getting name of the object returned by this property
        let nameOfPropSpec = builder.buildPropertySpecifier(code: "pnam", container: propSpec)

        do {
            let result = try sender.sendGetEvent(to: appName, specifier: nameOfPropSpec, timeoutSeconds: 10)
            let nameStr = result.stringValue ?? "(non-string)"
            findings.append(LintFinding(
                .info, category: "dynamic-chain",
                message: "property-of-property: name of \(propName) of \(path) = \(nameStr)"
            ))
        } catch {
            findings.append(LintFinding(
                .warning, category: "dynamic-chain",
                message: "property-of-property unsupported: name of \(propName) of \(path): \(error.localizedDescription)"
            ))
        }
    }

    // MARK: - Element-of-property

    /// Test whether we can count elements of an object returned by a property.
    private func testElementOfProperty(
        propName: String,
        propType: String?,
        propSpec: NSAppleEventDescriptor,
        path: String,
        findings: inout [LintFinding]
    ) {
        // Look up the property's declared type to find what elements it might have
        guard let typeName = propType,
              let targetClass = dictionary.findClass(typeName) else {
            return  // Can't determine elements without knowing the class
        }

        let targetElems = dictionary.allElements(for: targetClass)
        guard !targetElems.isEmpty else { return }

        // Try counting the first element type
        for elem in targetElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)
            do {
                let count = try sender.sendCountEvent(
                    to: appName,
                    container: propSpec,
                    elementCode: elementCode,
                    timeoutSeconds: 10
                )
                findings.append(LintFinding(
                    .info, category: "dynamic-chain",
                    message: "element-of-property: count of \(elemClass.pluralName ?? elemClass.name) of \(propName) of \(path) = \(count)"
                ))
            } catch {
                findings.append(LintFinding(
                    .warning, category: "dynamic-chain",
                    message: "element-of-property unsupported: count \(elemClass.name) of \(propName) of \(path): \(error.localizedDescription)"
                ))
            }
            break  // Only test the first element type to avoid excessive queries
        }
    }

    // MARK: - List access forms

    /// Test various item access forms on a property that returns a list.
    private func testListAccess(
        propName: String,
        propSpec: NSAppleEventDescriptor,
        listReply: NSAppleEventDescriptor,
        path: String,
        findings: inout [LintFinding]
    ) {
        let listCount = listReply.numberOfItems
        guard listCount > 0 else { return }

        let itemCode = "cobj"  // generic item class

        // Track which forms work
        var supported: [String] = []
        var unsupported: [String] = []

        // Test: item 1 of <property> of <path>
        let item1Spec = builder.buildElementWithPredicate(
            code: itemCode, predicate: .byIndex(1), container: propSpec
        )
        if testGetItemQuietly(spec: item1Spec) {
            supported.append("item 1")
        } else {
            unsupported.append("item 1")
        }

        // Test: item -1 of <property> of <path> (negative index, NOT kAELast ordinal)
        let itemNeg1Spec = buildNegativeIndexElement(code: itemCode, index: -1, container: propSpec)
        if testGetItemQuietly(spec: itemNeg1Spec) {
            supported.append("item -1")
        } else {
            unsupported.append("item -1")
        }

        // Test: every item of <property> of <path>
        let everySpec = builder.buildEveryElement(code: itemCode, container: propSpec)
        if testGetItemQuietly(spec: everySpec) {
            supported.append("every item")
        } else {
            unsupported.append("every item")
        }

        // Test: first item of <property> of <path>
        let firstSpec = buildOrdinalElement(code: itemCode, ordinal: AEConstants.kAEFirst, container: propSpec)
        if testGetItemQuietly(spec: firstSpec) {
            supported.append("first item")
        } else {
            unsupported.append("first item")
        }

        // Test: last item of <property> of <path>
        let lastSpec = buildOrdinalElement(code: itemCode, ordinal: AEConstants.kAELast, container: propSpec)
        if testGetItemQuietly(spec: lastSpec) {
            supported.append("last item")
        } else {
            unsupported.append("last item")
        }

        // Test: middle item of <property> of <path>
        let middleSpec = builder.buildElementWithPredicate(
            code: itemCode, predicate: .byOrdinal(.middle), container: propSpec
        )
        if testGetItemQuietly(spec: middleSpec) {
            supported.append("middle item")
        } else {
            unsupported.append("middle item")
        }

        // Test: some item of <property> of <path>
        let someSpec = builder.buildElementWithPredicate(
            code: itemCode, predicate: .byOrdinal(.some), container: propSpec
        )
        if testGetItemQuietly(spec: someSpec) {
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

        // Test if list items contain object specifiers → test property access on items
        if let firstItem = listReply.atIndex(1),
           firstItem.descriptorType == AEConstants.typeObjectSpecifier {
            testPropertyOfListItem(
                itemSpec: item1Spec, propName: propName, path: path, findings: &findings
            )
        }
    }

    /// Test property access on an item of a list that contains object specifiers.
    /// e.g. `name of item 1 of <property> of <path>`
    private func testPropertyOfListItem(
        itemSpec: NSAppleEventDescriptor,
        propName: String,
        path: String,
        findings: inout [LintFinding]
    ) {
        let nameOfItemSpec = builder.buildPropertySpecifier(code: "pnam", container: itemSpec)

        do {
            let result = try sender.sendGetEvent(to: appName, specifier: nameOfItemSpec, timeoutSeconds: 10)
            let nameStr = result.stringValue ?? "(non-string)"
            findings.append(LintFinding(
                .info, category: "dynamic-list",
                message: "name of item 1 of \(propName) of \(path) = \(nameStr)"
            ))
        } catch {
            findings.append(LintFinding(
                .warning, category: "dynamic-list",
                message: "Cannot get property of list item: name of item 1 of \(propName) of \(path): \(error.localizedDescription)"
            ))
        }
    }

    // MARK: - Helpers

    /// Try to get a specifier's value, return true on success.
    private func testGetItemQuietly(spec: NSAppleEventDescriptor) -> Bool {
        (try? sender.sendGetEvent(to: appName, specifier: spec, timeoutSeconds: 10)) != nil
    }

    /// Build an element specifier using an absolute ordinal (kAEFirst, kAELast, etc.)
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

    /// Build an element specifier with a literal negative integer index
    /// (not converted to kAELast ordinal like buildByIndex(-1) does).
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

    /// Test that `get every <element>` works (not just counting).
    /// Some apps support counting but not bulk retrieval.
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

            // Only test element types we know have instances
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

            // Test: get every <element>
            let everySpec = builder.buildEveryElement(
                code: elemClass.code,
                container: NSAppleEventDescriptor.null()
            )

            do {
                let result = try sender.sendGetEvent(to: appName, specifier: everySpec, timeoutSeconds: 10)
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
                        message: "every \(elemClass.name): count returned \(count) but get every returned \(resultCount) items"
                    ))
                }
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-every",
                    message: "Cannot get every \(elemClass.name): \(error.localizedDescription)"
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

    /// Test filter-based element access using whose clauses.
    private func testWhoseClause() -> [LintFinding] {
        var findings: [LintFinding] = []
        guard let appClass = dictionary.findClass("application") else { return findings }

        let allElems = dictionary.allElements(for: appClass)

        for elem in allElems {
            if elem.hidden { continue }
            guard let elemClass = dictionary.findClass(elem.type) else { continue }
            if elemClass.hidden { continue }

            let elementCode = FourCharCode(elemClass.code)

            // Only test element types with instances
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

            // Need the name property to build a whose clause
            let allProps = dictionary.allProperties(for: elemClass)
            guard allProps.contains(where: { $0.code == "pnam" }) else { continue }

            // Get name of first element
            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )
            let nameSpec = builder.buildPropertySpecifier(code: "pnam", container: firstSpec)

            guard let nameReply = try? sender.sendGetEvent(to: appName, specifier: nameSpec, timeoutSeconds: 10),
                  let name = nameReply.stringValue, !name.isEmpty else {
                continue
            }

            // Test: <elements> whose name = "<name>"
            let testExpr = TestExpr(path: ["name"], op: .equal, value: .string(name))
            let whoseSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .test(testExpr),
                container: NSAppleEventDescriptor.null()
            )

            // Try to get name of the whose result
            let whoseNameSpec = builder.buildPropertySpecifier(code: "pnam", container: whoseSpec)
            do {
                let result = try sender.sendGetEvent(to: appName, specifier: whoseNameSpec, timeoutSeconds: 10)
                // Result may be a single value or a list
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
                        message: "\(elemClass.pluralName ?? elemClass.name) whose name = \"\(name)\": found \(resultNames.count) match(es)"
                    ))
                } else {
                    findings.append(LintFinding(
                        .warning, category: "dynamic-whose",
                        message: "\(elemClass.name) whose clause returned unexpected results for name = \"\(name)\""
                    ))
                }
            } catch {
                findings.append(LintFinding(
                    .warning, category: "dynamic-whose",
                    message: "\(elemClass.name) whose clause not supported: \(error.localizedDescription)"
                ))
            }
        }

        return findings
    }

    // MARK: - Exists event testing

    /// Test the 'exists' Apple Event (core/doex) on elements.
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

            // Test: exists <first element> — should return true
            let firstSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byIndex(1),
                container: NSAppleEventDescriptor.null()
            )

            do {
                let exists = try sender.sendExistsEvent(to: appName, specifier: firstSpec, timeoutSeconds: 10)
                if exists {
                    successCount += 1
                } else {
                    failCount += 1
                    findings.append(LintFinding(
                        .warning, category: "dynamic-exists",
                        message: "exists \(elemClass.name) 1 returned false (expected true, count = \(count))"
                    ))
                }
            } catch {
                failCount += 1
                findings.append(LintFinding(
                    .warning, category: "dynamic-exists",
                    message: "exists \(elemClass.name) 1 failed: \(error.localizedDescription)"
                ))
            }

            // Test: exists <element by impossible name> — should return false
            let bogusSpec = builder.buildElementWithPredicate(
                code: elemClass.code,
                predicate: .byName("__aelint_nonexistent_\(UUID().uuidString)__"),
                container: NSAppleEventDescriptor.null()
            )

            do {
                let exists = try sender.sendExistsEvent(to: appName, specifier: bogusSpec, timeoutSeconds: 10)
                if !exists {
                    // Correct: nonexistent element reports false
                } else {
                    findings.append(LintFinding(
                        .warning, category: "dynamic-exists",
                        message: "exists \(elemClass.name) with bogus name returned true (expected false)"
                    ))
                }
            } catch {
                // Some apps throw an error instead of returning false for nonexistent — that's acceptable
            }
        }

        findings.append(LintFinding(
            .info, category: "dynamic-exists",
            message: "Exists event: \(successCount) succeeded, \(failCount) failed"
        ))

        return findings
    }

    // MARK: - Type validation

    /// Check that property return types match their SDEF-declared types.
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

            let reply: NSAppleEventDescriptor
            do {
                reply = try sender.sendGetEvent(to: appName, specifier: propSpec, timeoutSeconds: 10)
            } catch {
                continue  // read failures already reported
            }

            let actualType = reply.descriptorType
            if isTypeCompatible(declaredType: declaredType, actualDescType: actualType) {
                matchCount += 1
            } else {
                mismatchCount += 1
                let actualStr = descTypeString(actualType)
                findings.append(LintFinding(
                    .info, category: "dynamic-type",
                    message: "Property '\(prop.name)' declared as '\(declaredType)' but returned descriptor type '\(actualStr)'"
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

    /// Check whether a returned descriptor type is compatible with the SDEF-declared type.
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
            return true  // any type is acceptable
        default:
            // Check if declared type is a class name → expect object specifier
            if dictionary.findClass(declaredType) != nil {
                return actualStr == "obj "
            }
            // Check if declared type is an enumeration → expect typeEnumerated
            if dictionary.findEnumeration(declaredType) != nil {
                return actualStr == "enum"
            }
            return true  // unknown types pass by default
        }
    }

    /// Convert a DescType to a 4-character string for display.
    private func descTypeString(_ dt: DescType) -> String {
        FourCharCode(dt).stringValue
    }
}
