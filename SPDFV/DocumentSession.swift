import Combine
import Foundation
import PDFKit
import AppKit
import SPDFVCore
import UniformTypeIdentifiers

@MainActor
final class DocumentSession: ObservableObject {
    let recoveryID = UUID()
    @Published private(set) var document: PDFDocument?
    @Published private(set) var fileURL: URL?
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var selectedPageIndices: Set<Int> = []
    @Published private(set) var scaleFactor: CGFloat = 1
    @Published private(set) var pageLayout: PageLayoutMode
    @Published var thumbnailsVisible = true
    @Published var navigatorMode: NavigatorMode = .pages
    @Published var searchText = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var outlineEntries: [OutlineEntry] = []
    @Published private(set) var documentDetails: DocumentDetails?
    @Published private(set) var recentDocuments: [URL] = []
    @Published private(set) var hasTextSelection = false
    @Published private(set) var isDirty = false
    @Published private(set) var canUndoAnnotation = false
    @Published private(set) var annotationCount = 0
    @Published private(set) var annotationRecords: [AnnotationRecord] = []
    @Published private(set) var formFields: [PDFFormFieldReport] = []
    @Published private(set) var formGate: PDFFormGateReport?
    @Published private(set) var selectedFormField: FormFieldSelection?
    @Published private(set) var loadedRecipe: PDFRecipe?
    @Published private(set) var loadedRecipeName: String?
    @Published private(set) var activeLibraryRecipeID: UUID?
    @Published private(set) var recipeReport: PDFRecipeReport?
    @Published private(set) var lastRecipeOutputURL: URL?
    @Published private(set) var batchRecipeReport: PDFRecipeBatchReport?
    @Published private(set) var lastBatchOutputDirectory: URL?
    @Published private(set) var isRunningRecipe = false
    @Published private(set) var signatureDraft: SignatureDraft?
    @Published private(set) var pendingFormFieldDraft: PDFFormFieldDraft?
    @Published var activeAnnotationTool: CanvasAnnotationTool = .select
    @Published private(set) var isCropEditing = false
    @Published private(set) var selectedAnnotation: AnnotationSelection?
    @Published private(set) var pendingOpenURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var pendingCommand: ViewerCommand?
    @Published private(set) var isPerformingOCR = false
    @Published private(set) var ocrStatusMessage: String?
    @Published private(set) var lastOCRReport: PDFOCRReport?
    @Published private(set) var lastOCROutputURL: URL?
    @Published private(set) var pendingRedactions: [PendingRedaction] = []
    @Published private(set) var isRedactionEditing = false
    @Published private(set) var isSanitizingRedactions = false
    @Published private(set) var redactionStatusMessage: String?
    @Published private(set) var lastRedactionReport: PDFRedactionReport?

    private var securityScopedURL: URL?
    private let cachedThumbnails: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    private var searchSelections: [PDFSelection] = []
    private var annotationUndoStack: [AnnotationUndoOperation] = []
    private var pendingStyleEdit: (entry: AnnotationEntry, snapshot: AnnotationSnapshot)?
    private var pageSelectionAnchor: Int?
    private let pagePositionKey = "spdfv.document-page-position.v1"

    init() {
        let savedLayout = UserDefaults.standard.string(forKey: "pageLayoutMode")
        pageLayout = PageLayoutMode(rawValue: savedLayout ?? "") ?? .continuous
        refreshRecentDocuments()
    }

