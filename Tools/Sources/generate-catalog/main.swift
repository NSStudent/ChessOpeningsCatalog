//
//  generate-catalog
//
//  Reads Data/lichess/{a,b,c,d,e}.tsv (eco, name, pgn), replays every line with FischerCore, keys the final
//  position with Polyglot and writes Sources/ChessOpeningsCatalog/Resources/openings.bin plus Data/openings.tsv
//  (the same entries as text, for review and diffs).
//
//  Usage: swift run -c release --package-path Tools generate-catalog [package root]
//

import CatalogTooling
import ChessOpeningsCatalog
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let dataDirectory = root.appending(path: "Data/lichess")

struct Line {
    let eco: String
    let name: String
    let pgn: String
    let source: String
}

var lines: [Line] = []
for letter in ["a", "b", "c", "d", "e"] {
    let url = dataDirectory.appending(path: "\(letter).tsv")
    let text = try String(contentsOf: url, encoding: .utf8)
    for (number, row) in text.split(separator: "\n").enumerated() where number > 0 {
        let columns = row.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count >= 3 else {
            FileHandle.standardError.write(Data("bad row \(letter).tsv:\(number + 1)\n".utf8))
            exit(1)
        }
        lines.append(Line(eco: String(columns[0]), name: String(columns[1]), pgn: String(columns[2]), source: "\(letter).tsv:\(number + 1)"))
    }
}

var byKey: [UInt64: (opening: Opening, source: String)] = [:]
var duplicates: [String] = []
var checkedPositions = 0
var lineKeys: [[UInt64]] = []
for line in lines {
    let moves = Movetext.sanMoves(Substring(line.pgn))
    let (keys, failure) = Replay.keys(san: moves, crossCheck: true)
    checkedPositions += keys.count
    if let failure {
        FileHandle.standardError.write(Data("\(line.source) \(line.name): \(failure)\n".utf8))
        exit(1)
    }
    guard let key = keys.last else { continue }
    lineKeys.append(keys)
    let opening = Opening(id: 0, key: key, eco: line.eco, name: line.name, plies: moves.count)
    if let existing = byKey[key] {
        // Same position reached by two lines: keep the shorter line (the more canonical move order).
        duplicates.append("\(Replay.hex(key)) \(existing.source) «\(existing.opening.name)» / \(line.source) «\(line.name)»")
        if opening.plies < existing.opening.plies {
            byKey[key] = (opening, line.source)
        }
    } else {
        byKey[key] = (opening, line.source)
    }
}

let openings = byKey.values.map(\.opening).sorted { $0.key < $1.key }
let named = Dictionary(uniqueKeysWithValues: openings.map { ($0.key, $0) })

// MARK: Transpositions
//
// An unnamed position that catalog lines reach from different named positions (the last named position before it
// differs between lines) is a transposition: its name would depend on the move order. It gets the opening its
// nearest named continuations agree on: the most common family wins, and the bare family entry («Queen's Gambit
// Declined») is used when there is one. Unnamed positions reached from a single named position are not stored: they
// would only repeat that name, and for other move orders they would overwrite a more precise match (measured on
// Lumbras 2025, see the README).

struct Occurrence {
    var ancestors: Set<UInt64?> = []
    var descendants: [UInt64: Int] = [:] // named key → smallest distance
}
var occurrences: [UInt64: Occurrence] = [:]
for keys in lineKeys {
    var lastNamed: UInt64?
    for (ply, key) in keys.enumerated() {
        if named[key] != nil {
            lastNamed = key
            continue
        }
        var occurrence = occurrences[key] ?? Occurrence()
        occurrence.ancestors.insert(lastNamed)
        for later in (ply + 1)..<keys.count where named[keys[later]] != nil {
            let distance = later - ply
            occurrence.descendants[keys[later]] = min(occurrence.descendants[keys[later]] ?? .max, distance)
        }
        occurrences[key] = occurrence
    }
}

