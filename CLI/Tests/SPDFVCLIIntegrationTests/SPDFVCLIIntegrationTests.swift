import Foundation
import PDFKit
import SPDFVCore
import XCTest

final class SPDFVCLIIntegrationTests: XCTestCase {
    func testInspectEmitsStableJSONForRoundTripFixture() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("compatibility.pdf")
            try makeCompatibilityFixture().write(to: input)

            let result = try runCLI(["inspect", input.path, "--pretty"])

            XCTAssertEqual(result.status, 0, result.stderr)
            XCTAssertTrue(result.stderr.isEmpty)
            let report = try jsonObject(result.stdout)
            XCTAssertEqual(report["pages"] as? Int, 2)
            XCTAssertEqual(report["encrypted"] as? Bool, false)
            XCTAssertEqual((report["metadata"] as? [String: Any])?["title"] as? String, "SPDFV Compatibility Fixture")

            let pages = try XCTUnwrap(report["pageDetails"] as? [[String: Any]])
            XCTAssertEqual(pages.map { $0["page"] as? Int }, [1, 2])
            XCTAssertEqual(pages.map { $0["rotation"] as? Int }, [0, 90])
        }
    }

    func testRotateWritesReopenablePDFAndProtectsExistingOutput() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("input.pdf")
            let output = directory.appendingPathComponent("rotated.pdf")
            try makeCompatibilityFixture().write(to: input)

            let first = try runCLI([
                "rotate", input.path,
                "--pages", "2",
                "--degrees", "90",
                "--output", output.path
            ])

            XCTAssertEqual(first.status, 0, first.stderr)
            let report = try jsonObject(first.stdout)
            XCTAssertEqual(report["operation"] as? String, "rotate")
            XCTAssertEqual(report["pages"] as? [Int], [2])
            XCTAssertEqual(report["pageCount"] as? Int, 2)

            let reopened = try XCTUnwrap(PDFDocument(url: output))
            XCTAssertEqual(reopened.pageCount, 2)
            XCTAssertEqual(reopened.page(at: 0)?.rotation, 0)
            XCTAssertEqual(reopened.page(at: 1)?.rotation, 180)

            let second = try runCLI([
                "rotate", input.path,
                "--pages", "2",
                "--degrees", "90",
                "--output", output.path
            ])
            XCTAssertEqual(second.status, 1)
            XCTAssertTrue(second.stdout.isEmpty)
            XCTAssertTrue(second.stderr.contains("Output already exists"))
        }
    }

    func testUnknownCommandUsesUsageExitCodeAndStderr() throws {
        let result = try runCLI(["not-a-command"])

        XCTAssertEqual(result.status, 64)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.hasPrefix("spdfv: Unknown command: not-a-command"))
        XCTAssertTrue(result.stderr.contains("USAGE"))
    }

    func testSafetyGateEmitsMachineReadablePreflight() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("compatibility.pdf")
            try makeCompatibilityFixture().write(to: input)

            let result = try runCLI(["safety-gate", input.path, "--pretty"])

            XCTAssertEqual(result.status, 0, result.stderr)
            let wrapper = try jsonObject(result.stdout)
            let gate = try XCTUnwrap(wrapper["gate"] as? [String: Any])
            XCTAssertEqual(gate["level"] as? String, "pass")
            XCTAssertEqual(gate["encrypted"] as? Bool, false)
            XCTAssertEqual(gate["locked"] as? Bool, false)
            XCTAssertEqual(gate["certificateSignatureFields"] as? [String], [])
            XCTAssertEqual((gate["issues"] as? [[String: Any]])?.count, 0)
            let permissions = try XCTUnwrap(gate["permissions"] as? [String: Any])
            XCTAssertEqual(permissions["documentChanges"] as? Bool, true)
            XCTAssertEqual(permissions["documentAssembly"] as? Bool, true)
            XCTAssertEqual(permissions["formFieldEntry"] as? Bool, true)
        }
    }

    func testSignatureVerificationReportsUnsignedPDFWithoutClaimingValidity() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("unsigned.pdf")
            try makeCompatibilityFixture().write(to: input)

            let result = try runCLI(["verify-signatures", input.path, "--pretty"])

            XCTAssertEqual(result.status, 0, result.stderr)
            let report = try XCTUnwrap(try jsonObject(result.stdout)["report"] as? [String: Any])
            XCTAssertEqual(report["status"] as? String, "none")
            XCTAssertEqual(report["embeddedSignatureCount"] as? Int, 0)
            XCTAssertEqual(report["signatureFieldCount"] as? Int, 0)
        }
    }

    func testSafetyGateStopsLockedDocumentWithoutReadingContent() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("locked.pdf")
            let source = try XCTUnwrap(PDFDocument(data: makeCompatibilityFixture()))
            let options: [PDFDocumentWriteOption: Any] = [
                .ownerPasswordOption: "owner-secret",
                .userPasswordOption: "user-secret",
                .accessPermissionsOption: NSNumber(value: 0)
            ]
            try XCTUnwrap(source.dataRepresentation(options: options)).write(to: input)

            let result = try runCLI(["safety-gate", input.path, "--pretty"])

            XCTAssertEqual(result.status, 0, result.stderr)
            let wrapper = try jsonObject(result.stdout)
            let gate = try XCTUnwrap(wrapper["gate"] as? [String: Any])
            XCTAssertEqual(gate["level"] as? String, "stop")
            XCTAssertEqual(gate["encrypted"] as? Bool, true)
            XCTAssertEqual(gate["locked"] as? Bool, true)
            let issues = try XCTUnwrap(gate["issues"] as? [[String: Any]])
            XCTAssertEqual(issues.map { $0["id"] as? String }, ["locked-document"])
        }
    }

    func testSafeShareEmitsPrivacyPreservingHazardReport() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("review-copy.pdf")
            try makeCompatibilityFixture().write(to: input)

            let result = try runCLI(["safe-share", input.path, "--pretty"])

            XCTAssertEqual(result.status, 0, result.stderr)
            XCTAssertTrue(result.stderr.isEmpty)
            let wrapper = try jsonObject(result.stdout)
            let report = try XCTUnwrap(wrapper["report"] as? [String: Any])
            XCTAssertEqual(report["level"] as? String, "warning")
            let metadataKeys = Set(try XCTUnwrap(report["metadataKeys"] as? [String]))
            XCTAssertTrue(metadataKeys.isSuperset(of: ["title", "author"]))
            XCTAssertTrue(metadataKeys.contains("producer"))
            XCTAssertEqual(report["reviewAnnotationCount"] as? Int, 2)
            XCTAssertEqual(report["reviewAnnotationPages"] as? [Int], [1, 2])
            XCTAssertEqual(report["annotationsWithContents"] as? Int, 2)
            XCTAssertEqual(
                (report["findings"] as? [[String: Any]])?.compactMap { $0["id"] as? String },
                ["document-metadata", "review-annotations"]
            )
            XCTAssertFalse(result.stdout.contains("SPDFV Compatibility Fixture"))
            XCTAssertFalse(result.stdout.contains("SPDFV Tests"))
            XCTAssertFalse(result.stdout.contains("Fixture page 1"))
        }
    }

    func testAnnotationsFiltersPagesAndEmitsCanonicalRecords() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("annotations.pdf")
            try makeCompatibilityFixture().write(to: input)

            let result = try runCLI(["annotations", input.path, "--pages", "2", "--pretty"])

            XCTAssertEqual(result.status, 0, result.stderr)
            let report = try jsonObject(result.stdout)
            XCTAssertEqual(report["pages"] as? [Int], [2])
            XCTAssertEqual(report["count"] as? Int, 1)
            let annotations = try XCTUnwrap(report["annotations"] as? [[String: Any]])
            XCTAssertEqual(annotations.first?["page"] as? Int, 2)
            XCTAssertEqual(annotations.first?["contents"] as? String, "Fixture page 2")
        }
    }

    func testExtractMergeAndCropProduceReopenablePageGeometry() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("input.pdf")
            let extracted = directory.appendingPathComponent("extracted.pdf")
            let merged = directory.appendingPathComponent("merged.pdf")
            let cropped = directory.appendingPathComponent("cropped.pdf")
            try makeCompatibilityFixture().write(to: input)

            let extractResult = try runCLI([
                "extract", input.path, "--pages", "2", "--output", extracted.path
            ])
            XCTAssertEqual(extractResult.status, 0, extractResult.stderr)
            XCTAssertEqual(try jsonObject(extractResult.stdout)["pages"] as? [Int], [2])
            XCTAssertEqual(PDFDocument(url: extracted)?.pageCount, 1)

            let mergeResult = try runCLI([
                "merge", extracted.path, input.path, "--output", merged.path
            ])
            XCTAssertEqual(mergeResult.status, 0, mergeResult.stderr)
            XCTAssertEqual(try jsonObject(mergeResult.stdout)["pageCount"] as? Int, 3)

            let media = try XCTUnwrap(PDFDocument(url: merged)?.page(at: 0)?.bounds(for: .mediaBox))
            let cropResult = try runCLI([
                "crop", merged.path, "--pages", "1", "--insets", "10", "--output", cropped.path
            ])
            XCTAssertEqual(cropResult.status, 0, cropResult.stderr)
            let reopened = try XCTUnwrap(PDFDocument(url: cropped))
            let after = try XCTUnwrap(reopened.page(at: 0)?.bounds(for: .cropBox))
            XCTAssertEqual(after.width, media.width - 20, accuracy: 0.01)
            XCTAssertEqual(after.height, media.height - 20, accuracy: 0.01)
            XCTAssertEqual(reopened.pageCount, 3)
        }
    }

    func testFormAuthorFillAndRenameRoundTrip() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("input.pdf")
            let authored = directory.appendingPathComponent("authored.pdf")
            let filled = directory.appendingPathComponent("filled.pdf")
            let renamed = directory.appendingPathComponent("renamed.pdf")
            try makeCompatibilityFixture().write(to: input)

            let addResult = try runCLI([
                "add-field", input.path,
                "--page", "1", "--type", "text", "--name", "reviewer",
                "--bounds", "72,420,220,32", "--output", authored.path
            ])
            XCTAssertEqual(addResult.status, 0, addResult.stderr)
            XCTAssertEqual((try jsonObject(addResult.stdout)["field"] as? [String: Any])?["name"] as? String, "reviewer")

            let fillResult = try runCLI([
                "fill-form", authored.path,
                "--values", "{\"reviewer\":\"Ada\"}", "--output", filled.path
            ])
            XCTAssertEqual(fillResult.status, 0, fillResult.stderr)
            XCTAssertEqual(try jsonObject(fillResult.stdout)["updatedFields"] as? [String], ["reviewer"])

            let renameResult = try runCLI([
                "rename-field", filled.path,
                "--from", "reviewer", "--to", "review.owner", "--output", renamed.path
            ])
            XCTAssertEqual(renameResult.status, 0, renameResult.stderr)
            XCTAssertEqual(try jsonObject(renameResult.stdout)["widgetCount"] as? Int, 1)

            let reopened = try XCTUnwrap(PDFDocument(url: renamed))
            let widget = try XCTUnwrap(reopened.page(at: 0)?.annotations.first(where: { $0.fieldName == "review.owner" }))
            XCTAssertEqual(widget.widgetStringValue, "Ada")
        }
    }

    func testRecipeTemplateValidateEnqueueAndRunQueue() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("input.pdf")
            let recipe = directory.appendingPathComponent("recipe.json")
            let output = directory.appendingPathComponent("output.pdf")
            let queue = directory.appendingPathComponent("queue.json")
            try makeCompatibilityFixture().write(to: input)

            let templateResult = try runCLI(["recipe-template"])
            XCTAssertEqual(templateResult.status, 0, templateResult.stderr)
            try XCTUnwrap(templateResult.stdout.data(using: .utf8)).write(to: recipe)

            let validateResult = try runCLI([
                "validate-recipe", input.path, "--recipe", recipe.path
            ])
            XCTAssertEqual(validateResult.status, 0, validateResult.stderr)
            let validation = try XCTUnwrap(try jsonObject(validateResult.stdout)["report"] as? [String: Any])
            XCTAssertEqual(validation["dryRun"] as? Bool, true)
            XCTAssertEqual(validation["outputPageCount"] as? Int, 2)

            let enqueueResult = try runCLI([
                "enqueue-recipe", input.path,
                "--recipe", recipe.path, "--output", output.path, "--queue", queue.path
            ])
            XCTAssertEqual(enqueueResult.status, 0, enqueueResult.stderr)
            XCTAssertEqual((try jsonObject(enqueueResult.stdout)["summary"] as? [String: Any])?["queued"] as? Int, 1)

            let runResult = try runCLI(["run-queue", "--queue", queue.path])
            XCTAssertEqual(runResult.status, 0, runResult.stderr)
            let summary = try XCTUnwrap(try jsonObject(runResult.stdout)["summary"] as? [String: Any])
            XCTAssertEqual(summary["passed"] as? Int, 1)
            XCTAssertEqual(summary["failed"] as? Int, 0)
            XCTAssertEqual(PDFDocument(url: output)?.pageCount, 2)

            let statusResult = try runCLI(["queue-status", "--queue", queue.path])
            XCTAssertEqual(statusResult.status, 0, statusResult.stderr)
            XCTAssertEqual((try jsonObject(statusResult.stdout)["summary"] as? [String: Any])?["passed"] as? Int, 1)
        }
    }

    func testRecipeV2RunsPageOCRAndSafeSharePlates() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("input.pdf")
            let recipe = directory.appendingPathComponent("recipe-v2.json")
            let output = directory.appendingPathComponent("output.pdf")
            try makeCompatibilityFixture().write(to: input)
            let recipeJSON = #"""
            {
              "version": 2,
              "name": "Searchable review copy",
              "steps": [
                {"operation":"duplicatePages","pages":"1"},
                {"operation":"ocr","pages":"2","configuration":{"recognitionLevel":"fast","languages":[],"usesLanguageCorrection":true,"renderDPI":144}},
                {"operation":"deletePages","pages":"1"},
                {"operation":"assertSafeShare","maximum":"warning"}
              ]
            }
            """#
            try XCTUnwrap(recipeJSON.data(using: .utf8)).write(to: recipe)

            let validation = try runCLI([
                "validate-recipe", input.path, "--recipe", recipe.path, "--pretty"
            ])
            XCTAssertEqual(validation.status, 0, validation.stderr)
            let validationReport = try XCTUnwrap(try jsonObject(validation.stdout)["report"] as? [String: Any])
            XCTAssertEqual(validationReport["version"] as? Int, 2)
            XCTAssertEqual(validationReport["outputPageCount"] as? Int, 2)

            let run = try runCLI([
                "run-recipe", input.path, "--recipe", recipe.path, "--output", output.path, "--pretty"
            ])
            XCTAssertEqual(run.status, 0, run.stderr)
            XCTAssertEqual(PDFDocument(url: output)?.pageCount, 2)
            let report = try XCTUnwrap(try jsonObject(run.stdout)["report"] as? [String: Any])
            let steps = try XCTUnwrap(report["steps"] as? [[String: Any]])
            XCTAssertEqual(
                steps.compactMap { $0["operation"] as? String },
                ["duplicatePages", "ocr", "deletePages", "assertSafeShare"]
            )
        }
    }

    func testRecipeV3AcceptsContextAndUsesOutputTemplate() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("input.pdf")
            let authored = directory.appendingPathComponent("authored.pdf")
            let recipeURL = directory.appendingPathComponent("recipe-v3.json")
            let formDataURL = directory.appendingPathComponent("values.json")
            try makeCompatibilityFixture().write(to: input)
            let author = try runCLI([
                "add-field", input.path, "--page", "1", "--type", "text",
                "--name", "review.owner", "--bounds", "72,520,220,32", "--output", authored.path
            ])
            XCTAssertEqual(author.status, 0, author.stderr)
            try Data(#"{"version":1,"fields":[{"name":"review.owner","value":"Grace"}]}"#.utf8).write(to: formDataURL)

            let recipe = PDFRecipe(
                version: 3,
                name: "CLI v3",
                steps: [
                    .importFormData(source: "intake"),
                    .ifParameter(name: "mode", equals: "production", steps: [
                        .fillForm(values: ["review.owner": "{{owner}}"])
                    ]),
                    .assertCompare(reference: "baseline", maximumChangedPages: 1, options: PDFComparisonOptions()),
                    .assertDoctor(maximum: .critical)
                ],
                parameters: [PDFRecipeParameter(name: "mode"), PDFRecipeParameter(name: "owner")],
                outputNameTemplate: "{{inputName}}-{{owner}}.pdf"
            )
            try PDFRecipeRunner.encode(recipe).write(to: recipeURL)

            let result = try runCLI([
                "run-recipe", authored.path, "--recipe", recipeURL.path, "--output-dir", directory.path,
                "--parameters", #"{"mode":"production","owner":"Ada"}"#,
                "--references", #"{"baseline":"\#(authored.path)"}"#,
                "--form-data", #"{"intake":"\#(formDataURL.path)"}"#,
                "--pretty"
            ])

            XCTAssertEqual(result.status, 0, result.stderr)
            let output = directory.appendingPathComponent("authored-Ada.pdf")
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
            let reopened = try XCTUnwrap(PDFDocument(url: output))
            XCTAssertEqual(PDFOperations.formReport(for: reopened).fields.first { $0.name == "review.owner" }?.value, "Ada")
            let report = try XCTUnwrap(try jsonObject(result.stdout)["report"] as? [String: Any])
            XCTAssertEqual(report["suggestedOutputName"] as? String, "authored-Ada.pdf")
        }
    }

    func testCompareEmitsPageByPageMachineReadableReport() throws {
        try withFixtureDirectory { directory in
            let referenceURL = directory.appendingPathComponent("reference.pdf")
            let candidateURL = directory.appendingPathComponent("candidate.pdf")
            let fixture = try makeCompatibilityFixture()
            try fixture.write(to: referenceURL)
            let candidate = try XCTUnwrap(PDFDocument(data: fixture))
            candidate.page(at: 0)?.rotation = 90
            let added = PDFPage()
            added.setBounds(CGRect(x: 0, y: 0, width: 420, height: 600), for: .mediaBox)
            candidate.insert(added, at: candidate.pageCount)
            try XCTUnwrap(candidate.dataRepresentation()).write(to: candidateURL)

            let result = try runCLI([
                "compare", referenceURL.path, candidateURL.path,
                "--alignment", "intelligent",
                "--appearance-threshold", "0.995",
                "--ignore-regions", "0,0,0.1,0.1;0.9,0.9,0.1,0.1",
                "--pretty"
            ])

            XCTAssertEqual(result.status, 0, result.stderr)
            let wrapper = try jsonObject(result.stdout)
            XCTAssertEqual(wrapper["operation"] as? String, "compare")
            let report = try XCTUnwrap(wrapper["report"] as? [String: Any])
            XCTAssertEqual(report["status"] as? String, "changed")
            XCTAssertEqual(report["referencePageCount"] as? Int, 2)
            XCTAssertEqual(report["candidatePageCount"] as? Int, 3)
            XCTAssertEqual(report["addedPages"] as? Int, 1)
            let options = try XCTUnwrap(report["options"] as? [String: Any])
            XCTAssertEqual(options["alignment"] as? String, "intelligent")
            XCTAssertEqual(options["minimumAppearanceSimilarity"] as? Double, 0.995)
            XCTAssertEqual((options["ignoredRegions"] as? [[String: Any]])?.count, 2)
            let pages = try XCTUnwrap(report["pages"] as? [[String: Any]])
            XCTAssertEqual(pages.map { $0["status"] as? String }, ["changed", "unchanged", "added"])
            XCTAssertTrue((pages[0]["differences"] as? [String])?.contains("rotation") == true)
        }
    }

    func testFormDataExportValidateAndImportJourney() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("input.pdf")
            let authored = directory.appendingPathComponent("authored.pdf")
            let exported = directory.appendingPathComponent("values.json")
            let importedData = directory.appendingPathComponent("updated.json")
            let filled = directory.appendingPathComponent("filled.pdf")
            try makeCompatibilityFixture().write(to: input)

            let author = try runCLI([
                "add-field", input.path, "--page", "1", "--type", "text",
                "--name", "full_name", "--value", "Ada", "--bounds", "72,520,220,32",
                "--output", authored.path
            ])
            XCTAssertEqual(author.status, 0, author.stderr)

            let export = try runCLI([
                "export-form-data", authored.path, "--output", exported.path, "--pretty"
            ])
            XCTAssertEqual(export.status, 0, export.stderr)
            XCTAssertEqual(try jsonObject(export.stdout)["fields"] as? Int, 1)
            let exportedJSON = try jsonObject(String(decoding: Data(contentsOf: exported), as: UTF8.self))
            XCTAssertEqual(exportedJSON["version"] as? Int, 1)

            let update = #"{"version":1,"fields":[{"name":"full_name","value":"Grace"}]}"#
            try XCTUnwrap(update.data(using: .utf8)).write(to: importedData)
            let validation = try runCLI([
                "validate-form-data", authored.path, "--data", importedData.path, "--pretty"
            ])
            XCTAssertEqual(validation.status, 0, validation.stderr)
            let validationReport = try XCTUnwrap(try jsonObject(validation.stdout)["report"] as? [String: Any])
            XCTAssertEqual(validationReport["canApply"] as? Bool, true)
            XCTAssertEqual(validationReport["updatedFields"] as? [String], ["full_name"])

            let imported = try runCLI([
                "import-form-data", authored.path, "--data", importedData.path,
                "--output", filled.path, "--pretty"
            ])
            XCTAssertEqual(imported.status, 0, imported.stderr)
            let forms = try runCLI(["forms", filled.path, "--pretty"])
            XCTAssertEqual(forms.status, 0, forms.stderr)
            let formReport = try XCTUnwrap(try jsonObject(forms.stdout)["report"] as? [String: Any])
            let fields = try XCTUnwrap(formReport["fields"] as? [[String: Any]])
            XCTAssertEqual(fields.first { $0["name"] as? String == "full_name" }?["value"] as? String, "Grace")
        }
    }

    func testDoctorEmitsPrioritizedPrivacyConsciousReport() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("diagnostic.pdf")
            try makeCompatibilityFixture().write(to: input)

            let result = try runCLI(["doctor", input.path, "--pretty"])

            XCTAssertEqual(result.status, 0, result.stderr)
            let wrapper = try jsonObject(result.stdout)
            let report = try XCTUnwrap(wrapper["report"] as? [String: Any])
            XCTAssertEqual(report["level"] as? String, "attention")
            XCTAssertEqual(report["pageCount"] as? Int, 2)
            XCTAssertEqual(report["rotatedPages"] as? Int, 1)
            let issues = try XCTUnwrap(report["issues"] as? [[String: Any]])
            XCTAssertTrue(issues.contains { $0["id"] as? String == "mixed-page-sizes" })
            XCTAssertTrue(issues.contains { $0["id"] as? String == "privacy-document-metadata" })
            let plan = try XCTUnwrap(wrapper["plan"] as? [String: Any])
            let items = try XCTUnwrap(plan["items"] as? [[String: Any]])
            XCTAssertTrue(items.contains { $0["action"] as? String == "removeMetadata" })
            XCTAssertFalse(result.stdout.contains("SPDFV Compatibility Fixture"))
        }
    }

    func testBatchFormDataPreflightsThenWritesOnePDFPerCSVRow() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("template.pdf")
            let table = directory.appendingPathComponent("rows.csv")
            let mappingURL = directory.appendingPathComponent("mapping.json")
            let outputDirectory = directory.appendingPathComponent("completed", isDirectory: true)
            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: 0)
            try PDFOperations.addFormField(
                PDFFormFieldDraft(name: "full_name", kind: .text),
                to: document,
                pageIndex: 0,
                bounds: CGRect(x: 72, y: 650, width: 220, height: 32)
            )
            try XCTUnwrap(document.dataRepresentation()).write(to: input)
            try Data("Person,Case\nAda Lovelace,101\nGrace Hopper,102\n".utf8).write(to: table)
            let mapping = PDFFormDataBatchMapping(
                columns: [PDFFormDataColumnMapping(column: "Person", field: "full_name")],
                filenameTemplate: "case-{Case}.pdf"
            )
            try PDFOperations.encodeFormDataBatchMapping(mapping).write(to: mappingURL)

            let preview = try runCLI([
                "batch-form-data", input.path, "--data", table.path,
                "--mapping", mappingURL.path, "--dry-run", "--pretty"
            ])
            XCTAssertEqual(preview.status, 0, preview.stderr)
            let previewReport = try XCTUnwrap(try jsonObject(preview.stdout)["report"] as? [String: Any])
            XCTAssertEqual(previewReport["canWrite"] as? Bool, true)
            XCTAssertEqual(previewReport["validRows"] as? Int, 2)
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))

            let run = try runCLI([
                "batch-form-data", input.path, "--data", table.path,
                "--mapping", mappingURL.path, "--output-dir", outputDirectory.path, "--pretty"
            ])
            XCTAssertEqual(run.status, 0, run.stderr)
            let names = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).sorted()
            XCTAssertEqual(names, ["case-101.pdf", "case-102.pdf"])
            let first = try XCTUnwrap(PDFDocument(url: outputDirectory.appendingPathComponent(names[0])))
            XCTAssertEqual(PDFOperations.formReport(for: first).fields.first?.value, "Ada Lovelace")
        }
    }

    func testDoctorRepairWritesVerifiedMetadataCleanCopy() throws {
        try withFixtureDirectory { directory in
            let input = directory.appendingPathComponent("diagnostic.pdf")
            let output = directory.appendingPathComponent("repaired.pdf")
            try makeCompatibilityFixture().write(to: input)

            let result = try runCLI([
                "doctor-repair", input.path, "--actions", "metadata",
                "--output", output.path, "--pretty"
            ])

            XCTAssertEqual(result.status, 0, result.stderr)
            let wrapper = try jsonObject(result.stdout)
            let verification = try XCTUnwrap(wrapper["verification"] as? [String: Any])
            XCTAssertEqual(verification["pageCountPreserved"] as? Bool, true)
            XCTAssertEqual(verification["appliedActions"] as? [String], ["removeMetadata"])
            let repaired = try XCTUnwrap(PDFDocument(url: output))
            XCTAssertTrue(PDFOperations.safeShareAudit(for: repaired).metadataKeys.isEmpty)
            let original = try XCTUnwrap(PDFDocument(url: input))
            XCTAssertFalse(PDFOperations.safeShareAudit(for: original).metadataKeys.isEmpty)
        }
    }

    func testCheckedInCompatibilityCorpusMatchesManifest() throws {
        let corpus = packageRootURL().deletingLastPathComponent()
            .appendingPathComponent("CompatibilityCorpus", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            CompatibilityManifest.self,
            from: Data(contentsOf: corpus.appendingPathComponent("manifest.json"))
        )

        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.license, "MIT")
        XCTAssertFalse(manifest.fixtures.isEmpty)

        for fixture in manifest.fixtures {
            let input = corpus.appendingPathComponent(fixture.file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: input.path), fixture.file)
            let document = try XCTUnwrap(PDFDocument(url: input), fixture.file)
            XCTAssertEqual(document.isLocked, fixture.locked, fixture.file)
            XCTAssertEqual(document.pageCount, fixture.pageCount, fixture.file)

            if fixture.locked {
                let result = try runCLI(["safety-gate", input.path])
                XCTAssertEqual(result.status, 0, result.stderr)
                let gate = try XCTUnwrap(try jsonObject(result.stdout)["gate"] as? [String: Any])
                XCTAssertEqual(gate["level"] as? String, "stop")
                XCTAssertEqual(gate["locked"] as? Bool, true)
            } else {
                let result = try runCLI(["inspect", input.path])
                XCTAssertEqual(result.status, 0, result.stderr)
                XCTAssertEqual(try jsonObject(result.stdout)["pages"] as? Int, fixture.pageCount)
            }

            if !fixture.expectedFields.isEmpty {
                let result = try runCLI(["forms", input.path])
                XCTAssertEqual(result.status, 0, result.stderr)
                let report = try XCTUnwrap(try jsonObject(result.stdout)["report"] as? [String: Any])
                let fields = try XCTUnwrap(report["fields"] as? [[String: Any]])
                XCTAssertEqual(fields.compactMap { $0["name"] as? String }.sorted(), fixture.expectedFields)
            }
        }
    }

    private func makeCompatibilityFixture() throws -> Data {
        let document = PDFDocument()
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "SPDFV Compatibility Fixture",
            PDFDocumentAttribute.authorAttribute: "SPDFV Tests"
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
            annotation.contents = "Fixture page \(index + 1)"
            page.addAnnotation(annotation)
            document.insert(page, at: document.pageCount)
        }

        return try XCTUnwrap(document.dataRepresentation())
    }

    private func withFixtureDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SPDFVCLIIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func jsonObject(_ value: String) throws -> [String: Any] {
        let data = try XCTUnwrap(value.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func runCLI(_ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = try cliExecutableURL()
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func cliExecutableURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SPDFV_CLI_EXECUTABLE"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        let packageRoot = packageRootURL()
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/spdfv"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/spdfv"),
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/spdfv"),
            packageRoot.appendingPathComponent(".build/release/spdfv"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/release/spdfv"),
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/release/spdfv")
        ]
        return try XCTUnwrap(
            candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }),
            "The spdfv executable was not built before the integration tests."
        )
    }

    private func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct CompatibilityManifest: Decodable {
    let version: Int
    let license: String
    let fixtures: [CompatibilityFixture]
}

private struct CompatibilityFixture: Decodable {
    let file: String
    let purpose: String
    let pageCount: Int
    let locked: Bool
    let expectedFields: [String]
}

private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}
