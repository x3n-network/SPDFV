import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import SPDFVCore

struct ContentView: View {
    @StateObject private var session = DocumentSession()
    @State private var isTargeted = false
    @State private var didOpenInitialURL = false
    @State private var commandPalettePresented = false
    @State private var workspaceMode = DocumentWorkspaceMode.read
    @AppStorage("themePreference") private var themePreferenceRaw = ThemePreference.system.rawValue
    @Environment(\.openWindow) private var openWindow
    private let initialURL: URL?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    var body: some View {
        Group {
            if session.document == nil {
                EmptyDocumentView(
                    session: session,
                    themePreference: themePreference,
                    openDocument: openDocument
                )
            } else {
                ReaderView(
                    session: session,
                    themePreference: themePreference,
                    workspaceMode: $workspaceMode,
                    openDocument: openDocument,
                    saveAs: saveDocumentAs
                )
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(SPDFVTheme.canvas)
        .background(
            WindowCloseGuard(session: session, viewerActions: viewerActions)
                .frame(width: 0, height: 0)
        )
        .navigationTitle(session.document == nil ? "SPDFV" : session.displayName)
        .dropDestination(for: URL.self, action: handleDrop, isTargeted: { isTargeted = $0 })
        .overlay {
            if isTargeted {
                DropTargetOverlay()
                    .allowsHitTesting(false)
            }
        }
        .alert("Couldn’t complete action", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "The selected file could not be read.")
        }
        .alert("Save changes before opening another PDF?", isPresented: pendingOpenIsPresented) {
            Button("Save and Open") {
                session.resolvePendingOpen(savingChanges: true)
            }
            Button("Discard Changes", role: .destructive) {
                session.resolvePendingOpen(savingChanges: false)
            }
            Button("Cancel", role: .cancel) {
                session.cancelPendingOpen()
            }
        } message: {
            Text("Your markup in \(session.displayName) has not been saved.")
        }
        .sheet(isPresented: $commandPalettePresented) {
            CommandPaletteView(
                session: session,
                workspaceMode: $workspaceMode,
                openDocument: openDocument,
                saveDocumentAs: saveDocumentAs,
                openActivityCenter: { openWindow(id: "processing-queue") }
            )
        }
        .onOpenURL { session.open($0) }
        .preferredColorScheme(themePreference.wrappedValue.colorScheme)
        .focusedSceneValue(\.viewerActions, viewerActions)
        .onAppear {
            CloseProtectionCenter.shared.register(session)
            DocumentWindowManager.shared.register(session)
            applyApplicationAppearance(themePreference.wrappedValue)
            if !didOpenInitialURL, let initialURL {
                didOpenInitialURL = true
                session.open(initialURL)
            }
        }
        .onDisappear {
            RecipeWorkspaceWindowManager.shared.close(for: session)
            CloseProtectionCenter.shared.unregister(session)
            DocumentWindowManager.shared.unregister(session)
        }
        .onChange(of: themePreference.wrappedValue) { _, preference in
            applyApplicationAppearance(preference)
        }
    }

    private var themePreference: Binding<ThemePreference> {
        Binding(
            get: { ThemePreference(rawValue: themePreferenceRaw) ?? .system },
            set: { themePreferenceRaw = $0.rawValue }
        )
    }

    private var viewerActions: ViewerActions {
        ViewerActions(
            openDocument: openDocument,
            toggleNavigator: { session.thumbnailsVisible.toggle() },
            showPages: { showNavigator(.pages) },
            showOutline: { showNavigator(.outline) },
            showSearch: { showNavigator(.search) },
            showAnnotations: { showNavigator(.annotations) },
            showInfo: { showNavigator(.info) },
            previousPage: { session.perform(.previousPage) },
            nextPage: { session.perform(.nextPage) },
            zoomOut: { session.perform(.zoomOut) },
            zoomIn: { session.perform(.zoomIn) },
            fitPage: { session.perform(.fitPage) },
            setPageLayout: { session.setPageLayout($0) },
            save: { session.save() },
            saveAs: saveDocumentAs,
            pageSetup: { session.perform(.pageSetup) },
            printDocument: { session.perform(.printDocument) },
            addMarkup: { session.addMarkup($0) },
            setAnnotationTool: { session.setAnnotationTool($0) },
            undoEdit: { session.undoLastEdit() },
            redoEdit: { session.redoLastEdit() },
            deleteAnnotation: { session.deleteSelectedAnnotation() },
            duplicateAnnotation: { session.duplicateSelectedAnnotation() },
            nudgeSelection: { session.nudgeSelectedObject(horizontal: $0, vertical: $1) },
            rotatePage: { session.rotateCurrentPage(clockwise: $0) },
            duplicatePage: { session.duplicateCurrentPage() },
            deletePage: { session.deleteCurrentPage() },
            movePage: { session.moveCurrentPage(by: $0) },
            extractPage: { session.extractCurrentPageFromPicker() },
            appendPDF: { session.appendPagesFromPicker() },
            selectAllPages: { session.selectAllPages() },
            clearPageSelection: { session.clearPageSelection() },
            selectedPageCount: session.selectedPageIndices.count,
            canDeletePage: max(1, session.selectedPageIndices.count) < session.pageCount,
            canAnnotate: session.hasTextSelection,
            undoTitle: session.undoMenuTitle,
            redoTitle: session.redoMenuTitle,
            canUndoEdit: session.canUndoEdit,
            canRedoEdit: session.canRedoEdit,
            canDeleteAnnotation: session.selectedAnnotation != nil,
            canNudgeSelection: session.selectedAnnotation != nil || session.selectedFormField != nil,
            canSave: session.isDirty,
            canPrint: session.document?.allowsPrinting == true,
            showCommandPalette: { commandPalettePresented = true },
            openRecipePress: { RecipeWorkspaceWindowManager.shared.open(for: session) },
            setTheme: { themePreference.wrappedValue = $0 }
        )
    }

    private func showNavigator(_ mode: NavigatorMode) {
        session.thumbnailsVisible = true
        session.navigatorMode = mode
    }

    private func applyApplicationAppearance(_ preference: ThemePreference) {
        switch preference {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )
    }

    private var pendingOpenIsPresented: Binding<Bool> {
        Binding(
            get: { session.pendingOpenURL != nil },
            set: { if !$0 { session.cancelPendingOpen() } }
        )
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a PDF to view"

        if panel.runModal() == .OK, let url = panel.url {
            session.open(url)
        }
    }

    private func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = session.fileURL?.lastPathComponent ?? "Document.pdf"
        panel.message = "Save an edited copy of this PDF"

        if panel.runModal() == .OK, let url = panel.url {
            session.save(to: url)
        }
    }

