import Combine
import Foundation
import SPDFVCore

struct RecipeWatchConfiguration: Codable, Equatable {
    let inputBookmark: Data
    let outputBookmark: Data
    let inputName: String
    let outputName: String
    let recipeID: UUID
    var isArmed: Bool
    var lastRunAt: Date?
}

private struct RecipeWatchMainActorReference<Value>: @unchecked Sendable {
    let value: Value
}

@MainActor
final class RecipeLibraryStore: ObservableObject {
    static let shared = RecipeLibraryStore()

    @Published private(set) var catalog: PDFRecipeLibraryCatalog
    @Published private(set) var watchConfiguration: RecipeWatchConfiguration?
    @Published private(set) var lastWatchReport: PDFRecipeBatchReport?
    @Published private(set) var watchStatus = "No watch lane configured"

    private let defaults: UserDefaults
    private let storageKey = "spdfv.recipe-library.v1"
    private let watchStorageKey = "spdfv.recipe-watch.v1"
    private var watchTimer: Timer?
    private var watchIsRunning = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(PDFRecipeLibraryCatalog.self, from: data) {
            catalog = decoded
        } else {
            catalog = Self.seedCatalog
            persist()
        }
        if let data = defaults.data(forKey: watchStorageKey),
           let decoded = try? JSONDecoder().decode(RecipeWatchConfiguration.self, from: data) {
            watchConfiguration = decoded
            watchStatus = decoded.isArmed ? "Watch lane armed" : "Watch lane paused"
        } else {
            watchConfiguration = nil
        }
        if watchConfiguration?.isArmed == true { startWatchTimer() }
    }

    var entries: [PDFRecipeLibraryEntry] {
        catalog.entries.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            if $0.kind != $1.kind { return $0.kind == .preset }
            return $0.updatedAt > $1.updatedAt
        }
    }

    @discardableResult
    func save(_ recipe: PDFRecipe, to entryID: UUID? = nil) throws -> UUID {
        let id = try catalog.save(recipe, to: entryID)
        persist()
        return id
    }

    @discardableResult
    func duplicate(_ entryID: UUID) throws -> UUID? {
        let id = try catalog.duplicate(entryID)
        persist()
        return id
    }

    func toggleFavorite(_ entryID: UUID) {
        catalog.toggleFavorite(entryID)
        persist()
    }

    func remove(_ entryID: UUID) {
        catalog.remove(entryID)
        persist()
    }

    @discardableResult
    func restore(_ revisionID: UUID, in entryID: UUID) throws -> Bool {
        let restored = try catalog.restore(revisionID, in: entryID)
        persist()
        return restored
    }

    func entry(_ id: UUID) -> PDFRecipeLibraryEntry? {
        catalog.entries.first { $0.id == id }
    }

    func configureWatch(input: URL, output: URL, recipeID: UUID) throws {
        guard input.standardizedFileURL != output.standardizedFileURL else {
            throw PDFOperationError.invalidInput("Watch input and output folders must be different")
        }
        guard entry(recipeID) != nil else {
            throw PDFOperationError.invalidInput("Choose a recipe from the cabinet")
        }
        let inputBookmark = try input.bookmarkData(options: .withSecurityScope)
        let outputBookmark = try output.bookmarkData(options: .withSecurityScope)
        watchConfiguration = RecipeWatchConfiguration(
            inputBookmark: inputBookmark,
            outputBookmark: outputBookmark,
            inputName: input.lastPathComponent,
            outputName: output.lastPathComponent,
            recipeID: recipeID,
            isArmed: true,
            lastRunAt: nil
        )
        watchStatus = "Watch lane armed"
        persistWatch()
        startWatchTimer()
        runWatchNow()
    }

    func setWatchArmed(_ armed: Bool) {
        guard var configuration = watchConfiguration else { return }
        configuration.isArmed = armed
        watchConfiguration = configuration
        watchStatus = armed ? "Watch lane armed" : "Watch lane paused"
        persistWatch()
        armed ? startWatchTimer() : stopWatchTimer()
    }

    func clearWatch() {
        stopWatchTimer()
        watchConfiguration = nil
        lastWatchReport = nil
        watchStatus = "No watch lane configured"
        defaults.removeObject(forKey: watchStorageKey)
    }

    func runWatchNow() {
        guard !watchIsRunning, var configuration = watchConfiguration,
              let recipe = entry(configuration.recipeID)?.recipe else { return }
        watchIsRunning = true
        defer { watchIsRunning = false }

        do {
            let input = try resolveBookmark(configuration.inputBookmark)
            let output = try resolveBookmark(configuration.outputBookmark)
            let inputAccess = input.startAccessingSecurityScopedResource()
            let outputAccess = output.startAccessingSecurityScopedResource()
            defer {
                if inputAccess { input.stopAccessingSecurityScopedResource() }
                if outputAccess { output.stopAccessingSecurityScopedResource() }
            }

            let urls = try FileManager.default.contentsOfDirectory(
                at: input,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
                .filter { $0.pathExtension.lowercased() == "pdf" }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                .filter { !FileManager.default.fileExists(atPath: output.appendingPathComponent($0.lastPathComponent).path) }

            guard !urls.isEmpty else {
                watchStatus = "Caught up · no new PDFs"
                return
            }
            let inputs = try urls.map { PDFRecipeBatchInput(name: $0.lastPathComponent, data: try Data(contentsOf: $0)) }
            let result = PDFRecipeBatchRunner.run(recipe, inputs: inputs)
            for produced in result.outputs {
                let destination = output.appendingPathComponent(produced.name)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                try produced.data.write(to: destination, options: .atomic)
            }
            let manifest = output.appendingPathComponent("spdfv-watch-manifest.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(result.report).write(to: manifest, options: .atomic)
            lastWatchReport = result.report
            configuration.lastRunAt = Date()
            watchConfiguration = configuration
            watchStatus = result.report.failedCount == 0
                ? "Passed \(result.report.passedCount) new PDF\(result.report.passedCount == 1 ? "" : "s")"
                : "Passed \(result.report.passedCount) · stopped \(result.report.failedCount)"
            persistWatch()
        } catch {
            watchStatus = "Watch stopped · \((error as? PDFOperationError)?.description ?? error.localizedDescription)"
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func persistWatch() {
        guard let watchConfiguration,
              let data = try? JSONEncoder().encode(watchConfiguration) else { return }
        defaults.set(data, forKey: watchStorageKey)
    }

    private func resolveBookmark(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else { throw PDFOperationError.invalidInput("A watched folder permission is stale; configure it again") }
        return url
    }

    private func startWatchTimer() {
        guard watchTimer == nil else { return }
        let reference = RecipeWatchMainActorReference(value: self)
        watchTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in
                guard reference.value.watchConfiguration?.isArmed == true else { return }
                reference.value.runWatchNow()
            }
        }
    }

    private func stopWatchTimer() {
        watchTimer?.invalidate()
        watchTimer = nil
    }

    private static let seedCatalog = PDFRecipeLibraryCatalog(entries: [
        PDFRecipeLibraryEntry(
            id: UUID(uuidString: "7D66DA15-4C0D-4DDC-BEEA-21E159678001")!,
            recipe: .starter,
            kind: .preset,
            isFavorite: true
        ),
        PDFRecipeLibraryEntry(
            id: UUID(uuidString: "7D66DA15-4C0D-4DDC-BEEA-21E159678002")!,
            recipe: PDFRecipe(name: "Form intake gate", steps: [
                .assertPageCount(minimum: 1, maximum: nil),
                .assertFields(names: ["full_name", "approved"]),
                .assertFormGate(maximum: .warning)
            ]),
            kind: .preset
        ),
        PDFRecipeLibraryEntry(
            id: UUID(uuidString: "7D66DA15-4C0D-4DDC-BEEA-21E159678003")!,
            recipe: PDFRecipe(name: "Publish-ready copy", steps: [
                .assertText(contains: [], excludes: ["Draft", "Confidential"]),
                .crop(pages: "all", insets: PDFEdgeInsets(top: 18, right: 18, bottom: 18, left: 18)),
                .extract(pages: "all")
            ]),
            kind: .preset
        ),
        PDFRecipeLibraryEntry(
            id: UUID(uuidString: "7D66DA15-4C0D-4DDC-BEEA-21E159678004")!,
            recipe: PDFRecipe(name: "Quarter-turn archive", steps: [
                .assertPageCount(minimum: 1, maximum: nil),
                .rotate(pages: "all", degrees: 90),
                .extract(pages: "all")
            ]),
            kind: .preset
        )
    ])
}
