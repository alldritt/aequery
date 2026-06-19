import Foundation

/// A single rule describing a property that should be skipped during dynamic
/// testing. A `nil` field means "match anything" for that dimension.
struct PropertyExclusion: Equatable {
    let bundleID: String?     // nil = any application
    let className: String?    // nil = any class (matched against the class under test)
    let propertyName: String  // required, matched case-insensitively

    func matches(propertyName p: String, className c: String, bundleID b: String?) -> Bool {
        guard propertyName.lowercased() == p.lowercased() else { return false }
        if let className, className.lowercased() != c.lowercased() { return false }
        if let bundleID, bundleID.lowercased() != (b ?? "").lowercased() { return false }
        return true
    }
}

/// The set of property exclusions in effect for a run, plus the built-in
/// defaults that keep `--dynamic` from wedging known-problematic apps.
struct PropertyExclusions {
    let rules: [PropertyExclusion]

    /// Properties skipped by default. These recursively enumerate large object
    /// graphs (e.g. the filesystem) and can hang the target application.
    /// Script Debugger excludes Finder's `entire contents` for the same reason.
    static let defaults: [PropertyExclusion] = [
        PropertyExclusion(bundleID: "com.apple.finder", className: nil, propertyName: "entire contents"),
    ]

    func isExcluded(property: String, className: String, bundleID: String?) -> Bool {
        rules.contains { $0.matches(propertyName: property, className: className, bundleID: bundleID) }
    }

    /// Parse a CLI token of the form `property` or `Class.property` into a rule.
    /// User-supplied rules apply to the current run regardless of bundle ID.
    static func parse(_ token: String) -> PropertyExclusion {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if let dot = trimmed.firstIndex(of: ".") {
            let cls = String(trimmed[..<dot]).trimmingCharacters(in: .whitespaces)
            let prop = String(trimmed[trimmed.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            return PropertyExclusion(bundleID: nil, className: cls.isEmpty ? nil : cls, propertyName: prop)
        }
        return PropertyExclusion(bundleID: nil, className: nil, propertyName: trimmed)
    }

    /// Build the effective rule set: built-in defaults (unless disabled) plus
    /// any user-supplied `--exclude` tokens.
    static func build(userTokens: [String], includeDefaults: Bool) -> PropertyExclusions {
        var rules = includeDefaults ? defaults : []
        rules += userTokens.map { parse($0) }
        return PropertyExclusions(rules: rules)
    }
}
