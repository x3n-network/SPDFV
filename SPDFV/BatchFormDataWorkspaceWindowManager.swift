import AppKit
import SwiftUI

@MainActor
final class BatchFormDataWorkspaceWindowManager {
    static let shared = BatchFormDataWorkspaceWindowManager()

    private var windowControllers: [ObjectIdentifier: NSWindowController] = [:]
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private init() {}

    func open(for session: DocumentSession) {
        let sessionID = ObjectIdentifier(session)
        if let window = windowControllers[sessionID]?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Batch Form Data — \(session.displayName)"
        window.toolbarStyle = .unified
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 480)
        window.setFrameAutosaveName("SPDFVBatchFormDataWorkspace")
        window.contentViewController = NSHostingController(rootView: BatchFormDataWorkspace(session: session))
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

    private func release(_ sessionID: ObjectIdentifier) {
        if let observer = closeObservers.removeValue(forKey: sessionID) {
            NotificationCenter.default.removeObserver(observer)
        }
        windowControllers.removeValue(forKey: sessionID)
    }
}
