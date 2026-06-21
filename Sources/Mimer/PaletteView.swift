import SwiftUI

/// Command palette: search + result list over the persistent clipboard history.
/// Keyboard: ↑↓ move · ⏎ paste · ⌘1–9 quick · ⌘K transform · ⌘O act · ⌘D favorite · ⌫ delete · esc.
/// ⌘O is the context-aware action for the selected clip (reveal a secret · open a link ·
/// reveal a file in Finder) — see `ClipAction`.
/// ⌘K opens transform mode for the selected clip (UPPER/lower, base64, JSON, …),
/// with a live preview of each result. The search field stays mounted across modes
/// so keyboard focus never drops.
struct PaletteView: View {
    let onPaste: (String) -> Void
    let onClose: () -> Void
    var initialTransformIndex: Int? = nil   // debug hook: open straight into transform mode

    @ObservedObject private var store = ClipStore.shared
    @ObservedObject private var prefs = Preferences.shared
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool
    @State private var needsPasteGrant = !Paster.canPostEvents

    // Transform mode (⌘K): when set, the list shows transforms for this clip.
    @State private var transformTarget: ClipItem?
    @State private var transformSelection = 0

    // Secrets temporarily revealed via ⌘O. The panel is recreated on each open, so this
    // resets to empty every time — revealed secrets re-mask once the palette closes.
    @State private var revealedSecrets: Set<UUID> = []

    private var results: [ClipItem] {
        let snips = query.isEmpty ? store.snippets : store.snippets.filter { fuzzyMatch(query, $0.text) }
        let hist = query.isEmpty ? store.items : store.items.filter { fuzzyMatch(query, $0.text) }
        return snips + hist
    }

    private var transforms: [ClipTransform] {
        guard let target = transformTarget else { return [] }
        let applicable = ClipTransform.applicable(to: target.text)
        return query.isEmpty ? applicable : applicable.filter { fuzzyMatch(query, $0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if needsPasteGrant {
                pasteGrantBanner
                Divider()
            }

            TextField(transformTarget == nil ? "Search your clipboard…" : "Filter transforms…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(16)
                .focused($searchFocused)
                .onSubmit(commitSelection)

            if let target = transformTarget {
                transformBar(target)
            }

            Divider()

            if transformTarget != nil {
                transformList
            } else if results.isEmpty {
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
            query = ""
            if let idx = initialTransformIndex, store.items.indices.contains(idx) {
                transformTarget = store.items[idx]
                transformSelection = 0
            } else {
                transformTarget = nil
            }
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { if transformTarget != nil { transformSelection = 0 } else { selection = 0 } }
        .onChange(of: results.count) { if selection >= results.count { selection = max(0, results.count - 1) } }
        .onChange(of: transformTarget?.id) { DispatchQueue.main.async { searchFocused = true } }   // keep keys alive across modes
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.return) { commitSelection(); return .handled }
        .onKeyPress(.escape) { escapeAction(); return .handled }
        .onKeyPress(phases: .down) { handleCommandKey($0) }
    }

    // MARK: - Search results

    private var resultList: some View {
        let showSections = Set(results.map(section(for:))).count > 1
        return ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    if showSections, index == 0 || section(for: results[index - 1]) != section(for: item) {
                        sectionHeader(section(for: item))
                    }
                    resultRow(index: index, item: item)
                }
            }
            .padding(8)
        }
    }

