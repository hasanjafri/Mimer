import SwiftUI

/// Menu-bar dropdown: recent clipboard history (favorites pinned on top), height
/// driven by the "show N at once" preference (capped at screen height), then
/// scrolls. Click a clip to recall it; click the star to favorite (kept forever).
struct MenuBarView: View {
    @ObservedObject private var store = ClipStore.shared
    @ObservedObject private var prefs = Preferences.shared

    @State private var hoverID: UUID?
    @State private var copiedID: UUID?
    @State private var copyGeneration = 0

    private let rowHeight: CGFloat = 34   // fits the 22pt thumbnail + insets; rows are framed to this so listHeight is exact

    #if DEBUG
    private let debugFlatList: Bool

    init() { debugFlatList = false }

    /// Snapshot-only: seed the transient hover/copied row states and drop the
    /// ScrollView (which ImageRenderer can't lay out) so the self-test loop can
    /// render the copy-feedback affordances, otherwise only reachable with a live
    /// mouse. Never used by the running app.
    init(debugCopiedID: UUID?, debugHoverID: UUID? = nil) {
        _copiedID = State(initialValue: debugCopiedID)
        _hoverID = State(initialValue: debugHoverID)
        debugFlatList = true
    }
    #else
    init() {}
    #endif

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

            if prefs.isPaused {
                Label("Paused — not recording", systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            if store.items.isEmpty {
                Text("No clips yet — copy some text and it shows up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                #if DEBUG
                if debugFlatList { debugFlatClipList } else { clipList }
                #else
                clipList
                #endif
            }

            Divider()
            actions
        }
        .frame(width: 320)
    }

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(store.items) { item in
                    row(item: item)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(height: listHeight)
        // AppKit doesn't always deliver a row's hover-exit when the pointer leaves
        // the window, so clear here when the pointer leaves the list entirely.
        .onHover { if !$0 { hoverID = nil } }
    }

    #if DEBUG
    /// Non-scrolling render of the first rows, for the snapshot harness only.
    private var debugFlatClipList: some View {
        VStack(spacing: 1) {
            ForEach(Array(store.items.prefix(6))) { item in
                row(item: item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    #endif

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
            Text("Mimer").font(.headline)
            Spacer()
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())   // distinct from the row hover fill
                    .help("\(store.items.count) clips stored")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(item: ClipItem) -> some View {
        let isCopied = copiedID == item.id
        let isHovered = hoverID == item.id
        let masked = SecretDetector.maskedPreview(item.text)   // nil unless it's a secret
        return HStack(spacing: 10) {
            if item.kind == .image {
                ClipThumbnail(hash: item.blobHash, size: 22)
            } else if masked != nil {
                Image(systemName: "lock.fill").foregroundStyle(.orange).frame(width: 16)
            } else {
                KindIcon(kind: item.kind, text: item.text).frame(width: 16)
            }
            Text((prefs.maskSecrets ? masked : nil) ?? item.text).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if isCopied {
                // The full-row green tint already says "copied"; a bare check
                // reinforces it without crowding the favorite star with a chip.
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
                    .help("Copied to the clipboard")
            }
            // Star stays mounted (even during the copied flash) so favoriting is
            // never blocked by the transient confirmation.
            Button {
                store.toggleFavorite(item.id)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.tertiary))
            .help(item.isFavorite ? "Unfavorite" : "Favorite (kept forever)")
            .accessibilityLabel(item.isFavorite ? "Unfavorite" : "Favorite (kept forever)")
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)   // uniform row height so the menu's listHeight math is exact (image rows no longer clip)
        .background(
            isCopied ? Color.green.opacity(0.18)
                     : (isHovered ? Color.primary.opacity(0.08) : .clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoverID = item.id }
            else if hoverID == item.id { hoverID = nil }
        }
        .onTapGesture { copy(item) }
        .help("Click to copy to the clipboard")
    }

    /// Copy a clip and flash an inline "Copied" confirmation on its row — the
    /// menu-bar window stays open, so this is the only signal the click landed.
    /// Only confirm if the write landed, and tag each click with a generation so
    /// a re-copy's timer can't clear a later click's badge early.
    private func copy(_ item: ClipItem) {
        let landed: Bool
        if item.kind == .image, let hash = item.blobHash, let data = store.blobData(hash) {
            landed = Paster.copyImageToPasteboard(data)
        } else {
            landed = Paster.copyToPasteboard(item.text)
        }
        guard landed else { return }
        copyGeneration &+= 1
        let generation = copyGeneration
        withAnimation(.easeOut(duration: 0.15)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard copyGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.25)) { copiedID = nil }
        }
    }

    private var actions: some View {
        VStack(spacing: 1) {
            MenuActionRow(title: "Open Mimer", systemImage: "magnifyingglass",
                          shortcut: "⇧⌘V") {
                PaletteController.shared.toggle()
            }
            MenuActionRow(title: prefs.isPaused ? "Resume recording" : "Pause recording",
                          systemImage: prefs.isPaused ? "play.fill" : "pause.fill") {
                prefs.isPaused.toggle()
            }
            MenuActionRow(title: "New Snippet…", systemImage: "square.and.pencil") {
                SnippetComposerWindowController.shared.show()
            }
            MenuActionRow(title: "Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
                UpdaterController.shared.checkForUpdates()
            }
            MenuActionRow(title: "Settings…", systemImage: "gearshape") {
                SettingsWindowController.shared.show()
            }

            Divider().padding(.horizontal, 4).padding(.vertical, 3)

            MenuActionRow(title: "Quit Mimer", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

/// One row in the menu-bar footer: an aligned icon column, a label, and an
/// optional right-aligned shortcut, with the same hover highlight, icon column,
/// and padding as the clip rows so the whole menu reads as one surface.
private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var hovering = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 12

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)   // full-width hover + click target
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The menu-bar icon: bounces and briefly flashes a check when a clip is captured
/// (so it's clear Mimer caught the copy), and dims while recording is paused.
struct MenuBarLabel: View {
    @ObservedObject private var store = ClipStore.shared
    @ObservedObject private var prefs = Preferences.shared
    @State private var justCaptured = false

    var body: some View {
        Image(systemName: justCaptured ? "checkmark.circle.fill" : "doc.on.clipboard")
            .symbolEffect(.bounce, value: store.captureTick)
            .opacity(prefs.isPaused ? 0.4 : 1)
            .accessibilityLabel(prefs.isPaused ? "Mimer — paused" : "Mimer — recording clipboard")
            .onChange(of: store.captureTick) {
                justCaptured = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { justCaptured = false }
            }
    }
}
