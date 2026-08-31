import AppKit
import SwiftUI

@MainActor
final class CloseProtectionCenter {
    static let shared = CloseProtectionCenter()

    private final class WeakSession {
        weak var value: DocumentSession?
        init(_ value: DocumentSession) { self.value = value }
    }

    private var sessions: [ObjectIdentifier: WeakSession] = [:]

    func register(_ session: DocumentSession) {
        sessions[ObjectIdentifier(session)] = WeakSession(session)
        purgeReleasedSessions()
    }

    func unregister(_ session: DocumentSession) {
        sessions[ObjectIdentifier(session)] = nil
    }

    func shouldClose(_ session: DocumentSession) -> Bool {
        guard session.isDirty else { return true }
        return resolveUnsavedChanges(for: session)
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        purgeReleasedSessions()
        for session in sessions.values.compactMap(\.value) where session.isDirty {
            guard resolveUnsavedChanges(for: session) else {
                return .terminateCancel
            }
        }
        return .terminateNow
    }

    private func resolveUnsavedChanges(for session: DocumentSession) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes to \(session.displayName)?"
        alert.informativeText = "Your PDF annotations have not been saved."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return session.save()
        case .alertSecondButtonReturn:
            session.discardUnsavedChangesForClosing()
            return true
        default:
            return false
        }
    }

    private func purgeReleasedSessions() {
        sessions = sessions.filter { $0.value.value != nil }
    }
}

final class SPDFVApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let recoveries = MainActor.assumeIsolated {
            DocumentRecoveryStore.shared.beginLaunch()
        }
        guard !recoveries.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unsaved work was recovered"
        alert.informativeText = "SPDFV found \(recoveries.count) recovery cop\(recoveries.count == 1 ? "y" : "ies") from the previous session. Open them now?"
        alert.addButton(withTitle: "Open Recovery Copies")
        alert.addButton(withTitle: "Discard")
        if alert.runModal() == .alertFirstButtonReturn {
            MainActor.assumeIsolated {
                DocumentWindowManager.shared.open(recoveries)
            }
        } else {
            MainActor.assumeIsolated {
                DocumentRecoveryStore.shared.discardAllSnapshots()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            DocumentWindowManager.shared.open(urls)
            application.reply(toOpenOrPrint: .success)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let reply = CloseProtectionCenter.shared.applicationShouldTerminate()
            if reply == .terminateNow {
                DocumentRecoveryStore.shared.markCleanExit()
            }
            return reply
        }
    }
}

struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var session: DocumentSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        context.coordinator.session = session
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var session: DocumentSession
        private weak var window: NSWindow?
        private weak var originalDelegate: NSWindowDelegate?

        init(session: DocumentSession) {
            self.session = session
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            window.representedURL = session.fileURL
            window.title = session.displayName
            window.isDocumentEdited = session.isDirty
            guard self.window !== window else { return }
            detach()
            self.window = window
            originalDelegate = window.delegate
            window.delegate = self
        }

        func detach() {
            if let window, window.delegate === self {
                window.delegate = originalDelegate
            }
            window = nil
            originalDelegate = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard CloseProtectionCenter.shared.shouldClose(session) else { return false }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || originalDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if originalDelegate?.responds(to: aSelector) == true {
                return originalDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}

final class WindowProbeView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
