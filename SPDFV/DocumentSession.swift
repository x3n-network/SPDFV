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
    @Published var pageIndex = 0
    @Published var pageCount = 0
    @Published var selectedPageIndices: Set<Int> = []
    @Published private(set) var scaleFactor: CGFloat = 1
    @Published private(set) var pageLayout: PageLayoutMode
    @Published var thumbnailsVisible = true
    @Published var navigatorMode: NavigatorMode = .pages
    @Published var searchText = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published var outlineEntries: [OutlineEntry] = []
    @Published private(set) var documentDetails: DocumentDetails?
    @Published private(set) var safetyGate: PDFSafetyGateReport?
    @Published var signatureVerificationReport: PDFSignatureVerificationReport?
    @Published var isVerifyingSignatures = false
    @Published private(set) var safeShareReport: PDFSafeShareReport?
    @Published var doctorReport: PDFDoctorReport?
    @Published var doctorRepairPlan: PDFDoctorRepairPlan?
    @Published var doctorRepairVerification: PDFDoctorRepairVerification?
    @Published var lastDoctorRepairOutputURL: URL?
    @Published var isRepairingDocument = false
    @Published var doctorRepairStatusMessage: String?
    @Published var comparisonReport: PDFComparisonReport?
    @Published var comparisonReferenceName: String?
    @Published var comparisonOptions = PDFComparisonOptions()
    @Published var selectedComparisonPosition: Int?
    @Published var isComparing = false
    @Published private(set) var recentDocuments: [URL] = []
    @Published private(set) var hasTextSelection = false
    @Published private(set) var isDirty = false
    @Published var canUndoEdit = false
    @Published var canRedoEdit = false
    @Published var undoActionName: String?
    @Published var redoActionName: String?
    @Published var annotationCount = 0
    @Published var annotationRecords: [AnnotationRecord] = []
    @Published var formFields: [PDFFormFieldReport] = []
    @Published var formGate: PDFFormGateReport?
    @Published var pendingFormData: PDFFormDataFile?
    @Published var formDataValidation: PDFFormDataValidationReport?
    @Published var formDataFileName: String?
    @Published var selectedFormField: FormFieldSelection?
    @Published var loadedRecipe: PDFRecipe?
    @Published var loadedRecipeName: String?
    @Published var activeLibraryRecipeID: UUID?
    @Published var recipeReport: PDFRecipeReport?
    @Published var lastRecipeOutputURL: URL?
    @Published var batchRecipeReport: PDFRecipeBatchReport?
    @Published var lastBatchOutputDirectory: URL?
    @Published var recipeParameterValues: [String: String] = [:]
    @Published var recipeReferences: [String: Data] = [:]
    @Published var recipeFormDataSources: [String: PDFFormDataFile] = [:]
    @Published var isRunningRecipe = false
    @Published var signatureDraft: SignatureDraft?
    @Published var pendingFormFieldDraft: PDFFormFieldDraft?
    @Published var activeAnnotationTool: CanvasAnnotationTool = .select
    @Published var isCropEditing = false
    @Published var selectedAnnotation: AnnotationSelection?
    @Published private(set) var pendingOpenURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var pendingCommand: ViewerCommand?
    @Published var isPerformingOCR = false
    @Published var ocrStatusMessage: String?
    @Published var lastOCRReport: PDFOCRReport?
    @Published var lastOCROutputURL: URL?
    @Published var pendingRedactions: [PendingRedaction] = []
    @Published var isRedactionEditing = false
    @Published var isSanitizingRedactions = false
    @Published var redactionStatusMessage: String?
    @Published var lastRedactionReport: PDFRedactionReport?

    private var securityScopedURL: URL?
    let cachedThumbnails: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    private var searchSelections: [PDFSelection] = []
    var editUndoStack: [EditHistoryEntry] = []
    var editRedoStack: [EditHistoryEntry] = []
    var historyTruncated = false
    var pendingStyleEdit: (entry: AnnotationEntry, snapshot: AnnotationSnapshot)?
    var pageSelectionAnchor: Int?
    var comparisonRequestID: UUID?
    var comparisonReferenceDocument: PDFDocument?
    private let pagePositionKey = "spdfv.document-page-position.v1"
    let historyDepthLimit = 100

    init() {
        let savedLayout = UserDefaults.standard.string(forKey: "pageLayoutMode")
        pageLayout = PageLayoutMode(rawValue: savedLayout ?? "") ?? .continuous
        refreshRecentDocuments()
    }

    var zoomLabel: String {
        "\(Int((scaleFactor * 100).rounded()))%"
    }

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    var undoMenuTitle: String {
        undoActionName.map { "Undo \($0)" } ?? "Undo"
    }

    var redoMenuTitle: String {
        redoActionName.map { "Redo \($0)" } ?? "Redo"
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

    func createBlankDocument() {
        releaseSecurityScopedResource()
        let pdf = PDFDocument()
        pdf.insert(PDFPage(), at: 0)
        configureLoadedDocument(pdf, url: nil)
        markDirty()
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

    func unlockDocument(with password: String) -> Bool {
        guard let document, let fileURL, document.isLocked else { return false }
        guard !password.isEmpty, document.unlock(withPassword: password) else { return false }
        configureLoadedDocument(document, url: fileURL)
        return true
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

        configureLoadedDocument(pdf, url: url)
    }

    private func configureLoadedDocument(_ pdf: PDFDocument, url: URL?) {
        document = pdf
        fileURL = url
        safetyGate = PDFOperations.safetyGate(for: pdf)
        signatureVerificationReport = nil
        safeShareReport = nil
        doctorReport = nil
        doctorRepairPlan = nil
        doctorRepairVerification = nil
        lastDoctorRepairOutputURL = nil
        doctorRepairStatusMessage = nil
        comparisonReport = nil
        comparisonReferenceName = nil
        comparisonReferenceDocument = nil
        selectedComparisonPosition = nil
        isComparing = false
        comparisonRequestID = nil
        if safetyGate?.locked == true {
            navigatorMode = .info
            thumbnailsVisible = true
        }
        pageCount = pdf.pageCount
        let restoredPage = url.map { restoredPageIndex(for: $0, pageCount: pdf.pageCount) } ?? 0
        pageIndex = restoredPage
        selectedPageIndices = pdf.pageCount > 0 ? [restoredPage] : []
        pageSelectionAnchor = pdf.pageCount > 0 ? restoredPage : nil
        searchText = ""
        searchResults = []
        searchSelections = []
        cachedThumbnails.removeAllObjects()
        outlineEntries = Self.flattenOutline(pdf.outlineRoot, document: pdf)
        documentDetails = Self.makeDocumentDetails(document: pdf, url: url)
        editUndoStack = []
        editRedoStack = []
        historyTruncated = false
        pendingStyleEdit = nil
        refreshHistoryState()
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
        pendingFormData = nil
        formDataValidation = nil
        formDataFileName = nil
        markClean()
        hasTextSelection = false
        errorMessage = nil
        if let url {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            refreshRecentDocuments()
        }
        if restoredPage > 0 {
            perform(.goToPage(restoredPage))
        }
    }

    func perform(_ action: ViewerAction) {
        pendingCommand = ViewerCommand(action: action)
    }

    func updatePage(index: Int) {
        let updatedIndex = max(0, min(index, max(0, pageCount - 1)))
        if pageIndex != updatedIndex {
            pageIndex = updatedIndex
        }
        if selectedPageIndices.count <= 1 {
            let updatedSelection: Set<Int> = pageCount > 0 ? [updatedIndex] : []
            if selectedPageIndices != updatedSelection {
                selectedPageIndices = updatedSelection
            }
            let updatedAnchor = pageCount > 0 ? updatedIndex : nil
            if pageSelectionAnchor != updatedAnchor {
                pageSelectionAnchor = updatedAnchor
            }
        }
        savePagePosition(updatedIndex)
    }

    func updateScale(_ scale: CGFloat) {
        guard scaleFactor != scale else { return }
        scaleFactor = scale
    }

    func updateSelection(hasText: Bool) {
        guard hasTextSelection != hasText else { return }
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

    @discardableResult
    func permit(_ capability: PDFMutationCapability) -> Bool {
        guard let document else { return false }
        let decision = (safetyGate ?? PDFOperations.safetyGate(for: document)).decision(for: capability)
        guard decision.allowed else {
            errorMessage = decision.reason ?? "This PDF does not allow that change."
            return false
        }
        return true
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
            safetyGate = PDFOperations.safetyGate(for: savedDocument)
            signatureVerificationReport = nil

            editUndoStack = []
            editRedoStack = []
            historyTruncated = false
            refreshHistoryState()
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

    func refreshRecentDocuments() {
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

    func markDirty() {
        isDirty = true
        safeShareReport = nil
        doctorReport = nil
        doctorRepairPlan = nil
        doctorRepairVerification = nil
        lastDoctorRepairOutputURL = nil
        doctorRepairStatusMessage = nil
        DocumentRecoveryStore.shared.scheduleSnapshot(for: self)
    }

    func runSafeShareAudit() {
        guard let document else {
            safeShareReport = nil
            return
        }
        safeShareReport = PDFOperations.safeShareAudit(for: document)
    }

    func markClean() {
        isDirty = false
        DocumentRecoveryStore.shared.removeSnapshot(for: self)
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    static func message(for error: Error) -> String {
        (error as? PDFOperationError)?.description ?? error.localizedDescription
    }

    static func flattenOutline(
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

    private static func makeDocumentDetails(document: PDFDocument, url: URL?) -> DocumentDetails {
        let attributes = document.documentAttributes ?? [:]
        let fileSize: Int?
        if let url {
            fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        } else {
            fileSize = nil
        }
        let pageBounds = document.page(at: 0)?.bounds(for: .cropBox) ?? .zero

        return DocumentDetails(
            fileName: url?.lastPathComponent ?? "Untitled.pdf",
            fileSize: fileSize.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? (url == nil ? "Unsaved" : "Unknown"),
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
