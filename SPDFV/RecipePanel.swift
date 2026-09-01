import SwiftUI
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe.panel")
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
            .accessibilityIdentifier("recipe.close")
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
                    .accessibilityIdentifier("recipe.use-starter")
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
                RecipeCompositionDesk(
                    session: session,
                    recipe: recipe,
                    selectedStep: $selectedStep,
                    isChoosingOperation: $isChoosingOperation,
                    draggedStep: $draggedStep,
                    stepDraftError: $stepDraftError,
                    isComposing: $isComposing
                )
            } else {
                RecipeProofDesk(session: session, recipe: recipe)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe.loaded")
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

}
