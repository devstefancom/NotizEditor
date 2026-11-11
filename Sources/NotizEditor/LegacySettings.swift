import Foundation

/// Version 1.0.0 had another bundle identifier, so macOS kept its settings in another file. The first start with
/// the current identifier takes them over once (notes folder, font, open files …), so nothing seems reset after
/// the update. The earlier identifier is not spelled out here: its file is found by the ending ".notizeditor.plist".
enum LegacySettings {
    static let doneKey = "settingsTakenOver"

    /// The settings file of the earlier identifier in `folder` (~/Library/Preferences), if there is one.
    static func oldFile(in folder: URL, ownID: String) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        func modified(_ url: URL) -> Date {
            ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
        }
        return names.filter { $0.hasSuffix(".notizeditor.plist") && $0 != ownID + ".plist" }
            .map { folder.appendingPathComponent($0) }
            .max { modified($0) < modified($1) }
    }

    /// Copies the old settings into `defaults` – once, and only if `defaults` has no settings of its own yet.
    /// Returns true if something was taken over.
    @discardableResult
    static func takeOver(into defaults: UserDefaults, ownID: String, folder: URL) -> Bool {
        // Only the app itself, not test builds with their own identifier ("….notizeditor.selftest").
        guard ownID.hasSuffix(".notizeditor"), !defaults.bool(forKey: doneKey) else { return false }
        defaults.set(true, forKey: doneKey)
        guard defaults.object(forKey: "notesFolder") == nil,
              let file = oldFile(in: folder, ownID: ownID),
              let old = NSDictionary(contentsOf: file) as? [String: Any] else { return false }
        for (key, value) in old where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        return true
    }
}
