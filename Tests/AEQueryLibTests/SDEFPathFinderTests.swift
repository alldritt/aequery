import Testing
@testable import AEQueryLib

@Suite("SDEFPathFinder")
struct SDEFPathFinderTests {
    // Extended fixture SDEF with:
    // - application with windows, documents, files, folders, accounts
    // - window with documents (multiple paths to document)
    // - folder self-referential (folder contains folders) + files
    // - account/mailbox/message chain with sender property
    // - item base class for inheritance (file inherits item)
    // - track class with artist property, player class with "current track" property of type track
    private let sdef = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
    <dictionary>
        <suite name="Standard Suite" code="core">
            <class name="application" code="capp" plural="applications">
                <property name="name" code="pnam" type="text"/>
                <element type="window"/>
                <element type="document"/>
                <element type="file"/>
                <element type="folder"/>
                <element type="account"/>
                <element type="player"/>
            </class>
            <class name="window" code="cwin" plural="windows">
                <property name="name" code="pnam" type="text"/>
                <property name="index" code="pidx" type="integer"/>
                <element type="document"/>
            </class>
            <class name="document" code="docu" plural="documents">
                <property name="name" code="pnam" type="text"/>
                <property name="path" code="ppth" type="text"/>
            </class>
            <class name="item" code="cobj">
                <property name="name" code="pnam" type="text"/>
                <property name="id" code="ID  " type="integer"/>
            </class>
            <class name="file" code="file" plural="files" inherits="item">
                <property name="size" code="ptsz" type="integer"/>
            </class>
            <class name="folder" code="cfol" plural="folders">
                <property name="name" code="pnam" type="text"/>
                <element type="folder"/>
                <element type="file"/>
            </class>
            <class name="account" code="mact" plural="accounts">
                <property name="name" code="pnam" type="text"/>
                <element type="mailbox"/>
            </class>
            <class name="mailbox" code="mbxp" plural="mailboxes">
                <property name="name" code="pnam" type="text"/>
                <element type="message"/>
            </class>
            <class name="message" code="mssg" plural="messages">
                <property name="name" code="pnam" type="text"/>
                <property name="sender" code="sndr" type="text"/>
            </class>
            <class name="track" code="cTrk" plural="tracks">
                <property name="name" code="pnam" type="text"/>
                <property name="artist" code="pArt" type="text"/>
            </class>
            <class name="player" code="cPly" plural="players">
                <property name="name" code="pnam" type="text"/>
                <property name="current track" code="pTrk" type="track"/>
            </class>
        </suite>
    </dictionary>
    """

    private func makeFinder() throws -> SDEFPathFinder {
        let dict = try SDEFParser().parse(xmlString: sdef)
        return SDEFPathFinder(dictionary: dict)
    }

    @Test func testDirectElement() throws {
        let finder = try makeFinder()
        let paths = finder.findPaths(to: "window")
        #expect(paths.count == 1)
        #expect(paths[0].expression == "windows")
        #expect(paths[0].steps[0].kind == .element)
    }

    @Test func testMultiplePaths() throws {
        let finder = try makeFinder()
        let paths = finder.findPaths(to: "document")
        // document is reachable via application directly AND via windows
        #expect(paths.count == 2)
        let expressions = paths.map(\.expression)
        #expect(expressions.contains("documents"))
        #expect(expressions.contains("windows/documents"))
    }

    @Test func testCycleDefense() throws {
        let finder = try makeFinder()
        // folder contains folders — should not loop infinitely
        // Self-referential containment is collapsed: each class appears at most once per path
        let paths = finder.findPaths(to: "folder")
        #expect(!paths.isEmpty)
        let expressions = paths.map(\.expression)
        #expect(expressions.contains("folders"))
        // folders/folders should NOT appear (self-referential paths are collapsed)
        #expect(!expressions.contains("folders/folders"))
    }

    @Test func testPropertyTarget() throws {
        let finder = try makeFinder()
        let paths = finder.findPaths(to: "sender")
        #expect(!paths.isEmpty)
        // sender is on message, message is in mailbox, mailbox is in account, account is in application
        let expressions = paths.map(\.expression)
        #expect(expressions.contains("accounts/mailboxes/messages/sender"))
    }

    @Test func testPluralNameLookup() throws {
        let finder = try makeFinder()
        let pathsSingular = finder.findPaths(to: "window")
        let pathsPlural = finder.findPaths(to: "windows")
        #expect(pathsSingular.map(\.expression) == pathsPlural.map(\.expression))
    }

    @Test func testNoPathFound() throws {
        let finder = try makeFinder()
        let paths = finder.findPaths(to: "nonexistent")
        #expect(paths.isEmpty)
    }

    @Test func testInheritedContainment() throws {
        let finder = try makeFinder()
        // file is reachable through application directly, and through folder (folder has element type="file")
        let paths = finder.findPaths(to: "file")
        let expressions = paths.map(\.expression)
        #expect(expressions.contains("files"))
        #expect(expressions.contains("folders/files"))
    }

    @Test func testDepthLimit() throws {
        let finder = try makeFinder()
        // maxDepth=1 only returns direct children of application
        let paths = finder.findPaths(to: "document", maxDepth: 1)
        let expressions = paths.map(\.expression)
        #expect(expressions.contains("documents"))
        // windows/documents requires depth 2, so should NOT appear
        #expect(!expressions.contains("windows/documents"))
    }

    @Test func testPropertyTypedClassTraversal() throws {
        let finder = try makeFinder()
        // "artist" is a property on track. track is reachable via "current track" property on player.
        // player is an element of application.
        let paths = finder.findPaths(to: "artist")
        let expressions = paths.map(\.expression)
        #expect(expressions.contains("players/current track/artist"))
    }

    @Test func testApplicationAsTarget() throws {
        let finder = try makeFinder()
        let paths = finder.findPaths(to: "application")
        // application is the root — no path needed (empty steps)
        #expect(paths.count == 1)
        #expect(paths[0].steps.isEmpty)
        #expect(paths[0].expression == "")
    }
}
