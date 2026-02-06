import Foundation

public typealias FourCharCode = UInt32

extension FourCharCode {
    /// Initialize from a 4-character ASCII string like "capp" or "pnam"
    public init(_ fourCharString: String) {
        precondition(fourCharString.utf8.count == 4, "FourCharCode requires exactly 4 ASCII characters, got '\(fourCharString)'")
        let bytes = Array(fourCharString.utf8)
        self = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    /// Convert back to a 4-character string
    public var stringValue: String {
        let chars: [UInt8] = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
        return String(bytes: chars, encoding: .ascii) ?? "????"
    }
}

// Well-known type codes
public enum AEConstants {
    // Event class/ID
    public static let kAECoreSuite = FourCharCode("core")
    public static let kAEGetData = FourCharCode("getd")

    // Key forms
    public static let formAbsolutePosition = FourCharCode("indx")
    public static let formName = FourCharCode("name")
    public static let formUniqueID = FourCharCode("ID  ")
    public static let formRange = FourCharCode("rang")
    public static let formTest = FourCharCode("test")
    public static let formPropertyID = FourCharCode("prop")

    // Misc
    public static let typeObjectSpecifier = FourCharCode("obj ")
    public static let typeProperty = FourCharCode("type")
    public static let typeType = FourCharCode("type")
    public static let typeAbsoluteOrdinal = FourCharCode("abso")
    public static let typeNull = FourCharCode("null")
    public static let typeObjectBeingExamined = FourCharCode("exmn")
    public static let typeCompDescriptor = FourCharCode("cmpd")
    public static let typeLogicalDescriptor = FourCharCode("logi")
    public static let typeRangeDescriptor = FourCharCode("rang")

    // Ordinals
    public static let kAEAll = FourCharCode("all ")
    public static let kAEFirst = FourCharCode("firs")
    public static let kAELast = FourCharCode("last")
    public static let kAEMiddle = FourCharCode("midd")
    public static let kAEAny = FourCharCode("sran")

    // Object specifier keys
    public static let keyAEDesiredClass = FourCharCode("want")
    public static let keyAEContainer = FourCharCode("from")
    public static let keyAEKeyForm = FourCharCode("form")
    public static let keyAEKeyData = FourCharCode("seld")

    // Comparison operators
    public static let kAEEquals = FourCharCode("=   ")
    public static let kAEGreaterThan = FourCharCode(">   ")
    public static let kAELessThan = FourCharCode("<   ")
    public static let kAEGreaterThanEquals = FourCharCode(">=  ")
    public static let kAELessThanEquals = FourCharCode("<=  ")
    public static let kAENotEquals = FourCharCode("!=  ")
    public static let kAEContains = FourCharCode("cont")
    public static let kAEBeginsWith = FourCharCode("bgwt")
    public static let kAEEndsWith = FourCharCode("ends")

    // Logical operators
    public static let kAEAND = FourCharCode("AND ")
    public static let kAEOR = FourCharCode("OR  ")
    public static let kAENOT = FourCharCode("NOT ")

    // Comparison descriptor keys
    public static let keyAECompOperator = FourCharCode("relo")
    public static let keyAEObject1 = FourCharCode("obj1")
    public static let keyAEObject2 = FourCharCode("obj2")

    // Logical descriptor keys
    public static let keyAELogicalOperator = FourCharCode("logc")
    public static let keyAELogicalTerms = FourCharCode("term")

    // Range descriptor keys
    public static let keyAERangeStart = FourCharCode("star")
    public static let keyAERangeStop = FourCharCode("stop")

    // Event params
    public static let keyDirectObject = FourCharCode("----")
    public static let keyAERequestedType = FourCharCode("rtyp")

    // Well-known class codes
    public static let cApplication = FourCharCode("capp")
    public static let cWindow = FourCharCode("cwin")
    public static let cDocument = FourCharCode("docu")

    // Property code
    public static let pName = FourCharCode("pnam")
    
    // Error codes
    public static let errorNumber = FourCharCode("errn")
    public static let errorString = FourCharCode("errs")
    public static let errorOffendingObject = FourCharCode("erob")
}
