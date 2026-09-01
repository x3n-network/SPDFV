#!/usr/bin/env swift

import AppKit
import Foundation
import PDFKit

enum VerificationFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VerificationFailure.expectation(message) }
}

func makePage(number: Int) -> PDFPage {
    let page = PDFPage()
    page.setBounds(CGRect(x: 0, y: 0, width: 612 + number, height: 792), for: .mediaBox)
    page.rotation = number.isMultiple(of: 2) ? 90 : 0

    let identity = PDFAnnotation(
        bounds: CGRect(x: 32, y: 720, width: 120, height: 28),
        forType: .freeText,
        withProperties: nil
    )
    identity.contents = "SPDFV-PAGE-\(number)"
    page.addAnnotation(identity)
    return page
}

func pageIdentity(_ page: PDFPage?) -> String? {
    page?.annotations.first?.contents
}

do {
    let source = PDFDocument()
    for number in 1...5 {
        source.insert(makePage(number: number), at: source.pageCount)
    }

    let selectedIndices = [0, 2, 4]
    let extracted = PDFDocument()
    for index in selectedIndices {
        guard let copy = source.page(at: index)?.copy() as? PDFPage else {
            throw VerificationFailure.expectation("Could not copy source page \(index + 1)")
        }
        extracted.insert(copy, at: extracted.pageCount)
    }

    guard let data = extracted.dataRepresentation() else {
        throw VerificationFailure.expectation("Could not serialize extracted PDF")
    }
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SPDFV-roundtrip-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: outputURL) }
    try data.write(to: outputURL, options: .atomic)

    guard let reopened = PDFDocument(url: outputURL) else {
        throw VerificationFailure.expectation("Could not reopen serialized PDF")
    }
    try expect(reopened.pageCount == 3, "Expected 3 extracted pages, found \(reopened.pageCount)")
    try expect(
        (0..<reopened.pageCount).compactMap { pageIdentity(reopened.page(at: $0)) }
            == ["SPDFV-PAGE-1", "SPDFV-PAGE-3", "SPDFV-PAGE-5"],
        "Extracted page order or annotations changed during round trip"
    )
    try expect(reopened.page(at: 0)?.rotation == 0, "Odd-page rotation changed")

    let deletionCopy = PDFDocument(data: source.dataRepresentation()!)!
    for index in selectedIndices.sorted(by: >) {
        deletionCopy.removePage(at: index)
    }
    try expect(deletionCopy.pageCount == 2, "Batch deletion produced the wrong page count")
    try expect(
        (0..<deletionCopy.pageCount).compactMap { pageIdentity(deletionCopy.page(at: $0)) }
            == ["SPDFV-PAGE-2", "SPDFV-PAGE-4"],
        "Descending batch deletion did not preserve remaining page order"
    )

    let cropCopy = PDFDocument(data: source.dataRepresentation()!)!
    guard let cropPage = cropCopy.page(at: 0) else {
        throw VerificationFailure.expectation("Could not load crop verification page")
    }
    let mediaBox = cropPage.bounds(for: .mediaBox)
    cropPage.setBounds(mediaBox.insetBy(dx: 18, dy: 18), for: .cropBox)
    guard
        let cropData = cropCopy.dataRepresentation(),
        let reopenedCrop = PDFDocument(data: cropData),
        let reopenedCropPage = reopenedCrop.page(at: 0)
    else { throw VerificationFailure.expectation("Could not round-trip crop box") }
    try expect(reopenedCropPage.bounds(for: .mediaBox) == mediaBox, "Crop changed the original media box")
    try expect(
        reopenedCropPage.bounds(for: .cropBox) == mediaBox.insetBy(dx: 18, dy: 18),
        "Crop box changed during PDF serialization"
    )

    print("PASS: preserved extraction order/annotations, batch deletion, and nondestructive crop boxes")
    print(outputURL.path)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
