import ChessOpeningsCatalog
import Foundation
import Testing

/// Keys after each move of a UCI line (the starting position not included).
func keys(_ uci: String) -> [UInt64] {
    var board = PolyglotBoard.start
    return uci.split(separator: " ").map { move in
        let played = board.play(uci: move)
        precondition(played, "cannot play \(move)")
        return board.key
    }
}

@Suite("Polyglot keys")
struct PolyglotKeyTests {
    // The test vectors of the Polyglot book format specification (http://hgm.nubati.net/book_format.html).
    static let vectors: [(moves: String, fen: String, key: UInt64)] = [
        ("", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 0x463B_9618_1691_FC9C),
        ("e2e4", "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", 0x823C_9B50_FD11_4196),
        ("e2e4 d7d5", "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2", 0x0756_B944_61C5_0FB0),
        ("e2e4 d7d5 e4e5", "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2", 0x662F_AFB9_65DB_29D4),
        ("e2e4 d7d5 e4e5 f7f5", "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3", 0x22A4_8B5A_8E47_FF78),
        ("e2e4 d7d5 e4e5 f7f5 e1e2", "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPPKPPP/RNBQ1BNR b kq - 0 3", 0x652A_607C_A3F2_42C1),
        ("e2e4 d7d5 e4e5 f7f5 e1e2 e8f7", "rnbq1bnr/ppp1pkpp/8/3pPp2/8/8/PPPPKPPP/RNBQ1BNR w - - 0 4", 0x00FD_D303_C946_BDD9),
        ("a2a4 b7b5 h2h4 b5b4 c2c4", "rnbqkbnr/p1pppppp/8/8/PpP4P/8/1P1PPPP1/RNBQKBNR b KQkq c3 0 3", 0x3C81_23EA_7B06_7637),
        ("a2a4 b7b5 h2h4 b5b4 c2c4 b4c3 a1a3", "rnbqkbnr/p1pppppp/8/8/P6P/R1p5/1P1PPPP1/1NBQKBNR b Kkq - 0 4", 0x5C3F_9B82_9B27_9560),
    ]

    @Test("specification vectors from FEN")
    func fromFEN() {
        for vector in Self.vectors {
            #expect(PolyglotKey.key(fen: vector.fen) == vector.key, "\(vector.fen)")
        }
    }

    @Test("specification vectors move by move")
    func moveByMove() {
        #expect(PolyglotBoard.start.key == PolyglotKey.startingPosition)
        for vector in Self.vectors where !vector.moves.isEmpty {
            #expect(keys(vector.moves).last == vector.key, "\(vector.moves)")
        }
    }

    @Test("EPD without move counters and malformed FEN")
    func epdAndErrors() {
        #expect(PolyglotKey.key(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3") == 0x823C_9B50_FD11_4196)
        #expect(PolyglotKey.key(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq -") == nil)
        #expect(PolyglotKey.key(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq -") == nil)
        #expect(PolyglotKey.key(fen: "") == nil)
    }

    @Test("castling and promotion keep the key consistent with the FEN")
    func castlingAndPromotion() {
        // 1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.O-O
        #expect(keys("e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 e1g1").last
            == PolyglotKey.key(fen: "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 5 4"))
        var board = PolyglotBoard(fen: "8/P6k/8/8/8/8/8/K7 w - - 0 1")!
        board.play(uci: "a7a8n")
        #expect(board.key == PolyglotKey.key(fen: "N7/7k/8/8/8/8/8/K7 b - - 0 1"))
    }
}

@Suite("Catalog")
struct OpeningCatalogTests {
    let catalog = OpeningCatalog.shared

    @Test("the bundled catalog loads")
    func loads() {
        #expect(catalog.count > 3_000)
        #expect(catalog.linePositions.count > 3_000)
        #expect(catalog.openings.map(\.key) == catalog.openings.map(\.key).sorted())
    }