    private func handleDrop(_ urls: [URL], _ location: CGPoint) -> Bool {
        guard let pdfURL = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else {
            return false
        }
        session.open(pdfURL)
        return true
    }
}

private struct ReaderView: View {
    @ObservedObject var session: DocumentSession
    @Binding var themePreference: ThemePreference
    @Binding var workspaceMode: DocumentWorkspaceMode
    let openDocument: () -> Void
    let saveAs: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FolioBar(
                session: session,
                themePreference: $themePreference,
                openDocument: openDocument
            )

            WorkspaceBench(session: session, mode: $workspaceMode, saveAs: saveAs)

            if session.selectedAnnotation != nil {
                AnnotationInspectorStrip(session: session)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if session.isCropEditing {
                CropEditingStrip(session: session)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if session.isRedactionEditing {
                RedactionEditingStrip(session: session)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 0) {
                if session.thumbnailsVisible {
                    NavigatorSidebar(session: session)
                        .frame(width: 244)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Rectangle()
                        .fill(SPDFVTheme.divider)
                        .frame(width: 1)
                }

                ZStack(alignment: .trailing) {
                    if session.safetyGate?.locked == true {
                        LockedDocumentView(session: session, openDocument: openDocument)
                    } else {
                        PDFWorkspace(session: session)
                        PageSpine(session: session)
                    }
                }
            }

            DocumentStatusBar(session: session)
        }
        .animation(.snappy(duration: 0.22), value: session.thumbnailsVisible)
        .animation(.snappy(duration: 0.18), value: session.selectedAnnotation?.id)
        .animation(.snappy(duration: 0.18), value: session.isCropEditing)
        .animation(.snappy(duration: 0.18), value: session.isRedactionEditing)
    }
}