    var zoomLabel: String {
        "\(Int((scaleFactor * 100).rounded()))%"
    }

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "SPDFV"
    }

    func open(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else {
            errorMessage = "Choose a file with the .pdf extension."
            return
        }

        if isDirty, document != nil, url != fileURL {
            pendingOpenURL = url
            return
        }

        load(url)
    }

    func resolvePendingOpen(savingChanges: Bool) {
        guard let url = pendingOpenURL else { return }

        if savingChanges, !save() {
            return
        }

        pendingOpenURL = nil
        load(url)
    }

    func cancelPendingOpen() {
        pendingOpenURL = nil
    }

    private func load(_ url: URL) {

        releaseSecurityScopedResource()
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        guard let pdf = PDFDocument(url: url) else {
            releaseSecurityScopedResource()
            errorMessage = "“\(url.lastPathComponent)” is not a readable PDF."
            return
        }

        document = pdf
        fileURL = url
        pageCount = pdf.pageCount
        let restoredPage = restoredPageIndex(for: url, pageCount: pdf.pageCount)
        pageIndex = restoredPage
        selectedPageIndices = pdf.pageCount > 0 ? [restoredPage] : []
        pageSelectionAnchor = pdf.pageCount > 0 ? restoredPage : nil
        searchText = ""
        searchResults = []
        searchSelections = []
        cachedThumbnails.removeAllObjects()
        outlineEntries = Self.flattenOutline(pdf.outlineRoot, document: pdf)
        documentDetails = Self.makeDocumentDetails(document: pdf, url: url)
        annotationUndoStack = []
        pendingStyleEdit = nil
        canUndoAnnotation = false
        annotationCount = (0..<pdf.pageCount).reduce(into: 0) { count, index in
            count += pdf.page(at: index)?.annotations.filter { !$0.isFormWidget }.count ?? 0
        }
        refreshAnnotationRecords()
        refreshFormFields()
        recipeReport = nil
        lastRecipeOutputURL = nil
        batchRecipeReport = nil
        lastBatchOutputDirectory = nil
        activeAnnotationTool = .select
        pendingFormFieldDraft = nil
        signatureDraft = nil
        isCropEditing = false
        isRedactionEditing = false
        pendingRedactions = []
        redactionStatusMessage = nil
        lastRedactionReport = nil
        selectedAnnotation = nil
        selectedFormField = nil
        markClean()
        hasTextSelection = false
        errorMessage = nil
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecentDocuments()
        if restoredPage > 0 {
            perform(.goToPage(restoredPage))
        }
    }

    func perform(_ action: ViewerAction) {
        pendingCommand = ViewerCommand(action: action)
    }

    func updatePage(index: Int) {
        let updatedIndex = max(0, min(index, max(0, pageCount - 1)))
        pageIndex = updatedIndex
        if selectedPageIndices.count <= 1 {
            selectedPageIndices = pageCount > 0 ? [updatedIndex] : []
            pageSelectionAnchor = pageCount > 0 ? updatedIndex : nil
        }
        savePagePosition(updatedIndex)
    }

    func updateScale(_ scale: CGFloat) {
        scaleFactor = scale
    }

    func updateSelection(hasText: Bool) {
        hasTextSelection = hasText
    }

    func setPageLayout(_ layout: PageLayoutMode) {
        guard pageLayout != layout else { return }
        pageLayout = layout
        UserDefaults.standard.set(layout.rawValue, forKey: "pageLayoutMode")
        perform(.setPageLayout(layout))
    }

    func thumbnail(for pageIndex: Int) -> NSImage? {
        let key = NSNumber(value: pageIndex)
        if let cached = cachedThumbnails.object(forKey: key) {
            return cached
        }
        guard let page = document?.page(at: pageIndex) else { return nil }
        let thumbnail = page.thumbnail(of: NSSize(width: 136, height: 176), for: .cropBox)
        let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
        cachedThumbnails.setObject(thumbnail, forKey: key, cost: cost)
        return thumbnail
    }

    func goToPage(_ index: Int) {
        perform(.goToPage(index))
    }

    func selectPage(_ index: Int, extendingRange: Bool = false, toggling: Bool = false) {
        guard (0..<pageCount).contains(index) else { return }

        if extendingRange {
            let anchor = pageSelectionAnchor ?? pageIndex
            selectedPageIndices = Set(min(anchor, index)...max(anchor, index))
        } else if toggling {
            if selectedPageIndices.contains(index) {
                selectedPageIndices.remove(index)
            } else {
                selectedPageIndices.insert(index)
            }
            pageSelectionAnchor = index
        } else {
            selectedPageIndices = [index]
            pageSelectionAnchor = index
        }

        pageIndex = index
        perform(.goToPage(index))
    }

    func selectAllPages() {
        selectedPageIndices = Set(0..<pageCount)
        pageSelectionAnchor = pageIndex
    }

    func selectPages(matching parity: PageParity) {
        selectedPageIndices = Set((0..<pageCount).filter { parity.matches(pageNumber: $0 + 1) })
        pageSelectionAnchor = selectedPageIndices.sorted().first
    }

    func clearPageSelection() {
        selectedPageIndices = []
        pageSelectionAnchor = nil
    }

    var pageOperationIndices: [Int] {
        let selected = selectedPageIndices.sorted()
        return selected.isEmpty && pageCount > 0 ? [pageIndex] : selected
    }

    func addMarkup(_ kind: MarkupKind) {
        guard hasTextSelection else {
            errorMessage = "Select text in the document before adding markup."
            return
        }
        perform(.addMarkup(kind))
    }

    func setAnnotationTool(_ tool: CanvasAnnotationTool) {
        if tool == .signature, signatureDraft == nil {
            errorMessage = "Draw a signature in the Fields panel before placing it."
            navigatorMode = .forms
            thumbnailsVisible = true
            return
        }
        if tool == .formField, pendingFormFieldDraft == nil {
            errorMessage = "Prepare a field in the Build bench before placing it."
            navigatorMode = .forms
            thumbnailsVisible = true
            return
        }
        activeAnnotationTool = tool
        if tool != .select {
            selectedAnnotation = nil
            selectedFormField = nil
        }
    }

    func applyFormValue(_ value: String, to field: PDFFormFieldReport) {
        guard let document else { return }
        do {
            try PDFOperations.applyFormValue(value, named: field.name, in: document)
            markDirty()
            refreshFormFields()
            let pages = formFields.filter { $0.name == field.name }.map { $0.page - 1 }
            perform(.annotationsChanged(Array(Set(pages)).sorted()))
        } catch {
            errorMessage = "The field could not be updated: \(error.localizedDescription)"
        }
    }

    func showFormField(_ field: PDFFormFieldReport) {
        guard
            let page = document?.page(at: field.page - 1),
            let annotation = page.annotations.first(where: {
                $0.isFormWidget && $0.fieldName == field.name && PDFRectReport($0.bounds) == field.bounds
            }) ?? page.annotations.first(where: { $0.isFormWidget && $0.fieldName == field.name })
        else { return }
        activeAnnotationTool = .select
        selectedAnnotation = nil
        selectedFormField = FormFieldSelection(annotation: annotation, page: page, pageIndex: field.page - 1)
        goToPage(field.page - 1)
    }

    func deleteSelectedFormField() {
        guard let selectedFormField else { return }
        let entry = selectedFormField.entry
        entry.page.removeAnnotation(entry.annotation)
        annotationUndoStack.append(.formFieldRemoved(entry))
        canUndoAnnotation = true
        self.selectedFormField = nil
        markDirty()
        cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        refreshFormFields()
        perform(.annotationsChanged([entry.pageIndex]))
    }

    func registerFormFieldTransform(
        annotation: PDFAnnotation,
        page: PDFPage,
        pageIndex: Int,
        previousBounds: CGRect
    ) {
        guard annotation.bounds != previousBounds else { return }
        let entry = AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
        var snapshot = AnnotationSnapshot(annotation)
        snapshot.bounds = previousBounds
        annotationUndoStack.append(.formFieldModified(entry, snapshot))
        canUndoAnnotation = true
        markDirty()
        cachedThumbnails.removeObject(forKey: NSNumber(value: pageIndex))
        refreshFormFields()
        perform(.annotationsChanged([pageIndex]))
    }

    func updateSelectedFormFieldBounds(_ proposedBounds: CGRect) {
        guard let selectedFormField else { return }
        let pageBounds = selectedFormField.page.bounds(for: .cropBox)
        let width = min(max(16, proposedBounds.width), pageBounds.width)
        let height = min(max(16, proposedBounds.height), pageBounds.height)
        let x = min(max(proposedBounds.minX, pageBounds.minX), pageBounds.maxX - width)
        let y = min(max(proposedBounds.minY, pageBounds.minY), pageBounds.maxY - height)
        let clamped = CGRect(x: x, y: y, width: width, height: height)
        let previousBounds = selectedFormField.annotation.bounds
        guard clamped != previousBounds else { return }
        selectedFormField.annotation.bounds = clamped
        selectedFormField.annotation.modificationDate = Date()
        registerFormFieldTransform(
            annotation: selectedFormField.annotation,
            page: selectedFormField.page,
            pageIndex: selectedFormField.pageIndex,
            previousBounds: previousBounds
        )
    }

    func nudgeSelectedObject(horizontal: CGFloat, vertical: CGFloat) {
        if let selectedFormField {
            updateSelectedFormFieldBounds(selectedFormField.annotation.bounds.offsetBy(dx: horizontal, dy: vertical))
        } else {
            nudgeSelectedAnnotation(horizontal: horizontal, vertical: vertical)
        }
    }

    func renameFormField(from currentName: String, to proposedName: String) {
        guard let document else { return }
        let matching = (0..<document.pageCount).flatMap { pageIndex -> [AnnotationEntry] in
            guard let page = document.page(at: pageIndex) else { return [] }
            return page.annotations
                .filter { $0.isFormWidget && $0.fieldName == currentName }
                .map { AnnotationEntry(page: page, annotation: $0, pageIndex: pageIndex) }
        }
        let modifications = matching.map { FormFieldModification(entry: $0, snapshot: AnnotationSnapshot($0.annotation)) }
        do {
            let changedCount = try PDFOperations.renameFormField(named: currentName, to: proposedName, in: document)
            guard currentName.trimmingCharacters(in: .whitespacesAndNewlines)
                != proposedName.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            guard changedCount > 0 else { return }
            annotationUndoStack.append(.formFieldsModified(modifications))
            canUndoAnnotation = true
            markDirty()
            let pages = Array(Set(matching.map(\.pageIndex))).sorted()
            for index in pages { cachedThumbnails.removeObject(forKey: NSNumber(value: index)) }
            refreshFormFields()
            perform(.annotationsChanged(pages))
        } catch {
            errorMessage = "The field could not be renamed: \(error.localizedDescription)"
        }
    }

    func prepareSignature(_ draft: SignatureDraft) {
        guard !draft.strokes.isEmpty else {
            errorMessage = "Draw at least one signature stroke before placement."
            return
        }
        signatureDraft = draft
        setAnnotationTool(.signature)
    }

    func consumeSignatureDraft() -> SignatureDraft? {
        defer { signatureDraft = nil }
        return signatureDraft
    }

    func prepareFormField(_ draft: PDFFormFieldDraft) {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give the field a unique name before placement."
            return
        }
        guard !formFields.contains(where: { $0.name == name }) else {
            errorMessage = "A field named “\(name)” already exists."
            return
        }
        if draft.kind == .choice, draft.choices.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count < 2 {
            errorMessage = "Choice fields need at least two comma-separated options."
            return
        }
        pendingFormFieldDraft = PDFFormFieldDraft(name: name, kind: draft.kind, value: draft.value, choices: draft.choices)
        setAnnotationTool(.formField)
    }

    func consumeFormFieldDraft() -> PDFFormFieldDraft? {
        defer { pendingFormFieldDraft = nil }
        return pendingFormFieldDraft
    }

    func registerFormFieldTransaction(_ entry: AnnotationEntry) {
        annotationUndoStack.append(.formFieldAdded(entry))
        canUndoAnnotation = true
        markDirty()
        cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        refreshFormFields()
        selectedFormField = FormFieldSelection(annotation: entry.annotation, page: entry.page, pageIndex: entry.pageIndex)
        perform(.annotationsChanged([entry.pageIndex]))
    }

    func selectAnnotation(_ annotation: PDFAnnotation?, page: PDFPage?, pageIndex: Int?) {
        guard let annotation, let page, let pageIndex else {
            selectedAnnotation = nil
            selectedFormField = nil
            return
        }
        selectedAnnotation = AnnotationSelection(
            annotation: annotation,
            page: page,
            pageIndex: pageIndex
        )
        selectedFormField = nil
    }

    func registerAnnotationTransaction(_ entries: [AnnotationEntry]) {
        guard !entries.isEmpty else { return }
        annotationUndoStack.append(.added(entries))
        annotationCount += entries.count
        canUndoAnnotation = true
        markDirty()
        for entry in entries {
            cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        }
        perform(.annotationsChanged(Array(Set(entries.map(\.pageIndex))).sorted()))
        refreshAnnotationRecords()
    }

    func undoLastAnnotation() {
        guard let operation = annotationUndoStack.popLast() else { return }
        switch operation {
        case .added(let added):
            annotationCount = max(0, annotationCount - added.count)
            for entry in added {
                entry.page.removeAnnotation(entry.annotation)
            }
            finishAnnotationUndo(added)
        case .removed(let removed):
            annotationCount += removed.count
            for entry in removed {
                entry.page.addAnnotation(entry.annotation)
            }
            finishAnnotationUndo(removed)
        case .modified(let entry, let snapshot):
            snapshot.apply(to: entry.annotation)
            entry.annotation.modificationDate = Date()
            finishAnnotationUndo([entry])
        case .pagesRotated(let rotations):
            for rotation in rotations {
                rotation.page.rotation = rotation.previousRotation
            }
            let restoredIndices = rotations.compactMap { document?.index(for: $0.page) }
            refreshAfterPageEdit(targetPage: restoredIndices.first ?? pageIndex, selectedPages: restoredIndices)
        case .pagesRemoved(let removals):
            for removal in removals.sorted(by: { $0.index < $1.index }) {
                document?.insert(removal.page, at: removal.index)
            }
            let restoredIndices = removals.map(\.index).sorted()
            refreshAfterPageEdit(targetPage: restoredIndices.first ?? pageIndex, selectedPages: restoredIndices)
        case .pagesInserted(let indices):
            for index in indices.sorted(by: >) {
                document?.removePage(at: index)
            }
            let target = min(indices.first ?? pageIndex, max(0, (document?.pageCount ?? 1) - 1))
            refreshAfterPageEdit(targetPage: target, selectedPages: [target])
        case .pagesCropped(let crops):
            for crop in crops {
                crop.page.setBounds(crop.previousCropBox, for: .cropBox)
            }
            let restoredIndices = crops.compactMap { document?.index(for: $0.page) }
            refreshAfterPageEdit(targetPage: restoredIndices.first ?? pageIndex, selectedPages: restoredIndices)
        case .pageMoved(let from, let to):
            if let page = document?.page(at: to) {
                document?.removePage(at: to)
                document?.insert(page, at: from)
            }
            refreshAfterPageEdit(targetPage: from, selectedPages: [from])
        case .formFieldAdded(let entry):
            entry.page.removeAnnotation(entry.annotation)
            cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
            markDirty()
            refreshFormFields()
            perform(.annotationsChanged([entry.pageIndex]))
        case .formFieldRemoved(let entry):
            entry.page.addAnnotation(entry.annotation)
            cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
            markDirty()
            refreshFormFields()
            selectedFormField = FormFieldSelection(annotation: entry.annotation, page: entry.page, pageIndex: entry.pageIndex)
            perform(.annotationsChanged([entry.pageIndex]))
        case .formFieldModified(let entry, let snapshot):
            snapshot.apply(to: entry.annotation)
            cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
            markDirty()
            refreshFormFields()
            selectedFormField = FormFieldSelection(annotation: entry.annotation, page: entry.page, pageIndex: entry.pageIndex)
            perform(.annotationsChanged([entry.pageIndex]))
        case .formFieldsModified(let modifications):
            for modification in modifications {
                modification.snapshot.apply(to: modification.entry.annotation)
                cachedThumbnails.removeObject(forKey: NSNumber(value: modification.entry.pageIndex))
            }
            markDirty()
            refreshFormFields()
            if let selected = modifications.first {
                selectedFormField = FormFieldSelection(
                    annotation: selected.entry.annotation,
                    page: selected.entry.page,
                    pageIndex: selected.entry.pageIndex
                )
            }
            perform(.annotationsChanged(Array(Set(modifications.map(\.entry.pageIndex))).sorted()))
        }
        canUndoAnnotation = !annotationUndoStack.isEmpty
    }

    private func finishAnnotationUndo(_ entries: [AnnotationEntry]) {
        for entry in entries {
            cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        }
        selectedAnnotation = nil
        markDirty()
        perform(.annotationsChanged(Array(Set(entries.map(\.pageIndex))).sorted()))
        refreshAnnotationRecords()
    }

    func rotateCurrentPage(clockwise: Bool) {
        guard let document else { return }
        let indices = pageOperationIndices
        let rotations: [PageRotation]
        do {
            rotations = try PDFOperations.rotate(
                document,
                pageIndices: indices,
                degrees: clockwise ? 90 : -90
            ).map { PageRotation(page: $0.page, previousRotation: $0.previousRotation) }
        } catch {
            errorMessage = "The selected pages could not be rotated: \(error.localizedDescription)"
            return
        }
        guard !rotations.isEmpty else { return }
        annotationUndoStack.append(.pagesRotated(rotations))
        canUndoAnnotation = true
        refreshAfterPageEdit(targetPage: pageIndex, selectedPages: indices)
    }

    func duplicateCurrentPage() {
        guard let document else { return }
        let originals = pageOperationIndices
        var insertedIndices: [Int] = []
        var offset = 0
        for originalIndex in originals {
            let adjustedIndex = originalIndex + offset
            guard let page = document.page(at: adjustedIndex), let duplicate = page.copy() as? PDFPage else { continue }
            let insertionIndex = adjustedIndex + 1
            document.insert(duplicate, at: insertionIndex)
            insertedIndices.append(insertionIndex)
            offset += 1
        }
        guard !insertedIndices.isEmpty else { return }
        annotationUndoStack.append(.pagesInserted(indices: insertedIndices))
        canUndoAnnotation = true
        refreshAfterPageEdit(targetPage: insertedIndices.first!, selectedPages: insertedIndices)
    }

    func deleteCurrentPage() {
        guard let document else { return }
        let indices = pageOperationIndices
        guard indices.count < document.pageCount else {
            errorMessage = "A PDF must contain at least one page."
            return
        }
        let removals = indices.compactMap { index -> PageRemoval? in
            guard let page = document.page(at: index) else { return nil }
            return PageRemoval(page: page, index: index)
        }
        for removal in removals.sorted(by: { $0.index > $1.index }) {
            document.removePage(at: removal.index)
        }
        guard !removals.isEmpty else { return }
        annotationUndoStack.append(.pagesRemoved(removals))
        canUndoAnnotation = true
        let target = min(indices.first ?? pageIndex, document.pageCount - 1)
        refreshAfterPageEdit(targetPage: target, selectedPages: [target])
    }

    func movePage(from: Int, to: Int) {
        guard
            let document,
            from != to,
            document.pageCount > 1,
            (0..<document.pageCount).contains(from),
            (0..<document.pageCount).contains(to),
            let page = document.page(at: from)
        else { return }
        document.removePage(at: from)
        document.insert(page, at: to)
        annotationUndoStack.append(.pageMoved(from: from, to: to))
        canUndoAnnotation = true
        refreshAfterPageEdit(targetPage: to, selectedPages: [to])
    }

    func moveCurrentPage(by offset: Int) {
        let target = min(max(0, pageIndex + offset), max(0, pageCount - 1))
        movePage(from: pageIndex, to: target)
    }

    func appendPagesFromPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PDF to append"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let source = PDFDocument(url: url), source.pageCount > 0 else {
            errorMessage = "The selected PDF could not be appended."
            return
        }

        insertPages(source, pageIndices: Array(0..<source.pageCount), placement: .end)
    }

    func insertPages(_ source: PDFDocument, pageIndices: [Int], placement: PDFInsertionPlacement) {
        guard let document else { return }
        let insertionIndex: Int
        switch placement {
        case .beforeSelection:
            insertionIndex = selectedPageIndices.min() ?? pageIndex
        case .afterSelection:
            insertionIndex = min(pageCount, (selectedPageIndices.max() ?? pageIndex) + 1)
        case .end:
            insertionIndex = pageCount
        }

        do {
            let insertedIndices = try PDFOperations.insert(
                source: source,
                pageIndices: pageIndices,
                into: document,
                at: insertionIndex
            )
            registerInsertedPages(insertedIndices)
        } catch {
            errorMessage = "The selected pages could not be inserted: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func insertPDF(from url: URL, before pageIndex: Int) -> Bool {
        guard url.pathExtension.lowercased() == "pdf", let document else { return false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let source = try PDFOperations.open(url)
            let insertedIndices = try PDFOperations.insert(
                source: source,
                pageIndices: Array(0..<source.pageCount),
                into: document,
                at: min(max(0, pageIndex), document.pageCount)
            )
            registerInsertedPages(insertedIndices)
            return true
        } catch {
            errorMessage = "“\(url.lastPathComponent)” could not be inserted: \(error.localizedDescription)"
            return false
        }
    }

    private func registerInsertedPages(_ insertedIndices: [Int]) {
        guard let first = insertedIndices.first else { return }
        annotationUndoStack.append(.pagesInserted(indices: insertedIndices))
        canUndoAnnotation = true
        refreshAfterPageEdit(targetPage: first, selectedPages: insertedIndices)
    }

    func extractCurrentPageFromPicker() {
        let indices = pageOperationIndices
        guard let document, !indices.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = extractionFileName(for: indices)
        panel.message = indices.count == 1
            ? "Extract the selected page as a new PDF"
            : "Extract \(indices.count) selected pages as a new PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let extracted = try PDFOperations.extract(document, pageIndices: indices)
            try PDFOperations.write(extracted, to: url, overwrite: true)
        } catch {
            errorMessage = "The selected pages could not be extracted: \(error.localizedDescription)"
        }
    }

    func createSearchableCopy(
        scope: OCRPageScope,
        quality: PDFOCRRecognitionLevel,
        languages: [String]
    ) {
        guard let document, let sourceData = document.dataRepresentation(), !isPerformingOCR else { return }
        let indices: [Int]
        switch scope {
        case .current:
            indices = [pageIndex]
        case .selection:
            indices = pageOperationIndices
        case .all:
            indices = Array(0..<pageCount)
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(displayName)-searchable.pdf"
        panel.message = indices.count == pageCount
            ? "Create a searchable copy of the complete PDF"
            : "Create a searchable copy with OCR on \(indices.count) page\(indices.count == 1 ? "" : "s")"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isPerformingOCR = true
        ocrStatusMessage = "Reading \(indices.count) page\(indices.count == 1 ? "" : "s") on this Mac…"
        lastOCRReport = nil
        lastOCROutputURL = nil
        let configuration = PDFOCRConfiguration(
            recognitionLevel: quality,
            languages: languages,
            usesLanguageCorrection: true,
            renderDPI: quality == .accurate ? 216 : 144
        )

        Task { @MainActor in
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    let result = try PDFOperations.makeSearchable(
                        data: sourceData,
                        pageIndices: indices,
                        configuration: configuration
                    )
                    try PDFOperations.write(result, to: outputURL, overwrite: true)
                    return result.report
                }.value
                lastOCRReport = report
                lastOCROutputURL = outputURL
                ocrStatusMessage = "Added \(report.recognizedLines) searchable lines to the copy."
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                errorMessage = "The searchable copy could not be created: \(error.localizedDescription)"
                ocrStatusMessage = "OCR stopped before the copy was written."
            }
            isPerformingOCR = false
        }
    }

    func setRedactionEditing(_ enabled: Bool) {
        guard document != nil else { return }
        activeAnnotationTool = .select
        selectedAnnotation = nil
        isCropEditing = false
        isRedactionEditing = enabled
    }

    func registerPendingRedaction(page: PDFPage, bounds: CGRect) {
        guard bounds.width >= 6, bounds.height >= 6 else { return }
        pendingRedactions.append(PendingRedaction(page: page, bounds: bounds.standardized))
        redactionStatusMessage = "\(pendingRedactions.count) region\(pendingRedactions.count == 1 ? "" : "s") staged for secure export."
    }

    func removePendingRedaction(_ id: UUID) {
        pendingRedactions.removeAll { $0.id == id }
        redactionStatusMessage = pendingRedactions.isEmpty
            ? nil
            : "\(pendingRedactions.count) region\(pendingRedactions.count == 1 ? "" : "s") staged for secure export."
    }

    func clearPendingRedactions(currentPageOnly: Bool = false) {
        if currentPageOnly, let current = document?.page(at: pageIndex) {
            pendingRedactions.removeAll { $0.page === current }
        } else {
            pendingRedactions = []
        }
        redactionStatusMessage = pendingRedactions.isEmpty
            ? nil
            : "\(pendingRedactions.count) region\(pendingRedactions.count == 1 ? "" : "s") staged for secure export."
    }

    func createSanitizedCopy(
        restoresSearchableText: Bool,
        forbiddenTerms: [String]
    ) {
        guard
            let document,
            let sourceData = document.dataRepresentation(),
            !isSanitizingRedactions
        else { return }
        let regions = pendingRedactions.compactMap { mark -> PDFRedactionRegion? in
            let index = document.index(for: mark.page)
            guard index != NSNotFound else { return nil }
            return PDFRedactionRegion(page: index + 1, bounds: mark.bounds)
        }
        guard !regions.isEmpty else {
            errorMessage = "Draw at least one redaction region before creating a sanitized copy."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(displayName)-sanitized.pdf"
        panel.message = "Create a flattened, sanitized copy with \(regions.count) burned-in redaction\(regions.count == 1 ? "" : "s")"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isSanitizingRedactions = true
        isRedactionEditing = false
        lastRedactionReport = nil
        redactionStatusMessage = "Flattening affected pages and removing hidden objects…"
        Task { @MainActor in
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    let result = try PDFOperations.sanitize(
                        data: sourceData,
                        regions: regions,
                        configuration: PDFRedactionConfiguration(
                            renderDPI: 216,
                            restoresSearchableText: restoresSearchableText,
                            recognitionLevel: .accurate,
                            languages: []
                        ),
                        verifyAbsentTerms: forbiddenTerms
                    )
                    try PDFOperations.write(result, to: outputURL, overwrite: true)
                    return result.report
                }.value
                lastRedactionReport = report
                redactionStatusMessage = "Sanitized \(report.flattenedPages.count) page\(report.flattenedPages.count == 1 ? "" : "s"); \(report.verifiedAbsentTerms.count) forbidden term\(report.verifiedAbsentTerms.count == 1 ? "" : "s") verified absent."
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                errorMessage = "The sanitized copy could not be created: \(error.localizedDescription)"
                redactionStatusMessage = "Secure export stopped before a verified copy was written."
            }
            isSanitizingRedactions = false
        }
    }

    private func extractionFileName(for indices: [Int]) -> String {
        if indices.count == 1, let index = indices.first {
            return "\(displayName)-page-\(index + 1).pdf"
        }
        let first = (indices.first ?? 0) + 1
        let last = (indices.last ?? 0) + 1
        return "\(displayName)-pages-\(first)-\(last).pdf"
    }

    func cropInsetsForSelection() -> PageCropInsets {
        guard
            let index = pageOperationIndices.first,
            let page = document?.page(at: index)
        else { return .zero }
        let media = page.bounds(for: .mediaBox)
        let crop = page.bounds(for: .cropBox)
        return PageCropInsets(
            top: max(0, Double(media.maxY - crop.maxY)),
            right: max(0, Double(media.maxX - crop.maxX)),
            bottom: max(0, Double(crop.minY - media.minY)),
            left: max(0, Double(crop.minX - media.minX))
        )
    }

    func applyCropPreset(_ preset: PageCropPreset) {
        applyCropInsets(preset.insets)
    }

    func setCropEditing(_ enabled: Bool) {
        guard document != nil else { return }
        activeAnnotationTool = .select
        selectedAnnotation = nil
        isCropEditing = enabled
    }

    func registerInteractiveCrop(
        page: PDFPage,
        previousCropBox: CGRect,
        newCropBox: CGRect
    ) {
        guard
            let document,
            !previousCropBox.equalTo(newCropBox)
        else { return }

        let index = document.index(for: page)
        guard index != NSNotFound else { return }
        annotationUndoStack.append(.pagesCropped([
            PageCrop(page: page, previousCropBox: previousCropBox)
        ]))
        canUndoAnnotation = true
        cachedThumbnails.removeObject(forKey: NSNumber(value: index))
        pageIndex = index
        selectedPageIndices = [index]
        pageSelectionAnchor = index
        markDirty()
    }

    func applyCropInsets(_ requestedInsets: PageCropInsets) {
        guard let document else { return }
        let indices = pageOperationIndices
        let crops: [PageCrop]
        do {
            crops = try PDFOperations.crop(
                document,
                pageIndices: indices,
                insets: PDFEdgeInsets(
                    top: requestedInsets.top,
                    right: requestedInsets.right,
                    bottom: requestedInsets.bottom,
                    left: requestedInsets.left
                )
            ).map { PageCrop(page: $0.page, previousCropBox: $0.previousCropBox) }
        } catch {
            errorMessage = "The selected pages could not be cropped: \(error.localizedDescription)"
            return
        }

        guard !crops.isEmpty else { return }
        annotationUndoStack.append(.pagesCropped(crops))
        canUndoAnnotation = true
        refreshAfterPageEdit(targetPage: pageIndex, selectedPages: indices)
    }

    private func refreshAfterPageEdit(targetPage: Int, selectedPages: [Int]? = nil) {
        guard let document else { return }
        pageCount = document.pageCount
        pageIndex = min(max(0, targetPage), max(0, pageCount - 1))
        let validSelection = Set((selectedPages ?? selectedPageIndices.sorted()).filter { (0..<pageCount).contains($0) })
        selectedPageIndices = validSelection.isEmpty && pageCount > 0 ? [pageIndex] : validSelection
        pageSelectionAnchor = selectedPageIndices.sorted().first
        cachedThumbnails.removeAllObjects()
        selectedAnnotation = nil
        annotationCount = (0..<pageCount).reduce(into: 0) { count, index in
            count += document.page(at: index)?.annotations.filter { !$0.isFormWidget }.count ?? 0
        }
        outlineEntries = Self.flattenOutline(document.outlineRoot, document: document)
        refreshAnnotationRecords()
        markDirty()
        perform(.documentStructureChanged(pageIndex))
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotation else { return }
        let entry = selectedAnnotation.entry
        entry.page.removeAnnotation(entry.annotation)
        annotationCount = max(0, annotationCount - 1)
        annotationUndoStack.append(.removed([entry]))
        canUndoAnnotation = true
        self.selectedAnnotation = nil
        markAnnotationsChanged([entry])
    }

    func duplicateSelectedAnnotation() {
        guard
            let selectedAnnotation,
            let duplicate = selectedAnnotation.annotation.copy() as? PDFAnnotation
        else { return }

        let pageBounds = selectedAnnotation.page.bounds(for: .cropBox)
        let originalBounds = selectedAnnotation.annotation.bounds
        let proposed = originalBounds.offsetBy(dx: 12, dy: -12)
        duplicate.bounds = CGRect(
            x: min(max(pageBounds.minX, proposed.minX), pageBounds.maxX - proposed.width),
            y: min(max(pageBounds.minY, proposed.minY), pageBounds.maxY - proposed.height),
            width: proposed.width,
            height: proposed.height
        )
        duplicate.modificationDate = Date()
        selectedAnnotation.page.addAnnotation(duplicate)

        let entry = AnnotationEntry(
            page: selectedAnnotation.page,
            annotation: duplicate,
            pageIndex: selectedAnnotation.pageIndex
        )
        registerAnnotationTransaction([entry])
        selectAnnotation(duplicate, page: selectedAnnotation.page, pageIndex: selectedAnnotation.pageIndex)
    }

    func nudgeSelectedAnnotation(horizontal: CGFloat, vertical: CGFloat) {
        guard let selectedAnnotation else { return }
        let annotation = selectedAnnotation.annotation
        let pageBounds = selectedAnnotation.page.bounds(for: .cropBox)
        let previousBounds = annotation.bounds
        let dx = min(
            max(horizontal, pageBounds.minX - previousBounds.minX),
            pageBounds.maxX - previousBounds.maxX
        )
        let dy = min(
            max(vertical, pageBounds.minY - previousBounds.minY),
            pageBounds.maxY - previousBounds.maxY
        )
        annotation.bounds = previousBounds.offsetBy(dx: dx, dy: dy)
        registerAnnotationTransform(
            annotation: annotation,
            page: selectedAnnotation.page,
            pageIndex: selectedAnnotation.pageIndex,
            previousBounds: previousBounds
        )
    }

    func discardUnsavedChangesForClosing() {
        markClean()
    }

    func updateSelectedAnnotation(contents: String) {
        guard let selectedAnnotation else { return }
        let annotation = selectedAnnotation.annotation
        guard annotation.contents != contents else { return }
        annotationUndoStack.append(.modified(selectedAnnotation.entry, AnnotationSnapshot(annotation)))
        annotation.contents = contents
        annotation.modificationDate = Date()
        canUndoAnnotation = true
        markAnnotationsChanged([selectedAnnotation.entry])
    }

    func recolorSelectedAnnotation(_ preset: AnnotationColorPreset) {
        guard let selectedAnnotation else { return }
        let annotation = selectedAnnotation.annotation
        let newColor = preset.nsColor
        guard annotation.color != newColor else { return }
        annotationUndoStack.append(.modified(selectedAnnotation.entry, AnnotationSnapshot(annotation)))
        annotation.color = newColor
        annotation.modificationDate = Date()
        canUndoAnnotation = true
        markAnnotationsChanged([selectedAnnotation.entry])
    }

    func beginSelectedAnnotationStyleEdit() {
        guard pendingStyleEdit == nil, let selectedAnnotation else { return }
        pendingStyleEdit = (selectedAnnotation.entry, AnnotationSnapshot(selectedAnnotation.annotation))
    }

    func updateSelectedAnnotationOpacity(_ opacity: Double) {
        guard let selectedAnnotation else { return }
        let annotation = selectedAnnotation.annotation
        let value = CGFloat(min(max(opacity, 0.12), 1))
        guard abs(annotation.color.alphaComponent - value) > 0.001 else { return }
        annotation.color = annotation.color.withAlphaComponent(value)
        annotation.modificationDate = Date()
        markAnnotationsChanged([selectedAnnotation.entry], refreshRecords: false)
    }

    func updateSelectedAnnotationStrokeWidth(_ width: Double) {
        guard let selectedAnnotation else { return }
        let annotation = selectedAnnotation.annotation
        let value = CGFloat(min(max(width, 0.5), 8))
        let currentValue = annotation.paths?.first?.lineWidth ?? annotation.border?.lineWidth ?? 1
        guard abs(currentValue - value) > 0.001 else { return }
        let border = annotation.border ?? PDFBorder()
        border.lineWidth = value
        annotation.border = border
        annotation.paths?.forEach { $0.lineWidth = value }
        annotation.modificationDate = Date()
        markAnnotationsChanged([selectedAnnotation.entry], refreshRecords: false)
    }

    func updateSelectedAnnotationFontSize(_ size: Double) {
        guard let selectedAnnotation else { return }
        let annotation = selectedAnnotation.annotation
        let value = CGFloat(min(max(size, 8), 48))
        guard abs((annotation.font?.pointSize ?? 14) - value) > 0.001 else { return }
        annotation.font = (annotation.font ?? NSFont.systemFont(ofSize: value)).withSize(value)
        annotation.modificationDate = Date()
        markAnnotationsChanged([selectedAnnotation.entry], refreshRecords: false)
    }

    func commitSelectedAnnotationStyleEdit() {
        guard let pendingStyleEdit else { return }
        annotationUndoStack.append(.modified(pendingStyleEdit.entry, pendingStyleEdit.snapshot))
        canUndoAnnotation = true
        self.pendingStyleEdit = nil
        refreshAnnotationRecords()
    }

    func registerAnnotationTransform(
        annotation: PDFAnnotation,
        page: PDFPage,
        pageIndex: Int,
        previousBounds: CGRect
    ) {
        guard annotation.bounds != previousBounds else { return }
        let entry = AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
        var snapshot = AnnotationSnapshot(annotation)
        snapshot.bounds = previousBounds
        annotationUndoStack.append(.modified(entry, snapshot))
        canUndoAnnotation = true
        markAnnotationsChanged([entry])
    }

    func showAnnotation(_ record: AnnotationRecord) {
        activeAnnotationTool = .select
        selectAnnotation(record.annotation, page: record.page, pageIndex: record.pageIndex)
        goToPage(record.pageIndex)
    }

    private func markAnnotationsChanged(_ entries: [AnnotationEntry], refreshRecords: Bool = true) {
        markDirty()
        for entry in entries {
            cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        }
        perform(.annotationsChanged(Array(Set(entries.map(\.pageIndex))).sorted()))
        if refreshRecords {
            refreshAnnotationRecords()
        }
    }

    private func refreshAnnotationRecords() {
        guard let document else {
            annotationRecords = []
            return
        }
        annotationRecords = (0..<document.pageCount).flatMap { pageIndex -> [AnnotationRecord] in
            guard let page = document.page(at: pageIndex) else { return [] }
            return page.annotations.filter { !$0.isFormWidget }.map {
                AnnotationRecord(annotation: $0, page: page, pageIndex: pageIndex)
            }
        }
    }

    private func refreshFormFields() {
        guard let document else {
            formFields = []
            formGate = nil
            return
        }
        let report = PDFOperations.formReport(for: document)
        formFields = report.fields
        formGate = PDFOperations.formGate(for: report)
    }

    func importRecipeFromPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a versioned SPDFV recipe"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            loadedRecipe = try PDFRecipeRunner.decode(Data(contentsOf: url))
            loadedRecipeName = url.lastPathComponent
            activeLibraryRecipeID = nil
            recipeReport = nil
            lastRecipeOutputURL = nil
            batchRecipeReport = nil
            lastBatchOutputDirectory = nil
        } catch {
            errorMessage = "The recipe could not be loaded: \(Self.message(for: error))"
        }
    }

    func loadStarterRecipe() {
        loadedRecipe = .starter
        loadedRecipeName = "starter-recipe.json"
        activeLibraryRecipeID = nil
        recipeReport = nil
        lastRecipeOutputURL = nil
        batchRecipeReport = nil
        lastBatchOutputDirectory = nil
    }

    func renameLoadedRecipe(_ name: String) {
        guard let recipe = loadedRecipe, recipe.name != name else { return }
        loadedRecipe = PDFRecipe(version: recipe.version, name: name, steps: recipe.steps)
        markRecipeEdited()
    }

    func addRecipeStep(_ step: PDFRecipeStep, after index: Int? = nil) {
        guard let recipe = loadedRecipe else { return }
        var steps = recipe.steps
        let insertionIndex = min(max(0, (index ?? (steps.count - 1)) + 1), steps.count)
        steps.insert(step, at: insertionIndex)
        loadedRecipe = PDFRecipe(version: recipe.version, name: recipe.name, steps: steps)
        markRecipeEdited()
    }

    func updateRecipeStep(at index: Int, to step: PDFRecipeStep) {
        guard let recipe = loadedRecipe, recipe.steps.indices.contains(index), recipe.steps[index] != step else { return }
        var steps = recipe.steps
        steps[index] = step
        loadedRecipe = PDFRecipe(version: recipe.version, name: recipe.name, steps: steps)
        markRecipeEdited()
    }

    func removeRecipeStep(at index: Int) {
        guard let recipe = loadedRecipe, recipe.steps.indices.contains(index) else { return }
        var steps = recipe.steps
        steps.remove(at: index)
        loadedRecipe = PDFRecipe(version: recipe.version, name: recipe.name, steps: steps)
        markRecipeEdited()
    }

    func moveRecipeStep(from source: Int, to destination: Int) {
        guard let recipe = loadedRecipe,
              recipe.steps.indices.contains(source),
              destination >= 0,
              destination < recipe.steps.count,
              source != destination else { return }
        var steps = recipe.steps
        let moved = steps.remove(at: source)
        steps.insert(moved, at: destination)
        loadedRecipe = PDFRecipe(version: recipe.version, name: recipe.name, steps: steps)
        markRecipeEdited()
    }

    func saveLoadedRecipe() {
        guard let recipe = loadedRecipe else { return }
        do {
            let data = try PDFRecipeRunner.encode(recipe, pretty: true)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = Self.recipeFilename(recipe.name)
            panel.message = "Save this reusable SPDFV recipe"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            loadedRecipeName = url.lastPathComponent
        } catch {
            errorMessage = "The recipe could not be saved: \(Self.message(for: error))"
        }
    }

    func copyLoadedRecipe() {
        guard let recipe = loadedRecipe else { return }
        do {
            let text = String(decoding: try PDFRecipeRunner.encode(recipe, pretty: true), as: UTF8.self)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } catch {
            errorMessage = "The recipe could not be copied: \(Self.message(for: error))"
        }
    }

    func shareLoadedRecipe() {
        guard let recipe = loadedRecipe else { return }
        do {
            let text = String(decoding: try PDFRecipeRunner.encode(recipe, pretty: true), as: UTF8.self)
            guard let anchor = NSApp.keyWindow?.contentView else {
                throw PDFOperationError.operationFailed("No active window is available for sharing")
            }
            NSSharingServicePicker(items: [text]).show(
                relativeTo: NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY, width: 1, height: 1),
                of: anchor,
                preferredEdge: .minY
            )
        } catch {
            errorMessage = "The recipe could not be shared: \(Self.message(for: error))"
        }
    }

    func loadLibraryRecipe(_ entryID: UUID) {
        guard let entry = RecipeLibraryStore.shared.entry(entryID) else { return }
        loadedRecipe = entry.recipe
        activeLibraryRecipeID = entry.id
        loadedRecipeName = "\(entry.kind == .preset ? "PRESET" : "CABINET") · R\(entry.revision)"
        clearRecipeProof()
    }

    func saveLoadedRecipeToLibrary() {
        guard let recipe = loadedRecipe else { return }
        do {
            let targetID: UUID?
            if let activeLibraryRecipeID,
               RecipeLibraryStore.shared.entry(activeLibraryRecipeID)?.kind == .personal {
                targetID = activeLibraryRecipeID
            } else {
                targetID = nil
            }
            let id = try RecipeLibraryStore.shared.save(recipe, to: targetID)
            activeLibraryRecipeID = id
            if let entry = RecipeLibraryStore.shared.entry(id) {
                loadedRecipeName = "CABINET · R\(entry.revision)"
            }
        } catch {
            errorMessage = "The recipe could not enter the cabinet: \(Self.message(for: error))"
        }
    }

    func duplicateLibraryRecipe(_ entryID: UUID) {
        do {
            guard let duplicateID = try RecipeLibraryStore.shared.duplicate(entryID) else { return }
            loadLibraryRecipe(duplicateID)
        } catch {
            errorMessage = "The recipe could not be duplicated: \(Self.message(for: error))"
        }
    }

    func restoreLibraryRevision(_ revisionID: UUID, entryID: UUID) {
        do {
            guard try RecipeLibraryStore.shared.restore(revisionID, in: entryID) else { return }
            loadLibraryRecipe(entryID)
        } catch {
            errorMessage = "The recipe revision could not be restored: \(Self.message(for: error))"
        }
    }

    func removeLibraryRecipe(_ entryID: UUID) {
        guard RecipeLibraryStore.shared.entry(entryID)?.kind == .personal else { return }
        RecipeLibraryStore.shared.remove(entryID)
        if activeLibraryRecipeID == entryID {
            activeLibraryRecipeID = nil
            loadedRecipeName = "UNSAVED RECIPE"
        }
    }

    func configureRecipeWatch(_ entryID: UUID) {
        let inputPanel = NSOpenPanel()
        inputPanel.canChooseFiles = false
        inputPanel.canChooseDirectories = true
        inputPanel.canCreateDirectories = false
        inputPanel.allowsMultipleSelection = false
        inputPanel.prompt = "Watch Input"
        inputPanel.message = "Choose the folder SPDFV should scan for new PDF files"
        guard inputPanel.runModal() == .OK, let input = inputPanel.url else { return }

        let outputPanel = NSOpenPanel()
        outputPanel.canChooseFiles = false
        outputPanel.canChooseDirectories = true
        outputPanel.canCreateDirectories = true
        outputPanel.allowsMultipleSelection = false
        outputPanel.prompt = "Watch Output"
        outputPanel.message = "Choose where passing PDFs and the watch manifest should be written"
        guard outputPanel.runModal() == .OK, let output = outputPanel.url else { return }

        do {
            try RecipeLibraryStore.shared.configureWatch(input: input, output: output, recipeID: entryID)
        } catch {
            errorMessage = "The watch lane could not be configured: \(Self.message(for: error))"
        }
    }

    private func markRecipeEdited() {
        loadedRecipeName = activeLibraryRecipeID == nil ? "UNSAVED RECIPE" : "CABINET DRAFT"
        clearRecipeProof()
    }

    private func clearRecipeProof() {
        recipeReport = nil
        lastRecipeOutputURL = nil
        batchRecipeReport = nil
        lastBatchOutputDirectory = nil
    }

    private static func recipeFilename(_ name: String) -> String {
        let slug = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(slug.isEmpty ? "spdfv-recipe" : slug).json"
    }

    func validateLoadedRecipe() {
        guard let loadedRecipe, let data = document?.dataRepresentation() else { return }
        isRunningRecipe = true
        defer { isRunningRecipe = false }
        do {
            recipeReport = try PDFRecipeRunner.run(loadedRecipe, on: data, dryRun: true).report
            lastRecipeOutputURL = nil
            batchRecipeReport = nil
            lastBatchOutputDirectory = nil
        } catch {
            recipeReport = nil
            errorMessage = "Recipe dry-run failed: \(Self.message(for: error))"
        }
    }

    func exportLoadedRecipe() {
        guard let loadedRecipe, let data = document?.dataRepresentation() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(displayName)-processed.pdf"
        panel.message = "Export the verified recipe result as a new PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isRunningRecipe = true
        defer { isRunningRecipe = false }
        do {
            let result = try PDFRecipeRunner.run(loadedRecipe, on: data)
            try result.data.write(to: url, options: .atomic)
            guard let reopened = PDFDocument(url: url), reopened.pageCount == result.report.outputPageCount else {
                throw PDFOperationError.operationFailed("Exported recipe output failed final verification")
            }
            recipeReport = result.report
            lastRecipeOutputURL = url
            batchRecipeReport = nil
            lastBatchOutputDirectory = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            refreshRecentDocuments()
        } catch {
            errorMessage = "Recipe export failed: \(Self.message(for: error))"
        }
    }

    func copyStarterRecipe() {
        do {
            let text = String(decoding: try PDFRecipeRunner.encodedStarterRecipe(pretty: true), as: UTF8.self)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } catch {
            errorMessage = "The starter recipe could not be copied: \(Self.message(for: error))"
        }
    }

    func processRecipeFolder() {
        guard let loadedRecipe else { return }
        let inputPanel = NSOpenPanel()
        inputPanel.canChooseFiles = false
        inputPanel.canChooseDirectories = true
        inputPanel.canCreateDirectories = false
        inputPanel.allowsMultipleSelection = false
        inputPanel.prompt = "Choose Input"
        inputPanel.message = "Choose a folder whose direct PDF files should use this recipe"
        guard inputPanel.runModal() == .OK, let inputDirectory = inputPanel.url else { return }

        let outputPanel = NSOpenPanel()
        outputPanel.canChooseFiles = false
        outputPanel.canChooseDirectories = true
        outputPanel.canCreateDirectories = true
        outputPanel.allowsMultipleSelection = false
        outputPanel.prompt = "Choose Output"
        outputPanel.message = "Choose an empty output folder for passing PDFs and the batch manifest"
        guard outputPanel.runModal() == .OK, let outputDirectory = outputPanel.url else { return }
        guard inputDirectory.standardizedFileURL != outputDirectory.standardizedFileURL else {
            errorMessage = "Choose different input and output folders for batch processing."
            return
        }

        isRunningRecipe = true
        defer { isRunningRecipe = false }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: inputDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
                .filter { $0.pathExtension.lowercased() == "pdf" }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            guard !urls.isEmpty else { throw PDFOperationError.invalidInput("The input folder contains no PDF files") }
            let inputs = try urls.map {
                PDFRecipeBatchInput(name: $0.lastPathComponent, data: try Data(contentsOf: $0))
            }
            let result = PDFRecipeBatchRunner.run(loadedRecipe, inputs: inputs)
            let manifestURL = outputDirectory.appendingPathComponent("spdfv-batch-manifest.json")
            let destinations = result.outputs.map { outputDirectory.appendingPathComponent($0.name) } + [manifestURL]
            if let collision = destinations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                throw PDFOperationError.outputExists("Output already exists: \(collision.lastPathComponent). Choose an empty folder.")
            }
            for output in result.outputs {
                try output.data.write(to: outputDirectory.appendingPathComponent(output.name), options: .atomic)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(result.report).write(to: manifestURL, options: .atomic)
            batchRecipeReport = result.report
            lastBatchOutputDirectory = outputDirectory
            recipeReport = nil
            lastRecipeOutputURL = nil
        } catch {
            errorMessage = "Batch processing failed: \(Self.message(for: error))"
        }
    }

    @discardableResult
    func save(to destinationURL: URL? = nil) -> Bool {
        guard let document else { return false }
        guard let targetURL = destinationURL ?? fileURL else {
            errorMessage = "Choose a destination for this PDF."
            return false
        }

        do {
            guard let stagedData = document.dataRepresentation() else {
                errorMessage = "The edited PDF could not be prepared for saving."
                return false
            }
            let data: Data
            if formFields.isEmpty {
                data = stagedData
            } else {
                let normalized = try PDFOperations.normalizeFormData(stagedData)
                let gate = PDFOperations.formGate(for: normalized.report)
                guard gate.canSave else {
                    errorMessage = "Form Gate stopped the save. Resolve conflicting values or missing appearances first."
                    return false
                }
                data = normalized.data
            }
            try data.write(to: targetURL, options: .atomic)

            var savedDocument = document
            if !formFields.isEmpty, let normalizedDocument = PDFDocument(data: data) {
                savedDocument = normalizedDocument
                self.document = normalizedDocument
                selectedAnnotation = nil
                selectedFormField = nil
                cachedThumbnails.removeAllObjects()
                refreshAnnotationRecords()
                refreshFormFields()
                perform(.documentStructureChanged(pageIndex))
            }

            if destinationURL != nil {
                releaseSecurityScopedResource()
                if targetURL.startAccessingSecurityScopedResource() {
                    securityScopedURL = targetURL
                }
                fileURL = targetURL
            }

            documentDetails = Self.makeDocumentDetails(document: savedDocument, url: targetURL)

            annotationUndoStack = []
            canUndoAnnotation = false
            markClean()
            NSDocumentController.shared.noteNewRecentDocumentURL(targetURL)
            refreshRecentDocuments()
            return true
        } catch {
            errorMessage = "The PDF could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func clearRecentDocuments() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecentDocuments()
    }

    func runSearch() {
        guard let document, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearSearch()
            return
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchSelections = document.findString(query, withOptions: [.caseInsensitive])
        searchResults = searchSelections.enumerated().compactMap { index, selection in
            guard let page = selection.pages.first else { return nil }
            let pageIndex = document.index(for: page)
            let excerpt = selection.string?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SearchResult(
                selectionIndex: index,
                pageIndex: pageIndex,
                excerpt: excerpt?.isEmpty == false ? excerpt! : query
            )
        }

        if !searchResults.isEmpty {
            showSearchResult(at: 0)
        } else {
            perform(.clearSelection)
        }
    }

    func showSearchResult(at index: Int) {
        guard searchSelections.indices.contains(index) else { return }
        perform(.showSelection(index))
    }

    func searchSelection(at index: Int) -> PDFSelection? {
        guard searchSelections.indices.contains(index) else { return nil }
        return searchSelections[index]
    }

    func clearSearch() {
        searchResults = []
        searchSelections = []
        perform(.clearSelection)
    }

    private func refreshRecentDocuments() {
        recentDocuments = NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(6)
            .map { $0 }
    }

    private func releaseSecurityScopedResource() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private func restoredPageIndex(for url: URL, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let positions = UserDefaults.standard.dictionary(forKey: pagePositionKey) as? [String: Int]
        return min(max(0, positions?[url.standardizedFileURL.path] ?? 0), pageCount - 1)
    }

    private func savePagePosition(_ index: Int) {
        guard let fileURL else { return }
        var positions = UserDefaults.standard.dictionary(forKey: pagePositionKey) as? [String: Int] ?? [:]
        positions[fileURL.standardizedFileURL.path] = index
        if positions.count > 80 {
            positions = Dictionary(uniqueKeysWithValues: positions.suffix(80))
        }
        UserDefaults.standard.set(positions, forKey: pagePositionKey)
    }

    private func markDirty() {
        isDirty = true
        DocumentRecoveryStore.shared.scheduleSnapshot(for: self)
    }

    private func markClean() {
        isDirty = false
        DocumentRecoveryStore.shared.removeSnapshot(for: self)
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    private static func message(for error: Error) -> String {
        (error as? PDFOperationError)?.description ?? error.localizedDescription
    }

    private static func flattenOutline(
        _ root: PDFOutline?,
        document: PDFDocument
    ) -> [OutlineEntry] {
        guard let root else { return [] }
        var entries: [OutlineEntry] = []

        func visit(_ item: PDFOutline, depth: Int) {
            for childIndex in 0..<item.numberOfChildren {
                guard let child = item.child(at: childIndex) else { continue }
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                let pageIndex = destination?.page.map(document.index(for:))
                if let label = child.label, !label.isEmpty {
                    entries.append(OutlineEntry(label: label, pageIndex: pageIndex, depth: depth))
                }
                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 0)
        return entries
    }

    private static func makeDocumentDetails(document: PDFDocument, url: URL) -> DocumentDetails {
        let attributes = document.documentAttributes ?? [:]
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let pageBounds = document.page(at: 0)?.bounds(for: .cropBox) ?? .zero

        return DocumentDetails(
            fileName: url.lastPathComponent,
            fileSize: fileSize.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "Unknown",
            pageSize: pageBounds.isEmpty
                ? "Unknown"
                : String(format: "%.1f × %.1f in", pageBounds.width / 72, pageBounds.height / 72),
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
            subject: attributes[PDFDocumentAttribute.subjectAttribute] as? String,
            encrypted: document.isEncrypted,
            allowsCopying: document.allowsCopying,
            allowsPrinting: document.allowsPrinting
        )
    }
}

struct ViewerCommand: Identifiable, Equatable {
    let id = UUID()
    let action: ViewerAction
}

enum ViewerAction: Equatable {
    case previousPage
    case nextPage
    case zoomOut
    case zoomIn
    case actualSize
    case fitPage
    case pageSetup
    case printDocument
    case goToPage(Int)
    case showSelection(Int)
    case clearSelection
    case setPageLayout(PageLayoutMode)
    case addMarkup(MarkupKind)
    case annotationsChanged([Int])
    case documentStructureChanged(Int)
}

enum MarkupKind: String, CaseIterable, Identifiable {
    case highlight
    case underline
    case strikeOut

    var id: Self { self }

    var label: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeOut: "Strike"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .highlight: .highlighter
        case .underline: .underline
        case .strikeOut: .strike
        }
    }

    var annotationSubtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeOut: .strikeOut
        }
    }
}

