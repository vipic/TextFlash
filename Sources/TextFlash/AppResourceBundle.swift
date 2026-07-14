import Foundation

/// Resolves the SwiftPM resource bundle without touching the generated
/// `Bundle.module` accessor inside a packaged `.app`.
///
/// SwiftPM hard-codes the developer build path
/// (`…/Documents/…/.build/…/TextFlash_TextFlash.bundle`) as a fallback.
/// Evaluating `Bundle.module` therefore probes `~/Documents` and triggers a
/// Files and Folders TCC prompt on every launch.
enum AppResourceBundle {
    static let bundleName = "TextFlash_TextFlash.bundle"

    static let main: Bundle = {
        for url in candidateURLs(bundleURL: Bundle.main.bundleURL, resourceURL: Bundle.main.resourceURL) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        // Dev / `swift test` only. Never evaluate `.module` inside a shipped .app —
        // that initializer stats the Documents build path and prompts for access.
        if Bundle.main.bundlePath.hasSuffix(".app") {
            Swift.fatalError("Missing \(bundleName) under Contents/Resources")
        }
        return .module
    }()

    static func candidateURLs(bundleURL: URL, resourceURL: URL?) -> [URL] {
        var candidates: [URL] = []

        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleName))
        }

        // Explicit .app layout (resourceURL is usually enough; keep as belt-and-suspenders).
        candidates.append(
            bundleURL
                .appendingPathComponent("Contents/Resources")
                .appendingPathComponent(bundleName)
        )

        // SwiftPM executable layout: bundle sits next to the binary / .app root.
        candidates.append(bundleURL.appendingPathComponent(bundleName))

        return candidates
    }
}
