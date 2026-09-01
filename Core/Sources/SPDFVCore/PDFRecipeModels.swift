import Foundation


public struct PDFRecipe: Codable, Equatable, Sendable {
    public static let latestVersion = 2

    public let version: Int
    public let name: String
    public let steps: [PDFRecipeStep]

    public init(version: Int = 1, name: String, steps: [PDFRecipeStep]) {
        self.version = version
        self.name = name
        self.steps = steps
    }

    public static let starter = PDFRecipe(
        name: "Verified proof copy",
        steps: [
            .assertPageCount(minimum: 1, maximum: nil),
            .rotate(pages: "all", degrees: 0),
            .crop(pages: "all", insets: .zero),
            .extract(pages: "all")
        ]
    )
}

public enum PDFRecipeStep: Equatable, Sendable {
    case renameField(from: String, to: String)
    case fillForm(values: [String: String])
    case rotate(pages: String, degrees: Int)
    case crop(pages: String, insets: PDFEdgeInsets)
    case extract(pages: String)
    case duplicatePages(pages: String)
    case deletePages(pages: String)
    case ocr(pages: String, configuration: PDFOCRConfiguration)
    case assertPageCount(minimum: Int?, maximum: Int?)
    case assertText(contains: [String], excludes: [String])
    case assertFields(names: [String])
    case assertFormGate(maximum: PDFFormGateLevel)
    case assertSafeShare(maximum: PDFSafetyGateLevel)

    public var operation: String {
        switch self {
        case .renameField: "renameField"
        case .fillForm: "fillForm"
        case .rotate: "rotate"
        case .crop: "crop"
        case .extract: "extract"
        case .duplicatePages: "duplicatePages"
        case .deletePages: "deletePages"
        case .ocr: "ocr"
        case .assertPageCount: "assertPageCount"
        case .assertText: "assertText"
        case .assertFields: "assertFields"
        case .assertFormGate: "assertFormGate"
        case .assertSafeShare: "assertSafeShare"
        }
    }

    public var summary: String {
        switch self {
        case .renameField(let source, let destination): "Rename \(source) to \(destination)"
        case .fillForm(let values): "Fill \(values.count) field\(values.count == 1 ? "" : "s")"
        case .rotate(let pages, let degrees): "Rotate pages \(pages) by \(degrees) degrees"
        case .crop(let pages, let insets):
            "Crop pages \(pages) by \(Self.insetsLabel(insets)) pt"
        case .extract(let pages): "Keep pages \(pages)"
        case .duplicatePages(let pages): "Duplicate pages \(pages)"
        case .deletePages(let pages): "Delete pages \(pages)"
        case .ocr(let pages, let configuration):
            "OCR pages \(pages) at \(Self.number(configuration.renderDPI)) DPI"
        case .assertPageCount(let minimum, let maximum):
            switch (minimum, maximum) {
            case let (minimum?, maximum?): "Require \(minimum)-\(maximum) pages"
            case let (minimum?, nil): "Require at least \(minimum) page\(minimum == 1 ? "" : "s")"
            case let (nil, maximum?): "Require at most \(maximum) page\(maximum == 1 ? "" : "s")"
            case (nil, nil): "Require a valid page count"
            }
        case .assertText(let contains, let excludes):
            "Require \(contains.count) and exclude \(excludes.count) text term\(contains.count + excludes.count == 1 ? "" : "s")"
        case .assertFields(let names): "Require \(names.count) field\(names.count == 1 ? "" : "s")"
        case .assertFormGate(let maximum): "Require Form Gate \(maximum.rawValue) or better"
        case .assertSafeShare(let maximum): "Require Safe Share \(maximum.rawValue) or better"
        }
    }

    public var minimumRecipeVersion: Int {
        switch self {
        case .duplicatePages, .deletePages, .ocr, .assertSafeShare: 2
        default: 1
        }
    }