struct AnnotationEntry {
    let page: PDFPage
    let annotation: PDFAnnotation
    let pageIndex: Int
}

private enum AnnotationUndoOperation {
    case added([AnnotationEntry])
    case removed([AnnotationEntry])
    case modified(AnnotationEntry, AnnotationSnapshot)
    case pagesRotated([PageRotation])
    case pagesRemoved([PageRemoval])
    case pagesInserted(indices: [Int])
    case pagesCropped([PageCrop])
    case pageMoved(from: Int, to: Int)
    case formFieldAdded(AnnotationEntry)
    case formFieldRemoved(AnnotationEntry)
    case formFieldModified(AnnotationEntry, AnnotationSnapshot)
    case formFieldsModified([FormFieldModification])
}

private struct FormFieldModification {
    let entry: AnnotationEntry
    let snapshot: AnnotationSnapshot
}

private struct PageRotation {
    let page: PDFPage
    let previousRotation: Int
}

private struct PageRemoval {
    let page: PDFPage
    let index: Int
}

private struct PageCrop {
    let page: PDFPage
    let previousCropBox: CGRect
}

private struct AnnotationSnapshot {
    var bounds: CGRect
    let fieldName: String?
    let contents: String?
    let color: NSColor
    let borderLineWidth: CGFloat?
    let font: NSFont?
    let fontColor: NSColor?
    let pathLineWidths: [CGFloat]

