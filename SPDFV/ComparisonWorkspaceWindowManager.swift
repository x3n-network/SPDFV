import AppKit
import SwiftUI

@MainActor
final class ComparisonWorkspaceWindowManager {
    static let shared = ComparisonWorkspaceWindowManager()

    private var windowControllers: [ObjectIdentifier: NSWindowController] = [:]
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private init() {}

    func open(for session: DocumentSession) {
        let sessionID = ObjectIdentifier(session)
        if let window = windowControllers[sessionID]?.window {
            window.title = title(for: session)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = title(for: session)
        window.toolbarStyle = .unified
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 520)
        window.setFrameAutosaveName("SPDFVComparisonWorkspace")
        window.contentViewController = NSHostingController(rootView: ComparisonWorkspace(session: session))
        window.center()

        let controller = NSWindowController(window: window)
        windowControllers[sessionID] = controller
        closeObservers[sessionID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.release(sessionID) }
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(for session: DocumentSession) {
        windowControllers[ObjectIdentifier(session)]?.close()
    }

    private func title(for session: DocumentSession) -> String {
        "Compare — \(session.displayName)"
    }

    private func release(_ sessionID: ObjectIdentifier) {
        if let observer = closeObservers.removeValue(forKey: sessionID) {
            NotificationCenter.default.removeObserver(observer)
        }
        windowControllers.removeValue(forKey: sessionID)
    }
}
