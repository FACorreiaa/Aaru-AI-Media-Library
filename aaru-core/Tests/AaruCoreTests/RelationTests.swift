import Testing
@testable import AaruCore

struct RelationTests {
    @Test("Raw values match the server's core.Relation")
    func rawValues() {
        #expect(Relation.allCases.map(\.rawValue) == [
            "prequel", "sequel", "side_story", "spin_off", "adaptation",
            "source", "alternative", "summary", "parent", "other",
        ])
    }

    @Test("Each pair is written forward")
    func canonical() {
        #expect(Relation.prequel.canonical == (.sequel, true))
        #expect(Relation.source.canonical == (.adaptation, true))
        #expect(Relation.parent.canonical == (.sideStory, true))
        #expect(Relation.spinOff.canonical == (.spinOff, false))
        #expect(Relation.sequel.isMainChain)
        #expect(!Relation.adaptation.isMainChain)
    }
}
