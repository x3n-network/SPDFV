# Simple PDF Viewer — Mac App Store submission runbook

Last verified against the project and Apple documentation: September 5, 2026.

This is the source of truth for preparing, uploading, reviewing, and releasing the Mac App Store edition of SPDFV. Check off each item for the build being submitted.

## Product identity

| Field | Value |
| --- | --- |
| App Store name | `Simple PDF Viewer` |
| Platform | macOS |
| Xcode project | `SPDFV.xcodeproj` |
| Scheme and target | `SPDFV Reader` |
| Bundle ID | `com.x3nllc.SPDFV.Reader` |
| Apple developer team | `HT5B666N35` |
| Current version | `0.1.4` |
| Current build | `5` |
| Minimum macOS | macOS 14.0 |
| Primary language | English (U.S.) |
| Primary category | Productivity |
| Suggested secondary category | Utilities |
| Price | Free |
| Copyright | `2026 X3N LLC` |
| Suggested SKU | `SPDFV-READER-MAC` |
| Source | `https://github.com/x3n-network/SPDFV` |
| License | MIT |

The complete direct-download edition and the Reader edition remain in one public MIT-licensed repository. They are separate Xcode targets, not separate source copies:

- `SPDFV` is the complete Developer ID edition with Sparkle and the optional queue runner.
- `SPDFV Reader` is the internal target for the sandboxed Mac App Store app named **Simple PDF Viewer**. It exposes the interactive PDF feature set: reading, creation, saving, annotation, forms, page organization, OCR, permanent redaction, comparison, Document Doctor, navigation, search, layouts, and printing.

The App Store target presents interactive document operations in a **Tools** workspace. It excludes workflow automation: Recipe Press, batch processing, processing queues, folder watching, the background helper and LaunchAgent, Activity Center, App Intents, the CLI, and Sparkle/self-updating. The repository `LICENSE` is copied into the app bundle.

## Before creating the app record

- [ ] Apple Developer Program membership is active.
- [ ] The Account Holder has accepted every current agreement in App Store Connect under Business.
- [ ] The team has decided who owns App Store Connect metadata, upload, and release access.
- [ ] `Simple PDF Viewer` is available as the App Store name. Apple permits app names up to 30 characters.
- [ ] The immutable SKU `SPDFV-READER-MAC` is acceptable. Change it now if a different internal naming scheme is preferred.
- [ ] The current bundle ID `com.x3nllc.SPDFV.Reader` is final. Do not upload a build until it is final.
- [ ] The first public version will be `0.1.4`. If the store release should start at `1.0`, update `MARKETING_VERSION` in both Reader build configurations before uploading.

## Register the App ID

In Apple Developer → Certificates, Identifiers & Profiles → Identifiers:

1. Add a new **App ID**.
2. Select **App** and **Explicit App ID**.
3. Description: `Simple PDF Viewer (SPDFV App Store edition)`.
4. Bundle ID: `com.x3nllc.SPDFV.Reader`.
5. Register it for team `HT5B666N35`.

The target currently needs only the App Sandbox configuration supplied by its entitlements. Do not enable unrelated services.

## Create the App Store Connect record

In App Store Connect → Apps → **+** → **New App**:

| App Store Connect field | Enter |
| --- | --- |
| Platform | macOS |
| Name | `Simple PDF Viewer` |
| Primary language | English (U.S.) |
| Bundle ID | `com.x3nllc.SPDFV.Reader` |
| SKU | `SPDFV-READER-MAC` |
| User access | Full Access, unless the organization intentionally restricts it |

The Account Holder, Admin, or App Manager must create the record. Apple does not allow the SKU to be changed later, and the bundle ID cannot be changed after a build is uploaded.

## App information

Enter these values in **General → App Information**:

| Field | Recommended value |
| --- | --- |
| Name | `Simple PDF Viewer` |
| Subtitle | `Private PDF editor for Mac` |
| Primary category | Productivity |
| Secondary category | Utilities |
| Content rights | The app does not include or provide third-party content; users open files they choose |
| License agreement | Apple's standard EULA for the store transaction; the public source and bundled notice remain MIT |
| Made for Kids | No |
| App Store Server Notifications | Not applicable; there are no in-app purchases |

### Age rating

Complete Apple's current questionnaire based on the submitted Reader binary:

