import SwiftUI

struct ViewerActions {
    let openDocument: () -> Void
    let toggleNavigator: () -> Void
    let showPages: () -> Void
    let showOutline: () -> Void
    let showSearch: () -> Void
    let showAnnotations: () -> Void
    let showInfo: () -> Void
    let previousPage: () -> Void
    let nextPage: () -> Void
    let zoomOut: () -> Void
    let zoomIn: () -> Void
    let fitPage: () -> Void
    let setPageLayout: (PageLayoutMode) -> Void
    let save: () -> Void
    let saveAs: () -> Void
    let pageSetup: () -> Void
    let printDocument: () -> Void
    let addMarkup: (MarkupKind) -> Void
    let setAnnotationTool: (CanvasAnnotationTool) -> Void
    let undoAnnotation: () -> Void
    let deleteAnnotation: () -> Void
    let duplicateAnnotation: () -> Void
    let nudgeSelection: (CGFloat, CGFloat) -> Void
    let rotatePage: (Bool) -> Void
    let duplicatePage: () -> Void
    let deletePage: () -> Void
    let movePage: (Int) -> Void
    let extractPage: () -> Void
    let appendPDF: () -> Void
    let selectAllPages: () -> Void
    let clearPageSelection: () -> Void
    let selectedPageCount: Int
    let canDeletePage: Bool
    let canAnnotate: Bool
    let canUndoAnnotation: Bool
    let canDeleteAnnotation: Bool
    let canNudgeSelection: Bool
    let canSave: Bool
    let canPrint: Bool
    let setTheme: (ThemePreference) -> Void
}

private struct ViewerActionsKey: FocusedValueKey {
    typealias Value = ViewerActions
}

extension FocusedValues {
    var viewerActions: ViewerActions? {
        get { self[ViewerActionsKey.self] }
        set { self[ViewerActionsKey.self] = newValue }
    }
}

struct SPDFVCommands: Commands {
    @FocusedValue(\.viewerActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open PDF…") {
                actions?.openDocument()
            }
            .keyboardShortcut("o")
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { actions?.save() }
                .keyboardShortcut("s")
                .disabled(actions?.canSave != true)
            Button("Save As…") { actions?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") { actions?.pageSetup() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(actions?.canPrint != true)
            Button("Print…") { actions?.printDocument() }
                .keyboardShortcut("p")
                .disabled(actions?.canPrint != true)
        }

        CommandMenu("Markup") {
            ForEach(MarkupKind.allCases) { kind in
                Button(kind.label) { actions?.addMarkup(kind) }
                    .disabled(actions?.canAnnotate != true)
            }

            Divider()

            ForEach(CanvasAnnotationTool.allCases) { tool in
                Button(tool.label) { actions?.setAnnotationTool(tool) }
            }

            Divider()

            Button("Delete Selected Annotation") { actions?.deleteAnnotation() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(actions?.canDeleteAnnotation != true)

            Button("Duplicate Selected Annotation") { actions?.duplicateAnnotation() }
                .keyboardShortcut("d")
                .disabled(actions?.canDeleteAnnotation != true)

            Section("Nudge selected object") {
                Button("Nudge Left") { actions?.nudgeSelection(-1, 0) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Button("Nudge Right") { actions?.nudgeSelection(1, 0) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Nudge Up") { actions?.nudgeSelection(0, 1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                Button("Nudge Down") { actions?.nudgeSelection(0, -1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command])
            }
            .disabled(actions?.canNudgeSelection != true)

            Button("Undo Last Edit") { actions?.undoAnnotation() }
                .keyboardShortcut("z")
                .disabled(actions?.canUndoAnnotation != true)
        }

        CommandMenu("Pages") {
            Button("Select All Pages") { actions?.selectAllPages() }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Clear Page Selection") { actions?.clearPageSelection() }

            Divider()

            Button("Move Page Earlier") { actions?.movePage(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Move Page Later") { actions?.movePage(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Button((actions?.selectedPageCount ?? 0) > 1 ? "Rotate Selected Pages Left" : "Rotate Page Left") { actions?.rotatePage(false) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button((actions?.selectedPageCount ?? 0) > 1 ? "Rotate Selected Pages Right" : "Rotate Page Right") { actions?.rotatePage(true) }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button((actions?.selectedPageCount ?? 0) > 1 ? "Duplicate Selected Pages" : "Duplicate Page") { actions?.duplicatePage() }
            Button((actions?.selectedPageCount ?? 0) > 1 ? "Delete Selected Pages" : "Delete Page") { actions?.deletePage() }
                .disabled(actions?.canDeletePage != true)

            Divider()

            Button((actions?.selectedPageCount ?? 0) > 1 ? "Extract Selected Pages…" : "Extract Page…") { actions?.extractPage() }
            Button("Append PDF…") { actions?.appendPDF() }
        }

        CommandMenu("Navigate") {
            Button("Pages") { actions?.showPages() }
                .keyboardShortcut("1")
            Button("Contents") { actions?.showOutline() }
                .keyboardShortcut("2")
            Button("Find in Document…") { actions?.showSearch() }
                .keyboardShortcut("f")
            Button("Annotations") { actions?.showAnnotations() }
                .keyboardShortcut("4")
            Button("Document Info") { actions?.showInfo() }
                .keyboardShortcut("3")

            Divider()

            Button("Previous Page") { actions?.previousPage() }
                .keyboardShortcut(.leftArrow, modifiers: [.option])
            Button("Next Page") { actions?.nextPage() }
                .keyboardShortcut(.rightArrow, modifiers: [.option])

            Divider()

            Button("Toggle Navigator") { actions?.toggleNavigator() }
                .keyboardShortcut("s", modifiers: [.command, .control])
        }

        CommandMenu("View Scale") {
            Section("Page layout") {
                ForEach(PageLayoutMode.allCases) { layout in
                    Button(layout.label) {
                        actions?.setPageLayout(layout)
                    }
                }
            }

            Divider()

            Button("Zoom In") { actions?.zoomIn() }
                .keyboardShortcut("+")
            Button("Zoom Out") { actions?.zoomOut() }
                .keyboardShortcut("-")
            Button("Fit Page") { actions?.fitPage() }
                .keyboardShortcut("0")
        }

        CommandMenu("Appearance") {
            ForEach(ThemePreference.allCases) { preference in
                Button(preference.label) {
                    actions?.setTheme(preference)
                }
            }
        }

        CommandMenu("Automation") {
            Button("Open Processing Queue") {
                openWindow(id: "processing-queue")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
