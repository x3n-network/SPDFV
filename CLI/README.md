# SPDFV CLI

The CLI gives shell scripts and automated workflows a deterministic interface to the same PDFKit foundation as the app. Output is JSON by default and errors go to stderr.

```sh
swift build --package-path CLI -c release
CLI/.build/release/spdfv inspect document.pdf --pretty
CLI/.build/release/spdfv annotations document.pdf --pages all --pretty
CLI/.build/release/spdfv forms intake.pdf --pretty
CLI/.build/release/spdfv form-gate intake.pdf --pretty
CLI/.build/release/spdfv export-form-data intake.pdf --output intake-values.json --pretty
CLI/.build/release/spdfv validate-form-data intake.pdf --data completed-values.json --pretty
CLI/.build/release/spdfv import-form-data intake.pdf --data completed-values.json --output completed.pdf --pretty
CLI/.build/release/spdfv form-data-mapping-template intake.pdf --data recipients.csv --output mapping.json --filename 'case-{Case ID}.pdf'
CLI/.build/release/spdfv batch-form-data intake.pdf --data recipients.csv --mapping mapping.json --dry-run --pretty
CLI/.build/release/spdfv batch-form-data intake.pdf --data recipients.csv --mapping mapping.json --output-dir ./completed --pretty
CLI/.build/release/spdfv safety-gate intake.pdf --pretty
CLI/.build/release/spdfv verify-signatures signed-contract.pdf --pretty
CLI/.build/release/spdfv safe-share review-copy.pdf --pretty
CLI/.build/release/spdfv compare approved.pdf working-copy.pdf --alignment intelligent --appearance-threshold 0.995 --ignore-regions '0,0,1,0.05' --pretty
CLI/.build/release/spdfv doctor document.pdf --pretty
CLI/.build/release/spdfv doctor-repair document.pdf --actions metadata,forms --output repaired.pdf --pretty
CLI/.build/release/spdfv fill-form intake.pdf --values '{"full_name":"Ada Lovelace","approved":"true"}' --output completed.pdf
CLI/.build/release/spdfv add-field intake.pdf --page 1 --type text --name reviewer --bounds 72,540,220,32 --output authored.pdf
CLI/.build/release/spdfv rename-field authored.pdf --from reviewer --to review.owner --output renamed.pdf
CLI/.build/release/spdfv recipe-template > intake-recipe.json
CLI/.build/release/spdfv validate-recipe intake.pdf --recipe intake-recipe.json --pretty
CLI/.build/release/spdfv run-recipe intake.pdf --recipe intake-recipe.json --output prepared.pdf --pretty
CLI/.build/release/spdfv run-recipe intake.pdf --recipe recipe-v3.json --output-dir ./processed --parameters '{"case":"A-104"}' --references '{"approved":"./approved.pdf"}' --form-data '{"values":"./values.json"}' --pretty
CLI/.build/release/spdfv batch-recipe ./incoming --recipe intake-recipe.json --output-dir ./processed --pretty
CLI/.build/release/spdfv library-add --library recipes.json --recipe intake-recipe.json --favorite --pretty
CLI/.build/release/spdfv enqueue-recipe intake.pdf --recipe intake-recipe.json --output prepared.pdf --queue jobs.json --pretty
CLI/.build/release/spdfv run-queue --queue jobs.json --pretty
CLI/.build/release/spdfv watch-once ./incoming --recipe intake-recipe.json --output-dir ./processed --state watch-state.json --pretty
CLI/.build/release/spdfv text document.pdf --pages 1-3 --pretty
CLI/.build/release/spdfv extract document.pdf --pages 1,3-5 --output excerpt.pdf
CLI/.build/release/spdfv merge cover.pdf body.pdf --output complete.pdf
CLI/.build/release/spdfv rotate document.pdf --pages 2-4 --degrees 90 --output rotated.pdf
CLI/.build/release/spdfv crop document.pdf --pages all --insets 18 --output cropped.pdf
CLI/.build/release/spdfv ocr scan.pdf --pages all --quality accurate --languages en-US --output searchable.pdf
CLI/.build/release/spdfv redact report.pdf --regions '1:72,640,180,32;2:80,500,220,48' --verify-absent 'account number,secret' --output sanitized.pdf
```

Page specifications are one-based, accept comma-separated inclusive ranges, and preserve document order. Crop insets accept either one uniform point value or `top,right,bottom,left`. Existing output files are protected unless `--force` is supplied.

## Interactive forms

`safety-gate` reports encryption and lock state, all seven PDF access permissions, certificate-signature field names, and a pass, warning, or stop result. Run this preflight before an automated editing workflow when preserving document protections matters.

