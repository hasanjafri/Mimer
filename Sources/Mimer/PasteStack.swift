import Foundation

/// An ordered, deduplicated queue of clips the user is assembling to paste in sequence
/// (Tab toggles membership in the palette; ⇧⏎ pastes them all in order). Stores clip ids
/// and resolves to live `ClipItem`s at paste time. Pure + testable; resets each palette open.
struct PasteStack {
    private(set) var ids: [UUID] = []

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    /// Add the clip if absent, remove it if already stacked (Tab toggles).
    mutating func toggle(_ id: UUID) {
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
    }

    mutating func clear() { ids.removeAll() }

    /// Drop an id (e.g. when its clip is deleted) so the count/badges stay accurate.
    mutating func remove(_ id: UUID) { ids.removeAll { $0 == id } }

    /// 1-based position shown as the row badge, or nil if not stacked.
    func position(of id: UUID) -> Int? { ids.firstIndex(of: id).map { $0 + 1 } }

    /// The stacked clips in stack order, resolved against the given candidates (ids that no
    /// longer resolve — e.g. a deleted clip — are dropped).
    func ordered(from candidates: [ClipItem]) -> [ClipItem] {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }
}
