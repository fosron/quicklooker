import Foundation
import SQLite3

/// Read-only SQLite browser: table list, schema, indexes and a bounded row
/// preview per table.
public final class SQLiteDatabase {

    public struct Column: Sendable, Equatable {
        public let name: String
        public let type: String
        public let isPrimaryKey: Bool
        public let notNull: Bool
    }

    public struct ObjectInfo: Sendable, Equatable {
        public let name: String
        public let kind: String
        public let tableName: String?
        public let sql: String?
    }

    public struct RowPreview: Sendable {
        public let columns: [String]
        public let rows: [[String]]
        public let totalRows: Int
        public let sampledRows: Int
    }

    private var handle: OpaquePointer?
    private let path: String

    public enum OpenError: Error, LocalizedError {
        case cannotOpen(String)
        case notADatabase
        case queryFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotOpen(let reason): return "Could not open the database: \(reason)"
            case .notADatabase: return "The file is not a SQLite database."
            case .queryFailed(let reason): return "Query failed: \(reason)"
            }
        }
    }

    /// Opens the database read-only so previewing can never mutate the file.
    public init(path: String) throws {
        self.path = path
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw OpenError.cannotOpen(message)
        }
        self.handle = database
    }

    /// Verifies the SQLite header before doing any real work.
    public static func isValidDatabase(data: Data) -> Bool {
        let magic = Array("SQLite format 3\0".utf8)
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    public func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    deinit {
        close()
    }

    // MARK: - Queries

    public func objects() throws -> [ObjectInfo] {
        let sql = """
        SELECT name, type, tbl_name, sql
        FROM sqlite_master
        WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
        ORDER BY type DESC, name COLLATE NOCASE
        """
        return try query(sql) { statement in
            ObjectInfo(
                name: self.text(statement, 0) ?? "",
                kind: self.text(statement, 1) ?? "",
                tableName: self.text(statement, 2),
                sql: self.text(statement, 3)
            )
        }
    }

    public func indexes(table: String) throws -> [ObjectInfo] {
        let sql = """
        SELECT name, type, tbl_name, sql
        FROM sqlite_master
        WHERE type = 'index' AND tbl_name = ?1 AND name NOT LIKE 'sqlite_%'
        ORDER BY name COLLATE NOCASE
        """
        return try query(sql, bind: [table]) { statement in
            ObjectInfo(
                name: self.text(statement, 0) ?? "",
                kind: self.text(statement, 1) ?? "",
                tableName: self.text(statement, 2),
                sql: self.text(statement, 3)
            )
        }
    }

    /// Convenience for tests and previews: number of rows in a table.
    public func rowCount(table: String) throws -> Int {
        let sql = "SELECT COUNT(*) FROM \(quoteIdentifier(table))"
        return try query(sql) { statement in
            Int(sqlite3_column_int64(statement, 0))
        }.first ?? 0
    }

    /// Loads at most `limit` rows. When `sampleRows` is larger than zero the
    /// column type names are derived from that many rows instead of the full
    /// table, which keeps previews fast on large databases.
    public func preview(table: String, limit: Int, sampleRows: Int = 0, skipCount: Bool = false) throws -> RowPreview {
        var total = 0
        if !skipCount {
            total = try rowCount(table: table)
        }
        let sql = "SELECT * FROM \(quoteIdentifier(table)) LIMIT \(max(0, limit))"
        var columns: [String] = []
        var rows: [[String]] = []
        try execute(sql) { statement in
            let columnCount = Int(sqlite3_column_count(statement))
            for index in 0..<columnCount {
                columns.append(String(cString: sqlite3_column_name(statement, Int32(index))))
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String] = []
                for index in 0..<columnCount {
                    row.append(self.value(statement, Int32(index)))
                }
                rows.append(row)
            }
        }
        if skipCount {
            total = rows.count
        }
        return RowPreview(columns: columns, rows: rows, totalRows: total, sampledRows: max(0, sampleRows))
    }

    public func columns(table: String) throws -> [Column] {
        let sql = "PRAGMA table_info(\(quoteIdentifier(table)))"
        return try query(sql) { statement in
            Column(
                name: self.text(statement, 1) ?? "",
                type: (self.text(statement, 2) ?? "").uppercased(),
                isPrimaryKey: sqlite3_column_int(statement, 5) != 0,
                notNull: sqlite3_column_int(statement, 3) != 0
            )
        }
    }

    // MARK: - Statement plumbing

    private func execute(_ sql: String, bind: [String] = [], _ body: (OpaquePointer) throws -> Void) throws {
        guard let handle else { throw OpenError.cannotOpen("database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw OpenError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bind.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        try body(statement)
    }

    private func query<T>(_ sql: String, bind: [String] = [], _ transform: (OpaquePointer) -> T) throws -> [T] {
        var results: [T] = []
        try execute(sql, bind: bind) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(transform(statement))
            }
        }
        return results
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private func value(_ statement: OpaquePointer, _ column: Int32) -> String {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return "\(sqlite3_column_int64(statement, column))"
        case SQLITE_FLOAT:
            let double = sqlite3_column_double(statement, column)
            if double.rounded() == double, abs(double) < 1e15 {
                return String(format: "%.0f", double)
            }
            return String(double)
        case SQLITE_TEXT:
            let text = self.text(statement, column) ?? ""
            if text.count > 4_000 {
                let head = String(text.prefix(2_000))
                let tail = String(text.suffix(200))
                return "\(head)\n… (\(Format.integer(text.count)) chars) …\n\(tail)"
            }
            return text
        case SQLITE_BLOB:
            let bytes = Int(sqlite3_column_bytes(statement, column))
            return "<blob \(Format.bytes(bytes))>"
        case SQLITE_NULL:
            return "NULL"
        default:
            return ""
        }
    }

    func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Rendering

