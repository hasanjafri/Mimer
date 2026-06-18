import SwiftUI

/// Menu-bar dropdown: shows recent clipboard history (newest first). Clicking a
/// clip recalls it (puts it back on the clipboard so you can ⌘V it). The full
/// searchable, auto-pasting surface is the ⇧⌘V command palette.
struct MenuBarView: View {
    @ObservedObject private var monitor = ClipboardMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                Text("Mimer").font(.headline)
                Spacer()
                if !monitor.clips.isEmpty {
                    Text("\(monitor.clips.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if monitor.clips.isEmpty {
                Text("No clips yet — copy some text and it shows up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(monitor.clips.prefix(12).enumerated()), id: \.offset) { index, clip in
                            Button {
                                Paster.copyToPasteboard(clip)   // recall onto the clipboard
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 16, alignment: .trailing)
                                    Text(clip).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }

            Divider()

            VStack(spacing: 2) {
                Button { PaletteController.shared.toggle() } label: {
                    Label("Open Mimer  ⇧⌘V", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit Mimer", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}
