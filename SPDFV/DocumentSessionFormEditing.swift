import Foundation
import PDFKit
import SPDFVCore

extension DocumentSession {
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
}