- In-app controls: none.
- User-generated content sharing or social features: none.
- Messaging or chat: none.
- Advertising: none.
- Unrestricted web access: none. The Source Code and MIT License menu items open two fixed GitHub URLs in the default browser.
- Gambling, contests, loot boxes, violence, sexual content, profanity, drugs, horror, medical content, and other supplied content descriptors: none.
- Made for Kids or a higher-rating override: not applicable.

The app displays PDFs selected by the user but does not provide a content catalog or sharing service. Accept the rating App Store Connect calculates from the current questionnaire; do not hard-code an expected rating in release materials because Apple can revise rating systems.

### MIT licensing and the App Store EULA

The complete source tree remains publicly available under MIT, and the Reader bundle includes the MIT notice. App Store downloads are also subject to Apple's standard EULA when no custom EULA is supplied. That store agreement does not change the repository's license, but it governs the App Store transaction and installation.

Use Apple's standard EULA unless counsel determines the App Store-delivered binary needs a custom agreement. Do not paste the MIT text alone into App Store Connect as a custom EULA: Apple requires a custom EULA to contain its current minimum terms. If a custom agreement is ever adopted, have it reviewed for compatibility with the intended MIT grant and apply it consistently in every selected country or region.

### Regional and business declarations

- [ ] Choose the countries and regions where the app will be available.
- [ ] Set the price to Free.
- [ ] Complete the Digital Services Act trader-status declaration. If X3N LLC distributes in the EU as a trader, verify the public contact details Apple will display.
- [ ] Review any country-specific business, tax, or regulatory prompts shown for the selected storefronts.
- [ ] Confirm the app is not a regulated medical device.
- [ ] Confirm there are no in-app purchases or subscriptions.

## Product-page copy

Apple currently limits the name and subtitle to 30 characters, promotional text to 170 characters, description to 4,000 characters, and keywords to 100 bytes.

### Subtitle

```text
Private PDF editor for Mac
```

### Promotional text

```text
Read, create, annotate, fill, OCR, redact, compare, and organize PDFs in a focused native Mac app. Your documents stay local, with no account or uploads.
```

Promotional text is optional and can be updated without submitting a new binary.

### Description

```text
Simple PDF Viewer is a focused, native PDF editor for macOS, built from the open-source SPDFV project.

Open documents from Finder or the standard Open panel, create a new blank PDF, annotate and fill documents, organize pages, make scans searchable with on-device OCR, permanently redact content, compare PDFs, diagnose document issues, search text, and print through the native macOS print panel.

READ WITH LESS FRICTION
• Open PDFs from Finder, drag and drop, or the Open panel
• Browse page thumbnails and document outlines
• Search text and jump directly to results
• Move between pages with keyboard shortcuts
• Choose single-page, continuous, or facing-page layouts
• Zoom, fit pages, and switch between light and dark appearances

EDIT THE ESSENTIALS
• Create a new blank PDF
• Highlight, underline, strike out, draw, add notes, text, shapes, and visual signatures
• Fill existing form fields or create and rename interactive fields
• Move, rotate, duplicate, delete, crop, extract, and append pages
• Undo and redo document edits

USE BUILT-IN PDF TOOLS
• Add a searchable text layer to scanned pages with on-device OCR
• Permanently redact selected areas and verify removed text
• Compare one PDF with another
• Diagnose document issues with Document Doctor and save a repaired copy

KEEP CONTROL OF YOUR FILES
• Documents are processed locally on your Mac
• No account is required
• No analytics, advertising, tracking, or document uploads
• Save changes or create a new copy with Save As
• Print with the native macOS print system

OPEN SOURCE
Simple PDF Viewer is released as public open-source software under the MIT License. Its source code is available at github.com/x3n-network/SPDFV.

Requires macOS 14 or later.
```

### Keywords

```text
pdf,editor,reader,annotate,forms,ocr,redact,compare,offline,private
```

Do not add competitor names, repeat `SPDFV`, or make claims not present in the submitted build.

### URLs

Paste the two already-published pages before submission:

| Field | Value |
| --- | --- |
| Support URL | `PASTE_EXISTING_SPDFV_READER_SUPPORT_URL` |
| Privacy Policy URL | `PASTE_EXISTING_SPDFV_READER_PRIVACY_URL` |
| Marketing URL | `https://www.x3n.network/opensource/spdfv/` |
| User Privacy Choices URL | Leave blank; the app does not collect user data |

