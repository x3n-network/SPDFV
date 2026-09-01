import AppKit
import PDFKit
import SPDFVCore
import XCTest
@testable import SPDFV

@MainActor
final class DocumentSessionTests: XCTestCase {
    func testPageSelectionTracksRangesTogglesAndParity() throws {
        let fixture = try makePDF(pageCount: 4)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)

        XCTAssertEqual(session.pageCount, 4)
        XCTAssertEqual(session.pageIndex, 0)
        XCTAssertEqual(session.selectedPageIndices, [0])

        session.selectPage(2)
        session.selectPage(0, extendingRange: true)
        XCTAssertEqual(session.selectedPageIndices, [0, 1, 2])

        session.selectPage(1, toggling: true)
        XCTAssertEqual(session.selectedPageIndices, [0, 2])

        session.selectPages(matching: .even)
        XCTAssertEqual(session.selectedPageIndices, [1, 3])

        session.clearPageSelection()
        XCTAssertEqual(session.pageOperationIndices, [1])
    }

    func testRotateUndoAndRedoRestorePageState() throws {
        let fixture = try makePDF(pageCount: 1)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)
        let page = try XCTUnwrap(session.document?.page(at: 0))

        session.rotateCurrentPage(clockwise: true)
        XCTAssertEqual(page.rotation, 90)
        XCTAssertTrue(session.isDirty)
        XCTAssertTrue(session.canUndoEdit)
        XCTAssertEqual(session.undoActionName, "Rotate Page")

        session.undoLastEdit()
        XCTAssertEqual(page.rotation, 0)
        XCTAssertTrue(session.canRedoEdit)

        session.redoLastEdit()
        XCTAssertEqual(page.rotation, 90)
        XCTAssertTrue(session.canUndoEdit)
    }

    func testDuplicateUndoAndRedoMaintainPageSelection() throws {
        let fixture = try makePDF(pageCount: 2)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)
        session.selectPage(0)

        session.duplicateCurrentPage()
        XCTAssertEqual(session.pageCount, 3)
        XCTAssertEqual(session.selectedPageIndices, [1])
        XCTAssertEqual(session.undoActionName, "Duplicate Page")

        session.undoLastEdit()
        XCTAssertEqual(session.pageCount, 2)
        XCTAssertEqual(session.selectedPageIndices, [1])

        session.redoLastEdit()
        XCTAssertEqual(session.pageCount, 3)
        XCTAssertEqual(session.selectedPageIndices, [1])
    }

    func testRecipeEditingMaintainsOrderedImmutableSteps() {
        let session = DocumentSession()
        session.loadStarterRecipe()

        XCTAssertEqual(session.loadedRecipe?.name, "Verified proof copy")
        XCTAssertEqual(session.loadedRecipe?.steps.count, 4)

        session.renameLoadedRecipe("Review lane")
        session.addRecipeStep(.assertText(contains: ["APPROVED"], excludes: []), after: 0)
        XCTAssertEqual(session.loadedRecipe?.name, "Review lane")
        XCTAssertEqual(session.loadedRecipe?.steps.count, 5)
        XCTAssertEqual(session.loadedRecipe?.steps[1].operation, "assertText")
        XCTAssertEqual(session.loadedRecipeName, "UNSAVED RECIPE")

        session.moveRecipeStep(from: 1, to: 4)
        XCTAssertEqual(session.loadedRecipe?.steps.last?.operation, "assertText")

        session.updateRecipeStep(at: 4, to: .extract(pages: "1"))
        XCTAssertEqual(session.loadedRecipe?.steps.last?.operation, "extract")

        session.removeRecipeStep(at: 4)
        XCTAssertEqual(session.loadedRecipe?.steps.count, 4)
    }

    func testAddingRecipeV2PlateUpgradesCompositionWithoutChangingV1Starter() {
        let session = DocumentSession()
        session.loadStarterRecipe()
        XCTAssertEqual(session.loadedRecipe?.version, 1)

        session.addRecipeStep(.duplicatePages(pages: "1"), after: 0)

        XCTAssertEqual(session.loadedRecipe?.version, 2)
        XCTAssertEqual(session.loadedRecipe?.steps[1].operation, "duplicatePages")
        XCTAssertNoThrow(try PDFRecipeRunner.validate(XCTUnwrap(session.loadedRecipe)))
    }

    func testAnnotationTransactionUndoAndRedoMaintainInventory() throws {
        let fixture = try makePDF(pageCount: 1)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)
        let page = try XCTUnwrap(session.document?.page(at: 0))
        let annotation = PDFAnnotation(
            bounds: CGRect(x: 24, y: 40, width: 120, height: 36),
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = "Review"
        page.addAnnotation(annotation)

        session.registerAnnotationTransaction([
            AnnotationEntry(page: page, annotation: annotation, pageIndex: 0)
        ])
        XCTAssertEqual(session.annotationCount, 1)
        XCTAssertEqual(session.annotationRecords.count, 1)
        XCTAssertEqual(session.undoActionName, "Add Annotation")

        session.undoLastEdit()
        XCTAssertEqual(session.annotationCount, 0)
        XCTAssertTrue(page.annotations.isEmpty)

        session.redoLastEdit()
        XCTAssertEqual(session.annotationCount, 1)
        XCTAssertEqual(page.annotations.count, 1)
    }

    func testFormValueUndoAndRedoRestoreWidgetValue() throws {
        let fixture = try makePDF(pageCount: 1, formFieldName: "applicant.name")
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)
        let field = try XCTUnwrap(session.formFields.first)
        let widget = try XCTUnwrap(session.document?.page(at: 0)?.annotations.first)

        session.applyFormValue("Ada", to: field)
        XCTAssertEqual(widget.widgetStringValue, "Ada")
        XCTAssertEqual(session.undoActionName, "Fill Form Field")

        session.undoLastEdit()
        XCTAssertEqual(widget.widgetStringValue ?? "", "")

        session.redoLastEdit()
        XCTAssertEqual(widget.widgetStringValue, "Ada")
    }

    func testFormDataStudioAppliesAsOneUndoableTransaction() throws {
        let fixture = try makePDF(pageCount: 1, formFieldName: "applicant.name")
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)
        let file = PDFFormDataFile(fields: [PDFFormDataEntry(name: "applicant.name", value: "Grace")])
        session.pendingFormData = file
        session.formDataValidation = PDFOperations.validateFormData(file, for: try XCTUnwrap(session.document))

        session.applyPendingFormData()

        let widget = try XCTUnwrap(session.document?.page(at: 0)?.annotations.first)
        XCTAssertEqual(widget.widgetStringValue, "Grace")
        XCTAssertEqual(session.undoActionName, "Import Form Data")
        XCTAssertEqual(session.formDataValidation?.updatedFields, [])
        XCTAssertEqual(session.formDataValidation?.unchangedFields, ["applicant.name"])

        session.undoLastEdit()
        XCTAssertEqual(widget.widgetStringValue ?? "", "")
        session.redoLastEdit()
        XCTAssertEqual(widget.widgetStringValue, "Grace")
    }

    func testUnsavedDocumentDefersReplacementUntilResolved() throws {
        let first = try makePDF(pageCount: 1)
        let second = try makePDF(pageCount: 2)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let session = DocumentSession()
        session.open(first)
        session.rotateCurrentPage(clockwise: true)

        session.open(second)
        XCTAssertEqual(session.fileURL, first)
        XCTAssertEqual(session.pendingOpenURL, second)
        XCTAssertTrue(session.isDirty)

        session.cancelPendingOpen()
        XCTAssertNil(session.pendingOpenURL)
        XCTAssertEqual(session.fileURL, first)

        session.open(second)
        session.resolvePendingOpen(savingChanges: false)
        XCTAssertEqual(session.fileURL, second)
        XCTAssertEqual(session.pageCount, 2)
        XCTAssertFalse(session.isDirty)
        XCTAssertNil(session.pendingOpenURL)
    }

    func testEncryptedDocumentRejectsWrongPasswordAndConfiguresAfterUnlock() throws {
        let fixture = try makePDF(pageCount: 2, password: "reader-secret")
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)

        XCTAssertEqual(session.safetyGate?.locked, true)
        XCTAssertFalse(session.unlockDocument(with: "wrong-secret"))
        XCTAssertEqual(session.safetyGate?.locked, true)

        XCTAssertTrue(session.unlockDocument(with: "reader-secret"))
        XCTAssertEqual(session.safetyGate?.locked, false)
        XCTAssertEqual(session.pageCount, 2)
        XCTAssertEqual(session.selectedPageIndices, [0])
        XCTAssertFalse(session.isDirty)
    }

    func testSaveAsReopensEditedStateAndClearsHistory() throws {
        let fixture = try makePDF(pageCount: 1)
        let destination = temporaryPDFURL()
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: destination)
        }

        let session = DocumentSession()
        session.open(fixture)
        session.rotateCurrentPage(clockwise: true)
        XCTAssertTrue(session.canUndoEdit)

        XCTAssertTrue(session.save(to: destination))
        XCTAssertEqual(session.fileURL, destination)
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.canUndoEdit)
        XCTAssertFalse(session.canRedoEdit)
        XCTAssertEqual(PDFDocument(url: destination)?.page(at: 0)?.rotation, 90)
    }

    func testCropUndoAndRedoRestorePageGeometry() throws {
        let fixture = try makePDF(pageCount: 1)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)
        let page = try XCTUnwrap(session.document?.page(at: 0))
        let original = page.bounds(for: .cropBox)

        session.applyCropInsets(PageCropInsets(top: 12, right: 8, bottom: 6, left: 4))
        let cropped = page.bounds(for: .cropBox)
        XCTAssertEqual(cropped.width, original.width - 12, accuracy: 0.01)
        XCTAssertEqual(cropped.height, original.height - 18, accuracy: 0.01)
        XCTAssertEqual(session.undoActionName, "Crop Page")

        session.undoLastEdit()
        XCTAssertEqual(page.bounds(for: .cropBox), original)

        session.redoLastEdit()
        XCTAssertEqual(page.bounds(for: .cropBox), cropped)
    }

    func testSafeShareAuditRunsOnDemandAndInvalidatesAfterEditing() throws {
        let fixture = try makePDF(pageCount: 1, formFieldName: "account.owner")
        defer { try? FileManager.default.removeItem(at: fixture) }

        let session = DocumentSession()
        session.open(fixture)
        XCTAssertNil(session.safeShareReport)

        session.runSafeShareAudit()
        let report = try XCTUnwrap(session.safeShareReport)
        XCTAssertFalse(report.locked)
        XCTAssertEqual(report.pages, 1)

        session.rotateCurrentPage(clockwise: true)
        XCTAssertNil(session.safeShareReport)
    }

    private func makePDF(
        pageCount: Int,
        formFieldName: String? = nil,
        password: String? = nil
    ) throws -> URL {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 180, height: 240))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: image.size).fill()
            ("PAGE-\(index + 1)" as NSString).draw(
                at: NSPoint(x: 24, y: 108),
                withAttributes: [.foregroundColor: NSColor.black]
            )
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            if index == 0, let formFieldName {
                let widget = PDFAnnotation(
                    bounds: CGRect(x: 24, y: 40, width: 132, height: 28),
                    forType: .widget,
                    withProperties: nil
                )
                widget.widgetFieldType = .text
                widget.fieldName = formFieldName
                widget.widgetStringValue = ""
                page.addAnnotation(widget)
            }
            document.insert(page, at: index)
        }

        let url = temporaryPDFURL()
        if let password {
            let data = try XCTUnwrap(document.dataRepresentation(options: [
                PDFDocumentWriteOption.ownerPasswordOption: "owner-secret",
                PDFDocumentWriteOption.userPasswordOption: password
            ]))
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } else if !document.write(to: url) {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private func temporaryPDFURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("spdfv-session-tests-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
    }
}
