import Foundation

public struct AppleEventSender {
    public init() {}

    /// Send a 'get' Apple Event for the given object specifier to the target app.
    public func sendGetEvent(to appName: String, specifier: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let bundleID = try resolveBundleIdentifier(appName)
        let targetApp = NSAppleEventDescriptor(bundleIdentifier: bundleID)

        // Build core/getd event
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEConstants.kAECoreSuite,
            eventID: AEConstants.kAEGetData,
            targetDescriptor: targetApp,
            returnID: -1,  // kAutoGenerateReturnID
            transactionID: 0  // kAnyTransactionID
        )

        // Set the direct object to our specifier
        event.setParam(specifier, forKeyword: AEConstants.keyDirectObject)

        // Send the event via AESendMessage for reliable delivery
        let reply: NSAppleEventDescriptor
        var replyEvent = AppleEvent()
        let aeDesc = event.aeDesc!.pointee
        var mutableDesc = aeDesc
        let err = AESendMessage(&mutableDesc, &replyEvent, AESendMode(kAEWaitReply), 30 * 60)
        guard err == noErr else {
            throw AEQueryError.appleEventFailed(Int(err), "AESendMessage failed with OSStatus \(err)")
        }
        reply = NSAppleEventDescriptor(aeDescNoCopy: &replyEvent)

        // Extract the direct object from the reply
        // The reply is an Apple Event; the result is in the '----' parameter
        if let result = reply.paramDescriptor(forKeyword: AEKeyword(AEConstants.keyDirectObject)) {
            return result
        }

        // Try extracting using the raw keyword value for '----'
        let keyDirect: AEKeyword = 0x2D2D2D2D  // '----'
        if let result = reply.paramDescriptor(forKeyword: keyDirect) {
            return result
        }

        // Check if reply has numbered descriptors (list-like)
        if reply.numberOfItems > 0 {
            if let first = reply.atIndex(1) {
                // If there's only one item and it looks like a result, return it
                if reply.numberOfItems == 1 {
                    return first
                }
            }
            return reply
        }

        // Check for error in reply
        let errKeyword: AEKeyword = 0x65727270  // 'errn'
        if let errDesc = reply.paramDescriptor(forKeyword: errKeyword) {
            let errNum = Int(errDesc.int32Value)
            let errMsg = reply.paramDescriptor(forKeyword: 0x65727273)?.stringValue ?? "Unknown error"  // 'errs'
            throw AEQueryError.appleEventFailed(errNum, errMsg)
        }

        // If no direct object, the reply itself might be the result
        return reply
    }

    private func resolveBundleIdentifier(_ appName: String) throws -> String {
        // Common well-known bundle IDs
        let wellKnown: [String: String] = [
            "finder": "com.apple.finder",
            "safari": "com.apple.Safari",
            "textedit": "com.apple.TextEdit",
            "mail": "com.apple.mail",
            "music": "com.apple.Music",
            "system events": "com.apple.systemevents",
            "system preferences": "com.apple.systempreferences",
            "system settings": "com.apple.systempreferences",
            "terminal": "com.apple.Terminal",
            "notes": "com.apple.Notes",
            "calendar": "com.apple.iCal",
            "reminders": "com.apple.reminders",
            "preview": "com.apple.Preview",
            "pages": "com.apple.iWork.Pages",
            "numbers": "com.apple.iWork.Numbers",
            "keynote": "com.apple.iWork.Keynote",
            "xcode": "com.apple.dt.Xcode",
        ]

        let lower = appName.lowercased()
        if let bundleID = wellKnown[lower] {
            return bundleID
        }

        // Try to find the app by path and read its bundle ID
        let candidates = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            "/Applications/Utilities/\(appName).app",
        ]
        for path in candidates {
            if let bundle = Bundle(path: path),
               let bundleID = bundle.bundleIdentifier {
                return bundleID
            }
        }

        // As a last resort, try using the name as a bundle ID
        if appName.contains(".") {
            return appName
        }

        throw AEQueryError.appNotFound(appName)
    }
}
