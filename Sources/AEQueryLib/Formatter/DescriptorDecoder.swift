import Foundation

public enum AEValue: Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case list([AEValue])
    case record([(String, AEValue)])
    case null

    public static func == (lhs: AEValue, rhs: AEValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.integer(let a), .integer(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.date(let a), .date(let b)): return a == b
        case (.list(let a), .list(let b)): return a == b
        case (.null, .null): return true
        case (.record(let a), .record(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }
}

public struct DescriptorDecoder {
    public init() {}

    public func decode(_ descriptor: NSAppleEventDescriptor) -> AEValue {
        let typeCode = descriptor.descriptorType

        switch typeCode {
        // Null
        case typeNull:
            return .null

        // Boolean types
        case typeTrue:
            return .bool(true)
        case typeFalse:
            return .bool(false)
        case typeBoolean:
            return .bool(descriptor.booleanValue)

        // Integer types
        case typeSInt16, typeSInt32:
            return .integer(Int(descriptor.int32Value))
        case typeSInt64:
            let data = descriptor.data
            if data.count >= 8 {
                let val = data.withUnsafeBytes { $0.load(as: Int64.self) }
                return .integer(Int(val))
            }
            return .integer(Int(descriptor.int32Value))
        case typeUInt32:
            let data = descriptor.data
            if data.count >= 4 {
                let val = data.withUnsafeBytes { $0.load(as: UInt32.self) }
                return .integer(Int(val))
            }
            return .integer(Int(descriptor.int32Value))

        // Float types
        case typeIEEE32BitFloatingPoint:
            let data = descriptor.data
            if data.count >= 4 {
                let val = data.withUnsafeBytes { $0.load(as: Float.self) }
                return .double(Double(val))
            }
            return .double(0)
        case typeIEEE64BitFloatingPoint:
            let data = descriptor.data
            if data.count >= 8 {
                let val = data.withUnsafeBytes { $0.load(as: Double.self) }
                return .double(val)
            }
            return .double(0)

        // String types
        case typeUTF8Text, typeUnicodeText, typeUTF16ExternalRepresentation:
            return .string(descriptor.stringValue ?? "")
        case typeChar:
            return .string(descriptor.stringValue ?? "")

        // Date
        case typeLongDateTime:
            return .date(descriptor.dateValue ?? Date())

        // List
        case typeAEList:
            var items: [AEValue] = []
            for i in 1...max(1, descriptor.numberOfItems) {
                if let item = descriptor.atIndex(i) {
                    items.append(decode(item))
                }
            }
            // Handle empty lists
            if descriptor.numberOfItems == 0 {
                return .list([])
            }
            return .list(items)

        // Record
        case typeAERecord:
            var pairs: [(String, AEValue)] = []
            for i in 1...max(1, descriptor.numberOfItems) {
                let keyword = descriptor.keywordForDescriptor(at: i)
                if let item = descriptor.atIndex(i) {
                    let key = FourCharCode(keyword).stringValue
                    pairs.append((key, decode(item)))
                }
            }
            if descriptor.numberOfItems == 0 {
                return .record([])
            }
            return .record(pairs)

        // Type/Enum
        case typeType, typeEnumerated:
            let val = descriptor.typeCodeValue
            return .string(FourCharCode(val).stringValue)

        default:
            // Try coercing to string as a fallback
            if let str = descriptor.stringValue {
                return .string(str)
            }
            // Return the type code as a string for debugging
            let typeStr = FourCharCode(typeCode).stringValue
            return .string("[\(typeStr)]")
        }
    }
}

// Type codes from AE framework (UInt32 = OSType = DescriptorType)
private let typeNull: UInt32 = 0x6E756C6C       // 'null'
private let typeTrue: UInt32 = 0x74727565       // 'true'
private let typeFalse: UInt32 = 0x66616C73      // 'fals'
private let typeBoolean: UInt32 = 0x626F6F6C    // 'bool'
private let typeSInt16: UInt32 = 0x73686F72     // 'shor'
private let typeSInt32: UInt32 = 0x6C6F6E67     // 'long'
private let typeSInt64: UInt32 = 0x636F6D70     // 'comp'
private let typeUInt32: UInt32 = 0x6D61676E     // 'magn'
private let typeIEEE32BitFloatingPoint: UInt32 = 0x73696E67 // 'sing'
private let typeIEEE64BitFloatingPoint: UInt32 = 0x646F7562 // 'doub'
private let typeUTF8Text: UInt32 = 0x75746638   // 'utf8'
private let typeUnicodeText: UInt32 = 0x75747874 // 'utxt'
private let typeUTF16ExternalRepresentation: UInt32 = 0x75743136 // 'ut16'
private let typeChar: UInt32 = 0x54455854       // 'TEXT'
private let typeLongDateTime: UInt32 = 0x6C647420 // 'ldt '
private let typeAEList: UInt32 = 0x6C697374     // 'list'
private let typeAERecord: UInt32 = 0x7265636F   // 'reco'
private let typeType: UInt32 = 0x74797065       // 'type'
private let typeEnumerated: UInt32 = 0x656E756D // 'enum'