    init(_ annotation: PDFAnnotation) {
        bounds = annotation.bounds
        fieldName = annotation.fieldName
        contents = annotation.contents
        color = annotation.color
        borderLineWidth = annotation.border?.lineWidth
        font = annotation.font
        fontColor = annotation.fontColor
        pathLineWidths = annotation.paths?.map(\.lineWidth) ?? []
    }

    func apply(to annotation: PDFAnnotation) {
        annotation.bounds = bounds
        annotation.contents = contents
        annotation.color = color
        if let borderLineWidth {
            let border = annotation.border ?? PDFBorder()
            border.lineWidth = borderLineWidth
            annotation.border = border
        }
        annotation.font = font
        annotation.fontColor = fontColor
        annotation.fieldName = fieldName
        if let paths = annotation.paths {
            for (index, path) in paths.enumerated() where pathLineWidths.indices.contains(index) {
                path.lineWidth = pathLineWidths[index]
            }
        }
    }
}

enum CanvasAnnotationTool: String, CaseIterable, Identifiable {
    case select
    case note
    case freeText
    case ink
    case rectangle
    case signature
    case formField

    var id: Self { self }

    static let quickTools: [Self] = [.select, .note, .freeText, .ink, .rectangle]

    var label: String {
        switch self {
        case .select: "Select"
        case .note: "Note"
        case .freeText: "Text"
        case .ink: "Draw"
        case .rectangle: "Shape"
        case .signature: "Sign"
        case .formField: "Field"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .select: .select
        case .note: .noteAdd
        case .freeText: .text
        case .ink: .draw
        case .rectangle: .region
        case .signature: .signature
        case .formField: .editField
        }
    }

