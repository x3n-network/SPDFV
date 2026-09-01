import AppKit
import Foundation
import PDFKit
import SPDFVCore

extension DocumentSession {
func addMarkup(_ kind: MarkupKind) {
    guard permit(.annotations) else { return }
    guard hasTextSelection else {
        errorMessage = "Select text in the document before adding markup."
        return
    }
    perform(.addMarkup(kind))
}

func setAnnotationTool(_ tool: CanvasAnnotationTool) {
    if tool != .select, !permit(.annotations) { return }
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
    guard let document, permit(.formEntry) else { return }
    let matching = (0..<document.pageCount).flatMap { pageIndex -> [AnnotationEntry] in
        guard let page = document.page(at: pageIndex) else { return [] }
        return page.annotations
            .filter { $0.isFormWidget && $0.fieldName == field.name }
            .map { AnnotationEntry(page: page, annotation: $0, pageIndex: pageIndex) }
    }
    let modifications = matching.map {
        FormFieldModification(entry: $0, snapshot: AnnotationSnapshot($0.annotation))
    }
    do {
        try PDFOperations.applyFormValue(value, named: field.name, in: document)
        guard !modifications.isEmpty else { return }
        recordEdit(.formFieldsModified(modifications), actionName: "Fill Form Field")
        markDirty()
        refreshFormFields()
        let pages = matching.map(\.pageIndex)
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
    guard let selectedFormField, permit(.annotations) else { return }
    let entry = selectedFormField.entry
    entry.page.removeAnnotation(entry.annotation)
    recordEdit(.formFieldRemoved(entry), actionName: "Delete Form Field")
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
    recordEdit(.formFieldModified(entry, snapshot), actionName: "Move Form Field")
    markDirty()
    cachedThumbnails.removeObject(forKey: NSNumber(value: pageIndex))
    refreshFormFields()
    perform(.annotationsChanged([pageIndex]))
}

func updateSelectedFormFieldBounds(_ proposedBounds: CGRect) {
    guard let selectedFormField, permit(.annotations) else { return }
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
    guard let document, permit(.annotations) else { return }
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
        recordEdit(.formFieldsModified(modifications), actionName: "Rename Form Field")
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
    recordEdit(.formFieldAdded(entry), actionName: "Add Form Field")
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
    recordEdit(.added(entries))
    annotationCount += entries.count
    markDirty()
    for entry in entries {
        cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
    }
    perform(.annotationsChanged(Array(Set(entries.map(\.pageIndex))).sorted()))
    refreshAnnotationRecords()
}

func undoLastEdit() {
    guard let entry = editUndoStack.popLast() else { return }
    let inverse = applyHistoryOperation(entry.operation)
    editRedoStack.append(EditHistoryEntry(actionName: entry.actionName, operation: inverse))
    synchronizeHistoryStateAndDirtyFlag()
}

func redoLastEdit() {
    guard let entry = editRedoStack.popLast() else { return }
    let inverse = applyHistoryOperation(entry.operation)
    editUndoStack.append(EditHistoryEntry(actionName: entry.actionName, operation: inverse))
    synchronizeHistoryStateAndDirtyFlag()
}

private func applyHistoryOperation(_ operation: AnnotationUndoOperation) -> AnnotationUndoOperation {
    switch operation {
    case .added(let added):
        annotationCount = max(0, annotationCount - added.count)
        for entry in added {
            entry.page.removeAnnotation(entry.annotation)
        }
        finishAnnotationUndo(added)
        return .removed(added)
    case .removed(let removed):
        annotationCount += removed.count
        for entry in removed {
            entry.page.addAnnotation(entry.annotation)
        }
        finishAnnotationUndo(removed)
        return .added(removed)
    case .modified(let entry, let snapshot):
        let inverse = AnnotationSnapshot(entry.annotation)
        snapshot.apply(to: entry.annotation)
        entry.annotation.modificationDate = Date()
        finishAnnotationUndo([entry])
        return .modified(entry, inverse)
    case .pagesRotated(let rotations):
        let inverse = rotations.map { PageRotation(page: $0.page, previousRotation: $0.page.rotation) }
        for rotation in rotations {
            rotation.page.rotation = rotation.previousRotation
        }
        let restoredIndices = rotations.compactMap { document?.index(for: $0.page) }
        refreshAfterPageEdit(targetPage: restoredIndices.first ?? pageIndex, selectedPages: restoredIndices)
        return .pagesRotated(inverse)
    case .pagesRemoved(let removals):
        for removal in removals.sorted(by: { $0.index < $1.index }) {
            document?.insert(removal.page, at: removal.index)
        }
        let restoredIndices = removals.map(\.index).sorted()
        refreshAfterPageEdit(targetPage: restoredIndices.first ?? pageIndex, selectedPages: restoredIndices)
        return .pagesInserted(indices: restoredIndices)
    case .pagesInserted(let indices):
        let removals = indices.compactMap { index -> PageRemoval? in
            guard let page = document?.page(at: index) else { return nil }
            return PageRemoval(page: page, index: index)
        }
        for index in indices.sorted(by: >) {
            document?.removePage(at: index)
        }
        let target = min(indices.first ?? pageIndex, max(0, (document?.pageCount ?? 1) - 1))
        refreshAfterPageEdit(targetPage: target, selectedPages: [target])
        return .pagesRemoved(removals)
    case .pagesCropped(let crops):
        let inverse = crops.map { PageCrop(page: $0.page, previousCropBox: $0.page.bounds(for: .cropBox)) }
        for crop in crops {
            crop.page.setBounds(crop.previousCropBox, for: .cropBox)
        }
        let restoredIndices = crops.compactMap { document?.index(for: $0.page) }
        refreshAfterPageEdit(targetPage: restoredIndices.first ?? pageIndex, selectedPages: restoredIndices)
        return .pagesCropped(inverse)
    case .pageMoved(let from, let to):
        if let page = document?.page(at: to) {
            document?.removePage(at: to)
            document?.insert(page, at: from)
        }
        refreshAfterPageEdit(targetPage: from, selectedPages: [from])
        return .pageMoved(from: to, to: from)
    case .formFieldAdded(let entry):
        entry.page.removeAnnotation(entry.annotation)
        cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        markDirty()
        refreshFormFields()
        perform(.annotationsChanged([entry.pageIndex]))
        return .formFieldRemoved(entry)
    case .formFieldRemoved(let entry):
        entry.page.addAnnotation(entry.annotation)
        cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        markDirty()
        refreshFormFields()
        selectedFormField = FormFieldSelection(annotation: entry.annotation, page: entry.page, pageIndex: entry.pageIndex)
        perform(.annotationsChanged([entry.pageIndex]))
        return .formFieldAdded(entry)
    case .formFieldModified(let entry, let snapshot):
        let inverse = AnnotationSnapshot(entry.annotation)
        snapshot.apply(to: entry.annotation)
        cachedThumbnails.removeObject(forKey: NSNumber(value: entry.pageIndex))
        markDirty()
        refreshFormFields()
        selectedFormField = FormFieldSelection(annotation: entry.annotation, page: entry.page, pageIndex: entry.pageIndex)
        perform(.annotationsChanged([entry.pageIndex]))
        return .formFieldModified(entry, inverse)
    case .formFieldsModified(let modifications):
        let inverse = modifications.map {
            FormFieldModification(entry: $0.entry, snapshot: AnnotationSnapshot($0.entry.annotation))
        }
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
        return .formFieldsModified(inverse)
    }
}

func recordEdit(_ operation: AnnotationUndoOperation, actionName: String? = nil) {
    editUndoStack.append(EditHistoryEntry(actionName: actionName ?? operation.actionName, operation: operation))
    if editUndoStack.count > historyDepthLimit {
        editUndoStack.removeFirst(editUndoStack.count - historyDepthLimit)
        historyTruncated = true
    }
    editRedoStack.removeAll()
    refreshHistoryState()
}

func refreshHistoryState() {
    undoActionName = editUndoStack.last?.actionName
    redoActionName = editRedoStack.last?.actionName
    canUndoEdit = !editUndoStack.isEmpty
    canRedoEdit = !editRedoStack.isEmpty
}

private func synchronizeHistoryStateAndDirtyFlag() {
    refreshHistoryState()
    if editUndoStack.isEmpty && !historyTruncated {
        markClean()
    } else {
        markDirty()
    }
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


func deleteSelectedAnnotation() {
    guard let selectedAnnotation, permit(.annotations) else { return }
    let entry = selectedAnnotation.entry
    entry.page.removeAnnotation(entry.annotation)
    annotationCount = max(0, annotationCount - 1)
    recordEdit(.removed([entry]))
    self.selectedAnnotation = nil
    markAnnotationsChanged([entry])
}

func duplicateSelectedAnnotation() {
    guard permit(.annotations) else { return }
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
    guard let selectedAnnotation, permit(.annotations) else { return }
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
    guard let selectedAnnotation, permit(.annotations) else { return }
    let annotation = selectedAnnotation.annotation
    guard annotation.contents != contents else { return }
    recordEdit(.modified(selectedAnnotation.entry, AnnotationSnapshot(annotation)), actionName: "Edit Annotation Text")
    annotation.contents = contents
    annotation.modificationDate = Date()
    markAnnotationsChanged([selectedAnnotation.entry])
}

func recolorSelectedAnnotation(_ preset: AnnotationColorPreset) {
    guard let selectedAnnotation, permit(.annotations) else { return }
    let annotation = selectedAnnotation.annotation
    let newColor = preset.nsColor
    guard annotation.color != newColor else { return }
    recordEdit(.modified(selectedAnnotation.entry, AnnotationSnapshot(annotation)), actionName: "Change Annotation Color")
    annotation.color = newColor
    annotation.modificationDate = Date()
    markAnnotationsChanged([selectedAnnotation.entry])
}

func beginSelectedAnnotationStyleEdit() {
    guard pendingStyleEdit == nil, let selectedAnnotation else { return }
    pendingStyleEdit = (selectedAnnotation.entry, AnnotationSnapshot(selectedAnnotation.annotation))
}

func updateSelectedAnnotationOpacity(_ opacity: Double) {
    guard let selectedAnnotation, permit(.annotations) else { return }
    let annotation = selectedAnnotation.annotation
    let value = CGFloat(min(max(opacity, 0.12), 1))
    guard abs(annotation.color.alphaComponent - value) > 0.001 else { return }
    annotation.color = annotation.color.withAlphaComponent(value)
    annotation.modificationDate = Date()
    markAnnotationsChanged([selectedAnnotation.entry], refreshRecords: false)
}

func updateSelectedAnnotationStrokeWidth(_ width: Double) {
    guard let selectedAnnotation, permit(.annotations) else { return }
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
    guard let selectedAnnotation, permit(.annotations) else { return }
    let annotation = selectedAnnotation.annotation
    let value = CGFloat(min(max(size, 8), 48))
    guard abs((annotation.font?.pointSize ?? 14) - value) > 0.001 else { return }
    annotation.font = (annotation.font ?? NSFont.systemFont(ofSize: value)).withSize(value)
    annotation.modificationDate = Date()
    markAnnotationsChanged([selectedAnnotation.entry], refreshRecords: false)
}

func commitSelectedAnnotationStyleEdit() {
    guard let pendingStyleEdit else { return }
    recordEdit(.modified(pendingStyleEdit.entry, pendingStyleEdit.snapshot), actionName: "Change Annotation Style")
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
    recordEdit(.modified(entry, snapshot), actionName: "Move Annotation")
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

func refreshAnnotationRecords() {
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

func refreshFormFields() {
    guard let document else {
        formFields = []
        formGate = nil
        return
    }
    let report = PDFOperations.formReport(for: document)
    formFields = report.fields
    formGate = PDFOperations.formGate(for: report)
}
}
