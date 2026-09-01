import AppKit
import Foundation
import PDFKit
import SPDFVCore
import UniformTypeIdentifiers

extension DocumentSession {
func importRecipeFromPicker() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = "Choose a versioned SPDFV recipe"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
        loadedRecipe = try PDFRecipeRunner.decode(Data(contentsOf: url))
        configureRecipeInputs(for: loadedRecipe)
        loadedRecipeName = url.lastPathComponent
        activeLibraryRecipeID = nil
        recipeReport = nil
        lastRecipeOutputURL = nil
        batchRecipeReport = nil
        lastBatchOutputDirectory = nil
    } catch {
        errorMessage = "The recipe could not be loaded: \(Self.message(for: error))"
    }
}

func loadStarterRecipe() {
    loadedRecipe = .starter
    configureRecipeInputs(for: loadedRecipe)
    loadedRecipeName = "starter-recipe.json"
    activeLibraryRecipeID = nil
    recipeReport = nil
    lastRecipeOutputURL = nil
    batchRecipeReport = nil
    lastBatchOutputDirectory = nil
}

func renameLoadedRecipe(_ name: String) {
    guard let recipe = loadedRecipe, recipe.name != name else { return }
    loadedRecipe = PDFRecipe(version: recipe.version, name: name, steps: recipe.steps, parameters: recipe.parameters, outputNameTemplate: recipe.outputNameTemplate)
    markRecipeEdited()
}

func updateRecipeConfiguration(parameters: [PDFRecipeParameter], outputNameTemplate: String?) {
    guard let recipe = loadedRecipe else { return }
    let template = outputNameTemplate?.trimmingCharacters(in: .whitespacesAndNewlines)
    loadedRecipe = PDFRecipe(
        version: parameters.isEmpty && template == nil ? recipe.version : max(recipe.version, 3),
        name: recipe.name,
        steps: recipe.steps,
        parameters: parameters,
        outputNameTemplate: template?.isEmpty == true ? nil : template
    )
    let prior = recipeParameterValues
    recipeParameterValues = Dictionary(uniqueKeysWithValues: parameters.map {
        ($0.name, prior[$0.name] ?? $0.defaultValue ?? "")
    })
    markRecipeEdited()
}

func addRecipeStep(_ step: PDFRecipeStep, after index: Int? = nil) {
    guard let recipe = loadedRecipe else { return }
    var steps = recipe.steps
    var parameters = recipe.parameters
    if case .ifParameter(let name, _, _) = step,
       !parameters.contains(where: { $0.name == name }) {
        parameters.append(PDFRecipeParameter(name: name))
        recipeParameterValues[name] = ""
    }
    let insertionIndex = min(max(0, (index ?? (steps.count - 1)) + 1), steps.count)
    steps.insert(step, at: insertionIndex)
    loadedRecipe = PDFRecipe(
        version: max(recipe.version, step.minimumRecipeVersion),
        name: recipe.name,
        steps: steps,
        parameters: parameters,
        outputNameTemplate: recipe.outputNameTemplate
    )
    markRecipeEdited()
}

func updateRecipeStep(at index: Int, to step: PDFRecipeStep) {
    guard let recipe = loadedRecipe, recipe.steps.indices.contains(index), recipe.steps[index] != step else { return }
    var steps = recipe.steps
    steps[index] = step
    loadedRecipe = PDFRecipe(
        version: max(recipe.version, step.minimumRecipeVersion),
        name: recipe.name,
        steps: steps,
        parameters: recipe.parameters,
        outputNameTemplate: recipe.outputNameTemplate
    )
    markRecipeEdited()
}

func removeRecipeStep(at index: Int) {
    guard let recipe = loadedRecipe, recipe.steps.indices.contains(index) else { return }
    var steps = recipe.steps
    steps.remove(at: index)
    loadedRecipe = PDFRecipe(version: recipe.version, name: recipe.name, steps: steps, parameters: recipe.parameters, outputNameTemplate: recipe.outputNameTemplate)
    markRecipeEdited()
}

func moveRecipeStep(from source: Int, to destination: Int) {
    guard let recipe = loadedRecipe,
          recipe.steps.indices.contains(source),
          destination >= 0,
          destination < recipe.steps.count,
          source != destination else { return }
    var steps = recipe.steps
    let moved = steps.remove(at: source)
    steps.insert(moved, at: destination)
    loadedRecipe = PDFRecipe(version: recipe.version, name: recipe.name, steps: steps, parameters: recipe.parameters, outputNameTemplate: recipe.outputNameTemplate)
    markRecipeEdited()
}

