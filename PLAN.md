# PLAN.md — QuickLooker

QuickLooker — clone of "QuickLook Pro: File Preview" (apps.apple.com/us/app/quicklook-pro-file-preview/id6812534537). macOS app bundle + embedded Quick Look extensions. All processing local. No accounts, no uploads.

## 0. Prior Art — sbarex/SourceCodeSyntaxHighlight

Existing OSS project (GPL-3.0): github.com/sbarex/SourceCodeSyntaxHighlight. Covers code/text highlighting for hundreds of formats via bundled `highlight` engine (app + QLExtension + XPC service pattern). Overlaps our Code adapter and text-highlight fallback for JSON/YAML/TOML/.env.

Gaps it does NOT cover (our differentiators):
- JSON/JSONL structured tree (it does text-highlight only)
- SQLite schema/tables/index browse
- .env secret masking
- package.json structured summary
- ZIP/GZIP/tar archive listing + folder browse
- Markdown rendered output (author delegates to QLMarkdown)

Decision: use it as architecture reference. Option A: build all custom per plan. Option B: integrate `highlight` engine for the Code adapter to get mature highlighting for free. Recommended: Option B for Code; custom adapters for everything else.

## 1. Research Summary

Original app features:

- JSON tree explorer and JSONL record browser
- YAML/TOML pretty formatting (fallback: highlighted text)
- SQLite table/schema/index browser (read-only)
- env file preview with likely secrets masked
- Markdown rendered or source code with syntax highlight + line numbers
- package.json overview (name, version, scripts, deps)
- composer.json / composer.lock overview (PHP Composer; added during implementation)
- docker-compose service overview (added during implementation)
- Folder browser (session navigation) without extraction
- ZIP, GZIP, tar archive listings
- macOS 15+ target
- Bounded previews for large files

## 2. Architecture

```
QuickLooker.app
├── Main App (Swift, AppKit/SwiftUI)
│   └── Setup screen: enable extensions in System Settings → Extensions → Quick Look
└── Extensions (per format family)
    ├── JSONPreview      → .json, .jsonl
    ├── ConfigPreview    → .yaml, .yml, .toml
    ├── SQLitePreview    → .sqlite, .db
    ├── SecretsPreview   → .env
    ├── MarkdownPreview  → .md
    ├── CodePreview      → .swift, .py, .js, .ts, .go, .rs, .c, .h, .cpp, etc.
    ├── PackagePreview   → package.json
    └── ArchivePreview   → .zip, .gz, .tar
```

Use data-based Quick Look preview extensions (`QLPreviewProvider`) — preferred over view controller-based, sandbox-friendly. Return HTML via `QLPreviewReply` formatted attachments for rich rendering.

## 3. Technology Stack

- Swift 5.9+, Xcode 15+
- macOS target: 15.0+
- Rendering: HTML embedded in QLPreviewReply (Q&R formatting) + inline CSS
- SQLite access: `sqlite3` C library via module
- Syntax highlighting: bundle `highlight` engine (per sbarex/SourceCodeSyntaxHighlight) via XPC service, fallback regex-based lexer
- JSON parsing: `Foundation` `JSONSerialization` / `Codable`
- Archive support: `libarchive` via `Compression`/Archive lib (e.g. `SWCompression` or `ZipArchive`) — bundle via SPM
- Testing: XCTest for parsers per format

## 4. Feature Modules

### 4.1 Main App
- Single window: instructions how to enable extensions (System Settings path)
- List of supported extensions with descriptions
- App can quit after enabling; extensions continue working

### 4.2 JSON / JSONL
- Parse file content
- Render expandable tree: objects, arrays replacement; keys bolded
- JSONL: split lines, each rendered as separate record; show index
- Fallback: print raw on parse error

### 4.3 YAML / TOML
- Basic parsing: try `Yams` (YAML lib) if format fits, fallback to syntax-highlighted text
- TOML: custom regex highlighting (sections, keys, values)
- Show formatted structure if parsed

### 4.4 SQLite
- Open read-only (`SQLITE_OPEN_READONLY`)
- List tables, indexes, schema (CREATE statements)
- Render first N rows per table (bounded)
- Sandboxing: use security-scoped URL properly

### 4.5 Secrets (.env)
- Parse lines KEY=VALUE
- Mask values that match secret patterns (password, key, token, secret, api, etc.)
- Show masked by default, reveal toggle in HTML (JS) optional
- Highlight comments (#)

### 4.6 Markdown
- Render Markdown to HTML (use `Down`, `MarkdownUI` renderer lib or custom parser for subset: headings, lists, code fences)
- Show formatted HTML output
- Line numbers + mono font for source view toggle

### 4.7 Code
- Language-level lexer per supported grammar (subset regex highlighting)
- Keywords, strings, comments, numbers, attributes
- Line numbers in gutter
- Monospace font, dark/light adaptive via CSS `prefers-color-scheme`

### 4.8 package.json
- Extract: name, version, description, license, author
- scripts table (name → command)
- dependencies table (name → version)
- devDependencies count
- Render as styled summary

### 4.9 Archives (ZIP/GZIP/tar) + Folder Browse
- ZIP: list entries with name, size, compressed ratio, modified date
- GZIP: decompress in memory (limit size), render content as text (fallback: binary info)
- TAR: list entries
- Folder browse: list directory with file names, sizes
- Unsupported: ZIP64, split archives, sparse tar

## 5. UX / Constraint Rules

- All processing local (no network)
- Bounded previews: large files truncate at N bytes/N entries
- Adaptive light/dark theming in HTML output
- macOS 15+ deployment target
- No sandbox escape: purely extension preview, user-driven Finder
- Respect Apple's file association priority; test standard CSV doesn't conflict

## 6. Build Phases

- Phase 1: Scaffolding — main app, QLPreviewProvider skeleton, common HTML/CSS renderer
- Phase 2: Formats — implement each preview adapter independently in own target/extension or single multi-type extension
- Phase 3: Testing — unit tests for parsers, UI test for extension enablement, sample fixtures
- Phase 4: Packaging — codesigning, App Store metadata, screenshots, privacy declaration
- Phase 5: Distribution — App Store Connect upload or direct distribution

## 7. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| QLPreviewReply size limits | Truncate + paginate in HTML (JS) |
| Sandbox file access restrictions | QLFilePreviewRequest passes URL; limit to supported types |
| SQLite corruption/format variance | Read-only open, error handling for malformed DBs |
| Archive bombs (ZIP/GZIP) | Bounded decompression limits, reject >N bytes |
| HTML injection in JSON/.env | Escape all user content |
| macOS extension enablement UX friction | Clear setup app + README + screenshots |
