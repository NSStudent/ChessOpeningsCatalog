//
//  bench-catalog
//
//  Speed of classify on synthetic games, without the replay: each game has 40 keys, the first 2–12 taken from the
//  catalog (hits) and the rest random (misses, as when a game leaves the book).
//
//  Usage: swift run -c release --package-path Tools bench-catalog [games …]
//  Keep the game count small (the default 2,048 and 10,000 fit in cache): with large sets the figures measure memory
//  paging, not the lookup.
//

import ChessOpeningsCatalog
import Foundation

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

@inline(never)
func run(games: Int, catalog: OpeningCatalog) -> (index: Double, match: Double, array: Double) {
    var generator = SystemRandomNumberGenerator()
    let named = catalog.openings.map(\.key)
    var flat: [UInt64] = []
    flat.reserveCapacity(games * 40)
    for _ in 0..<games {
        let hits = Int.random(in: 2...12, using: &generator)
        for ply in 0..<40 {
            flat.append(ply < hits ? named.randomElement(using: &generator)! : UInt64.random(in: 0...UInt64.max, using: &generator))
        }
    }
    let arrays = (0..<games).map { Array(flat[($0 * 40)..<($0 * 40 + 40)]) }
    var best = (index: Double.infinity, match: Double.infinity, array: Double.infinity)
    var sink = 0
    flat.withUnsafeBufferPointer { all in
        for _ in 0..<7 {
            var start = now()
            for game in 0..<games {
                sink &+= catalog.classifyIndex(keys: UnsafeBufferPointer(rebasing: all[(game * 40)..<(game * 40 + 40)]))
            }
            best.index = min(best.index, now() - start)
            start = now()
            for game in 0..<games {
                sink &+= catalog.classifyMatch(keys: UnsafeBufferPointer(rebasing: all[(game * 40)..<(game * 40 + 40)]))?.index ?? 0
            }
            best.match = min(best.match, now() - start)
            start = now()
            for keys in arrays {
                sink &+= catalog.classify(keys: keys)?.plies ?? 0
            }
            best.array = min(best.array, now() - start)
        }
    }
    precondition(sink != .min)
    let scale = 1e9 / Double(games)
    return (best.index * scale, best.match * scale, best.array * scale)
}

// Shells and agents may start processes at a low QoS, which moves the loop to efficiency cores at random.
pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
let catalog = OpeningCatalog.shared
let sizes = CommandLine.arguments.dropFirst().compactMap(Int.init)
for games in sizes.isEmpty ? [2_048, 10_000] : sizes {
    let result = run(games: games, catalog: catalog)
    print(String(format: "%7d games: classifyIndex %.0f ns, classifyMatch %.0f ns, classify([UInt64]) %.0f ns",
                 games, result.index, result.match, result.array))
}
