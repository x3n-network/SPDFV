#!/usr/bin/env swift

import AppKit
import Foundation
import PDFKit

enum CorpusError: Error {
    case couldNotEncode(String)
}

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = repositoryRoot.appendingPathComponent("CompatibilityCorpus", isDirectory: true)
let fixtureDate = Date(timeIntervalSince1970: 946_684_800)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func mixedLayoutDocument() -> PDFDocument {
    let document = PDFDocument()
    document.documentAttributes = [
        PDFDocumentAttribute.titleAttribute: "SPDFV Mixed Layout Fixture",
        PDFDocumentAttribute.authorAttribute: "SPDFV Project",
        PDFDocumentAttribute.creationDateAttribute: fixtureDate,
        PDFDocumentAttribute.modificationDateAttribute: fixtureDate
    ]

    for index in 0..<2 {
        let page = PDFPage()
        page.setBounds(
            CGRect(x: 0, y: 0, width: index == 0 ? 612 : 792, height: index == 0 ? 792 : 612),
            for: .mediaBox
        )
        page.setBounds(
            CGRect(x: 18, y: 18, width: index == 0 ? 576 : 756, height: index == 0 ? 756 : 576),
            for: .cropBox
        )
        page.rotation = index == 0 ? 0 : 90

        let annotation = PDFAnnotation(
            bounds: CGRect(x: 72, y: 500, width: 240, height: 32),
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = "Compatibility page \(index + 1)"
        page.addAnnotation(annotation)
        document.insert(page, at: document.pageCount)
    }
    return document
}

func interactiveFormDocument() -> PDFDocument {
    let document = PDFDocument()
    document.documentAttributes = [
        PDFDocumentAttribute.titleAttribute: "SPDFV Interactive Form Fixture",
        PDFDocumentAttribute.authorAttribute: "SPDFV Project",
        PDFDocumentAttribute.creationDateAttribute: fixtureDate,
        PDFDocumentAttribute.modificationDateAttribute: fixtureDate
    ]
    let page = PDFPage()
    page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
    page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .cropBox)

    let text = PDFAnnotation(
        bounds: CGRect(x: 72, y: 620, width: 240, height: 32),
        forType: .widget,
        withProperties: nil
    )
    text.widgetFieldType = .text
    text.fieldName = "review.owner"
    text.widgetStringValue = "Ada"
    page.addAnnotation(text)

    let checkbox = PDFAnnotation(
        bounds: CGRect(x: 72, y: 560, width: 24, height: 24),
        forType: .widget,
        withProperties: nil
    )
    checkbox.widgetFieldType = .button
    checkbox.fieldName = "approved"
    checkbox.buttonWidgetState = .onState
    page.addAnnotation(checkbox)

    document.insert(page, at: 0)
    return document
}

func write(_ document: PDFDocument, named name: String) throws {
    guard let data = document.dataRepresentation() else {
        throw CorpusError.couldNotEncode(name)
    }
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}

let mixed = mixedLayoutDocument()
try write(mixed, named: "mixed-layout.pdf")
try write(interactiveFormDocument(), named: "interactive-form.pdf")

guard let locked = mixed.dataRepresentation(options: [
    PDFDocumentWriteOption.ownerPasswordOption: "owner-fixture-password",
    PDFDocumentWriteOption.userPasswordOption: "fixture-password",
    PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: 0)
]) else {
    throw CorpusError.couldNotEncode("locked.pdf")
}
try locked.write(to: outputDirectory.appendingPathComponent("locked.pdf"), options: .atomic)
