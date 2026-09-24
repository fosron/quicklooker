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
    ///
    /// Only the end of central directory record and the central directory are
    /// read, so a large archive never needs to be loaded into memory in full.
    public static func entries(in data: Data) throws -> [Entry] {
        guard let eocd = findEndOfCentralDirectory(data) else {
            throw ArchiveError.notAnArchive
        }
        let entryCount = Int(readUInt16(data, eocd + 10))
        let centralOffset = Int(readUInt32(data, eocd + 16))
        let centralSize = Int(readUInt32(data, eocd + 12))

        if centralOffset == 0xFFFF_FFFF || entryCount == 0xFFFF || centralSize == 0xFFFF_FFFF {
            throw ArchiveError.zip64Unsupported
        }

        guard centralOffset >= 0, centralSize >= 0,
              centralOffset + centralSize <= data.count else {
            throw ArchiveError.corrupted("central directory is outside the read window")
        }
        let directory = data[centralOffset..<(centralOffset + centralSize)]
        return try parseCentralDirectory(directory, entryCount: entryCount)
    }

    /// File backed variant. Reads the EOCD and central directory by seeking so
    /// archives larger than the preview read limit still list correctly, and
    /// also handles archives whose central directory sits past the truncation
    /// point of `data` (the provider reads the head plus the tail).
    public static func entries(fileURL: URL, data: Data) throws -> [Entry] {
        if hasCompleteCentralDirectory(data) {
            return try entries(in: data)
        }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw ArchiveError.notAnArchive
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize >= 22 else { throw ArchiveError.notAnArchive }

        let tailLength = min(UInt64(66_000), fileSize)
        try handle.seek(toOffset: fileSize - tailLength)
        guard let tail = try handle.read(upToCount: Int(tailLength)) else {
            throw ArchiveError.notAnArchive
        }
        guard let eocdInTail = findEndOfCentralDirectory(tail) else {
            throw ArchiveError.notAnArchive
        }

        let entryCount = Int(readUInt16(tail, eocdInTail + 10))
        let centralOffsetValue = readUInt32(tail, eocdInTail + 16)
        let centralSize = Int(readUInt32(tail, eocdInTail + 12))
        if centralOffsetValue == 0xFFFF_FFFF || entryCount == 0xFFFF || centralSize == 0xFFFF_FFFF {
            throw ArchiveError.zip64Unsupported
        }
        let centralOffset = UInt64(centralOffsetValue)
        guard centralOffset < fileSize else {
            throw ArchiveError.corrupted("central directory offset is outside the file")
        }
        let available = Int(min(UInt64(centralSize), fileSize - centralOffset, UInt64(256 * 1024 * 1024)))
        try handle.seek(toOffset: centralOffset)
        guard let directory = try handle.read(upToCount: max(available, 46)) else {
            throw ArchiveError.corrupted("central directory could not be read")
        }
        return try parseCentralDirectory(directory, entryCount: entryCount)
    }

    /// True when `data` contains a complete central directory for a ZIP file.
    private static func hasCompleteCentralDirectory(_ data: Data) -> Bool {
        guard let eocd = findEndOfCentralDirectory(data) else { return false }
        let entryCount = Int(readUInt16(data, eocd + 10))
        let centralOffset = Int(readUInt32(data, eocd + 16))
        let centralSize = Int(readUInt32(data, eocd + 12))
        guard centralOffset != 0xFFFF_FFFF, entryCount != 0xFFFF, centralSize != 0xFFFF_FFFF else {
            return false
        }
        return centralOffset + centralSize <= data.count && centralOffset >= 0 && centralSize >= 0
    }

    private static func parseCentralDirectory(_ slice: Data, entryCount: Int) throws -> [Entry] {
        // Normalise to a zero based Data: slices keep the parent's indices and
        // the offset arithmetic below assumes index == offset.
        let data = slice.startIndex == slice.endIndex ? Data() : Data(slice)
        var entries: [Entry] = []
        var cursor = 0
        var parsed = 0
        while parsed < entryCount, cursor + 46 <= data.count {
            guard readUInt32(data, cursor) == 0x0201_4b50 else { break }
            let flags = readUInt16(data, cursor + 8)
            let method = readUInt16(data, cursor + 10)
            let modTime = readUInt16(data, cursor + 12)
            let modDate = readUInt16(data, cursor + 14)
            let crc = readUInt32(data, cursor + 16)
            let compressedSize = Int(readUInt32(data, cursor + 20))
            let uncompressedSize = Int(readUInt32(data, cursor + 24))
            let nameLength = Int(readUInt16(data, cursor + 28))
            let extraLength = Int(readUInt16(data, cursor + 30))
            let commentLength = Int(readUInt16(data, cursor + 32))
            let externalAttributes = readUInt32(data, cursor + 38)

            guard flags & 0x0001 == 0 else { throw ArchiveError.encryptedUnsupported }

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else {
                throw ArchiveError.corrupted("truncated file name")
            }
            let nameBytes = data[nameStart..<(nameStart + nameLength)]
            let isUTF8 = flags & 0x0800 != 0
            let name = decodeName(nameBytes, isUTF8: isUTF8, nameLength: nameLength)

            let extraStart = nameStart + nameLength
            if extraLength > 0 {
                var extraCursor = extraStart
                let extraEnd = min(data.count, extraStart + extraLength)
                while extraCursor + 4 <= extraEnd {
                    let headerID = readUInt16(data, extraCursor)
                    let dataSize = Int(readUInt16(data, extraCursor + 2))
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
        guard let eocd = findEndOfCentralDirectory(data) else { return nil }
        let length = Int(readUInt16(data, eocd + 20))
        guard length > 0, eocd + 22 + length <= data.count else { return nil }
        return String(data: data[(eocd + 22)..<(eocd + 22 + length)], encoding: .utf8)
    }

    // MARK: - Helpers

    private static func decodeName(_ bytes: Data, isUTF8: Bool, nameLength: Int) -> String {
        if isUTF8, let name = String(data: bytes, encoding: .utf8) {
            return name
        }
        // Bit 11 unset means CP437; a UTF-8 attempt still handles the common case.
        if let name = String(data: bytes, encoding: .utf8) {
            return name
        }
        return String(data: bytes, encoding: .isoLatin1) ?? "<name \(nameLength) bytes>"
    }

    public static func findEndOfCentralDirectory(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minimum = max(0, data.count - 22 - 65_535)
        var index = data.count - 22
        while index >= minimum {
            let base = data.startIndex + index
            if data[base] == 0x50, data[base + 1] == 0x4B, data[base + 2] == 0x05, data[base + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
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
            // Size and mtime are raw numeric fields: they may be octal or GNU
            // base-256, so they must not be decoded as text first.
            let size = parseNumericBytes(block, offset: 124, length: 12) ?? 0
            let modifiedValue = parseNumericBytes(block, offset: 136, length: 12)
            let typeFlag = String(UnicodeScalar(block[156]))
            let linkName = readString(block, 157, 100)
            let modeValue = parseNumericBytes(block, offset: 100, length: 8) ?? 0
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

    /// Reads a numeric header field. Octal fields are NUL or space terminated;
    /// GNU base-256 fields carry a 0x80 marker, which may sit after leading
    /// sign extension bytes (`00 00 00 00 00 00 00 80 …` for large positives).
    static func parseNumericBytes(_ block: [UInt8], offset: Int, length: Int) -> Int? {
        guard offset >= 0, length > 0, offset + length <= block.count else { return nil }
        let field = Array(block[offset..<(offset + length)])
        if let marker = field.firstIndex(where: { $0 & 0x80 != 0 }) {
            var value = 0
            for (index, byte) in field[marker...].enumerated() {
                value = (value << 8) | Int(index == 0 ? byte & 0x7F : byte)
            }
            return value
        }
        let digits = field.prefix { $0 >= 0x30 && $0 <= 0x37 }
        guard !digits.isEmpty else { return 0 }
        return Int(String(bytes: digits, encoding: .ascii) ?? "", radix: 8)
    }

    /// Handles both octal and GNU base-256 numeric fields.
    static func parseNumeric(_ text: String) -> Int? {
        parseNumericBytes(Array(text.utf8), offset: 0, length: text.utf8.count)
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

        // The 8 byte trailer (CRC32 + ISIZE) must still be present. A header
        // with a filename, comment or header CRC can otherwise run to the end
        // of the file and make the deflate range invalid.
        guard cursor <= bytes.count - 8 else { throw GZIPError.truncatedHeader }
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
