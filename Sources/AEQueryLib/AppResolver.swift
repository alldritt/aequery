import AppKit

/// Find a running application by name, matching case-insensitively against
/// both the localized display name and the bundle filename.
///
/// App extensions are skipped: they can share their host app's display name
/// (Messages runs "Messages Assistant Extension.appex", localized as
/// "Messages") but have no scripting dictionary and don't handle the app's
/// Apple Events. Among the remaining matches, an ordinary app wins over a
/// background one, so faceless scriptable apps are still found when they're
/// the only match.
func findRunningApp(named appName: String) -> NSRunningApplication? {
    let lower = appName.lowercased()
    let matches = NSWorkspace.shared.runningApplications.filter { app in
        if app.bundleURL?.pathExtension.lowercased() == "appex" { return false }
        if app.localizedName?.lowercased() == lower { return true }
        if let bundleURL = app.bundleURL {
            let bundleName = bundleURL.deletingPathExtension().lastPathComponent
            if bundleName.lowercased() == lower { return true }
        }
        return false
    }
    return matches.first { $0.activationPolicy == .regular } ?? matches.first
}
