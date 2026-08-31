import AppKit
import SwiftUI

/// SPDFV's own document-instrument icon vocabulary.
///
/// Every case resolves to an SVG in `Assets.xcassets/SPDFVIcons`. Keeping the
/// vocabulary semantic prevents Apple symbol names from leaking back into the
/// interface and gives the app one consistent visual voice.
enum SPDFVIconName: String {
    case add, annotations, archive, automation, back, check, checkboxOff, checkboxOn
    case choiceField, close, closeFilled, controls, copy, crop, cropRotate
    case delete, document, documentAdd, down, drag, draw, duplicate, editField
    case extract, favorite, favoriteFilled, field, filter, fitPage, highlighter
    case info, insertPages, jump, left, link, list, moveDown, moveUp, note
    case noteAdd, outline, pageCount, pages, processing, queue, quickAction
    case redo, region, retry, reveal, right, rotateLeft, rotateRight, route
    case run, save, scan, scanText, scissors, search, secureCopy, select
    case share, sidebarHide, sidebarShow, signature, strike, text, textCursor, themeAuto, themeDark
    case themeLight, tray, underline, unknownField, up, warning, zoomIn, zoomOut

    var assetName: String { "SPDFVIcon-\(rawValue)" }
}

struct SPDFVIcon: View {
    let name: SPDFVIconName
    let size: CGFloat

    init(_ name: SPDFVIconName, size: CGFloat = 13) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name.assetName)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SPDFVIconLabel: View {
    let title: String
    let icon: SPDFVIconName
    var size: CGFloat = 13

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SPDFVIcon(icon, size: size)
        }
    }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .system: .themeAuto
        case .light: .themeLight
        case .dark: .themeDark
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum SPDFVTheme {
    static let canvas = adaptive(light: 0xC2CAD6, dark: 0x151A21)
    static let folio = adaptive(light: 0xF7F9FC, dark: 0x242B35)
    static let navigator = adaptive(light: 0xE9EDF3, dark: 0x1B222C)
    static let navigatorInset = adaptive(light: 0xDDE3EB, dark: 0x11161D)
    static let statusBarBackground = adaptive(light: 0x202733, dark: 0x0C1016)
    static let primaryText = adaptive(light: 0x171C24, dark: 0xF4F7FB)
    static let secondaryText = adaptive(light: 0x5E6876, dark: 0xA7B0BD)
    static let tertiaryText = adaptive(light: 0x6F7A88, dark: 0x9AA4B1)
    static let navigatorText = adaptive(light: 0x27303C, dark: 0xECF1F7)
    static let navigatorMuted = adaptive(light: 0x4F5B6A, dark: 0xA4ADBA)
    static let navigatorFaint = adaptive(light: 0x5E6978, dark: 0x8C97A5)
    static let statusBarLabel = adaptive(light: 0xAAB4C1, dark: 0x8C96A4)
    static let statusBarText = adaptive(light: 0xE8EDF3, dark: 0xD5DCE5)
    static let divider = adaptive(light: 0x8A95A4, dark: 0x596575)
    static let controlPressed = adaptive(light: 0xE2E7EE, dark: 0x343D49)
    static let pageBorder = adaptive(light: 0xB8C1CD, dark: 0x4A5564)
    static let spineTrack = adaptive(light: 0x596575, dark: 0xFFFFFF, lightAlpha: 0.26, darkAlpha: 0.14)
    static let cobalt = adaptive(light: 0x2F62D8, dark: 0x356BE4)
    static let paleCobalt = adaptive(light: 0x245FCF, dark: 0x8FB5FF)
    static let redaction = adaptive(light: 0xB4232D, dark: 0xFF6B72)
    static let redactionInk = adaptive(light: 0x111318, dark: 0x050608)

    static func canvasNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(hex: 0x151A21)
            : NSColor(hex: 0xC2CAD6)
    }

    static func selectionNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(hex: 0x7FA7FF, alpha: 0.48)
            : NSColor(hex: 0x2F62D8, alpha: 0.34)
    }

    static func annotationNSColor(for kind: MarkupKind) -> NSColor {
        switch kind {
        case .highlight:
            NSColor(srgbRed: 1.0, green: 0.78, blue: 0.20, alpha: 0.58)
        case .underline:
            NSColor(srgbRed: 0.18, green: 0.38, blue: 0.85, alpha: 0.9)
        case .strikeOut:
            NSColor(srgbRed: 0.86, green: 0.25, blue: 0.24, alpha: 0.86)
        }
    }

    private static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
