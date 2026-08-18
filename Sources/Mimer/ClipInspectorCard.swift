import SwiftUI
import AppKit

/// The hover preview card ("peek") for a clip: the full content with the middle elided
/// instead of the ends, plus the provenance and shape of the clip you need to tell two
/// near-identical ones apart. Content comes from `ClipInspector` (pure, tested); this file
/// is layout only. Hosted by `ClipPeek` in a click-through panel beside the palette or menu.
struct ClipInspectorCard: View {
    let inspector: ClipInspector

    static let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hairline
            content
            hairline
            footer
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .clipShape(shape)
        .accessibilityHidden(true)   // a mirror of the row it describes; VoiceOver reads the row
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
    private var hairline: some View { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }

    /// The format leads when it knows better than the stored kind — a diff and a minified JSON
    /// blob are both "code" to the row, but nothing alike to read.
    private var symbol: String {
        switch inspector.format {
        case .json: return "curlybraces"
        case .diff: return "plusminus"
        default: return inspector.kind.symbolName
        }
    }

    private var tint: Color {
        switch inspector.format {
        case .json: return .purple
        case .diff: return .green
        default: return inspector.kind.tint
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.18))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 22, height: 22)

            Text(inspector.title).font(.subheadline.weight(.semibold))

            if let badge = inspector.badge {
                Text(badge)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }

            Spacer(minLength: 8)

            if inspector.isFavorite {
                Label("Favorite", systemImage: "star.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.07))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch inspector.content {
        case .text(let preview): textContent(preview)
        case .masked(let masked): maskedContent(masked)
        case .image(let hash): ImagePeek(hash: hash)
        case .color(let hex, let rgb): colorContent(hex: hex, rgb: rgb)
        }
    }

    private func textContent(_ preview: ClipInspector.Preview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            body(preview.head, monospaced: preview.monospaced, spans: preview.headSpans)
            if preview.isElided {
                elisionMarker(preview.elided, hiddenMatches: preview.hiddenMatches)
                body(preview.tail, monospaced: preview.monospaced, spans: preview.tailSpans)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func body(_ text: String, monospaced: Bool, spans: [ClipSyntax.Span]) -> some View {
        Text(highlighted(text, spans: spans))
            .font(monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12.5))
            .foregroundStyle(.primary)
            .lineSpacing(1.5)
            .textSelection(.disabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The elided middle, called out rather than hidden — you should always know how much of
    /// the clip you are not looking at.
    private func elisionMarker(_ count: Int, hiddenMatches: Int) -> some View {
        HStack(spacing: 8) {
            rule
            Text(hiddenMatches > 0
                 ? "\(count.formatted()) more characters · \(hiddenMatchLabel(hiddenMatches)) hidden"
                 : "\(count.formatted()) more characters")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .fixedSize()
            rule
        }
    }

    /// At the counting ceiling say "500+" — a card should never state a number it didn't count.
    private func hiddenMatchLabel(_ count: Int) -> String {
        if count >= ClipInspector.hiddenMatchCap { return "\(count)+ matches" }
        return "\(count) match\(count == 1 ? "" : "es")"
    }

    private var rule: some View { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5) }

    private func maskedContent(_ masked: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 15)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(masked).font(.system(size: 12.5, design: .monospaced))
                Text("Masked here and in the list — the full value still copies and pastes.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func colorContent(hex: String, rgb: String?) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hexString: hex) ?? .gray)
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(hex.uppercased()).font(.system(size: 13, design: .monospaced).weight(.medium))
                if let rgb {
                    Text(rgb).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    /// Paints the body in one pass: syntax colour from `ClipSyntax` underneath, the palette's
    /// search term highlighted on top — including in the middle of a long clip, which is the
    /// part a truncated row can never show.
    private func highlighted(_ text: String, spans: [ClipSyntax.Span]) -> AttributedString {
        let hits = ClipInspector.highlightRanges(in: text, query: inspector.query)
        guard !spans.isEmpty || !hits.isEmpty else { return AttributedString(text) }

        var styles = [ClipSyntax.Style](repeating: .plain, count: text.count)
        for span in spans {
            for index in span.range.clamped(to: 0..<text.count) { styles[index] = span.style }
        }
        var highlighted = [Bool](repeating: false, count: text.count)
        for hit in hits {
            let lower = text.distance(from: text.startIndex, to: hit.lowerBound)
            let upper = text.distance(from: text.startIndex, to: hit.upperBound)
            for index in (lower..<upper).clamped(to: 0..<text.count) { highlighted[index] = true }
        }

        var out = AttributedString()
        var run = ""
        var current: (ClipSyntax.Style, Bool)?

        func flush() {
            guard !run.isEmpty, let current else { return }
            var piece = AttributedString(run)
            // Attributes are set by key type, not by the `piece.foregroundColor` dynamic member:
            // that form builds a key path into a non-Sendable attribute scope, which is a warning
            // today and an error in the Swift 6 language mode this codebase is moving to.
            if let color = color(for: current.0) {
                piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color
            }
            if current.0 == .host {
                piece[AttributeScopes.SwiftUIAttributes.FontAttribute.self] =
                    .system(size: 11.5, design: .monospaced).weight(.semibold)
            }
            if current.1 {
                piece[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] =
                    Color.accentColor.opacity(0.28)
            }
            out += piece
            run = ""
        }

        for (index, character) in text.enumerated() {
            let key = (styles[index], highlighted[index])
            if let existing = current, existing == key {
                run.append(character)
            } else {
                flush()
                current = key
                run = String(character)
            }
        }
        flush()
        return out
    }

    private func color(for style: ClipSyntax.Style) -> Color? {
        switch style {
        case .plain: return nil
        case .comment, .meta: return .secondary
        case .string: return .green
        case .number: return .orange
        case .keyword: return .pink
        case .jsonKey: return .blue
        case .added: return .green
        case .removed: return .red
        case .hunk: return .purple
        case .host: return .primary
        case .tracking: return .red.opacity(0.75)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !inspector.stats.isEmpty {
                statsLine(inspector.stats)
            }
            HStack(spacing: 5) {
                if let app = inspector.sourceApp {
                    AppIconView(appName: app)
                    Text(app)
                    dot
                }
                Text(inspector.relativeTime)
                dot
                Text(inspector.absoluteTime)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let hint = inspector.actionHint {
                HStack(spacing: 5) {
                    Text("⌘O").font(.caption2.monospaced().weight(.medium))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    Text(hint).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func statsLine(_ stats: [ClipInspector.Stat]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 { dot }
                Text(stat.value).font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(.primary)
                if !stat.label.isEmpty {
                    Text(stat.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private var dot: some View { Text("·").font(.caption2).foregroundStyle(.tertiary) }
}

/// The image clip's own pixels, at a size worth looking at, plus what the blob says about
/// itself. Loads through the shared thumbnail cache, so hovering a row costs one decode.
private struct ImagePeek: View {
    let hash: String?
    @State private var image: NSImage?
    @State private var info: ImageBlobInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                } else {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.teal)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12)))

            if let info {
                HStack(spacing: 5) {
                    ForEach(Array(ClipInspector.imageStats(pixelWidth: info.pixelWidth,
                                                           pixelHeight: info.pixelHeight,
                                                           byteCount: info.byteCount,
                                                           type: info.type).enumerated()), id: \.offset) { index, stat in
                        if index > 0 { Text("·").foregroundStyle(.tertiary) }
                        Text(stat.value).monospacedDigit()
                        if !stat.label.isEmpty { Text(stat.label).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2)
            }
        }
        .padding(14)
        .task(id: hash) {
            guard let hash else { return }
            (image, info) = await ThumbnailCache.shared.preview(for: hash, maxPixel: 640)
        }
    }
}

/// The icon of the app a clip came from. Best-effort: we store the app's localized name (not a
/// bundle id), so this matches against running apps and simply shows nothing when it can't.
private struct AppIconView: View {
    let appName: String

    var body: some View {
        if let icon = AppIconLookup.icon(forLocalizedName: appName) {
            Image(nsImage: icon).resizable().frame(width: 12, height: 12)
        }
    }
}

@MainActor
private enum AppIconLookup {
    private static var cache: [String: NSImage?] = [:]

    static func icon(forLocalizedName name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let icon = NSWorkspace.shared.runningApplications
            .first { $0.localizedName == name }
            .flatMap(\.icon)
        cache[name] = icon
        return icon
    }
}
