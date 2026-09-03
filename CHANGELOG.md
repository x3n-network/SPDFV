# Changelog

## Unreleased

## 0.1.4 - 2026-09-03

- Replaced internal AcroForm/XFA field paths with readable form labels while preserving exact PDF keys, and kept the Contents navigator label legible in narrow sidebars

## 0.1.3 - 2026-09-01

- Added cryptographic PDF signature verification for detached CMS signatures with ByteRange integrity, certificate details, macOS trust evaluation, authenticated timestamps, later-revision detection, and edit invalidation warnings
- Added a privacy-conscious Document Doctor that prioritizes access, page, searchable-text, form, and sharing issues; previews copy-safe repairs; OCRs only affected pages; normalizes forms; removes metadata; and verifies repaired copies in the app and CLI
- Added Form Data Studio for versioned JSON value export, privacy-conscious import validation, atomic native apply/undo, and CLI automation
- Added Batch Form Data Studio for CSV/TSV mail-merge-style generation with reusable column aliases, filename templates, and all-rows validation before output
- Expanded privacy-conscious PDF Compare with intelligent inserted/removed-page alignment, configurable appearance tolerance and ignored regions, side-by-side/overlay/heatmap views, and JSON report export across Core, CLI, and the native workspace
- Added backward-compatible Recipe v2 plates for page duplication, page deletion, OCR, and Safe Share assertions, with automatic schema upgrade in Recipe Press
- Added Recipe v3 parameters, variable substitution, conditional branches, named form-data and comparison inputs, Doctor/Compare assertions, safe output naming templates, native run-input controls, and CLI context maps
- Added a privacy-preserving Safe Share audit for metadata, review annotations, filled form fields, attachments, encryption, and signature fields across Core, CLI, and the native document inspector
- Added a Document Safety Gate for encryption, permissions, and certificate-signature fields, with in-app password unlocking and machine-readable CLI output
- Enforced PDF access permissions across page editing, annotations, forms, OCR, redaction, recipes, and CLI operations
- Split Recipe Press, document safety UI, navigation and annotation models, page operations, OCR, redaction, recipe automation, forms, and edit history out of the largest app source files to make future changes easier to isolate
- Added native app tests for document lifecycle, encrypted unlock, save-as, page selection and geometry, edit history, annotations, forms, and recipe composition state transitions
- Added stable accessibility identifiers and UI automation for empty, document, automation, and encrypted-document flows
- Expanded executable-level CLI tests across annotations, page assembly and crop, form authoring, recipes, and durable queues
- Added an MIT-licensed, manifest-backed compatibility corpus for mixed page geometry, interactive forms, and encrypted-document preflight
- Added clock-metric performance coverage for 250-page inspection and a 60-page multi-step recipe pipeline
- Hardened macOS releases with monotonic version/build preflight, clean-tree enforcement, credential-free rehearsal, bundle-content verification, and atomic appcast validation
- Unified CI, contributor, and release validation with release-optimized Core/CLI tests, PDFKit round-trip smoke coverage, native app tests, UI automation build/run modes, visual audits, and whitespace checks

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
