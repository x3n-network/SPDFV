import Foundation


public struct PDFRecipe: Codable, Equatable, Sendable {
    public static let latestVersion = 3

    public let version: Int
    public let name: String
    public let steps: [PDFRecipeStep]
    public let parameters: [PDFRecipeParameter]
    public let outputNameTemplate: String?

    public init(
        version: Int = 1,
        name: String,
        steps: [PDFRecipeStep],
        parameters: [PDFRecipeParameter] = [],
        outputNameTemplate: String? = nil
    ) {
        self.version = version
        self.name = name
        self.steps = steps
        self.parameters = parameters
        self.outputNameTemplate = outputNameTemplate
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

public struct PDFRecipeParameter: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let defaultValue: String?
    public let required: Bool

    public init(name: String, defaultValue: String? = nil, required: Bool = true) {
        self.name = name
        self.defaultValue = defaultValue
        self.required = required
    }

    private enum CodingKeys: String, CodingKey { case name, defaultValue, required }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            defaultValue: try container.decodeIfPresent(String.self, forKey: .defaultValue),
            required: try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        if !required { try container.encode(false, forKey: .required) }
    }
}

extension PDFRecipe {
    private enum CodingKeys: String, CodingKey { case version, name, steps, parameters, outputNameTemplate }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            name: try container.decode(String.self, forKey: .name),
            steps: try container.decode([PDFRecipeStep].self, forKey: .steps),
            parameters: try container.decodeIfPresent([PDFRecipeParameter].self, forKey: .parameters) ?? [],
            outputNameTemplate: try container.decodeIfPresent(String.self, forKey: .outputNameTemplate)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(name, forKey: .name)
        try container.encode(steps, forKey: .steps)
        if !parameters.isEmpty { try container.encode(parameters, forKey: .parameters) }
        try container.encodeIfPresent(outputNameTemplate, forKey: .outputNameTemplate)
    }
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
    case importFormData(source: String)
    case assertCompare(reference: String, maximumChangedPages: Int, options: PDFComparisonOptions)
    case assertDoctor(maximum: PDFDoctorLevel)
    case ifParameter(name: String, equals: String, steps: [PDFRecipeStep])

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
        case .importFormData: "importFormData"
        case .assertCompare: "assertCompare"
        case .assertDoctor: "assertDoctor"
        case .ifParameter: "ifParameter"
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
        case .importFormData(let source): "Import form data \(source)"
        case .assertCompare(let reference, let maximum, _):
            "Compare with \(reference); allow \(maximum) changed page\(maximum == 1 ? "" : "s")"
        case .assertDoctor(let maximum): "Require Doctor \(maximum.rawValue) or better"
        case .ifParameter(let name, let expected, let steps):
            "If \(name) equals \(expected), run \(steps.count) step\(steps.count == 1 ? "" : "s")"
        }
    }

    public var minimumRecipeVersion: Int {
        switch self {
        case .duplicatePages, .deletePages, .ocr, .assertSafeShare: 2
        case .importFormData, .assertCompare, .assertDoctor, .ifParameter: 3
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
        case source, reference, maximumChangedPages, options, name, equals, steps
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
        case "importFormData":
            self = .importFormData(source: try container.decode(String.self, forKey: .source))
        case "assertCompare":
            self = .assertCompare(
                reference: try container.decode(String.self, forKey: .reference),
                maximumChangedPages: try container.decodeIfPresent(Int.self, forKey: .maximumChangedPages) ?? 0,
                options: try container.decodeIfPresent(PDFComparisonOptions.self, forKey: .options) ?? PDFComparisonOptions()
            )
        case "assertDoctor":
            self = .assertDoctor(maximum: try container.decode(PDFDoctorLevel.self, forKey: .maximum))
        case "ifParameter":
            self = .ifParameter(
                name: try container.decode(String.self, forKey: .name),
                equals: try container.decode(String.self, forKey: .equals),
                steps: try container.decode([PDFRecipeStep].self, forKey: .steps)
            )
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
        case .importFormData(let source):
            try container.encode(source, forKey: .source)
        case .assertCompare(let reference, let maximum, let options):
            try container.encode(reference, forKey: .reference)
            try container.encode(maximum, forKey: .maximumChangedPages)
            try container.encode(options, forKey: .options)
        case .assertDoctor(let maximum):
            try container.encode(maximum, forKey: .maximum)
        case .ifParameter(let name, let expected, let steps):
            try container.encode(name, forKey: .name)
            try container.encode(expected, forKey: .equals)
            try container.encode(steps, forKey: .steps)
        }
    }
}

public extension PDFRecipe {
    var requiredReferenceNames: [String] { Self.externalNames(in: steps, reference: true) }
    var requiredFormDataNames: [String] { Self.externalNames(in: steps, reference: false) }

    private static func externalNames(in steps: [PDFRecipeStep], reference: Bool) -> [String] {
        var names: Set<String> = []
        for step in steps {
            switch step {
            case .assertCompare(let name, _, _) where reference: names.insert(name)
            case .importFormData(let name) where !reference: names.insert(name)
            case .ifParameter(_, _, let nested): names.formUnion(externalNames(in: nested, reference: reference))
            default: break
            }
        }
        return names.sorted()
    }
}
