import AppKit
import SwiftUI

// The help window – the same in every devstefan.com app; only HelpContent.swift differs.
// Topics on the left (with a search field), the chosen topic on the right: steps, tips and notes.
// It looks like the app itself: plain sidebar symbols, the app's accent colour, grey boxes – nothing colourful.

enum HelpStyle {
    static let accent = Color.accentColor
    static let box = Color.secondary.opacity(0.1)
}

/// A text in English and German; the app's language decides which one is shown.
struct HelpText: ExpressibleByStringLiteral {
    let en: String
    let de: String

    init(_ en: String, de: String) {
        self.en = en
        self.de = de
    }

    init(stringLiteral value: String) { self.init(value, de: value) }

    static var german: Bool { Bundle.main.preferredLocalizations.first == "de" }
    var text: String { Self.german ? de : en }
}

struct HelpTopic: Identifiable, Hashable {
    enum Block {
        case text(HelpText)
        case steps([HelpText])
        case tip(HelpText)
        case note(HelpText)
        case keys([(String, HelpText)])
    }

    let id: String
    let icon: String
    let title: HelpText
    let summary: HelpText
    let blocks: [Block]

    static func == (a: HelpTopic, b: HelpTopic) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Everything that can be found with the search field.
    var searchText: String {
        var parts = [title.text, summary.text]
        for block in blocks {
            switch block {
            case .text(let t), .tip(let t), .note(let t): parts.append(t.text)
            case .steps(let steps): parts += steps.map(\.text)
            case .keys(let keys): parts += keys.map { $0.0 + " " + $0.1.text }
            }
        }
        return parts.joined(separator: " ")
    }
}

struct HelpView: View {
    let topics: [HelpTopic]
    @State private var selection: String?
    @State private var search = ""

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    }

    private var found: [HelpTopic] {
        let words = search.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return topics }
        return topics.filter { topic in
            words.allSatisfy { topic.searchText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(found, selection: $selection) { topic in
                Label(topic.title.text, systemImage: topic.icon)
                    .lineLimit(2)
                    .padding(.vertical, 2)
                    .tag(topic.id)
            }
            .searchable(text: $search, placement: .sidebar, prompt: HelpText("Search help", de: "Hilfe durchsuchen").text)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            if let topic = topics.first(where: { $0.id == selection }) {
                HelpPage(topic: topic, search: search)
                    .id(topic.id)
            } else {
                ContentUnavailableView(HelpText("Choose a topic", de: "Wähle ein Thema").text, systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(HelpText("\(appName) Help", de: "\(appName) Hilfe").text)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { if selection == nil { selection = topics.first?.id } }
        .onChange(of: search) { _, _ in
            if let first = found.first, !found.contains(where: { $0.id == selection }) { selection = first.id }
        }
    }
}

private struct HelpPage: View {
    let topic: HelpTopic
    let search: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 30))
                        .foregroundStyle(HelpStyle.accent)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topic.title.text).font(.title2.weight(.semibold))
                        Text(topic.summary.text).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
                Divider().padding(.top, 8)
                HStack(spacing: 6) {
                    Text(HelpText("Still stuck? Write to", de: "Noch Fragen? Schreib an").text).foregroundStyle(.secondary)
                    Link("hello@devstefan.com", destination: URL(string: "mailto:hello@devstefan.com")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("devstefan.com", destination: URL(string: "https://devstefan.com")!)
                }
                .font(.callout)
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func view(for block: HelpTopic.Block) -> some View {
        switch block {
        case .text(let text):
            marked(text.text).fixedSize(horizontal: false, vertical: true)
        case .steps(let steps):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.callout.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(HelpStyle.accent))
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 7 }
                        marked(step.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .tip(let text):
            box(text, symbol: "lightbulb", color: HelpStyle.accent)
        case .note(let text):
            box(text, symbol: "exclamationmark.circle", color: .secondary)
        case .keys(let keys):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    GridRow {
                        Text(key.0)
                            .font(.callout.monospaced().weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(HelpStyle.box))
                        Text(key.1.text)
                    }
                }
            }
        }
    }

    private func box(_ text: HelpText, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            marked(text.text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(HelpStyle.box))
    }

    /// **bold** works in the texts; search words are marked in yellow, like in the app.
    private func marked(_ string: String) -> Text {
        var text = (try? AttributedString(markdown: string)) ?? AttributedString(string)
        for word in search.split(separator: " ").map(String.init) where !word.isEmpty {
            let plain = String(text.characters)
            var start = plain.startIndex
            while let range = plain.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: start..<plain.endIndex) {
                let lower = text.index(text.startIndex, offsetByCharacters: plain.distance(from: plain.startIndex, to: range.lowerBound))
                let upper = text.index(lower, offsetByCharacters: plain.distance(from: range.lowerBound, to: range.upperBound))
                text[lower..<upper].backgroundColor = .yellow.opacity(0.6)
                start = range.upperBound
            }
        }
        return Text(text)
    }
}

/// Menu entry "Help → <App> Help" (⌘?), replacing the system's empty help menu.
struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) { HelpMenuButton() }
    }
}

private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
        Button(HelpText("\(name) Help", de: "\(name) Hilfe").text) { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
