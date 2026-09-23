import Foundation

/// Builds the single stylesheet shared by every preview adapter.
///
/// The document is themed with CSS custom properties so the same markup works
/// in light and dark mode. Syntax coloring uses the same class names as the
/// code lexer (`tok-keyword`, `tok-string`, …).
public enum StyleSheet {

    public static func document(
        title: String,
        appearance: Appearance,
        header: String,
        body: String,
        footer: String
    ) -> String {
        let schemeRule: String
        switch appearance {
        case .auto:
            schemeRule = ":root { color-scheme: light dark; \(variables(light: true)) }\n"
                + "@media (prefers-color-scheme: dark) { :root { \(variables(light: false)) } }"
        case .light:
            schemeRule = ":root { color-scheme: light; \(variables(light: true)) }"
        case .dark:
            schemeRule = ":root { color-scheme: dark; \(variables(light: false)) }"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(HTML.escape(title))</title>
        <style>
        \(schemeRule)
        \(base)
        \(components)
        </style>
        </head>
        <body>
        <header class="qlp-header">\(header)</header>
        <main class="qlp-body">
        \(body)
        </main>
        \(footer.isEmpty ? "" : "<footer class=\"qlp-footer\">\(footer)</footer>")
        </body>
        </html>
        """
    }

    static func variables(light: Bool) -> String {
        if light {
            return """
            --bg: #ffffff;
            --bg-elevated: #f6f7f9;
            --bg-code: #f6f8fa;
            --fg: #1d1d1f;
            --fg-muted: #6b7280;
            --fg-subtle: #9ca3af;
            --border: #e3e6ea;
            --border-strong: #d0d5db;
            --accent: #0a66c2;
            --accent-soft: rgba(10, 102, 194, 0.10);
            --key: #1d4ed8;
            --string: #0f7b3f;
            --number: #b45309;
            --boolean: #7c3aed;
            --null: #9ca3af;
            --comment: #6b7280;
            --keyword: #a21caf;
            --type: #0e7490;
            --attribute: #b45309;
            --punctuation: #4b5563;
            --line: #d8dce1;
            --shadow: 0 1px 2px rgba(16, 24, 40, 0.06);
            --danger: #b42318;
            --warn: #b45309;
            --ok: #0f7b3f;
            """
        }
        return """
        --bg: #1c1c1e;
        --bg-elevated: #242426;
        --bg-code: #202124;
        --fg: #f2f2f4;
        --fg-muted: #a1a1a6;
        --fg-subtle: #7d7d82;
        --border: #333336;
        --border-strong: #45454a;
        --accent: #6cb2ff;
        --accent-soft: rgba(108, 178, 255, 0.14);
        --key: #8ab4ff;
        --string: #7ee2a8;
        --number: #ffb86b;
        --boolean: #c9a6ff;
        --null: #8e8e93;
        --comment: #8e8e93;
        --keyword: #f0a6ff;
        --type: #6ed3e8;
        --attribute: #ffb86b;
        --punctuation: #b6bcc6;
        --line: #3a3a3d;
        --shadow: 0 1px 2px rgba(0, 0, 0, 0.4);
        --danger: #ff8a80;
        --warn: #ffb86b;
        --ok: #7ee2a8;
        """
    }

    private static let base = """
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
        margin: 0;
        background: var(--bg);
        color: var(--fg);
        font: 13px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
        word-break: break-word;
    }
    .qlp-header {
        position: sticky;
        top: 0;
        z-index: 3;
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
        padding: 10px 16px;
        background: var(--bg-elevated);
        border-bottom: 1px solid var(--border);
    }
    .qlp-header .title {
        font-weight: 600;
        font-size: 13px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        max-width: 46ch;
    }
    .qlp-header .spacer { flex: 1 1 auto; }
    .qlp-body { padding: 16px; }
    .qlp-footer {
        padding: 10px 16px 24px;
        color: var(--fg-subtle);
        font-size: 11px;
        border-top: 1px solid var(--border);
        margin-top: 24px;
    }
    .badge {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 2px 8px;
        border-radius: 999px;
        background: var(--accent-soft);
        color: var(--accent);
        font-size: 11px;
        font-weight: 600;
        white-space: nowrap;
    }
    .badge.warn { background: rgba(180, 83, 9, 0.12); color: var(--warn); }
    .badge.muted { background: var(--bg-code); color: var(--fg-muted); }
    .meta { color: var(--fg-muted); font-size: 11px; }
    code, pre, .mono {
        font: 12px/1.55 ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace;
    }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    h1, h2, h3 { line-height: 1.25; }
    .notice {
        display: flex;
        gap: 8px;
        align-items: flex-start;
        margin: 0 0 14px;
        padding: 10px 12px;
        border: 1px solid var(--border);
        border-left: 3px solid var(--warn);
        border-radius: 6px;
        background: var(--bg-elevated);
        color: var(--fg-muted);
        font-size: 12px;
    }
    """

    private static let components = """
    /* ---------- trees (JSON / YAML / TOML) ---------- */
    .tree { font: 12px/1.6 ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace; }
    .tree details { margin: 0; }
    .tree summary {
        cursor: default;
        list-style: none;
        display: inline-flex;
        align-items: baseline;
        gap: 4px;
        border-radius: 4px;
    }
    .tree summary::-webkit-details-marker { display: none; }
    .tree summary::before {
        content: "▸";
        color: var(--fg-subtle);
        font-size: 9px;
        display: inline-block;
        width: 9px;
        transform: translateY(-1px);
    }
    .tree details[open] > summary::before { content: "▾"; }
    .tree .node { position: relative; margin-left: 14px; padding-left: 0; }
    .tree .node::before {
        content: "";
        position: absolute;
        left: -8px;
        top: 2px;
        bottom: 2px;
        width: 1px;
        background: var(--line);
    }
    .tree .leaf { margin-left: 23px; position: relative; padding-left: 0; }
    .tree .leaf::before {
        content: "";
        position: absolute;
        left: -8px;
        top: 2px;
        bottom: 2px;
        width: 1px;
        background: var(--line);
    }
    .tree .children { margin-left: 8px; }
    .tree .more { color: var(--fg-subtle); font-style: italic; }
    .tree summary .line { display: block; }
    .tree .record-separator { border-top: 1px dashed var(--line); margin: 8px 0; }
    .tree .key { color: var(--key); }
    .tree .index { color: var(--fg-subtle); }
    .tree .colon { color: var(--fg-muted); }
    .tree .count { color: var(--fg-subtle); font-size: 11px; }
    .tree .line { padding: 0 4px; border-radius: 4px; }
    .tree .line:hover { background: var(--bg-elevated); }
    .tok-string { color: var(--string); }
    .tok-number { color: var(--number); }
    .tok-boolean { color: var(--boolean); }
    .tok-null { color: var(--null); font-style: italic; }
    .tok-keyword { color: var(--keyword); }
    .tok-type { color: var(--type); }
    .tok-comment { color: var(--comment); font-style: italic; }
    .tok-attribute { color: var(--attribute); }
    .tok-punctuation { color: var(--punctuation); }
    .tok-key { color: var(--key); }

    /* ---------- tables ---------- */
    table.grid {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        background: var(--bg);
        border: 1px solid var(--border);
        border-radius: 8px;
        overflow: hidden;
    }
    table.grid th, table.grid td {
        text-align: left;
        padding: 6px 10px;
        border-bottom: 1px solid var(--border);
        vertical-align: top;
    }
    table.grid th {
        background: var(--bg-elevated);
        color: var(--fg-muted);
        font-weight: 600;
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.04em;
    }
    table.grid tr:last-child td { border-bottom: none; }
    table.grid td.num, table.grid th.num { text-align: right; font-variant-numeric: tabular-nums; }
    table.grid tr:hover td { background: var(--bg-elevated); }
    .table-scroll { overflow-x: auto; border-radius: 8px; }
    .table-scroll.bounded { max-height: 65vh; overflow: auto; }
    .more { color: var(--fg-subtle); font-style: italic; padding: 8px 2px; }

    /* ---------- code ---------- */
    .code {
        counter-reset: codeline;
        background: var(--bg-code);
        border: 1px solid var(--border);
        border-radius: 8px;
        overflow-x: auto;
        padding: 10px 0;
        font: 12px/1.55 ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace;
        tab-size: 4;
    }
    .code pre { margin: 0; }
    .code .ln {
        display: block;
        white-space: pre;
        padding: 0 14px 0 0;
    }
    .code .ln::before {
        counter-increment: codeline;
        content: counter(codeline);
        display: inline-block;
        width: 3.2em;
        margin-right: 14px;
        padding-right: 10px;
        text-align: right;
        color: var(--fg-subtle);
        border-right: 1px solid var(--line);
        user-select: none;
    }
    .code .ln:hover { background: var(--accent-soft); }

    /* ---------- cards / summaries ---------- */
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 10px; margin-bottom: 16px; }
    .card {
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 10px 12px;
        background: var(--bg-elevated);
        box-shadow: var(--shadow);
        overflow: hidden;
    }
    .card .label { color: var(--fg-subtle); font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; }
    .card .value { font-weight: 600; font-size: 13px; margin-top: 2px; }
    .section { margin: 20px 0 8px; font-size: 12px; font-weight: 600; color: var(--fg-muted); text-transform: uppercase; letter-spacing: 0.06em; }
    .empty { color: var(--fg-subtle); font-size: 12px; font-style: italic; padding: 6px 0; }