private struct CropEditingStrip: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 12) {
            SPDFVIcon(.cropRotate)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SPDFVTheme.paleCobalt)

            VStack(alignment: .leading, spacing: 2) {
                Text("TRIM TABLE · PAGE \(session.pageIndex + 1)")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.1)
                Text("Drag the blue edge and corner registers. The shaded stock remains in the PDF.")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.secondaryText)
            }

            Spacer()

            Button("DONE") { session.setCropEditing(false) }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .buttonStyle(.borderedProminent)
                .tint(SPDFVTheme.cobalt)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(SPDFVTheme.folio)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.cobalt).frame(height: 2)
        }
    }
}

private struct RedactionEditingStrip: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 12) {
            SPDFVIcon(.region)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SPDFVTheme.redaction)
            VStack(alignment: .leading, spacing: 2) {
                Text("REDACTION TABLE · \(session.pendingRedactions.count) STAGED")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.1)
                Text("Drag over every region that must be destroyed in the sanitized copy.")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.secondaryText)
            }
            Spacer()
            Button("DONE MARKING") { session.setRedactionEditing(false) }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .buttonStyle(.borderedProminent)
                .tint(SPDFVTheme.redaction)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(SPDFVTheme.folio)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.redaction).frame(height: 2)
        }
    }
}

private struct FolioBar: View {
    @ObservedObject var session: DocumentSession
    @Binding var themePreference: ThemePreference
    let openDocument: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                SquareToolButton(
                    icon: session.thumbnailsVisible ? .sidebarHide : .sidebarShow,
                    help: session.thumbnailsVisible ? "Hide navigator" : "Show navigator"
                ) {
                    session.thumbnailsVisible.toggle()
                }

                Button(action: openDocument) {
                    Text("PDF")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(SPDFVTheme.cobalt)
                }
                .buttonStyle(.plain)
                .help("Open another PDF")

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SPDFVTheme.primaryText)
                        .lineLimit(1)
                    Text("\(session.pageCount) PAGE\(session.pageCount == 1 ? "" : "S")")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(SPDFVTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PageStepper(session: session)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                PageLayoutSelector(session: session)
                ZoomDeck(session: session)
            }
                .frame(maxWidth: .infinity, alignment: .trailing)

            Rectangle()
                .fill(SPDFVTheme.divider)
                .frame(width: 1, height: 22)
                .padding(.leading, 10)

            ThemeSelector(selection: $themePreference)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(SPDFVTheme.folio)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
    }
}

enum DocumentWorkspaceMode: String, CaseIterable, Identifiable {
    case read
    case markup
    case organize
    case automate

    var id: Self { self }

    var label: String {
        switch self {
        case .read: "Read"
        case .markup: "Markup"
        case .organize: "Organize"
        case .automate: "Automate"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .read: .document
        case .markup: .highlighter
        case .organize: .pages
        case .automate: .automation
        }
    }
}