    @Test("lookup by key")
    func lookup() throws {
        let ruy = try #require(OpeningCatalog.lookup(key: keys("e2e4 e7e5 g1f3 b8c6 f1b5").last!))
        #expect(ruy.eco == "C60")
        #expect(ruy.name == "Ruy Lopez")
        #expect(ruy.family == "Ruy Lopez")
        #expect(ruy.variation == nil)
        #expect(ruy.plies == 5)
        #expect(ruy.moveCount == 3)

        let najdorf = try #require(catalog.lookup(key: keys("e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6").last!))
        #expect(najdorf.eco == "B90")
        #expect(najdorf.family == "Sicilian Defense")
        #expect(najdorf.variation == "Najdorf Variation")
    }

    @Test("transpositions reach the same opening")
    func transpositions() throws {
        // The example of the brief: the final position has no name of its own in the Lichess data, it is a
        // position on ~80 Queen's Gambit Declined lines that the two move orders reach from different names.
        let first = keys("d2d4 g8f6 c2c4 e7e6 g1f3 d7d5")
        let second = keys("c2c4 e7e6 g1f3 d7d5 d2d4 g8f6")
        #expect(first.last == second.last)
        let a = try #require(catalog.classifyMatch(keys: first))
        let b = try #require(catalog.classifyMatch(keys: second))
        #expect(a.opening == b.opening)
        #expect(a.opening.name == "Queen's Gambit Declined")
        #expect(a.index == 5 && b.index == 5)
        #expect(!a.isNamedPosition)

        // With named positions only, each order keeps the last name it passed through.
        #expect(catalog.classify(keys: first, matching: .namedPositions)?.name == "Indian Defense: Anti-Nimzo-Indian")
        #expect(catalog.classify(keys: second, matching: .namedPositions)?.name == "English Opening: Agincourt Defense")

        // A named position reached by two move orders: 1.e4 e5 2.Nf3 Nc6 3.Bb5 and 1.Nf3 Nc6 2.e4 e5 3.Bb5.
        let ruy = catalog.classify(keys: keys("e2e4 e7e5 g1f3 b8c6 f1b5"), matching: .namedPositions)
        #expect(ruy?.name == "Ruy Lopez")
        #expect(catalog.classify(keys: keys("g1f3 b8c6 e2e4 e7e5 f1b5"), matching: .namedPositions) == ruy)
    }

    @Test("the deepest match wins")
    func deepestWins() throws {
        let game = keys("e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6 c1e3 e7e5 d4b3")
        let named = try #require(catalog.classifyMatch(keys: game, matching: .namedPositions))
        #expect(named.opening.name == "Sicilian Defense: Najdorf Variation, English Attack")
        #expect(named.index == 10)
        #expect(named.isNamedPosition)
        // With line positions the later moves still belong to the English Attack lines.
        #expect(catalog.classify(keys: game)?.family == "Sicilian Defense")
        // A shorter window stops at shallower names.
        #expect(catalog.classify(keys: game, limit: 9, matching: .namedPositions)?.name == "Sicilian Defense: Najdorf Variation")
        #expect(catalog.classify(keys: game, limit: 4)?.eco == "B50")
        #expect(catalog.classify(keys: game, limit: 1)?.eco == "B20")
        #expect(catalog.classify(keys: game, limit: 0)?.name == "King's Pawn Game")
    }

    @Test("the starting position first does not change the result")
    func withStartingPosition() {
        let moves = keys("e2e4 e7e5 g1f3 b8c6 f1b5 a7a6")
        #expect(catalog.classify(keys: [PolyglotKey.startingPosition] + moves) == catalog.classify(keys: moves))
    }

    @Test("a game that leaves the catalog and comes back later keeps the later match")
    func laterTransposition() throws {
        // 1.Nf3 Nf6 2.c4 e6 3.Nc3 d5 4.d4 — the position of the QGD after 1.d4 d5 2.c4 e6 3.Nc3 Nf6 4.Nf3.
        let game = keys("g1f3 g8f6 c2c4 e7e6 b1c3 d7d5 d2d4")
        let direct = keys("d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 g1f3")
        let match = try #require(catalog.classifyMatch(keys: game))
        #expect(match.index == 6)
        #expect(match.opening == catalog.lookup(key: direct.last!))
    }

