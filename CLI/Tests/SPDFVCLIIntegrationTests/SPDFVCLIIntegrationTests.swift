import Foundation
import PDFKit
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
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/spdfv")
        ]
        return try XCTUnwrap(
            candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }),
            "The spdfv debug executable was not built before the integration tests."
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