private struct WorkspaceBench: View {
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
        } else {
            BenchButton("Pages", icon: .pages) { showNavigator(.pages) }
            BenchButton("Contents", icon: .outline) { showNavigator(.outline) }
            BenchButton("Find", icon: .search) { showNavigator(.search) }
            status("Document ready")
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
            ocrButton(compact: true)
            redactionButton(compact: true)
            queueButton(compact: true)
        } else {
            BenchButton("Recipe Press", icon: .quickAction, active: session.loadedRecipe != nil) { openRecipeWorkspace() }
                .disabled(session.isRunningRecipe)
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

private struct RedactionGate: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @State private var restoresSearchableText = true
    @State private var forbiddenText = ""

    private var forbiddenTerms: [String] {
        forbiddenText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("REDACTION GATE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.35)
                    Text("DESTRUCTIVE OUTPUT CONTROL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                ZStack {
                    Rectangle()
                        .fill(SPDFVTheme.redactionInk)
                        .frame(width: 34, height: 20)
                    Rectangle()
                        .stroke(SPDFVTheme.redaction, lineWidth: 1.5)
                        .frame(width: 42, height: 28)
                }
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(spacing: 10) {
                Button {
                    session.setRedactionEditing(!session.isRedactionEditing)
                    isPresented = false
                } label: {
                    HStack {
                        SPDFVIconLabel(
                            title: session.isRedactionEditing ? "Stop drawing regions" : "Draw redaction regions",
                            icon: .region
                        )
                        Spacer()
                        Text(session.isRedactionEditing ? "ARMED" : "DIRECT")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                }
                .buttonStyle(.plain)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.pendingRedactions.count) REGION\(session.pendingRedactions.count == 1 ? "" : "S") STAGED")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        Text("Affected pages will be flattened")
                            .font(.system(size: 10))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                    Spacer()
                    Button("CLEAR") { session.clearPendingRedactions() }
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .buttonStyle(.plain)
                        .foregroundStyle(SPDFVTheme.redaction)
                        .disabled(session.pendingRedactions.isEmpty)
                }

                if !session.pendingRedactions.isEmpty {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(session.pendingRedactions) { mark in
                                RedactionRegisterRow(session: session, mark: mark)
                            }
                        }
                    }
                    .frame(maxHeight: 96)
                }

                VStack(alignment: .leading, spacing: 6) {
                    OCRSectionLabel(text: "VERIFY ABSENT · OPTIONAL")
                    TextField("secret, account number, identifier", text: $forbiddenText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(SPDFVTheme.navigator)
                        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                    Text("The export fails if any listed phrase remains extractable anywhere in the copy.")
                        .font(.system(size: 9))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }

                Toggle(isOn: $restoresSearchableText) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REBUILD SAFE TEXT")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        Text("OCR runs only after black regions are burned in")
                            .font(.system(size: 9))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                }
                .toggleStyle(.switch)

                HStack(alignment: .top, spacing: 9) {
                    Rectangle().fill(SPDFVTheme.redaction).frame(width: 3, height: 58)
                    Text("This is destructive by design. Affected pages become new page images, hidden objects are discarded, annotations are baked in, and the original file remains untouched.")
                        .font(.system(size: 10))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)

            if session.isSanitizingRedactions {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView().progressViewStyle(.linear)
                    Text(session.redactionStatusMessage ?? "Sanitizing pages…")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            Button {
                session.createSanitizedCopy(
                    restoresSearchableText: restoresSearchableText,
                    forbiddenTerms: forbiddenTerms
                )
            } label: {
                HStack {
                    SPDFVIconLabel(title: "Create sanitized copy", icon: .secureCopy)
                    Spacer()
                    Text(forbiddenTerms.isEmpty ? "UNVERIFIED" : "VERIFY \(forbiddenTerms.count)")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(SPDFVTheme.redaction)
            }
            .buttonStyle(.plain)
            .disabled(session.pendingRedactions.isEmpty || session.isSanitizingRedactions)
            .padding(12)
        }
        .frame(width: 344)
        .background(SPDFVTheme.navigatorInset)
    }
}

private struct RedactionRegisterRow: View {
    @ObservedObject var session: DocumentSession
    let mark: PendingRedaction