    private func section(for item: ClipItem) -> String {
        if item.kind == .snippet { return "Snippets" }
        if item.isFavorite { return "Favorites" }
        return "Recents"
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
        let masked = SecretDetector.maskedPreview(item.text)   // nil unless it's a secret
        let revealed = revealedSecrets.contains(item.id)
        let showMasked = masked != nil && prefs.maskSecrets && !revealed
        return HStack(spacing: 8) {
            if masked != nil {
                Image(systemName: revealed ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(.orange).frame(width: 15)
            } else {
                KindIcon(kind: item.kind, text: item.text)
            }
            Text(showMasked ? masked! : item.text).lineLimit(1).truncationMode(.middle)
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

    // MARK: - Transform mode (⌘K)

    private func transformBar(_ target: ClipItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars").foregroundStyle(.purple)
            Text("Transform").foregroundStyle(.secondary)
            Text((prefs.maskSecrets ? SecretDetector.maskedPreview(target.text) : nil) ?? target.text)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text("esc to go back").foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var transformList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if transforms.isEmpty {
                    Text("No transforms for this clip.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                ForEach(Array(transforms.enumerated()), id: \.element.id) { index, t in
                    transformRow(index: index, t: t)
                }
            }
            .padding(8)
        }
    }

    private func transformRow(index: Int, t: ClipTransform) -> some View {
        // Don't preview a transformed secret — the result can expose it in another
        // encoding/case. The transform still applies to the real value on tap.
        let hideSecret = prefs.maskSecrets && transformTarget.map { SecretDetector.isSecret($0.text) } == true
        let preview = hideSecret ? "••••" : (transformTarget.flatMap { t.apply($0.text) } ?? "")
        return HStack(spacing: 8) {
            Image(systemName: t.systemImage).foregroundStyle(.purple).frame(width: 16)
            Text(t.name)
            Spacer(minLength: 12)
            Text(preview)
                .lineLimit(1).truncationMode(.middle)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 300, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            index == transformSelection ? Color.accentColor.opacity(0.25) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { transformSelection = index; applyTransform(t) }
    }

    // MARK: - Banner / footer

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
        Text(footerHint)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private var footerHint: String {
        if transformTarget != nil { return "↑↓ move · ⏎ apply · esc back" }
        let base = "↑↓ move · ⏎ paste · ⌘K transform · ⌘D favorite · ⌘⌫ delete · esc"
        if let action = selectedAction { return "⌘O \(action.label) · \(base)" }
        return base
    }

    // MARK: - Actions

    private func moveSelection(_ delta: Int) {
        if transformTarget != nil {
            guard !transforms.isEmpty else { return }
            transformSelection = (transformSelection + delta + transforms.count) % transforms.count
        } else {
            guard !results.isEmpty else { return }
            selection = (selection + delta + results.count) % results.count
        }
    }

    private func commitSelection() {
        if transformTarget != nil {
            guard transforms.indices.contains(transformSelection) else { return }
            applyTransform(transforms[transformSelection])
        } else {
            pasteSelected()
        }
    }

    private func escapeAction() {
        if transformTarget != nil {
            transformTarget = nil
            query = ""
        } else {
            onClose()
        }
    }

    private func handleCommandKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else { return .ignored }
        if press.characters == "k" { toggleTransformMode(); return .handled }
        guard transformTarget == nil else { return .ignored }   // ⌘⌫ / ⌘D / ⌘1–9 / ⌘O only in search mode
        if press.characters == "o" { actOnSelected(); return .handled }
        if press.key == .delete || press.characters == "\u{7f}" || press.characters == "\u{8}" {
            deleteSelected(); return .handled       // ⌘⌫ deletes the selected clip (plain ⌫ stays for editing the query)
        }
        if press.characters == "d" { toggleFavoriteSelected(); return .handled }
        if let n = press.characters.first?.wholeNumberValue, (1...9).contains(n) {
            pasteVisible(at: n - 1); return .handled
        }
        return .ignored
    }

    private func toggleTransformMode() {
        if transformTarget != nil {
            transformTarget = nil
            query = ""
        } else if results.indices.contains(selection) {
            transformTarget = results[selection]
            transformSelection = 0
            query = ""
        }
    }

    private func applyTransform(_ t: ClipTransform) {
        guard let target = transformTarget, let result = t.apply(target.text) else { return }
        store.insert(text: result)   // record the transformed value (the paste-back is RestoredType-skipped)
        onPaste(result)
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
        let id = results[selection].id
        store.toggleFavorite(id)
        if let newIndex = results.firstIndex(where: { $0.id == id }) {
            selection = newIndex   // favoriting reorders the list — follow the clip so the next action hits it
        }
    }

    private func deleteSelected() {
        guard results.indices.contains(selection) else { return }
        store.delete(results[selection].id)
    }

    /// The context-aware action (⌘O) for the selected clip, or nil. Computed live from text.
    private var selectedAction: ClipAction? {
        guard transformTarget == nil, results.indices.contains(selection) else { return nil }
        return ClipAction.of(results[selection].text)
    }

    private func actOnSelected() {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        switch ClipAction.of(item.text) {
        case .revealSecret:
            if revealedSecrets.contains(item.id) { revealedSecrets.remove(item.id) }
            else { revealedSecrets.insert(item.id) }
        case .openURL(let url):
            NSWorkspace.shared.open(url)
            onClose()
        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onClose()
        case .none:
            break
        }
    }
}
