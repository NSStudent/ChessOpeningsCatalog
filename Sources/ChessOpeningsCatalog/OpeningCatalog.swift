//
//  OpeningCatalog.swift
//  ChessOpeningsCatalog
//
//  Lookup of named openings by Polyglot key. The bundled data is the Lichess chess-openings catalog (CC0); see the
//  README. Two kinds of keys are indexed:
//
//  - named positions: the final position of each catalog line (≈3,900);
//  - line positions: the unnamed positions those lines pass through, each pointing at a named opening chosen from the
//    position alone (see the README), so two move orders that meet in the same position get the same opening.
//
//  Lookups go through an open-addressing table built at load time: classifying a game costs one or two probes per
//  position and no allocation until the result is returned.
//

import Foundation

public final class OpeningCatalog: @unchecked Sendable {
    /// Plies a classification looks at by default. The longest catalog line is shorter (see the README).
    public static let defaultLimit = 40

    /// Which keys a lookup or classification uses.
    public enum Matching: Sendable, Hashable {
        /// Only the named positions: exactly the Lichess data, as pgn-extract would use it.
        case namedPositions
        /// Named positions and every position on the catalog lines (the default): transposition-proof.
        case linePositions
    }

    /// Every named entry, sorted by key.
    public let openings: [Opening]
    /// Line positions and the index in ``openings`` each points at, sorted by key.
    public let linePositions: [(key: UInt64, opening: Int)]

    // Open addressing on the low bits of the key (Zobrist keys are uniform). `slotValue` holds entry + 1 (0 = empty),
    // with the top bit set for line positions. Raw pointers, read-only after init: hot loops on every core read them
    // without retain/release.
    private let slotKeys: UnsafeMutablePointer<UInt64>
    private let slotValue: UnsafeMutablePointer<UInt32>
    private let mask: Int
    private static let lineBit: UInt32 = 1 << 31