    private var pageNumber: Int {
        let index = session.document?.index(for: mark.page) ?? NSNotFound
        return index == NSNotFound ? 0 : index + 1
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(SPDFVTheme.redactionInk)
                .frame(width: 24, height: 13)
                .overlay { Rectangle().stroke(SPDFVTheme.redaction, lineWidth: 1) }
            Text("PAGE \(pageNumber) · \(Int(mark.bounds.width.rounded()))×\(Int(mark.bounds.height.rounded())) PT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorText)
            Spacer()
            Button {
                session.removePendingRedaction(mark.id)
            } label: {
                SPDFVIcon(.close)
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove redaction on page \(pageNumber)")
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(SPDFVTheme.navigator)
    }
}

private struct OCRPanel: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @State private var scope: OCRPageScope = .all
    @State private var quality: PDFOCRRecognitionLevel = .accurate
    @State private var language: OCRLanguagePreset = .automatic

    private var scopedPageCount: Int {
        switch scope {
        case .current: 1
        case .selection: max(1, session.selectedPageIndices.count)
        case .all: session.pageCount
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OCR")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.4)
                    Text("ON-DEVICE TEXT RECOGNITION")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                ZStack {
                    SPDFVIcon(.scanText)
                        .font(.system(size: 22, weight: .light))
                    Text("Aa")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .offset(y: 1)
                }
                .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                OCRSectionLabel(text: "SHEETS TO READ")
                HStack(spacing: 6) {
                    ForEach(OCRPageScope.allCases) { item in
                        Button {
                            scope = item
                        } label: {
                            Text(item.label)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .foregroundStyle(scope == item ? Color.white : SPDFVTheme.navigatorText)
                                .background(scope == item ? SPDFVTheme.cobalt : Color.clear)
                                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        OCRSectionLabel(text: "OUTPUT")
                        Picker("Quality", selection: $quality) {
                            Text("PROOF · ACCURATE").tag(PDFOCRRecognitionLevel.accurate)
                            Text("DRAFT · FAST").tag(PDFOCRRecognitionLevel.fast)
                        }
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        OCRSectionLabel(text: "LANGUAGE")
                        Picker("Language", selection: $language) {
                            ForEach(OCRLanguagePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                    }
                }

                HStack(alignment: .top, spacing: 9) {
                    Rectangle()
                        .fill(SPDFVTheme.cobalt)
                        .frame(width: 3, height: 44)
                    Text("The page image stays untouched. SPDFV adds an invisible, selectable text layer to a separate PDF using Apple Vision on this Mac.")
                        .font(.system(size: 10))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)

            if session.isPerformingOCR {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView().progressViewStyle(.linear)
                    Text(session.ocrStatusMessage ?? "Reading pages…")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            Button {
                session.createSearchableCopy(
                    scope: scope,
                    quality: quality,
                    languages: language.languages
                )
                if !session.isPerformingOCR { isPresented = false }
            } label: {
                HStack {
                    SPDFVIconLabel(title: "Create searchable copy", icon: .scanText)
                    Spacer()
                    Text("\(scopedPageCount) PG")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(SPDFVTheme.cobalt)
            }
            .buttonStyle(.plain)
            .disabled(session.isPerformingOCR)
            .padding(12)
        }
        .frame(width: 326)
        .background(SPDFVTheme.navigatorInset)
    }
}

private struct OCRSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(SPDFVTheme.navigatorFaint)
    }
}

private struct MarkupToolButton: View {
    let kind: MarkupKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                SPDFVIcon(kind.icon, size: 11)
                    .font(.system(size: 11, weight: .semibold))
                Text(kind.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: SPDFVTheme.annotationNSColor(for: kind)))
                    .frame(height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .help("Add \(kind.label.lowercased()) to selected text")
    }
}

private struct CanvasToolButton: View {
    let tool: CanvasAnnotationTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SPDFVIcon(tool.icon, size: 11)
                    .font(.system(size: 11, weight: .semibold))
                Text(tool.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.white : SPDFVTheme.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isSelected ? SPDFVTheme.cobalt : Color.clear)
            .overlay {
                Rectangle().stroke(isSelected ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.help)
        .accessibilityLabel(tool.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct AnnotationInspectorStrip: View {
    @ObservedObject var session: DocumentSession
    @State private var contents = ""
    @State private var opacity = 1.0
    @State private var strokeWidth = 1.0
    @State private var fontSize = 14.0

    private var selection: AnnotationSelection? { session.selectedAnnotation }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(selection.map { Color(nsColor: $0.annotation.color) } ?? SPDFVTheme.cobalt)
                .frame(width: 5)

            VStack(spacing: 7) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((selection?.typeLabel ?? "ANNOTATION").uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(SPDFVTheme.primaryText)
                        Text("PAGE \((selection?.pageIndex ?? 0) + 1) · \(selection?.author ?? "Unknown")")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.secondaryText)
                    }
                    .frame(width: 150, alignment: .leading)

                    TextField("Annotation text or note", text: $contents)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SPDFVTheme.primaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(SPDFVTheme.navigatorInset)
                        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                        .onSubmit(commitContents)
                        .accessibilityLabel("Annotation contents")

                    HStack(spacing: 6) {
                        duplicateButton
                        deleteButton
                    }
                }

                HStack(spacing: 10) {
                    Text("INK")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SPDFVTheme.secondaryText)

                    HStack(spacing: 4) {
                        ForEach(AnnotationColorPreset.allCases) { preset in
                            colorButton(preset)
                        }
                    }

                    Rectangle().fill(SPDFVTheme.divider).frame(width: 1, height: 18)

                    InspectorMetricSlider(
                        label: "OPACITY",
                        value: $opacity,
                        range: 0.12...1,
                        displayValue: "\(Int((opacity * 100).rounded()))%",
                        onEditingChanged: editStyle
                    ) { session.updateSelectedAnnotationOpacity($0) }

                    if selection?.hasAdjustableStroke == true {
                        InspectorMetricSlider(
                            label: "STROKE",
                            value: $strokeWidth,
                            range: 0.5...8,
                            displayValue: String(format: "%.1f", strokeWidth),
                            onEditingChanged: editStyle
                        ) { session.updateSelectedAnnotationStrokeWidth($0) }
                    }

                    if selection?.hasAdjustableFont == true {
                        InspectorMetricSlider(
                            label: "TYPE",
                            value: $fontSize,
                            range: 8...48,
                            displayValue: "\(Int(fontSize.rounded()))",
                            onEditingChanged: editStyle
                        ) { session.updateSelectedAnnotationFontSize($0) }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.trailing, 14)
        .frame(height: 74)
        .background(SPDFVTheme.folio)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
        .onAppear(perform: loadContents)
        .onChange(of: session.selectedAnnotation?.id) { _, _ in loadContents() }
    }

    private func loadContents() {
        contents = session.selectedAnnotation?.contents ?? ""
        opacity = session.selectedAnnotation?.opacity ?? 1
        strokeWidth = session.selectedAnnotation?.strokeWidth ?? 1
        fontSize = session.selectedAnnotation?.fontSize ?? 14
    }

    private func commitContents() {
        session.updateSelectedAnnotation(contents: contents)
    }

    private func editStyle(_ isEditing: Bool) {
        if isEditing {
            session.beginSelectedAnnotationStyleEdit()
        } else {
            session.commitSelectedAnnotationStyleEdit()
        }
    }

    private func colorButton(_ preset: AnnotationColorPreset) -> some View {
        Button {
            session.recolorSelectedAnnotation(preset)
            opacity = session.selectedAnnotation?.opacity ?? opacity
        } label: {
            Rectangle()
                .fill(Color(nsColor: preset.nsColor))
                .frame(width: 16, height: 16)
                .overlay { Rectangle().stroke(SPDFVTheme.primaryText.opacity(0.22), lineWidth: 1) }
                .padding(2)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Use \(preset.label.lowercased())")
        .accessibilityLabel("\(preset.label) annotation color")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            session.deleteSelectedAnnotation()
        } label: {
            HStack(spacing: 6) {
                SPDFVIcon(.delete)
                Text("DELETE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
            }
            .foregroundStyle(Color.red)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .overlay { Rectangle().stroke(Color.red.opacity(0.7), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete selected annotation")
    }

    private var duplicateButton: some View {
        Button {
            session.duplicateSelectedAnnotation()
        } label: {
            SPDFVIcon(.duplicate)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SPDFVTheme.primaryText)
                .frame(width: 30, height: 30)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Duplicate selected annotation (⌘D)")
        .accessibilityLabel("Duplicate selected annotation")
    }
}

private struct InspectorMetricSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String
    let onEditingChanged: (Bool) -> Void
    let update: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(SPDFVTheme.secondaryText)
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .controlSize(.mini)
                .frame(width: 70)
                .onChange(of: value) { _, newValue in update(newValue) }
            Text(displayValue)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(SPDFVTheme.primaryText)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(displayValue)
    }
}

private struct PageStepper: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        PageJumpControl(session: session)
    }
}

private struct ZoomDeck: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 2) {
            SquareToolButton(icon: .zoomOut, help: "Zoom out") {
                session.perform(.zoomOut)
            }

            Button {
                session.perform(.actualSize)
            } label: {
                Text(session.zoomLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.primaryText)
                    .frame(width: 48, height: 34)
            }
            .buttonStyle(.plain)
            .help("Actual size")

            SquareToolButton(icon: .zoomIn, help: "Zoom in") {
                session.perform(.zoomIn)
            }

            Rectangle()
                .fill(SPDFVTheme.divider)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 5)

            SquareToolButton(icon: .fitPage, help: "Fit page") {
                session.perform(.fitPage)
            }
        }
    }
}

