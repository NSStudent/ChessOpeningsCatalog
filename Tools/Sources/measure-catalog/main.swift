//
//  measure-catalog
//
//  Coverage and speed of the catalog on a PGN base:
//  - replays the first 40 plies of every game with FischerCore and keys them with PolyglotBoard;
//  - % of games with a recognized opening, with named positions only and with transpositions;
//  - % of games whose computed ECO differs from the ECO tag, with the most common disagreements;
//  - time of classify per game over the keys held in memory.
//
//  Usage: swift run -c release --package-path Tools measure-catalog <file.pgn> [report.md]
//  The README figures come from LumbrasGigabase_OTB_2025.pgn (492k games).
//

import CatalogTooling
import ChessOpeningsCatalog
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
// Child mode, launched by the parent: --shard <index> <count> <records file> <file.pgn>
var shard: (index: Int, count: Int, output: String)?
if arguments.first == "--shard", arguments.count >= 5, let index = Int(arguments[1]), let count = Int(arguments[2]) {
    shard = (index, count, arguments[3])
    arguments.removeFirst(4)
}
guard let path = arguments.first else {
    print("usage: measure-catalog <file.pgn> [report.md]")
    exit(2)
}
let reportPath = arguments.dropFirst().first
let limit = OpeningCatalog.defaultLimit

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

// MARK: Catalog load

let loadStart = now()
let catalog = OpeningCatalog.shared
let loadSeconds = now() - loadStart
let resourceBytes = try CatalogFile.encode(
    catalog.openings,
    transpositions: Dictionary(uniqueKeysWithValues: catalog.transpositions.map { ($0.key, catalog.openings[$0.opening].key) })
).count

// MARK: Split the file into games

let readStart = now()
let data = try Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), options: .alwaysMapped)
var starts: [Int] = []
data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    let bytes = raw.bindMemory(to: UInt8.self)
    // A game starts at a "[" that begins a line when the previous non-empty line was not a tag (or at offset 0).
    var previousLineIsTag = false
    var lineStart = 0
    var index = 0
    while index < bytes.count {
        if index == lineStart {
            let byte = bytes[index]
            let isTag = byte == UInt8(ascii: "[")
            if isTag && !previousLineIsTag { starts.append(index) }
            if byte != UInt8(ascii: "\n") && byte != UInt8(ascii: "\r") {
                previousLineIsTag = isTag
            }
        }
        if bytes[index] == UInt8(ascii: "\n") { lineStart = index + 1 }
        index += 1
    }
}
starts.append(data.count)
let gameCount = starts.count - 1
print("games: \(gameCount) (split in \(String(format: "%.1f", now() - readStart)) s)")

// MARK: Replay in child processes

struct GameRecord: Sendable {
    var ecoTag: String?
    var hasStartingFEN = false
    var keys: [UInt64] = []
    var replayFailed = false
    var firstMoves = ""
    var label = ""
}

func parse(_ text: Substring) -> GameRecord {
    var record = GameRecord()
    var movetextStart = text.endIndex
    var white = ""
    var black = ""
    var year = ""
    var cursor = text.startIndex
    while cursor < text.endIndex {
        let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
        let line = text[cursor..<lineEnd]
        if line.hasPrefix("[") {
            if let space = line.firstIndex(of: " "),
               let open = line.firstIndex(of: "\""),
               let close = line.lastIndex(of: "\""), open < close {
                let name = line[line.index(after: line.startIndex)..<space]
                let value = String(line[line.index(after: open)..<close])
                switch name {
                case "ECO": record.ecoTag = value.isEmpty || value == "?" ? nil : value
                case "FEN": record.hasStartingFEN = true
                case "White": white = value
                case "Black": black = value
                case "Date": year = String(value.prefix(4))
                default: break
                }
            }
        } else if !line.allSatisfy(\.isWhitespace) {
            movetextStart = cursor
            break
        }
        cursor = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
    }
    _ = (white, black)
    record.label = year
    guard !record.hasStartingFEN else { return record }
    let moves = Movetext.sanMoves(text[movetextStart...], limit: limit)
    record.firstMoves = moves.prefix(16).joined(separator: " ")
    let (keys, failure) = Replay.keys(san: moves)
    record.keys = keys
    record.replayFailed = failure != nil
    return record
}