func family(_ name: String) -> String {
    name.firstIndex(of: ":").map { String(name[..<$0]) } ?? name
}
let bareByFamily = Dictionary(grouping: openings.filter { !$0.name.contains(":") }, by: \.name)
func byEcoThenPlies(_ a: Opening, _ b: Opening) -> Bool {
    (a.eco, a.plies, a.name) < (b.eco, b.plies, b.name)
}

var transpositions: [UInt64: UInt64] = [:]
var junctions: [(key: UInt64, ancestors: [String], chosen: Opening)] = []
for (key, occurrence) in occurrences where occurrence.ancestors.count > 1 {
    let nearest = occurrence.descendants.values.min()!
    let candidates = occurrence.descendants.filter { $0.value == nearest }.map { named[$0.key]! }.sorted(by: byEcoThenPlies)
    let votes = Dictionary(grouping: candidates, by: { family($0.name) })
    let winner = votes.max { a, b in
        a.value.count != b.value.count ? a.value.count < b.value.count : byEcoThenPlies(b.value[0], a.value[0])
    }!
    let lowestEco = winner.value[0].eco
    let chosen: Opening
    if let bare = bareByFamily[winner.key]?.sorted(by: byEcoThenPlies) {
        chosen = bare.last(where: { $0.eco <= lowestEco }) ?? bare[0]
    } else {
        chosen = winner.value[0]
    }
    transpositions[key] = chosen.key
    junctions.append((key, occurrence.ancestors.map { $0.flatMap { named[$0]?.name } ?? "—" }.sorted(), chosen))
}

let data = try CatalogFile.encode(openings, transpositions: transpositions)
let output = root.appending(path: "Sources/ChessOpeningsCatalog/Resources/openings.bin")
try data.write(to: output)

// Round trip through the runtime reader.
let catalog = try OpeningCatalog(data: data)
precondition(catalog.count == openings.count)
precondition(catalog.transpositions.count == transpositions.count)
for opening in openings {
    precondition(catalog.lookup(key: opening.key, matching: .namedPositions)?.name == opening.name)
}
for (key, target) in transpositions {
    precondition(catalog.lookup(key: key, matching: .namedPositions) == nil)
    precondition(catalog.lookup(key: key)?.key == target)
}

var text = "key\teco\tplies\tname\n"
for opening in openings {
    text += "\(Replay.hex(opening.key))\t\(opening.eco)\t\(opening.plies)\t\(opening.name)\n"
}
try text.write(to: root.appending(path: "Data/openings.tsv"), atomically: true, encoding: .utf8)

var junctionText = "key\teco\tchosen opening\tlast named positions before it on the catalog lines\n"
for junction in junctions.sorted(by: { ($0.chosen.eco, $0.key) < ($1.chosen.eco, $1.key) }) {
    junctionText += "\(Replay.hex(junction.key))\t\(junction.chosen.eco)\t\(junction.chosen.name)\t\(junction.ancestors.joined(separator: " | "))\n"
}
try junctionText.write(to: root.appending(path: "Data/transpositions.tsv"), atomically: true, encoding: .utf8)

let names = Set(openings.map(\.name)).count
let maxPlies = openings.map(\.plies).max() ?? 0
let pliesHistogram = Dictionary(grouping: openings, by: { $0.plies > 40 ? 41 : $0.plies }).mapValues(\.count)
print("rows: \(lines.count)")
print("positions cross-checked (board vs FEN key): \(checkedPositions)")
print("entries: \(openings.count), distinct names: \(names)")
print("duplicate positions: \(duplicates.count)")
for duplicate in duplicates { print("  \(duplicate)") }
print("longest line: \(maxPlies) plies; lines over 40 plies: \(pliesHistogram[41] ?? 0)")
print("unnamed positions on catalog lines: \(occurrences.count); transpositions stored: \(transpositions.count)")
print("openings.bin: \(data.count) bytes")