    /// The catalog bundled with the package.
    public static let shared: OpeningCatalog = {
        guard let url = Bundle.module.url(forResource: "openings", withExtension: "bin") else {
            fatalError("ChessOpeningsCatalog: openings.bin is missing from the bundle")
        }
        do {
            return try OpeningCatalog(data: Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            fatalError("ChessOpeningsCatalog: cannot read openings.bin: \(error)")
        }
    }()

    /// Reads a catalog in the binary format written by ``CatalogFile/encode(_:linePositions:)``.
    public convenience init(data: Data) throws {
        let file = try CatalogFile.decode(data)
        try self.init(openings: file.openings, linePositions: file.linePositions)
    }

    /// Builds a catalog from named entries and line positions (position key → key of a named entry).
    /// Keys must be unique across both; the entries are re-numbered in key order.
    public init(openings entries: [Opening], linePositions lines: [UInt64: UInt64] = [:]) throws {
        let sorted = entries.sorted { $0.key < $1.key }
        guard sorted.count < Int(UInt16.max) else { throw CatalogFile.Error.tooManyEntries }
        for pair in zip(sorted, sorted.dropFirst()) where pair.0.key == pair.1.key {
            throw CatalogFile.Error.duplicateKey(pair.0.key)
        }
        let named = sorted.enumerated().map { index, entry in
            Opening(id: index, key: entry.key, eco: entry.eco, name: entry.name, plies: entry.plies)
        }
        openings = named
        var indexByKey: [UInt64: Int] = [:]
        for opening in named { indexByKey[opening.key] = opening.id }
        var resolved: [(key: UInt64, opening: Int)] = []
        resolved.reserveCapacity(lines.count)
        for (key, target) in lines {
            if indexByKey[key] != nil { throw CatalogFile.Error.duplicateKey(key) }
            guard let index = indexByKey[target] else { throw CatalogFile.Error.unknownTarget(target) }
            resolved.append((key, index))
        }
        resolved.sort { $0.key < $1.key }
        linePositions = resolved

        let total = named.count + resolved.count
        var capacity = 16
        while capacity < total * 2 { capacity <<= 1 }
        mask = capacity - 1
        slotKeys = .allocate(capacity: capacity)
        slotKeys.initialize(repeating: 0, count: capacity)
        slotValue = .allocate(capacity: capacity)
        slotValue.initialize(repeating: 0, count: capacity)
        func insert(_ key: UInt64, _ value: UInt32) {
            var slot = Int(truncatingIfNeeded: key) & mask
            while slotValue[slot] != 0 { slot = (slot + 1) & mask }
            slotKeys[slot] = key
            slotValue[slot] = value
        }
        for opening in named { insert(opening.key, UInt32(opening.id + 1)) }
        for line in resolved { insert(line.key, UInt32(line.opening + 1) | Self.lineBit) }
    }

    deinit {
        slotKeys.deallocate()
        slotValue.deallocate()
    }

    /// Named entries.
    public var count: Int { openings.count }

    // MARK: - Lookup

    /// The opening of the position with this key, or nil. With `.linePositions` (the default) an unnamed position
    /// on a catalog line also answers, with the opening it points at.
    public func lookup(key: UInt64, matching: Matching = .linePositions) -> Opening? {
        let value = slot(for: key, matching: matching)
        return value == 0 ? nil : openings[Int(value & ~Self.lineBit) - 1]
    }

    /// Stored value for `key` (entry + 1, top bit for line positions), or 0.
    @inline(__always)
    private func slot(for key: UInt64, matching: Matching) -> UInt32 {
        var slot = Int(truncatingIfNeeded: key) & mask
        while true {
            let value = slotValue[slot]
            if value == 0 { return 0 }
            if slotKeys[slot] == key {
                if matching == .namedPositions, value & Self.lineBit != 0 { return 0 }
                return value
            }
            slot = (slot + 1) & mask
        }
    }

    // MARK: - Classification

    /// The opening of a game: the catalog position reached last within the first `limit` plies, transpositions
    /// included (the position decides, not the move order). This is how pgn-extract and ChessBase classify.
    ///
    /// - Parameters:
    ///   - keys: Polyglot keys of the game's positions in order. With or without the starting position first:
    ///     it is not in the catalog, so it never matches.
    ///   - limit: Plies to look at; `limit + 1` keys are read so a sequence that starts with the initial
    ///     position still reaches ply `limit`.
    ///   - matching: Named positions only, or also the positions on the catalog lines (the default).
    public func classify(
        keys: [UInt64],
        limit: Int = OpeningCatalog.defaultLimit,
        matching: Matching = .linePositions
    ) -> Opening? {
        classifyMatch(keys: keys, limit: limit, matching: matching)?.opening
    }

    /// Like ``classify(keys:limit:matching:)`` and also says where the match was.
    public func classifyMatch(
        keys: [UInt64],
        limit: Int = OpeningCatalog.defaultLimit,
        matching: Matching = .linePositions
    ) -> OpeningMatch? {
        keys.withUnsafeBufferPointer { classifyMatch(keys: $0, limit: limit, matching: matching) }
    }

    /// Buffer variant for callers that already hold the keys in contiguous memory.
    public func classifyMatch(
        keys: UnsafeBufferPointer<UInt64>,
        limit: Int = OpeningCatalog.defaultLimit,
        matching: Matching = .linePositions
    ) -> OpeningMatch? {
        let end = min(keys.count, limit + 1)
        var best: UInt32 = 0
        var bestAt = -1
        var position = 0
        while position < end {
            let value = slot(for: keys[position], matching: matching)
            if value != 0 {
                best = value
                bestAt = position
            }
            position += 1
        }
        guard best != 0 else { return nil }
        return OpeningMatch(
            opening: openings[Int(best & ~Self.lineBit) - 1],
            index: bestAt,
            isNamedPosition: best & Self.lineBit == 0
        )
    }

    /// Entry index of the classification in ``openings`` (-1 when nothing matches). No allocation and no ARC
    /// traffic: the form to use when classifying millions of games.
    public func classifyIndex(
        keys: UnsafeBufferPointer<UInt64>,
        limit: Int = OpeningCatalog.defaultLimit,
        matching: Matching = .linePositions
    ) -> Int {
        let end = min(keys.count, limit + 1)
        var best: UInt32 = 0
        var position = 0
        while position < end {
            let value = slot(for: keys[position], matching: matching)
            if value != 0 { best = value }
            position += 1
        }
        return Int(best & ~Self.lineBit) - 1
    }

    // MARK: - Shared catalog shortcuts

    /// ``lookup(key:matching:)`` on the bundled catalog.
    public static func lookup(key: UInt64, matching: Matching = .linePositions) -> Opening? {
        shared.lookup(key: key, matching: matching)
    }

    /// ``classify(keys:limit:matching:)`` on the bundled catalog.
    public static func classify(keys: [UInt64], limit: Int = defaultLimit, matching: Matching = .linePositions) -> Opening? {
        shared.classify(keys: keys, limit: limit, matching: matching)
    }
}
