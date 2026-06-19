import Testing
import Foundation
import CoreServices
@testable import AEQueryLib

/// Pins every hand-defined four-char code in ``AEConstants`` that has a
/// standardized counterpart in the system AppleEvent headers against that
/// counterpart. The codes are typed as raw string literals (e.g.
/// `FourCharCode("any ")`), so a transcription typo compiles cleanly and only
/// fails at runtime against a live app — exactly how `kAEAny` shipped as the
/// bogus `"sran"`. This suite turns that class of bug into a build failure.
///
/// The system constants arrive as a mix of `Int`, `OSType`, `DescType`, and
/// `AEKeyword`, so each is funnelled through `FourCharCode(truncatingIfNeeded:)`
/// for comparison.
@Suite("AEConstants match system headers")
struct AEConstantsTests {
    /// (label, project value, system value). System values come from
    /// `CoreServices` (the AppleEvent / Open Scripting headers).
    private static let pairs: [(String, FourCharCode, FourCharCode)] = [
        ("kAECoreSuite", AEConstants.kAECoreSuite, sys(kAECoreSuite)),
        ("kAEGetData", AEConstants.kAEGetData, sys(kAEGetData)),

        ("formAbsolutePosition", AEConstants.formAbsolutePosition, sys(formAbsolutePosition)),
        ("formName", AEConstants.formName, sys(formName)),
        ("formUniqueID", AEConstants.formUniqueID, sys(formUniqueID)),
        ("formRange", AEConstants.formRange, sys(formRange)),
        ("formTest", AEConstants.formTest, sys(formTest)),
        ("formPropertyID", AEConstants.formPropertyID, sys(formPropertyID)),

        ("typeObjectSpecifier", AEConstants.typeObjectSpecifier, sys(typeObjectSpecifier)),
        ("typeType", AEConstants.typeType, sys(typeType)),
        ("typeAbsoluteOrdinal", AEConstants.typeAbsoluteOrdinal, sys(typeAbsoluteOrdinal)),
        ("typeNull", AEConstants.typeNull, sys(typeNull)),
        ("typeObjectBeingExamined", AEConstants.typeObjectBeingExamined, sys(typeObjectBeingExamined)),
        ("typeCompDescriptor", AEConstants.typeCompDescriptor, sys(typeCompDescriptor)),
        ("typeLogicalDescriptor", AEConstants.typeLogicalDescriptor, sys(typeLogicalDescriptor)),
        ("typeRangeDescriptor", AEConstants.typeRangeDescriptor, sys(typeRangeDescriptor)),
        ("typeAEList", AEConstants.typeAEList, sys(typeAEList)),

        ("kAEAll", AEConstants.kAEAll, sys(kAEAll)),
        ("kAEFirst", AEConstants.kAEFirst, sys(kAEFirst)),
        ("kAELast", AEConstants.kAELast, sys(kAELast)),
        ("kAEMiddle", AEConstants.kAEMiddle, sys(kAEMiddle)),
        ("kAEAny", AEConstants.kAEAny, sys(kAEAny)),

        ("keyAEDesiredClass", AEConstants.keyAEDesiredClass, sys(keyAEDesiredClass)),
        ("keyAEContainer", AEConstants.keyAEContainer, sys(keyAEContainer)),
        ("keyAEKeyForm", AEConstants.keyAEKeyForm, sys(keyAEKeyForm)),
        ("keyAEKeyData", AEConstants.keyAEKeyData, sys(keyAEKeyData)),

        ("kAEEquals", AEConstants.kAEEquals, sys(kAEEquals)),
        ("kAEGreaterThan", AEConstants.kAEGreaterThan, sys(kAEGreaterThan)),
        ("kAELessThan", AEConstants.kAELessThan, sys(kAELessThan)),
        ("kAEGreaterThanEquals", AEConstants.kAEGreaterThanEquals, sys(kAEGreaterThanEquals)),
        ("kAELessThanEquals", AEConstants.kAELessThanEquals, sys(kAELessThanEquals)),
        ("kAEContains", AEConstants.kAEContains, sys(kAEContains)),
        ("kAEBeginsWith", AEConstants.kAEBeginsWith, sys(kAEBeginsWith)),
        ("kAEEndsWith", AEConstants.kAEEndsWith, sys(kAEEndsWith)),

        ("kAEAND", AEConstants.kAEAND, sys(kAEAND)),
        ("kAEOR", AEConstants.kAEOR, sys(kAEOR)),
        ("kAENOT", AEConstants.kAENOT, sys(kAENOT)),

        ("keyAECompOperator", AEConstants.keyAECompOperator, sys(keyAECompOperator)),
        ("keyAEObject1", AEConstants.keyAEObject1, sys(keyAEObject1)),
        ("keyAEObject2", AEConstants.keyAEObject2, sys(keyAEObject2)),
        ("keyAELogicalOperator", AEConstants.keyAELogicalOperator, sys(keyAELogicalOperator)),
        ("keyAELogicalTerms", AEConstants.keyAELogicalTerms, sys(keyAELogicalTerms)),
        ("keyAERangeStart", AEConstants.keyAERangeStart, sys(keyAERangeStart)),
        ("keyAERangeStop", AEConstants.keyAERangeStop, sys(keyAERangeStop)),

        ("keyDirectObject", AEConstants.keyDirectObject, sys(keyDirectObject)),
        ("keyAERequestedType", AEConstants.keyAERequestedType, sys(keyAERequestedType)),

        ("kAEDoObjectsExist", AEConstants.kAEDoObjectsExist, sys(kAEDoObjectsExist)),
        ("kAESetData", AEConstants.kAESetData, sys(kAESetData)),
        ("kAECreateElement", AEConstants.kAECreateElement, sys(kAECreateElement)),
        ("kAEDelete", AEConstants.kAEDelete, sys(kAEDelete)),

        ("keyAEObjectClass", AEConstants.keyAEObjectClass, sys(keyAEObjectClass)),
        ("keyAEInsertHere", AEConstants.keyAEInsertHere, sys(keyAEInsertHere)),

        ("cApplication", AEConstants.cApplication, sys(cApplication)),
        ("cWindow", AEConstants.cWindow, sys(cWindow)),
        ("cDocument", AEConstants.cDocument, sys(cDocument)),

        ("pName", AEConstants.pName, sys(pName)),

        ("errorNumber", AEConstants.errorNumber, sys(keyErrorNumber)),
        ("errorString", AEConstants.errorString, sys(keyErrorString)),
    ]

    /// Normalize a system constant (Int/OSType/DescType/AEKeyword) to FourCharCode.
    private static func sys<T: BinaryInteger>(_ value: T) -> FourCharCode {
        FourCharCode(truncatingIfNeeded: value)
    }

    @Test func everyStandardizedConstantMatchesSystemHeader() {
        for (label, project, system) in Self.pairs {
            #expect(
                project == system,
                "\(label): project '\(project.stringValue)' != system '\(system.stringValue)'"
            )
        }
    }

    // The following AEConstants are intentionally NOT cross-checked because no
    // standardized symbol for them is surfaced into Swift by the system headers:
    //   • kAENotEquals ('!=  ')        — AppleScript expresses ≠ as NOT(=); no AE operator.
    //   • typeProperty ('type')        — project-local alias of typeType.
    //   • pAll ('pALL')                — keyAEProperties is 'qpro', not a match.
    //   • errorOffendingObject ('erob')— no exposed system constant.
}
