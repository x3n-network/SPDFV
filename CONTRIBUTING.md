# Contributing to SPDFV

SPDFV is a macOS application with a shared core and CLI. Changes should preserve the same PDF behavior across those surfaces whenever the operation belongs in `SPDFVCore`.

## Before opening a change

1. Build the app with signing disabled.
2. Run `swift test --package-path Core`.
3. If the shared core changed, rebuild `CLI` and exercise the relevant command.
4. Test both light and dark appearance for visible interface changes.
5. Test with a copy of the PDF, especially for forms, redaction, page deletion, and saving.

## Code shape

- Keep PDF transformations in `Core` when they can be independent of the app interface.
- Keep AppKit and SwiftUI coordination in the app target.
- Do not add network processing for document content without an explicit design discussion.
- Protect existing output files unless an operation clearly asks for replacement.
- Prefer focused changes over broad restyling or renaming.

## Contribution license

By submitting a contribution, you agree that it may be distributed under the project’s [MIT License](LICENSE).

## Reports

A useful bug report includes the macOS version, SPDFV build, exact operation, expected result, actual result, and whether the PDF contains forms, encryption, signatures, or scanned pages. Do not attach a private document; make a reduced sample that contains no sensitive information.
