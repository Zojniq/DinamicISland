import SwiftUI

/// SwiftUI entry point.
///
/// We deliberately do NOT use a `WindowGroup`: the island is an AppKit `NSPanel` owned by
/// `AppDelegate`, because SwiftUI scenes cannot (on macOS 13) produce a borderless,
/// non-activating, menu-bar-level window. SwiftUI only owns the status item and Settings.
@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MacIsland", systemImage: "capsule.portrait.fill") {
            Button("Settings…") { AppDelegate.openSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit MacIsland") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            // Full settings UI arrives in Phase 5.
            Text("MacIsland Settings")
                .frame(width: 420, height: 240)
        }
    }
}
