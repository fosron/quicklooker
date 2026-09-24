# QuickLooker

Rich Quick Look previews for code and data files on macOS. A macOS app bundle
plus an embedded Quick Look preview extension. All processing happens locally:
no accounts, no network, no uploads.

## Supported formats

| Family | Extensions | Preview |
| --- | --- | --- |
| JSON | `.json` | Collapsible tree with type colored values |
| JSON Lines | `.jsonl`, `.ndjson` | One record per line, numbered, expandable |
| YAML | `.yaml`, `.yml` | Parsed tree with inferred types and line numbers |
| TOML | `.toml` | Tables, array tables, dotted keys, type hints |
| Environment | `.env`, `.env.*` | KEY=VALUE list, likely secrets masked |
| SQLite | `.sqlite`, `.sqlite3`, `.db` | Read-only tables, indexes, schema, row preview |
| Markdown | `.md`, `.markdown` | Rendered HTML with highlighted code fences |
| package.json | `package.json` | Metadata, scripts, dependency tables |
| Composer | `composer.json`, `composer.lock` | Metadata, authors, require tables; lock file package set |
| Docker Compose | `docker-compose*.yml`, `compose*.yaml` | Services, images/builds, ports, volumes, masked environment, networks |
| Source code | `.swift`, `.py`, `.js`, `.ts`, `.go`, `.rs`, `.c`, `.h`, `.cpp`, … | Syntax highlighting with line numbers |
| Archives | `.zip`, `.tar`, `.gz`, `.tgz` | Entry listings, gzip payload preview |
| Folders | any directory | Item listing with sizes and dates |

Every adapter falls back to syntax highlighted source when a structured parse
fails, and every preview is bounded (bytes, depth, node count, entries, rows).

## Layout

```
Sources/Core/              QuickLookCore framework (parsers + HTML renderers)
Sources/App/               Menu bar-less setup app
Sources/QuickLookExtension/QLPreviewProvider data-based extension
Tests/CoreTests/           XCTest suite + fixtures
Scripts/                   Icon generator
project.yml                XcodeGen spec (source of truth for the project)
```

## Build

The Xcode project is generated, not committed:

```sh
brew install xcodegen          # once
xcodegen generate
xcodebuild -project QuickLooker.xcodeproj -scheme QuickLooker build
```

Run the tests:

```sh
xcodebuild -project QuickLooker.xcodeproj -scheme QuickLooker test
```

Or with SwiftPM for the core library only:

```sh
swift test
```

## Install and enable

1. Build the Release configuration.
2. Move `QuickLooker.app` to `/Applications` and launch it once.
3. System Settings → General → Login Items & Extensions → Quick Look → enable
   **QuickLooker** (the app has an *Open Settings* button).
4. Press space on a supported file in Finder.

Local development builds are ad-hoc signed. Set `DEVELOPMENT_TEAM` in
`project.yml` and regenerate to produce a Developer ID signed build for
distribution.

## Notes

- SQLite databases are opened with `SQLITE_OPEN_READONLY`; previewing never
  mutates a file. Every statement runs under a wall clock deadline and views
  are never counted, so a recursive view cannot hang the preview.
- ZIP listings are read from the end of central directory record, so archives
  larger than the read window still list correctly.
- `.env` values that match secret naming patterns are masked, and the unmasked
  value is never written into the preview document.
- Archives are parsed in memory; ZIP64, split archives and sparse tar entries
  are rejected with a clear message instead of being partially parsed.
- Gzip payloads are capped by `PreviewLimits.maxDecompressedBytes` to guard
  against decompression bombs.
- Previews are offline by construction: the HTML carries a strict
  Content-Security-Policy and Markdown never emits a remote image request.

## Verifying previews

`Scripts/verify_previews.swift` renders every supported fixture through the same
code path the extension uses and reports the renderer, summary and HTML size:

```sh
swiftc -F <path-to-QuickLookCore.framework> -framework QuickLookCore \
  Scripts/verify_previews.swift -o /tmp/verify_previews
DYLD_FRAMEWORK_PATH=<framework-dir> /tmp/verify_previews Tests/CoreTests/Fixtures
```

Quick Look selects an extension by UTI, so the extension's
`QLSupportedContentTypes` must contain the type the system resolves for a file
(or a type that file's type conforms to). `Tests/CoreTests/Fixtures` covers one
file per claimed type; the resolved UTIs are:

| File | Resolved UTI | Matched by |
| --- | --- | --- |
| `.json`, `package.json`, `composer.json` | `public.json` | direct |
| `.jsonl`, `.ndjson` | `com.fosron.quicklooker.jsonl` | direct (or `public.json` conformance) |
| `.yaml`, `.yml`, compose files | `public.yaml` | direct |
| `.toml` | `public.toml` | direct |
| `.env` | `com.fosron.quicklooker.dotenv` | direct (or `public.plain-text` conformance) |
| `.md`, `.markdown` | `net.daringfireball.markdown` | direct |
| `.swift`, `.js`, `.ts`, `.c`, `.go`, `.rs`, … | `public.source-code` conformance | conformance |
| `.py` | `public.python-script` | direct |
| `.csv` | `public.comma-separated-values-text` | direct |
| `.ini` | `com.microsoft.ini` | direct |
| `.txt`, `.text` | `public.plain-text` | direct |
| `.sqlite`, `.sqlite3`, `.db` | `org.sqlite.sqlite` | direct |
| `.zip`, `.jar`, `.epub` | `public.zip-archive` | direct |
| `.tar` | `public.tar-archive` | direct |
| `.gz`, `.tgz` | `org.gnu.gnu-zip-archive` | direct |

## Known environment issue

On this macOS build `qlmanage -p` crashes for any third-party Quick Look
extension (`ExtensionFoundation` nil-key exception), including unrelated
extensions such as QLMarkdown. Use Finder's space bar to verify previews.
