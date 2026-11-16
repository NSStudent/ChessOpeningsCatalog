//
//  Replay.swift
//  CatalogTooling
//
//  SAN replay with FischerCore, keys with the package's PolyglotBoard. With `crossCheck` every position is also
//  keyed from FischerCore's FEN through PolyglotKey.key(fen:), so the incremental key and the FEN path must agree.
//

import ChessOpeningsCatalog
@preconcurrency import FischerCore

public struct ReplayFailure: Error, CustomStringConvertible {
    public let ply: Int
    public let san: String
    public let reason: String
    public var description: String { "ply \(ply) «\(san)»: \(reason)" }
}

public enum Replay {
    static let startBoard = PolyglotBoard.start

    /// Keys of the positions after each move (the starting position is not included), up to `limit` plies.
    /// Returns the keys played before the first move that cannot be resolved, plus the failure.
    public static func keys(
        san moves: [Substring],
        limit: Int = .max,
        crossCheck: Bool = false
    ) -> (keys: [UInt64], failure: ReplayFailure?) {
        var game = Game()
        var board = startBoard
        var keys: [UInt64] = []
        keys.reserveCapacity(min(moves.count, limit))
        for (ply, text) in moves.prefix(limit).enumerated() {
            // Parse without FischerCore's lenient normalization (Foundation string replacements, ~60 µs a move);
            // Movetext already strips annotation glyphs, and castling with zeros is mapped here.
            let san = text.hasPrefix("0-0") ? Substring(text.replacingOccurrences(of: "0", with: "O")) : text
            guard let parsed = try? SANMove(san: String(san), options: .strict) else {
                return (keys, ReplayFailure(ply: ply, san: String(text), reason: "unreadable SAN"))
            }
            switch game.resolveResult(parsed) {
            case let .success(resolved):
                do {
                    try game.execute(resolvedMove: resolved, considerHalfmoves: false)
                } catch {
                    return (keys, ReplayFailure(ply: ply, san: String(text), reason: "\(error)"))
                }
                guard board.play(uci: resolved.uci) else {
                    return (keys, ReplayFailure(ply: ply, san: String(text), reason: "PolyglotBoard rejected \(resolved.uci)"))
                }
                if crossCheck {
                    let fen = game.position.fen()
                    let fromFEN = PolyglotKey.key(fen: fen)
                    if fromFEN != board.key {
                        return (keys, ReplayFailure(
                            ply: ply,
                            san: String(text),
                            reason: "key mismatch: board \(hex(board.key)) FEN \(fromFEN.map(hex) ?? "nil") \(fen)"
                        ))
                    }
                }
                keys.append(board.key)
            case let .failure(reason):
                return (keys, ReplayFailure(ply: ply, san: String(text), reason: "\(reason)"))
            }
        }
        return (keys, nil)
    }

    public static func hex(_ key: UInt64) -> String {
        let digits = String(key, radix: 16)
        return "0x" + String(repeating: "0", count: 16 - digits.count) + digits
    }
}

public enum Movetext {
    /// SAN tokens of a PGN movetext: move numbers, results, NAGs, comments, variations and annotation glyphs removed.
    /// Stops after `limit` moves. Works on UTF-8 bytes: every delimiter is ASCII.
    public static func sanMoves(_ text: Substring, limit: Int = .max) -> [Substring] {
        var moves: [Substring] = []
        let utf8 = text.utf8
        var depth = 0          // variation nesting
        var index = utf8.startIndex
        while index < utf8.endIndex, moves.count < limit {
            let byte = utf8[index]
            switch byte {
            case UInt8(ascii: "{"):
                while index < utf8.endIndex, utf8[index] != UInt8(ascii: "}") { utf8.formIndex(after: &index) }
                if index < utf8.endIndex { utf8.formIndex(after: &index) }
            case UInt8(ascii: ";"):
                while index < utf8.endIndex, utf8[index] != UInt8(ascii: "\n") { utf8.formIndex(after: &index) }
            case UInt8(ascii: "("):
                depth += 1
                utf8.formIndex(after: &index)
            case UInt8(ascii: ")"):
                depth = max(0, depth - 1)
                utf8.formIndex(after: &index)
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
                utf8.formIndex(after: &index)
            default:
                var end = index
                while end < utf8.endIndex, !isDelimiter(utf8[end]) { utf8.formIndex(after: &end) }
                let token = text[index..<end]
                index = end
                guard depth == 0 else { continue }
                if let move = sanToken(token) { moves.append(move) }
            }
        }
        return moves
    }

    @inline(__always)
    static func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"),
             UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: ";"):
            true
        default:
            false
        }
    }

    /// The SAN in a token such as `12.Nf3`, `e4!?`, `0-0` or `Qxe7+`; nil for numbers, results and NAGs.
    static func sanToken(_ token: Substring) -> Substring? {
        var token = token
        guard let first = token.utf8.first else { return nil }
        if first == UInt8(ascii: "$") || first == UInt8(ascii: "*") { return nil }
        if token == "1-0" || token == "0-1" || token == "1/2-1/2" { return nil }
        // A leading move number: "12." or "12..." possibly glued to the move. "0-0" is castling, not a number.
        if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(first), !token.hasPrefix("0-0") {
            guard let dot = token.utf8.lastIndex(of: UInt8(ascii: ".")) else { return nil }
            token = token[token.utf8.index(after: dot)...]
        }
        while let last = token.utf8.last, last == UInt8(ascii: "!") || last == UInt8(ascii: "?") {
            token = token.dropLast()
        }
        if token.isEmpty || token == "--" || token == "Z0" { return nil }
        return token
    }
}
