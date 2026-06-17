import Testing
@testable import AEQueryLib

@Suite("Composite type names")
struct CompositeTypeNameTests {
    @Test("Plain type returns itself")
    func plainType() {
        #expect(ScriptingDictionary.componentTypeNames(of: "text") == ["text"])
    }

    @Test("`list of X` strips the prefix")
    func listOf() {
        #expect(ScriptingDictionary.componentTypeNames(of: "list of paragraph") == ["paragraph"])
        #expect(ScriptingDictionary.componentTypeNames(of: "List Of Paragraph") == ["Paragraph"])
    }

    @Test("Pipe-separated unions split into components")
    func pipeUnion() {
        #expect(ScriptingDictionary.componentTypeNames(of: "color | gradient") == ["color", "gradient"])
    }

    @Test("Slash-separated unions split into components")
    func slashUnion() {
        #expect(ScriptingDictionary.componentTypeNames(of: "page / section") == ["page", "section"])
        #expect(ScriptingDictionary.componentTypeNames(of: "page/section") == ["page", "section"])
    }

    @Test("Union of list types strips each prefix")
    func listUnion() {
        #expect(ScriptingDictionary.componentTypeNames(of: "list of text | list of file") == ["text", "file"])
    }

    @Test("Multi-word base types are preserved")
    func multiWord() {
        #expect(ScriptingDictionary.componentTypeNames(of: "list of rgb color") == ["rgb color"])
    }

    @Test("isListType detection")
    func listDetection() {
        #expect(ScriptingDictionary.isListType("list of paragraph"))
        #expect(ScriptingDictionary.isListType("list of text | list of file"))
        #expect(!ScriptingDictionary.isListType("paragraph"))
        #expect(!ScriptingDictionary.isListType("list"))
    }
}
