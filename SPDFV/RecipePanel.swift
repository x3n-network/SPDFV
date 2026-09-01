import SwiftUI
import UniformTypeIdentifiers
import SPDFVCore

struct RecipePanel: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @ObservedObject private var library = RecipeLibraryStore.shared
    @State private var isComposing = false
    @State private var isShowingLibrary = false
    @State private var selectedStep = 0
    @State private var isChoosingOperation = false
    @State private var draggedStep: Int?
    @State private var stepDraftError: String?
    @State private var librarySearch = ""
    @State private var libraryFilter = RecipeLibraryFilter.all
    @State private var selectedLibraryEntryID: UUID?
    @State private var pendingLibraryDelete: PDFRecipeLibraryEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            if isShowingLibrary {
                recipeCabinet
            } else if let recipe = session.loadedRecipe {
                loadedRecipe(recipe)
            } else {
                emptyState
            }
        }
        .frame(
            minWidth: 390,
            idealWidth: isShowingLibrary ? 590 : (isComposing && session.loadedRecipe != nil ? 660 : 390),
            maxWidth: .infinity,
            minHeight: 430,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(SPDFVTheme.navigator)
        .animation(.snappy(duration: 0.22), value: isComposing)
        .alert("Remove recipe drawer?", isPresented: Binding(
            get: { pendingLibraryDelete != nil },
            set: { if !$0 { pendingLibraryDelete = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let entry = pendingLibraryDelete {
                    session.removeLibraryRecipe(entry.id)
                    selectedLibraryEntryID = nil
                    repairLibrarySelection()
                }
                pendingLibraryDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingLibraryDelete = nil }
        } message: {
            Text("The personal recipe and its revision history will be removed. Export JSON first if you need a recoverable copy.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RECIPES")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.35)
                Text("SAVED WORKFLOWS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            Spacer()
            if session.loadedRecipe != nil || isShowingLibrary {
                HStack(spacing: 0) {
                    modeButton("CABINET", active: isShowingLibrary) {
                        isShowingLibrary = true
                        isComposing = false
                    }
                    if session.loadedRecipe != nil {
                        modeButton("PROOF", active: !isComposing && !isShowingLibrary, enabled: stepDraftError == nil) {
                            isShowingLibrary = false
                            isComposing = false
                        }
                        modeButton("COMPOSE", active: isComposing && !isShowingLibrary) {
                            isShowingLibrary = false
                            isComposing = true
                        }
                    }
                }
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
            } else {
                Text("JSON / PDF")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            Button { isPresented = false } label: {
                SPDFVIcon(.close)
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close recipe panel")
        }
        .foregroundStyle(SPDFVTheme.navigatorText)
        .padding(16)
    }

    private func modeButton(_ title: String, active: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(active ? Color.white : SPDFVTheme.navigatorMuted)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(active ? SPDFVTheme.cobalt : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(SPDFVTheme.cobalt)
                    .frame(width: 4, height: 68)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose a recipe")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SPDFVTheme.navigatorText)
                    Text("Dry-run ordered PDF operations against this document before exporting a verified copy.")
                        .font(.system(size: 11))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button("LOAD JSON") { session.importRecipeFromPicker() }
                    .buttonStyle(RecipePanelButtonStyle(prominent: true))
                Button("USE STARTER") { session.loadStarterRecipe() }
                    .buttonStyle(RecipePanelButtonStyle(prominent: false))
                Button("CABINET") { isShowingLibrary = true }
                    .buttonStyle(RecipePanelButtonStyle(prominent: false))
            }
        }
        .padding(16)
    }

    private func loadedRecipe(_ recipe: PDFRecipe) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if isComposing {
                        TextField("Recipe name", text: Binding(
                            get: { recipe.name },
                            set: { session.renameLoadedRecipe($0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SPDFVTheme.navigatorText)
                    } else {
                        Text(recipe.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(SPDFVTheme.navigatorText)
                    }
                    Text("V\(recipe.version) · \(session.loadedRecipeName ?? "IN MEMORY")")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorFaint)
                        .lineLimit(1)
                }
                Spacer()
                if isComposing {
                    recipeUtilityButton("KEEP", icon: .archive) { session.saveLoadedRecipeToLibrary() }
                        .disabled(!canPersist(recipe))
                    recipeUtilityButton("FILE", icon: .save) { session.saveLoadedRecipe() }
                        .disabled(!canPersist(recipe))
                    recipeUtilityButton("COPY", icon: .copy) { session.copyLoadedRecipe() }
                        .disabled(!canPersist(recipe))
                    recipeUtilityButton("SHARE", icon: .share) { session.shareLoadedRecipe() }
                        .disabled(!canPersist(recipe))
                } else {
                    Button("REPLACE") { session.importRecipeFromPicker() }
                        .buttonStyle(.plain)
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.paleCobalt)
                }
            }
            .padding(14)
            .background(SPDFVTheme.navigatorInset)

            if isComposing {
                compositionDesk(recipe)
            } else {
                proofDesk(recipe)
            }
        }
        .onChange(of: recipe.steps.count) { _, count in
            selectedStep = min(selectedStep, max(0, count - 1))
        }
    }

    private func recipeUtilityButton(_ title: String, icon: SPDFVIconName, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                SPDFVIcon(icon, size: 10)
                Text(title).font(.system(size: 6.5, weight: .black, design: .monospaced))
            }
            .foregroundStyle(SPDFVTheme.paleCobalt)
            .frame(width: 38, height: 30)
        }
        .buttonStyle(.plain)
    }

    private var recipeCabinet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    SPDFVIcon(.search, size: 11)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                    TextField("Search names or operations", text: $librarySearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(SPDFVTheme.navigatorInset)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }

                Text("\(filteredLibraryEntries.count) DRAWER\(filteredLibraryEntries.count == 1 ? "" : "S")")
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            .padding(12)

            HStack(spacing: 0) {
                ForEach(RecipeLibraryFilter.allCases) { filter in
                    Button {
                        libraryFilter = filter
                        repairLibrarySelection()
                    } label: {
                        HStack(spacing: 4) {
                            SPDFVIcon(filter.icon, size: 8)
                            Text(filter.label)
                        }
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(libraryFilter == filter ? Color.white : SPDFVTheme.navigatorMuted)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(libraryFilter == filter ? SPDFVTheme.cobalt : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(filteredLibraryEntries.enumerated()), id: \.element.id) { offset, entry in
                            RecipeCabinetRow(
                                index: offset + 1,
                                entry: entry,
                                isSelected: selectedLibraryEntryID == entry.id,
                                isLoaded: session.activeLibraryRecipeID == entry.id,
                                select: { selectedLibraryEntryID = entry.id },
                                favorite: { library.toggleFavorite(entry.id) }
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(width: 282, height: 342)

                Rectangle().fill(SPDFVTheme.divider).frame(width: 1, height: 342)

                Group {
                    if let entry = selectedLibraryEntry {
                        cabinetDetail(entry)
                    } else {
                        VStack(spacing: 8) {
                            SPDFVIcon(.archive)
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(SPDFVTheme.paleCobalt)
                            Text(filteredLibraryEntries.isEmpty ? "No matching drawers" : "Choose a recipe drawer")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text(filteredLibraryEntries.isEmpty ? "Change the search or filter." : "Its revision history will appear here.")
                                .font(.system(size: 9))
                                .foregroundStyle(SPDFVTheme.navigatorMuted)
                        }
                        .foregroundStyle(SPDFVTheme.navigatorText)
                    }
                }
                .frame(width: 307, height: 342)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            HStack(spacing: 8) {
                Circle()
                    .fill(library.watchConfiguration?.isArmed == true ? Color.green : SPDFVTheme.navigatorFaint)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(watchLaneTitle)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.6)
                    Text(watchLaneDetail)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .lineLimit(1)
                }
                Spacer()
                if let configuration = library.watchConfiguration {
                    Button(configuration.isArmed ? "PAUSE" : "ARM") {
                        library.setWatchArmed(!configuration.isArmed)
                    }
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    Button("RUN") { library.runWatchNow() }
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .buttonStyle(.plain)
                        .foregroundStyle(SPDFVTheme.paleCobalt)
                    Button { library.clearWatch() } label: {
                        SPDFVIcon(.close)
                            .font(.system(size: 7, weight: .black))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .help("Disconnect watched folders")
                    .accessibilityLabel("Disconnect watched folders")
                }
                Button(library.watchConfiguration == nil ? "ARM LANE" : "REWIRE") {
                    if let selectedLibraryEntryID { session.configureRecipeWatch(selectedLibraryEntryID) }
                }
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundStyle(SPDFVTheme.paleCobalt)
                    .disabled(selectedLibraryEntryID == nil)
            }
            .foregroundStyle(SPDFVTheme.navigatorText)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(SPDFVTheme.navigatorInset)
        }
        .onAppear { repairLibrarySelection() }
        .onChange(of: librarySearch) { _, _ in repairLibrarySelection() }
        .onChange(of: library.catalog) { _, _ in repairLibrarySelection() }
    }

    private func cabinetDetail(_ entry: PDFRecipeLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.kind == .preset ? "BUILT-IN" : "PERSONAL")
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(entry.kind == .preset ? Color.orange : SPDFVTheme.paleCobalt)
                    Text(entry.recipe.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SPDFVTheme.navigatorText)
                        .lineLimit(2)
                }
                Spacer()
                if entry.kind == .personal {
                    Button { pendingLibraryDelete = entry } label: {
                        SPDFVIcon(.delete)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SPDFVTheme.redaction)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(entry.recipe.name)")
                }
                Button { library.toggleFavorite(entry.id) } label: {
                    SPDFVIcon(entry.isFavorite ? .favoriteFilled : .favorite, size: 10)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(entry.isFavorite ? Color.orange : SPDFVTheme.navigatorMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.isFavorite ? "Remove \(entry.recipe.name) from favorites" : "Add \(entry.recipe.name) to favorites")
            }
            .padding(14)

            HStack(spacing: 6) {
                cabinetMetric("R\(entry.revision)", label: "REVISION")
                cabinetMetric("\(entry.recipe.steps.count)", label: "STEPS")
                cabinetMetric("\(entry.history.count)", label: "PROOFS")
            }
            .padding(.horizontal, 14)

            HStack(spacing: 7) {
                Button("USE RECIPE") {
                    session.loadLibraryRecipe(entry.id)
                    isShowingLibrary = false
                    isComposing = false
                }
                .buttonStyle(RecipePanelButtonStyle(prominent: true))
                Button("DUPLICATE") {
                    session.duplicateLibraryRecipe(entry.id)
                    selectedLibraryEntryID = session.activeLibraryRecipeID
                }
                .buttonStyle(RecipePanelButtonStyle(prominent: false))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1).padding(.top, 12)

            VStack(alignment: .leading, spacing: 7) {
                Text("REVISION HISTORY")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)

                HStack {
                    Text("R\(entry.revision) · CURRENT")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                    Spacer()
                    Text(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorFaint)
                }
                .padding(8)
                .background(SPDFVTheme.controlPressed)
                .overlay(alignment: .leading) { Rectangle().fill(SPDFVTheme.cobalt).frame(width: 2) }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(entry.history.reversed()) { revision in
                            HStack(spacing: 7) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("R\(revision.revision) · \(revision.recipe.steps.count) STEPS")
                                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                                    Text(revision.savedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 7.5, design: .monospaced))
                                        .foregroundStyle(SPDFVTheme.navigatorFaint)
                                }
                                Spacer()
                                Button("RESTORE") {
                                    session.restoreLibraryRevision(revision.id, entryID: entry.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                                .foregroundStyle(SPDFVTheme.paleCobalt)
                            }
                            .padding(8)
                            .background(SPDFVTheme.navigatorInset)
                        }
                    }
                }
                .frame(maxHeight: 92)
            }
            .padding(14)
            Spacer(minLength: 0)
        }
    }

    private func cabinetMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 12, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 6.5, weight: .black, design: .monospaced)).foregroundStyle(SPDFVTheme.navigatorFaint)
        }
        .foregroundStyle(SPDFVTheme.navigatorText)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(SPDFVTheme.navigatorInset)
        .overlay { Rectangle().stroke(SPDFVTheme.divider.opacity(0.7), lineWidth: 1) }
    }

    private var filteredLibraryEntries: [PDFRecipeLibraryEntry] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.entries.filter { entry in
            let matchesFilter = switch libraryFilter {
            case .all: true
            case .favorites: entry.isFavorite
            case .personal: entry.kind == .personal
            case .presets: entry.kind == .preset
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            let haystack = ([entry.recipe.name] + entry.recipe.steps.map { "\($0.operation) \($0.summary)" }).joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedLibraryEntry: PDFRecipeLibraryEntry? {
        guard let selectedLibraryEntryID else { return nil }
        return filteredLibraryEntries.first { $0.id == selectedLibraryEntryID }
    }

    private func repairLibrarySelection() {
        if !filteredLibraryEntries.contains(where: { $0.id == selectedLibraryEntryID }) {
            selectedLibraryEntryID = filteredLibraryEntries.first?.id
        }
    }

    private var watchLaneTitle: String {
        guard let configuration = library.watchConfiguration else { return "WATCH LANE UNARMED" }
        return configuration.isArmed ? "WATCH LANE ARMED" : "WATCH LANE PAUSED"
    }

    private var watchLaneDetail: String {
        guard let configuration = library.watchConfiguration else {
            return "Select a drawer, then connect input and output folders"
        }
        return "\(configuration.inputName) → \(configuration.outputName) · \(library.watchStatus)"
    }

    private func proofDesk(_ recipe: PDFRecipe) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { offset, step in
                        RecipeStepRow(index: offset + 1, step: step, isLast: offset == recipe.steps.count - 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(height: min(CGFloat(recipe.steps.count * 48 + 16), 230))

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            verificationPlate
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            HStack(spacing: 8) {
                Button(session.isRunningRecipe ? "CHECKING…" : "DRY RUN") { session.validateLoadedRecipe() }
                    .buttonStyle(RecipePanelButtonStyle(prominent: false))
                    .disabled(session.isRunningRecipe)
                Button(session.isRunningRecipe ? "PROCESSING…" : "EXPORT PDF") { session.exportLoadedRecipe() }
                    .buttonStyle(RecipePanelButtonStyle(prominent: true))
                    .disabled(session.isRunningRecipe)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Button(session.isRunningRecipe ? "FEEDING FOLDER…" : "PROCESS FOLDER") {
                session.processRecipeFolder()
            }
            .buttonStyle(RecipePanelButtonStyle(prominent: false))
            .disabled(session.isRunningRecipe)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
    }

    private func compositionDesk(_ recipe: PDFRecipe) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("STEPS")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                        Spacer()
                        Text("DRAG TO REORDER")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.navigatorFaint)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)

                    Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

                    if recipe.steps.isEmpty {
                        VStack(spacing: 8) {
                            SPDFVIcon(.noteAdd)
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(SPDFVTheme.paleCobalt)
                            Text("No steps yet")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text("Add the first operation to begin.")
                                .font(.system(size: 9))
                                .foregroundStyle(SPDFVTheme.navigatorMuted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(SPDFVTheme.navigatorText)
                    } else {
                        ScrollView {
                            VStack(spacing: 3) {
                                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { offset, step in
                                    RecipeComposerStepRow(
                                        index: offset,
                                        step: step,
                                        isSelected: selectedStep == offset,
                                        canDelete: true,
                                        canMoveUp: offset > 0,
                                        canMoveDown: offset < recipe.steps.count - 1,
                                        select: {
                                            selectedStep = offset
                                            isChoosingOperation = false
                                            stepDraftError = nil
                                        },
                                        moveUp: {
                                            session.moveRecipeStep(from: offset, to: offset - 1)
                                            selectedStep = offset - 1
                                        },
                                        moveDown: {
                                            session.moveRecipeStep(from: offset, to: offset + 1)
                                            selectedStep = offset + 1
                                        },
                                        remove: { session.removeRecipeStep(at: offset) }
                                    )
                                    .onDrag {
                                        draggedStep = offset
                                        return NSItemProvider(object: String(offset) as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.plainText],
                                        delegate: RecipeStepDropDelegate(
                                            destination: offset,
                                            draggedStep: $draggedStep,
                                            selectedStep: $selectedStep,
                                            move: session.moveRecipeStep
                                        )
                                    )
                                }
                            }
                            .padding(8)
                        }
                    }

                    Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
                    Button {
                        isChoosingOperation.toggle()
                    } label: {
                        HStack {
                            SPDFVIcon(isChoosingOperation ? .close : .add)
                            Text(isChoosingOperation ? "CANCEL PLATE" : "ADD OPERATION")
                            Spacer()
                            Text("\(recipe.steps.count) / 100")
                                .foregroundStyle(SPDFVTheme.navigatorFaint)
                        }
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.paleCobalt)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                    .disabled(recipe.steps.count >= 100)
                }
                .frame(width: 278, height: 360)

                Rectangle().fill(SPDFVTheme.divider).frame(width: 1, height: 360)

                Group {
                    if isChoosingOperation {
                        operationPalette(recipe)
                    } else if recipe.steps.indices.contains(selectedStep) {
                        RecipeStepEditor(
                            index: selectedStep,
                            step: recipe.steps[selectedStep],
                            update: { session.updateRecipeStep(at: selectedStep, to: $0) },
                            validationChanged: { stepDraftError = $0 }
                        )
                        .id("\(selectedStep)-\(recipe.steps[selectedStep].operation)")
                    } else {
                        Text("Choose an operation from the plate catalog.")
                            .font(.system(size: 10))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 381, height: 360)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            compositionStatus(recipe)
        }
    }

    private func operationPalette(_ recipe: PDFRecipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PLATE CATALOG")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(0.9)
                Text("Assertions stop a run. Actions change the PDF.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2), spacing: 7) {
                ForEach(RecipeOperationKind.allCases) { operation in
                    Button {
                        let insertion = recipe.steps.isEmpty ? nil : selectedStep
                        session.addRecipeStep(operation.defaultStep, after: insertion)
                        selectedStep = recipe.steps.isEmpty ? 0 : min(selectedStep + 1, recipe.steps.count)
                        isChoosingOperation = false
                        stepDraftError = nil
                    } label: {
                        HStack(spacing: 8) {
                            SPDFVIcon(operation.icon, size: 12)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(operation.isAssertion ? Color.orange : SPDFVTheme.paleCobalt)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(operation.title)
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                Text(operation.isAssertion ? "ASSERTION" : "ACTION")
                                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(SPDFVTheme.navigatorText)
                        .padding(.horizontal, 9)
                        .frame(height: 44)
                        .background(SPDFVTheme.navigatorInset)
                        .overlay { Rectangle().stroke(SPDFVTheme.divider.opacity(0.75), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .foregroundStyle(SPDFVTheme.navigatorText)
    }

    private func compositionStatus(_ recipe: PDFRecipe) -> some View {
        let error = stepDraftError ?? recipeValidationError(recipe)
        return HStack(spacing: 9) {
            Circle()
                .fill(error == nil ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(error == nil ? "COMPOSITION VALID" : "COMPOSITION NEEDS INPUT")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.6)
                Text(error ?? "Ready to save, share, validate, or run")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .lineLimit(1)
            }
            Spacer()
            Button("PROOF IT") { isComposing = false }
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(SPDFVTheme.paleCobalt)
                .disabled(error != nil)
        }
        .foregroundStyle(SPDFVTheme.navigatorText)
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(SPDFVTheme.navigatorInset)
    }

    private func recipeValidationError(_ recipe: PDFRecipe) -> String? {
        do {
            try PDFRecipeRunner.validate(recipe)
            return nil
        } catch {
            return (error as? PDFOperationError)?.description ?? error.localizedDescription
        }
    }

    private func canPersist(_ recipe: PDFRecipe) -> Bool {
        stepDraftError == nil && recipeValidationError(recipe) == nil
    }

    private var verificationPlate: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(verificationColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(verificationTitle)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(SPDFVTheme.navigatorText)
                Text(verificationDetail)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            Spacer()
            if let batch = session.batchRecipeReport {
                Text("\(batch.passedCount) / \(batch.inputCount)")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            } else if let report = session.recipeReport {
                Text("\(report.inputPageCount) → \(report.outputPageCount) PGS")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(SPDFVTheme.navigatorInset)
    }

    private var verificationTitle: String {
        if let batch = session.batchRecipeReport {
            return batch.failedCount == 0 ? "BATCH VERIFIED" : "BATCH NEEDS REVIEW"
        }
        if session.lastRecipeOutputURL != nil { return "OUTPUT VERIFIED" }
        if session.recipeReport != nil { return "DRY RUN PASSED" }
        return "AWAITING PROOF"
    }

    private var verificationDetail: String {
        if let batch = session.batchRecipeReport {
            let directory = session.lastBatchOutputDirectory?.lastPathComponent ?? "OUTPUT FOLDER"
            return "\(batch.passedCount) passed · \(batch.failedCount) stopped · \(directory)"
        }
        if let url = session.lastRecipeOutputURL { return url.lastPathComponent }
        if let report = session.recipeReport {
            return "\(report.steps.count) steps · \(report.formGate == nil ? "PDF CHECK" : "FORM GATE PASS")"
        }
        return "Run without writing to validate every step"
    }

    private var verificationColor: Color {
        if let batch = session.batchRecipeReport {
            return batch.failedCount == 0 ? Color.green : Color.orange
        }
        return session.recipeReport == nil ? SPDFVTheme.navigatorFaint : Color.green
    }
}

private enum RecipeLibraryFilter: String, CaseIterable, Identifiable {
    case all, favorites, personal, presets

    var id: Self { self }
    var label: String {
        switch self {
        case .all: "ALL"
        case .favorites: "STARRED"
        case .personal: "MINE"
        case .presets: "PRESETS"
        }
    }
    var icon: SPDFVIconName {
        switch self {
        case .all: .archive
        case .favorites: .favoriteFilled
        case .personal: .select
        case .presets: .check
        }
    }
}

private struct RecipeCabinetRow: View {
    let index: Int
    let entry: PDFRecipeLibraryEntry
    let isSelected: Bool
    let isLoaded: Bool
    let select: () -> Void
    let favorite: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", index))
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : SPDFVTheme.navigatorMuted)
                        .frame(width: 25, height: 25)
                        .background(isSelected ? SPDFVTheme.cobalt : SPDFVTheme.navigatorInset)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(entry.recipe.name)
                                .font(.system(size: 9.5, weight: .semibold))
                                .lineLimit(1)
                            if isLoaded {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                            }
                        }
                        Text("\(entry.kind == .preset ? "PRESET" : "R\(entry.revision)") · \(entry.recipe.steps.count) STEPS")
                            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.navigatorFaint)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(entry.recipe.name)")

            Button(action: favorite) {
                SPDFVIcon(entry.isFavorite ? .favoriteFilled : .favorite, size: 9)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(entry.isFavorite ? Color.orange : SPDFVTheme.navigatorFaint)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isFavorite ? "Remove \(entry.recipe.name) from favorites" : "Add \(entry.recipe.name) to favorites")
        }
        .foregroundStyle(SPDFVTheme.navigatorText)
        .padding(.horizontal, 7)
        .frame(height: 45)
        .background(isSelected ? SPDFVTheme.controlPressed : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? SPDFVTheme.cobalt : Color.clear).frame(width: 2)
        }
    }
}

private struct RecipeComposerStepRow: View {
    let index: Int
    let step: PDFRecipeStep
    let isSelected: Bool
    let canDelete: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 8) {
                    SPDFVIcon(.drag, size: 8)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SPDFVTheme.navigatorFaint)
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : SPDFVTheme.navigatorMuted)
                        .frame(width: 25, height: 25)
                        .background(isSelected ? SPDFVTheme.cobalt : SPDFVTheme.navigatorInset)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.operation.uppercased())
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .foregroundStyle(isSelected ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorMuted)
                        Text(step.summary)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(SPDFVTheme.navigatorText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected && canDelete {
                Button(action: moveUp) {
                    SPDFVIcon(.up, size: 7)
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 16, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .disabled(!canMoveUp)

                Button(action: moveDown) {
                    SPDFVIcon(.down, size: 7)
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 16, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .disabled(!canMoveDown)

                Button(action: remove) {
                    SPDFVIcon(.delete, size: 9)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SPDFVTheme.redaction)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 45)
        .background(isSelected ? SPDFVTheme.controlPressed : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? SPDFVTheme.cobalt : Color.clear).frame(width: 2)
        }
    }
}

