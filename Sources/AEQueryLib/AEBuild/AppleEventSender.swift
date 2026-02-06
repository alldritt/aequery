import AppKit
import Foundation

public struct AppleEventSender {
    public init() {}

    /// Resolve the bundle identifier for an app name.
    public func bundleIdentifier(for appName: String) throws -> String {
        try resolveBundleIdentifier(appName)
    }

    /// Send a 'get' Apple Event for the given object specifier to the target app.
    /// - Parameter timeoutSeconds: Timeout in seconds (default 120). Use -1 for no timeout, -2 for system default.
    public func sendGetEvent(to appName: String, specifier: NSAppleEventDescriptor, timeoutSeconds: Int = 120, verbose: Bool = false) throws -> NSAppleEventDescriptor {
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
        let timeoutTicks = timeoutSeconds < 0 ? timeoutSeconds : timeoutSeconds * 60
        let err = AESendMessage(&mutableDesc, &replyEvent, AESendMode(kAEWaitReply), Int(timeoutTicks))

        if verbose {
            FileHandle.standardError.write(Data("AESendMessage returned: \(err)\n".utf8))
        }

        guard err == noErr else {
            throw AEQueryError.appleEventFailed(Int(err), "", nil)
        }
        reply = NSAppleEventDescriptor(aeDescNoCopy: &replyEvent)

        if verbose {
            FileHandle.standardError.write(Data("Reply descriptor: \(reply)\n".utf8))
        }

        // Extract the direct object from the reply
        // The reply is an Apple Event; the result is in the '----' parameter
        if let result = reply.paramDescriptor(forKeyword: AEKeyword(AEConstants.keyDirectObject)) {
            return result
        }

        // Check for error in reply before any fallbacks
        let errKeyword: AEKeyword = 0x6572726E  // 'errn'
        if let errDesc = reply.paramDescriptor(forKeyword: errKeyword) {
            let errNum = Int(errDesc.int32Value)
            let errMsg = reply.paramDescriptor(forKeyword: 0x65727273)?.stringValue  // 'errs'

            // Extract offending object ('erob') if present
            let erobKeyword: AEKeyword = 0x65726F62  // 'erob'
            var offendingObject: AEValue? = nil
            if let erobDesc = reply.paramDescriptor(forKeyword: erobKeyword) {
                offendingObject = DescriptorDecoder().decode(erobDesc)
            }

            throw AEQueryError.appleEventFailed(errNum, errMsg ?? "", offendingObject)
        }

        // No direct object and no error — return null
        return NSAppleEventDescriptor.null()
    }

    private func resolveBundleIdentifier(_ appName: String) throws -> String {
        // Check running applications first
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
           let bundleID = running.bundleIdentifier {
            return bundleID
        }

        // Try to find the app by path and read its bundle ID
        let candidates = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            "/Applications/Utilities/\(appName).app",
            "/System/Library/CoreServices/\(appName).app",
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
