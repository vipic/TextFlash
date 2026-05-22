import Testing
@testable import TextFlash

@Test func backupValidatorCreatesDefaultGroupForEmptyBackup() throws {
    let groups = try SnippetBackupValidator.normalizedGroups(from: SnippetBackup(groups: []))

    #expect(groups.count == 1)
    #expect(groups[0].name == "通用")
}

@Test func backupValidatorAcceptsValidGroups() throws {
    let groups = [
        SnippetGroup(
            name: "Work",
            snippets: [
                Snippet(abbreviation: "sig", expandedText: "Regards", description: "")
            ]
        )
    ]

    let normalized = try SnippetBackupValidator.normalizedGroups(from: SnippetBackup(groups: groups))

    #expect(normalized == groups)
}

@Test func backupValidatorRejectsEmptyGroupName() {
    let groups = [SnippetGroup(name: " ", snippets: [])]

    #expect(throws: SnippetImportExportError.self) {
        try SnippetBackupValidator.validate(groups)
    }
}

@Test func backupValidatorRejectsEmptyAbbreviation() {
    let groups = [
        SnippetGroup(
            name: "Work",
            snippets: [Snippet(abbreviation: " ", expandedText: "Text", description: "")]
        )
    ]

    #expect(throws: SnippetImportExportError.self) {
        try SnippetBackupValidator.validate(groups)
    }
}

@Test func backupValidatorRejectsEmptyExpansion() {
    let groups = [
        SnippetGroup(
            name: "Work",
            snippets: [Snippet(abbreviation: "sig", expandedText: " \n", description: "")]
        )
    ]

    #expect(throws: SnippetImportExportError.self) {
        try SnippetBackupValidator.validate(groups)
    }
}

@Test func backupValidatorRejectsDuplicateAbbreviations() {
    let groups = [
        SnippetGroup(
            name: "Work",
            snippets: [
                Snippet(abbreviation: "sig", expandedText: "One", description: ""),
                Snippet(abbreviation: "sig", expandedText: "Two", description: "")
            ]
        )
    ]

    #expect(throws: SnippetImportExportError.self) {
        try SnippetBackupValidator.validate(groups)
    }
}
