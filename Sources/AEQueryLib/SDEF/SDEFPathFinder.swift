import Foundation

public struct PathStep {
    public enum Kind: Equatable { case element, property }
    public let name: String       // plural for elements, property name for properties
    public let className: String  // the SDEF class this step refers to
    public let kind: Kind
}

public struct FoundPath {
    public let steps: [PathStep]

    public var expression: String {
        steps.map(\.name).joined(separator: "/")
    }
}

public struct SDEFPathFinder {
    private let dictionary: ScriptingDictionary
    private let reverseIndex: [String: [ContainmentEntry]]  // lowercased class name → containers

    public init(dictionary: ScriptingDictionary) {
        self.dictionary = dictionary
        self.reverseIndex = SDEFPathFinder.buildReverseIndex(dictionary: dictionary)
    }

    /// Find all valid paths from the application root to a target class or property.
    /// Tries class lookup first (singular and plural), then property lookup.
    /// Returns paths sorted shortest-first.
    public func findPaths(to target: String, maxDepth: Int = 8) -> [FoundPath] {
        let lower = target.lowercased()

        // Special case: application is the root
        if let cls = dictionary.findClass(lower), cls.name.lowercased() == "application" {
            return [FoundPath(steps: [])]
        }

        // Try as class first (singular or plural)
        if let cls = dictionary.findClass(lower) {
            return findPathsToClass(cls.name.lowercased(), maxDepth: maxDepth)
        }

        // Try as property
        let propertyPaths = findPathsToProperty(named: lower, maxDepth: maxDepth)
        if !propertyPaths.isEmpty {
            return propertyPaths
        }

        return []
    }

    // MARK: - Reverse Index

    private struct ContainmentEntry {
        let containerClassName: String  // the class that contains the target
        let stepName: String            // name for the path step
        let kind: PathStep.Kind
    }

    private static func buildReverseIndex(dictionary: ScriptingDictionary) -> [String: [ContainmentEntry]] {
        var index: [String: [ContainmentEntry]] = [:]

        for classDef in dictionary.classes.values {
            let allElems = dictionary.allElements(for: classDef)
            for elem in allElems {
                guard let elemClass = dictionary.findClass(elem.type) else { continue }
                let key = elemClass.name.lowercased()
                let stepName = elemClass.pluralName ?? elemClass.name
                let entry = ContainmentEntry(
                    containerClassName: classDef.name.lowercased(),
                    stepName: stepName,
                    kind: .element
                )
                // Deduplicate: don't add if same container+kind already present
                if let existing = index[key] {
                    if existing.contains(where: { $0.containerClassName == entry.containerClassName && $0.kind == entry.kind }) {
                        continue
                    }
                }
                index[key, default: []].append(entry)
            }

            let allProps = dictionary.allProperties(for: classDef)
            for prop in allProps {
                guard let propType = prop.type,
                      dictionary.findClass(propType) != nil else { continue }
                let key = propType.lowercased()
                let entry = ContainmentEntry(
                    containerClassName: classDef.name.lowercased(),
                    stepName: prop.name,
                    kind: .property
                )
                if let existing = index[key] {
                    if existing.contains(where: { $0.containerClassName == entry.containerClassName && $0.stepName == entry.stepName && $0.kind == entry.kind }) {
                        continue
                    }
                }
                index[key, default: []].append(entry)
            }
        }

        return index
    }

    // MARK: - Backward Search

    /// Find all paths from application root to a class.
    private func findPathsToClass(_ targetLower: String, maxDepth: Int) -> [FoundPath] {
        var results: [FoundPath] = []
        walkBackward(target: targetLower, depth: maxDepth, visited: [], results: &results)
        // Sort shortest-first, then alphabetically for deterministic output
        results.sort {
            if $0.steps.count != $1.steps.count {
                return $0.steps.count < $1.steps.count
            }
            return $0.expression < $1.expression
        }
        // Deduplicate by expression
        var seen = Set<String>()
        results = results.filter { seen.insert($0.expression).inserted }
        return results
    }

    /// Recursive backward walk: from target, find what contains it, recurse toward "application".
    private func walkBackward(target: String, depth: Int, visited: Set<String>, results: inout [FoundPath]) {
        guard depth > 0 else { return }

        guard let entries = reverseIndex[target] else { return }

        // Include target in visited so no class appears twice in the same path
        // (collapses self-referential containment like folder→folder)
        var visited = visited
        visited.insert(target)

        for entry in entries {
            // Skip if we've already visited this container on this path
            if visited.contains(entry.containerClassName) { continue }

            let step = PathStep(
                name: entry.stepName,
                className: target,
                kind: entry.kind
            )

            if entry.containerClassName == "application" {
                // Base case: reached the root
                results.append(FoundPath(steps: [step]))
            } else {
                // Recurse: find paths to the container class
                var subResults: [FoundPath] = []
                walkBackward(target: entry.containerClassName, depth: depth - 1, visited: visited, results: &subResults)
                for sub in subResults {
                    results.append(FoundPath(steps: sub.steps + [step]))
                }
            }
        }
    }

    /// Find all paths to classes that declare a property with the given name,
    /// then append the property step.
    private func findPathsToProperty(named propertyName: String, maxDepth: Int) -> [FoundPath] {
        let lower = propertyName.lowercased()
        var results: [FoundPath] = []

        // Find all classes that directly declare this property
        for classDef in dictionary.classes.values {
            let allProps = dictionary.allProperties(for: classDef)
            guard allProps.contains(where: { $0.name.lowercased() == lower }) else { continue }

            let propStep = PathStep(
                name: propertyName,
                className: classDef.name,
                kind: .property
            )

            if classDef.name.lowercased() == "application" {
                // Property directly on application
                results.append(FoundPath(steps: [propStep]))
            } else {
                // Find paths to this class, then append the property step
                let classPaths = findPathsToClass(classDef.name.lowercased(), maxDepth: maxDepth - 1)
                for path in classPaths {
                    results.append(FoundPath(steps: path.steps + [propStep]))
                }
            }
        }

        // Sort and deduplicate
        results.sort {
            if $0.steps.count != $1.steps.count {
                return $0.steps.count < $1.steps.count
            }
            return $0.expression < $1.expression
        }
        var seen = Set<String>()
        results = results.filter { seen.insert($0.expression).inserted }
        return results
    }
}
