import Foundation

public struct SDEFParser {
    public init() {}

    public func parse(data: Data) throws -> ScriptingDictionary {
        let doc = try XMLDocument(data: data)

        // Resolve xi:include directives before parsing
        resolveXIncludes(in: doc)

        var dictionary = ScriptingDictionary()

        // Parse all suites
        let suites = try doc.nodes(forXPath: "//dictionary/suite")
        for suite in suites {
            guard let suiteElement = suite as? XMLElement else { continue }
            try parseSuite(suiteElement, into: &dictionary)
        }

        return dictionary
    }

    /// Resolve `xi:include` elements by loading the referenced file and inlining its content.
    private func resolveXIncludes(in doc: XMLDocument) {
        guard let includes = try? doc.nodes(forXPath: "//*[local-name()='include']"),
              !includes.isEmpty else { return }
        resolveIncludeNodes(includes)
    }

    private func resolveIncludeNodes(_ includes: [XMLNode]) {
        for include in includes {
            guard let includeElement = include as? XMLElement,
                  let href = includeElement.attribute(forName: "href")?.stringValue,
                  let url = URL(string: href),
                  let data = try? Data(contentsOf: url),
                  let includedDoc = try? XMLDocument(data: data) else { continue }

            let parent = includeElement.parent as? XMLElement
            let index = includeElement.index

            // Collect nodes to insert from the included document
            // The xpointer typically selects suite children; just grab all suite-level nodes
            var nodesToInsert: [XMLNode] = []
            if let suites = try? includedDoc.nodes(forXPath: "//dictionary/suite") {
                nodesToInsert = suites
            } else if let rootChildren = includedDoc.rootElement()?.children {
                nodesToInsert = rootChildren
            }

            // Remove the xi:include element
            includeElement.detach()

            // Insert the included nodes at the same position
            for (offset, node) in nodesToInsert.enumerated() {
                let copy = node.copy() as! XMLNode
                parent?.insertChild(copy, at: index + offset)
            }
        }
    }

    public func parse(xmlString: String) throws -> ScriptingDictionary {
        guard let data = xmlString.data(using: .utf8) else {
            throw SDEFParserError.invalidXML
        }
        return try parse(data: data)
    }

    private func parseSuite(_ suite: XMLElement, into dictionary: inout ScriptingDictionary) throws {
        // Parse classes
        for node in try suite.nodes(forXPath: "class") {
            guard let element = node as? XMLElement else { continue }
            let classDef = try parseClass(element)
            dictionary.addClass(classDef)
        }

        // Parse class-extensions
        for node in try suite.nodes(forXPath: "class-extension") {
            guard let element = node as? XMLElement else { continue }
            guard let extends = element.attribute(forName: "extends")?.stringValue else { continue }
            let properties = parseProperties(element)
            let elements = parseElements(element)
            dictionary.mergeExtension(into: extends, properties: properties, elements: elements)
        }

        // Parse enumerations
        for node in try suite.nodes(forXPath: "enumeration") {
            guard let element = node as? XMLElement else { continue }
            let enumDef = parseEnumeration(element)
            dictionary.enumerations[enumDef.name.lowercased()] = enumDef
        }
    }

    private func parseClass(_ element: XMLElement) throws -> ClassDef {
        guard let name = element.attribute(forName: "name")?.stringValue,
              let code = element.attribute(forName: "code")?.stringValue else {
            throw SDEFParserError.missingAttribute("name or code on class")
        }
        let plural = element.attribute(forName: "plural")?.stringValue
        let inherits = element.attribute(forName: "inherits")?.stringValue
        let hidden = element.attribute(forName: "hidden")?.stringValue == "yes"
        let properties = parseProperties(element)
        let elements = parseElements(element)

        return ClassDef(
            name: name,
            code: code,
            pluralName: plural,
            inherits: inherits,
            hidden: hidden,
            properties: properties,
            elements: elements
        )
    }

    private func parseProperties(_ element: XMLElement) -> [PropertyDef] {
        var props: [PropertyDef] = []
        for node in (try? element.nodes(forXPath: "property")) ?? [] {
            guard let propElement = node as? XMLElement,
                  let name = propElement.attribute(forName: "name")?.stringValue,
                  let code = propElement.attribute(forName: "code")?.stringValue else { continue }
            let type = propElement.attribute(forName: "type")?.stringValue
            let accessStr = propElement.attribute(forName: "access")?.stringValue
            let access = accessStr.flatMap { PropertyAccess(rawValue: $0) }
            let hidden = propElement.attribute(forName: "hidden")?.stringValue == "yes"
            props.append(PropertyDef(name: name, code: code, type: type, access: access, hidden: hidden))
        }
        return props
    }

