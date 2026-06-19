import Testing
@testable import AEQueryLib

/// These tests load the real macOS system SDEF files, so they assert against
/// types AppleScript has shipped for many OS releases.
struct SystemTypeRegistryTests {
    @Test func testLoadsSystemTypes() {
        let registry = SystemTypeRegistry()
        #expect(!registry.typeNames.isEmpty)
    }

    @Test func testCoreValueTypes() {
        let registry = SystemTypeRegistry()
        // From Foundation's Intrinsics.sdef.
        #expect(registry.isSystemType("integer"))
        #expect(registry.isSystemType("text"))
        #expect(registry.isSystemType("record"))
    }

    @Test func testStandardSuiteTypes() {
        let registry = SystemTypeRegistry()
        // From CocoaStandard.sdef.
        #expect(registry.isSystemType("print settings"))
        #expect(registry.isSystemType("save options"))
    }

    @Test func testLegacyCompatibilityTypes() {
        let registry = SystemTypeRegistry()
        // From OpenScripting's Compatibility.sdef — the types that previously
        // triggered the "May be a system-defined type" guess.
        #expect(registry.isSystemType("double integer"))
        #expect(registry.isSystemType("picture"))
        #expect(registry.isSystemType("RGB color"))
        #expect(registry.isSystemType("list"))
    }

    @Test func testCaseInsensitive() {
        let registry = SystemTypeRegistry()
        #expect(registry.isSystemType("PICTURE"))
        #expect(registry.isSystemType("Double Integer"))
    }

    @Test func testUnknownTypeNotSystem() {
        let registry = SystemTypeRegistry()
        #expect(!registry.isSystemType("totally made up type"))
        // App-specific types (not in the canonical system files) are not system types.
        #expect(!registry.isSystemType("saveable file format"))
    }

    @Test func testMissingPathsSkippedGracefully() {
        let registry = SystemTypeRegistry(paths: ["/no/such/file.sdef"])
        #expect(registry.typeNames.isEmpty)
        #expect(!registry.isSystemType("integer"))
    }
}
