import Foundation

public struct AEQuery: Equatable {
    public let appName: String
    public let steps: [Step]

    public init(appName: String, steps: [Step]) {
        self.appName = appName
        self.steps = steps
    }
}

public struct Step: Equatable {
    public let name: String
    public let predicates: [Predicate]

    public init(name: String, predicates: [Predicate] = []) {
        self.name = name
        self.predicates = predicates
    }
}

public indirect enum Predicate: Equatable {
    case byIndex(Int)
    case byRange(Int, Int)
    case byName(String)
    case byID(Value)
    case test(TestExpr)
    case compound(Predicate, BoolOp, Predicate)
}

public struct TestExpr: Equatable {
    public let path: [String]
    public let op: ComparisonOp
    public let value: Value

    public init(path: [String], op: ComparisonOp, value: Value) {
        self.path = path
        self.op = op
        self.value = value
    }
}

public enum ComparisonOp: Equatable {
    case equal
    case notEqual
    case lessThan
    case greaterThan
    case lessOrEqual
    case greaterOrEqual
    case contains
    case beginsWith
    case endsWith
}

public enum BoolOp: Equatable {
    case and
    case or
}

public enum Value: Equatable {
    case string(String)
    case integer(Int)
}
