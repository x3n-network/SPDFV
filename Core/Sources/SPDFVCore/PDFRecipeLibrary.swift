import Foundation

public struct PDFRecipeRevision: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let revision: Int
    public let savedAt: Date
    public let recipe: PDFRecipe

    public init(id: UUID = UUID(), revision: Int, savedAt: Date, recipe: PDFRecipe) {
        self.id = id
        self.revision = revision
        self.savedAt = savedAt
        self.recipe = recipe
    }
}

public enum PDFRecipeLibraryKind: String, Codable, Equatable, Sendable {
    case preset
    case personal
}

public struct PDFRecipeLibraryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var recipe: PDFRecipe
    public var kind: PDFRecipeLibraryKind
    public var isFavorite: Bool
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var history: [PDFRecipeRevision]

    public init(
        id: UUID = UUID(),
        recipe: PDFRecipe,
        kind: PDFRecipeLibraryKind = .personal,
        isFavorite: Bool = false,
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        history: [PDFRecipeRevision] = []
    ) {
        self.id = id
        self.recipe = recipe
        self.kind = kind
        self.isFavorite = isFavorite
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.history = history
    }
}

public struct PDFRecipeLibraryCatalog: Codable, Equatable, Sendable {
    public private(set) var entries: [PDFRecipeLibraryEntry]

    public init(entries: [PDFRecipeLibraryEntry] = []) {
        self.entries = entries
    }

    @discardableResult
    public mutating func save(
        _ recipe: PDFRecipe,
        to entryID: UUID? = nil,
        kind: PDFRecipeLibraryKind = .personal,
        at date: Date = Date()
    ) throws -> UUID {
        try PDFRecipeRunner.validate(recipe)
        if let entryID, let index = entries.firstIndex(where: { $0.id == entryID }) {
            guard entries[index].recipe != recipe else {
                entries[index].updatedAt = date
                return entryID
            }
            let snapshot = PDFRecipeRevision(
                revision: entries[index].revision,
                savedAt: entries[index].updatedAt,
                recipe: entries[index].recipe
            )
            entries[index].history = Array((entries[index].history + [snapshot]).suffix(20))
            entries[index].recipe = recipe
            entries[index].revision += 1
            entries[index].updatedAt = date
            entries[index].kind = .personal
            return entryID
        }

        let entry = PDFRecipeLibraryEntry(recipe: recipe, kind: kind, createdAt: date, updatedAt: date)
        entries.append(entry)
        return entry.id
    }

    @discardableResult
    public mutating func duplicate(_ entryID: UUID, at date: Date = Date()) throws -> UUID? {
        guard let source = entries.first(where: { $0.id == entryID }) else { return nil }
        let duplicate = PDFRecipe(
            version: source.recipe.version,
            name: "\(source.recipe.name) copy",
            steps: source.recipe.steps
        )
        return try save(duplicate, kind: .personal, at: date)
    }

    public mutating func toggleFavorite(_ entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].isFavorite.toggle()
    }

    public mutating func remove(_ entryID: UUID) {
        entries.removeAll { $0.id == entryID }
    }

    @discardableResult
    public mutating func restore(_ revisionID: UUID, in entryID: UUID, at date: Date = Date()) throws -> Bool {
        guard let entry = entries.first(where: { $0.id == entryID }),
              let revision = entry.history.first(where: { $0.id == revisionID }) else { return false }
        _ = try save(revision.recipe, to: entryID, at: date)
        return true
    }
}