    var help: String {
        switch self {
        case .select: "Select and inspect annotations"
        case .note: "Click a page to place a note"
        case .freeText: "Click a page to place editable text"
        case .ink: "Draw directly on the page"
        case .rectangle: "Click a page to place a rectangle"
        case .signature: "Click a page to place the prepared signature"
        case .formField: "Click a page to place the prepared form field"
        }
    }
}

enum AnnotationColorPreset: String, CaseIterable, Identifiable {
    case amber
    case cobalt
    case coral
    case jade
    case graphite

    var id: Self { self }

    var label: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .amber: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.20, alpha: 0.72)
        case .cobalt: NSColor(srgbRed: 0.18, green: 0.38, blue: 0.85, alpha: 0.92)
        case .coral: NSColor(srgbRed: 0.86, green: 0.25, blue: 0.24, alpha: 0.9)
        case .jade: NSColor(srgbRed: 0.16, green: 0.62, blue: 0.45, alpha: 0.9)
        case .graphite: NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 0.9)
        }
    }
}

struct AnnotationSelection: Identifiable {
    let annotation: PDFAnnotation
    let page: PDFPage
    let pageIndex: Int

    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
    var entry: AnnotationEntry {
        AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
    }
    var typeLabel: String {
        (annotation.type ?? "Annotation")
            .replacingOccurrences(of: "StrikeOut", with: "Strikeout")
            .replacingOccurrences(of: "FreeText", with: "Text")
    }
    var author: String { annotation.userName?.isEmpty == false ? annotation.userName! : "Unknown" }
    var contents: String { annotation.contents ?? "" }
    var opacity: Double { Double(annotation.color.alphaComponent) }
    var strokeWidth: Double {
        Double(annotation.paths?.first?.lineWidth ?? annotation.border?.lineWidth ?? 1)
    }
    var fontSize: Double { Double(annotation.font?.pointSize ?? 14) }
    var hasAdjustableFont: Bool { annotation.font != nil }
    var hasAdjustableStroke: Bool {
        annotation.border != nil || annotation.paths?.isEmpty == false
    }
}