func saveLoadedRecipe() {
    guard let recipe = loadedRecipe else { return }
    do {
        let data = try PDFRecipeRunner.encode(recipe, pretty: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.recipeFilename(recipe.name)
        panel.message = "Save this reusable SPDFV recipe"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
        loadedRecipeName = url.lastPathComponent
    } catch {
        errorMessage = "The recipe could not be saved: \(Self.message(for: error))"
    }
}

func copyLoadedRecipe() {
    guard let recipe = loadedRecipe else { return }
    do {
        let text = String(decoding: try PDFRecipeRunner.encode(recipe, pretty: true), as: UTF8.self)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    } catch {
        errorMessage = "The recipe could not be copied: \(Self.message(for: error))"
    }
}

func shareLoadedRecipe() {
    guard let recipe = loadedRecipe else { return }
    do {
        let text = String(decoding: try PDFRecipeRunner.encode(recipe, pretty: true), as: UTF8.self)
        guard let anchor = NSApp.keyWindow?.contentView else {
            throw PDFOperationError.operationFailed("No active window is available for sharing")
        }
        NSSharingServicePicker(items: [text]).show(
            relativeTo: NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY, width: 1, height: 1),
            of: anchor,
            preferredEdge: .minY
        )
    } catch {
        errorMessage = "The recipe could not be shared: \(Self.message(for: error))"
    }
}

func loadLibraryRecipe(_ entryID: UUID) {
    guard let entry = RecipeLibraryStore.shared.entry(entryID) else { return }
    loadedRecipe = entry.recipe
    configureRecipeInputs(for: loadedRecipe)
    activeLibraryRecipeID = entry.id
    loadedRecipeName = "\(entry.kind == .preset ? "PRESET" : "CABINET") · R\(entry.revision)"
    clearRecipeProof()
}

func saveLoadedRecipeToLibrary() {
    guard let recipe = loadedRecipe else { return }
    do {
        let targetID: UUID?
        if let activeLibraryRecipeID,
           RecipeLibraryStore.shared.entry(activeLibraryRecipeID)?.kind == .personal {
            targetID = activeLibraryRecipeID
        } else {
            targetID = nil
        }
        let id = try RecipeLibraryStore.shared.save(recipe, to: targetID)
        activeLibraryRecipeID = id
        if let entry = RecipeLibraryStore.shared.entry(id) {
            loadedRecipeName = "CABINET · R\(entry.revision)"
        }
    } catch {
        errorMessage = "The recipe could not enter the cabinet: \(Self.message(for: error))"
    }
}

func duplicateLibraryRecipe(_ entryID: UUID) {
    do {
        guard let duplicateID = try RecipeLibraryStore.shared.duplicate(entryID) else { return }
        loadLibraryRecipe(duplicateID)
    } catch {
        errorMessage = "The recipe could not be duplicated: \(Self.message(for: error))"
    }
}

func restoreLibraryRevision(_ revisionID: UUID, entryID: UUID) {
    do {
        guard try RecipeLibraryStore.shared.restore(revisionID, in: entryID) else { return }
        loadLibraryRecipe(entryID)
    } catch {
        errorMessage = "The recipe revision could not be restored: \(Self.message(for: error))"
    }
}

func removeLibraryRecipe(_ entryID: UUID) {
    guard RecipeLibraryStore.shared.entry(entryID)?.kind == .personal else { return }
    RecipeLibraryStore.shared.remove(entryID)
    if activeLibraryRecipeID == entryID {
        activeLibraryRecipeID = nil
        loadedRecipeName = "UNSAVED RECIPE"
    }
}

func configureRecipeWatch(_ entryID: UUID) {
    let inputPanel = NSOpenPanel()
    inputPanel.canChooseFiles = false
    inputPanel.canChooseDirectories = true
    inputPanel.canCreateDirectories = false
    inputPanel.allowsMultipleSelection = false
    inputPanel.prompt = "Watch Input"
    inputPanel.message = "Choose the folder SPDFV should scan for new PDF files"
    guard inputPanel.runModal() == .OK, let input = inputPanel.url else { return }

    let outputPanel = NSOpenPanel()
    outputPanel.canChooseFiles = false
    outputPanel.canChooseDirectories = true
    outputPanel.canCreateDirectories = true
    outputPanel.allowsMultipleSelection = false
    outputPanel.prompt = "Watch Output"
    outputPanel.message = "Choose where passing PDFs and the watch manifest should be written"
    guard outputPanel.runModal() == .OK, let output = outputPanel.url else { return }

    do {
        try RecipeLibraryStore.shared.configureWatch(input: input, output: output, recipeID: entryID)
    } catch {
        errorMessage = "The watch lane could not be configured: \(Self.message(for: error))"
    }
}

private func markRecipeEdited() {
    loadedRecipeName = activeLibraryRecipeID == nil ? "UNSAVED RECIPE" : "CABINET DRAFT"
    clearRecipeProof()
}

