import AppKit
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

            // Evaluate the xpointer attribute to select the right nodes from the
            // included document. The xpointer contains an XPath expression, e.g.:
            //   Bike:     xpointer(/dictionary/suite)         → import whole suites
            //   Contacts: xpointer(/dictionary/suite/node()…) → import suite children
            var nodesToInsert: [XMLNode] = []
            if let xpointer = includeElement.attribute(forName: "xpointer")?.stringValue,
               let xpath = extractXPath(from: xpointer),
               let nodes = try? includedDoc.nodes(forXPath: xpath),
               !nodes.isEmpty {
                nodesToInsert = nodes
            } else if parent?.name == "dictionary" {
                // Fallback: include at dictionary level → import whole suites
                if let suites = try? includedDoc.nodes(forXPath: "/dictionary/suite") {
                    nodesToInsert = suites
                }
            } else {
                // Fallback: include inside a suite → import suite children
                if let children = try? includedDoc.nodes(forXPath: "/dictionary/suite/*") {
                    nodesToInsert = children
                }
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

    /// Extract the XPath expression from an xpointer value like "xpointer(/dictionary/suite)".
    private func extractXPath(from xpointer: String) -> String? {
        let prefix = "xpointer("
        let suffix = ")"
        guard xpointer.hasPrefix(prefix), xpointer.hasSuffix(suffix) else { return nil }
        let start = xpointer.index(xpointer.startIndex, offsetBy: prefix.count)
        let end = xpointer.index(xpointer.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return String(xpointer[start..<end])
    }

    public func parse(xmlString: String) throws -> ScriptingDictionary {
        guard let data = xmlString.data(using: .utf8) else {
            throw SDEFParserError.invalidXML
        }
        return try parse(data: data)
    }

    private func parseSuite(_ suite: XMLElement, into dictionary: inout ScriptingDictionary) throws {
        let suiteName = suite.attribute(forName: "name")?.stringValue
        if let suiteName = suiteName {
            dictionary.suiteNames.append(suiteName)
        }

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

        // Parse commands
        for node in try suite.nodes(forXPath: "command") {
            guard let element = node as? XMLElement else { continue }
            let commandDef = parseCommand(element, suiteName: suiteName)
            dictionary.commands[commandDef.name.lowercased()] = commandDef
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
        let description = element.attribute(forName: "description")?.stringValue
        let properties = parseProperties(element)
        let elements = parseElements(element)

        return ClassDef(
            name: name,
            code: code,
            pluralName: plural,
            inherits: inherits,
            hidden: hidden,
            description: description,
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
            let type = resolveType(from: propElement)
            let accessStr = propElement.attribute(forName: "access")?.stringValue
            let access = accessStr.flatMap { PropertyAccess(rawValue: $0) }
            let hidden = propElement.attribute(forName: "hidden")?.stringValue == "yes"
            let description = propElement.attribute(forName: "description")?.stringValue
            props.append(PropertyDef(name: name, code: code, type: type, access: access, hidden: hidden, description: description))
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

    /// Resolve the type for a property, parameter, or result element.
    /// Checks the `type` attribute first, then falls back to nested `<type>` child elements.
    private func resolveType(from element: XMLElement) -> String? {
        // Prefer the inline type attribute
        if let type = element.attribute(forName: "type")?.stringValue {
            return type
        }
        // Fall back to nested <type> child elements
        guard let typeNodes = try? element.nodes(forXPath: "type"),
              !typeNodes.isEmpty else { return nil }
        var types: [String] = []
        for node in typeNodes {
            guard let typeElement = node as? XMLElement,
                  typeElement.attribute(forName: "hidden")?.stringValue != "yes",
                  let typeName = typeElement.attribute(forName: "type")?.stringValue,
                  typeName != "missing value" else { continue }
            let isList = typeElement.attribute(forName: "list")?.stringValue == "yes"
            types.append(isList ? "list of \(typeName)" : typeName)
        }
        return types.isEmpty ? nil : types.joined(separator: " / ")
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

    private func parseCommand(_ element: XMLElement, suiteName: String?) -> CommandDef {
        let name = element.attribute(forName: "name")?.stringValue ?? ""
        let code = element.attribute(forName: "code")?.stringValue ?? ""
        let description = element.attribute(forName: "description")?.stringValue
        let hidden = element.attribute(forName: "hidden")?.stringValue == "yes"

        // Parse direct-parameter
        var directParam: CommandParam? = nil
        if let dpNode = (try? element.nodes(forXPath: "direct-parameter"))?.first as? XMLElement {
            let dpType = resolveType(from: dpNode)
            let dpOptional = dpNode.attribute(forName: "optional")?.stringValue == "yes"
            let dpDesc = dpNode.attribute(forName: "description")?.stringValue
            directParam = CommandParam(type: dpType, optional: dpOptional, description: dpDesc)
        }

        // Parse parameters
        var params: [CommandParam] = []
        for node in (try? element.nodes(forXPath: "parameter")) ?? [] {
            guard let paramElement = node as? XMLElement else { continue }
            let pName = paramElement.attribute(forName: "name")?.stringValue
            let pCode = paramElement.attribute(forName: "code")?.stringValue
            let pType = resolveType(from: paramElement)
            let pOptional = paramElement.attribute(forName: "optional")?.stringValue == "yes"
            let pDesc = paramElement.attribute(forName: "description")?.stringValue
            params.append(CommandParam(name: pName, code: pCode, type: pType, optional: pOptional, description: pDesc))
        }

        // Parse result
        var result: CommandResult? = nil
        if let resNode = (try? element.nodes(forXPath: "result"))?.first as? XMLElement {
            let resType = resolveType(from: resNode)
            let resDesc = resNode.attribute(forName: "description")?.stringValue
            result = CommandResult(type: resType, description: resDesc)
        }

        return CommandDef(
            name: name,
            code: code,
            description: description,
            hidden: hidden,
            directParameter: directParam,
            parameters: params,
            result: result,
            suiteName: suiteName
        )
    }
}

/// Load SDEF from an application
public struct SDEFLoader {
    public init() {}

    public func loadSDEF(forApp appName: String) throws -> (ScriptingDictionary, String) {
        let appPath = try resolveAppPath(appName)

        // Prefer /usr/bin/sdef which merges the system Standard Suite definitions
        // (e.g. the "item" class with "class", "properties" etc.) into the result.
        if let sdefData = try? loadSDEFViaCommand(appPath) {
            return (try SDEFParser().parse(data: sdefData), appPath)
        }

        // Fall back to reading .sdef directly from the bundle
        if let sdefData = try? loadSDEFFromBundle(appPath) {
            return (try SDEFParser().parse(data: sdefData), appPath)
        }

        throw AEQueryError.sdefLoadFailed(appPath, "No SDEF found")
    }

    private func resolveAppPath(_ appName: String) throws -> String {
        // Check if the app is currently running and use that bundle path
        let running = findRunningApp(named: appName)
        if let running = running, let bundleURL = running.bundleURL {
            return bundleURL.path
        }

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
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        process.waitUntilExit()
        if !output.isEmpty, let first = output.components(separatedBy: "\n").first,
           FileManager.default.fileExists(atPath: first) {
            return first
        }

        throw AEQueryError.appNotFound(appName)
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
        // Read pipes before waitUntilExit to avoid deadlock when output exceeds pipe buffer
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            let errStr = String(data: errData, encoding: .utf8) ?? ""
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
