import Foundation
import Testing
@testable import CheckoffCore

@Suite struct MarkdownTests {
    @Test func readsAParentWithItsChildren() {
        let doc = TodoMarkdown.parse("""
            - [ ] GG-12 Fix login
              - [x] Reproduce it
              - [ ] Write the test
            - [ ] Buy milk

            """)
        #expect(doc.items.map(\.title) == ["GG-12 Fix login", "Buy milk"])
        #expect(doc.items.first?.children.map(\.title) == ["Reproduce it", "Write the test"])
        #expect(doc.items.first?.children.map(\.isDone) == [true, false])
        #expect(doc.items.first?.isDone == false)
        #expect(doc.items.last?.children.isEmpty == true)
    }

    @Test func readsDoneMarksInEitherCase() {
        let doc = TodoMarkdown.parse("- [x] one\n- [X] two\n- [ ] three\n")
        #expect(doc.items.map(\.isDone) == [true, true, false])
    }

    @Test func readsADueDateAndRemovesItFromTheTitle() throws {
        let doc = TodoMarkdown.parse("- [ ] Ship it @due(2026-10-15)\n  - [ ] Tag @due(2026-10-14)\n")
        #expect(doc.items.first?.title == "Ship it")
        #expect(try doc.items.first?.due == day("2026-10-15"))
        #expect(doc.items.first?.children.first?.title == "Tag")
        #expect(try doc.items.first?.children.first?.due == day("2026-10-14"))
    }

    @Test func aDueDateInTheMiddleOfATitleStillCounts() throws {
        let doc = TodoMarkdown.parse("- [ ] Ship @due(2026-10-15) the build\n")
        #expect(doc.items.first?.title == "Ship the build")
        #expect(try doc.items.first?.due == day("2026-10-15"))
    }

    @Test func aDueDateThatDoesNotExistStaysInTheTitle() {
        let doc = TodoMarkdown.parse("- [ ] Ship it @due(2026-02-30)\n- [ ] Later @due(soon)\n")
        #expect(doc.items.map(\.title) == ["Ship it @due(2026-02-30)", "Later @due(soon)"])
        #expect(doc.items.map(\.due) == [nil, nil])
    }

    @Test func taskWithNoDueDateHasNone() {
        #expect(TodoMarkdown.parse("- [ ] Plain\n").items.first?.due == nil)
    }

    @Test func deeperIndentsFlattenToOneLevel() {
        let doc = TodoMarkdown.parse("- [ ] Parent\n  - [ ] Child\n      - [ ] Grandchild\n\t- [ ] Tabbed\n")
        #expect(doc.items.count == 1)
        #expect(doc.items.first?.children.map(\.title) == ["Child", "Grandchild", "Tabbed"])
    }

    @Test func aWholeListThatIsIndentedKeepsItsShape() {
        let doc = TodoMarkdown.parse("  - [ ] A\n    - [ ] B\n  - [ ] C\n")
        #expect(doc.items.map(\.title) == ["A", "C"])
        #expect(doc.items.first?.children.map(\.title) == ["B"])
        #expect(doc.items.last?.children.isEmpty == true)
    }

    @Test func acceptsStarAndPlusBullets() {
        let doc = TodoMarkdown.parse("* [ ] star\n+ [x] plus\n")
        #expect(doc.items.map(\.title) == ["star", "plus"])
        #expect(doc.items.map(\.isDone) == [false, true])
    }

    @Test func acceptsWindowsLineEndings() {
        let doc = TodoMarkdown.parse("- [ ] one\r\n  - [x] two\r\n")
        #expect(doc.items.map(\.title) == ["one"])
        #expect(doc.items.first?.children.map(\.title) == ["two"])
    }

    @Test func keepsLinesBeforeTheFirstTask() {
        let doc = TodoMarkdown.parse("# Work\n\nSome notes.\n- [ ] one\n")
        #expect(doc.preamble == ["# Work", "", "Some notes."])
        #expect(doc.items.map(\.title) == ["one"])
    }

    @Test func keepsOtherLinesWithTheTaskTheyFollow() {
        let doc = TodoMarkdown.parse("- [ ] one\n  a note\n  - [ ] child\n    child note\n\n- [ ] two\n")
        #expect(doc.items.first?.extraLines == ["  a note"])
        #expect(doc.items.first?.children.first?.extraLines == ["    child note", ""])
        #expect(doc.items.last?.extraLines == [])
    }

    @Test func plainBulletsAndEmptyCheckboxesAreNotTasks() {
        let doc = TodoMarkdown.parse("- [ ] real\n- not a task\n- [ ] \n-[ ] no space\n")
        #expect(doc.items.map(\.title) == ["real"])
        #expect(doc.items.first?.extraLines == ["- not a task", "- [ ] ", "-[ ] no space"])
    }

    @Test func emptyTextIsAnEmptyDocument() {
        #expect(TodoMarkdown.parse("").items.isEmpty)
        #expect(TodoMarkdown.parse("").preamble.isEmpty)
        #expect(TodoMarkdown.serialize(TodoDocument()) == "")
    }

    @Test func writesTheCanonicalForm() throws {
        let doc = TodoDocument(items: [
            TodoItem(title: "GG-12 Fix login", due: try day("2026-10-15"), children: [
                TodoItem(title: "Reproduce it", isDone: true),
                TodoItem(title: "Write the test", due: try day("2026-10-14")),
            ]),
            TodoItem(title: "Buy milk", isDone: true),
        ])
        #expect(TodoMarkdown.serialize(doc) == """
            - [ ] GG-12 Fix login @due(2026-10-15)
              - [x] Reproduce it
              - [ ] Write the test @due(2026-10-14)
            - [x] Buy milk

            """)
    }

    @Test func aCanonicalFileSurvivesReadThenWriteUnchanged() {
        let text = """
            # Work

            - [ ] GG-12 Fix login @due(2026-10-15)
              see the ticket for the stack trace
              - [x] Reproduce it
              - [ ] Write the test
                use the staging account

            - [x] Buy milk

            """
        #expect(TodoMarkdown.serialize(TodoMarkdown.parse(text)) == text)
    }

    @Test func aMessyFileIsTidiedWithoutLosingTasks() {
        let text = "* [X] one\n\t\t- [ ] two   @due(2026-10-15)  \n"
        #expect(TodoMarkdown.serialize(TodoMarkdown.parse(text)) == "- [x] one\n  - [ ] two @due(2026-10-15)\n")
    }

    @Test func aFileWithoutAFinalNewlineStillReadsItsLastTask() {
        #expect(TodoMarkdown.parse("- [ ] one\n- [ ] two").items.map(\.title) == ["one", "two"])
    }
}
