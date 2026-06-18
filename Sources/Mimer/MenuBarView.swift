import SwiftUI

/// Menu-bar dropdown: shows recent clipboard history (newest first). Its height
/// grows with the number of clips up to the "show N at once" preference (capped
/// at the screen height), then scrolls. Clicking a clip recalls it onto the
/// clipboard. The full searchable, auto-pasting surface is the ⇧⌘V palette.
struct MenuBarView: View {
    @ObservedObject private var monitor = ClipboardMonitor.shared
    @ObservedObject private var prefs = Preferences.shared

    private let rowHeight: CGFloat = 30

    /// Height of the scrollable list: content height, capped at the user's
    /// "show N at once" rows, itself capped at the available screen height.
    private var listHeight: CGFloat {
        let screenCap = (NSScreen.main?.visibleFrame.height ?? 800) - 160
        let visibleCap = min(CGFloat(prefs.visibleRows) * rowHeight, screenCap)
        let contentHeight = CGFloat(monitor.clips.count) * rowHeight
        return max(rowHeight, min(contentHeight, visibleCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if monitor.clips.isEmpty {
                Text("No clips yet — copy some text and it shows up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(monitor.clips.enumerated()), id: \.offset) { index, clip in
                            row(index: index, clip: clip)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: listHeight)
            }

            Divider()
            actions
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
            Text("Mimer").font(.headline)
            Spacer()
            if !monitor.clips.isEmpty {
                Text("\(monitor.clips.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func row(index: Int, clip: String) -> some View {
        Button {
            Paster.copyToPasteboard(clip)   // recall onto the clipboard
        } label: {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .trailing)
                Text(clip).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actions: some View {
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
}
