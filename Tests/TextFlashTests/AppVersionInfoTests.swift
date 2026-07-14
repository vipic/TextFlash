import Foundation
import Testing
@testable import TextFlash

@Suite struct AppVersionInfoTests {
    @Test func displayCurrentFallsBackToBundleWhenGeneratedIsPlaceholder() {
        #expect(AppVersion.displayCurrent(generated: "0.0.0-dev", bundle: "0.1.12") == "0.1.12")
    }

    @Test func displayCurrentPrefersBundleVersion() {
        #expect(AppVersion.displayCurrent(generated: "v0.2.0", bundle: "0.1.12") == "0.1.12")
    }

    @Test func displayCurrentUsesGeneratedReleaseVersionWhenBundleMissing() {
        #expect(AppVersion.displayCurrent(generated: "v0.2.0", bundle: nil) == "0.2.0")
    }

    @Test func displayBuildFallsBackToBundleWhenGeneratedIsPlaceholder() {
        #expect(AppVersion.displayBuild(generated: "0", bundle: "abc1234") == "abc1234")
    }

    @Test func displayBuildPrefersGeneratedReleaseBuild() {
        #expect(AppVersion.displayBuild(generated: "42", bundle: "abc1234") == "42")
    }
}
