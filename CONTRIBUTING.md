# Contributing to SPDFV

SPDFV is a macOS application with a shared core and CLI. Changes should preserve the same PDF behavior across those surfaces whenever the operation belongs in `SPDFVCore`.

## Before opening a change

1. Run the `SPDFVTests` target with signing disabled and build the UI automation bundle with `build-for-testing`.
2. Run `swift test --package-path Core`.
3. Run `swift test --package-path CLI`; if the shared core changed, also exercise the relevant command manually.
4. Test both light and dark appearance for visible interface changes.
5. Test with a copy of the PDF, especially for forms, redaction, page deletion, and saving.

## Code shape

- Keep PDF transformations in `Core` when they can be independent of the app interface.
- Keep AppKit and SwiftUI coordination in the app target.
- Do not add network processing for document content without an explicit design discussion.
- Protect existing output files unless an operation clearly asks for replacement.
- Prefer focused changes over broad restyling or renaming.

## Compatibility tests

App tests use small generated PDFs to verify `DocumentSession` state transitions without checking in document fixtures. Add a focused state assertion when changing document opening, unlocking, saving, page selection, edit history, or recipe composition behavior.

UI tests launch deterministic generated PDFs through the debug-only `SPDFV_UI_TEST_PDF` environment variable. Keep stable `document.*`, `workspace.*`, `navigator.*`, `page.*`, and `automation.*` accessibility identifiers on critical controls. Running UI automation locally requires Accessibility permission for the Xcode test runner.

CLI integration tests generate deterministic PDFKit fixtures at runtime and exercise the compiled `spdfv` executable. Keep fixtures small and focused on one compatibility behavior. When a bug requires an external PDF, use a redistributable, non-sensitive sample, record its source and license, and add a save/reopen assertion that captures the regression.

`CompatibilityCorpus` provides stable checked-in bytes for recurring interoperability cases. Every entry must be non-sensitive, listed in `manifest.json`, include provenance and license information, and be exercised by the manifest-backed CLI test. Use the generator for project-owned fixtures; PDFKit may refresh internal identifiers and encryption salts, so review semantic expectations rather than expecting regenerated hashes to match.

Core performance tests record XCTest clock metrics for large-document inspection and multi-step recipes. Keep correctness assertions inside measured work, compare measurements on similar hardware, and establish Xcode baselines deliberately instead of adding tight wall-clock assertions that make CI hardware variance look like a regression.

## Contribution license

By submitting a contribution, you agree that it may be distributed under the project’s [MIT License](LICENSE).

## Reports

A useful bug report includes the macOS version, SPDFV build, exact operation, expected result, actual result, and whether the PDF contains forms, encryption, signatures, or scanned pages. Do not attach a private document; make a reduced sample that contains no sensitive information.
