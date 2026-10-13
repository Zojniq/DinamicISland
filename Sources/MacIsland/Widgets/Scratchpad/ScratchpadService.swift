import Foundation
import Combine

/// Manages quick scratchpad notes, automatically persisting changes to UserDefaults.
@MainActor
final class ScratchpadService: ObservableObject {

    private static let storageKey = "com.macisland.scratchpad.text"

    @Published var text: String {
        didSet {
            debouncedSave()
        }
    }

    private var saveWorkItem: DispatchWorkItem?

    init() {
        self.text = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
    }

    func clear() {
        text = ""
        saveImmediately()
    }

    private func debouncedSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveImmediately()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func saveImmediately() {
        UserDefaults.standard.set(text, forKey: Self.storageKey)
    }
}
