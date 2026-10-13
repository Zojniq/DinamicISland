import SwiftUI
import AppKit

/// Simple, elegant scratchpad TextEditor that automatically saves to UserDefaults.
struct ScratchpadWidgetView: View {
    @ObservedObject var service: ScratchpadService
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header bar
            HStack(spacing: 4) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 9, weight: .bold))
                Text("SCRATCHPAD")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.3)

                Spacer(minLength: 4)

                if !service.text.isEmpty {
                    // Copy action
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(service.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(.white.opacity(0.6))
                    .help("Copy to clipboard")

                    // Clear action
                    Button {
                        service.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(.white.opacity(0.45))
                    .help("Clear scratchpad")
                }
            }
            .foregroundStyle(Color(red: 0.95, green: 0.8, blue: 0.4))

            // Editor with placeholder
            ZStack(alignment: .topLeading) {
                if service.text.isEmpty {
                    Text("Jot down quick thoughts, links, or notes…")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $service.text)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandCard()
        .onTapGesture {
            isFocused = true
        }
    }
}
