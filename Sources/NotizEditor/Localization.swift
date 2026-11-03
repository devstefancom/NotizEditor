import Foundation

/// Looks up an English key in Localizable.strings (German translation in de.lproj) and fills in %@ / %d arguments.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
}

/// 12345 -> "12,345" (English) or "12.345" (German).
func grouped(_ number: Int) -> String {
    number.formatted(.number.grouping(.automatic))
}
