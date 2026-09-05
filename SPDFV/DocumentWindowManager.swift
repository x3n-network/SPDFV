import AppKit
import SwiftUI

@MainActor
final class DocumentWindowManager {
    static let shared = DocumentWindowManager()

    private final class WeakSession {
        weak var value: DocumentSession?
        let edition: SPDFVEdition

        init(_ value: DocumentSession, edition: SPDFVEdition) {
            self.value = value
            self.edition = edition
        }
    }

    private var sessions: [ObjectIdentifier: WeakSession] = [:]
    private var windowControllers: [ObjectIdentifier: NSWindowController] = [:]
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var defaultEdition = SPDFVEdition.direct

    private init() {}

    func configure(edition: SPDFVEdition) {
        defaultEdition = edition
    }

    func register(_ session: DocumentSession, edition: SPDFVEdition) {
        sessions[ObjectIdentifier(session)] = WeakSession(session, edition: edition)
        purgeReleasedSessions()
    }

    func unregister(_ session: DocumentSession) {
        sessions[ObjectIdentifier(session)] = nil
    }

    func open(_ urls: [URL]) {
        let pdfURLs = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { $0.standardizedFileURL }

        guard !pdfURLs.isEmpty else { return }
        purgeReleasedSessions()

        var remaining = pdfURLs
        if let emptySession = sessions.values.compactMap(\.value).first(where: { $0.document == nil }),
           let first = remaining.first {
            emptySession.open(first)
            remaining.removeFirst()
        }

        for url in remaining {
            if let existing = existingWindow(for: url) {
                existing.makeKeyAndOrderFront(nil)
            } else {
                makeWindow(for: url, edition: defaultEdition)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func newDocument(edition: SPDFVEdition? = nil) {
        makeWindow(for: nil, edition: edition ?? defaultEdition)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func existingWindow(for url: URL) -> NSWindow? {
        sessions.values
            .compactMap(\.value)
            .first(where: { $0.fileURL?.standardizedFileURL == url })?
            .window
    }

    private func makeWindow(for url: URL?, edition: SPDFVEdition) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url?.deletingPathExtension().lastPathComponent ?? "Untitled"
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: ContentView(
                initialURL: url,
                createsBlankDocument: url == nil,
                edition: edition
            )
        )
        window.center()

        let controller = NSWindowController(window: window)
        let identifier = ObjectIdentifier(window)
        windowControllers[identifier] = controller
        closeObservers[identifier] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.releaseWindow(identifier)
            }
        }
        controller.showWindow(nil)
    }

    private func releaseWindow(_ identifier: ObjectIdentifier) {
        if let observer = closeObservers.removeValue(forKey: identifier) {
            NotificationCenter.default.removeObserver(observer)
        }
        windowControllers.removeValue(forKey: identifier)
    }

    private func purgeReleasedSessions() {
        sessions = sessions.filter { $0.value.value != nil }
    }
}

private extension DocumentSession {
    var window: NSWindow? {
        NSApp.windows.first { window in
            window.title == displayName || window.representedURL?.standardizedFileURL == fileURL?.standardizedFileURL
        }
    }
}
