import SwiftUI

/// Centralized design tokens, seeded from the design review's "add real metrics"
/// feedback. Expanded with colors, type scale, materials, and motion as the UI lands.
enum DesignSystem {
    enum Metrics {
        static let paletteWidth: CGFloat = 720
        static let paletteHeight: CGFloat = 440
        static let listPreviewSplit: CGFloat = 0.60   // ~60/40 list/preview
        static let rowHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 12
    }
    enum Motion {
        static let summon: Double = 0.15              // panel summon target (s)
    }
}
