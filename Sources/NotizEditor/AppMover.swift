import AppKit
import Darwin

/// Offers to move the app into the Applications folder when it is started from the disk image or from Downloads –
/// started from there, macOS may forget granted permissions (e.g. screen recording). Builds anywhere else (developer
/// builds in the project folder) are left alone.
@MainActor
enum AppMover {
    private static let suppressKey = "moveToApplicationsSuppressed"

    /// Returns true if the app is being moved and relaunched from the Applications folder; the caller stops launching.
    static func offerMoveIfNeeded() -> Bool {
        let fileManager = FileManager.default
        let running = Bundle.main.bundleURL
        let source = originalURL(of: running)
        let path = source.resolvingSymlinksInPath().path
        let home = fileManager.homeDirectoryForCurrentUser.path
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") { return false }
        let fromDiskImage = path.hasPrefix("/Volumes/")
        let fromDownloads = path.hasPrefix(home + "/Downloads/")
        let translocated = source != running   // quarantined download started in place
        guard fromDiskImage || fromDownloads || translocated,
              !UserDefaults.standard.bool(forKey: suppressKey) else { return false }

        let name = running.deletingPathExtension().lastPathComponent
        let alert = NSAlert()
        alert.messageText = L("Move %@ to the Applications folder?", name)
        alert.informativeText = L("Apps belong in the Applications folder. Started from the download or the disk image, macOS may forget permissions you have granted.")
        alert.addButton(withTitle: L("Move to Applications"))
        alert.addButton(withTitle: L("Don't Move"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("Don't ask again")
        NSApp.activate(ignoringOtherApps: true)
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: suppressKey) }
        guard answer == .alertFirstButtonReturn else { return false }

        let destination = URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(running.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                // An older copy is already there and may be running.
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                where app.bundleURL?.standardizedFileURL == destination.standardizedFileURL {
                    app.terminate()
                }
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            }
            try fileManager.copyItem(at: running, to: destination)
        } catch {
            let failed = NSAlert()
            failed.alertStyle = .warning
            failed.messageText = L("Couldn't move %@", name)
            failed.informativeText = L("Please drag %@ into the Applications folder yourself.", name) + "\n\n" + error.localizedDescription
            failed.runModal()
            return false
        }
        if fromDownloads { try? fileManager.trashItem(at: source, resultingItemURL: nil) }
        let volume = fromDiskImage ? "/" + path.split(separator: "/").prefix(2).joined(separator: "/") : nil
        relaunch(destination, detaching: volume)
        return true
    }

    /// Starts the moved copy as soon as this process has quit, and ejects the disk image it came from.
    private static func relaunch(_ app: URL, detaching volume: String?) {
        let pid = ProcessInfo.processInfo.processIdentifier
        var script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\""
        if volume != nil { script += "; /usr/bin/hdiutil detach \"$1\" -quiet" }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, app.path] + (volume.map { [$0] } ?? [])
        try? task.run()
        NSApp.terminate(nil)
    }

    /// A quarantined app started from Downloads runs from a randomised read-only copy (App Translocation).
    /// Returns where it really lies, so it can be moved away from there.
    private static func originalURL(of url: URL) -> URL {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return url }
        var translocated = false
        guard unsafeBitCast(isSymbol, to: IsTranslocated.self)(url as CFURL, &translocated, nil), translocated,
              let original = unsafeBitCast(originalSymbol, to: OriginalPath.self)(url as CFURL, nil) else { return url }
        return original.takeRetainedValue() as URL
    }
}