func replay(_ range: Range<Int>) -> [GameRecord] {
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        let base = raw.baseAddress!
        return range.map { game in
            let bytes = UnsafeRawBufferPointer(start: base + starts[game], count: starts[game + 1] - starts[game])
            return parse(Substring(String(decoding: bytes, as: UTF8.self)))
        }
    }
}

// Record file: per game a flags byte (1 FEN, 2 failed), ECO (3 bytes, or "---"), key count, keys, label, first moves.
func encode(_ records: [GameRecord]) -> Data {
    var out = Data()
    func string(_ value: String) {
        let bytes = Array(value.utf8.prefix(65_535))
        withUnsafeBytes(of: UInt16(bytes.count).littleEndian) { out.append(contentsOf: $0) }
        out.append(contentsOf: bytes)
    }
    for record in records {
        out.append((record.hasStartingFEN ? 1 : 0) | (record.replayFailed ? 2 : 0))
        let eco = Array((record.ecoTag ?? "---").utf8)
        out.append(contentsOf: eco.count == 3 ? eco : Array("???".utf8))
        out.append(UInt8(record.keys.count))
        for key in record.keys { withUnsafeBytes(of: key.littleEndian) { out.append(contentsOf: $0) } }
        string(record.label)
        string(record.firstMoves)
    }
    return out
}

func decode(_ data: Data) -> [GameRecord] {
    var records: [GameRecord] = []
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        var at = 0
        func string() -> String {
            let count = Int(raw.loadUnaligned(fromByteOffset: at, as: UInt16.self).littleEndian)
            at += 2
            defer { at += count }
            return String(decoding: UnsafeRawBufferPointer(rebasing: raw[at..<(at + count)]), as: UTF8.self)
        }
        while at < raw.count {
            var record = GameRecord()
            let flags = raw[at]
            record.hasStartingFEN = flags & 1 != 0
            record.replayFailed = flags & 2 != 0
            let eco = String(decoding: UnsafeRawBufferPointer(rebasing: raw[(at + 1)..<(at + 4)]), as: UTF8.self)
            record.ecoTag = eco == "---" ? nil : eco
            let count = Int(raw[at + 4])
            at += 5
            record.keys = (0..<count).map { raw.loadUnaligned(fromByteOffset: at + 8 * $0, as: UInt64.self).littleEndian }
            at += 8 * count
            record.label = string()
            record.firstMoves = string()
            records.append(record)
        }
    }
    return records
}

if let shard {
    let lower = gameCount * shard.index / shard.count
    let upper = gameCount * (shard.index + 1) / shard.count
    try encode(replay(lower..<upper)).write(to: URL(fileURLWithPath: shard.output))
    exit(0)
}

// One process per core: FischerCore keeps its attack tables in `static var` arrays, and threads of one process
// reading them fight over the same reference counts (measured: 10 threads ran no faster than one).
let replayStart = now()
let workers = ProcessInfo.processInfo.activeProcessorCount
let scratch = FileManager.default.temporaryDirectory.appending(path: "measure-catalog-\(ProcessInfo.processInfo.processIdentifier)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
var children: [(Process, URL)] = []
for index in 0..<workers {
    let output = scratch.appending(path: "shard-\(index).bin")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["--shard", "\(index)", "\(workers)", output.path, path]
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    children.append((process, output))
}
var records: [GameRecord] = []
records.reserveCapacity(gameCount)
for (process, output) in children {
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        print("shard failed: \(process.terminationStatus)")
        exit(1)
    }
    records += decode(try Data(contentsOf: output))
}
precondition(records.count == gameCount)
let replaySeconds = now() - replayStart
print("replay: \(String(format: "%.1f", replaySeconds)) s")

// MARK: Speed of classify