    @Test("unknown positions give nil")
    func unknown() {
        #expect(catalog.lookup(key: PolyglotKey.startingPosition) == nil)
        #expect(catalog.lookup(key: PolyglotKey.startingPosition, matching: .namedPositions) == nil)
        #expect(catalog.lookup(key: 0x0123_4567_89AB_CDEF) == nil)
        #expect(catalog.lookup(key: 0) == nil)
        #expect(catalog.classify(keys: []) == nil)
        #expect(catalog.classify(keys: [PolyglotKey.startingPosition, 1, 2, 3]) == nil)
        // A position reached far from any catalog line.
        var board = PolyglotBoard(fen: "8/8/4k3/8/8/4K3/8/8 w - - 0 1")!
        board.play(uci: "e3e4")
        #expect(catalog.lookup(key: board.key) == nil)
    }

    @Test("classification stops at the limit")
    func limit() {
        // 20 quiet knight moves then 1.e4 e5 2.Nf3 Nc6 3.Bb5 (Ruy Lopez) after ply 20.
        let shuffle = Array(repeating: "g1f3 g8f6 f3g1 f6g8", count: 5).joined(separator: " ")
        let game = keys(shuffle + " e2e4 e7e5 g1f3 b8c6 f1b5")
        #expect(catalog.classify(keys: game, limit: 40)?.name == "Ruy Lopez")
        #expect(catalog.classify(keys: game, limit: 22) != catalog.classify(keys: game, limit: 40))
    }
}

@Suite("Format")
struct CatalogFileTests {
    @Test("encode and decode round trip")
    func roundTrip() throws {
        let openings = [
            Opening(id: 0, key: 42, eco: "E99", name: "King's Indian Defense: Orthodox Variation, Classical System", plies: 18),
            Opening(id: 1, key: 7, eco: "A00", name: "Amar Opening", plies: 1),
            Opening(id: 2, key: 9, eco: "A00", name: "Amar Opening", plies: 255),
        ]
        let contents = try CatalogFile.decode(CatalogFile.encode(openings, linePositions: [100: 42, 101: 7]))
        let decoded = contents.openings
        #expect(contents.linePositions == [100: 42, 101: 7])
        let catalog = try OpeningCatalog(openings: decoded, linePositions: contents.linePositions)
        #expect(catalog.lookup(key: 100)?.key == 42)
        #expect(catalog.lookup(key: 100, matching: .namedPositions) == nil)
        #expect(catalog.classifyMatch(keys: [7, 100])?.isNamedPosition == false)
        #expect(catalog.classifyMatch(keys: [7, 100], matching: .namedPositions)?.opening.key == 7)
        #expect(throws: CatalogFile.Error.unknownTarget(5)) { try CatalogFile.encode(openings, linePositions: [100: 5]) }
        #expect(decoded.map(\.key) == [7, 9, 42])
        #expect(decoded.map(\.eco) == ["A00", "A00", "E99"])
        #expect(decoded.map(\.plies) == [1, 255, 18])
        #expect(decoded.last?.variation == "Orthodox Variation, Classical System")
        #expect(throws: CatalogFile.Error.badMagic) { try CatalogFile.decode(Data(repeating: 0, count: 32)) }
        #expect(throws: CatalogFile.Error.duplicateKey(7)) {
            try OpeningCatalog(openings: [openings[1], Opening(id: 3, key: 7, eco: "B00", name: "X", plies: 2)])
        }
    }

    @Test("ECO index")
    func ecoIndex() {
        #expect(Opening.ecoIndex("A00") == 0)
        #expect(Opening.ecoIndex("E99") == 499)
        #expect(Opening.ecoIndex("C42") == 242)
        #expect(Opening.ecoIndex("F00") == nil)
        #expect(Opening.ecoIndex("C4") == nil)
        #expect(Opening.eco(index: 242) == "C42")
    }
}