struct FormFieldSelection: Identifiable {
    let annotation: PDFAnnotation
    let page: PDFPage
    let pageIndex: Int

    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
    var entry: AnnotationEntry {
        AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
    }
}

struct AnnotationRecord: Identifiable {
    let annotation: PDFAnnotation
    let page: PDFPage
    let pageIndex: Int

    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
    var typeLabel: String {
        (annotation.type ?? "Annotation")
            .replacingOccurrences(of: "StrikeOut", with: "Strikeout")
            .replacingOccurrences(of: "FreeText", with: "Text")
    }
    var preview: String {
        let value = annotation.contents?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "No attached text"
    }
    var color: NSColor { annotation.color }
    var category: AnnotationCategory {
        let normalized = (annotation.type ?? "").lowercased()
        if normalized.contains("highlight") || normalized.contains("underline") || normalized.contains("strike") {
            return .markup
        }
        if normalized.contains("ink") {
            return .drawing
        }
        if normalized.contains("square") || normalized.contains("circle") || normalized.contains("line") {
            return .shape
        }
        return .note
    }
}

enum AnnotationCategory: String, CaseIterable, Identifiable {
    case all
    case markup
    case note
    case drawing
    case shape

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum PageLayoutMode: String, CaseIterable, Identifiable {
    case single
    case continuous
    case spread

    var id: Self { self }

    var label: String {
        switch self {
        case .single: "Single"
        case .continuous: "Continuous"
        case .spread: "Spread"
        }
    }

    var displayMode: PDFDisplayMode {
        switch self {
        case .single: .singlePage
        case .continuous: .singlePageContinuous
        case .spread: .twoUpContinuous
        }
    }

    var displaysAsBook: Bool {
        self == .spread
    }
}

enum PageParity: String, CaseIterable, Identifiable {
    case odd
    case even

