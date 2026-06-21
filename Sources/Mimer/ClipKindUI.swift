import SwiftUI

extension ClipKind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo"
        case .file: return "doc"
        case .snippet: return "note.text"
        case .gitSHA: return "number"
        case .issueKey: return "ticket"
        case .fileRef: return "doc.text"
        }
    }

    var tint: Color {
        switch self {
        case .link: return .blue
        case .code: return .purple
        case .snippet: return .orange
        case .file, .image, .fileRef: return .teal
        case .gitSHA: return .brown
        case .issueKey: return .pink
        default: return .secondary
        }
    }
}

/// Leading type indicator for a clip row: a real color swatch for `.color`,
/// otherwise a tinted SF Symbol. Keeps links/code/colors distinguishable at a glance.
struct KindIcon: View {
    let kind: ClipKind
    let text: String

    var body: some View {
        Group {
            if kind == .color, let swatch = Color(hexString: text) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(swatch)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.35)))
            } else {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(kind.tint)
            }
        }
        .frame(width: 15, height: 15)
    }
}

extension Color {
    /// Parse `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA`.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xff) / 255
            g = Double((value >> 16) & 0xff) / 255
            b = Double((value >> 8) & 0xff) / 255
            a = Double(value & 0xff) / 255
        } else {
            r = Double((value >> 16) & 0xff) / 255
            g = Double((value >> 8) & 0xff) / 255
            b = Double(value & 0xff) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
