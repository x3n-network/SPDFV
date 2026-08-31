#!/usr/bin/env swift

import Foundation

// SPDFV icon master. The family is intentionally angular and drafted on a
// 24-point grid: square terminals, clipped paper corners, and small registration
// ticks borrow from bindery and prepress tools instead of platform pictograms.

let iconNames = [
    "add", "annotations", "archive", "automation", "back", "check", "checkboxOff", "checkboxOn",
    "choiceField", "close", "closeFilled", "controls", "copy", "crop", "cropRotate",
    "delete", "document", "documentAdd", "down", "drag", "draw", "duplicate", "editField",
    "extract", "favorite", "favoriteFilled", "field", "filter", "fitPage", "highlighter",
    "info", "insertPages", "jump", "left", "link", "list", "moveDown", "moveUp", "note",
    "noteAdd", "outline", "pageCount", "pages", "processing", "queue", "quickAction",
    "redo", "region", "retry", "reveal", "right", "rotateLeft", "rotateRight", "route",
    "run", "save", "scan", "scanText", "scissors", "search", "secureCopy", "select",
    "share", "sidebarHide", "sidebarShow", "signature", "strike", "text", "textCursor", "themeAuto", "themeDark",
    "themeLight", "tray", "underline", "unknownField", "up", "warning", "zoomIn", "zoomOut"
]

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #filePath)
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let catalog = projectRoot.appendingPathComponent("SPDFV/Assets.xcassets/SPDFVIcons")

func page(_ extras: String = "") -> String {
    "<path d=\"M5 2.75h9.5L19 7.25V21H5z M14.5 2.75v4.5H19\"/>\(extras)"
}

func box(_ extras: String = "") -> String {
    "<path d=\"M4 4h16v16H4z\"/>\(extras)"
}

func arrow(_ direction: String) -> String {
    switch direction {
    case "left": return "<path d=\"M20 12H5 M10 7l-5 5 5 5\"/>"
    case "right": return "<path d=\"M4 12h15 M14 7l5 5-5 5\"/>"
    case "up": return "<path d=\"M12 20V5 M7 10l5-5 5 5\"/>"
    default: return "<path d=\"M12 4v15 M7 14l5 5 5-5\"/>"
    }
}

