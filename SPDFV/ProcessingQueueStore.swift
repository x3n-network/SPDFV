import AppKit
import Combine
import Foundation
import ServiceManagement
import SPDFVCore
import UniformTypeIdentifiers

private struct AutomationJobAccess: Codable {
    let inputBookmark: Data
    let recipeBookmark: Data
    let outputDirectoryBookmark: Data
}

private struct ProcessingQueueMainActorReference<Value>: @unchecked Sendable {
    let value: Value
}

@MainActor
final class ProcessingQueueStore: ObservableObject {
    static let shared = ProcessingQueueStore()

    @Published private(set) var queue: PDFRecipeJobQueue
    @Published private(set) var isRunning = false
    @Published var notice = "Queue ready"
    @Published private(set) var backgroundStatus = BackgroundProcessingStatus.off

    private let defaults: UserDefaults
    private let queueKey = "spdfv.processing-queue.queue.v1"
    private let accessKey = "spdfv.processing-queue.access.v1"
    private var access: [String: AutomationJobAccess]
    private let backgroundService = SMAppService.agent(plistName: "com.x3nllc.SPDFV.QueueRunner.plist")
    private var backgroundTimer: Timer?

    private var isRunningFromXcodeBuildFolder: Bool {
        Bundle.main.bundleURL.path.contains("/DerivedData/")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: queueKey),
           let decoded = try? JSONDecoder().decode(PDFRecipeJobQueue.self, from: data) {
            queue = decoded
        } else {
            queue = PDFRecipeJobQueue()
        }
        if let data = defaults.data(forKey: accessKey),
           let decoded = try? JSONDecoder().decode([String: AutomationJobAccess].self, from: data) {
            access = decoded
        } else {
            access = [:]
        }
        let interruptedCount = queue.jobs.count { $0.status == .running }
        _ = queue.prepareForRun()
        for job in queue.jobs { syncActivity(for: job) }
        if interruptedCount > 0 {
            notice = "Recovered \(interruptedCount) interrupted job\(interruptedCount == 1 ? "" : "s")"
            persistQueue()
        }
        refreshBackgroundStatus()
        startBackgroundTimer()
    }

    func hasAccess(to id: UUID) -> Bool {
        access[id.uuidString] != nil
    }

    func addJob() {
        guard let input = chooseFile(type: .pdf, message: "Choose the PDF to process") else { return }
        guard let recipe = chooseFile(type: .json, message: "Choose the recipe JSON") else { return }
        guard let outputDirectory = chooseDirectory(message: "Choose the folder for the processed PDF") else { return }
        addJob(input: input, recipe: recipe, outputDirectory: outputDirectory)
    }

    func relink(_ id: UUID) {
        guard queue.jobs.contains(where: { $0.id == id }) else { return }
        guard let input = chooseFile(type: .pdf, message: "Relink the input PDF") else { return }
        guard let recipe = chooseFile(type: .json, message: "Relink the recipe JSON") else { return }
        guard let outputDirectory = chooseDirectory(message: "Relink the output folder") else { return }
        do {
            access[id.uuidString] = try makeAccess(input: input, recipe: recipe, outputDirectory: outputDirectory)
            persistAccess()
            notice = "Access linked for \(input.lastPathComponent)"
        } catch {
            notice = "Could not retain file access · \(error.localizedDescription)"
        }
    }

    func retry(_ id: UUID) {
        guard queue.retry(id) else { return }
        if let job = queue.jobs.first(where: { $0.id == id }) { syncActivity(for: job) }
        persistQueue()
        notice = "Job returned to the queue"
    }

    func remove(_ id: UUID) {
        let removedJob = queue.jobs.first { $0.id == id }
        guard queue.remove(id) else { return }
        if let removedJob {
            ActivityCenterStore.shared.cancel(id, detail: "Removed \(URL(fileURLWithPath: removedJob.inputPath).lastPathComponent) from the processing queue")
        }
        access.removeValue(forKey: id.uuidString)
        persistQueue()
        persistAccess()
        notice = "Job removed"
    }

    func clearFinished() {
        let terminalIDs = queue.jobs
            .filter { $0.status == .passed || $0.status == .failed }
            .map { $0.id.uuidString }
        let count = queue.removeFinished()
        for id in terminalIDs { access.removeValue(forKey: id) }
        persistQueue()
        persistAccess()
        notice = count == 0 ? "No finished jobs to clear" : "Cleared \(count) finished job\(count == 1 ? "" : "s")"
    }

    func importQueue() {
        guard let url = chooseFile(type: .json, message: "Choose an SPDFV queue file") else { return }
        do {
            let imported = try JSONDecoder().decode(PDFRecipeJobQueue.self, from: Data(contentsOf: url))
            let count = try queue.merge(imported)
            for job in queue.jobs { syncActivity(for: job) }
            persistQueue()
            notice = count == 0 ? "Queue already contains every imported job" : "Imported \(count) job\(count == 1 ? "" : "s") · relink access to run"
        } catch {
            notice = "Queue import stopped · \(error.localizedDescription)"
        }
    }

    func exportQueue() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "spdfv-automation-queue.json"
        panel.message = "Export a queue for SPDFV or the command line"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(queue).write(to: url, options: .atomic)
            notice = "Exported \(queue.summary.total) job\(queue.summary.total == 1 ? "" : "s")"
        } catch {
            notice = "Queue export stopped · \(error.localizedDescription)"
        }
    }

    func revealOutput(for id: UUID) {
        guard let job = queue.jobs.first(where: { $0.id == id }),
              let record = access[id.uuidString],
              let directory = try? resolve(record.outputDirectoryBookmark) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory.appendingPathComponent(URL(fileURLWithPath: job.outputPath).lastPathComponent)])
    }

    func runPending() {
        guard !isRunning else { return }
        let pending = queue.prepareForRun()
        guard !pending.isEmpty else {
            notice = "Queue is caught up"
            return
        }
        persistQueue()
        if backgroundStatus == .on {
            syncBackgroundQueue()
            notice = "Queued for background processing"
            return
        }
        isRunning = true
        notice = "Running \(pending.count) job\(pending.count == 1 ? "" : "s")"
        Task {
            for id in pending { await run(id) }
            isRunning = false
            let summary = queue.summary
            notice = summary.failed == 0
                ? "Queue passed · \(summary.passed) finished"
                : "Queue stopped \(summary.failed) · passed \(summary.passed)"
        }
    }

    func setBackgroundProcessingEnabled(_ enabled: Bool) {
        if enabled && isRunningFromXcodeBuildFolder {
            backgroundStatus = .needsInstall
            notice = "Move SPDFV to Applications before turning on background processing"
            return
        }
        do {
            if enabled {
                syncBackgroundQueue(force: true)
                try backgroundService.register()
            } else {
                try backgroundService.unregister()
            }
            refreshBackgroundStatus()
            notice = enabled ? "Background processing enabled" : "Background processing disabled"
        } catch {
            refreshBackgroundStatus()
            let nsError = error as NSError
            notice = nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1
                ? "Move SPDFV to Applications, then turn on background processing"
                : "Background setting unchanged · \(error.localizedDescription)"
        }
    }

    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openBackgroundSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refreshBackgroundStatus() {
        let serviceStatus: BackgroundProcessingStatus = switch backgroundService.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .notRegistered: .off
        case .notFound: .off
        @unknown default: .unavailable
        }
        backgroundStatus = serviceStatus == .off && isRunningFromXcodeBuildFolder ? .needsInstall : serviceStatus
        if backgroundStatus == .on || backgroundStatus == .needsApproval {
            syncBackgroundResults()
        }
    }

    private func addJob(input: URL, recipe: URL, outputDirectory: URL) {
        do {
            _ = try PDFRecipeRunner.decode(Data(contentsOf: recipe))
            let stem = input.deletingPathExtension().lastPathComponent
            let output = outputDirectory.appendingPathComponent("\(stem)-processed.pdf")
            let id = try queue.enqueue(inputPath: input.path, recipePath: recipe.path, outputPath: output.path)
            access[id.uuidString] = try makeAccess(input: input, recipe: recipe, outputDirectory: outputDirectory)
            persistQueue()
            persistAccess()
            notice = "Queued \(input.lastPathComponent)"
            if let job = queue.jobs.first(where: { $0.id == id }) { syncActivity(for: job) }
        } catch {
            notice = "Job could not be queued · \((error as? PDFOperationError)?.description ?? error.localizedDescription)"
        }
    }

    private func run(_ id: UUID) async {
        guard let job = queue.jobs.first(where: { $0.id == id }) else { return }
        guard let record = access[id.uuidString] else {
            _ = queue.markRunning(id)
            _ = queue.markFailed(id, error: "File access is not linked. Relink the input, recipe, and output folder.")
            if let failed = queue.jobs.first(where: { $0.id == id }) { syncActivity(for: failed) }
            persistQueue()
            return
        }
        guard queue.markRunning(id) else { return }
        if let running = queue.jobs.first(where: { $0.id == id }) { syncActivity(for: running) }
        persistQueue()

        do {
            let input = try resolve(record.inputBookmark)
            let recipe = try resolve(record.recipeBookmark)
            let outputDirectory = try resolve(record.outputDirectoryBookmark)
            let inputAccess = input.startAccessingSecurityScopedResource()
            let recipeAccess = recipe.startAccessingSecurityScopedResource()
            let outputAccess = outputDirectory.startAccessingSecurityScopedResource()
            defer {
                if inputAccess { input.stopAccessingSecurityScopedResource() }
                if recipeAccess { recipe.stopAccessingSecurityScopedResource() }
                if outputAccess { outputDirectory.stopAccessingSecurityScopedResource() }
            }
            let output = outputDirectory.appendingPathComponent(URL(fileURLWithPath: job.outputPath).lastPathComponent)
            guard !FileManager.default.fileExists(atPath: output.path) else {
                throw PDFOperationError.invalidInput("Output already exists: \(output.lastPathComponent)")
            }
            let inputData = try Data(contentsOf: input)
            let recipeData = try Data(contentsOf: recipe)
            let result = try await Task.detached(priority: .userInitiated) {
                let decoded = try PDFRecipeRunner.decode(recipeData)
                return try PDFRecipeRunner.run(decoded, on: inputData)
            }.value
            try result.data.write(to: output, options: .atomic)
            _ = queue.markPassed(id, report: result.report)
            ActivityCenterStore.shared.finish(
                id,
                detail: "Exported \(result.report.outputPageCount) page\(result.report.outputPageCount == 1 ? "" : "s") after \(result.report.steps.count) verified step\(result.report.steps.count == 1 ? "" : "s")",
                outputURL: output
            )
        } catch {
            _ = queue.markFailed(id, error: (error as? PDFOperationError)?.description ?? error.localizedDescription)
            ActivityCenterStore.shared.fail(id, detail: (error as? PDFOperationError)?.description ?? error.localizedDescription)
        }
        persistQueue()
    }

    private func makeAccess(input: URL, recipe: URL, outputDirectory: URL) throws -> AutomationJobAccess {
        AutomationJobAccess(
            inputBookmark: try input.bookmarkData(options: .withSecurityScope),
            recipeBookmark: try recipe.bookmarkData(options: .withSecurityScope),
            outputDirectoryBookmark: try outputDirectory.bookmarkData(options: .withSecurityScope)
        )
    }

    private func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw PDFOperationError.invalidInput("Stored file access is stale; relink this job") }
        return url
    }

    private func chooseFile(type: UTType, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults.set(data, forKey: queueKey)
        syncBackgroundQueue()
    }

    private func persistAccess() {
        guard let data = try? JSONEncoder().encode(access) else { return }
        defaults.set(data, forKey: accessKey)
    }

    private func backgroundQueueURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let directory = support.appendingPathComponent("SPDFV", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("background-queue.json")
    }

    private func syncBackgroundQueue(force: Bool = false) {
        guard force || backgroundStatus == .on || backgroundStatus == .needsApproval,
              let url = backgroundQueueURL() else { return }
        syncBackgroundResults()
        let runnable = queue.jobs.filter { hasAccess(to: $0.id) }
        let backgroundQueue = PDFRecipeJobQueue(version: queue.version, jobs: runnable)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(backgroundQueue).write(to: url, options: .atomic)
    }

    private func syncBackgroundResults() {
        guard let url = backgroundQueueURL(),
              let data = try? Data(contentsOf: url),
              let backgroundQueue = try? JSONDecoder().decode(PDFRecipeJobQueue.self, from: data),
              ((try? queue.applyExecutionUpdates(from: backgroundQueue)) ?? 0) > 0 else { return }
        guard let encoded = try? JSONEncoder().encode(queue) else { return }
        defaults.set(encoded, forKey: queueKey)
        for job in queue.jobs { syncActivity(for: job) }
    }

    private func syncActivity(for job: PDFRecipeJob) {
        let status: SPDFVActivityStatus = switch job.status {
        case .queued: .queued
        case .running: .running
        case .passed: .succeeded
        case .failed: .failed
        }
        let inputName = URL(fileURLWithPath: job.inputPath).lastPathComponent
        let detail: String = switch job.status {
        case .queued: "Waiting to run with \(URL(fileURLWithPath: job.recipePath).deletingPathExtension().lastPathComponent)"
        case .running: "Applying the queued recipe"
        case .passed: "Finished on attempt \(job.attempts)"
        case .failed: job.error ?? "The queued recipe stopped"
        }
        ActivityCenterStore.shared.upsert(
            id: job.id,
            kind: .queue,
            title: "Process \(inputName)",
            detail: detail,
            documentName: inputName,
            status: status,
            outputURL: job.status == .passed ? URL(fileURLWithPath: job.outputPath) : nil
        )
    }

    private func startBackgroundTimer() {
        guard backgroundTimer == nil else { return }
        let reference = ProcessingQueueMainActorReference(value: self)
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                reference.value.refreshBackgroundStatus()
            }
        }
    }
}

enum BackgroundProcessingStatus: String {
    case off
    case on
    case needsApproval
    case needsInstall
    case unavailable

    var label: String {
        switch self {
        case .off: "BACKGROUND OFF"
        case .on: "BACKGROUND ON"
        case .needsApproval: "APPROVAL NEEDED"
        case .needsInstall: "MOVE TO APPLICATIONS"
        case .unavailable: "BACKGROUND UNAVAILABLE"
        }
    }
}
