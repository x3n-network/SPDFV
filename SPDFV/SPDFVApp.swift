//
//  SPDFVApp.swift
//  SPDFV
//
//  Created by Joseph Spears on 8/29/26.
//

import SwiftUI

@main
struct SPDFVApp: App {
    @NSApplicationDelegateAdaptor(SPDFVApplicationDelegate.self) private var applicationDelegate
    private let updaterController = SPDFVUpdaterController()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            SPDFVCommands()
        }

        Window("Activity Center", id: "processing-queue") {
            ProcessingQueueView()
                .preferredColorScheme(nil)
        }
        .defaultSize(width: 1040, height: 700)
        .windowStyle(.titleBar)
    }
}