    private static func insetsLabel(_ insets: PDFEdgeInsets) -> String {
        if insets.top == insets.right, insets.top == insets.bottom, insets.top == insets.left {
            return Self.number(insets.top)
        }
        return [insets.top, insets.right, insets.bottom, insets.left].map(Self.number).joined(separator: ",")
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

extension PDFRecipeStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case operation, from, to, values, pages, degrees, insets, configuration
        case minimum, maximum, contains, excludes, names
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try container.decode(String.self, forKey: .operation)
        switch operation {
        case "renameField":
            self = .renameField(
                from: try container.decode(String.self, forKey: .from),
                to: try container.decode(String.self, forKey: .to)
            )
        case "fillForm":
            self = .fillForm(values: try container.decode([String: String].self, forKey: .values))
        case "rotate":
            self = .rotate(
                pages: try container.decode(String.self, forKey: .pages),
                degrees: try container.decode(Int.self, forKey: .degrees)
            )
        case "crop":
            self = .crop(
                pages: try container.decode(String.self, forKey: .pages),
                insets: try container.decode(PDFEdgeInsets.self, forKey: .insets)
            )
        case "extract":
            self = .extract(pages: try container.decode(String.self, forKey: .pages))
        case "duplicatePages":
            self = .duplicatePages(pages: try container.decode(String.self, forKey: .pages))
        case "deletePages":
            self = .deletePages(pages: try container.decode(String.self, forKey: .pages))
        case "ocr":
            self = .ocr(
                pages: try container.decode(String.self, forKey: .pages),
                configuration: try container.decode(PDFOCRConfiguration.self, forKey: .configuration)
            )
        case "assertPageCount":
            self = .assertPageCount(
                minimum: try container.decodeIfPresent(Int.self, forKey: .minimum),
                maximum: try container.decodeIfPresent(Int.self, forKey: .maximum)
            )
        case "assertText":
            self = .assertText(
                contains: try container.decodeIfPresent([String].self, forKey: .contains) ?? [],
                excludes: try container.decodeIfPresent([String].self, forKey: .excludes) ?? []
            )
        case "assertFields":
            self = .assertFields(names: try container.decode([String].self, forKey: .names))
        case "assertFormGate":
            self = .assertFormGate(maximum: try container.decode(PDFFormGateLevel.self, forKey: .maximum))
        case "assertSafeShare":
            self = .assertSafeShare(maximum: try container.decode(PDFSafetyGateLevel.self, forKey: .maximum))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .operation,
                in: container,
                debugDescription: "Unsupported recipe operation: \(operation)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation, forKey: .operation)
        switch self {
        case .renameField(let source, let destination):
            try container.encode(source, forKey: .from)
            try container.encode(destination, forKey: .to)
        case .fillForm(let values):
            try container.encode(values, forKey: .values)
        case .rotate(let pages, let degrees):
            try container.encode(pages, forKey: .pages)
            try container.encode(degrees, forKey: .degrees)
        case .crop(let pages, let insets):
            try container.encode(pages, forKey: .pages)
            try container.encode(insets, forKey: .insets)
        case .extract(let pages):
            try container.encode(pages, forKey: .pages)
        case .duplicatePages(let pages), .deletePages(let pages):
            try container.encode(pages, forKey: .pages)
        case .ocr(let pages, let configuration):
            try container.encode(pages, forKey: .pages)
            try container.encode(configuration, forKey: .configuration)
        case .assertPageCount(let minimum, let maximum):
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case .assertText(let contains, let excludes):
            if !contains.isEmpty { try container.encode(contains, forKey: .contains) }
            if !excludes.isEmpty { try container.encode(excludes, forKey: .excludes) }
        case .assertFields(let names):
            try container.encode(names, forKey: .names)
        case .assertFormGate(let maximum):
            try container.encode(maximum, forKey: .maximum)
        case .assertSafeShare(let maximum):
            try container.encode(maximum, forKey: .maximum)
        }
    }
}