private struct PageLayoutSelector: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        Menu {
            ForEach(PageLayoutMode.allCases) { layout in
                Button {
                    session.setPageLayout(layout)
                } label: {
                    if layout == session.pageLayout {
                        SPDFVIconLabel(title: layout.label, icon: .check)
                    } else {
                        Text(layout.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                PageLayoutGlyph(layout: session.pageLayout)
                    .frame(width: 22, height: 22)
                Text(session.pageLayout.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Page layout: \(session.pageLayout.label)")
        .accessibilityLabel("Page layout")
        .accessibilityValue(session.pageLayout.label)
    }
}

private struct PageLayoutGlyph: View {
    let layout: PageLayoutMode

    var body: some View {
        GeometryReader { geometry in
            let color = SPDFVTheme.primaryText
            switch layout {
            case .single:
                page(color)
                    .frame(width: 11, height: 15)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            case .continuous:
                VStack(spacing: 2) {
                    page(color)
                    page(color)
                }
                .frame(width: 11, height: 18)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            case .spread:
                HStack(spacing: 2) {
                    page(color)
                    page(color)
                }
                .frame(width: 18, height: 13)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }

    private func page(_ color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(0.13))
            .overlay { Rectangle().stroke(color, lineWidth: 1) }
    }
}

private struct SquareToolButton: View {
    let icon: SPDFVIconName
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            SPDFVIcon(icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquareToolButtonStyle(isHovering: isHovering))
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }
}

private struct SquareToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? SPDFVTheme.primaryText : SPDFVTheme.tertiaryText)
            .background(
                configuration.isPressed
                    ? SPDFVTheme.controlPressed
                    : (isHovering && isEnabled ? SPDFVTheme.controlPressed.opacity(0.72) : Color.clear)
            )
            .overlay {
                Rectangle().stroke(SPDFVTheme.divider.opacity(configuration.isPressed ? 1 : 0), lineWidth: 1)
            }
    }
}

private struct PageSpine: View {
    @ObservedObject var session: DocumentSession

