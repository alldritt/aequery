import Foundation

public struct ObjectSpecifierBuilder {
    private let dictionary: ScriptingDictionary?

    public init(dictionary: ScriptingDictionary? = nil) {
        self.dictionary = dictionary
    }

    /// Build a complete object specifier chain from resolved steps.
    /// The chain is built innermost-first: application → first step → ... → last step.
    /// When there are no steps, returns a specifier for all properties of the application.
    public func buildSpecifier(from resolvedQuery: ResolvedQuery) -> NSAppleEventDescriptor {
        var container = NSAppleEventDescriptor.null()

        if resolvedQuery.steps.isEmpty {
            // No steps: get all properties of the application
            return buildPropertySpecifier(code: AEConstants.pAll.stringValue, container: container)
        }

        for step in resolvedQuery.steps {
            container = buildStep(step, container: container)
        }

        return container
    }

    /// Build a single step's specifier with the given container.
    public func buildStep(_ step: ResolvedStep, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        switch step.kind {
        case .property:
            return buildPropertySpecifier(code: step.code, container: container)
        case .element:
            if step.predicates.isEmpty {
                return buildEveryElement(code: step.code, container: container)
            }
            let predicate = step.predicates[0]
            return buildElementWithPredicate(code: step.code, predicate: predicate, container: container)
        }
    }

    // MARK: - Property