let playable = records.filter { !$0.hasStartingFEN && !$0.keys.isEmpty }
var flat: [UInt64] = []
var offsets: [Int] = [0]
for record in playable {
    flat.append(contentsOf: record.keys)
    offsets.append(flat.count)
}

struct Timings {
    var bufferLines = Double.infinity
    var bufferNamed = Double.infinity
    var matchLines = Double.infinity
    var arrayLines = Double.infinity
}

// Timed in blocks of 2,048 games whose keys are copied first (not timed) so they are in cache, as they are when an
// indexer classifies the keys it has just computed. Timing the whole base in one pass measures memory paging
// instead: on a machine under memory pressure the 150 MB of keys get compressed and the figures jump 10×.
@inline(never)
func benchmark(catalog: OpeningCatalog, flat: [UInt64], offsets: [Int], passes: Int) -> Timings {
    var totals = Timings(bufferLines: 0, bufferNamed: 0, matchLines: 0, arrayLines: 0)
    let games = offsets.count - 1
    var sink = 0
    let block = 2_048
    var lower = 0
    while lower < games {
        let upper = min(games, lower + block)
        let local = Array(flat[offsets[lower]..<offsets[upper]])
        let localOffsets = offsets[lower...upper].map { $0 - offsets[lower] }
        let arrays = (0..<(upper - lower)).map { Array(local[localOffsets[$0]..<localOffsets[$0 + 1]]) }
        var best = Timings()
        local.withUnsafeBufferPointer { all in
            for _ in 0..<passes {
                var start = now()
                for game in 0..<(upper - lower) {
                    sink &+= catalog.classifyIndex(keys: UnsafeBufferPointer(rebasing: all[localOffsets[game]..<localOffsets[game + 1]]))
                }
                best.bufferLines = min(best.bufferLines, now() - start)

                start = now()
                for game in 0..<(upper - lower) {
                    sink &+= catalog.classifyIndex(
                        keys: UnsafeBufferPointer(rebasing: all[localOffsets[game]..<localOffsets[game + 1]]),
                        matching: .namedPositions
                    )
                }
                best.bufferNamed = min(best.bufferNamed, now() - start)

                start = now()
                for game in 0..<(upper - lower) {
                    sink &+= catalog.classifyMatch(keys: UnsafeBufferPointer(rebasing: all[localOffsets[game]..<localOffsets[game + 1]]))?.index ?? 0
                }
                best.matchLines = min(best.matchLines, now() - start)

                start = now()
                for keys in arrays {
                    sink &+= catalog.classify(keys: keys)?.plies ?? 0
                }
                best.arrayLines = min(best.arrayLines, now() - start)
            }
        }
        totals.bufferLines += best.bufferLines
        totals.bufferNamed += best.bufferNamed
        totals.matchLines += best.matchLines
        totals.arrayLines += best.arrayLines
        lower = upper
    }
    precondition(sink != Int.min)
    let scale = 1e9 / Double(games)
    return Timings(
        bufferLines: totals.bufferLines * scale,
        bufferNamed: totals.bufferNamed * scale,
        matchLines: totals.matchLines * scale,
        arrayLines: totals.arrayLines * scale
    )
}

pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
let timings = benchmark(catalog: catalog, flat: flat, offsets: offsets, passes: 3)
let indexLines = timings.bufferLines
let indexNamed = timings.bufferNamed
let matchLines = timings.matchLines
let arrayNs = timings.arrayLines
let averageKeys = Double(flat.count) / Double(playable.count)

// MARK: Coverage

struct Coverage {
    var recognized = 0
    var withTag = 0
    var same = 0
    var sameLetter = 0
    var differ = 0
    var disagreements: [String: Int] = [:]
    var examples: [String: String] = [:]
    var computedWithoutTag = 0
}

