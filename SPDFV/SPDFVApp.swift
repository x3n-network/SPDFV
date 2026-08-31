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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1080, height: 760)
        .commands {
            SPDFVCommands()
        }

        Window("Processing Queue", id: "processing-queue") {
            ProcessingQueueView()
                .preferredColorScheme(nil)
        }
        .defaultSize(width: 1040, height: 700)
        .windowStyle(.titleBar)
    }
}
