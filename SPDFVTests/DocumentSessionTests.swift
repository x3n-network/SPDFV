import AppKit
import PDFKit
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

    private func makePDF(pageCount: Int, formFieldName: String? = nil) throws -> URL {
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

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spdfv-session-tests-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        guard document.write(to: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}
