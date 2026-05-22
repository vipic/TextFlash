import Testing
@testable import TextFlash

@Test func matcherFindsExactAbbreviation() {
    let matcher = SnippetMatcher()
    matcher.insert(abbreviation: "sig", expansion: "Regards")

    #expect(matcher.match(in: "sig") == SnippetMatch(abbreviation: "sig", expansion: "Regards"))
}

@Test func matcherFindsSuffixAfterUnrelatedInput() {
    let matcher = SnippetMatcher()
    matcher.insert(abbreviation: "addr", expansion: "123 Main")

    #expect(matcher.match(in: "helloaddr") == SnippetMatch(abbreviation: "addr", expansion: "123 Main"))
}

@Test func matcherWaitsOnPartialPrefix() {
    let matcher = SnippetMatcher()
    matcher.insert(abbreviation: "addr", expansion: "123 Main")

    #expect(matcher.match(in: "ad") == nil)
    #expect(matcher.trimToPossibleSuffix("xxad") == "ad")
}

@Test func matcherClearsImpossibleBuffer() {
    let matcher = SnippetMatcher()
    matcher.insert(abbreviation: "addr", expansion: "123 Main")

    #expect(matcher.match(in: "xyz") == nil)
    #expect(matcher.trimToPossibleSuffix("xyz") == "")
}

@Test func matcherRemovesAbbreviation() {
    let matcher = SnippetMatcher()
    matcher.insert(abbreviation: "sig", expansion: "Regards")
    matcher.remove(abbreviation: "sig")

    #expect(matcher.match(in: "sig") == nil)
}
