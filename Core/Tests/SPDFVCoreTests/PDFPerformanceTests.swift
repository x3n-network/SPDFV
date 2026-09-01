import PDFKit
import XCTest
@testable import SPDFVCore

final class PDFPerformanceTests: XCTestCase {
    func testLargeDocumentInspectionPerformance() throws {
        let document = makeDocument(pageCount: 250, annotationStride: 5)
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            let report = PDFOperations.inspect(document)
            XCTAssertEqual(report.pages, 250)
            XCTAssertEqual(report.pageDetails.reduce(0) { $0 + $1.annotations }, 50)
        }
    }

    func testRecipePipelinePerformance() throws {
        let source = makeDocument(pageCount: 60, annotationStride: 6)
        let data = try XCTUnwrap(source.dataRepresentation())
        let recipe = PDFRecipe(
            name: "Performance pipeline",
            steps: [
                .rotate(pages: "all", degrees: 90),
                .crop(pages: "all", insets: PDFEdgeInsets(top: 4, right: 4, bottom: 4, left: 4)),
                .extract(pages: "1-30")
            ]
        )
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        var operationError: Error?

        measure(metrics: [XCTClockMetric()], options: options) {
            do {
                let result = try PDFRecipeRunner.run(recipe, on: data)
                XCTAssertEqual(result.report.inputPageCount, 60)
                XCTAssertEqual(result.report.outputPageCount, 30)
                XCTAssertEqual(result.report.steps.count, 3)
            } catch {
                operationError = error
            }
        }

        XCTAssertNil(operationError)
    }

    private func makeDocument(pageCount: Int, annotationStride: Int) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            page.setBounds(CGRect(x: 12, y: 12, width: 588, height: 768), for: .cropBox)
            if index.isMultiple(of: annotationStride) {
                let annotation = PDFAnnotation(
                    bounds: CGRect(x: 72, y: 640, width: 180, height: 28),
                    forType: .freeText,
                    withProperties: nil
                )
                annotation.contents = "Performance page \(index + 1)"
                page.addAnnotation(annotation)
            }
            document.insert(page, at: document.pageCount)
        }
        return document
    }
}