private struct RecipeStepDropDelegate: DropDelegate {
    let destination: Int
    @Binding var draggedStep: Int?
    @Binding var selectedStep: Int
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let source = draggedStep, source != destination else { return }
        move(source, destination)
        draggedStep = destination
        selectedStep = destination
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedStep = nil
        return true
    }
}

private enum RecipeOperationKind: String, CaseIterable, Identifiable {
    case assertPageCount, assertText, assertFields, assertFormGate
    case renameField, fillForm, rotate, crop, extract

    var id: Self { self }
    var isAssertion: Bool { rawValue.hasPrefix("assert") }

    var title: String {
        switch self {
        case .assertPageCount: "PAGE COUNT"
        case .assertText: "TEXT CHECK"
        case .assertFields: "FIELD CHECK"
        case .assertFormGate: "FORM GATE"
        case .renameField: "RENAME FIELD"
        case .fillForm: "FILL FORM"
        case .rotate: "ROTATE"
        case .crop: "CROP"
        case .extract: "EXTRACT"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .assertPageCount: .pageCount
        case .assertText: .search
        case .assertFields: .list
        case .assertFormGate: .check
        case .renameField: .textCursor
        case .fillForm: .editField
        case .rotate: .rotateRight
        case .crop: .crop
        case .extract: .extract
        }
    }

