import Foundation
import Testing

@Suite struct SigningConfigurationTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(of relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func scriptsDefaultToSharedAuthorSigningIdentity() throws {
        let deployScript = try contents(of: "deploy.sh")
        let releaseScript = try contents(of: "release.sh")

        #expect(deployScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        #expect(releaseScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
    }

    @Test func scriptsRejectAdhocSigningFallback() throws {
        let deployScript = try contents(of: "deploy.sh")
        let releaseScript = try contents(of: "release.sh")

        for script in [deployScript, releaseScript] {
            #expect(script.contains("不能使用 ad-hoc 签名"))
            #expect(!script.contains("回退 ad-hoc"))
            #expect(!script.contains("codesign --force --sign -"))
            #expect(!script.contains("codesign --force --deep --sign -"))
        }
    }

    @Test func documentsDescribeReusableAuthorCertificate() throws {
        let developmentGuide = try contents(of: "docs/DEVELOPMENT.md")
        let releaseGuide = try contents(of: "RELEASE.md")

        #expect(developmentGuide.contains("TextFlash 必须使用稳定代码签名"))
        #expect(developmentGuide.contains("不要使用 ad-hoc 签名"))
        #expect(developmentGuide.contains(#"export CODESIGN_IDENTITY="Your Certificate Name""#))
        #expect(releaseGuide.contains("多个应用可以共用同一张代码签名证书"))
        #expect(releaseGuide.contains("没有匹配证书或签名失败时脚本会直接停止"))
    }
}
