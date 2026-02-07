import AppKit

/// Find a running application by name, matching case-insensitively against
/// both the localized display name and the bundle filename.
func findRunningApp(named appName: String) -> NSRunningApplication? {
    let lower = appName.lowercased()
    return NSWorkspace.shared.runningApplications.first { app in
        if app.localizedName?.lowercased() == lower { return true }
        if let bundleURL = app.bundleURL {
            let bundleName = bundleURL.deletingPathExtension().lastPathComponent
            if bundleName.lowercased() == lower { return true }
        }
        return false
    }
}