    var defaultStep: PDFRecipeStep {
        switch self {
        case .assertPageCount: .assertPageCount(minimum: 1, maximum: nil)
        case .assertText: .assertText(contains: ["Required text"], excludes: [])
        case .assertFields: .assertFields(names: ["field.name"])
        case .assertFormGate: .assertFormGate(maximum: .pass)
        case .renameField: .renameField(from: "old.name", to: "new.name")
        case .fillForm: .fillForm(values: ["field.name": "Value"])
        case .rotate: .rotate(pages: "all", degrees: 90)
        case .crop: .crop(pages: "all", insets: .zero)
        case .extract: .extract(pages: "all")
        }
    }
}

private struct RecipeStepDraft: Equatable {
    var primary = ""
    var secondary = ""
    var tertiary = ""
    var quaternary = ""
    var pages = "all"
    var degree = "90"
    var gate = PDFFormGateLevel.pass.rawValue

    init(_ step: PDFRecipeStep) {
        switch step {
        case .renameField(let from, let to):
            primary = from; secondary = to
        case .fillForm(let values):
            primary = values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        case .rotate(let selection, let degrees):
            pages = selection; degree = String(degrees)
        case .crop(let selection, let insets):
            pages = selection
            primary = Self.number(insets.top); secondary = Self.number(insets.right)
            tertiary = Self.number(insets.bottom); quaternary = Self.number(insets.left)
        case .extract(let selection):
            pages = selection
        case .assertPageCount(let minimum, let maximum):
            primary = minimum.map(String.init) ?? ""; secondary = maximum.map(String.init) ?? ""
        case .assertText(let contains, let excludes):
            primary = contains.joined(separator: ", "); secondary = excludes.joined(separator: ", ")
        case .assertFields(let names):
            primary = names.joined(separator: ", ")
        case .assertFormGate(let maximum):
            gate = maximum.rawValue
        }
    }