private func clearRecipeProof() {
    recipeReport = nil
    lastRecipeOutputURL = nil
    batchRecipeReport = nil
    lastBatchOutputDirectory = nil
}

private func configureRecipeInputs(for recipe: PDFRecipe?) {
    recipeReferences = [:]
    recipeFormDataSources = [:]
    recipeParameterValues = Dictionary(uniqueKeysWithValues: (recipe?.parameters ?? []).map {
        ($0.name, $0.defaultValue ?? "")
    })
}

private func recipeExecutionContext(inputName: String?) -> PDFRecipeExecutionContext {
    PDFRecipeExecutionContext(
        parameters: recipeParameterValues,
        references: recipeReferences,
        formData: recipeFormDataSources,
        inputName: inputName
    )
}

func setRecipeParameter(_ name: String, value: String) {
    recipeParameterValues[name] = value
    if let recipe = loadedRecipe {
        for source in recipe.requiredReferenceNames {
            if let data = recipeReferences[source] { recipeReferences[resolvedRecipeInputKey(source)] = data }
        }
        for source in recipe.requiredFormDataNames {
            if let data = recipeFormDataSources[source] { recipeFormDataSources[resolvedRecipeInputKey(source)] = data }
        }
    }
    clearRecipeProof()
}

func chooseRecipeReference(named name: String) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    panel.allowsMultipleSelection = false
    panel.message = "Choose the PDF reference named \(name)"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        let data = try Data(contentsOf: url)
        recipeReferences[name] = data
        recipeReferences[resolvedRecipeInputKey(name)] = data
        clearRecipeProof()
    } catch {
        errorMessage = "The recipe reference could not be loaded: \(Self.message(for: error))"
    }
}

func chooseRecipeFormData(named name: String) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.message = "Choose the form-data JSON named \(name)"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        let data = try PDFOperations.decodeFormData(Data(contentsOf: url))
        recipeFormDataSources[name] = data
        recipeFormDataSources[resolvedRecipeInputKey(name)] = data
        clearRecipeProof()
    } catch {
        errorMessage = "The recipe form data could not be loaded: \(Self.message(for: error))"
    }
}

private func resolvedRecipeInputKey(_ source: String) -> String {
    var result = source
    for (name, value) in recipeParameterValues {
        result = result.replacingOccurrences(of: "{{\(name)}}", with: value)
    }
    if let recipe = loadedRecipe {
        result = result.replacingOccurrences(of: "{{recipeName}}", with: recipe.name)
    }
    return result
}

private static func recipeFilename(_ name: String) -> String {
    let slug = name.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
    return "\(slug.isEmpty ? "spdfv-recipe" : slug).json"
}

func validateLoadedRecipe() {
    guard let loadedRecipe, let data = document?.dataRepresentation() else { return }
    isRunningRecipe = true
    defer { isRunningRecipe = false }
    let activityID = ActivityCenterStore.shared.begin(
        kind: .recipe,
        title: "Check \(loadedRecipe.name)",
        detail: "Verifying \(loadedRecipe.steps.count) recipe step\(loadedRecipe.steps.count == 1 ? "" : "s") without writing output",
        documentName: displayName
    )
    do {
        recipeReport = try PDFRecipeRunner.run(
            loadedRecipe,
            on: data,
            dryRun: true,
            context: recipeExecutionContext(inputName: displayName)
        ).report
        lastRecipeOutputURL = nil
        batchRecipeReport = nil
        lastBatchOutputDirectory = nil
        ActivityCenterStore.shared.finish(
            activityID,
            detail: "Verified \(recipeReport?.steps.count ?? 0) step\((recipeReport?.steps.count ?? 0) == 1 ? "" : "s") · \(recipeReport?.outputPageCount ?? 0) output page\((recipeReport?.outputPageCount ?? 0) == 1 ? "" : "s")"
        )
    } catch {
        recipeReport = nil
        errorMessage = "Recipe dry-run failed: \(Self.message(for: error))"
        ActivityCenterStore.shared.fail(activityID, detail: Self.message(for: error))
    }
}

