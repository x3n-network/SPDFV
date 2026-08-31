import AppKit
import Combine
import Foundation

enum SPDFVActivityKind: String, Codable, CaseIterable {
    case ocr
    case redaction
    case recipe
    case batch
    case watch
    case queue

    var label: String {
        switch self {
        case .ocr: "OCR"
        case .redaction: "Redaction"
        case .recipe: "Recipe"
        case .batch: "Batch"
        case .watch: "Watch lane"
        case .queue: "Queue"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .ocr: .scanText
        case .redaction: .secureCopy
        case .recipe: .quickAction
        case .batch: .automation
        case .watch: .route
        case .queue: .queue
        }
    }
}

enum SPDFVActivityStatus: String, Codable, CaseIterable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled

    var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .succeeded: "Finished"
        case .failed: "Stopped"
        case .cancelled: "Cancelled"
        }
    }

    var isTerminal: Bool {
        self == .succeeded || self == .failed || self == .cancelled
    }
}

struct SPDFVActivityRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: SPDFVActivityKind
    let title: String
    let documentName: String?
    let startedAt: Date
    var updatedAt: Date
    var status: SPDFVActivityStatus
    var detail: String
    var outputPath: String?
}

@MainActor
final class ActivityCenterStore: ObservableObject {
    static let shared = ActivityCenterStore()

    @Published private(set) var records: [SPDFVActivityRecord]

    private let defaults: UserDefaults
    private let storageKey = "spdfv.activity-center.records.v1"
    private let recordLimit = 120

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SPDFVActivityRecord].self, from: data) {
            records = decoded.map { record in
                guard record.status == .running else { return record }
                var recovered = record
                recovered.status = .failed
                recovered.detail = "SPDFV closed before this activity reported completion."
                recovered.updatedAt = Date()
                return recovered
            }
        } else {
            records = []
        }
        persist()
    }

    @discardableResult
    func begin(
        kind: SPDFVActivityKind,
        title: String,
        detail: String,
        documentName: String? = nil,
        id: UUID = UUID(),
        status: SPDFVActivityStatus = .running
    ) -> UUID {
        upsert(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            documentName: documentName,
            status: status
        )
        return id
    }

    func upsert(
        id: UUID,
        kind: SPDFVActivityKind,
        title: String,
        detail: String,
        documentName: String? = nil,
        status: SPDFVActivityStatus,
        outputURL: URL? = nil
    ) {
        let now = Date()
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index].status = status
            records[index].detail = detail
            records[index].updatedAt = now
            if let outputURL { records[index].outputPath = outputURL.path }
        } else {
            records.append(SPDFVActivityRecord(
                id: id,
                kind: kind,
                title: title,
                documentName: documentName,
                startedAt: now,
                updatedAt: now,
                status: status,
                detail: detail,
                outputPath: outputURL?.path
            ))
        }
        trimAndPersist()
    }

    func finish(_ id: UUID, detail: String, outputURL: URL? = nil) {
        update(id, status: .succeeded, detail: detail, outputURL: outputURL)
    }

    func fail(_ id: UUID, detail: String) {
        update(id, status: .failed, detail: detail)
    }

    func cancel(_ id: UUID, detail: String) {
        update(id, status: .cancelled, detail: detail)
    }

    func clearFinished() {
        records.removeAll { $0.status.isTerminal }
        persist()
    }

    func revealOutput(for id: UUID) {
        guard let path = records.first(where: { $0.id == id })?.outputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func update(_ id: UUID, status: SPDFVActivityStatus, detail: String, outputURL: URL? = nil) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = status
        records[index].detail = detail
        records[index].updatedAt = Date()
        if let outputURL { records[index].outputPath = outputURL.path }
        trimAndPersist()
    }

    private func trimAndPersist() {
        if records.count > recordLimit {
            records = Array(records.sorted { $0.updatedAt > $1.updatedAt }.prefix(recordLimit))
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