The Support URL must be publicly reachable without signing in and provide real contact information. The Privacy Policy URL must be publicly reachable and accurately describe the Reader edition—not only the more capable direct edition.

## App privacy

For the current Reader target, the recommended App Privacy response is:

> No, we do not collect data from this app.

This is based on the current submitted architecture:

- PDFs are opened from locations the user selects.
- PDF reading, creation, editing, forms, OCR, redaction, comparison, diagnostics, and search happen locally with Apple frameworks.
- The Reader target contains no analytics, advertising, account, telemetry, or upload SDK.
- The Reader has no network-client entitlement.
- Opening the fixed Source Code or MIT License link hands the URL to the user's default browser; the app does not receive browser activity.
- Printing is handled by the macOS print system.

Before every version, re-audit the target and all linked dependencies. If data collection, analytics, crash reporting, accounts, remote content, or another third-party SDK is added, update both App Store privacy answers and the public privacy policy before submitting.

## Export compliance

Complete App Store Connect's encryption questionnaire for the exact submitted binary. The shared core uses Apple cryptographic and Security frameworks for document integrity and signature-related code, so do not answer from memory or assume that “offline” means “no encryption.”

- [ ] Run the App Store Connect export-compliance questionnaire.
- [ ] Determine whether the binary uses only exempt encryption or requires documentation.
- [ ] If Apple determines no documentation is required, add `ITSAppUsesNonExemptEncryption = NO` to `SPDFV/ReaderInfo.plist` in a separate reviewed code change so future uploads do not repeat the question.
- [ ] If documentation is required, upload it and add Apple's approved compliance code to the Info.plist as instructed.

This is a legal/export classification decision, not a build-system guess.

## Screenshots

Apple requires between one and ten Mac screenshots. Use one accepted 16:10 size consistently:

- 1280 × 800
- 1440 × 900
- 2560 × 1600
- 2880 × 1800

Recommended set: six screenshots at 1440 × 900. The current native capture is 1080 × 760, so this profile scales the window slightly down and preserves sharper interface text. Do not use the 2560 × 1600 profile unless the source window is captured at least as large as its roughly 1820 × 1280 placement.

1. **Read without friction** — a PDF open at a useful page with the Read workspace visible.
2. **Annotate clearly** — the Markup workspace with several tasteful annotations on a public PDF.
3. **Organize every page** — the Organize workspace and thumbnail navigator showing page tools.
4. **Fill and create forms** — the Fields navigator on a public blank form with no personal information.
5. **Find anything quickly** — Find or Contents showing useful results in a public document.
6. **Use built-in PDF tools** — the Tools workspace showing OCR, permanent redaction, and Document Doctor.

Finished screenshot set:

| Slot | Caption | File |
| --- | --- | --- |
| 1 — Read without friction | `Read and edit PDFs` / `without the clutter` | `Screenshots/AppStore/Simple-PDF-Viewer-01-Read.png` |
| 2 — Annotate clearly | `Annotate ideas` / `right on the page` | `Screenshots/AppStore/Simple-PDF-Viewer-02-Annotate.png` |
| 3 — Organize every page | `Organize pages` / `your way` | `Screenshots/AppStore/Simple-PDF-Viewer-03-Organize.png` |
| 4 — Fill and create forms | `Fill and create` / `interactive forms` | `Screenshots/AppStore/Simple-PDF-Viewer-04-Forms.png` |
| 5 — Find anything quickly | `Find what matters` / `in seconds` | `Screenshots/AppStore/Simple-PDF-Viewer-05-Find.png` |
| 6 — Built-in PDF tools | `Powerful PDF tools` / `built right in` | `Screenshots/AppStore/Simple-PDF-Viewer-06-Tools.png` |

Every asset was captured from the actual signed and sandboxed `SPDFV Reader` Debug target, then composed by AppFramer with its `mac1440` profile and `midnight` theme. The native source window is 1080 × 760, so AppFramer scales it down rather than up. Debug-only launch arguments select a workspace, navigator, page, or search query without changing release behavior. Documents are opened through macOS Launch Services so the App Sandbox receives the same user-selected-file access it receives in production. The NASA Artemis presentation supplies the reading, annotation, organization, and search examples; the official blank IRS Form W-9 supplies the form example. No personal information is entered. Every exported PNG is 1440 × 900 with an embedded sRGB IEC61966-2.1 profile.