    func resolved(for original: PDFRecipeStep) -> PDFRecipeStep? {
        switch original {
        case .renameField:
            guard !trim(primary).isEmpty, !trim(secondary).isEmpty else { return nil }
            return .renameField(from: trim(primary), to: trim(secondary))
        case .fillForm:
            guard let values = formValues, !values.isEmpty else { return nil }
            return .fillForm(values: values)
        case .rotate:
            guard !trim(pages).isEmpty, let degrees = Int(degree) else { return nil }
            return .rotate(pages: trim(pages), degrees: degrees)
        case .crop:
            guard !trim(pages).isEmpty,
                  let top = Double(primary), let right = Double(secondary),
                  let bottom = Double(tertiary), let left = Double(quaternary),
                  [top, right, bottom, left].min() ?? -1 >= 0 else { return nil }
            return .crop(pages: trim(pages), insets: PDFEdgeInsets(top: top, right: right, bottom: bottom, left: left))
        case .extract:
            guard !trim(pages).isEmpty else { return nil }
            return .extract(pages: trim(pages))
        case .assertPageCount:
            let minimumText = trim(primary), maximumText = trim(secondary)
            guard minimumText.isEmpty || Int(minimumText) != nil,
                  maximumText.isEmpty || Int(maximumText) != nil else { return nil }
            let minimum = minimumText.isEmpty ? nil : Int(minimumText)
            let maximum = maximumText.isEmpty ? nil : Int(maximumText)
            guard minimum != nil || maximum != nil,
                  minimum.map({ $0 >= 0 }) ?? true,
                  maximum.map({ $0 >= 0 }) ?? true,
                  minimum == nil || maximum == nil || minimum! <= maximum! else { return nil }
            return .assertPageCount(minimum: minimum, maximum: maximum)
        case .assertText:
            let contains = list(primary), excludes = list(secondary)
            guard !contains.isEmpty || !excludes.isEmpty else { return nil }
            return .assertText(contains: contains, excludes: excludes)
        case .assertFields:
            let names = list(primary)
            guard !names.isEmpty else { return nil }
            return .assertFields(names: names)
        case .assertFormGate:
            guard let level = PDFFormGateLevel(rawValue: gate) else { return nil }
            return .assertFormGate(maximum: level)
        }
    }

