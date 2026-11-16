//
//  PolyglotKey.swift
//  ChessOpeningsCatalog
//
//  The 64-bit Zobrist key Polyglot `.bin` books are sorted by, computed from a FEN/EPD or move by move from UCI
//  moves. Pieces are numbered black pawn 0, white pawn 1, black knight 2 … white king 11; squares a1 = 0 … h8 = 63.
//  The en passant file only counts when a pawn of the side to move stands next to the pawn that just moved two
//  squares (pseudo-legal, as the specification says: a pinned pawn still counts).
//

public enum PolyglotKey {
    /// The key of the standard starting position, `0x463b96181691fc9c`.
    public static let startingPosition: UInt64 = 0x463B_9618_1691_FC9C

    /// The key of the position in `fen`. Accepts a full FEN or an EPD (the first four fields are enough).
    /// Returns `nil` when the placement, side to move, castling or en passant field cannot be read.
    public static func key(fen: some StringProtocol) -> UInt64? {
        var board = PolyglotBoard.empty
        guard board.load(fen: String(fen)) else { return nil }
        return board.key
    }
}

/// A minimal mailbox board that keeps the Polyglot key up to date while UCI moves are played on it.
///
/// It trusts the moves: there is no legality check. It is enough to replay opening lines and test fixtures without
/// a chess engine; the app passes the keys its own codec already computes.
public struct PolyglotBoard: Sendable, Hashable {
    /// Polyglot piece index (0–11) per square, or -1.
    private var squares: [Int8]
    private var whiteToMove: Bool
    /// Bits: 1 white king side, 2 white queen side, 4 black king side, 8 black queen side.
    private var castling: UInt8
    /// The square a pawn just skipped over (any double push), or nil.
    private var enPassantTarget: Int?

    /// The key of the current position.
    public private(set) var key: UInt64