    var id: Self { self }
    var label: String { rawValue.capitalized }

    func matches(pageNumber: Int) -> Bool {
        switch self {
        case .odd: pageNumber.isMultiple(of: 2) == false
        case .even: pageNumber.isMultiple(of: 2)
        }
    }
}

enum PDFInsertionPlacement: String, CaseIterable, Identifiable {
    case beforeSelection
    case afterSelection
    case end

    var id: Self { self }
    var label: String {
        switch self {
        case .beforeSelection: "BEFORE"
        case .afterSelection: "AFTER"
        case .end: "END"
        }
    }
}

struct PageCropInsets: Equatable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    static let zero = PageCropInsets(top: 0, right: 0, bottom: 0, left: 0)
}

enum PageCropPreset: String, CaseIterable, Identifiable {
    case full
    case trim18
    case trim36

    var id: Self { self }
    var label: String {
        switch self {
        case .full: "FULL"
        case .trim18: "18 PT"
        case .trim36: "36 PT"
        }
    }
    var insets: PageCropInsets {
        switch self {
        case .full: .zero
        case .trim18: PageCropInsets(top: 18, right: 18, bottom: 18, left: 18)
        case .trim36: PageCropInsets(top: 36, right: 36, bottom: 36, left: 36)
        }
    }
}

