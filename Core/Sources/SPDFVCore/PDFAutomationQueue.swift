import Foundation

public enum PDFRecipeJobStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case queued
    case running
    case passed
    case failed
}

public struct PDFRecipeJob: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let inputPath: String
    public let recipePath: String
    public let outputPath: String
    public var status: PDFRecipeJobStatus
    public var attempts: Int
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var report: PDFRecipeReport?
    public var error: String?

    public init(
        id: UUID = UUID(),
        inputPath: String,
        recipePath: String,
        outputPath: String,
        status: PDFRecipeJobStatus = .queued,
        attempts: Int = 0,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        report: PDFRecipeReport? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.inputPath = inputPath
        self.recipePath = recipePath
        self.outputPath = outputPath
        self.status = status
        self.attempts = attempts
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.report = report
        self.error = error
    }
}

public struct PDFRecipeJobQueueSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let queued: Int
    public let running: Int
    public let passed: Int
    public let failed: Int

    public init(jobs: [PDFRecipeJob]) {
        total = jobs.count
        queued = jobs.count { $0.status == .queued }
        running = jobs.count { $0.status == .running }
        passed = jobs.count { $0.status == .passed }
        failed = jobs.count { $0.status == .failed }
    }
}

public struct PDFRecipeJobQueue: Codable, Equatable, Sendable {
    public let version: Int
    public private(set) var jobs: [PDFRecipeJob]

    public init(version: Int = 1, jobs: [PDFRecipeJob] = []) {
        self.version = version
        self.jobs = jobs
    }

    public var summary: PDFRecipeJobQueueSummary {
        PDFRecipeJobQueueSummary(jobs: jobs)
    }

    @discardableResult
    public mutating func enqueue(
        inputPath: String,
        recipePath: String,
        outputPath: String,
        id: UUID = UUID(),
        at date: Date = Date()
    ) throws -> UUID {
        let paths = [inputPath, recipePath, outputPath].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard paths.allSatisfy({ !$0.isEmpty }) else {
            throw PDFOperationError.invalidInput("Queued jobs require input, recipe, and output paths")
        }
        guard !jobs.contains(where: { $0.id == id }) else {
            throw PDFOperationError.invalidInput("A queued job already uses identifier \(id.uuidString)")
        }
        jobs.append(PDFRecipeJob(
            id: id,
            inputPath: paths[0],
            recipePath: paths[1],
            outputPath: paths[2],
            createdAt: date
        ))
        return id
    }

    /// Recovers jobs left running by an interrupted process and returns all work ready to claim.
    @discardableResult
    public mutating func prepareForRun() -> [UUID] {
        for index in jobs.indices where jobs[index].status == .running {
            jobs[index].status = .queued
            jobs[index].startedAt = nil
            jobs[index].completedAt = nil
            jobs[index].report = nil
            jobs[index].error = "Recovered after an interrupted run"
        }
        return jobs.filter { $0.status == .queued }.map(\.id)
    }

    @discardableResult
    public mutating func markRunning(_ id: UUID, at date: Date = Date()) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.status == .queued }) else { return false }
        jobs[index].status = .running
        jobs[index].attempts += 1
        jobs[index].startedAt = date
        jobs[index].completedAt = nil
        jobs[index].report = nil
        jobs[index].error = nil
        return true
    }

    @discardableResult
    public mutating func markPassed(_ id: UUID, report: PDFRecipeReport, at date: Date = Date()) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.status == .running }) else { return false }
        jobs[index].status = .passed
        jobs[index].completedAt = date
        jobs[index].report = report
        jobs[index].error = nil
        return true
    }

    @discardableResult
    public mutating func markFailed(_ id: UUID, error: String, at date: Date = Date()) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.status == .running }) else { return false }
        jobs[index].status = .failed
        jobs[index].completedAt = date
        jobs[index].report = nil
        jobs[index].error = error
        return true
    }

    @discardableResult
    public mutating func retry(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.status == .failed }) else { return false }
        jobs[index].status = .queued
        jobs[index].startedAt = nil
        jobs[index].completedAt = nil
        jobs[index].report = nil
        jobs[index].error = nil
        return true
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.status != .running }) else { return false }
        jobs.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func removeFinished() -> Int {
        let previousCount = jobs.count
        jobs.removeAll { $0.status == .passed || $0.status == .failed }
        return previousCount - jobs.count
    }

    /// Adds jobs not already present by identifier while preserving this queue's state.
    @discardableResult
    public mutating func merge(_ other: PDFRecipeJobQueue) throws -> Int {
        guard other.version == version else {
            throw PDFOperationError.invalidInput("Queue version \(other.version) is not compatible with version \(version)")
        }
        let existingIDs = Set(jobs.map(\.id))
        let additions = other.jobs.filter { !existingIDs.contains($0.id) }
        jobs.append(contentsOf: additions)
        return additions.count
    }

    /// Applies newer execution state for existing jobs without importing unknown jobs.
    @discardableResult
    public mutating func applyExecutionUpdates(from other: PDFRecipeJobQueue) throws -> Int {
        guard other.version == version else {
            throw PDFOperationError.invalidInput("Queue version \(other.version) is not compatible with version \(version)")
        }
        var count = 0
        for incoming in other.jobs {
            guard let index = jobs.firstIndex(where: { $0.id == incoming.id }) else { continue }
            let current = jobs[index]
            let hasNewAttempt = incoming.attempts > current.attempts
            let completedCurrentAttempt = incoming.attempts == current.attempts
                && (incoming.status == .passed || incoming.status == .failed)
                && current.status == .running
            guard hasNewAttempt || completedCurrentAttempt else { continue }
            jobs[index] = incoming
            count += 1
        }
        return count
    }
}
