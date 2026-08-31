import SPDFVCore
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var session: DocumentSession
    @ObservedObject private var library = RecipeLibraryStore.shared
    @Binding var workspaceMode: DocumentWorkspaceMode
    let openDocument: () -> Void
    let saveDocumentAs: () -> Void
    let openActivityCenter: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            masthead
            searchField
            resultList
            footer
        }
        .frame(width: 640, height: 520)
        .background(SPDFVTheme.navigator)
        .onAppear {
            selectedID = filteredItems.first?.id
            searchFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedID = filteredItems.first?.id
        }
        .onMoveCommand(perform: moveSelection)
        .onExitCommand { dismiss() }
    }

    private var masthead: some View {
        HStack(spacing: 11) {
            SPDFVIcon(.quickAction, size: 16)
                .foregroundStyle(SPDFVTheme.paleCobalt)
            VStack(alignment: .leading, spacing: 3) {
                Text("COMMAND INDEX")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1.25)
                Text(session.document == nil ? "SPDFV" : session.displayName.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            Spacer()
            Text("⌘K")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .foregroundStyle(SPDFVTheme.navigatorText)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.cobalt).frame(height: 2) }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            SPDFVIcon(.search, size: 15)
                .foregroundStyle(SPDFVTheme.paleCobalt)
            TextField("Search commands, documents, and recipes", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .focused($searchFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(.up)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(.down)
                    return .handled
                }
                .onSubmit { runSelected() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    SPDFVIcon(.closeFilled, size: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .help("Clear search")
                .accessibilityLabel("Clear command search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(SPDFVTheme.navigator)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }

    @ViewBuilder
    private var resultList: some View {
        if filteredItems.isEmpty {
            VStack(spacing: 10) {
                SPDFVIcon(.search, size: 22)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                Text("No matching commands")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Try an action, PDF name, recipe, or workspace.")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(SPDFVTheme.navigatorText)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            CommandPaletteRow(
                                index: index + 1,
                                item: item,
                                isSelected: selectedID == item.id,
                                select: { selectedID = item.id },
                                run: { run(item) }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 7)
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            footerHint("↑↓", "Choose")
            footerHint("↩", "Run")
            footerHint("esc", "Close")
            Spacer()
            Text("\(filteredItems.count) RESULT\(filteredItems.count == 1 ? "" : "S")")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .top) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).fontWeight(.black)
            Text(label)
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(SPDFVTheme.navigatorMuted)
    }

    private var filteredItems: [CommandPaletteItem] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let searchable = ([item.title, item.detail, item.category] + item.keywords)
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy(searchable.contains)
        }
    }

    private var items: [CommandPaletteItem] {
        var result: [CommandPaletteItem] = [
            item("open", "Open PDF…", "Choose a document from this Mac", "DOCUMENT", .documentAdd, shortcut: "⌘O", keywords: ["file", "browse"], action: openDocument),
            item("activity-center", "Open Activity Center", "Review document work, automation, outputs, and failures", "AUTOMATION", .processing, shortcut: "⇧⌘L", keywords: ["activity", "queue", "jobs", "history"], action: openActivityCenter)
        ]

        if session.document != nil {
            result += [
                item("save", "Save PDF", "Write edits to \(session.displayName)", "DOCUMENT", .save, shortcut: "⌘S", enabled: session.isDirty, keywords: ["write"], action: { _ = session.save() }),
                item("save-as", "Save PDF As…", "Write an edited copy to a new location", "DOCUMENT", .save, shortcut: "⇧⌘S", keywords: ["copy", "export"], action: saveDocumentAs),
                item("workspace-read", "Switch to Read", "Navigation and document reading tools", "WORKSPACE", .document, keywords: ["mode", "view"], action: { workspaceMode = .read }),
                item("workspace-markup", "Switch to Markup", "Annotations, drawing, notes, and text markup", "WORKSPACE", .highlighter, keywords: ["mode", "edit", "annotate"], action: { workspaceMode = .markup }),
                item("workspace-organize", "Switch to Organize", "Rotate, duplicate, extract, and append pages", "WORKSPACE", .pages, keywords: ["mode", "pages"], action: { workspaceMode = .organize }),
                item("workspace-automate", "Switch to Automate", "OCR, redaction, recipes, and processing", "WORKSPACE", .automation, keywords: ["mode", "ocr", "redact"], action: { workspaceMode = .automate }),
                item("nav-pages", "Show Pages", "Open the page navigator", "NAVIGATE", .pages, shortcut: "⌘1", keywords: ["sidebar", "thumbnails"], action: { showNavigator(.pages) }),
                item("nav-outline", "Show Contents", "Open the document outline", "NAVIGATE", .outline, shortcut: "⌘2", keywords: ["sidebar", "bookmarks"], action: { showNavigator(.outline) }),
                item("nav-find", "Find in Document…", "Search the PDF text", "NAVIGATE", .search, shortcut: "⌘F", keywords: ["sidebar", "text"], action: { showNavigator(.search) }),
                item("nav-info", "Show Document Info", "Review size, permissions, and metadata", "NAVIGATE", .info, shortcut: "⌘3", keywords: ["sidebar", "details"], action: { showNavigator(.info) }),
                item("nav-annotations", "Show Annotations", "Review every annotation in the PDF", "NAVIGATE", .annotations, shortcut: "⌘4", keywords: ["sidebar", "markup"], action: { showNavigator(.annotations) }),
                item("previous-page", "Previous Page", "Move back one page", "NAVIGATE", .left, shortcut: "⌥←", enabled: session.pageIndex > 0, keywords: ["back"], action: { session.perform(.previousPage) }),
                item("next-page", "Next Page", "Move forward one page", "NAVIGATE", .right, shortcut: "⌥→", enabled: session.pageIndex + 1 < session.pageCount, keywords: ["forward"], action: { session.perform(.nextPage) }),
                item("fit-page", "Fit Page", "Fit the current page in the window", "VIEW", .fitPage, shortcut: "⌘0", keywords: ["zoom", "scale"], action: { session.perform(.fitPage) }),
                item("zoom-in", "Zoom In", "Increase document scale", "VIEW", .zoomIn, shortcut: "⌘+", keywords: ["scale"], action: { session.perform(.zoomIn) }),
                item("zoom-out", "Zoom Out", "Decrease document scale", "VIEW", .zoomOut, shortcut: "⌘−", keywords: ["scale"], action: { session.perform(.zoomOut) }),
                item("rotate-left", "Rotate Page Left", "Rotate the selected page set counterclockwise", "ORGANIZE", .rotateLeft, shortcut: "⌥⌘L", keywords: ["pages"], action: { session.rotateCurrentPage(clockwise: false) }),
                item("rotate-right", "Rotate Page Right", "Rotate the selected page set clockwise", "ORGANIZE", .rotateRight, shortcut: "⌥⌘R", keywords: ["pages"], action: { session.rotateCurrentPage(clockwise: true) }),
                item("duplicate-page", "Duplicate Page", "Duplicate the selected page set", "ORGANIZE", .duplicate, keywords: ["pages", "copy"], action: { session.duplicateCurrentPage() }),
                item("recipe-press", "Open Recipe Press", "Build and verify document recipes", "AUTOMATION", .quickAction, shortcut: "⇧⌘R", keywords: ["composer", "cabinet"], action: { RecipeWorkspaceWindowManager.shared.open(for: session) })
            ]
        }

        result += session.recentDocuments.map { url in
            item(
                "recent-\(url.standardizedFileURL.path)",
                url.deletingPathExtension().lastPathComponent,
                url.deletingLastPathComponent().path,
                "RECENT PDF",
                .document,
                keywords: ["recent", url.lastPathComponent],
                action: { session.open(url) }
            )
        }

        if session.document != nil {
            result += library.entries.map { entry in
                item(
                    "recipe-\(entry.id.uuidString)",
                    entry.recipe.name,
                    "\(entry.kind == .preset ? "Preset" : "Cabinet") · revision \(entry.revision) · \(entry.recipe.steps.count) step\(entry.recipe.steps.count == 1 ? "" : "s")",
                    "RECIPE",
                    entry.isFavorite ? .favoriteFilled : .quickAction,
                    keywords: ["automation", "recipe", entry.kind.rawValue],
                    action: {
                        session.loadLibraryRecipe(entry.id)
                        RecipeWorkspaceWindowManager.shared.open(for: session)
                    }
                )
            }
        }
        return result
    }

    private func item(
        _ id: String,
        _ title: String,
        _ detail: String,
        _ category: String,
        _ icon: SPDFVIconName,
        shortcut: String? = nil,
        enabled: Bool = true,
        keywords: [String] = [],
        action: @escaping () -> Void
    ) -> CommandPaletteItem {
        CommandPaletteItem(id: id, title: title, detail: detail, category: category, icon: icon, shortcut: shortcut, isEnabled: enabled, keywords: keywords, action: action)
    }

    private func showNavigator(_ mode: NavigatorMode) {
        session.thumbnailsVisible = true
        session.navigatorMode = mode
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let available = filteredItems.filter(\.isEnabled)
        guard !available.isEmpty else { return }
        let current = available.firstIndex { $0.id == selectedID } ?? 0
        let next: Int
        switch direction {
        case .up: next = max(0, current - 1)
        case .down: next = min(available.count - 1, current + 1)
        default: return
        }
        selectedID = available[next].id
    }

    private func runSelected() {
        guard let item = filteredItems.first(where: { $0.id == selectedID && $0.isEnabled }) else { return }
        run(item)
    }

    private func run(_ item: CommandPaletteItem) {
        guard item.isEnabled else { return }
        dismiss()
        DispatchQueue.main.async { item.action() }
    }
}

private struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let category: String
    let icon: SPDFVIconName
    let shortcut: String?
    let isEnabled: Bool
    let keywords: [String]
    let action: () -> Void
}

private struct CommandPaletteRow: View {
    let index: Int
    let item: CommandPaletteItem
    let isSelected: Bool
    let select: () -> Void
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorMuted)
                    .frame(width: 24, alignment: .trailing)
                SPDFVIcon(item.icon, size: 14)
                    .foregroundStyle(isSelected ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(SPDFVTheme.navigatorText)
                        Text(item.category)
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .tracking(0.65)
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                    Text(item.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 52)
            .background(isSelected ? SPDFVTheme.controlPressed : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? SPDFVTheme.cobalt : Color.clear)
                    .frame(width: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.42)
        .onHover { hovering in if hovering { select() } }
        .accessibilityLabel(item.title)
        .accessibilityHint(item.detail)
    }
}
