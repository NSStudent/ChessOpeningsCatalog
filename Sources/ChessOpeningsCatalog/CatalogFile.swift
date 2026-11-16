//
//  CatalogFile.swift
//  ChessOpeningsCatalog
//
//  Binary format of openings.bin, little endian, columns sorted by key:
//
//    0   magic "OPCT"            4 bytes
//    4   version                 UInt16 (1)
//    6   reserved                UInt16
//    8   entry count N           UInt32
//    12  name count M            UInt32
//    16  name bytes B            UInt32
//    20  line position count L   UInt32
//    24  keys                    N × UInt64 (ascending)
//        eco                     N × UInt16 (A00 = 0 … E99 = 499)
//        name index              N × UInt16
//        plies                   N × UInt8
//        name offsets            (M + 1) × UInt32 into the name bytes
//        name bytes              B bytes of UTF-8
//        line position keys      L × UInt64 (ascending)
//        line position targets   L × UInt16 (entry index)
//

import Foundation

public enum CatalogFile {
    public static let magic: [UInt8] = Array("OPCT".utf8)
    public static let version: UInt16 = 1

    public enum Error: Swift.Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt16)
        case truncated
        case badEntry(Int)
        case duplicateKey(UInt64)
        case tooManyEntries
        case unknownTarget(UInt64)
    }

    /// The decoded contents: named entries in key order and line positions (position key → named key).
    public struct Contents: Sendable {
        public var openings: [Opening]
        public var linePositions: [UInt64: UInt64]
    }

    /// Writes `openings` (any order) and the line positions (position key → key of a named entry) in the binary
    /// format. Names are stored once each.
    public static func encode(_ openings: [Opening], linePositions: [UInt64: UInt64] = [:]) throws -> Data {
        let sorted = openings.sorted { $0.key < $1.key }
        guard sorted.count < Int(UInt16.max) else { throw Error.tooManyEntries }
        var names: [String] = []
        var nameIndex: [String: Int] = [:]
        for opening in sorted where nameIndex[opening.name] == nil {
            nameIndex[opening.name] = names.count
            names.append(opening.name)
        }
        guard names.count < Int(UInt16.max) else { throw Error.tooManyEntries }
        var nameBytes: [UInt8] = []
        var offsets: [UInt32] = [0]
        for name in names {
            nameBytes.append(contentsOf: name.utf8)
            offsets.append(UInt32(nameBytes.count))
        }

        var data = Data()
        data.append(contentsOf: magic)
        append(version, to: &data)
        append(UInt16(0), to: &data)
        append(UInt32(sorted.count), to: &data)
        append(UInt32(names.count), to: &data)
        append(UInt32(nameBytes.count), to: &data)
        append(UInt32(linePositions.count), to: &data)
        for opening in sorted { append(opening.key, to: &data) }
        for opening in sorted {
            guard let eco = Opening.ecoIndex(opening.eco) else { throw Error.badEntry(opening.id) }
            append(eco, to: &data)
        }
        for opening in sorted { append(UInt16(nameIndex[opening.name]!), to: &data) }
        for opening in sorted {
            guard (0...255).contains(opening.plies) else { throw Error.badEntry(opening.id) }
            data.append(UInt8(opening.plies))
        }
        for offset in offsets { append(offset, to: &data) }
        data.append(contentsOf: nameBytes)
        var indexByKey: [UInt64: Int] = [:]
        for (index, opening) in sorted.enumerated() { indexByKey[opening.key] = index }
        let lines = linePositions.sorted { $0.key < $1.key }
        for line in lines {
            guard indexByKey[line.key] == nil else { throw Error.duplicateKey(line.key) }
            append(line.key, to: &data)
        }
        for line in lines {
            guard let index = indexByKey[line.value] else { throw Error.unknownTarget(line.value) }
            append(UInt16(index), to: &data)
        }
        return data
    }

    /// Reads the binary format.
    public static func decode(_ data: Data) throws -> Contents {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> Contents in
            guard raw.count >= 24 else { throw Error.truncated }
            guard Array(raw[0..<4]) == magic else { throw Error.badMagic }
            let fileVersion = raw.loadUnaligned(fromByteOffset: 4, as: UInt16.self).littleEndian
            guard fileVersion == version else { throw Error.unsupportedVersion(fileVersion) }
            let count = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian)
            let nameCount = Int(raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian)
            let nameByteCount = Int(raw.loadUnaligned(fromByteOffset: 16, as: UInt32.self).littleEndian)
            let lineCount = Int(raw.loadUnaligned(fromByteOffset: 20, as: UInt32.self).littleEndian)

            let keysAt = 24
            let ecoAt = keysAt + 8 * count
            let nameIndexAt = ecoAt + 2 * count
            let pliesAt = nameIndexAt + 2 * count
            let offsetsAt = pliesAt + count
            let bytesAt = offsetsAt + 4 * (nameCount + 1)
            let lineKeysAt = bytesAt + nameByteCount
            let lineTargetsAt = lineKeysAt + 8 * lineCount
            guard raw.count >= lineTargetsAt + 2 * lineCount else { throw Error.truncated }

            var names: [String] = []
            names.reserveCapacity(nameCount)
            for index in 0..<nameCount {
                let start = Int(raw.loadUnaligned(fromByteOffset: offsetsAt + 4 * index, as: UInt32.self).littleEndian)
                let end = Int(raw.loadUnaligned(fromByteOffset: offsetsAt + 4 * index + 4, as: UInt32.self).littleEndian)
                guard start <= end, end <= nameByteCount else { throw Error.badEntry(index) }
                let slice = UnsafeRawBufferPointer(rebasing: raw[(bytesAt + start)..<(bytesAt + end)])
                names.append(String(decoding: slice, as: UTF8.self))
            }

            var openings: [Opening] = []
            openings.reserveCapacity(count)
            for index in 0..<count {
                let key = raw.loadUnaligned(fromByteOffset: keysAt + 8 * index, as: UInt64.self).littleEndian
                let eco = raw.loadUnaligned(fromByteOffset: ecoAt + 2 * index, as: UInt16.self).littleEndian
                let name = Int(raw.loadUnaligned(fromByteOffset: nameIndexAt + 2 * index, as: UInt16.self).littleEndian)
                let plies = Int(raw[pliesAt + index])
                guard eco < 500, name < nameCount else { throw Error.badEntry(index) }
                openings.append(Opening(id: index, key: key, eco: Opening.eco(index: eco), name: names[name], plies: plies))
            }
            var lines: [UInt64: UInt64] = [:]
            lines.reserveCapacity(lineCount)
            for index in 0..<lineCount {
                let key = raw.loadUnaligned(fromByteOffset: lineKeysAt + 8 * index, as: UInt64.self).littleEndian
                let target = Int(raw.loadUnaligned(fromByteOffset: lineTargetsAt + 2 * index, as: UInt16.self).littleEndian)
                guard target < openings.count else { throw Error.badEntry(index) }
                lines[key] = openings[target].key
            }
            return Contents(openings: openings, linePositions: lines)
        }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
