//
//  Opening.swift
//  ChessOpeningsCatalog
//

/// A named opening position of the catalog.
public struct Opening: Sendable, Hashable, Identifiable {
    /// Index of the entry in its catalog. Stable only within one version of the data.
    public let id: Int
    /// The Polyglot key of the position.
    public let key: UInt64
    /// ECO code, `A00` … `E99`.
    public let eco: String
    /// The full name, for example `Sicilian Defense: Najdorf Variation, English Attack`.
    public let name: String
    /// Half-moves of the catalog line that reaches the position.
    public let plies: Int

    /// The part of the name before «:», for example `Sicilian Defense`.
    public var family: String {
        guard let colon = name.firstIndex(of: ":") else { return name }
        return String(name[..<colon])
    }

    /// The part after «: », for example `Najdorf Variation, English Attack`; nil for a bare family.
    public var variation: String? {
        guard let colon = name.firstIndex(of: ":") else { return nil }
        let rest = name[name.index(after: colon)...].drop(while: { $0 == " " })
        return rest.isEmpty ? nil : String(rest)
    }

    /// The ECO code as a number, `A00` = 0 … `E99` = 499. Two bytes per game when an index stores it.
    public var ecoIndex: UInt16 { Opening.ecoIndex(eco) ?? 0 }

    /// Full moves of the catalog line (`plies` rounded up).
    public var moveCount: Int { (plies + 1) / 2 }

    public init(id: Int, key: UInt64, eco: String, name: String, plies: Int) {
        self.id = id
        self.key = key
        self.eco = eco
        self.name = name
        self.plies = plies
    }

    /// `A00` = 0 … `E99` = 499; nil for anything else.
    public static func ecoIndex(_ eco: some StringProtocol) -> UInt16? {
        let bytes = Array(eco.utf8)
        guard bytes.count == 3,
              (UInt8(ascii: "A")...UInt8(ascii: "E")).contains(bytes[0]),
              (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[1]),
              (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[2]) else { return nil }
        return UInt16(bytes[0] - UInt8(ascii: "A")) * 100 + UInt16(bytes[1] - UInt8(ascii: "0")) * 10
            + UInt16(bytes[2] - UInt8(ascii: "0"))
    }

    /// The code for an index from ``ecoIndex(_:)``.
    public static func eco(index: UInt16) -> String {
        let letter = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8(min(index / 100, 4))))
        let number = index % 100
        return "\(letter)\(number / 10)\(number % 10)"
    }
}

/// Where in a game the catalog matched.
public struct OpeningMatch: Sendable, Hashable {
    public let opening: Opening
    /// Index in the key sequence passed to ``OpeningCatalog/classifyMatch(keys:limit:matching:)``.
    public let index: Int
    /// True when the matched position is the named one itself, false for a transposition that points at it.
    public let isNamedPosition: Bool

    public init(opening: Opening, index: Int, isNamedPosition: Bool) {
        self.opening = opening
        self.index = index
        self.isNamedPosition = isNamedPosition
    }
}