func exportLoadedRecipe() {
    guard let loadedRecipe, let data = document?.dataRepresentation() else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.canCreateDirectories = true
    do {
        panel.nameFieldStringValue = try PDFRecipeRunner.suggestedOutputName(
            for: loadedRecipe,
            context: recipeExecutionContext(inputName: displayName)
        ) ?? "\(displayName)-processed.pdf"
    } catch {
        errorMessage = "Recipe export inputs are incomplete: \(Self.message(for: error))"
        return
    }
    panel.message = "Export the verified recipe result as a new PDF"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    isRunningRecipe = true
    defer { isRunningRecipe = false }
    let activityID = ActivityCenterStore.shared.begin(
        kind: .recipe,
        title: "Export \(loadedRecipe.name)",
        detail: "Applying \(loadedRecipe.steps.count) recipe step\(loadedRecipe.steps.count == 1 ? "" : "s")",
        documentName: displayName
    )
    do {
        let result = try PDFRecipeRunner.run(
            loadedRecipe,
            on: data,
            context: recipeExecutionContext(inputName: displayName)
        )
        try result.data.write(to: url, options: .atomic)
        guard let reopened = PDFDocument(url: url), reopened.pageCount == result.report.outputPageCount else {
            throw PDFOperationError.operationFailed("Exported recipe output failed final verification")
        }
        recipeReport = result.report
        lastRecipeOutputURL = url
        batchRecipeReport = nil
        lastBatchOutputDirectory = nil
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecentDocuments()
        ActivityCenterStore.shared.finish(
            activityID,
            detail: "Exported \(result.report.outputPageCount) page\(result.report.outputPageCount == 1 ? "" : "s") after \(result.report.steps.count) verified step\(result.report.steps.count == 1 ? "" : "s")",
            outputURL: url
        )
    } catch {
        errorMessage = "Recipe export failed: \(Self.message(for: error))"
        ActivityCenterStore.shared.fail(activityID, detail: Self.message(for: error))
    }
}

func copyStarterRecipe() {
    do {
        let text = String(decoding: try PDFRecipeRunner.encodedStarterRecipe(pretty: true), as: UTF8.self)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    } catch {
        errorMessage = "The starter recipe could not be copied: \(Self.message(for: error))"
    }
}

func processRecipeFolder() {
    guard let loadedRecipe else { return }
    let inputPanel = NSOpenPanel()
    inputPanel.canChooseFiles = false
    inputPanel.canChooseDirectories = true
    inputPanel.canCreateDirectories = false
    inputPanel.allowsMultipleSelection = false
    inputPanel.prompt = "Choose Input"
    inputPanel.message = "Choose a folder whose direct PDF files should use this recipe"
    guard inputPanel.runModal() == .OK, let inputDirectory = inputPanel.url else { return }

    let outputPanel = NSOpenPanel()
    outputPanel.canChooseFiles = false
    outputPanel.canChooseDirectories = true
    outputPanel.canCreateDirectories = true
    outputPanel.allowsMultipleSelection = false
    outputPanel.prompt = "Choose Output"
    outputPanel.message = "Choose an empty output folder for passing PDFs and the batch manifest"
    guard outputPanel.runModal() == .OK, let outputDirectory = outputPanel.url else { return }
    guard inputDirectory.standardizedFileURL != outputDirectory.standardizedFileURL else {
        errorMessage = "Choose different input and output folders for batch processing."
        return
    }

    isRunningRecipe = true
    defer { isRunningRecipe = false }
    let activityID = ActivityCenterStore.shared.begin(
        kind: .batch,
        title: "Process folder with \(loadedRecipe.name)",
        detail: "Reading PDFs from \(inputDirectory.lastPathComponent)",
        documentName: displayName
    )
    do {
        let urls = try FileManager.default.contentsOfDirectory(
            at: inputDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        guard !urls.isEmpty else { throw PDFOperationError.invalidInput("The input folder contains no PDF files") }
        let inputs = try urls.map {
            PDFRecipeBatchInput(name: $0.lastPathComponent, data: try Data(contentsOf: $0))
        }
        let result = PDFRecipeBatchRunner.run(
            loadedRecipe,
            inputs: inputs,
            context: recipeExecutionContext(inputName: nil)
        )
        let manifestURL = outputDirectory.appendingPathComponent("spdfv-batch-manifest.json")
        let destinations = result.outputs.map { outputDirectory.appendingPathComponent($0.name) } + [manifestURL]
        if let collision = destinations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            throw PDFOperationError.outputExists("Output already exists: \(collision.lastPathComponent). Choose an empty folder.")
        }
        for output in result.outputs {
            try output.data.write(to: outputDirectory.appendingPathComponent(output.name), options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(result.report).write(to: manifestURL, options: .atomic)
        batchRecipeReport = result.report
        lastBatchOutputDirectory = outputDirectory
        recipeReport = nil
        lastRecipeOutputURL = nil
        ActivityCenterStore.shared.finish(
            activityID,
            detail: "Passed \(result.report.passedCount) · stopped \(result.report.failedCount)",
            outputURL: outputDirectory
        )
    } catch {
        errorMessage = "Batch processing failed: \(Self.message(for: error))"
        ActivityCenterStore.shared.fail(activityID, detail: Self.message(for: error))
    }
}
}
