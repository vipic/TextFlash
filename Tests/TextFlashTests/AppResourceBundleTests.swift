import Foundation
import Testing
@testable import TextFlash

struct AppResourceBundleTests {
    @Test func packagedAppCandidatesPreferContentsResources() {
        let appURL = URL(fileURLWithPath: "/Applications/TextFlash.app")
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources")
        let candidates = AppResourceBundle.candidateURLs(bundleURL: appURL, resourceURL: resourcesURL)

        #expect(candidates.count == 3)
        #expect(candidates[0].path == "/Applications/TextFlash.app/Contents/Resources/\(AppResourceBundle.bundleName)")
        #expect(candidates[1].path == "/Applications/TextFlash.app/Contents/Resources/\(AppResourceBundle.bundleName)")
        #expect(candidates[2].path == "/Applications/TextFlash.app/\(AppResourceBundle.bundleName)")
        #expect(candidates.allSatisfy { !$0.path.contains("/Documents/") })
        #expect(candidates.allSatisfy { !$0.path.contains("/.build/") })
    }

    @Test func missingResourceURLStillHasSafeFallbacks() {
        let appURL = URL(fileURLWithPath: "/Applications/TextFlash.app")
        let candidates = AppResourceBundle.candidateURLs(bundleURL: appURL, resourceURL: nil)

        #expect(candidates.count == 2)
        #expect(candidates[0].path.hasSuffix("Contents/Resources/\(AppResourceBundle.bundleName)"))
        #expect(candidates.allSatisfy { !$0.path.contains("/Documents/") })
    }
}
