// Renders every supported file type through the same code path the Quick Look
// extension uses and reports what the preview would contain.
//
// Usage: swift Scripts/verify_previews.swift [fixture-directory]
import Foundation
import QuickLookCore

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Tests/CoreTests/Fixtures")

let files = [
    "sample.json", "sample.jsonl", "sample.yaml", "sample.toml", "sample.env",
    "package.json", "composer.json", "composer.lock",
    "docker-compose.yml", "docker-compose.dev.yml",
    "sample.md", "sample.swift", "sample.py", "sample.js", "sample.csv",
    "sample.ini", "sample.txt", "sample.sqlite", "sample.db",
    "sample.zip", "sample.tar",
    "sample.txt.gz", "sample.tar.gz",
]

var failures = 0
for name in files {
    let url = directory.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else {
        print("✗ \(name): missing fixture")
        failures += 1
        continue
    }
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier ?? ""
    let context = RenderContext(
        data: data,
        fileName: name,
        contentTypeIdentifier: type,
        fileURL: url
    )
    do {
        let preview = try PreviewRenderer.render(context: context)
        let html = PreviewRenderer.renderHTML(context: context)
        let wellFormed = html.hasPrefix("<!DOCTYPE html>") && html.hasSuffix("</html>\n") || html.contains("</html>")
        let noScript = !html.contains("<script")
        let marker = wellFormed && noScript && preview.html.count > 40 ? "✓" : "✗"
        if marker == "✗" { failures += 1 }
        print("\(marker) \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(preview.renderer.padding(toLength: 16, withPad: " ", startingAt: 0)) \(preview.summary.padding(toLength: 42, withPad: " ", startingAt: 0)) html=\(html.count)B")
    } catch {
        failures += 1
        print("✗ \(name): \(error.localizedDescription)")
    }
}
print(failures == 0 ? "\nall previews rendered" : "\n\(failures) failures")
exit(failures == 0 ? 0 : 1)