func coverage(_ matching: OpeningCatalog.Matching) -> Coverage {
    var result = Coverage()
    for record in playable {
        guard let opening = catalog.classify(keys: record.keys, matching: matching) else { continue }
        result.recognized += 1
        guard let tag = record.ecoTag else {
            result.computedWithoutTag += 1
            continue
        }
        result.withTag += 1
        if tag == opening.eco {
            result.same += 1
        } else {
            result.differ += 1
            if tag.first == opening.eco.first { result.sameLetter += 1 }
            let pair = "\(tag) → \(opening.eco)"
            result.disagreements[pair, default: 0] += 1
            if result.examples[pair] == nil {
                result.examples[pair] = "\(record.label): \(record.firstMoves) — «\(opening.name)»"
            }
        }
    }
    return result
}

let named = coverage(.namedPositions)
let lines = coverage(.transpositions)

let total = records.count
let withFEN = records.filter(\.hasStartingFEN).count
let failed = records.filter(\.replayFailed).count
let empty = records.filter { !$0.hasStartingFEN && $0.keys.isEmpty }.count
let tagged = playable.filter { $0.ecoTag != nil }.count
let tagMissing = playable.count - tagged
let unrecognized = playable.filter { catalog.classify(keys: $0.keys) == nil }

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "—" : String(format: "%.2f %%", Double(part) / Double(whole) * 100)
}
func ns(_ value: Double) -> String { String(format: "%.0f", value) }

var report = """
# Measurement on \((path as NSString).lastPathComponent)

- Games: \(total); with a starting FEN (not classified): \(withFEN); without moves: \(empty); \
replay stopped by an unplayable move before ply \(limit): \(failed) (classified with the keys that were played).
- Classifiable: \(playable.count); with an ECO tag: \(tagged) (\(percent(tagged, playable.count))); without: \(tagMissing).
- Replay of the first \(limit) plies with FischerCore: \(String(format: "%.1f", replaySeconds)) s in \(workers) processes.

## Resource and loading

- `openings.bin`: \(resourceBytes) bytes; \(catalog.count) named positions and \(catalog.transpositions.count) transpositions.
- Loading `OpeningCatalog.shared` (read + hash table): \(String(format: "%.2f", loadSeconds * 1000)) ms.

## Time of `classify` per game

\(String(format: "%.1f", averageKeys)) keys per game on average (up to \(limit) plies); all \(playable.count) games in blocks of 2,048 with their keys in cache (best of 3 passes per block), one core:

| Variant | ns/game |
|---|---|
| `classifyIndex(keys:)` on a buffer, with transpositions | \(ns(indexLines)) |
| `classifyIndex(keys:matching: .namedPositions)` | \(ns(indexNamed)) |
| `classifyMatch(keys:)` on a buffer → `OpeningMatch` | \(ns(matchLines)) |
| `classify(keys: [UInt64])` → `Opening` | \(ns(arrayNs)) |

## Coverage

| | Named positions only | With transpositions (default) |
|---|---|---|
| Games with a recognized opening | \(named.recognized) (\(percent(named.recognized, playable.count))) | \(lines.recognized) (\(percent(lines.recognized, playable.count))) |
| Computed ECO = tag | \(named.same) (\(percent(named.same, named.withTag))) | \(lines.same) (\(percent(lines.same, lines.withTag))) |
| Computed ECO ≠ tag | \(named.differ) (\(percent(named.differ, named.withTag))) | \(lines.differ) (\(percent(lines.differ, lines.withTag))) |
| … of them with the same letter | \(named.sameLetter) | \(lines.sameLetter) |
| ECO computed for games without a tag | \(named.computedWithoutTag) | \(lines.computedWithoutTag) |

«=» and «≠» are counted over the games with a tag and a recognized opening (\(named.withTag) and \(lines.withTag)).

### Most common disagreements (with transpositions)

| Tag → computed | Games | First example |
|---|---|---|

"""
for (pair, count) in lines.disagreements.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(25) {
    let example = (lines.examples[pair] ?? "").replacingOccurrences(of: "|", with: "/")
    report += "| \(pair) | \(count) | \(example) |\n"
}
// How deep the matches are, and the tags that say nothing (A00 for games that are not irregular openings).
var depthHistogram = [0, 0, 0, 0, 0] // match at ply 1–5, 6–9, 10–15, 16–23, 24+
var depthSum = 0
var a00Tags = 0
var a00TagsComputedOther = 0
var nonA00WithTag = 0
var nonA00Same = 0
for record in playable {
    guard let match = catalog.classifyMatch(keys: record.keys) else { continue }
    let ply = match.index + 1
    depthSum += ply
    depthHistogram[ply <= 5 ? 0 : ply <= 9 ? 1 : ply <= 15 ? 2 : ply <= 23 ? 3 : 4] += 1
    if record.ecoTag == "A00" {
        a00Tags += 1
        if match.opening.eco != "A00" { a00TagsComputedOther += 1 }
    } else if let tag = record.ecoTag, Opening.ecoIndex(tag) != nil {
        nonA00WithTag += 1
        if tag == match.opening.eco { nonA00Same += 1 }
    }
}
let matched = depthHistogram.reduce(0, +)
report += """

### Depth of the match (with transpositions)

Average ply of the last match: \(String(format: "%.1f", Double(depthSum) / Double(max(matched, 1)))).

| Ply of the match | 1–5 | 6–9 | 10–15 | 16–23 | 24–40 |
|---|---|---|---|---|---|
| Games | \(depthHistogram.map { "\($0) (\(percent($0, matched)))" }.joined(separator: " | ")) |

### A00 tags

\(a00Tags) games carry `ECO "A00"`; for \(a00TagsComputedOther) (\(percent(a00TagsComputedOther, a00Tags))) the catalog finds another opening: the tag is a placeholder. \
Leaving them out (and tags that are not a valid ECO), the computed ECO equals the tag in \(nonA00Same) of \(nonA00WithTag) games (\(percent(nonA00Same, nonA00WithTag))).

"""