func body(for name: String) -> String {
    switch name {
    case "add": return "<path d=\"M12 4v16M4 12h16\"/>"
    case "annotations": return page("<path d=\"M8 10h8M8 14h5M7 19l3-3\"/>")
    case "archive": return "<path d=\"M4 7h16v13H4zM3 3h18v4H3zM9 11h6\"/>"
    case "automation": return "<path d=\"M5 6l7-3 7 3v8l-7 7-7-7zM8 10h8M8 14h5\"/>"
    case "back": return arrow("left")
    case "check": return "<path d=\"M4 12.5l5 5L20 6.5\"/>"
    case "checkboxOff": return box()
    case "checkboxOn": return box("<path d=\"M7 12l3 3 7-7\"/>")
    case "choiceField": return box("<path d=\"M7 8h2M11 8h6M7 12h2M11 12h6M7 16h2M11 16h6\"/>")
    case "close": return "<path d=\"M5 5l14 14M19 5L5 19\"/>"
    case "closeFilled": return "<path fill=\"#000\" stroke=\"none\" d=\"M12 2.5A9.5 9.5 0 1 0 12 21.5 9.5 9.5 0 0 0 12 2.5zm-3.8 5.7 3.8 3.8 3.8-3.8 1.2 1.2-3.8 3.8 3.8 3.8-1.2 1.2-3.8-3.8-3.8 3.8-1.2-1.2 3.8-3.8-3.8-3.8z\"/>"
    case "controls": return "<path d=\"M4 6h5M15 6h5M9 3v6M4 12h10M18 12h2M14 9v6M4 18h2M12 18h8M6 15v6\"/>"
    case "copy": return "<path d=\"M8 4h11v14H8zM5 7H3v14h11v-3\"/>"
    case "crop": return "<path d=\"M7 3v14h14M3 7h14v14\"/>"
    case "cropRotate": return "<path d=\"M7 3v14h14M3 7h14v8M16 20a6 6 0 0 0 5-5M21 15v4h-4\"/>"
    case "delete": return "<path d=\"M5 7h14M9 7V4h6v3M7 7l1 14h8l1-14M10 11v6M14 11v6\"/>"
    case "document": return page()
    case "documentAdd": return page("<path d=\"M12 10v7M8.5 13.5h7\"/>")
    case "down", "moveDown": return arrow("down")
    case "drag": return "<path d=\"M5 7h14M5 12h14M5 17h14\"/>"
    case "draw": return "<path d=\"M5 18.5l1-4L16.5 4 20 7.5 9.5 18zM14.5 6l3.5 3.5M5 21h14\"/>"
    case "duplicate": return "<path d=\"M8 3h11v14H8zM5 7H3v14h11v-4M13.5 7v6M10.5 10h6\"/>"
    case "editField": return box("<path d=\"M7 16l1-4 7-7 3 3-7 7zM13.5 6.5l3 3\"/>")
    case "extract": return "<path d=\"M5 3h10v14H5zM9 10h11M16 6l4 4-4 4M8 21h11\"/>"
    case "favorite": return "<path d=\"M12 3.5l2.5 5.1 5.6.8-4 4 .9 5.6-5-2.6L7 19l1-5.6-4.1-4 5.6-.8z\"/>"
    case "favoriteFilled": return "<path fill=\"#000\" stroke=\"none\" d=\"M12 2.8l2.8 5.7 6.3.9-4.5 4.4 1.1 6.2-5.7-3-5.7 3 1.1-6.2-4.5-4.4 6.3-.9z\"/>"
    case "field": return box("<path d=\"M8 7h8M12 7v10M8.5 17h7\"/>")
    case "filter": return "<path d=\"M4 5h16M7 12h10M10 19h4\"/>"
    case "fitPage": return page("<path d=\"M2 8V3h5M22 8V3h-5M2 16v5h5M22 16v5h-5\"/>")
    case "highlighter": return "<path d=\"M7 16l8-12 4 3-8 12H7zM13 7l4 3M4 21h15\"/>"
    case "info": return box("<path d=\"M12 10v7M12 7h.01\"/>")
    case "insertPages": return page("<path d=\"M2 10h9M7 6l4 4-4 4\"/>")
    case "jump": return "<path d=\"M4 12h12M12 8l4 4-4 4M20 5v14\"/>"
    case "left": return arrow("left")
    case "link": return "<path d=\"M9.5 14.5l5-5M8 17H6a4 4 0 0 1 0-8h4M16 7h2a4 4 0 0 1 0 8h-4\"/>"
    case "list": return "<path d=\"M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01\"/>"
    case "moveUp", "up": return arrow("up")
    case "note": return page("<path d=\"M8 10h8M8 14h6\"/>")
    case "noteAdd": return page("<path d=\"M12 10v7M8.5 13.5h7\"/>")
    case "outline": return "<path d=\"M4 5h4M11 5h9M4 11h4M11 11h9M4 17h4M11 17h6M11 20h9\"/>"
    case "pageCount": return page("<path d=\"M9 10h6M9 14h6M11 8v8\"/>")
    case "pages": return "<path d=\"M3 3h8v8H3zM13 3h8v8h-8zM3 13h8v8H3zM13 13h8v8h-8z\"/>"
    case "processing": return "<path d=\"M12 3v4M12 17v4M3 12h4M17 12h4M5.6 5.6l2.8 2.8M15.6 15.6l2.8 2.8M18.4 5.6l-2.8 2.8M8.4 15.6l-2.8 2.8\"/>"
    case "queue": return "<path d=\"M4 5h13v4H4zM7 10h13v4H7zM4 15h13v4H4z\"/>"
    case "quickAction": return "<path d=\"M14 2L5 14h7l-2 8 9-12h-7z\"/>"
    case "redo": return "<path d=\"M5 8h9a5 5 0 0 1 0 10H9M16 4l4 4-4 4\"/>"
    case "region": return "<path stroke-dasharray=\"3 2\" d=\"M4 4h16v16H4z\"/><path d=\"M8 4v4H4M16 20v-4h4\"/>"
    case "retry": return "<path d=\"M19 8a8 8 0 1 0 1 7M19 3v5h-5\"/>"
    case "reveal": return box("<path d=\"M9 15l6-6M11 9h4v4\"/>")
    case "right": return arrow("right")
    case "rotateLeft": return "<path d=\"M6 7h5V2M6 7a8 8 0 1 1-1 9\"/>"
    case "rotateRight": return "<path d=\"M18 7h-5V2M18 7a8 8 0 1 0 1 9\"/>"
    case "route": return "<path d=\"M5 18V7h6v6h8M5 4v3M11 10v3M19 13v4\"/><path fill=\"#000\" stroke=\"none\" d=\"M3 2h4v4H3zM9 8h4v4H9zM17 16h4v4h-4z\"/>"
    case "run": return "<path d=\"M8 4l11 8L8 20z\"/>"
    case "save": return page("<path d=\"M12 9v8M8.5 13.5L12 17l3.5-3.5\"/>")
    case "scan": return "<path d=\"M3 9V4h5M21 9V4h-5M3 15v5h5M21 15v5h-5M7 12h10\"/>"
    case "scanText": return "<path d=\"M3 9V4h5M21 9V4h-5M3 15v5h5M21 15v5h-5M8 9h8M12 9v7M9 16h6\"/>"
    case "scissors": return "<path d=\"M9 9l11-6M9 15l11 6M8.5 12H20\"/><circle cx=\"6\" cy=\"8\" r=\"3\"/><circle cx=\"6\" cy=\"16\" r=\"3\"/>"
    case "search": return "<circle cx=\"10.5\" cy=\"10.5\" r=\"6.5\"/><path d=\"M15.5 15.5L21 21\"/>"
    case "secureCopy": return page("<path d=\"M9 13h6v5H9zM10 13v-2a2 2 0 0 1 4 0v2\"/>")
    case "select": return "<path d=\"M5 3l13 10-7 1-3 7z\"/>"
    case "share": return page("<path d=\"M12 16V8M8.5 11.5L12 8l3.5 3.5\"/>")
    case "sidebarHide": return box("<path d=\"M9 4v16M14 9l-3 3 3 3\"/>")
    case "sidebarShow": return box("<path d=\"M15 4v16M10 9l3 3-3 3\"/>")
    case "signature": return "<path d=\"M3 17c4-8 5-9 6-9s-2 9 0 9c2 0 3-5 4-5s-1 5 1 5c2 0 2-3 4-3 1 0 1 1 3 1M3 21h18\"/>"
    case "strike": return "<path d=\"M7 8c0-3 10-3 10 0M7 16c0 3 10 3 10 0M4 12h16\"/>"
    case "text": return "<path d=\"M5 5h14M12 5v14M8 19h8\"/>"
    case "textCursor": return box("<path d=\"M8 8h8M12 8v8M9 16h6M19 5v14\"/>")
    case "themeAuto": return "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path fill=\"#000\" stroke=\"none\" d=\"M12 3a9 9 0 0 1 0 18z\"/>"
    case "themeDark": return "<path d=\"M18 16.5A8 8 0 0 1 7.5 6 8 8 0 1 0 18 16.5z\"/><path d=\"M17 5v3M15.5 6.5h3\"/>"
    case "themeLight": return "<circle cx=\"12\" cy=\"12\" r=\"4\"/><path d=\"M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2\"/>"
    case "tray": return "<path d=\"M3 6h18v13H3zM3 13h5l2 3h4l2-3h5\"/>"
    case "underline": return "<path d=\"M7 4v8a5 5 0 0 0 10 0V4M5 21h14\"/>"
    case "unknownField": return box("<path d=\"M9 9a3 3 0 1 1 4 2.8c-1 .5-1 1.2-1 2.2M12 17h.01\"/>")
    case "warning": return "<path d=\"M12 3l9 17H3zM12 8v6M12 17h.01\"/>"
    case "zoomIn": return "<circle cx=\"10\" cy=\"10\" r=\"6\"/><path d=\"M14.5 14.5L21 21M10 7v6M7 10h6\"/>"
    case "zoomOut": return "<circle cx=\"10\" cy=\"10\" r=\"6\"/><path d=\"M14.5 14.5L21 21M7 10h6\"/>"
    default: return box()
    }
}

let svgPrefix = """
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
<g fill="none" stroke="#000" stroke-width="1.65" stroke-linecap="square" stroke-linejoin="miter">
"""
let svgSuffix = "</g>\n</svg>\n"
let contents = """
{
  "images" : [
    { "filename" : "icon.svg", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
"""

try fileManager.createDirectory(at: catalog, withIntermediateDirectories: true)
try "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    .write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for name in iconNames {
    let imageSet = catalog.appendingPathComponent("SPDFVIcon-\(name).imageset")
    try fileManager.createDirectory(at: imageSet, withIntermediateDirectories: true)
    try (svgPrefix + body(for: name) + svgSuffix)
        .write(to: imageSet.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)
    try contents.write(to: imageSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

print("Generated \(iconNames.count) SPDFV SVG icons in \(catalog.path)")
