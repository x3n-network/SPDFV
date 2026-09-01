import AppKit
import PDFKit
import SPDFVCore
import SwiftUI

struct WorkspaceBench: View {
    @ObservedObject var session: DocumentSession
    @ObservedObject private var automation = ProcessingQueueStore.shared
    @Binding var mode: DocumentWorkspaceMode
    @Environment(\.openWindow) private var openWindow
    let saveAs: () -> Void
    @State private var showsOCRPanel = false
    @State private var showsRedactionGate = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bench(compact: false).fixedSize(horizontal: true, vertical: false)
            bench(compact: true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
    }

    private func bench(compact: Bool) -> some View {
        HStack(spacing: 8) {
            WorkspaceModePicker(selection: $mode, compact: compact, select: selectMode)
            divider
            tools(compact: compact)
            Spacer(minLength: 8)
            saveStatus
        }
    }

    @ViewBuilder
    private func tools(compact: Bool) -> some View {
        switch mode {
        case .read:
            readTools(compact: compact)
        case .markup:
            markupTools(compact: compact)
        case .organize:
            organizeTools(compact: compact)
        case .automate:
            automateTools(compact: compact)
        }
    }

    @ViewBuilder
    private func readTools(compact: Bool) -> some View {
        if compact {
            SquareToolButton(icon: .pages, help: "Show pages") { showNavigator(.pages) }
            SquareToolButton(icon: .outline, help: "Show contents") { showNavigator(.outline) }
            SquareToolButton(icon: .search, help: "Find in document") { showNavigator(.search) }
            SquareToolButton(icon: .copy, help: "Compare with another PDF") { compareDocument() }
        } else {
            BenchButton("Pages", icon: .pages) { showNavigator(.pages) }
            BenchButton("Contents", icon: .outline) { showNavigator(.outline) }
            BenchButton("Find", icon: .search) { showNavigator(.search) }
            BenchButton("Compare", icon: .copy) { compareDocument() }
            status(comparisonStatus)
        }
    }

    @ViewBuilder
    private func markupTools(compact: Bool) -> some View {
        if compact {
            markupMenu
            SquareToolButton(icon: .back, help: session.undoMenuTitle) { session.undoLastEdit() }
                .disabled(!session.canUndoEdit)
            SquareToolButton(icon: .redo, help: session.redoMenuTitle) { session.redoLastEdit() }
                .disabled(!session.canRedoEdit)
            status(benchStatus)
        } else {
            ForEach(MarkupKind.allCases) { kind in
                MarkupToolButton(kind: kind) { session.addMarkup(kind) }
                    .disabled(!session.hasTextSelection)
            }
            divider
            ForEach(CanvasAnnotationTool.quickTools) { tool in
                CanvasToolButton(tool: tool, isSelected: session.activeAnnotationTool == tool) {
                    session.setAnnotationTool(tool)
                }
            }
            SquareToolButton(icon: .back, help: session.undoMenuTitle) { session.undoLastEdit() }
                .disabled(!session.canUndoEdit)
            SquareToolButton(icon: .redo, help: session.redoMenuTitle) { session.redoLastEdit() }
                .disabled(!session.canRedoEdit)
            status(benchStatus)
        }
    }

