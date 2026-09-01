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

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
}

private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}
