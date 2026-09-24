# CHECKLIST.md — Progress Tracker

QuickLooker — track progress on PLAN.md below. Check off items as completed.

## Phase 1: Scaffolding
- [x] Xcode project created, main app target set up (`project.yml` → `xcodegen generate`, Xcode project `QuickLooker.xcodeproj`)
- [x] Main app UI: setup instructions screen, extensions list (`Sources/App/SetupView.swift`)
- [x] Shared HTML/CSS renderer module (light/dark adaptive) (`Sources/Core/StyleSheet.swift`, `Document.swift`)
- [x] QLPreviewProvider base class / helper created (`Sources/QuickLookExtension/PreviewProvider.swift`)
- [x] Info.plist declares all supported UTIs/extensions (`Sources/QuickLookExtension/Info.plist`, imported UTIs in `Sources/App/Info.plist`)
- [x] `.gitignore`, build scheme, macOS 15 target set

## Phase 2: Preview Adapters
Single multi-type extension `com.fosron.quicklooker.preview` with a format router
(`PreviewRenderer.detectFormat`) instead of eight separate extensions — one
provider avoids ambiguous Quick Look handler priority between extensions.

### JSON
- [x] `.json` parse + tree render
- [x] `.jsonl` line-split render (record index, per-record trees)
- [x] Parse error fallback (syntax highlighted source + notice)

### YAML / TOML
- [x] YAML render or fallback (custom block parser: mappings, sequences, flow
      collections, block scalars, type hints, line numbers)
- [x] TOML highlighting lexer (tables, array tables, dotted keys, multiline arrays)

### SQLite
- [x] Read-only open helper (`SQLITE_OPEN_READONLY`)
- [x] Schema/tables/indexes listing (columns, indexes, CREATE statement, views)
- [x] Bounded row render (`maxRows`, row count notice)

### Secrets (.env)
- [x] KEY=VALUE parser (export prefix, quotes, comments, malformed lines)
- [x] Secret pattern masking — masked values are never embedded in the preview HTML
- [x] Comment highlighting

### Markdown
- [x] Markdown → HTML renderer (headings, lists, task lists, tables, quotes,
      rules, links, images, fenced code with highlighting)
- [x] Line numbers/source view toggle — source fallback keeps the line gutter;
      rendered view is the default

### Code
- [x] Language regex lexers (Swift, Python, JS/TS, Go, Rust, C/C++, Java/Kotlin,
      Ruby, Shell, CSS, SQL, YAML, TOML, JSON, plain text)
- [x] Line number gutter (CSS counters)
- [x] Adaptive theme CSS (`prefers-color-scheme` + `Appearance` override)

### package.json
- [x] Meta fields extracted (name, version, license, author, engines, private)
- [x] Scripts table
- [x] Dependencies table (dependencies, dev, peer, optional)

### docker-compose
- [x] File name detection (`docker-compose*.yml`, `compose*.yaml`, dotted variants)
- [x] Service cards: image, build context/target, command, entrypoint, restart, user, workdir
- [x] Ports, volumes, depends_on, networks, labels, deploy replicas and resource limits
- [x] Environment table (mapping and list forms) with secret masking
- [x] env_file, profiles, healthcheck
- [x] Top level volumes, networks, secrets, configs
- [x] Fallback to highlighted source when `services` is missing or the YAML is malformed

### composer.json / composer.lock
- [x] Meta fields extracted (name, description, type, license, stability, homepage)
- [x] Authors table (name, email, role)
- [x] require / require-dev / suggest / conflict / replace / provide tables
- [x] autoload, scripts, support, extra sections
- [x] composer.lock package + packages-dev listing with versions and dependency counts

### Archives + Folder Browse
- [x] ZIP entry listing (central directory reader, ratio, method, dates)
- [x] GZIP decompress + text render (Compression framework, nested tar listing)
- [x] TAR listing (ustar + GNU long names, links, modes)
- [x] Folder browse (directory list, sizes, dates)
- [x] Reject ZIP64/split/sparse gracefully (typed errors → source fallback)

## Phase 3: Testing
- [x] XCTest: JSON parser tests (`Tests/CoreTests/JSONTests.swift`)
- [x] XCTest: env masking tests (`Tests/CoreTests/SecretsTests.swift`)
- [x] XCTest: archive entry listing tests (`Tests/CoreTests/ArchiveTests.swift`)
- [x] XCTest: highlight lexer tests (`Tests/CoreTests/SyntaxLexerTests.swift`)
- [x] XCTest: YAML/TOML/Markdown/package.json/SQLite tests
      (`ConfigFormatTests.swift`, `ViewTests.swift`)
- [x] XCTest: composer.json / composer.lock tests (`ComposerTests.swift`)
- [x] XCTest: docker-compose tests (`DockerComposeTests.swift`)
      — **130 tests, all passing**
- [x] Sample fixture files for each type (`Tests/CoreTests/Fixtures/`)
- [ ] Manual: enable extension via System Settings
- [ ] Manual: Finder space-bar preview each supported file

## Phase 4: Packaging
- [ ] Codesigning configured (Developer ID or App Store) — currently ad-hoc
      (`CODE_SIGN_IDENTITY: "-"`); set `DEVELOPMENT_TEAM` in `project.yml`
- [x] App icon created (`Scripts/generate_app_icon.swift` → `Resources/Assets.xcassets/AppIcon.appiconset`)
- [ ] Screenshots for each preview adapter
- [x] Privacy declaration (no data collected) — README + Setup window copy; no
      network entitlements, sandboxed with read-only file access
- [x] Info.plist clean, UTIs valid (`plutil -lint`, extension registers with pluginkit)
- [ ] Build size optimized (static framework keeps the extension small; not measured yet)

## Phase 5: Distribution
- [ ] App Store Connect upload (or direct distribution)
- [x] Versioning scheme (semver, `MARKETING_VERSION` 1.0.0 / build 1)
- [ ] Post-release bug fix plan

## Verification log
- `xcodebuild -project QuickLooker.xcodeproj -scheme QuickLooker test` → 130/130 pass
- Release build: ad-hoc signed app + extension, `codesign --verify --deep --strict` passes
- Extension registers with LaunchServices: `pluginkit -m -i com.fosron.quicklooker.preview` → `+`
- Known environment issue: `qlmanage` crashes for *any* third-party preview
  extension on this macOS build (reproduced with QLMarkdown), so extension
  previews must be verified interactively in Finder (space bar).