    /// The standard starting position.
    public static var start: PolyglotBoard {
        var board = PolyglotBoard.empty
        _ = board.load(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        return board
    }

    static var empty: PolyglotBoard {
        PolyglotBoard(squares: Array(repeating: -1, count: 64), whiteToMove: true, castling: 0, enPassantTarget: nil, key: 0)
    }

    /// Creates a board from a FEN or EPD; nil when it cannot be read.
    public init?(fen: String) {
        self = .empty
        guard load(fen: fen) else { return nil }
    }

    private init(squares: [Int8], whiteToMove: Bool, castling: UInt8, enPassantTarget: Int?, key: UInt64) {
        self.squares = squares
        self.whiteToMove = whiteToMove
        self.castling = castling
        self.enPassantTarget = enPassantTarget
        self.key = key
    }

    /// Plays a UCI move such as `e2e4`, `e1g1` (castling) or `e7e8q`. Returns false for malformed text or when
    /// there is no piece on the start square; the board is unchanged then.
    @discardableResult
    public mutating func play(uci: some StringProtocol) -> Bool {
        let bytes = Array(uci.utf8)
        guard bytes.count == 4 || bytes.count == 5,
              let from = Self.square(bytes[0], bytes[1]),
              let to = Self.square(bytes[2], bytes[3]) else { return false }
        var promotion: Int?
        if bytes.count == 5 {
            switch bytes[4] {
            case UInt8(ascii: "n"): promotion = 1
            case UInt8(ascii: "b"): promotion = 2
            case UInt8(ascii: "r"): promotion = 3
            case UInt8(ascii: "q"): promotion = 4
            default: return false
            }
        }
        return play(from: from, to: to, promotionType: promotion)
    }

    /// Plays a move given by squares (a1 = 0 … h8 = 63). `promotionType` is the Polyglot piece type
    /// (knight 1, bishop 2, rook 3, queen 4). Castling is the king moving two squares.
    @discardableResult
    public mutating func play(from: Int, to: Int, promotionType: Int? = nil) -> Bool {
        guard (0..<64).contains(from), (0..<64).contains(to) else { return false }
        let piece = Int(squares[from])
        guard piece >= 0 else { return false }
        let type = piece / 2
        let isWhite = piece % 2 == 1

        removeEnPassantAndCastlingFromKey()

        // Captures, including en passant.
        if squares[to] >= 0 {
            toggle(Int(squares[to]), on: to)
        } else if type == 0, from % 8 != to % 8, to == enPassantTarget {
            let captured = isWhite ? to - 8 : to + 8
            toggle(Int(squares[captured]), on: captured)
            squares[captured] = -1
        }

        // Move the piece (promoting when asked).
        toggle(piece, on: from)
        squares[from] = -1
        let placed = promotionType.map { $0 * 2 + (isWhite ? 1 : 0) } ?? piece
        squares[to] = Int8(placed)
        toggle(placed, on: to)

        // Castling moves the rook too.
        if type == 5, abs(to - from) == 2 {
            let (rookFrom, rookTo) = to > from ? (from + 3, from + 1) : (from - 4, from - 1)
            let rook = Int(squares[rookFrom])
            if rook >= 0 {
                toggle(rook, on: rookFrom)
                squares[rookFrom] = -1
                squares[rookTo] = Int8(rook)
                toggle(rook, on: rookTo)
            }
        }

        // Castling rights lost by moving or capturing on the king and rook squares.
        for square in [from, to] {
            switch square {
            case 4: castling &= ~0b0011
            case 7: castling &= ~0b0001
            case 0: castling &= ~0b0010
            case 60: castling &= ~0b1100
            case 63: castling &= ~0b0100
            case 56: castling &= ~0b1000
            default: break
            }
        }

        enPassantTarget = (type == 0 && abs(to - from) == 16) ? (from + to) / 2 : nil
        whiteToMove.toggle()
        key ^= PolyglotRandom.table[780]
        addEnPassantAndCastlingToKey()
        return true
    }

    // MARK: - FEN

    fileprivate mutating func load(fen: String) -> Bool {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 4 else { return false }
        var rank = 7
        var file = 0
        for character in fields[0] {
            if character == "/" {
                guard file == 8, rank > 0 else { return false }
                rank -= 1
                file = 0
            } else if let skip = character.wholeNumberValue {
                file += skip
                guard file <= 8 else { return false }
            } else {
                guard file < 8, let piece = Self.pieceIndex(character) else { return false }
                squares[rank * 8 + file] = Int8(piece)
                file += 1
            }
        }
        guard rank == 0, file == 8 else { return false }

        switch fields[1] {
        case "w": whiteToMove = true
        case "b": whiteToMove = false
        default: return false
        }

        castling = 0
        if fields[2] != "-" {
            for character in fields[2] {
                switch character {
                case "K": castling |= 1
                case "Q": castling |= 2
                case "k": castling |= 4
                case "q": castling |= 8
                default: return false
                }
            }
        }

        if fields[3] == "-" {
            enPassantTarget = nil
        } else {
            let bytes = Array(fields[3].utf8)
            guard bytes.count == 2, let square = Self.square(bytes[0], bytes[1]) else { return false }
            enPassantTarget = square
        }

        key = 0
        for square in 0..<64 where squares[square] >= 0 {
            key ^= PolyglotRandom.table[64 * Int(squares[square]) + square]
        }
        if whiteToMove { key ^= PolyglotRandom.table[780] }
        addEnPassantAndCastlingToKey()
        return true
    }

    // MARK: - Key helpers

    private mutating func toggle(_ piece: Int, on square: Int) {
        key ^= PolyglotRandom.table[64 * piece + square]
    }

    private mutating func removeEnPassantAndCastlingFromKey() {
        addEnPassantAndCastlingToKey() // XOR is its own inverse.
    }

    private mutating func addEnPassantAndCastlingToKey() {
        for bit in 0..<4 where castling & (1 << bit) != 0 {
            key ^= PolyglotRandom.table[768 + bit]
        }
        if let file = enPassantFileForKey() {
            key ^= PolyglotRandom.table[772 + file]
        }
    }

    /// The en passant file when a pawn of the side to move stands next to the pawn that just moved two squares.
    private func enPassantFileForKey() -> Int? {
        guard let target = enPassantTarget else { return nil }
        let file = target % 8
        let pushedRank = whiteToMove ? 4 : 3
        let capturer = whiteToMove ? 1 : 0
        for neighbour in [file - 1, file + 1] where (0..<8).contains(neighbour) {
            if Int(squares[pushedRank * 8 + neighbour]) == capturer {
                return file
            }
        }
        return nil
    }

    private static func square(_ file: UInt8, _ rank: UInt8) -> Int? {
        guard (UInt8(ascii: "a")...UInt8(ascii: "h")).contains(file),
              (UInt8(ascii: "1")...UInt8(ascii: "8")).contains(rank) else { return nil }
        return Int(rank - UInt8(ascii: "1")) * 8 + Int(file - UInt8(ascii: "a"))
    }

    private static func pieceIndex(_ character: Character) -> Int? {
        let type: Int
        switch character.lowercased() {
        case "p": type = 0
        case "n": type = 1
        case "b": type = 2
        case "r": type = 3
        case "q": type = 4
        case "k": type = 5
        default: return nil
        }
        return type * 2 + (character.isUppercase ? 1 : 0)
    }
}
