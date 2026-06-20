import Foundation
import Testing
@testable import TextFlash

@Test func backupValidatorDecodesWrappedBackup() throws {
    let groups = [
        SnippetGroup(
            name: "Work",
            snippets: [Snippet(abbreviation: "sig", expandedText: "Regards", description: "")]
        )
    ]
    let data = try JSONEncoder().encode(SnippetBackup(groups: groups))

    let decoded = try SnippetBackupValidator.decodeImportData(data)

    #expect(decoded == groups)
}

@Test func backupValidatorDecodesRawGroupArray() throws {
    let groups = [
        SnippetGroup(
            name: "Work",
            snippets: [Snippet(abbreviation: "addr", expandedText: "Office", description: "")]
        )
    ]
    let data = try JSONEncoder().encode(groups)

    let decoded = try SnippetBackupValidator.decodeImportData(data)

    #expect(decoded == groups)
}

@Test func backupValidatorDecodesSingleGroup() throws {
    let group = SnippetGroup(
        name: "Personal",
        snippets: [Snippet(abbreviation: "home", expandedText: "Home address", description: "")]
    )
    let data = try JSONEncoder().encode(group)

    let decoded = try SnippetBackupValidator.decodeImportData(data)

    #expect(decoded == [group])
}

@Test func backupValidatorRejectsUnknownJSONShape() {
    let data = Data(#"{"items":[]}"#.utf8)

    #expect(throws: SnippetImportExportError.self) {
        try SnippetBackupValidator.decodeImportData(data)
    }
}

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

@Test func backupValidatorNormalizesImportedWhitespace() throws {
    let group = SnippetGroup(
        name: " Work \n",
        snippets: [
            Snippet(abbreviation: " sig ", expandedText: " \nRegards", description: " note \n")
        ]
    )

    let normalized = try SnippetBackupValidator.normalize([group])

    #expect(normalized[0].name == "Work")
    #expect(normalized[0].snippets[0].abbreviation == "sig")
    #expect(normalized[0].snippets[0].expandedText == "Regards")
    #expect(normalized[0].snippets[0].description == "note")
}