To repeat a capture after building the Reader target, open the document through Launch Services and use Debug-only arguments to select the desired state:

```bash
APPFRAMER_DIR="$HOME/Documents/appframer"
READER_APP="/tmp/spdfv-reader-screenshots/Build/Products/Debug/SPDFV Reader.app"

open -n -a "$READER_APP" /tmp/spdfv-artemis.pdf --args \
  -SPDFV_UI_TEST_WINDOW_SIZE app-store \
  -SPDFV_UI_TEST_WORKSPACE read \
  -SPDFV_UI_TEST_NAVIGATOR outline

osascript -e 'delay 1' \
  -e 'tell application "System Events" to tell process "SPDFV Reader" to set size of front window to {1080, 760}' \
  -e 'delay 1'

cd "$APPFRAMER_DIR"
node bin/appframer.js capture mac \
  --app 'Simple PDF Viewer' \
  --out /tmp/spdfv-reader-raw.png \
  --settle-ms 1500 \
  --json

node bin/appframer.js frame /tmp/spdfv-reader-raw.png \
  --caption 'Read and edit PDFs\nwithout the clutter' \
  --caption-size M \
  --device mac1440 \
  --theme midnight \
  --out-dir /tmp/spdfv-reader-framed \
  --format png \
  --json
```

Available Debug-only keys are `SPDFV_UI_TEST_WINDOW_SIZE` (`app-store` uses a 1080 × 760 content area), `SPDFV_UI_TEST_WORKSPACE` (`read`, `markup`, `organize`, or `automate`; the Reader displays the last value as **Tools**), `SPDFV_UI_TEST_NAVIGATOR` (`pages`, `outline`, `search`, `forms`, `annotations`, or `info`), `SPDFV_UI_TEST_SEARCH`, and one-based `SPDFV_UI_TEST_PAGE`. Generate the temporary annotation fixture with:

```bash
swift Scripts/create_app_store_screenshot_fixture.swift \
  /tmp/spdfv-artemis.pdf \
  /tmp/spdfv-artemis-annotated.pdf
```

Screenshot rules for this release:

- [ ] Capture the `SPDFV Reader` target, not the complete `SPDFV` edition.
- [ ] Show only features available in the submitted binary.
- [ ] Use a redistributable public document, such as the NASA document already credited in the repository.
- [ ] Do not show private files, names, paths, notifications, account details, or unrelated desktop content.
- [ ] Do not include device frames; this is a Mac app.
- [ ] Keep text legible at App Store thumbnail size.
- [ ] Show only the Read, Markup, Organize, Tools, Fields, Marks, and document-information surfaces available in the submitted target.
- [ ] OCR, permanent redaction, comparison, and Document Doctor may be shown; do not claim recipes, batch processing, queues, folder watching, Activity Center, CLI integration, App Intents, or Sparkle updates.
- [ ] Export PNG or JPEG in sRGB and verify every file has the exact accepted dimensions.

An app preview video is optional and unnecessary for the first submission.

## Build configuration audit

Before archiving, confirm the Reader target still has:

- Bundle ID `com.x3nllc.SPDFV.Reader`.
- Automatic signing with team `HT5B666N35`.
- Release version and build matching App Store Connect.
- App Sandbox enabled.
- User-selected file read/write enabled.
- Printing enabled.
- No network or temporary-exception entitlements.
- No Sparkle framework linkage.
- No `SPDFVQueueRunner` executable or queue LaunchAgent.
- No App Intents metadata.
- A bundled `LICENSE` file.
- An App Store icon with the complete required macOS icon set.

Current entitlements live in `SPDFVReader.entitlements`. Reader-specific metadata lives in `SPDFV/ReaderInfo.plist`.

## Local preflight

Run the repository validation suite:

```sh
bash Scripts/validate_project.sh --release
```

Run a clean unsigned Reader build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project SPDFV.xcodeproj \
  -scheme 'SPDFV Reader' \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/spdfv-reader-preflight \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Inspect the produced bundle:

```sh
APP='/tmp/spdfv-reader-preflight/Build/Products/Release/SPDFV Reader.app'

file "$APP/Contents/MacOS/SPDFV Reader"
plutil -p "$APP/Contents/Info.plist"
find "$APP/Contents" -maxdepth 4 -print | sort
otool -L "$APP/Contents/MacOS/SPDFV Reader"
```

