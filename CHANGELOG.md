# Changelog

## Unreleased

- Added a Document Safety Gate for encryption, permissions, and certificate-signature fields, with in-app password unlocking and machine-readable CLI output
- Enforced PDF access permissions across page editing, annotations, forms, OCR, redaction, recipes, and CLI operations
- Split Recipe Press, document safety UI, navigation and annotation models, page operations, OCR, redaction, recipe automation, forms, and edit history out of the largest app source files to make future changes easier to isolate
- Added native app tests for document lifecycle, encrypted unlock, save-as, page selection and geometry, edit history, annotations, forms, and recipe composition state transitions
- Added stable accessibility identifiers and UI automation for empty, document, automation, and encrypted-document flows
- Expanded executable-level CLI tests across annotations, page assembly and crop, form authoring, recipes, and durable queues
- Added an MIT-licensed, manifest-backed compatibility corpus for mixed page geometry, interactive forms, and encrypted-document preflight
- Added clock-metric performance coverage for 250-page inspection and a 60-page multi-step recipe pipeline
- Hardened macOS releases with monotonic version/build preflight, clean-tree enforcement, credential-free rehearsal, bundle-content verification, and atomic appcast validation

## 0.1.2 - 2026-08-31

- Added signed in-app update checking and installation through Sparkle

## 0.1.1 - 2026-08-31

- Added focused Read, Markup, Organize, and Automate workspaces with responsive controls
- Promoted Recipe Press to a resizable document utility window
- Added native named Undo and Redo across document editing workflows
- Added a keyboard-first Command Index for actions, navigation, recent PDFs, and recipes
- Added a persistent Activity Center for OCR, redaction, recipes, batches, watches, and queue jobs
- Refined action typography and captured the updated interface in the project README
- Restored document-scoped commands for PDFs opened directly from Finder

## 0.1.0 - 2026-08-31

- Native PDF viewing and editing workspace for macOS
- Finder and multi-window document opening
- Annotation, page editing, forms, OCR, permanent redaction, recipes, and queues
- Shared `SPDFVCore` package and `spdfv` command-line interface
- Opt-in background queue runner
- Native printing, unsaved-work recovery, and restored page position
