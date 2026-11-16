# ChessOpeningsCatalog

Classifies chess games by opening (ECO code and name) from the **Polyglot Zobrist keys** of their positions, so the result depends neither on the move order nor on the `ECO` tag of the PGN. The deepest catalog position the game reaches wins, the way pgn-extract and ChessBase classify.

- Swift 6, Swift Package Manager, iOS 18 / macOS 15.
- **No runtime dependencies.** The caller passes the keys it already computes while replaying a game (a PGN indexer, a database codec, an engine).
- The data generator and the measurements live in `Tools/`, a separate package that depends on [FischerCore](https://github.com/NSStudent/fischer-core) (branch `feature/0.4.0`) to replay SAN. Apps that use the library never fetch it.
- Data: the [Lichess chess-openings](https://github.com/lichess-org/chess-openings) catalog, CC0.

## Installation

```swift
.package(url: "https://github.com/NSStudent/ChessOpeningsCatalog.git", branch: "main"),
```

and `.product(name: "ChessOpeningsCatalog", package: "ChessOpeningsCatalog")` in the target.

## Usage

```swift
import ChessOpeningsCatalog

let catalog = OpeningCatalog.shared            // loads Resources/openings.bin (~210 KB)

// One position
if let opening = catalog.lookup(key: 0x823C_9B50_FD11_4196) {
    print(opening.eco, opening.name)           // B00 King's Pawn Game
}

// One game: the keys of its positions in order, with or without the starting position first
let opening = catalog.classify(keys: keysOfTheGame)       // Opening?
opening?.eco          // "D37"
opening?.name         // "Queen's Gambit Declined: Three Knights Variation"
opening?.family       // "Queen's Gambit Declined"
opening?.variation    // "Three Knights Variation"
opening?.plies        // half-moves of the catalog line
opening?.ecoIndex     // 0…499, two bytes per game in an index

// Indexing millions of games: no allocation, no reference counting
keys.withUnsafeBufferPointer { buffer in
    let index = catalog.classifyIndex(keys: buffer)       // into catalog.openings, -1 when nothing matches
}

// No engine at hand? PolyglotBoard replays UCI moves and keeps the key up to date.
var board = PolyglotBoard.start
let keys = ["d2d4", "g8f6", "c2c4", "e7e6", "g1f3", "d7d5"].map { board.play(uci: $0); return board.key }
catalog.classify(keys: keys)?.name             // "Queen's Gambit Declined"
```

| API | What it does |
|---|---|
| `OpeningCatalog.shared` | The catalog bundled with the package. |
| `lookup(key:matching:)` | The opening of one position, or `nil`. Also static: `OpeningCatalog.lookup(key:)`. |
| `classify(keys:limit:matching:) -> Opening?` | The deepest match within the first `limit` plies (40 by default; the longest catalog line has 36). |
| `classifyMatch(keys:…) -> OpeningMatch?` | The same, plus the index in `keys` where it matched and whether it was a named position or a transposition. |
| `classifyIndex(keys: UnsafeBufferPointer<UInt64>, …) -> Int` | Index into `openings`; the form for indexers. |
| `PolyglotKey.key(fen:)` | Polyglot key of a FEN or EPD. |
| `PolyglotBoard` | A minimal board that updates the key move by move from UCI (`play(uci:)`). No legality checks. |
| `CatalogFile.encode/decode` | The binary format of the resource. |

`matching: .namedPositions` uses only the named positions (the Lichess data as is, as pgn-extract would). The default, `.transpositions`, adds the transpositions described below.

### Keys

They are exactly the keys of Polyglot `.bin` books: the `Random64[781]` table of the [specification](http://hgm.nubati.net/book_format.html) (pieces 0–767 with the black pawn first, castling 768–771, en passant file 772–779, white to move 780). The en passant file only counts when a pawn of the side to move stands next to the pawn that has just moved two squares (pseudo-legal: a pinned pawn counts too).

Checks:

- the tests cover the nine vectors of the specification (starting position `0x463b96181691fc9c`, after 1.e4 `0x823c9b50fd114196`, both en passant cases, castling rights lost);
- the generator keys every position of the catalog twice, incrementally with `PolyglotBoard` and from FischerCore's FEN with `PolyglotKey.key(fen:)`, and stops if they differ (37,700 positions agree);
- 1,716 of the 3,865 named keys appear in a real Polyglot book built from 2020–2025 games (26,490 positions); wrong keys would give practically none.

## Transpositions

Many opening positions have no name of their own in the catalog: they are intermediate steps of several lines. When a game reaches one by another move order, «the last named position» depends on the order. For example:

- 1.d4 Nf6 2.c4 e6 3.Nf3 d5 — the last named position is after 3.Nf3: **E10 Indian Defense: Anti-Nimzo-Indian**;
- 1.c4 e6 2.Nf3 d5 3.d4 Nf6 — the last one is after 2…d5: **A13 English Opening: Agincourt Defense**.

Both end in the same Queen's Gambit Declined position, which Lichess only lists as a step of ~80 QGD lines. So the resource also stores **141 transpositions**: unnamed positions that catalog lines reach from different named positions. Each points at an opening that already exists in the catalog (no names are made up), chosen from the position alone:

1. take the nearest named continuations (fewest plies) on the lines through it;
2. the most common family (the part of the name before «:») wins; ties go to the lowest ECO;
3. use the entry of that family without a variation («Queen's Gambit Declined», D30) when there is one; otherwise the nearest variation with the lowest ECO.

While classifying, a transposition only replaces the current match when it belongs to **another family**: 1.d4 d5 2.c4 e6 3.Nc3 Nf6 4.Nf3 Be7 stays D37 (Three Knights) and does not fall back to the generic QGD.

The full list, with the names each one comes from, is in [`Data/transpositions.tsv`](Data/transpositions.tsv). Some inherit quirks of the data: the only Lichess line through 1.e4 d5 2.Nc3 is a Van Geet line, so that position is a Van Geet Opening (A00) even when reached from the Scandinavian.

**Rejected:** indexing *every* intermediate position of the lines (4,117) with the name of the named position before it. On Lumbras it made things worse: the Catalan 1.d4 Nf6 2.c4 e6 3.g3 d5 4.Nf3 became E10 because the catalog lines reach it through 3.Nf3, and among the games where both modes disagreed the PGN tag sided with «named only» 383 times against 26 (sample of 8,923 games).

## Data: origin and license

- **Origin:** [lichess-org/chess-openings](https://github.com/lichess-org/chess-openings), files `a.tsv`…`e.tsv` (columns `eco`, `name`, `pgn`), commit `3ba6b20d31b2e6125cb0e6a2e792f400717d9d39` (5 Nov 2026). Verbatim copy in `Data/lichess/`.
- **License:** CC0 1.0 Universal (public domain). The repository says so in its README («As a collection of facts, this data set is in the public domain») and in `COPYING.txt`, copied to `Data/lichess/COPYING.txt`. No attribution is required; it is credited anyway.
- The Lichess repository no longer ships the `uci` and `epd` columns (its `Makefile` generates them with python-chess), so the generator replays the SAN of each line with FischerCore.
- The code of this package is MIT (see `LICENSE`).

### Regenerating

```sh
swift run -c release --package-path Tools generate-catalog .
```

1. Reads the 3,865 lines and replays each one with FischerCore.
2. Keys every position twice (see «Keys») and stops on any difference.
3. Writes `Sources/ChessOpeningsCatalog/Resources/openings.bin`, `Data/openings.tsv` (the same entries as text, for review and diffs) and `Data/transpositions.tsv`.
4. Reads the binary back with the library's reader and checks every entry.

With the current data: 3,865 named positions (3,177 distinct names, no position repeated), longest line 36 plies, 141 transpositions.

### `openings.bin` format

Little endian, columns sorted by key: a 24-byte header (`OPCT`, version 1, counts of entries, names, name bytes and transpositions), `UInt64` keys, `UInt16` ECO (A00 = 0 … E99 = 499), `UInt16` name index, `UInt8` plies, name offsets and UTF-8 bytes (each name stored once), then the transpositions (`UInt64` key + `UInt16` entry). Loading builds an open-addressing hash table over the keys; details in `CatalogFile.swift`.

## Figures

Measured on 16 Nov 2026 on an Apple Silicon Mac (10 cores), Swift 6.4, release build. Full report: [`Docs/Measurement_Lumbras_2025.md`](Docs/Measurement_Lumbras_2025.md).

### Resource and speed

| | |
|---|---|
| `openings.bin` | 213,986 bytes (3,865 named positions, 141 transpositions) |
| Loading `OpeningCatalog.shared` | ~11–19 ms (read + hash table) |
| `classifyIndex(keys:)`, 39 keys per game | **306 ns per game** |
| `classifyMatch(keys:)` → `OpeningMatch` | 366 ns |
| `classify(keys: [UInt64])` → `Opening` | 332 ns |
| `.namedPositions` instead of `.transpositions` | 303 ns |

Target was under 2 µs per game. Times are for keys already in cache, as when an indexer classifies the keys it has just computed: all 492,182 games of the base in blocks of 2,048, best of 3 passes per block, one core. The synthetic `bench-catalog` gives the same ~305 ns. Timing the whole base in one pass on a machine under heavy memory pressure gave 0.8–5 µs: that measured page compression and swap of the 150 MB of keys, not the lookup.

### Coverage on Lumbras Gigabase OTB 2025

492,184 over-the-board games; the first 40 plies of each replayed in 52 s (10 processes).

| | Named positions only | With transpositions (default) |
|---|---|---|
| Games with a recognized opening | 100.00 % | 100.00 % |
| Computed ECO = PGN tag | 72.76 % | 71.78 % |
| Computed ECO ≠ PGN tag | 27.24 % | 28.22 % |
| Games without an ECO tag that now get one | 99,435 (20.2 %) | 99,435 |

- Recognition is 100 % because almost every first move has a name; depth says more. The last match falls at ply 1–5 in 35.1 % of games, 6–9 in 36.3 %, 10–15 in 24.8 %, 16–23 in 3.7 % and later in 0.1 %; the average is ply 7.6.
- Most disagreements are placeholder tags. 57,414 games carry `ECO "A00"` (irregular openings), and for 95.05 % of them the catalog finds a real opening, for example a London System (D02), an Italian Game (C50) or a Closed Sicilian (B23). Leaving those out, the computed ECO equals the tag in **90.20 %** of games (279,058 of 309,387).
- The two modes disagree in 8,257 games (1.68 %). The tags were made by move order, so they side with «named only» (4,052 against 201). The most common case is the transposition above, 1.d4 Nf6 2.c4 e6 3.Nf3 d5: tag E10, transpositions D30 (470 games).
- The remaining ~10 % of real tags differ from the Lichess catalog on where it draws the line between codes: for example Slav and Semi-Slav move orders, or E60 against E61 in the King's Indian fianchetto. The tagger of the base is unknown, so these are differences, not errors of either side.

### Reproducing

```sh
swift run -c release --package-path Tools measure-catalog path/to/base.pgn Docs/Measurement.md
swift run -c release --package-path Tools bench-catalog
```

`measure-catalog` replays the first 40 plies of every game with one process per core: FischerCore keeps its attack tables in `static var` arrays and threads of one process fight over their reference counts (10 threads were no faster than one). It also parses SAN without FischerCore's lenient normalization, which runs every move through Foundation's `replacingOccurrences` (~60 µs a move).

## Tests

```sh
swift test
```

16 tests: the nine Polyglot vectors (from FEN and move by move), EPD and malformed FEN, castling and promotion, lookup by key, the two move orders above (and that `.namedPositions` gives E10 and A13), deepest match and ply limit, a transposition not overriding a more precise opening of the same family, unknown positions → `nil`, binary format round trip and ECO codes.

## Notes for integration

- Pass the keys of the first 40 plies to `classifyIndex(keys:)`. Keys computed by any Polyglot-compatible code work, as long as the en passant file follows the rule above.
- `Opening.id` is only stable within one version of the resource. To persist a classification, store the ECO (`ecoIndex`, two bytes) or the key of the named position (`Opening.key`).