The executable must contain both `arm64` and `x86_64`. The bundle listing and linked libraries must not contain Sparkle, QueueRunner, a LaunchAgent, or App Intents metadata.

### Manual acceptance test

Test on a clean macOS user account if possible:

- [ ] Launch succeeds without a network connection.
- [ ] File → Open PDF opens a normal PDF.
- [ ] Finder's Open With can open a PDF in Simple PDF Viewer.
- [ ] Dragging a PDF into the app opens it.
- [ ] A second PDF can open in a separate window.
- [ ] Page thumbnails navigate correctly.
- [ ] A document outline navigates correctly.
- [ ] Search finds text and selects a result.
- [ ] Previous/Next Page and zoom shortcuts work.
- [ ] Every advertised page-layout mode works.
- [ ] Light, dark, and system appearances remain legible.
- [ ] File → New Blank PDF creates one writable US Letter page in a new document window.
- [ ] Save writes an existing document and prompts for a destination for an untitled document.
- [ ] Save As writes a copy to a user-selected location.
- [ ] Text markup and placed notes, text, ink, shapes, and visual signatures can be created, selected, edited, undone, and redone.
- [ ] Existing interactive fields can be filled, and new fields can be placed and renamed.
- [ ] Pages can be moved, rotated, duplicated, deleted, cropped, extracted, and appended without data loss.
- [ ] Tools → OCR creates a user-selected searchable copy using on-device recognition.
- [ ] Tools → Redact permanently rasterizes marked areas into a user-selected copy and verification completes.
- [ ] Compare opens a second user-selected PDF and reports meaningful differences.
- [ ] Document Doctor diagnoses the current PDF; any repair is previewed and saved as a new copy.
- [ ] Page Setup and Print open native macOS panels.
- [ ] A print-restricted PDF disables printing appropriately.
- [ ] Password-protected and malformed PDFs fail safely.
- [ ] Closing a changed document does not silently discard changes.
- [ ] Source Code and MIT License open the correct public URLs.
- [ ] No updater, Automate-branded workspace, Recipe Press, batch processing, queue, folder watching, CLI, App Intents, or Activity Center command is visible.
- [ ] VoiceOver can identify the principal controls and navigator results.
- [ ] Full Keyboard Access can reach principal controls without trapping focus.

## Archive and upload

### Recommended: Xcode Organizer

1. Open `SPDFV.xcodeproj`.
2. Select the `SPDFV Reader` scheme and **Any Mac (Apple Silicon, Intel)** or the generic Mac destination.
3. Choose **Product → Archive**.
4. In Organizer, select the new archive.
5. Choose **Distribute App → App Store Connect → Upload**.
6. Keep automatic signing enabled unless the team's release process requires manual profiles.
7. Run validation, resolve every error, review warnings, then upload.

Do not use the direct edition's `Scripts/release_macos.sh`; that is the Developer ID, notarization, and Sparkle release path.

### Command-line archive

```sh
mkdir -p build/app-store

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project SPDFV.xcodeproj \
  -scheme 'SPDFV Reader' \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$PWD/build/app-store/SPDFV-Reader.xcarchive" \
  -allowProvisioningUpdates \
  clean archive
```

Export and upload using the checked-in App Store options:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -exportArchive \
  -archivePath "$PWD/build/app-store/SPDFV-Reader.xcarchive" \
  -exportPath "$PWD/build/app-store/export" \
  -exportOptionsPlist Scripts/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

`Scripts/ExportOptions-AppStore.plist` uses `destination = upload`. Upload credentials and certificates must stay in Xcode, Keychain, or an approved secret store and must never be committed.

## App Store Connect version

After Apple's processing email arrives:

- [ ] Open the macOS version record matching `CFBundleShortVersionString`.
- [ ] Select build `5`, or the newer build number actually uploaded.
- [ ] Resolve any export-compliance prompt attached to the build.
- [ ] Confirm the app icon, bundle ID, version, minimum macOS, and supported architectures.
- [ ] Paste the subtitle, description, promotional text, and keywords from this document.
- [ ] Paste the existing Support URL and Privacy Policy URL.
- [ ] Add the Marketing URL.
- [ ] Upload the Reader screenshots in the intended order.
- [ ] Publish the App Privacy answer.
- [ ] Complete age rating, content rights, category, price, availability, and DSA information.
- [ ] Enter the copyright as `2026 X3N LLC`.
- [ ] Select **Manual release** for the first version so approval does not publish it unexpectedly.