// Where the two modes disagree, which one matches the tag?
var modeDiff = 0
var namedRight = 0
var linesRight = 0
var modePairs: [String: (count: Int, example: String)] = [:]
for record in playable {
    guard let byName = catalog.classifyMatch(keys: record.keys, matching: .namedPositions),
          let byLine = catalog.classifyMatch(keys: record.keys),
          byName.opening.eco != byLine.opening.eco else { continue }
    modeDiff += 1
    if record.ecoTag == byName.opening.eco { namedRight += 1 }
    if record.ecoTag == byLine.opening.eco { linesRight += 1 }
    let pair = "\(record.ecoTag ?? "—") / \(byName.opening.eco) (ply \(byName.index + 1)) / \(byLine.opening.eco) (ply \(byLine.index + 1))"
    let key = "\(record.ecoTag ?? "—") / \(byName.opening.eco) / \(byLine.opening.eco)"
    let example = "\(record.firstMoves) — «\(byName.opening.name)» / «\(byLine.opening.name)» · \(pair)"
    modePairs[key] = (modePairs[key]?.count ?? 0) + 1 > 1 ? ((modePairs[key]!.count + 1), modePairs[key]!.example) : (1, example)
}
report += """

### When the two modes give different ECOs

\(modeDiff) games (\(percent(modeDiff, playable.count))); the tag agrees with «named only» in \(namedRight) and with «transpositions» in \(linesRight).

| Tag / named only / with transpositions | Games | Example |
|---|---|---|

"""
for (key, value) in modePairs.sorted(by: { ($0.value.count, $1.key) > ($1.value.count, $0.key) }).prefix(20) {
    report += "| \(key) | \(value.count) | \(value.example.replacingOccurrences(of: "|", with: "/")) |\n"
}

report += "\n### Games without a recognized opening (sample)\n\n"
for record in unrecognized.prefix(10) {
    report += "- \(record.label): \(record.firstMoves) (ECO tag: \(record.ecoTag ?? "—"))\n"
}

print(report)
if let reportPath {
    try report.write(toFile: (reportPath as NSString).expandingTildeInPath, atomically: true, encoding: .utf8)
}