enum NavigatorMode: String, CaseIterable, Identifiable {
    case pages
    case outline
    case search
    case forms
    case annotations
    case info

    var id: Self { self }

    var label: String {
        switch self {
        case .pages: "Pages"
        case .outline: "Contents"
        case .search: "Find"
        case .forms: "Fields"
        case .annotations: "Marks"
        case .info: "Info"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .pages: .pages
        case .outline: .outline
        case .search: .search
        case .forms: .textCursor
        case .annotations: .annotations
        case .info: .info
        }
    }
}

struct SignatureDraft: Equatable {
    let strokes: [[CGPoint]]
}

extension PDFAnnotation {
    var isFormWidget: Bool {
        type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "Widget"
    }
}

enum OCRPageScope: String, CaseIterable, Identifiable {
    case current
    case selection
    case all

    var id: Self { self }

    var label: String {
        switch self {
        case .current: "CURRENT"
        case .selection: "SELECTION"
        case .all: "ALL"
        }
    }
}

struct PendingRedaction: Identifiable {
    let id = UUID()
    let page: PDFPage
    let bounds: CGRect
}

enum OCRLanguagePreset: String, CaseIterable, Identifiable {
    case automatic
    case english = "en-US"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"

    var id: Self { self }
    var languages: [String] { self == .automatic ? [] : [rawValue] }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        }
    }
}

struct DocumentDetails {
    let fileName: String
    let fileSize: String
    let pageSize: String
    let title: String?
    let author: String?
    let subject: String?
    let encrypted: Bool
    let allowsCopying: Bool
    let allowsPrinting: Bool
}

struct SearchResult: Identifiable {
    let id = UUID()
    let selectionIndex: Int
    let pageIndex: Int
    let excerpt: String
}

struct OutlineEntry: Identifiable {
    let id = UUID()
    let label: String
    let pageIndex: Int?
    let depth: Int
}
