import Testing
@testable import TextFlash

@Test func updateInstallScriptReadsRuntimeArguments() {
    let script = UpdateInstallScriptBuilder.script()

    #expect(script.contains("DMG=\"$1\""))
    #expect(script.contains("TARGET=\"$2\""))
    #expect(script.contains("EXPECTED_VERSION=\"$3\""))
    #expect(script.contains("CURRENT_PID=\"$4\""))
}

@Test func updateInstallScriptRejectsMismatchedSigningIdentity() {
    let script = UpdateInstallScriptBuilder.script()

    #expect(script.contains("更新包签名身份与当前 App 不匹配，拒绝自动更新"))
    #expect(!script.contains("继续安装；系统权限可能需要重新授权"))
}

@Test func updateInstallScriptPersistsUserVisibleFailureReason() {
    let script = UpdateInstallScriptBuilder.script()

    #expect(script.contains("ERROR_FILE=\"/tmp/textflash_update_error.txt\""))
    #expect(script.contains("fail_update()"))
    #expect(script.contains("printf \"%s\\n\" \"$1\" > \"$ERROR_FILE\""))
}