    private func parseElements(_ element: XMLElement) -> [ElementDef] {
        var elems: [ElementDef] = []
        for node in (try? element.nodes(forXPath: "element")) ?? [] {
            guard let elemElement = node as? XMLElement,
                  let type = elemElement.attribute(forName: "type")?.stringValue else { continue }
            let access = elemElement.attribute(forName: "access")?.stringValue
            let hidden = elemElement.attribute(forName: "hidden")?.stringValue == "yes"
            elems.append(ElementDef(type: type, access: access, hidden: hidden))
        }
        return elems
    }

    private func parseEnumeration(_ element: XMLElement) -> EnumDef {
        let name = element.attribute(forName: "name")?.stringValue ?? ""
        let code = element.attribute(forName: "code")?.stringValue
        var enumerators: [Enumerator] = []
        for node in (try? element.nodes(forXPath: "enumerator")) ?? [] {
            guard let enumElement = node as? XMLElement,
                  let eName = enumElement.attribute(forName: "name")?.stringValue,
                  let eCode = enumElement.attribute(forName: "code")?.stringValue else { continue }
            enumerators.append(Enumerator(name: eName, code: eCode))
        }
        return EnumDef(name: name, code: code, enumerators: enumerators)
    }
}

/// Load SDEF from an application
public struct SDEFLoader {
    public init() {}

    public func loadSDEF(forApp appName: String) throws -> ScriptingDictionary {
        let appPath = try resolveAppPath(appName)

        // Try reading .sdef from bundle directly
        if let sdefData = try? loadSDEFFromBundle(appPath) {
            return try SDEFParser().parse(data: sdefData)
        }

        // Fall back to /usr/bin/sdef command
        let sdefData = try loadSDEFViaCommand(appPath)
        return try SDEFParser().parse(data: sdefData)
    }

    private func resolveAppPath(_ appName: String) throws -> String {
        // Try common locations
        let candidates = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            "/Applications/Utilities/\(appName).app",
            "/System/Library/CoreServices/\(appName).app",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using 'mdfind' to locate the app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemKind == 'Application' && kMDItemDisplayName == '\(appName)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty, let first = output.components(separatedBy: "\n").first,
           FileManager.default.fileExists(atPath: first) {
            return first
        }

        throw AEQueryError.appNotFound(appName)
    }

    private func bundleIDForName(_ name: String) -> String {
        let wellKnown: [String: String] = [
            "finder": "com.apple.finder",
            "safari": "com.apple.Safari",
            "textedit": "com.apple.TextEdit",
            "mail": "com.apple.mail",
            "music": "com.apple.Music",
            "system events": "com.apple.systemevents",
            "terminal": "com.apple.Terminal",
            "notes": "com.apple.Notes",
            "calendar": "com.apple.iCal",
            "preview": "com.apple.Preview",
            "xcode": "com.apple.dt.Xcode",
        ]
        return wellKnown[name.lowercased()] ?? "com.apple.\(name)"
    }

    private func loadSDEFFromBundle(_ appPath: String) throws -> Data? {
        let bundle = Bundle(path: appPath)
        if let sdefURL = bundle?.url(forResource: nil, withExtension: "sdef") {
            return try Data(contentsOf: sdefURL)
        }
        // Check inside Resources
        let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcesPath) {
            for file in contents where file.hasSuffix(".sdef") {
                let url = URL(fileURLWithPath: resourcesPath).appendingPathComponent(file)
                return try Data(contentsOf: url)
            }
        }
        return nil
    }

    private func loadSDEFViaCommand(_ appPath: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sdef")
        process.arguments = [appPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, !data.isEmpty else {
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AEQueryError.sdefLoadFailed(appPath, errStr)
        }
        return data
    }
}

public enum SDEFParserError: Error, LocalizedError {
    case invalidXML
    case missingAttribute(String)

    public var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "Invalid SDEF XML"
        case .missingAttribute(let attr):
            return "Missing attribute: \(attr)"
        }
    }
}
