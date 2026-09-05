import Foundation

/// A small, reproducible PRNG.
///
/// `Array.shuffled()` uses the system generator, which cannot be reproduced —
/// and an unreproducible shuffle is untestable. Seeding also means a shuffle
/// session can be recreated exactly.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // No special case for zero: it is splitmix64's canonical initial state,
        // not a degenerate one. Remapping it would only make seed 0 and
        // 0x9E3779B97F4A7C15 produce identical sequences.
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// How a playback sequence is arranged.
///
/// Order is one of the three orthogonal dimensions in CONTEXT.md, and since
/// docs/adr/0006 it is purely about arrangement — it carries no presentation of
/// its own. A shuffled sequence plays in the same left/right viewer.
enum MediaOrder {
    /// Deterministic for a given seed, and provably a permutation: no item is
    /// dropped or duplicated.
    static func shuffled(_ items: [MediaItem], seed: UInt64) -> [MediaItem] {
        var generator = SeededGenerator(seed: seed)
        return items.shuffled(using: &generator)
    }

    /// Builds the sequence to hand the viewer.
    ///
    /// In isolated mode the sequence keeps only the entry item's kind, so
    /// shuffling photos never drops you into a video. In mixed mode both kinds
    /// share one sequence.
    static func sequence(
        from items: [MediaItem],
        entry: MediaItem?,
        mixed: Bool,
        seed: UInt64? = nil
    ) -> (items: [MediaItem], startIndex: Int) {
        let pool: [MediaItem]
        if mixed {
            pool = items
        } else if let entry {
            pool = items.filter { $0.type == entry.type }
        } else {
            // Shuffling the whole folder has no entry item to match, so
            // "isolated" is taken to mean photos only — the library is 98.6%
            // photos and the point of the setting is not being interrupted by a
            // video mid-browse.
            pool = items.filter { !$0.isVideo }
        }

        let ordered = seed.map { shuffled(pool, seed: $0) } ?? pool
        let start = entry.flatMap { target in ordered.firstIndex(where: { $0.id == target.id }) } ?? 0
        return (ordered, start)
    }
}

/// Whether a shuffle mixes photos and videos, or stays within one kind.
/// Carried over from the web frontend, where it governed the vertical sequence;
/// after docs/adr/0006 this is its only remaining use.
enum MixedModePreference {
    private static let key = "viewer.mixedMode"

    static func load() -> Bool {
        // Default to mixed, matching the web frontend's default.
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func store(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
