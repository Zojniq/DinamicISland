import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = IslandViewModel()
    private var islandController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory` = no Dock icon / no app menu, but we may still own key windows
        // (needed for Settings and the Quick Notes text field). LSUIElement in Info.plist
        // does the same for the bundled app; this line covers `swift run` too.
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchWindowController(viewModel: viewModel)
        controller.showIsland()
        islandController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Closing Settings must never kill the island.
    }

    /// Opens the SwiftUI `Settings` scene from AppKit / MenuBarExtra.
    ///
    /// WORKAROUND: `SettingsLink` is macOS 14+. On macOS 13 the Settings scene is reachable
    /// only through the private-but-stable `showSettingsWindow:` responder action.
    /// An accessory app must also be activated first, or the window opens behind others.
    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
