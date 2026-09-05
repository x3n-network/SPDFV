import SwiftUI

@main
struct SPDFVReaderApp: App {
    @NSApplicationDelegateAdaptor(SPDFVApplicationDelegate.self) private var applicationDelegate

    init() {
        DocumentWindowManager.shared.configure(edition: .reader)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(edition: .reader)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1080, height: 760)
        .commands {
            SPDFVReaderCommands()
        }
    }
}
