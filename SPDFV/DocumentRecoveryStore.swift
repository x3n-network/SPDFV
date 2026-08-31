import Foundation
import PDFKit

@MainActor
final class DocumentRecoveryStore {
    static let shared = DocumentRecoveryStore()

    private let defaults = UserDefaults.standard
    private let cleanExitKey = "spdfv.recovery.clean-exit"
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func beginLaunch() -> [URL] {
        let previousExitWasClean = defaults.object(forKey: cleanExitKey) == nil
            || defaults.bool(forKey: cleanExitKey)
        defaults.set(false, forKey: cleanExitKey)
        guard !previousExitWasClean else { return [] }
        return recoveryFiles()
    }

    func markCleanExit() {
        defaults.set(true, forKey: cleanExitKey)
    }

    func scheduleSnapshot(for session: DocumentSession) {
        let id = session.recoveryID
        pendingWrites[id]?.cancel()
        pendingWrites[id] = Task { @MainActor [weak self, weak session] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled,
                  let self,
                  let session,
                  session.isDirty,
                  let data = session.document?.dataRepresentation(),
                  let url = self.recoveryURL(for: session)
            else { return }

            do {
                try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: url, options: .atomic)
                }.value
            } catch {
                // Recovery is best-effort and must never interrupt document editing.
            }
            self.pendingWrites[id] = nil
        }
    }

    func removeSnapshot(for session: DocumentSession) {
        pendingWrites[session.recoveryID]?.cancel()
        pendingWrites[session.recoveryID] = nil
        guard let directory = recoveryDirectory() else { return }
        let suffix = "-\(session.recoveryID.uuidString).pdf"
        for url in (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [] where url.lastPathComponent.hasSuffix(suffix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func discardAllSnapshots() {
        pendingWrites.values.forEach { $0.cancel() }
        pendingWrites.removeAll()
        guard let directory = recoveryDirectory() else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func recoveryFiles() -> [URL] {
        guard let directory = recoveryDirectory() else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension.lowercased() == "pdf" }
        .sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs < rhs
        }
    }

    private func recoveryURL(for session: DocumentSession) -> URL? {
        guard let directory = recoveryDirectory() else { return nil }
        let base = session.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("\(base)-\(session.recoveryID.uuidString).pdf")
    }

    private func recoveryDirectory() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support
            .appendingPathComponent("SPDFV", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }
}