    func validationMessage(for original: PDFRecipeStep) -> String {
        guard resolved(for: original) == nil else { return "Parameters ready" }
        return switch original {
        case .renameField: "Both field names are required"
        case .fillForm: "Use one field=value pair per line"
        case .rotate: "Pages and an integer angle are required"
        case .crop: "Pages and four non-negative inset values are required"
        case .extract: "Enter all, a page, or a page range"
        case .assertPageCount: "Set a valid minimum, maximum, or both"
        case .assertText: "Enter required or forbidden text"
        case .assertFields: "Enter at least one field name"
        case .assertFormGate: "Choose the highest allowed gate level"
        }
    }

    private var formValues: [String: String]? {
        var values: [String: String] = [:]
        for line in primary.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, !trim(pair[0]).isEmpty else { return nil }
            values[trim(pair[0])] = trim(pair[1])
        }
        return values
    }

    private func list(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0.isNewline }).map { trim(String($0)) }.filter { !$0.isEmpty }
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

private struct RecipeStepEditor: View {
    let index: Int
    let step: PDFRecipeStep
    let update: (PDFRecipeStep) -> Void
    let validationChanged: (String?) -> Void
    @State private var draft: RecipeStepDraft

    init(
        index: Int,
        step: PDFRecipeStep,
        update: @escaping (PDFRecipeStep) -> Void,
        validationChanged: @escaping (String?) -> Void
    ) {
        self.index = index
        self.step = step
        self.update = update
        self.validationChanged = validationChanged
        _draft = State(initialValue: RecipeStepDraft(step))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CALIBRATION \(String(format: "%02d", index + 1))")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                    Text(step.operation)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(SPDFVTheme.navigatorText)
                }
                Spacer()
                SPDFVIcon(RecipeOperationKind(rawValue: step.operation)?.icon ?? .controls, size: 18)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            ScrollView {
                editorFields
                    .padding(14)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            HStack(spacing: 8) {
                Circle()
                    .fill(draft.resolved(for: step) == nil ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(draft.validationMessage(for: step).uppercased())
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(SPDFVTheme.navigatorInset)
        }
        .onChange(of: draft) { _, value in
            if let resolved = value.resolved(for: step) {
                validationChanged(nil)
                update(resolved)
            } else {
                validationChanged(value.validationMessage(for: step))
            }
        }
        .onAppear {
            validationChanged(draft.resolved(for: step) == nil ? draft.validationMessage(for: step) : nil)
        }
    }

    @ViewBuilder private var editorFields: some View {
        switch step {
        case .renameField:
            RecipeField(label: "SOURCE FIELD", hint: "Exact existing field name") {
                recipeTextField("full_name", text: $draft.primary)
            }
            RecipeArrow()
            RecipeField(label: "DESTINATION FIELD", hint: "New canonical field name") {
                recipeTextField("review.owner", text: $draft.secondary)
            }
        case .fillForm:
            RecipeField(label: "FIELD VALUES", hint: "One field=value pair per line") {
                TextEditor(text: $draft.primary)
                    .font(.system(size: 10, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 116)
                    .background(SPDFVTheme.navigatorInset)
                    .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
            }
        case .rotate:
            pagesField
            RecipeField(label: "TURN", hint: "Clockwise degrees") {
                Picker("", selection: $draft.degree) {
                    ForEach(["0", "90", "180", "270"], id: \.self) { Text("\($0)°").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        case .crop:
            pagesField
            Text("INSETS · POINTS")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
            HStack(spacing: 7) {
                insetField("TOP", text: $draft.primary)
                insetField("RIGHT", text: $draft.secondary)
                insetField("BOTTOM", text: $draft.tertiary)
                insetField("LEFT", text: $draft.quaternary)
            }
        case .extract:
            pagesField
            RecipeNote("Only selected pages continue to later steps.")
        case .assertPageCount:
            HStack(spacing: 9) {
                RecipeField(label: "MINIMUM", hint: "Optional") { recipeTextField("1", text: $draft.primary) }
                RecipeField(label: "MAXIMUM", hint: "Optional") { recipeTextField("12", text: $draft.secondary) }
            }
        case .assertText:
            RecipeField(label: "MUST CONTAIN", hint: "Comma-separated phrases") {
                recipeTextField("Invoice, Approved", text: $draft.primary)
            }
            RecipeField(label: "MUST NOT CONTAIN", hint: "Comma-separated phrases") {
                recipeTextField("Draft, Confidential", text: $draft.secondary)
            }
        case .assertFields:
            RecipeField(label: "REQUIRED FIELDS", hint: "Comma-separated exact names") {
                recipeTextField("full_name, approved", text: $draft.primary)
            }
        case .assertFormGate:
            RecipeField(label: "HIGHEST ALLOWED LEVEL", hint: "The run stops above this level") {
                Picker("", selection: $draft.gate) {
                    ForEach(PDFFormGateLevel.allCases, id: \.rawValue) { Text($0.rawValue.uppercased()).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var pagesField: some View {
        RecipeField(label: "PAGES", hint: "all · 1,3,5 · 2-6") {
            recipeTextField("all", text: $draft.pages)
        }
    }

    private func insetField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 6.5, weight: .black, design: .monospaced)).foregroundStyle(SPDFVTheme.navigatorFaint)
            recipeTextField("0", text: text)
        }
    }

    private func recipeTextField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(SPDFVTheme.navigatorText)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(SPDFVTheme.navigatorInset)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
    }
}

private struct RecipeField<Content: View>: View {
    let label: String
    let hint: String
    let content: Content

    init(label: String, hint: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                Spacer()
                Text(hint)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
            }
            content
        }
        .padding(.bottom, 12)
    }
}

private struct RecipeArrow: View {
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            SPDFVIcon(.down, size: 8).foregroundStyle(SPDFVTheme.paleCobalt)
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
        .padding(.bottom, 12)
    }
}

private struct RecipeNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(SPDFVTheme.navigatorMuted)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SPDFVTheme.navigatorInset)
            .overlay(alignment: .leading) { Rectangle().fill(SPDFVTheme.cobalt).frame(width: 2) }
    }
}

private struct RecipeStepRow: View {
    let index: Int
    let step: PDFRecipeStep
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(SPDFVTheme.cobalt)
                if !isLast {
                    Rectangle().fill(SPDFVTheme.cobalt.opacity(0.45)).frame(width: 1, height: 24)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.operation.uppercased())
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.paleCobalt)
                Text(step.summary)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .lineLimit(2)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(minHeight: isLast ? 34 : 48, alignment: .top)
    }
}

private struct RecipePanelButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(prominent ? Color.white : SPDFVTheme.navigatorText)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(prominent ? SPDFVTheme.cobalt.opacity(configuration.isPressed ? 0.72 : 1) : Color.clear)
            .overlay { Rectangle().stroke(prominent ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.48)
    }
}

