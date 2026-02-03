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

    /// Number of property-typed steps among intermediate steps (all except last).
    /// Paths with 0 traverse the natural element containment hierarchy.
    /// Paths with >0 go through property shortcuts to specific instances.
    public var propertyIntermediateCount: Int {
        guard steps.count > 1 else { return 0 }
        return steps.dropLast().filter { $0.kind == .property }.count
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
            // Skip hidden classes entirely
            if classDef.hidden { continue }

            let allElems = dictionary.allElements(for: classDef)
            for elem in allElems {
                // Skip hidden elements
                if elem.hidden { continue }
                guard let elemClass = dictionary.findClass(elem.type) else { continue }
                // Skip if the target class is hidden
                if elemClass.hidden { continue }
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
                // Skip hidden properties
                if prop.hidden { continue }
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
        results = Self.sortAndDeduplicate(results)
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
            if classDef.hidden { continue }
            let allProps = dictionary.allProperties(for: classDef)
            guard allProps.contains(where: { $0.name.lowercased() == lower && !$0.hidden }) else { continue }

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

        results = Self.sortAndDeduplicate(results)
        return results
    }

    // MARK: - Sorting

    /// Sort by property intermediate count (element-only paths first),
    /// then by step count (shortest first), then alphabetically. Deduplicate by expression.
    private static func sortAndDeduplicate(_ paths: [FoundPath]) -> [FoundPath] {
        var results = paths
        results.sort {
            if $0.propertyIntermediateCount != $1.propertyIntermediateCount {
                return $0.propertyIntermediateCount < $1.propertyIntermediateCount
            }
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
