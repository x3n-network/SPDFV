# Release checklist

## Code and documents

- Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- Move completed entries from Unreleased into a dated section in `CHANGELOG.md`.
- Run the Core tests and build the CLI in release mode.
- Build both Debug and Release app configurations.
- Exercise Finder opening, multi-window opening, save protection, printing, OCR, redaction, forms, and the background queue.
- Check light, dark, VoiceOver, keyboard-only navigation, and a large PDF.

## Distribution

- Confirm a `Developer ID Application` certificate is present with `security find-identity -v -p codesigning`.
- Store notarization credentials once with `xcrun notarytool store-credentials "SPDFV-notary"`.
- Run `Scripts/release_macos.sh VERSION`; it archives, exports, creates a DMG, notarizes, staples, verifies, and writes a SHA-256 checksum.
- The release script also signs the DMG for Sparkle and updates `Updates/appcast.xml`. The private EdDSA key remains in the login Keychain under the `x3n-network` account.
- Set `SPARKLE_GENERATE_APPCAST` only when Sparkle's package tool cannot be found automatically. Set `GENERATE_SPARKLE_APPCAST=0` only for a non-publishing diagnostic build.
- Keep `NOTARY_PROFILE`, `BUILD_NUMBER`, and `OUTPUT_DIR` as optional environment overrides; never place notarization credentials in the repository.
- Test the exact downloadable artifact on a Mac that has not run the development build.

## GitHub

- Confirm that no signing identities, provisioning profiles, local paths, private PDFs, or recovery files are tracked.
- Confirm the root MIT license and any required third-party notices are current.
- Create release notes that state the minimum macOS version and any known PDF compatibility limits.
- Attach checksums for downloadable artifacts.
- After the GitHub release assets are uploaded, commit and push the generated `Updates/appcast.xml` so installed copies can discover the release.
- Publish the first build as a GitHub prerelease until clean-Mac testing is complete.

## Sparkle bootstrap

- SPDFV 0.1.2 is the first updater-enabled build. Existing 0.1.1 installations require one manual upgrade.
- The appcast is served from the repository's stable raw URL and update enclosures point to versioned GitHub Release assets.
- Test “Check for Updates…” from an exported app in `/Applications`, including an attempted install while a PDF has unsaved changes.
- Never export or commit the Sparkle private key. Only `SUPublicEDKey` belongs in the app bundle.
