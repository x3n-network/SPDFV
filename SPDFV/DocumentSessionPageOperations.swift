import AppKit
import PDFKit
import SPDFVCore
import UniformTypeIdentifiers

extension DocumentSession {
func rotateCurrentPage(clockwise: Bool) {
    guard let document, permit(.pageAssembly) else { return }
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
    recordEdit(.pagesRotated(rotations))
    refreshAfterPageEdit(targetPage: pageIndex, selectedPages: indices)
}

func duplicateCurrentPage() {
    guard let document, permit(.pageAssembly) else { return }
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
    recordEdit(.pagesInserted(indices: insertedIndices), actionName: insertedIndices.count == 1 ? "Duplicate Page" : "Duplicate Pages")
    refreshAfterPageEdit(targetPage: insertedIndices.first!, selectedPages: insertedIndices)
}

func deleteCurrentPage() {
    guard let document, permit(.pageAssembly) else { return }
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
    recordEdit(.pagesRemoved(removals))
    let target = min(indices.first ?? pageIndex, document.pageCount - 1)
    refreshAfterPageEdit(targetPage: target, selectedPages: [target])
}

func movePage(from: Int, to: Int) {
    guard permit(.pageAssembly) else { return }
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
    recordEdit(.pageMoved(from: from, to: to))
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
    guard let document, permit(.pageAssembly) else { return }
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
    guard url.pathExtension.lowercased() == "pdf", let document, permit(.pageAssembly) else { return false }
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
    recordEdit(.pagesInserted(indices: insertedIndices))
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
    if enabled, !permit(.pageAssembly) { return }
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
    recordEdit(.pagesCropped([
        PageCrop(page: page, previousCropBox: previousCropBox)
    ]))
    cachedThumbnails.removeObject(forKey: NSNumber(value: index))
    pageIndex = index
    selectedPageIndices = [index]
    pageSelectionAnchor = index
    markDirty()
}

func applyCropInsets(_ requestedInsets: PageCropInsets) {
    guard let document, permit(.pageAssembly) else { return }
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
    recordEdit(.pagesCropped(crops))
    refreshAfterPageEdit(targetPage: pageIndex, selectedPages: indices)
}

    func refreshAfterPageEdit(targetPage: Int, selectedPages: [Int]? = nil) {
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
}
