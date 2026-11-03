import AppKit

// Your own scripts (any language: zsh, Python, Ruby, …) in the Scripts menu. A script gets the selected text
// (or the whole note) on standard input; what it prints replaces the selection. Comment lines at the top
// can change that:
//   # input: selection | document | none
//   # output: replace-selection | replace-document | insert | new-note | none

enum Scripts {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotizEditor/Scripts", isDirectory: true)
    }

    static func list() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return items.filter { !AppModel.isFolder($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func title(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    @MainActor
    static func openFolder() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            installExamples()
        }
        NSWorkspace.shared.open(folder)
    }

    private static func installExamples() {
        let examples: [(String, String)] = [
            (L("Insert Date") + ".sh", """
            #!/bin/zsh
            # \(L("Inserts today's date at the insertion point."))
            # input: none
            # output: insert
            date "+%d.%m.%Y" | tr -d '\\n'
            """),
            (L("Number Lines") + ".sh", """
            #!/bin/zsh
            # \(L("Numbers the selected lines (or all lines of the note)."))
            # input: selection
            # output: replace-selection
            awk '{ printf "%d. %s\\n", NR, $0 }'
            """),
            (L("Format JSON") + ".sh", """
            #!/bin/zsh
            # \(L("Formats JSON readably (selection or whole note)."))
            # input: selection
            # output: replace-selection
            plutil -convert json -r -o - -
            """),
        ]
        for (name, script) in examples {
            let url = folder.appendingPathComponent(name)
            try? (script + "\n").write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    private static func directive(_ key: String, in script: URL) -> String? {
        guard let text = try? String(contentsOf: script, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix("--") else { continue }
            if let range = trimmed.range(of: #"(?i)\b"# + key + #"\s*:\s*([\w-]+)"#, options: .regularExpression) {
                return trimmed[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces).lowercased()
            }
        }
        return nil
    }

    @MainActor
    static func run(_ script: URL, model: AppModel) {
        guard let textView = model.textView, let document = model.document else { NSSound.beep(); return }
        let string = textView.string as NSString
        let input = directive("input", in: script) ?? "selection"
        var output = directive("output", in: script) ?? "replace-selection"
        var range = textView.selectedRange()
        if input == "document" || (input == "selection" && range.length == 0) {
            range = NSRange(location: 0, length: string.length)
            if output == "replace-selection" { output = "replace-document" }
        }
        let text = input == "none" ? "" : string.substring(with: range)

        let process = Process()
        if FileManager.default.isExecutableFile(atPath: script.path) {
            process.executableURL = script
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path]
        }
        var environment = ProcessInfo.processInfo.environment
        environment["NOTIZEDITOR_FILE"] = document.url.path
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        process.currentDirectoryURL = document.url.deletingLastPathComponent()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            var result = Data()
            do {
                try process.run()
                DispatchQueue.global().async {
                    stdin.fileHandleForWriting.write(Data(text.utf8))
                    try? stdin.fileHandleForWriting.close()
                }
                result = stdout.fileHandleForReading.readDataToEndOfFile()
                let errors = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    failure = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if failure!.isEmpty { failure = L("The script ended with error code %d.", Int(process.terminationStatus)) }
                }
            } catch {
                failure = error.localizedDescription
            }
            let failed = failure, printed = result
            Task { @MainActor in
                if let failure = failed {
                    let alert = NSAlert()
                    alert.messageText = L("The script “%@” failed.", title(script))
                    alert.informativeText = failure
                    alert.runModal()
                    return
                }
                var newText = String(decoding: printed, as: UTF8.self)
                if newText.hasSuffix("\n"), !text.hasSuffix("\n"), output.hasPrefix("replace") { newText.removeLast() }
                apply(newText, output: output, range: range, model: model, scriptName: title(script))
            }
        }
    }

    @MainActor
    private static func apply(_ text: String, output: String, range: NSRange, model: AppModel, scriptName: String) {
        guard let textView = model.textView else { return }
        switch output {
        case "replace-selection", "replace-document":
            textView.replace(range, with: text)
        case "insert":
            textView.replace(NSRange(location: NSMaxRange(textView.selectedRange()), length: 0), with: text, select: false)
        case "new-note":
            model.newNote(content: text, name: scriptName)
        default:
            break
        }
    }
}

/// The command `notizeditor` for the Terminal: a small script inside the app, linked into /usr/local/bin.
enum CommandLineTool {
    static let link = "/usr/local/bin/notizeditor"

    static var bundledScript: String {
        Bundle.main.resourceURL!.appendingPathComponent("bin/notizeditor").path
    }

    static var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == bundledScript
    }

    @MainActor
    static func install() {
        let script = bundledScript
        let fileManager = FileManager.default
        // Without asking if the folder is writable (e.g. with Homebrew on Intel Macs).
        if fileManager.isWritableFile(atPath: "/usr/local/bin") {
            try? fileManager.removeItem(atPath: link)
            if (try? fileManager.createSymbolicLink(atPath: link, withDestinationPath: script)) != nil {
                done()
                return
            }
        }
        let command = "mkdir -p /usr/local/bin && ln -sf '\(script)' '\(link)'"
        var error: NSDictionary?
        let apple = NSAppleScript(source: "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges")
        apple?.executeAndReturnError(&error)
        if error == nil, isInstalled {
            done()
            return
        }
        if (error?[NSAppleScript.errorNumber] as? Int) == -128 { return }   // cancelled
        let alert = NSAlert()
        alert.messageText = L("The command couldn't be installed automatically.")
        alert.informativeText = L("Copy this command and run it in the Terminal:") + "\n\nsudo " + command
        alert.addButton(withTitle: L("Copy Command"))
        alert.addButton(withTitle: L("Close"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("sudo " + command, forType: .string)
        }
    }

    @MainActor
    private static func done() {
        let alert = NSAlert()
        alert.messageText = L("The command “notizeditor” is installed.")
        alert.informativeText = L("In the Terminal: notizeditor file.txt – or: echo Hello | notizeditor")
        alert.runModal()
    }
}
