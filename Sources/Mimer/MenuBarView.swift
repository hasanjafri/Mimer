import SwiftUI

/// Menu-bar dropdown: recent clipboard history (newest first), height driven by
/// the "show N at once" preference (capped at screen height), then scrolls.
/// Clicking a clip recalls it onto the clipboard.
struct MenuBarView: View {
    @ObservedObject private var store = ClipStore.shared
    @ObservedObject private var prefs = Preferences.shared

    private let rowHeight: CGFloat = 30

    private var listHeight: CGFloat {
        let screenCap = (NSScreen.main?.visibleFrame.height ?? 800) - 160
        let visibleCap = min(CGFloat(prefs.visibleRows) * rowHeight, screenCap)
        let contentHeight = CGFloat(store.items.count) * rowHeight
        return max(rowHeight, min(contentHeight, visibleCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.items.isEmpty {
                Text("No clips yet — copy some text and it shows up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                            row(index: index, text: item.text)
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
            if !store.items.isEmpty {
                Text("\(store.items.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func row(index: Int, text: String) -> some View {
        Button {
            Paster.copyToPasteboard(text)
        } label: {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .trailing)
                Text(text).lineLimit(1).truncationMode(.middle)
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
            Button { SettingsWindowController.shared.show() } label: {
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