    private var markupMenu: some View {
        Menu {
            Section("Selected text") {
                ForEach(MarkupKind.allCases) { kind in
                    Button(kind.label) { session.addMarkup(kind) }
                        .disabled(!session.hasTextSelection)
                }
            }
            Section("Place on page") {
                ForEach(CanvasAnnotationTool.quickTools) { tool in
                    Button(tool.label) { session.setAnnotationTool(tool) }
                }
            }
        } label: {
            HStack(spacing: 7) {
                SPDFVIcon(session.activeAnnotationTool.icon)
                Text(session.activeAnnotationTool.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a markup tool")
    }

    @ViewBuilder
    private func organizeTools(compact: Bool) -> some View {
        SquareToolButton(icon: .rotateLeft, help: "Rotate selected pages left") { session.rotateCurrentPage(clockwise: false) }
        SquareToolButton(icon: .rotateRight, help: "Rotate selected pages right") { session.rotateCurrentPage(clockwise: true) }
        if compact {
            pageOperationsMenu
        } else {
            BenchButton("Duplicate", icon: .duplicate) { session.duplicateCurrentPage() }
            BenchButton("Extract", icon: .extract) { session.extractCurrentPageFromPicker() }
            BenchButton("Append PDF", icon: .insertPages) { session.appendPagesFromPicker() }
            status(pageSelectionStatus)
        }
    }

    private var pageOperationsMenu: some View {
        Menu {
            Button("Duplicate selected pages") { session.duplicateCurrentPage() }
            Button("Extract selected pages…") { session.extractCurrentPageFromPicker() }
            Button("Append PDF…") { session.appendPagesFromPicker() }
        } label: {
            SPDFVIcon(.controls)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More page operations")
        .accessibilityLabel("More page operations")
    }

    @ViewBuilder
    private func automateTools(compact: Bool) -> some View {
        if compact {
            SquareToolButton(icon: .quickAction, help: "Open Recipe Press") { openRecipeWorkspace() }
                .disabled(session.isRunningRecipe)
                .accessibilityIdentifier("automation.recipe")
            ocrButton(compact: true)
            redactionButton(compact: true)
            queueButton(compact: true)
        } else {
            BenchButton("Recipe Press", icon: .quickAction, active: session.loadedRecipe != nil) { openRecipeWorkspace() }
                .disabled(session.isRunningRecipe)
                .accessibilityIdentifier("automation.recipe")
            ocrButton(compact: false)
            redactionButton(compact: false)
            queueButton(compact: false)
        }
    }

    private func ocrButton(compact: Bool) -> some View {
        Button { showsOCRPanel.toggle() } label: {
            toolLabel(
                compact: compact,
                title: session.isPerformingOCR ? "Reading…" : "OCR",
                icon: session.isPerformingOCR ? .scanText : .scan,
                color: session.isPerformingOCR ? SPDFVTheme.paleCobalt : SPDFVTheme.primaryText
            )
        }
        .buttonStyle(.plain)
        .disabled(session.isPerformingOCR)
        .popover(isPresented: $showsOCRPanel, arrowEdge: .top) {
            OCRPanel(session: session, isPresented: $showsOCRPanel)
        }
        .help("Create a searchable PDF copy with on-device OCR")
        .accessibilityIdentifier("automation.ocr")
    }

    private func redactionButton(compact: Bool) -> some View {
        Button { showsRedactionGate.toggle() } label: {
            toolLabel(
                compact: compact,
                title: "Redact",
                icon: .region,
                color: session.pendingRedactions.isEmpty ? SPDFVTheme.primaryText : SPDFVTheme.redaction
            )
            .overlay(alignment: .topTrailing) {
                if !session.pendingRedactions.isEmpty {
                    countBadge(session.pendingRedactions.count, color: SPDFVTheme.redaction)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(session.isSanitizingRedactions)
        .popover(isPresented: $showsRedactionGate, arrowEdge: .top) {
            RedactionGate(session: session, isPresented: $showsRedactionGate)
        }
        .accessibilityLabel("Redaction Gate")
        .accessibilityValue("\(session.pendingRedactions.count) staged regions")
        .accessibilityIdentifier("automation.redaction")
        .help("Stage regions and create a sanitized PDF copy")
    }

    private func queueButton(compact: Bool) -> some View {
        Button { openWindow(id: "processing-queue") } label: {
            HStack(spacing: 7) {
                SPDFVIcon(.queue)
                if !compact {
                    Text("Activity").font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                if queueIssueCount > 0 {
                    countBadge(
                        queueIssueCount,
                        color: automation.queue.summary.failed > 0 ? SPDFVTheme.redaction : SPDFVTheme.cobalt
                    )
                }
            }
            .foregroundStyle(automation.queue.summary.failed > 0 ? SPDFVTheme.redaction : SPDFVTheme.primaryText)
            .padding(.horizontal, compact ? 0 : 10)
            .frame(width: compact && queueIssueCount == 0 ? 34 : nil, height: 32)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Open the activity center")
        .accessibilityLabel("Open activity center")
        .accessibilityIdentifier("automation.activity")
    }

    private func toolLabel(compact: Bool, title: String, icon: SPDFVIconName, color: Color) -> some View {
        HStack(spacing: 7) {
            SPDFVIcon(icon)
            if !compact {
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 0 : 10)
        .frame(width: compact ? 34 : nil, height: 32)
        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.system(size: 7, weight: .black, design: .monospaced))
            .foregroundStyle(Color.white)
            .frame(minWidth: 14, minHeight: 14)
            .background(color)
            .clipShape(Circle())
    }

    private var saveStatus: some View {
        Menu {
            Button("Save") { session.save() }.disabled(!session.isDirty)
            Button("Save As…", action: saveAs)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(session.isDirty ? Color.orange : SPDFVTheme.cobalt).frame(width: 6, height: 6)
                Text(session.isDirty ? "Unsaved" : "Saved")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Document save status")
        .accessibilityValue(session.isDirty ? "Unsaved changes" : "Saved")
        .accessibilityIdentifier("document.save-status")
    }

    private var divider: some View {
        Rectangle().fill(SPDFVTheme.divider).frame(width: 1, height: 24).padding(.horizontal, 2)
    }

    private func status(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.65)
            .foregroundStyle(SPDFVTheme.tertiaryText)
            .lineLimit(1)
    }

    private var queueIssueCount: Int {
        automation.queue.summary.queued + automation.queue.summary.failed
    }

    private var pageSelectionStatus: String {
        let count = max(1, session.selectedPageIndices.count)
        return count == 1 ? "Current page" : "\(count) pages selected"
    }

    private func selectMode(_ newMode: DocumentWorkspaceMode) {
        mode = newMode
        if newMode == .organize { showNavigator(.pages) }
    }

    private func showNavigator(_ navigatorMode: NavigatorMode) {
        session.thumbnailsVisible = true
        session.navigatorMode = navigatorMode
    }

    private func compareDocument() {
        showNavigator(.info)
        session.compareWithPicker()
    }

    private var comparisonStatus: String {
        if session.isComparing { return "Comparing…" }
        switch session.comparisonReport?.status {
        case .identical: return "Documents identical"
        case .changed: return "Changes found"
        case nil: return "Document ready"
        }
    }

    private func openRecipeWorkspace() {
        RecipeWorkspaceWindowManager.shared.open(for: session)
    }

    private var benchStatus: String {
        switch session.activeAnnotationTool {
        case .select:
            session.hasTextSelection ? "TEXT READY" : "SELECT TEXT / MARK"
        case .note:
            "CLICK PAGE TO PLACE NOTE"
        case .freeText:
            "CLICK PAGE TO PLACE TEXT"
        case .ink:
            "DRAG ON PAGE TO DRAW"
        case .rectangle:
            "CLICK PAGE TO PLACE SHAPE"
        case .signature:
            "CLICK PAGE TO PLACE SIGNATURE"
        case .formField:
            "CLICK PAGE TO PLACE FIELD"
        }
    }
}

private struct WorkspaceModePicker: View {
    @Binding var selection: DocumentWorkspaceMode
    let compact: Bool
    let select: (DocumentWorkspaceMode) -> Void

    var body: some View {
        if compact {
            Menu {
                ForEach(DocumentWorkspaceMode.allCases) { mode in
                    Button {
                        select(mode)
                    } label: {
                        if mode == selection {
                            SPDFVIconLabel(title: mode.label, icon: .check)
                        } else {
                            SPDFVIconLabel(title: mode.label, icon: mode.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    SPDFVIcon(selection.icon)
                    Text(selection.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(SPDFVTheme.cobalt)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Workspace: \(selection.label)")
            .accessibilityLabel("Document workspace")
            .accessibilityValue(selection.label)
            .accessibilityIdentifier("workspace.selector")
        } else {
            HStack(spacing: 0) {
                ForEach(DocumentWorkspaceMode.allCases) { mode in
                    Button {
                        select(mode)
                    } label: {
                        HStack(spacing: 6) {
                            SPDFVIcon(mode.icon, size: 11)
                            Text(mode.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(mode == selection ? Color.white : SPDFVTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(mode == selection ? SPDFVTheme.cobalt : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mode.label) workspace")
                    .accessibilityValue(mode == selection ? "Selected" : "Not selected")
                    .accessibilityIdentifier("workspace.\(mode.rawValue)")
                }
            }
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
    }
}

private struct BenchButton: View {
    let title: String
    let icon: SPDFVIconName
    let active: Bool
    let action: () -> Void

    init(_ title: String, icon: SPDFVIconName, active: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                SPDFVIcon(icon, size: 11)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? SPDFVTheme.paleCobalt : SPDFVTheme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .overlay { Rectangle().stroke(active ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