public enum SQLiteBuilder {

    /// In-memory variant for callers that only hold the file data.
    public static func render(context: RenderContext) throws -> RenderedPreview {
        try renderInMemory(context)
    }

    /// File based variant used by the Quick Look extension.
    public static func render(context: RenderContext, fileURL: URL) throws -> RenderedPreview {
        guard SQLiteDatabase.isValidDatabase(data: context.data) else {
            throw OpenError.notADatabase
        }
        let database = try SQLiteDatabase(path: fileURL.path)
        defer { database.close() }
        return try render(database: database, context: context)
    }

    /// In-memory variant for tests and for callers that only hold data.
    public static func renderInMemory(_ context: RenderContext) throws -> RenderedPreview {
        guard SQLiteDatabase.isValidDatabase(data: context.data) else {
            throw OpenError.notADatabase
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlp-\(UUID().uuidString).sqlite")
        try context.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try SQLiteDatabase(path: url.path)
        defer { database.close() }
        return try render(database: database, context: context)
    }

    enum OpenError: Error, LocalizedError {
        case notADatabase

        var errorDescription: String? {
            "The file is not a valid SQLite database."
        }
    }

    public static func render(database: SQLiteDatabase, context: RenderContext) throws -> RenderedPreview {
        let objects = try database.objects()
        let tables = objects.filter { $0.kind == "table" }
        let views = objects.filter { $0.kind == "view" }

        var html = ""

        if tables.isEmpty && views.isEmpty {
            html += "<div class=\"empty\">No tables found in this database.</div>"
        }

        for table in tables {
            html += try tableSection(database: database, object: table, context: context)
        }
        for view in views {
            html += try tableSection(database: database, object: view, context: context)
        }

        let summary = "\(Format.integer(tables.count)) tables\(views.isEmpty ? "" : " · \(Format.integer(views.count)) views") · \(Format.bytes(context.data.count))"
        return RenderedPreview(renderer: "SQLite", summary: summary, html: html)
    }

    private static func tableSection(database: SQLiteDatabase, object: SQLiteDatabase.ObjectInfo, context: RenderContext) throws -> String {
        var html = ""
        let isView = object.kind == "view"
        let icon = isView ? "👁" : "▦"
        html += Document.section("\(icon) \(object.name)")

        // Schema
        var details: [(String, String)] = []
        if let columns = try? database.columns(table: object.name), !columns.isEmpty {
            let columnText = columns.map { column -> String in
                var text = column.name
                if !column.type.isEmpty { text += " \(column.type)" }
                if column.isPrimaryKey { text += " PK" }
                if column.notNull { text += " NOT NULL" }
                return text
            }.joined(separator: ", ")
            details.append(("columns", columnText))
        }
        if let indexes = try? database.indexes(table: object.name), !indexes.isEmpty {
            details.append(("indexes", indexes.map(\.name).joined(separator: ", ")))
        }
        if let sql = object.sql {
            details.append(("create", sql.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if !details.isEmpty {
            html += "<div class=\"kv\" style=\"margin-bottom:10px\">"
            for (key, value) in details {
                html += "<div class=\"k\">\(HTML.escape(key))</div><div class=\"mono\">\(HTML.escape(Format.ellipsizeMiddle(value, limit: 400)))</div>"
            }
            html += "</div>"
        }

        // Rows
        let preview = try database.preview(table: object.name, limit: context.limits.maxRows, sampleRows: context.limits.maxRows)
        if preview.rows.isEmpty {
            html += "<div class=\"empty\">No rows.</div>"
        } else {
            let headers = preview.columns
            let rows = preview.rows.map { row in
                row.map { cell in
                    if cell == "NULL" {
                        return Document.Cell(html: "<span class=\"tok-null\">NULL</span>")
                    }
                    if cell.hasPrefix("<blob ") {
                        return Document.Cell(html: "<span class=\"meta\">\(HTML.escape(cell))</span>")
                    }
                    return Document.Cell(cell)
                }
            }
            html += Document.table(headers: headers, rows: rows)
            let shown = preview.rows.count
            if preview.totalRows > shown {
                html += "<div class=\"meta\" style=\"margin-top:6px\">Showing \(Format.integer(shown)) of \(Format.integer(preview.totalRows)) rows.</div>"
            } else {
                html += "<div class=\"meta\" style=\"margin-top:6px\">\(Format.integer(shown)) row\(shown == 1 ? "" : "s").</div>"
            }
        }
        return html
    }
}
