import AppIntents

struct RunSPDFVWatchLaneIntent: AppIntent {
    static let title: LocalizedStringResource = "Run SPDFV Watch Lane"
    static let description = IntentDescription("Processes new PDFs in the watched folder using its selected recipe.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = RecipeLibraryStore.shared
        guard store.watchConfiguration != nil else {
            return .result(dialog: "No watch lane is configured. Open SPDFV and connect input and output folders first.")
        }
        store.runWatchNow()
        return .result(dialog: IntentDialog(stringLiteral: store.watchStatus))
    }
}

struct ArmSPDFVWatchLaneIntent: AppIntent {
    static let title: LocalizedStringResource = "Arm SPDFV Watch Lane"
    static let description = IntentDescription("Resumes automatic processing for the configured watched folder.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = RecipeLibraryStore.shared
        guard store.watchConfiguration != nil else {
            return .result(dialog: "No watch lane is configured. Open SPDFV and connect folders first.")
        }
        store.setWatchArmed(true)
        return .result(dialog: "SPDFV watch lane armed.")
    }
}

struct PauseSPDFVWatchLaneIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause SPDFV Watch Lane"
    static let description = IntentDescription("Pauses automatic processing without disconnecting watched folders.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = RecipeLibraryStore.shared
        guard store.watchConfiguration != nil else {
            return .result(dialog: "No SPDFV watch lane is configured.")
        }
        store.setWatchArmed(false)
        return .result(dialog: "SPDFV watch lane paused.")
    }
}

struct SPDFVShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunSPDFVWatchLaneIntent(),
            phrases: [
                "Run the \(.applicationName) watch lane",
                "Process watched PDFs with \(.applicationName)"
            ],
            shortTitle: "Run Watch Lane",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: ArmSPDFVWatchLaneIntent(),
            phrases: ["Arm the \(.applicationName) watch lane"],
            shortTitle: "Arm Watch Lane",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseSPDFVWatchLaneIntent(),
            phrases: ["Pause the \(.applicationName) watch lane"],
            shortTitle: "Pause Watch Lane",
            systemImageName: "pause.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
