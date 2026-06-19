import Foundation

/// Resolves whether a type name is defined by one of macOS's system-wide
/// scripting type files, instead of guessing "may be a system-defined type".
///
/// AppleScript's standard and legacy types are declared in a small set of
/// canonical SDEF files shipped with macOS:
///   - Foundation's `Intrinsics.sdef` — the core value types (`text`,
///     `integer`, `boolean`, `record`, …).
///   - `CocoaStandard.sdef` — the Cocoa Standard suite (`print settings`,
///     `save options`, the `document`/`window` classes, …).
///   - OpenScripting's `Compatibility.sdef` — the comprehensive legacy
///     AppleScript catalog (`double integer`, `picture`, `RGB color`,
///     `list`, `alias`, `data`, the month/weekday classes, …).
///
/// We collect every named type (class, value-type, record-type, enumeration)
/// declared by those files so a validator can verify a dangling type
/// reference against them rather than assuming it is system-defined.
public struct SystemTypeRegistry {
    /// Canonical system SDEF files. Missing files are skipped gracefully so
    /// the registry stays usable across macOS versions.
    public static let systemSDEFPaths: [String] = [
        "/System/Library/Frameworks/Foundation.framework/Versions/C/Resources/Intrinsics.sdef",
        "/System/Library/ScriptingDefinitions/CocoaStandard.sdef",
        "/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/OpenScripting.framework/Versions/A/Resources/Compatibility.sdef",
    ]

    /// Lowercased names of every type declared by the system SDEF files.
    public let typeNames: Set<String>

    public init(paths: [String] = SystemTypeRegistry.systemSDEFPaths) {
        var names: Set<String> = []
        // Every element that declares a named type usable as a type reference.
        let xpath = "//class[@name] | //value-type[@name] | //record-type[@name] | //enumeration[@name]"
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path),
                  let doc = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]),
                  let nodes = try? doc.nodes(forXPath: xpath) else { continue }
            for node in nodes {
                guard let element = node as? XMLElement,
                      let name = element.attribute(forName: "name")?.stringValue else { continue }
                names.insert(name.lowercased())
            }
        }
        self.typeNames = names
    }

    /// Whether `name` is a type declared by one of the system SDEF files.
    public func isSystemType(_ name: String) -> Bool {
        typeNames.contains(name.lowercased())
    }
}