`verify-signatures` validates the raw PDF ByteRange against common detached CMS signature containers (`adbe.pkcs7.detached` and `ETSI.CAdES.detached`), reports cryptographic integrity separately from macOS certificate trust, includes signer summary and certificate SHA-256 fingerprint, distinguishes authenticated timestamps from signer-supplied times, and detects bytes added after the signed revision. Unsupported containers are reported without claiming validity. Any PDF edit may invalidate or remove existing signatures.

`safe-share` audits common information that can unintentionally travel with a PDF: populated metadata fields, review annotations, filled form fields, file attachments, encryption, and certificate-signature fields. Its JSON report deliberately includes metadata keys and form-field names rather than their private values, and summarizes annotation contents without copying them to stdout. A locked document returns `stop` without inspecting its contents.

`compare` produces a privacy-conscious, page-by-page report for a reference and candidate PDF. Intelligent alignment (the default) anchors matching pages so insertions and removals do not cascade into false changes; `--alignment position` restores strict positional comparison. `--appearance-threshold` accepts 0–1, and `--ignore-regions` accepts semicolon-separated normalized top-left-origin `x,y,width,height` rectangles. The report explains changes through rendered appearance, normalized text, dimensions, rotation, annotation count, and form-field count without copying page text or field values.

`doctor` composes the Safety Gate, Form Gate, Safe Share audit, page geometry, rotation, and searchable-text coverage into one prioritized diagnostic and repair plan. `doctor-repair` applies all planned repairs, or a requested subset of `ocr`, `forms`, and `metadata`, to a new output and emits the before/after verification. OCR is limited to pages without searchable text. Both reports contain page and field identifiers, never document text, metadata values, annotation contents, or form values.

`forms` reports every page widget, its canonical field name, type, value, bounds, choices, read-only status, and whether it has a normal appearance stream. `fill-form` accepts a JSON object of string values, keeps the output interactive, repairs genuinely orphaned PDFKit widgets during the write, and reopens the result to verify the canonical `/AcroForm/Fields` tree, widget values, and `/AP` `/N` appearances. Boolean button values accept `true`, `yes`, `on`, `checked`, or `1`.

`form-gate` runs the same preflight used by the app. It reports pass, warning, or stop along with orphan widgets, canonical fields without page controls, conflicting repeated names, and missing appearance streams.

`add-field` authors a new text, checkbox, or choice field at PDF point coordinates. Choice options are comma separated. Field names must be unique, bounds must remain on the selected page, and the command normalizes and verifies the resulting interactive form before writing it. Certificate-backed signature fields remain a separate signing milestone.

`rename-field` updates a logical field name across every repeated widget, rejects collisions, normalizes the canonical field tree, and verifies appearances before writing the output.

Form Data Studio files are versioned JSON containing writable field names and values. `export-form-data` deliberately exports private values, `validate-form-data` reports missing, duplicate, read-only, unsupported, conflicting, and invalid-choice fields without echoing their values, and `import-form-data` writes only after the complete file passes validation. The native Fields → Data workbench uses the same contract and applies a valid import as one undoable edit.

Batch Form Data accepts quote-aware UTF-8 CSV or TSV tables and generates one completed PDF per row. Exact column/field names map automatically; `form-data-mapping-template` creates a versioned JSON mapping that can be edited for aliases and reused. Filename templates accept `{row}` and table headers such as `{Case ID}`. `batch-form-data --dry-run` checks every row, mapped choice, and output name without writing; a real run refuses to write anything unless the entire preflight passes. The native Batch Form Data workspace provides the same mapping, save/load, preflight, and generation flow.

## Recipes

Recipes are deterministic JSON workflows. Version 1 supports ordered `renameField`, `fillForm`, `rotate`, `crop`, and `extract` actions plus page-count, text, field, and Form Gate assertions. Version 2 remains backward-compatible and adds `duplicatePages`, `deletePages`, `ocr`, and `assertSafeShare`. Version 3 adds declared string parameters, `importFormData`, `assertCompare`, `assertDoctor`, simple `ifParameter` branches, and output filename templates. Older recipe JSON decodes unchanged, and Recipe Press upgrades the version only when a newer plate or input feature is added.

`recipe-template` prints a v1-compatible starter, `validate-recipe` executes the complete workflow in memory without writing a PDF, and `run-recipe` writes only after the output survives PDF round-trip verification and Form Gate validation. A recipe may contain at most 100 steps, and page specifications are evaluated against the document state at that step. OCR configuration uses the same recognition level, language codes, language-correction flag, and 72–400 DPI range as the standalone command.

`batch-recipe` processes the direct PDF children of an input directory in deterministic filename order. Passing documents are written to the output directory; failed documents produce no PDF. A `spdfv-batch-manifest.json` records every result. The command exits nonzero if any item fails, even though passing outputs and the manifest are still written. Use `--dry-run` without an output directory to validate the entire folder without writing anything.

