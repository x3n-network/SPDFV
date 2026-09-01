import PDFKit
import AppKit
import XCTest
@testable import SPDFVCore

final class SPDFVCoreTests: XCTestCase {
    func testSafeShareAuditReportsHazardsWithoutCopyingPrivateValues() throws {
        let document = PDFDocument()
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Confidential acquisition",
            PDFDocumentAttribute.authorAttribute: "Private Author"
        ]
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)

        let note = PDFAnnotation(
            bounds: CGRect(x: 40, y: 700, width: 180, height: 28),
            forType: .freeText,
            withProperties: nil
        )
        note.contents = "Do not include this comment"
        note.userName = "Private Reviewer"
        page.addAnnotation(note)

        let attachment = PDFAnnotation(
            bounds: CGRect(x: 40, y: 650, width: 24, height: 24),
            forType: PDFAnnotationSubtype(rawValue: "FileAttachment"),
            withProperties: nil
        )
        page.addAnnotation(attachment)
        document.insert(page, at: 0)
        _ = try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "account.owner", kind: .text, value: "Ada Lovelace"),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 560, width: 200, height: 28)
        )

        let report = PDFOperations.safeShareAudit(for: document)

        XCTAssertEqual(report.level, .warning)
        XCTAssertEqual(report.metadataKeys, ["title", "author"])
        XCTAssertEqual(report.reviewAnnotationCount, 1)
        XCTAssertEqual(report.reviewAnnotationPages, [1])
        XCTAssertEqual(report.annotationsWithContents, 1)
        XCTAssertEqual(report.filledFormFields, ["account.owner"])
        XCTAssertEqual(report.fileAttachmentCount, 1)
        XCTAssertEqual(
            report.findings.map(\.id),
            ["document-metadata", "review-annotations", "filled-form-fields", "file-attachments"]
        )

        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertFalse(json.contains("Confidential acquisition"))
        XCTAssertFalse(json.contains("Private Author"))
        XCTAssertFalse(json.contains("Private Reviewer"))
        XCTAssertFalse(json.contains("Do not include this comment"))
        XCTAssertFalse(json.contains("Ada Lovelace"))
    }

    func testSafeShareAuditStopsBeforeInspectingLockedContent() throws {
        let source = makeDocument(pageNumbers: [1])
        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: "owner-secret",
            .userPasswordOption: "user-secret",
            .accessPermissionsOption: NSNumber(value: 0)
        ]
        let encryptedData = try XCTUnwrap(source.dataRepresentation(options: options))
        let locked = try XCTUnwrap(PDFDocument(data: encryptedData))

        let report = PDFOperations.safeShareAudit(for: locked)

        XCTAssertEqual(report.level, .stop)
        XCTAssertTrue(report.locked)
        XCTAssertEqual(report.findings.map(\.id), ["locked-document"])
        XCTAssertTrue(report.metadataKeys.isEmpty)
        XCTAssertTrue(report.filledFormFields.isEmpty)
        XCTAssertEqual(report.reviewAnnotationCount, 0)
    }

    func testSafetyGateReportsPlainLockedAndRestrictedDocuments() throws {
        let plain = makeDocument(pageNumbers: [1])
        let plainGate = PDFOperations.safetyGate(for: plain)
        XCTAssertEqual(plainGate.level, .pass)
        XCTAssertTrue(plainGate.canReadContent)
        XCTAssertTrue(plainGate.canEditContent)
        XCTAssertTrue(plainGate.permissions.restrictedCapabilities.isEmpty)

        let encryptionOptions: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: "owner-secret",
            .userPasswordOption: "user-secret",
            .accessPermissionsOption: NSNumber(value: 0)
        ]
        let encryptedData = try XCTUnwrap(plain.dataRepresentation(options: encryptionOptions))
        let encrypted = try XCTUnwrap(PDFDocument(data: encryptedData))

        let lockedGate = PDFOperations.safetyGate(for: encrypted)
        XCTAssertTrue(lockedGate.encrypted)
        XCTAssertTrue(lockedGate.locked)
        XCTAssertEqual(lockedGate.level, .stop)
        XCTAssertFalse(lockedGate.canReadContent)
        XCTAssertEqual(lockedGate.issues.map(\.id), ["locked-document"])
        XCTAssertFalse(lockedGate.decision(for: .contentCopying).allowed)
        XCTAssertTrue(lockedGate.decision(for: .contentCopying).reason?.contains("Unlock") == true)

        XCTAssertTrue(encrypted.unlock(withPassword: "user-secret"))
        let unlockedGate = PDFOperations.safetyGate(for: encrypted)
        XCTAssertTrue(unlockedGate.encrypted)
        XCTAssertFalse(unlockedGate.locked)
        XCTAssertEqual(unlockedGate.level, .warning)
        XCTAssertFalse(unlockedGate.canEditContent)
        XCTAssertFalse(unlockedGate.canAssemblePages)
        XCTAssertFalse(unlockedGate.canFillForms)
        XCTAssertTrue(unlockedGate.permissions.restrictedCapabilities.contains("document changes"))
        XCTAssertEqual(unlockedGate.issues.map(\.id), ["encrypted-document", "restricted-permissions"])
        for capability in PDFMutationCapability.allCases {
            let decision = unlockedGate.decision(for: capability)
            XCTAssertFalse(decision.allowed)
            XCTAssertNotNil(decision.reason)
            XCTAssertThrowsError(try PDFOperations.requirePermission(capability, for: encrypted))
        }
        XCTAssertThrowsError(try PDFOperations.extract(encrypted, pageIndices: [0]))
        XCTAssertThrowsError(try PDFOperations.rotate(encrypted, pageIndices: [0], degrees: 90))
        XCTAssertThrowsError(try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "blocked", kind: .text),
            to: encrypted,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 600, width: 180, height: 30)
        ))
    }

    func testSafetyGateConservativelyReportsCertificateSignatureFields() throws {
        let document = makeDocument(pageNumbers: [1])
        let page = try XCTUnwrap(document.page(at: 0))
        let signature = PDFAnnotation(
            bounds: CGRect(x: 72, y: 620, width: 220, height: 48),
            forType: .widget,
            withProperties: nil
        )
        signature.widgetFieldType = .signature
        signature.fieldName = "approval.signature"
        page.addAnnotation(signature)

        let gate = PDFOperations.safetyGate(for: document)
        XCTAssertEqual(gate.level, .warning)
        XCTAssertEqual(gate.certificateSignatureFields, ["approval.signature"])
        XCTAssertEqual(gate.issues.map(\.id), ["certificate-signatures"])
        XCTAssertTrue(gate.issues[0].detail.contains("not validated"))
    }

    func testPageSelectionParsesRangesAndDeduplicates() throws {
        XCTAssertEqual(try PDFPageSelection.parse("1,3-5,3", pageCount: 6), [0, 2, 3, 4])
        XCTAssertEqual(try PDFPageSelection.parse("all", pageCount: 3), [0, 1, 2])
        XCTAssertThrowsError(try PDFPageSelection.parse("4", pageCount: 3))
    }

    func testExtractMergeRotateCropAndAnnotations() throws {
        let first = makeDocument(pageNumbers: [1, 2, 3])
        let second = makeDocument(pageNumbers: [4, 5])

        let extracted = try PDFOperations.extract(first, pageIndices: [0, 2])
        XCTAssertEqual(extracted.pageCount, 2)
        XCTAssertEqual(identity(extracted.page(at: 1)), "PAGE-3")

        let merged = try PDFOperations.merge([extracted, second])
        XCTAssertEqual(merged.pageCount, 4)
        XCTAssertEqual(identity(merged.page(at: 2)), "PAGE-4")

        let rotations = try PDFOperations.rotate(merged, pageIndices: [0, 3], degrees: 90)
        XCTAssertEqual(rotations.count, 2)
        XCTAssertEqual(merged.page(at: 0)?.rotation, 90)

        let media = merged.page(at: 0)!.bounds(for: .mediaBox)
        let crops = try PDFOperations.crop(
            merged,
            pageIndices: [0],
            insets: PDFEdgeInsets(top: 18, right: 18, bottom: 18, left: 18)
        )
        XCTAssertEqual(crops.count, 1)
        XCTAssertEqual(merged.page(at: 0)?.bounds(for: .mediaBox), media)
        XCTAssertEqual(merged.page(at: 0)?.bounds(for: .cropBox), media.insetBy(dx: 18, dy: 18))

        let annotations = try PDFOperations.annotations(in: merged)
        XCTAssertEqual(annotations.count, 4)
        XCTAssertEqual(annotations.first?.contents, "PAGE-1")
    }

    func testOCRCreatesSearchableTextLayer() throws {
        let image = NSImage(size: NSSize(width: 900, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        ("SPDFV OCR TEST" as NSString).draw(
            at: NSPoint(x: 60, y: 100),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        let source = PDFDocument()
        let sourcePage = PDFPage(image: image)!
        let note = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 80, height: 24),
            forType: .freeText,
            withProperties: nil
        )
        note.contents = "REVIEW NOTE"
        sourcePage.addAnnotation(note)
        source.insert(sourcePage, at: 0)
        let result = try PDFOperations.makeSearchable(
            data: source.dataRepresentation()!,
            configuration: PDFOCRConfiguration(renderDPI: 144)
        )
        let reopened = PDFDocument(data: result.data)
        XCTAssertEqual(result.report.pageCount, 1)
        XCTAssertGreaterThan(result.report.recognizedCharacters, 5)
        XCTAssertTrue(reopened?.string?.localizedCaseInsensitiveContains("SPDFV") == true)
        XCTAssertEqual(reopened?.page(at: 0)?.bounds(for: .mediaBox).size, source.page(at: 0)?.bounds(for: .cropBox).size)
        XCTAssertEqual(reopened?.page(at: 0)?.annotations.count, 1)
        XCTAssertEqual(reopened?.page(at: 0)?.annotations.first?.contents, "REVIEW NOTE")
    }

    func testRedactionBurnsRegionAndVerifiesForbiddenTextIsAbsent() throws {
        let image = NSImage(size: NSSize(width: 700, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 54, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        ("SECRET" as NSString).draw(at: NSPoint(x: 40, y: 170), withAttributes: attributes)
        ("PUBLIC" as NSString).draw(at: NSPoint(x: 380, y: 60), withAttributes: attributes)
        image.unlockFocus()

        let source = PDFDocument()
        source.insert(PDFPage(image: image)!, at: 0)
        let result = try PDFOperations.sanitize(
            data: source.dataRepresentation()!,
            regions: [PDFRedactionRegion(page: 1, bounds: CGRect(x: 20, y: 135, width: 290, height: 115))],
            configuration: PDFRedactionConfiguration(renderDPI: 144),
            verifyAbsentTerms: ["SECRET"]
        )
        let reopened = PDFDocument(data: result.data)
        XCTAssertFalse(reopened?.string?.localizedCaseInsensitiveContains("SECRET") == true)
        XCTAssertTrue(reopened?.string?.localizedCaseInsensitiveContains("PUBLIC") == true)
        XCTAssertEqual(reopened?.page(at: 0)?.annotations.count, 0)
        XCTAssertEqual(result.report.flattenedPages, [1])
        XCTAssertEqual(result.report.verifiedAbsentTerms, ["SECRET"])
    }

    func testInteractiveFormInspectionAndFillRoundTrip() throws {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)

        let name = PDFAnnotation(
            bounds: CGRect(x: 72, y: 650, width: 250, height: 32),
            forType: .widget,
            withProperties: nil
        )
        name.widgetFieldType = .text
        name.fieldName = "full_name"
        name.widgetStringValue = ""
        name.font = NSFont.systemFont(ofSize: 13)
        name.fontColor = .black
        name.backgroundColor = .white
        page.addAnnotation(name)

        let approved = PDFAnnotation(
            bounds: CGRect(x: 72, y: 600, width: 20, height: 20),
            forType: .widget,
            withProperties: nil
        )
        approved.widgetFieldType = .button
        approved.widgetControlType = .checkBoxControl
        approved.fieldName = "approved"
        approved.buttonWidgetState = .offState
        approved.buttonWidgetStateString = "Yes"
        page.addAnnotation(approved)
        document.insert(page, at: 0)

        let input = try XCTUnwrap(document.dataRepresentation())
        let initial = PDFOperations.formReport(for: try XCTUnwrap(PDFDocument(data: input)))
        XCTAssertEqual(initial.widgetCount, 2)
        XCTAssertEqual(initial.canonicalFieldCount, 0, "The fixture begins with orphan widgets to exercise repair")

        let result = try PDFOperations.fillForm(
            data: input,
            values: ["full_name": "Ada Lovelace", "approved": "true"]
        )
        let fields = Dictionary(uniqueKeysWithValues: result.report.fields.map { ($0.name, $0) })
        XCTAssertEqual(fields["full_name"]?.value, "Ada Lovelace")
        XCTAssertEqual(fields["approved"]?.value, "true")
        XCTAssertTrue(fields.values.allSatisfy(\.hasNormalAppearance))
        XCTAssertGreaterThanOrEqual(result.report.canonicalFieldCount, 2)
        XCTAssertTrue(result.report.isInteractive)
    }

    func testFormAuthoringCreatesCanonicalInteractiveFields() throws {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        document.insert(page, at: 0)

        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "contact", kind: .text, value: "Ada"),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 650, width: 220, height: 32)
        )
        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "approved", kind: .checkbox, value: "true"),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 600, width: 22, height: 22)
        )
        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "status", kind: .choice, value: "Review", choices: ["Draft", "Review", "Approved"]),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 550, width: 190, height: 30)
        )
        let staged = try XCTUnwrap(document.dataRepresentation())
        let stagedDocument = try XCTUnwrap(PDFDocument(data: staged))
        let stagedGate = PDFOperations.formGate(for: stagedDocument)
        XCTAssertEqual(stagedGate.level, .warning)
        XCTAssertFalse(stagedGate.issues.first(where: { $0.id == "orphan-widgets" })?.fields.isEmpty ?? true)

        let result = try PDFOperations.normalizeFormData(staged)
        XCTAssertEqual(result.report.widgetCount, 3)
        XCTAssertGreaterThanOrEqual(result.report.canonicalFieldCount, 3)
        XCTAssertEqual(Set(result.report.fields.map(\.kind)), Set([.text, .checkbox, .choice]))
        XCTAssertTrue(result.report.fields.allSatisfy(\.hasNormalAppearance))
        XCTAssertEqual(result.report.fields.first(where: { $0.name == "status" })?.value, "Review")
        XCTAssertEqual(result.report.fields.first(where: { $0.name == "approved" })?.value, "true")
        XCTAssertEqual(PDFOperations.formGate(for: result.report).level, .pass)
        XCTAssertEqual(result.report.canonicalFieldNames.sorted(), ["approved", "contact", "status"])

        XCTAssertThrowsError(try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "contact", kind: .text),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 320, y: 650, width: 180, height: 32)
        ))
    }

    func testFormRenameMovesRepeatedWidgetsAndSurvivesNormalization() throws {
        let document = PDFDocument()
        for pageIndex in 0..<2 {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: pageIndex)
            let widget = try PDFOperations.addFormField(
                PDFFormFieldDraft(name: "reviewer_\(pageIndex)", kind: .text, value: "Ada"),
                to: document,
                pageIndex: pageIndex,
                bounds: CGRect(x: 72, y: 650, width: 220, height: 32)
            )
            widget.fieldName = "reviewer"
        }

        XCTAssertEqual(try PDFOperations.renameFormField(named: "reviewer", to: "review.owner", in: document), 2)
        XCTAssertEqual(Set(PDFOperations.formReport(for: document).fields.map(\.name)), ["review.owner"])

        let normalized = try PDFOperations.normalizeFormData(try XCTUnwrap(document.dataRepresentation()))
        XCTAssertEqual(normalized.report.widgetCount, 2)
        XCTAssertEqual(Set(normalized.report.fields.map(\.name)), ["review.owner"])
        XCTAssertTrue(normalized.report.fields.allSatisfy { $0.value == "Ada" && $0.hasNormalAppearance })
        XCTAssertEqual(PDFOperations.formGate(for: normalized.report).level, .pass)
    }

    func testFormRenameRejectsCollisionsWithoutChangingFields() throws {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        document.insert(page, at: 0)
        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "source", kind: .text),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 650, width: 220, height: 32)
        )
        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "destination", kind: .text),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 600, width: 220, height: 32)
        )

        XCTAssertThrowsError(try PDFOperations.renameFormField(named: "source", to: "destination", in: document))
        XCTAssertEqual(Set(PDFOperations.formReport(for: document).fields.map(\.name)), ["source", "destination"])
    }

    func testRecipeDecodesRunsAndVerifiesFormOutput() throws {
        let document = PDFDocument()
        for index in 0..<2 {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "full_name", kind: .text),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 650, width: 220, height: 32)
        )
        let recipeJSON = """
        {
          "version": 1,
          "name": "Form intake",
          "steps": [
            {"operation":"renameField","from":"full_name","to":"review.owner"},
            {"operation":"fillForm","values":{"review.owner":"Ada"}},
            {"operation":"rotate","pages":"2","degrees":90},
            {"operation":"crop","pages":"all","insets":{"top":12,"right":12,"bottom":12,"left":12}},
            {"operation":"extract","pages":"1"}
          ]
        }
        """
        let recipe = try PDFRecipeRunner.decode(try XCTUnwrap(recipeJSON.data(using: .utf8)))
        let result = try PDFRecipeRunner.run(
            recipe,
            on: try XCTUnwrap(document.dataRepresentation()),
            dryRun: true
        )
        let reopened = try XCTUnwrap(PDFDocument(data: result.data))
        let form = PDFOperations.formReport(for: reopened)

        XCTAssertTrue(result.report.dryRun)
        XCTAssertEqual(result.report.inputPageCount, 2)
        XCTAssertEqual(result.report.outputPageCount, 1)
        XCTAssertEqual(result.report.steps.map(\.operation), ["renameField", "fillForm", "rotate", "crop", "extract"])
        XCTAssertEqual(result.report.steps.last?.pageCount, 1)
        XCTAssertEqual(form.fields.first?.name, "review.owner")
        XCTAssertEqual(form.fields.first?.value, "Ada")
        XCTAssertEqual(result.report.formGate?.level, .pass)
        XCTAssertEqual(reopened.page(at: 0)?.bounds(for: .cropBox), CGRect(x: 12, y: 12, width: 588, height: 768))
    }

    func testRecipeRejectsUnsupportedOperationsAndVersions() throws {
        let unknown = #"{"version":1,"name":"Bad","steps":[{"operation":"flatten"}]}"#
        XCTAssertThrowsError(try PDFRecipeRunner.decode(try XCTUnwrap(unknown.data(using: .utf8))))

        let future = PDFRecipe(version: 3, name: "Future", steps: [.extract(pages: "all")])
        XCTAssertThrowsError(try PDFRecipeRunner.run(future, on: try XCTUnwrap(makeDocument(pageNumbers: [1]).dataRepresentation())))

        let mismatched = PDFRecipe(version: 1, name: "Old schema", steps: [.duplicatePages(pages: "1")])
        XCTAssertThrowsError(try PDFRecipeRunner.validate(mismatched)) { error in
            XCTAssertTrue(String(describing: error).contains("requires recipe version 2"))
        }
    }

    func testRecipeV2ComposesPageOperationsOCRAndSafeShareGate() throws {
        let image = NSImage(size: NSSize(width: 420, height: 160))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        ("RECIPE OCR" as NSString).draw(
            at: NSPoint(x: 36, y: 64),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()
        let source = PDFDocument()
        source.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)

        let recipe = PDFRecipe(
            version: 2,
            name: "Searchable proof",
            steps: [
                .assertSafeShare(maximum: .warning),
                .duplicatePages(pages: "1"),
                .ocr(
                    pages: "2",
                    configuration: PDFOCRConfiguration(recognitionLevel: .fast, renderDPI: 144)
                ),
                .deletePages(pages: "1"),
                .assertPageCount(minimum: 1, maximum: 1)
            ]
        )

        let encoded = try PDFRecipeRunner.encode(recipe)
        XCTAssertEqual(try PDFRecipeRunner.decode(encoded), recipe)
        let result = try PDFRecipeRunner.run(recipe, on: try XCTUnwrap(source.dataRepresentation()))
        let reopened = try XCTUnwrap(PDFDocument(data: result.data))

        XCTAssertEqual(result.report.version, 2)
        XCTAssertEqual(result.report.inputPageCount, 1)
        XCTAssertEqual(result.report.outputPageCount, 1)
        XCTAssertEqual(
            result.report.steps.map(\.operation),
            ["assertSafeShare", "duplicatePages", "ocr", "deletePages", "assertPageCount"]
        )
        XCTAssertEqual(reopened.pageCount, 1)
    }

    func testPageDuplicationAndDeletionPreserveOrderAndRequireOnePage() throws {
        let document = makeDocument(pageNumbers: [1, 2, 3])

        XCTAssertEqual(try PDFOperations.duplicatePages(document, pageIndices: [0, 2]), 2)
        XCTAssertEqual(document.pageCount, 5)
        XCTAssertEqual((0..<5).compactMap { identity(document.page(at: $0)) }, ["PAGE-1", "PAGE-1", "PAGE-2", "PAGE-3", "PAGE-3"])

        XCTAssertEqual(try PDFOperations.deletePages(document, pageIndices: [1, 3]), 2)
        XCTAssertEqual((0..<3).compactMap { identity(document.page(at: $0)) }, ["PAGE-1", "PAGE-2", "PAGE-3"])
        XCTAssertThrowsError(try PDFOperations.deletePages(document, pageIndices: [0, 1, 2]))
        XCTAssertEqual(document.pageCount, 3)
    }

    func testRecipeAssertionsObserveCurrentDocumentState() throws {
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        document.insert(page, at: 0)
        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "source", kind: .text, value: "Ada"),
            to: document,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 650, width: 220, height: 32)
        )
        let recipe = PDFRecipe(
            name: "State assertions",
            steps: [
                .assertPageCount(minimum: 1, maximum: 1),
                .assertFields(names: ["source"]),
                .renameField(from: "source", to: "destination"),
                .assertFields(names: ["destination"]),
                .assertFormGate(maximum: .warning),
                .assertText(contains: [], excludes: ["SECRET"])
            ]
        )
        let result = try PDFRecipeRunner.run(recipe, on: try XCTUnwrap(document.dataRepresentation()), dryRun: true)
        XCTAssertEqual(result.report.steps.count, 6)
        XCTAssertEqual(result.report.steps.first?.operation, "assertPageCount")
        XCTAssertEqual(PDFOperations.formReport(for: try XCTUnwrap(PDFDocument(data: result.data))).fields.first?.name, "destination")

        let impossible = PDFRecipe(name: "Impossible", steps: [.assertPageCount(minimum: 2, maximum: nil)])
        XCTAssertThrowsError(try PDFRecipeRunner.run(impossible, on: try XCTUnwrap(document.dataRepresentation()))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Recipe step 1") || String(describing: error).contains("Recipe step 1"))
        }
    }

    func testBatchRecipeIsolatesFailedDocuments() throws {
        let passing = PDFDocument()
        let passingPage = PDFPage()
        passingPage.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        passing.insert(passingPage, at: 0)
        try PDFOperations.addFormField(
            PDFFormFieldDraft(name: "required", kind: .text),
            to: passing,
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 650, width: 220, height: 32)
        )
        let failing = makeDocument(pageNumbers: [1])
        let recipe = PDFRecipe(name: "Field intake", steps: [.assertFields(names: ["required"]), .extract(pages: "all")])
        let result = PDFRecipeBatchRunner.run(
            recipe,
            inputs: [
                PDFRecipeBatchInput(name: "passing.pdf", data: try XCTUnwrap(passing.dataRepresentation())),
                PDFRecipeBatchInput(name: "failing.pdf", data: try XCTUnwrap(failing.dataRepresentation()))
            ]
        )

        XCTAssertEqual(result.report.inputCount, 2)
        XCTAssertEqual(result.report.passedCount, 1)
        XCTAssertEqual(result.report.failedCount, 1)
        XCTAssertEqual(result.outputs.map(\.name), ["passing.pdf"])
        XCTAssertEqual(result.report.items.first(where: { $0.name == "failing.pdf" })?.status, .failed)
        XCTAssertTrue(result.report.items.first(where: { $0.name == "failing.pdf" })?.error?.contains("required") == true)
    }

    func testRecipeEncodingValidatesEditableContract() throws {
        let edited = PDFRecipe(
            name: "Review-ready proof",
            steps: [
                .assertPageCount(minimum: 1, maximum: 4),
                .rotate(pages: "all", degrees: 90)
            ]
        )
        let data = try PDFRecipeRunner.encode(edited, pretty: true)
        XCTAssertEqual(try PDFRecipeRunner.decode(data), edited)

        XCTAssertThrowsError(try PDFRecipeRunner.encode(PDFRecipe(name: "", steps: edited.steps)))
        XCTAssertThrowsError(try PDFRecipeRunner.encode(PDFRecipe(name: "Empty", steps: [])))
        XCTAssertThrowsError(
            try PDFRecipeRunner.encode(PDFRecipe(name: "Bad turn", steps: [.rotate(pages: "all", degrees: 45)]))
        )
        XCTAssertThrowsError(
            try PDFRecipeRunner.encode(PDFRecipe(name: "Bad crop", steps: [
                .crop(pages: "all", insets: PDFEdgeInsets(top: -1, right: 0, bottom: 0, left: 0))
            ]))
        )
    }

    func testRecipeLibraryVersionsDuplicatesAndRestores() throws {
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        var catalog = PDFRecipeLibraryCatalog()
        let original = PDFRecipe(name: "Library proof", steps: [.extract(pages: "all")])
        let entryID = try catalog.save(original, at: firstDate)

        let edited = PDFRecipe(name: "Library proof", steps: [
            .assertPageCount(minimum: 1, maximum: nil),
            .extract(pages: "all")
        ])
        XCTAssertEqual(try catalog.save(edited, to: entryID, at: secondDate), entryID)
        let versioned = try XCTUnwrap(catalog.entries.first { $0.id == entryID })
        XCTAssertEqual(versioned.revision, 2)
        XCTAssertEqual(versioned.history.map(\.recipe), [original])

        let duplicateID = try XCTUnwrap(catalog.duplicate(entryID, at: secondDate))
        XCTAssertEqual(catalog.entries.first { $0.id == duplicateID }?.recipe.name, "Library proof copy")
        catalog.toggleFavorite(duplicateID)
        XCTAssertEqual(catalog.entries.first { $0.id == duplicateID }?.isFavorite, true)

        let revisionID = try XCTUnwrap(versioned.history.first?.id)
        XCTAssertTrue(try catalog.restore(revisionID, in: entryID, at: Date(timeIntervalSince1970: 300)))
        let restored = try XCTUnwrap(catalog.entries.first { $0.id == entryID })
        XCTAssertEqual(restored.recipe, original)
        XCTAssertEqual(restored.revision, 3)
        XCTAssertEqual(restored.history.count, 2)
    }

    private func makeDocument(pageNumbers: [Int]) -> PDFDocument {
        let document = PDFDocument()
        for number in pageNumbers {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            let annotation = PDFAnnotation(
                bounds: CGRect(x: 20, y: 700, width: 100, height: 24),
                forType: .freeText,
                withProperties: nil
            )
            annotation.contents = "PAGE-\(number)"
            page.addAnnotation(annotation)
            document.insert(page, at: document.pageCount)
        }
        return document
    }

    private func identity(_ page: PDFPage?) -> String? {
        page?.annotations.first?.contents
    }

    func testAutomationQueueTransitionsAndRecoversInterruptedJobs() throws {
        let created = Date(timeIntervalSinceReferenceDate: 100)
        let started = Date(timeIntervalSinceReferenceDate: 200)
        let completed = Date(timeIntervalSinceReferenceDate: 300)
        let firstID = UUID(uuidString: "405D70D0-5EE0-4BB0-93C6-D54B03D86C01")!
        let secondID = UUID(uuidString: "405D70D0-5EE0-4BB0-93C6-D54B03D86C02")!
        var queue = PDFRecipeJobQueue()

        try queue.enqueue(inputPath: "/in/one.pdf", recipePath: "/recipes/a.json", outputPath: "/out/one.pdf", id: firstID, at: created)
        try queue.enqueue(inputPath: "/in/two.pdf", recipePath: "/recipes/a.json", outputPath: "/out/two.pdf", id: secondID, at: created)
        XCTAssertEqual(queue.summary.total, 2)
        XCTAssertEqual(queue.summary.queued, 2)

        XCTAssertTrue(queue.markRunning(firstID, at: started))
        XCTAssertFalse(queue.markRunning(firstID, at: started))
        XCTAssertEqual(queue.jobs[0].attempts, 1)

        let recovered = queue.prepareForRun()
        XCTAssertEqual(recovered, [firstID, secondID])
        XCTAssertEqual(queue.jobs[0].error, "Recovered after an interrupted run")
        XCTAssertTrue(queue.markRunning(firstID, at: started))
        XCTAssertTrue(queue.markFailed(firstID, error: "Fixture failure", at: completed))
        XCTAssertTrue(queue.markRunning(secondID, at: started))

        let recipeResult = try PDFRecipeRunner.run(.starter, on: makeDocument(pageNumbers: [1]).dataRepresentation()!)
        XCTAssertTrue(queue.markPassed(secondID, report: recipeResult.report, at: completed))
        XCTAssertEqual(queue.summary.queued, 0)
        XCTAssertEqual(queue.summary.running, 0)
        XCTAssertEqual(queue.summary.passed, 1)
        XCTAssertEqual(queue.summary.failed, 1)
        XCTAssertEqual(queue.jobs[0].attempts, 2)
        XCTAssertEqual(queue.jobs[1].report?.recipe, PDFRecipe.starter.name)

        XCTAssertTrue(queue.retry(firstID))
        XCTAssertEqual(queue.jobs[0].status, .queued)
        XCTAssertNil(queue.jobs[0].error)
        XCTAssertFalse(queue.retry(secondID))

        var imported = PDFRecipeJobQueue()
        let importedID = try imported.enqueue(inputPath: "/in/three.pdf", recipePath: "/recipes/b.json", outputPath: "/out/three.pdf")
        XCTAssertEqual(try queue.merge(imported), 1)
        XCTAssertEqual(try queue.merge(imported), 0)
        XCTAssertTrue(queue.remove(importedID))
        XCTAssertEqual(queue.removeFinished(), 1)
        XCTAssertEqual(queue.jobs.map(\.id), [firstID])

        var background = queue
        XCTAssertTrue(background.markRunning(firstID, at: started))
        XCTAssertTrue(background.markFailed(firstID, error: "Background failure", at: completed))
        XCTAssertEqual(try queue.applyExecutionUpdates(from: background), 1)
        XCTAssertEqual(queue.jobs[0].status, .failed)
        XCTAssertEqual(queue.jobs[0].error, "Background failure")
        XCTAssertEqual(try queue.applyExecutionUpdates(from: background), 0)
    }
}
