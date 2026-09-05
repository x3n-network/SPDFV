#!/usr/bin/env swift

import AppKit
import PDFKit

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift Scripts/create_app_store_screenshot_fixture.swift INPUT.pdf OUTPUT.pdf\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let document = PDFDocument(url: inputURL), let page = document.page(at: 0) else {
    fputs("Could not open the input PDF.\n", stderr)
    exit(1)
}

let pageBounds = page.bounds(for: .cropBox)

let callout = PDFAnnotation(
    bounds: CGRect(x: pageBounds.minX + 72, y: pageBounds.minY + 72, width: 315, height: 58),
    forType: .freeText,
    withProperties: nil
)
callout.contents = "A clear plan, right where you need it."
callout.font = .systemFont(ofSize: 17, weight: .semibold)
callout.fontColor = .white
callout.color = NSColor(calibratedRed: 0.12, green: 0.33, blue: 0.73, alpha: 0.95)
callout.alignment = .center
page.addAnnotation(callout)

let focusRing = PDFAnnotation(
    bounds: CGRect(x: pageBounds.maxX - 300, y: pageBounds.midY - 85, width: 215, height: 170),
    forType: .circle,
    withProperties: nil
)
focusRing.color = NSColor(calibratedRed: 0.95, green: 0.38, blue: 0.18, alpha: 0.95)
focusRing.border = PDFBorder()
focusRing.border?.lineWidth = 6
focusRing.contents = "Review this section"
page.addAnnotation(focusRing)

let note = PDFAnnotation(
    bounds: CGRect(x: pageBounds.maxX - 115, y: pageBounds.minY + 70, width: 30, height: 30),
    forType: .text,
    withProperties: nil
)
note.color = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.13, alpha: 1)
note.contents = "Follow up during the next review."
page.addAnnotation(note)

guard document.write(to: outputURL) else {
    fputs("Could not write the annotated PDF.\n", stderr)
    exit(1)
}

print(outputURL.path)
