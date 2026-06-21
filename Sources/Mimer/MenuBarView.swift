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

    private let rowHeight: CGFloat = 30

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
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    row(index: index, item: item)
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
            ForEach(Array(store.items.prefix(6).enumerated()), id: \.element.id) { index, item in
                row(index: index, item: item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    #endif

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

    private func row(index: Int, item: ClipItem) -> some View {
        let isCopied = copiedID == item.id
        let isHovered = hoverID == item.id
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 18, alignment: .trailing)
            KindIcon(kind: item.kind, text: item.text)
            Text(item.text).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if isCopied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
        guard Paster.copyToPasteboard(item.text) else { return }
        copyGeneration &+= 1
        let generation = copyGeneration
        withAnimation(.easeOut(duration: 0.15)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard copyGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.25)) { copiedID = nil }
        }
    }

    private var actions: some View {
        VStack(spacing: 2) {
            Button { PaletteController.shared.toggle() } label: {
                Label("Open Mimer  ⇧⌘V", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { prefs.isPaused.toggle() } label: {
                Label(prefs.isPaused ? "Resume recording" : "Pause recording",
                      systemImage: prefs.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { SnippetComposerWindowController.shared.show() } label: {
                Label("New Snippet…", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { UpdaterController.shared.checkForUpdates() } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
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
            .onChange(of: store.captureTick) {
                justCaptured = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { justCaptured = false }
            }
    }
}