Recipe v3 parameters are declared with `name`, optional `defaultValue`, and `required`. Strings may interpolate `{{name}}`, `{{inputName}}`, and `{{recipeName}}`. `--parameters` accepts a JSON string map; `--references` and `--form-data` accept JSON maps from recipe source names to local file paths. `run-recipe --output-dir` uses `outputNameTemplate`, sanitizes unsafe filename characters, and adds `.pdf` when needed. Conditional nesting is limited to five levels and every recipe is limited to 100 total steps, including nested steps. Reports mark skipped conditions without exposing parameter values.

Queued and watched recipes run without an external execution context. They therefore support v3 recipes whose required parameters have defaults and which do not require named reference or form-data files; use direct app or CLI runs for recipes with external inputs.

```json
{
  "version": 3,
  "name": "Approved intake",
  "parameters": [
    {"name": "case", "required": true},
    {"name": "mode", "defaultValue": "production", "required": true}
  ],
  "outputNameTemplate": "{{inputName}}-{{case}}.pdf",
  "steps": [
    {"operation": "importFormData", "source": "values"},
    {"operation": "ifParameter", "name": "mode", "equals": "production", "steps": [
      {"operation": "assertDoctor", "maximum": "attention"}
    ]},
    {"operation": "assertCompare", "reference": "approved", "maximumChangedPages": 1}
  ]
}
```

## Queue files

Recipe cabinets are JSON files. `library-add` creates or extends a cabinet, `library-list` returns its complete machine-readable inventory, and `library-export` resolves a recipe UUID back to a standalone recipe file. These files use the same versioned catalog format as SPDFVCore.

Durable queues make longer workflows restartable. `enqueue-recipe` validates the recipe and appends a queued job; `run-queue` persists `running`, `passed`, or `failed` after every transition; and `queue-status` returns the complete queue plus aggregate counts. If a process is interrupted, its `running` jobs are recovered to `queued` on the next run. Each job carries stable absolute paths, timestamps, attempt count, the full recipe report on success, or a precise error on failure. A mixed queue preserves passing outputs but exits nonzero while failed jobs remain.

The macOS app’s Processing Queue reads and writes this same format. Imported jobs retain their reports and paths; because the app is sandboxed, queued imports must be relinked to their input PDF, recipe, and output folder before the app can run them. Security-scoped bookmarks stay local and are never included in an exported queue.

### Background processing

SPDFV includes a small queue runner inside the app bundle. Background processing is off by default and can be turned on from the Processing Queue window after SPDFV has been moved to Applications. macOS may ask for approval in System Settings under Login Items. When enabled, the runner checks for queued work every 15 seconds, writes each result back to the queue, and exits; it does not keep the full app running.

Jobs must first be added or relinked in SPDFV so the app can retain access to the input PDF, recipe, and output folder. Turning background processing off unregisters the runner without removing the queue or its history.

`watch-once` is designed for launchd, cron, and other scheduled jobs. It processes only direct PDF children, never replaces an existing output, and atomically records each successful filename in a separate state file. Failed inputs are not marked processed, so a later invocation can retry them after the document or recipe is corrected.

```json
{
  "version": 1,
  "name": "Intake preparation",
  "steps": [
    {"operation": "assertPageCount", "minimum": 1, "maximum": 20},
    {"operation": "assertFields", "names": ["full_name", "approved"]},
    {"operation": "renameField", "from": "full_name", "to": "review.owner"},
    {"operation": "fillForm", "values": {"review.owner": "Ada Lovelace"}},
    {"operation": "assertFormGate", "maximum": "pass"},
    {"operation": "crop", "pages": "all", "insets": {"top": 12, "right": 12, "bottom": 12, "left": 12}}
  ]
}
```

## Searchable scanned PDFs

`ocr` uses Apple's on-device Vision framework. It preserves the original page artwork and adds an invisible, selectable text layer to a separate output PDF. No document content leaves the Mac.

- `--pages` defaults to `all`.
- `--quality` defaults to `accurate`; use `fast` for draft batches.
- `--languages` accepts comma-separated Vision language codes such as `en-US,fr-FR`. Omit it for automatic language detection.
- `--dpi` controls recognition rendering from 72 through 400 and defaults to 216.

## True redaction

`redact` does not place removable black annotations. Each affected page is rasterized, its marked rectangles are burned into the pixels, hidden page objects are discarded, and searchable text is rebuilt from the already-redacted image. Unaffected pages remain native PDF pages.

Regions use PDF point coordinates as `page:x,y,width,height`, separated by semicolons. `--verify-absent` rejects the output if any comma-separated forbidden term remains extractable. Use `--no-ocr` when affected pages should contain no text layer at all.
