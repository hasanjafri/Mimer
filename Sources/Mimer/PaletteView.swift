import SwiftUI

/// Command palette: search + result list over the persistent clipboard history.
/// Keyboard: ↑↓ move · ⏎ paste · ⌘1–9 quick-paste · ⌘D favorite · ⌫ delete · esc.
struct PaletteView: View {
    let onPaste: (String) -> Void
    let onClose: () -> Void

    @ObservedObject private var store = ClipStore.shared
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool
    @State private var needsPasteGrant = !Paster.canPostEvents

    private var results: [ClipItem] {
        let all = store.items
        return query.isEmpty ? all : all.filter { fuzzyMatch(query, $0.text) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if needsPasteGrant {
                pasteGrantBanner
                Divider()
            }
            TextField("Search your clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(16)
                .focused($searchFocused)
                .onSubmit(pasteSelected)

            Divider()

            if results.isEmpty {
                emptyState
            } else {
                resultList
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            selection = 0
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { selection = 0 }
        .onChange(of: results.count) { if selection >= results.count { selection = max(0, results.count - 1) } }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { pasteSelected(); return .handled }
        .onKeyPress(.delete) { deleteSelected(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.characters == "d" { toggleFavoriteSelected(); return .handled }
            if let n = press.characters.first?.wholeNumberValue, (1...9).contains(n) {
                pasteVisible(at: n - 1)
                return .handled
            }
            return .ignored
        }
    }

    private var resultList: some View {
        let showSections = results.contains(where: \.isFavorite) && results.contains(where: { !$0.isFavorite })
        return ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    if showSections && index == 0 {
                        sectionHeader("Favorites")
                    }
                    if showSections && index > 0 && results[index - 1].isFavorite && !item.isFavorite {
                        sectionHeader("Recents")
                    }
                    resultRow(index: index, item: item)
                }
            }
            .padding(8)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }

    private func resultRow(index: Int, item: ClipItem) -> some View {
        HStack(spacing: 8) {
            KindIcon(kind: item.kind, text: item.text)
            Text(item.text).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if item.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            index == selection ? Color.accentColor.opacity(0.25) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = index; pasteSelected() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.secondary)
            Text(store.items.isEmpty ? "No clips yet" : "No matches").font(.headline)
            Text(store.items.isEmpty ? "Copy some text and it appears here." : "Try a different search.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var pasteGrantBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill").foregroundStyle(.orange)
            Text("Enable auto-paste so ⏎ pastes into the app you were in").font(.caption)
            Spacer(minLength: 0)
            Button("Enable") {
                Paster.requestPostEventAccess()
                needsPasteGrant = !Paster.canPostEvents
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var footer: some View {
        Text("↑↓ move · ⏎ paste · ⌘1–9 quick · ⌘D favorite · ⌫ delete · esc close")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func pasteSelected() {
        guard results.indices.contains(selection) else { return }
        onPaste(results[selection].text)
    }

    private func pasteVisible(at index: Int) {
        guard results.indices.contains(index) else { return }
        onPaste(results[index].text)
    }

    private func toggleFavoriteSelected() {
        guard results.indices.contains(selection) else { return }
        store.toggleFavorite(results[selection].id)
    }

    private func deleteSelected() {
        guard results.indices.contains(selection) else { return }
        store.delete(results[selection].id)
    }
}
