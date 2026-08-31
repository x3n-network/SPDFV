import AppKit
import SwiftUI

/// Owns one Recipe Press utility window per document session.
///
/// Recipe authoring is substantial, persistent work, so it should not disappear
/// like a transient toolbar popover when the user returns to the document.
@MainActor
final class RecipeWorkspaceWindowManager {
    static let shared = RecipeWorkspaceWindowManager()

    private var windowControllers: [ObjectIdentifier: NSWindowController] = [:]
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private init() {}

    func open(for session: DocumentSession) {
        let sessionID = ObjectIdentifier(session)
        if let window = windowControllers[sessionID]?.window {
            window.title = windowTitle(for: session)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle(for: session)
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 390, height: 430)
        window.setFrameAutosaveName("SPDFVRecipeWorkspace")

        let isPresented = Binding(
            get: { [weak window] in window?.isVisible == true },
            set: { [weak window] newValue in
                if !newValue { window?.close() }
            }
        )
        window.contentViewController = NSHostingController(
            rootView: RecipePanel(session: session, isPresented: isPresented)
        )
        window.center()

        let controller = NSWindowController(window: window)
        windowControllers[sessionID] = controller
        closeObservers[sessionID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.release(sessionID)
            }
        }

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(for session: DocumentSession) {
        windowControllers[ObjectIdentifier(session)]?.close()
    }

    private func windowTitle(for session: DocumentSession) -> String {
        "Recipe Press — \(session.displayName)"
    }

    private func release(_ sessionID: ObjectIdentifier) {
        if let observer = closeObservers.removeValue(forKey: sessionID) {
            NotificationCenter.default.removeObserver(observer)
        }
        windowControllers.removeValue(forKey: sessionID)
    }
}
