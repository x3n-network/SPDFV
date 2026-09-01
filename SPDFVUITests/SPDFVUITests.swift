import AppKit
import PDFKit
import XCTest

final class SPDFVUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEmptyWorkspaceExposesOpenAndAppearanceControls() {
        let app = launchApplication()

        XCTAssertTrue(app.buttons["document.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["document.empty"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["document.window"].exists)
    }

    func testDocumentWorkspaceExposesNavigationAndAutomationControls() throws {
        let fixture = try makePDF()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = launchApplication(documentURL: fixture)

        XCTAssertTrue(app.descendants(matching: .any)["document.pdf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace.read"].exists)
        XCTAssertTrue(app.buttons["workspace.markup"].exists)
        XCTAssertTrue(app.buttons["workspace.organize"].exists)
        XCTAssertTrue(app.buttons["workspace.automate"].exists)
        XCTAssertTrue(app.buttons["navigator.pages"].exists)
        XCTAssertTrue(app.buttons["page.jump"].exists)

        app.buttons["workspace.automate"].click()
        XCTAssertTrue(app.buttons["automation.recipe"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["automation.ocr"].exists)
        XCTAssertTrue(app.buttons["automation.redaction"].exists)
        XCTAssertTrue(app.buttons["automation.activity"].exists)
    }

    func testLockedDocumentCanBeUnlocked() throws {
        let fixture = try makePDF(password: "reader-secret")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = launchApplication(documentURL: fixture)

        XCTAssertTrue(app.descendants(matching: .any)["document.locked"].waitForExistence(timeout: 5))
        let password = app.secureTextFields["document.unlock.password"]
        XCTAssertTrue(password.exists)
        password.click()
        password.typeText("reader-secret")
        app.buttons["document.unlock.submit"].click()

        XCTAssertTrue(app.descendants(matching: .any)["document.pdf"].waitForExistence(timeout: 5))
    }

    func testDocumentHealthToolsProduceReports() throws {
        let fixture = try makePDF()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = launchApplication(documentURL: fixture)

        XCTAssertTrue(app.descendants(matching: .any)["document.pdf"].waitForExistence(timeout: 5))
        selectButton(app.buttons["navigator.info"])

        let doctor = app.buttons["doctor.run"]
        XCTAssertTrue(doctor.waitForExistence(timeout: 2))
        doctor.click()
        XCTAssertTrue(app.descendants(matching: .any)["doctor.report"].waitForExistence(timeout: 2))

        let safeShare = app.buttons["safe-share.run"]
        XCTAssertTrue(safeShare.waitForExistence(timeout: 2))
        safeShare.click()
        XCTAssertTrue(app.descendants(matching: .any)["safe-share.report"].waitForExistence(timeout: 2))

        XCTAssertTrue(app.buttons["compare.choose-reference"].exists)
    }

    func testFormDataStudioIsAvailableForInteractiveForms() throws {
        let fixture = try makePDF(withTextField: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = launchApplication(documentURL: fixture)

        XCTAssertTrue(app.descendants(matching: .any)["document.pdf"].waitForExistence(timeout: 5))
        selectButton(app.buttons["navigator.forms"])
        selectButton(app.buttons["forms.workbench.data"])

        XCTAssertTrue(app.buttons["form-data.import"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["form-data.export"].exists)
        XCTAssertTrue(app.buttons["form-data.export"].isEnabled)
    }

    func testRecipePressLoadsStarterRecipe() throws {
        let fixture = try makePDF()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = launchApplication(documentURL: fixture)

        XCTAssertTrue(app.descendants(matching: .any)["document.pdf"].waitForExistence(timeout: 5))
        app.buttons["workspace.automate"].click()
        app.buttons["automation.recipe"].click()

        XCTAssertTrue(app.descendants(matching: .any)["recipe.panel"].waitForExistence(timeout: 3))
        app.buttons["recipe.use-starter"].click()
        XCTAssertTrue(app.descendants(matching: .any)["recipe.loaded"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["recipe.dry-run"].exists)
    }

    private func launchApplication(documentURL: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        if let documentURL {
            app.launchEnvironment["SPDFV_UI_TEST_PDF"] = documentURL.path
        }
        app.launch()
        return app
    }

    private func selectButton(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        button.click()
        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: button)
        waitForExpectations(timeout: 2)
    }

    private func makePDF(password: String? = nil, withTextField: Bool = false) throws -> URL {
        let image = NSImage(size: NSSize(width: 360, height: 480))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        ("SPDFV UI TEST" as NSString).draw(
            at: NSPoint(x: 72, y: 220),
            withAttributes: [.foregroundColor: NSColor.black]
        )
        image.unlockFocus()

        let document = PDFDocument()
        let page = try XCTUnwrap(PDFPage(image: image))
        if withTextField {
            let field = PDFAnnotation(
                bounds: CGRect(x: 72, y: 120, width: 216, height: 28),
                forType: .widget,
                withProperties: nil
            )
            field.widgetFieldType = .text
            field.fieldName = "contact.name"
            field.widgetStringValue = "Ada Lovelace"
            page.addAnnotation(field)
        }
        document.insert(page, at: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spdfv-ui-tests-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        if let password {
            let data = try XCTUnwrap(document.dataRepresentation(options: [
                PDFDocumentWriteOption.ownerPasswordOption: "owner-secret",
                PDFDocumentWriteOption.userPasswordOption: password
            ]))
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } else {
            guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        }
        return url
    }
}
