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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.window")
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
            compareDocument: {
                showNavigator(.info)
                session.compareWithPicker()
            },
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
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("document.pdf")
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