    public func buildPropertySpecifier(code: String, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()
        let fourCC = FourCharCode(code)

        // want = type(prop)
        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: AEConstants.formPropertyID),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        // from = container
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        // form = formPropertyID
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formPropertyID),
            forKeyword: AEConstants.keyAEKeyForm
        )
        // seld = type code of the property
        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: fourCC),
            forKeyword: AEConstants.keyAEKeyData
        )

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - Every element (no predicate)

    public func buildEveryElement(code: String, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
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
        // seld = kAEAll as typeAbsoluteOrdinal (native byte order)
        var allCode = AEConstants.kAEAll
        let allData = Data(bytes: &allCode, count: 4)
        let allDesc = NSAppleEventDescriptor(descriptorType: AEConstants.typeAbsoluteOrdinal, data: allData)!
        specifier.setDescriptor(allDesc, forKeyword: AEConstants.keyAEKeyData)

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - Element with predicate

    public func buildElementWithPredicate(code: String, predicate: Predicate, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let fourCC = FourCharCode(code)

        switch predicate {
        case .byIndex(let index):
            return buildByIndex(wantCode: fourCC, index: index, container: container)
        case .byName(let name):
            return buildByName(wantCode: fourCC, name: name, container: container)
        case .byID(let value):
            return buildByID(wantCode: fourCC, value: value, container: container)
        case .byOrdinal(let ordinal):
            return buildByOrdinal(wantCode: fourCC, ordinal: ordinal, container: container)
        case .byRange(let start, let stop):
            return buildByRange(wantCode: fourCC, start: start, stop: stop, container: container)
        case .test(let testExpr):
            return buildByTest(wantCode: fourCC, test: testExpr, container: container)
        case .compound(let left, let boolOp, let right):
            return buildByCompoundTest(wantCode: fourCC, left: left, boolOp: boolOp, right: right, container: container)
        }
    }

    // MARK: - By index

    private func buildByIndex(wantCode: FourCharCode, index: Int, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()

        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: wantCode),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formAbsolutePosition),
            forKeyword: AEConstants.keyAEKeyForm
        )

        if index == -1 {
            specifier.setDescriptor(
                NSAppleEventDescriptor(enumCode: AEConstants.kAELast),
                forKeyword: AEConstants.keyAEKeyData
            )
        } else {
            specifier.setDescriptor(
                NSAppleEventDescriptor(int32: Int32(index)),
                forKeyword: AEConstants.keyAEKeyData
            )
        }

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - By ordinal

    private func buildByOrdinal(wantCode: FourCharCode, ordinal: Ordinal, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()

        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: wantCode),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formAbsolutePosition),
            forKeyword: AEConstants.keyAEKeyForm
        )

        let ordinalCode: FourCharCode
        switch ordinal {
        case .middle: ordinalCode = AEConstants.kAEMiddle
        case .some: ordinalCode = AEConstants.kAEAny
        }
        var code = ordinalCode
        let data = Data(bytes: &code, count: 4)
        let ordinalDesc = NSAppleEventDescriptor(descriptorType: AEConstants.typeAbsoluteOrdinal, data: data)!
        specifier.setDescriptor(ordinalDesc, forKeyword: AEConstants.keyAEKeyData)

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - By name

    private func buildByName(wantCode: FourCharCode, name: String, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()

        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: wantCode),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formName),
            forKeyword: AEConstants.keyAEKeyForm
        )
        specifier.setDescriptor(
            NSAppleEventDescriptor(string: name),
            forKeyword: AEConstants.keyAEKeyData
        )

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - By ID

    private func buildByID(wantCode: FourCharCode, value: Value, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()

        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: wantCode),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formUniqueID),
            forKeyword: AEConstants.keyAEKeyForm
        )

        let seld: NSAppleEventDescriptor
        switch value {
        case .integer(let n):
            seld = NSAppleEventDescriptor(int32: Int32(n))
        case .string(let s):
            seld = NSAppleEventDescriptor(string: s)
        }
        specifier.setDescriptor(seld, forKeyword: AEConstants.keyAEKeyData)

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - By range

    private func buildByRange(wantCode: FourCharCode, start: Int, stop: Int, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        // Build range descriptor
        let rangeDesc = NSAppleEventDescriptor.record()

        // Start specifier
        let startSpec = NSAppleEventDescriptor.record()
        startSpec.setDescriptor(NSAppleEventDescriptor(typeCode: wantCode), forKeyword: AEConstants.keyAEDesiredClass)
        startSpec.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEConstants.keyAEContainer)
        startSpec.setDescriptor(NSAppleEventDescriptor(enumCode: AEConstants.formAbsolutePosition), forKeyword: AEConstants.keyAEKeyForm)
        startSpec.setDescriptor(NSAppleEventDescriptor(int32: Int32(start)), forKeyword: AEConstants.keyAEKeyData)
        let startObjSpec = startSpec.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!

        // Stop specifier
        let stopSpec = NSAppleEventDescriptor.record()
        stopSpec.setDescriptor(NSAppleEventDescriptor(typeCode: wantCode), forKeyword: AEConstants.keyAEDesiredClass)
        stopSpec.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEConstants.keyAEContainer)
        stopSpec.setDescriptor(NSAppleEventDescriptor(enumCode: AEConstants.formAbsolutePosition), forKeyword: AEConstants.keyAEKeyForm)
        stopSpec.setDescriptor(NSAppleEventDescriptor(int32: Int32(stop)), forKeyword: AEConstants.keyAEKeyData)
        let stopObjSpec = stopSpec.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!

        rangeDesc.setDescriptor(startObjSpec, forKeyword: AEConstants.keyAERangeStart)
        rangeDesc.setDescriptor(stopObjSpec, forKeyword: AEConstants.keyAERangeStop)

        let rangeCoerced = rangeDesc.coerce(toDescriptorType: AEConstants.typeRangeDescriptor)!

        // Build the element specifier with formRange
        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: wantCode), forKeyword: AEConstants.keyAEDesiredClass)
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: AEConstants.formRange), forKeyword: AEConstants.keyAEKeyForm)
        specifier.setDescriptor(rangeCoerced, forKeyword: AEConstants.keyAEKeyData)

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    // MARK: - By test (whose clause)

    private func buildByTest(wantCode: FourCharCode, test: TestExpr, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let testDesc = buildTestDescriptor(test, inClassCode: wantCode)

        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: wantCode), forKeyword: AEConstants.keyAEDesiredClass)
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: AEConstants.formTest), forKeyword: AEConstants.keyAEKeyForm)
        specifier.setDescriptor(testDesc, forKeyword: AEConstants.keyAEKeyData)

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    private func buildTestDescriptor(_ test: TestExpr, inClassCode classCode: FourCharCode? = nil) -> NSAppleEventDescriptor {
        let comp = NSAppleEventDescriptor.record()

        // obj1 = property specifier using objectBeingExamined as container
        let examContainer = NSAppleEventDescriptor(descriptorType: AEConstants.typeObjectBeingExamined, data: nil)!
        // Build a property specifier for the test path (simplified: just use first element as property name)
        let propName = test.path.first ?? ""
        let propDesc = buildPropertyRefForTest(name: propName, container: examContainer, inClassCode: classCode)

        comp.setDescriptor(propDesc, forKeyword: AEConstants.keyAEObject1)

        // relo = comparison operator
        let opCode = comparisonOpCode(test.op)
        comp.setDescriptor(
            NSAppleEventDescriptor(enumCode: opCode),
            forKeyword: AEConstants.keyAECompOperator
        )

        // obj2 = value
        let valDesc: NSAppleEventDescriptor
        switch test.value {
        case .integer(let n):
            valDesc = NSAppleEventDescriptor(int32: Int32(n))
        case .string(let s):
            valDesc = NSAppleEventDescriptor(string: s)
        }
        comp.setDescriptor(valDesc, forKeyword: AEConstants.keyAEObject2)

        return comp.coerce(toDescriptorType: AEConstants.typeCompDescriptor)!
    }

    private func buildPropertyRefForTest(name: String, container: NSAppleEventDescriptor, inClassCode classCode: FourCharCode? = nil) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: AEConstants.formPropertyID),
            forKeyword: AEConstants.keyAEDesiredClass
        )
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(
            NSAppleEventDescriptor(enumCode: AEConstants.formPropertyID),
            forKeyword: AEConstants.keyAEKeyForm
        )
        let code = resolvePropertyCode(name, inClassCode: classCode)
        specifier.setDescriptor(
            NSAppleEventDescriptor(typeCode: code),
            forKeyword: AEConstants.keyAEKeyData
        )
        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    private func resolvePropertyCode(_ name: String, inClassCode classCode: FourCharCode? = nil) -> FourCharCode {
        if let dictionary = dictionary {
            let lower = name.lowercased()
            // If we have a class context, look up the property in that class first
            if let classCode = classCode,
               let classDef = dictionary.findClassByCode(classCode.stringValue) {
                if let prop = dictionary.allProperties(for: classDef).first(where: { $0.name.lowercased() == lower }) {
                    return FourCharCode(prop.code)
                }
            }
            // Search all classes as fallback
            for classDef in dictionary.classes.values {
                if let prop = dictionary.allProperties(for: classDef).first(where: { $0.name.lowercased() == lower }) {
                    return FourCharCode(prop.code)
                }
            }
        }
        // Last resort: pad or truncate to 4 ASCII characters
        var padded = name.prefix(4).lowercased()
        while padded.count < 4 { padded += " " }
        return FourCharCode(String(padded))
    }

    private func comparisonOpCode(_ op: ComparisonOp) -> FourCharCode {
        switch op {
        case .equal: return AEConstants.kAEEquals
        case .notEqual: return AEConstants.kAENotEquals
        case .lessThan: return AEConstants.kAELessThan
        case .greaterThan: return AEConstants.kAEGreaterThan
        case .lessOrEqual: return AEConstants.kAELessThanEquals
        case .greaterOrEqual: return AEConstants.kAEGreaterThanEquals
        case .contains: return AEConstants.kAEContains
        case .beginsWith: return AEConstants.kAEBeginsWith
        case .endsWith: return AEConstants.kAEEndsWith
        }
    }

    // MARK: - Compound test

    private func buildByCompoundTest(wantCode: FourCharCode, left: Predicate, boolOp: BoolOp, right: Predicate, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let leftDesc = buildPredicateTestDescriptor(left, inClassCode: wantCode)
        let rightDesc = buildPredicateTestDescriptor(right, inClassCode: wantCode)

        let logicalDesc = NSAppleEventDescriptor.record()
        let logOp: FourCharCode = boolOp == .and ? AEConstants.kAEAND : AEConstants.kAEOR
        logicalDesc.setDescriptor(
            NSAppleEventDescriptor(enumCode: logOp),
            forKeyword: AEConstants.keyAELogicalOperator
        )

        let termsList = NSAppleEventDescriptor.list()
        termsList.insert(leftDesc, at: 1)
        termsList.insert(rightDesc, at: 2)
        logicalDesc.setDescriptor(termsList, forKeyword: AEConstants.keyAELogicalTerms)

        let logicalCoerced = logicalDesc.coerce(toDescriptorType: AEConstants.typeLogicalDescriptor)!

        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: wantCode), forKeyword: AEConstants.keyAEDesiredClass)
        specifier.setDescriptor(container, forKeyword: AEConstants.keyAEContainer)
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: AEConstants.formTest), forKeyword: AEConstants.keyAEKeyForm)
        specifier.setDescriptor(logicalCoerced, forKeyword: AEConstants.keyAEKeyData)

        return specifier.coerce(toDescriptorType: AEConstants.typeObjectSpecifier)!
    }

    private func buildPredicateTestDescriptor(_ predicate: Predicate, inClassCode classCode: FourCharCode? = nil) -> NSAppleEventDescriptor {
        switch predicate {
        case .test(let testExpr):
            return buildTestDescriptor(testExpr, inClassCode: classCode)
        case .compound(let left, let boolOp, let right):
            let leftDesc = buildPredicateTestDescriptor(left, inClassCode: classCode)
            let rightDesc = buildPredicateTestDescriptor(right, inClassCode: classCode)
            let logicalDesc = NSAppleEventDescriptor.record()
            let logOp: FourCharCode = boolOp == .and ? AEConstants.kAEAND : AEConstants.kAEOR
            logicalDesc.setDescriptor(NSAppleEventDescriptor(enumCode: logOp), forKeyword: AEConstants.keyAELogicalOperator)
            let termsList = NSAppleEventDescriptor.list()
            termsList.insert(leftDesc, at: 1)
            termsList.insert(rightDesc, at: 2)
            logicalDesc.setDescriptor(termsList, forKeyword: AEConstants.keyAELogicalTerms)
            return logicalDesc.coerce(toDescriptorType: AEConstants.typeLogicalDescriptor)!
        default:
            // For non-test predicates, return a null descriptor as fallback
            return NSAppleEventDescriptor.null()
        }
    }
}
