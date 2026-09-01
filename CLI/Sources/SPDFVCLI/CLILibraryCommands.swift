import Foundation
import SPDFVCore

func libraryList(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--library"])
    guard parser.positional.isEmpty else { throw CLIError.usage("library-list does not accept positional arguments") }
    let libraryURL = fileURL(try parser.requireOption("--library"))
    let catalog = FileManager.default.fileExists(atPath: libraryURL.path)
        ? try decodeFile(PDFRecipeLibraryCatalog.self, at: libraryURL)
        : PDFRecipeLibraryCatalog()
    let entries = catalog.entries.sorted {
        if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
        return $0.updatedAt > $1.updatedAt
    }
    print(try encode(
        RecipeLibraryOperationReport(
            operation: "library-list",
            library: libraryURL.path,
            count: entries.count,
            entry: nil,
            entries: entries,
            output: nil
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func libraryAdd(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--library", "--recipe"])
    guard parser.positional.isEmpty else { throw CLIError.usage("library-add does not accept positional arguments") }
    let libraryURL = fileURL(try parser.requireOption("--library"))
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    var catalog = FileManager.default.fileExists(atPath: libraryURL.path)
        ? try decodeFile(PDFRecipeLibraryCatalog.self, at: libraryURL)
        : PDFRecipeLibraryCatalog()
    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    let id = try catalog.save(recipe)
    if parser.flags.contains("--favorite") { catalog.toggleFavorite(id) }
    try writeJSONFile(catalog, to: libraryURL)
    let entry = catalog.entries.first { $0.id == id }
    print(try encode(
        RecipeLibraryOperationReport(
            operation: "library-add",
            library: libraryURL.path,
            count: catalog.entries.count,
            entry: entry,
            entries: nil,
            output: nil
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func libraryExport(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--library", "--id", "--output"])
    guard parser.positional.isEmpty else { throw CLIError.usage("library-export does not accept positional arguments") }
    let libraryURL = fileURL(try parser.requireOption("--library"))
    let outputURL = fileURL(try parser.requireOption("--output"))
    guard let id = UUID(uuidString: try parser.requireOption("--id")) else {
        throw CLIError.usage("--id must be a UUID")
    }
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let catalog = try decodeFile(PDFRecipeLibraryCatalog.self, at: libraryURL)
    guard let entry = catalog.entries.first(where: { $0.id == id }) else {
        throw CLIError.failure("Recipe not found in library: \(id.uuidString)")
    }
    try writeJSONFile(entry.recipe, to: outputURL)
    print(try encode(
        RecipeLibraryOperationReport(
            operation: "library-export",
            library: libraryURL.path,
            count: catalog.entries.count,
            entry: entry,
            entries: nil,
            output: outputURL.path
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}
