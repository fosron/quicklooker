import Foundation
import Compression

/// Reader for the ZIP container format (single disk, non ZIP64).
public enum ZIPReader {

    public struct Entry: Sendable {
        public let name: String
        public let method: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let modified: Date?
        public let isDirectory: Bool
        public let crc32: UInt32

        public var methodName: String {
            switch method {
            case 0: return "stored"
            case 8: return "deflate"
            case 9: return "deflate64"
            case 12: return "bzip2"
            case 14: return "lzma"
            case 93: return "zstd"
            case 99: return "aes"
            default: return "method \(method)"
            }
        }
    }

    public enum ArchiveError: Error, LocalizedError {
        case notAnArchive
        case zip64Unsupported
        case encryptedUnsupported
        case corrupted(String)

        public var errorDescription: String? {
            switch self {
            case .notAnArchive: return "The file is not a ZIP archive."
            case .zip64Unsupported: return "ZIP64 archives are not supported."
            case .encryptedUnsupported: return "Encrypted archives are not supported."
            case .corrupted(let reason): return "The archive is corrupted: \(reason)"
            }
        }
    }

    /// Central directory entries, in file order. Directories are included.
    public static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = findEndOfCentralDirectory(bytes) else {
            throw ArchiveError.notAnArchive
        }
        let entryCount = Int(readUInt16(bytes, eocd + 10))
        let centralOffset = Int(readUInt32(bytes, eocd + 16))
        let centralSize = Int(readUInt32(bytes, eocd + 12))

        if centralOffset == 0xFFFF_FFFF || entryCount == 0xFFFF || centralSize == 0xFFFF_FFFF {
            throw ArchiveError.zip64Unsupported
        }

        var entries: [Entry] = []
        var cursor = centralOffset
        var parsed = 0
        while parsed < entryCount, cursor + 46 <= bytes.count {
            guard readUInt32(bytes, cursor) == 0x0201_4b50 else { break }
            let flags = readUInt16(bytes, cursor + 8)
            let method = readUInt16(bytes, cursor + 10)
            let modTime = readUInt16(bytes, cursor + 12)
            let modDate = readUInt16(bytes, cursor + 14)
            let crc = readUInt32(bytes, cursor + 16)
            let compressedSize = Int(readUInt32(bytes, cursor + 20))
            let uncompressedSize = Int(readUInt32(bytes, cursor + 24))
            let nameLength = Int(readUInt16(bytes, cursor + 28))
            let extraLength = Int(readUInt16(bytes, cursor + 30))
            let commentLength = Int(readUInt16(bytes, cursor + 32))
            let externalAttributes = readUInt32(bytes, cursor + 38)

            guard flags & 0x0001 == 0 else { throw ArchiveError.encryptedUnsupported }

            let nameStart = cursor + 46
            guard nameStart + nameLength <= bytes.count else {
                throw ArchiveError.corrupted("truncated file name")
            }
            let nameBytes = Array(bytes[nameStart..<(nameStart + nameLength)])
            let isUTF8 = flags & 0x0800 != 0
            let name = decodeName(nameBytes, isUTF8: isUTF8, nameLength: nameLength)

            let extraStart = nameStart + nameLength
            let extraBytes = extraStart..<min(bytes.count, extraStart + extraLength)
            if extraLength > 0 {
                var extraCursor = extraBytes.lowerBound
                while extraCursor + 4 <= extraBytes.upperBound {
                    let headerID = readUInt16(bytes, extraCursor)
                    let dataSize = Int(readUInt16(bytes, extraCursor + 2))
                    if headerID == 0x0001 {
                        throw ArchiveError.zip64Unsupported
                    }
                    extraCursor += 4 + dataSize
                }
            }

            let isDirectory = name.hasSuffix("/")
                || ((externalAttributes >> 16) & 0xF000) == 0x4000

            entries.append(Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                modified: dosDate(date: modDate, time: modTime),
                isDirectory: isDirectory,
                crc32: crc
            ))
            cursor = extraStart + extraLength + commentLength
            parsed += 1
        }
        return entries
    }

    /// Human readable archive comment, if present.
    public static func comment(in data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let eocd = findEndOfCentralDirectory(bytes) else { return nil }
        let length = Int(readUInt16(bytes, eocd + 20))
        guard length > 0 else { return nil }
        let start = eocd + 22
        guard start + length <= bytes.count else { return nil }
        return String(data: Data(bytes[start..<(start + length)]), encoding: .utf8)
    }

    // MARK: - Helpers

    private static func decodeName(_ bytes: [UInt8], isUTF8: Bool, nameLength: Int) -> String {
        if isUTF8, let name = String(bytes: bytes, encoding: .utf8) {
            return name
        }
        // Bit 11 unset means CP437; a UTF-8 attempt still handles the common case.
        if let name = String(bytes: bytes, encoding: .utf8) {
            return name
        }
        return String(data: Data(bytes), encoding: .isoLatin1) ?? "<name \(nameLength) bytes>"
    }

    static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let minimum = max(0, bytes.count - 22 - 65_535)
        var index = bytes.count - 22
        while index >= minimum {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4b, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    static func dosDate(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var components = DateComponents()
        components.year = Int((date >> 9) & 0x7F) + 1980
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int((time >> 11) & 0x1F)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int(time & 0x1F) * 2
        guard let month = components.month, let day = components.day,
              month >= 1, month <= 12, day >= 1 else { return nil }
        return Calendar(identifier: .gregorian).date(from: components)
    }
}

