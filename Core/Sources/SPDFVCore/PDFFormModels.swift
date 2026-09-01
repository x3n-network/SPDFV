import Foundation

public enum PDFFormFieldKind: String, Codable, Sendable {
    case text
    case checkbox
    case radio
    case pushButton
    case choice
    case signature
    case unknown
}

public struct PDFFormFieldReport: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let page: Int
    public let kind: PDFFormFieldKind
    public let value: String
    public let bounds: PDFRectReport
    public let choices: [String]
    public let readOnly: Bool
    public let hasNormalAppearance: Bool

    public init(
        id: String,
        name: String,
        page: Int,
        kind: PDFFormFieldKind,
        value: String,
        bounds: PDFRectReport,
        choices: [String],
        readOnly: Bool,
        hasNormalAppearance: Bool
    ) {
        self.id = id
        self.name = name
        self.page = page
        self.kind = kind
        self.value = value
        self.bounds = bounds
        self.choices = choices
        self.readOnly = readOnly
        self.hasNormalAppearance = hasNormalAppearance
    }
}

public struct PDFFormReport: Codable, Equatable, Sendable {
    public let fields: [PDFFormFieldReport]
    public let widgetCount: Int
    public let canonicalFieldCount: Int
    public let widgetsWithNormalAppearance: Int
    public let canonicalFieldNames: [String]
    public let orphanWidgetNames: [String]
    public let canonicalFieldsWithoutWidgets: [String]
    public let conflictingWidgetNames: [String]
    public let widgetsMissingAppearances: [String]

    public var isInteractive: Bool { widgetCount > 0 && canonicalFieldCount > 0 }
}

public enum PDFFormGateLevel: String, Codable, Comparable, CaseIterable, Sendable {
    case pass
    case warning
    case stop

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let rank: [Self: Int] = [.pass: 0, .warning: 1, .stop: 2]
        return rank[lhs, default: 0] < rank[rhs, default: 0]
    }
}

public struct PDFFormGateIssue: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let level: PDFFormGateLevel
    public let title: String
    public let detail: String
    public let fields: [String]
}

public struct PDFFormGateReport: Codable, Equatable, Sendable {
    public let level: PDFFormGateLevel
    public let widgetCount: Int
    public let canonicalFieldCount: Int
    public let issues: [PDFFormGateIssue]

    public var canSave: Bool { level != .stop }
}

public struct PDFFormFillResult: Sendable {
    public let data: Data
    public let report: PDFFormReport
}

public struct PDFFormFieldDraft: Codable, Equatable, Sendable {
    public let name: String
    public let kind: PDFFormFieldKind
    public let value: String
    public let choices: [String]

    public init(name: String, kind: PDFFormFieldKind, value: String = "", choices: [String] = []) {
        self.name = name
        self.kind = kind
        self.value = value
        self.choices = choices
    }
}