    private var progress: CGFloat {
        guard session.pageCount > 1 else { return 0 }
        return CGFloat(session.pageIndex) / CGFloat(session.pageCount - 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let usableHeight = max(1, geometry.size.height - 64)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(SPDFVTheme.spineTrack)
                    .frame(width: 1)
                    .padding(.vertical, 24)

                VStack(spacing: 0) {
                    Text(String(format: "%02d", session.pageIndex + 1))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 24)
                        .background(SPDFVTheme.cobalt)
                    Rectangle()
                        .fill(SPDFVTheme.paleCobalt)
                        .frame(width: 1, height: 12)
                }
                .offset(y: 20 + usableHeight * progress)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 34)
        .padding(.trailing, 6)
        .allowsHitTesting(false)
    }
}

private struct DocumentStatusBar: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 18) {
            DocumentStatusItem(label: "PAGE", value: "\(session.pageIndex + 1) OF \(session.pageCount)")
            DocumentStatusItem(label: "VIEW", value: session.pageLayout.label.uppercased())
            DocumentStatusItem(label: "MARKS", value: "\(session.annotationCount)")
            Spacer()
            DocumentStatusItem(label: "SCALE", value: session.zoomLabel)
            Circle()
                .fill(session.isDirty ? Color.orange : SPDFVTheme.cobalt)
                .frame(width: 6, height: 6)
            Text(session.isDirty ? "MODIFIED" : "READY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(SPDFVTheme.statusBarText)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(SPDFVTheme.statusBarBackground)
    }
}

