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
    /// Keys of the positions after each move (the starting position is not included), up to `limit` plies.
    /// Returns the keys played before the first move that cannot be resolved, plus the failure.
    public static func keys(
        san moves: [Substring],
        limit: Int = .max,
        crossCheck: Bool = false
    ) -> (keys: [UInt64], failure: ReplayFailure?) {
        var game = Game()
        var board = PolyglotBoard.start
        var keys: [UInt64] = []
        keys.reserveCapacity(min(moves.count, limit))
        for (ply, text) in moves.prefix(limit).enumerated() {
            switch game.resolveResult(san: String(text)) {
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
    /// Stops after `limit` moves.
    public static func sanMoves(_ text: Substring, limit: Int = .max) -> [Substring] {
        var moves: [Substring] = []
        var depth = 0          // variation nesting
        var inBrace = false
        var index = text.startIndex
        while index < text.endIndex, moves.count < limit {
            let character = text[index]
            if inBrace {
                if character == "}" { inBrace = false }
                index = text.index(after: index)
                continue
            }
            switch character {
            case "{":
                inBrace = true
                index = text.index(after: index)
            case ";":
                // Comment to end of line.
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
            case "(":
                depth += 1
                index = text.index(after: index)
            case ")":
                depth = max(0, depth - 1)
                index = text.index(after: index)
            case " ", "\n", "\r", "\t":
                index = text.index(after: index)
            default:
                var end = index
                while end < text.endIndex, !" \n\r\t{}();".contains(text[end]) { end = text.index(after: end) }
                let token = text[index..<end]
                index = end
                guard depth == 0 else { continue }
                if let move = sanToken(token) { moves.append(move) }
            }
        }
        return moves
    }

    /// The SAN in a token such as `12.Nf3`, `e4!?` or `Qxe7+`; nil for numbers, results and NAGs.
    static func sanToken(_ token: Substring) -> Substring? {
        var token = token
        if token.first == "$" { return nil }
        if token == "1-0" || token == "0-1" || token == "1/2-1/2" || token == "*" { return nil }
        // Strip a leading move number: "12." or "12..." possibly glued to the move.
        if let first = token.first, first.isNumber {
            guard let dot = token.lastIndex(of: ".") else { return nil }
            token = token[token.index(after: dot)...]
        }
        while let last = token.last, "!?".contains(last) { token = token.dropLast() }
        if token.isEmpty || token == "--" || token == "Z0" { return nil }
        return token
    }
}