/// Reader for POSIX / GNU tar archives.
public enum TARReader {

    public struct Entry: Sendable {
        public enum Kind: String, Sendable {
            case file = "file"
            case directory = "directory"
            case symlink = "symlink"
            case hardlink = "hardlink"
            case other = "other"
        }
        public let name: String
        public let size: Int
        public let modified: Date?
        public let kind: Kind
        public let linkTarget: String?
        public let mode: String
    }

    public enum ArchiveError: Error, LocalizedError {
        case notAnArchive
        case sparseUnsupported
        case corrupted(String)

        public var errorDescription: String? {
            switch self {
            case .notAnArchive: return "The file is not a tar archive."
            case .sparseUnsupported: return "Sparse tar archives are not supported."
            case .corrupted(let reason): return "The archive is corrupted: \(reason)"
            }
        }
    }

    public static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 512 else { throw ArchiveError.notAnArchive }
        guard let first = String(bytes: bytes[257..<262], encoding: .utf8), first.hasPrefix("ustar") else {
            throw ArchiveError.notAnArchive
        }

        var entries: [Entry] = []
        var offset = 0
        var pendingLongName: String?
        var pendingLongLink: String?

        while offset + 512 <= bytes.count {
            let block = Array(bytes[offset..<(offset + 512)])
            if block.allSatisfy({ $0 == 0 }) {
                break
            }
            guard let nameField = readString(block, 0, 100) else {
                throw ArchiveError.corrupted("unreadable header at offset \(offset)")
            }
            let prefix = readString(block, 345, 155) ?? ""
            let sizeField = readString(block, 124, 12) ?? "0"
            let size = parseNumeric(sizeField) ?? 0
            let modifiedValue = readString(block, 136, 12).flatMap { parseNumeric($0) }
            let typeFlag = String(UnicodeScalar(block[156] ?? 0))
            let linkName = readString(block, 157, 100)
            let modeValue = readString(block, 100, 8).flatMap { parseNumeric($0) } ?? 0
            let mode = String(format: "%03o", modeValue)

            offset += 512

            switch typeFlag {
            case "L":
                pendingLongName = readPayload(bytes, offset: offset, size: size)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                offset += paddedSize(size)
                continue
            case "K":
                pendingLongLink = readPayload(bytes, offset: offset, size: size)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                offset += paddedSize(size)
                continue
            case "x", "g":
                offset += paddedSize(size)
                continue
            case "S":
                throw ArchiveError.sparseUnsupported
            default:
                break
            }

            var name = pendingLongName ?? (prefix.isEmpty ? nameField : "\(prefix)/\(nameField)")
            pendingLongName = nil
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            var target = pendingLongLink ?? linkName
            pendingLongLink = nil
            target = target?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))

            let kind: Entry.Kind
            switch typeFlag {
            case "5": kind = .directory
            case "2": kind = .symlink
            case "1": kind = .hardlink
            case "0", "7", "\0": kind = .file
            default: kind = .other
            }

            entries.append(Entry(
                name: name,
                size: size,
                modified: modifiedValue.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                kind: kind,
                linkTarget: target?.isEmpty == true ? nil : target,
                mode: mode
            ))
            offset += paddedSize(size)
        }
        return entries
    }

    private static func readPayload(_ bytes: [UInt8], offset: Int, size: Int) -> String? {
        guard size > 0, offset + size <= bytes.count else { return nil }
        return String(bytes: bytes[offset..<(offset + size)], encoding: .utf8)
    }

    private static func paddedSize(_ size: Int) -> Int {
        (size + 511) / 512 * 512
    }

    static func readString(_ block: [UInt8], _ offset: Int, _ length: Int) -> String? {
        guard offset + length <= block.count else { return nil }
        var bytes = Array(block[offset..<(offset + length)])
        if let zero = bytes.firstIndex(of: 0) {
            bytes = Array(bytes[..<zero])
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Handles both octal and GNU base-256 numeric fields.
    static func parseNumeric(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        if trimmed.isEmpty { return 0 }
        if trimmed.hasPrefix("\u{80}") || trimmed.unicodeScalars.first.map({ $0.value > 127 }) == true {
            var value = 0
            for scalar in trimmed.unicodeScalars {
                var byte = Int(scalar.value & 0xFF)
                if value == 0 {
                    byte &= 0x7F
                }
                value = (value << 8) | byte
            }
            return value
        }
        return Int(trimmed, radix: 8)
    }
}

/// GZIP reader built on the Compression framework, with guards against
/// decompression bombs.
public enum GZIPReader {

    public struct Info: Sendable {
        public let originalName: String?
        public let comment: String?
        public let extra: Data?
        public let modified: Date?
        public let os: UInt8
    }

    public enum GZIPError: Error, LocalizedError {
        case notGzip
        case truncatedHeader
        case checksumMismatch
        case decompressionFailed

        public var errorDescription: String? {
            switch self {
            case .notGzip: return "The file is not a GZIP archive."
            case .truncatedHeader: return "The GZIP header is truncated."
            case .checksumMismatch: return "The decompressed data failed its CRC check."
            case .decompressionFailed: return "The data could not be decompressed."
            }
        }
    }

    public struct Result: Sendable {
        public let info: Info
        public let data: Data
        public let originalSize: Int
        public let truncated: Bool
    }

    public static func decompress(_ data: Data, maxBytes: Int) throws -> Result {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { throw GZIPError.truncatedHeader }
        guard bytes[0] == 0x1F, bytes[1] == 0x8B else { throw GZIPError.notGzip }
        let method = bytes[2]
        guard method == 8 else { throw GZIPError.decompressionFailed }

        let flags = bytes[3]
        let modified = Date(timeIntervalSince1970: TimeInterval(readUInt32(bytes, 4)))

        var cursor = 10
        var info = Info(originalName: nil, comment: nil, extra: nil, modified: modified, os: bytes[9])

        if flags & 0x04 != 0 {
            guard cursor + 2 <= bytes.count else { throw GZIPError.truncatedHeader }
            let extraLength = Int(bytes[cursor]) | (Int(bytes[cursor + 1]) << 8)
            cursor += 2
            guard cursor + extraLength <= bytes.count else { throw GZIPError.truncatedHeader }
            info = Info(originalName: info.originalName, comment: info.comment, extra: Data(bytes[cursor..<(cursor + extraLength)]), modified: modified, os: bytes[9])
            cursor += extraLength
        }
        if flags & 0x08 != 0 {
            let (name, next) = readZeroTerminated(bytes, from: cursor)
            info = Info(originalName: name, comment: info.comment, extra: info.extra, modified: modified, os: bytes[9])
            cursor = next
        }
        if flags & 0x10 != 0 {
            let (comment, next) = readZeroTerminated(bytes, from: cursor)
            info = Info(originalName: info.originalName, comment: comment, extra: info.extra, modified: modified, os: bytes[9])
            cursor = next
        }
        if flags & 0x02 != 0 {
            cursor += 2
        }

        guard cursor < bytes.count else { throw GZIPError.truncatedHeader }
        let deflated = bytes[cursor..<(bytes.count - 8)]
        let originalSize = Int(readUInt32(bytes, bytes.count - 4))

        let (output, hitLimit) = try inflate(Data(deflated), maxBytes: maxBytes)
        return Result(info: info, data: output, originalSize: originalSize, truncated: hitLimit)
    }

    private static func readZeroTerminated(_ bytes: [UInt8], from start: Int) -> (String?, Int) {
        var cursor = start
        while cursor < bytes.count, bytes[cursor] != 0 {
            cursor += 1
        }
        let value = String(bytes: bytes[start..<min(cursor, bytes.count)], encoding: .utf8) ?? String(bytes: bytes[start..<min(cursor, bytes.count)], encoding: .isoLatin1)
        return (value, min(cursor + 1, bytes.count))
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    static func inflate(_ data: Data, maxBytes: Int) throws -> (Data, Bool) {
        guard !data.isEmpty else { return (Data(), false) }
        let chunkSize = 256 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        var stream = compression_stream(dst_ptr: buffer, dst_size: chunkSize, src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw GZIPError.decompressionFailed
        }
        defer { compression_stream_destroy(&stream) }

        var output = Data()
        var hitLimit = false

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.src_ptr = base
            stream.src_size = raw.count
            loop: while true {
                stream.dst_ptr = buffer
                stream.dst_size = chunkSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunkSize - stream.dst_size
                if produced > 0 {
                    let remaining = maxBytes - output.count
                    if remaining <= 0 {
                        hitLimit = true
                        break loop
                    }
                    output.append(buffer, count: min(produced, remaining))
                    if produced > remaining {
                        hitLimit = true
                        break loop
                    }
                }
                switch status {
                case COMPRESSION_STATUS_OK:
                    continue loop
                case COMPRESSION_STATUS_END:
                    break loop
                default:
                    if output.isEmpty {
                        throw GZIPError.decompressionFailed
                    }
                    break loop
                }
            }
        }
        return (output, hitLimit)
    }
}