## App Review information

### Contact information

Enter a monitored name, email, and phone number for X3N LLC. The phone number must include `+` and the country code. Do not put private review contact information in this repository.

### Sign-in

Select **Sign-in not required**. The app has no account system or demo credentials.

### Review notes

Paste and update this for the exact submitted build:

```text
Simple PDF Viewer is a native, sandboxed PDF reader and editor for macOS, built from the open-source SPDFV project. It requires no account, subscription, in-app purchase, or network connection.

To review the app:
1. Launch Simple PDF Viewer.
2. Choose File > Open PDF and select any local PDF, or drag a PDF into the window.
3. Use the Read, Markup, and Organize workspaces to test navigation, annotations, and page operations.
4. Use Tools to test on-device OCR, permanent redaction, and Document Doctor. Use Compare to select a second PDF.
5. Use Fields and Marks in the navigator to test interactive form and annotation management.
6. Choose File > New Blank PDF to create a document, then use Save or Save As to write it.
7. Use View Scale to test page layouts and zoom, and File > Page Setup or Print for printing workflows.

The app accesses only files the reviewer explicitly selects. Document processing is local. The fixed Source Code and MIT License menu items open the public GitHub repository in the default browser.

This submitted target intentionally does not contain the Sparkle updater, optional queue-runner helper, its LaunchAgent, CLI integration, App Intents, Recipe Press, batch processing, folder watching, or Activity Center present in SPDFV's separately distributed Developer ID edition. Interactive PDF tools—including OCR, permanent redaction, comparison, and Document Doctor—are included and operate on files explicitly selected by the user.

Public source code: https://github.com/x3n-network/SPDFV
MIT license: https://github.com/x3n-network/SPDFV/blob/main/LICENSE
```

No attachment is normally required. If App Review requests a sample PDF, use a redistributable, non-sensitive fixture and explain its provenance.

## Final submission checklist

### Binary

- [ ] Release build number is unique and greater than every previous upload.
- [ ] Version and build match the selected App Store Connect version.
- [ ] Archive was produced from `SPDFV Reader`, not `SPDFV`.
- [ ] Distribution signing and provisioning are valid.
- [ ] Organizer validation passes.
- [ ] Sandbox entitlements match the documented set.
- [ ] No forbidden direct-edition components are in the archive.
- [ ] MIT `LICENSE` is bundled.

### Metadata

- [ ] Existing Support and Privacy Policy URLs are pasted and publicly reachable.
- [ ] Product copy matches the Reader binary.
- [ ] Keywords are within Apple's byte limit.
- [ ] Screenshots have accepted dimensions and show only Reader features.
- [ ] App Privacy is accurate and published.
- [ ] Age rating questionnaire is complete.
- [ ] Export compliance is complete.
- [ ] Content-rights answer is complete.
- [ ] Price, territories, tax category, and availability are set.
- [ ] DSA trader status is complete.
- [ ] Review contact information is current.
- [ ] Review notes match the submitted build.
- [ ] Manual release is selected for version 1.

### Submission and release

- [ ] Add the version to a draft App Review submission.
- [ ] Click **Submit for Review**; adding it to the draft alone does not send it.
- [ ] Monitor App Review messages and respond from App Store Connect.
- [ ] If rejected, preserve the review message, reproduce the issue, and update this runbook when the resolution changes the process.
- [ ] After approval, run a final product-page and availability check.
- [ ] Release manually when support coverage and the public website are ready.
- [ ] Install the production App Store build and repeat the critical open/search/save/print smoke test.
- [ ] Tag the exact released source commit and publish matching source under the MIT License.

## Update checklist

For every later version:

1. Increment the Reader build number; never reuse a build number for the same version.
2. Update the version number when creating a new public version.
3. Re-run repository validation, the Reader clean build, bundle audit, and manual acceptance tests.
4. Re-audit privacy, export compliance, entitlements, linked dependencies, and App Review notes.
5. Add accurate **What's New** text; Apple requires it for updates.
6. Upload, process, select, validate, and submit the new build.
7. Tag and publish the exact corresponding MIT source revision.

## Apple references

- [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id)
- [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [App information fields](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Required App Store Connect properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties)
- [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- [Export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Choose a build](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
- [Provide a custom license agreement](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/)
- [Apple's minimum EULA terms](https://www.apple.com/legal/macapps/minterms/)
