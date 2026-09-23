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
  mutates a file.
- `.env` values that match secret naming patterns are masked, and the unmasked
  value is never written into the preview document.
- Archives are parsed in memory; ZIP64, split archives and sparse tar entries
  are rejected with a clear message instead of being partially parsed.
- Gzip payloads are capped by `PreviewLimits.maxDecompressedBytes` to guard
  against decompression bombs.

## Known environment issue

On this macOS build `qlmanage -p` crashes for any third-party Quick Look
extension (`ExtensionFoundation` nil-key exception), including unrelated
extensions such as QLMarkdown. Use Finder's space bar to verify previews.