private struct DocumentStatusItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(SPDFVTheme.statusBarLabel)
            Text(value).foregroundStyle(SPDFVTheme.statusBarText)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(0.8)
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            SPDFVTheme.statusBarBackground.opacity(0.9)
            Rectangle()
                .strokeBorder(SPDFVTheme.paleCobalt, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .padding(16)
            VStack(spacing: 10) {
                SPDFVIcon(.insertPages)
                    .font(.system(size: 30, weight: .light))
                Text("Drop to open")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
        }
    }
}

private struct EmptyDocumentView: View {
    @ObservedObject var session: DocumentSession
    @Binding var themePreference: ThemePreference
    let openDocument: () -> Void

    var body: some View {
        ZStack {
            SPDFVTheme.canvas

            VStack(spacing: 0) {
                HStack {
                    Text("SPDFV")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(2.4)
                    Spacer()
                    HStack(spacing: 16) {
                        Text("SIMPLE PDF VIEWER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(SPDFVTheme.secondaryText)
                        ThemeSelector(selection: $themePreference)
                    }
                }
                .foregroundStyle(SPDFVTheme.primaryText)
                .padding(22)

                Spacer()

                HStack(spacing: 22) {
                    launchCard

                    if !session.recentDocuments.isEmpty {
                        RecentDocumentsPanel(session: session)
                    }
                }

                Spacer()

                Text("⌘O  OPEN   ·   DROP  ANYWHERE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(SPDFVTheme.tertiaryText)
                    .padding(.bottom, 22)
            }
        }
    }

    private var launchCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(SPDFVTheme.cobalt)
                .frame(width: 7)

            VStack(alignment: .leading, spacing: 26) {
                Text("A clear place\nfor documents.")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(SPDFVTheme.primaryText)

                Text("Open a PDF or drop one into the window.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(SPDFVTheme.secondaryText)

                Button(action: openDocument) {
                    HStack(spacing: 28) {
                        Text("OPEN PDF")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.3)
                        SPDFVIcon(.reveal)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(SPDFVTheme.statusBarBackground)
                }
                .buttonStyle(.plain)
            }
            .padding(42)
        }
        .frame(width: 510, height: 350, alignment: .leading)
        .background(SPDFVTheme.folio)
        .shadow(color: .black.opacity(0.28), radius: 32, y: 16)
    }
}

private struct RecentDocumentsPanel: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(SPDFVTheme.secondaryText)
                Spacer()
                Button("CLEAR") { session.clearRecentDocuments() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.tertiaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(session.recentDocuments.prefix(5).enumerated()), id: \.element) { index, url in
                    Button {
                        session.open(url)
                    } label: {
                        HStack(spacing: 11) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(SPDFVTheme.paleCobalt)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SPDFVTheme.primaryText)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().lastPathComponent.uppercased())
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(0.7)
                                    .foregroundStyle(SPDFVTheme.tertiaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            SPDFVIcon(.reveal)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(SPDFVTheme.tertiaryText)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 55)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open recent document \(url.lastPathComponent)")

                    if index < min(session.recentDocuments.count, 5) - 1 {
                        Rectangle()
                            .fill(SPDFVTheme.divider)
                            .frame(height: 1)
                            .padding(.leading, 40)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 270, height: 350)
        .background(SPDFVTheme.folio)
        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
    }
}

private struct ThemeSelector: View {
    @Binding var selection: ThemePreference

    var body: some View {
        Menu {
            ForEach(ThemePreference.allCases) { preference in
                Button {
                    selection = preference
                } label: {
                    SPDFVIconLabel(title: preference.label, icon: preference.icon)
                }
            }
        } label: {
            HStack(spacing: 7) {
                SPDFVIcon(selection.icon, size: 11)
                    .font(.system(size: 11, weight: .semibold))
                Text(selection.label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 9)
            .frame(height: 34)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance: \(selection.label)")
        .accessibilityLabel("Appearance")
        .accessibilityValue(selection.label)
    }
}

#Preview {
    ContentView()
}