    /* ---------- .env reveal toggle ---------- */
    .env .reveal-toggle { position: absolute; opacity: 0; pointer-events: none; }
    .env .env-toolbar { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
    .env .reveal-button {
        cursor: pointer;
        user-select: none;
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 3px 10px;
        border: 1px solid var(--border-strong);
        border-radius: 999px;
        font-size: 11px;
        color: var(--fg-muted);
        background: var(--bg);
    }
    .env .reveal-button::before { content: "Reveal values"; }
    .env .reveal-toggle:checked ~ .env-toolbar .reveal-button::before { content: "Hide values"; }
    .env .env-revealed { display: none; }
    .env .reveal-toggle:checked ~ .env-masked { display: none; }
    .env .reveal-toggle:checked ~ .env-revealed { display: block; }
    .env .env-line { display: block; white-space: pre-wrap; padding: 0 14px; }
    .env .env-ln {
        display: inline-block;
        width: 2.6em;
        margin-right: 12px;
        color: var(--fg-subtle);
        text-align: right;
        user-select: none;
    }
    .env .env-key { color: var(--key); }
    .env .env-equals { color: var(--fg-muted); }
    .env .warn-text { color: var(--warn); }

    /* ---------- markdown ---------- */
    .markdown { max-width: 88ch; }
    .markdown h1 { font-size: 22px; border-bottom: 1px solid var(--border); padding-bottom: 6px; }
    .markdown h2 { font-size: 18px; border-bottom: 1px solid var(--border); padding-bottom: 4px; margin-top: 24px; }
    .markdown h3 { font-size: 15px; margin-top: 20px; }
    .markdown h4, .markdown h5, .markdown h6 { font-size: 13px; margin-top: 16px; }
    .markdown code { background: var(--bg-code); border: 1px solid var(--border); border-radius: 4px; padding: 1px 5px; }
    .markdown pre { background: var(--bg-code); border: 1px solid var(--border); border-radius: 8px; padding: 10px 12px; overflow-x: auto; }
    .markdown pre code { background: none; border: none; padding: 0; }
    .markdown blockquote {
        margin: 10px 0;
        padding: 2px 14px;
        border-left: 3px solid var(--border-strong);
        color: var(--fg-muted);
    }
    .markdown table { border-collapse: collapse; font-size: 12px; }
    .markdown table th, .markdown table td { border: 1px solid var(--border); padding: 5px 10px; }
    .markdown img { max-width: 100%; }
    .markdown hr { border: none; border-top: 1px solid var(--border); margin: 20px 0; }
    .markdown ul, .markdown ol { padding-left: 22px; }
    .markdown li { margin: 2px 0; }
    .markdown li.task { list-style: none; margin-left: -18px; }
    .markdown del { color: var(--fg-subtle); }

    /* ---------- raw / error ---------- */
    .raw {
        white-space: pre-wrap;
        background: var(--bg-code);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 10px 12px;
        font: 12px/1.55 ui-monospace, "SF Mono", Menlo, monospace;
    }
    .error {
        display: flex;
        gap: 10px;
        align-items: flex-start;
        padding: 12px 14px;
        border: 1px solid var(--border);
        border-left: 3px solid var(--danger);
        border-radius: 6px;
        background: var(--bg-elevated);
    }
    .error .glyph { font-size: 16px; line-height: 1.2; }
    .error .message { font-size: 12px; color: var(--fg-muted); }
    .kv { display: grid; grid-template-columns: max-content 1fr; gap: 4px 16px; font-size: 12px; }
    .kv .k { color: var(--fg-muted); }
    .scroll { max-height: 70vh; overflow: auto; }
    """
}
