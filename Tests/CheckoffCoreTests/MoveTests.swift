import Foundation
import Testing
@testable import CheckoffCore

@Suite struct MoveTests {
    @Test func reordersTopLevelTasks() {
        let f = Fixture()
        #expect(f.apply(.before(f.milk), to: f.bread))
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3] Bread Milk")
        #expect(f.apply(.after(f.bread), to: f.ticket))
        #expect(f.shape == "Bread Ticket[Step 1,Step 2,Step 3] Milk")
    }

    @Test func aParentMovesWithItsSubTasks() {
        let f = Fixture()
        #expect(f.apply(.end, to: f.ticket))
        #expect(f.shape == "Milk Bread Ticket[Step 1,Step 2,Step 3]")
        #expect(f.doc.items[2].children.map(\.isDone) == [true, false, false])
    }

    @Test func droppingIntoATaskMakesItTheLastSubTask() {
        let f = Fixture()
        #expect(f.apply(.into(f.ticket), to: f.milk))
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3,Milk] Bread")
        #expect(f.doc.parentID(of: f.milk) == f.ticket)
    }

    @Test func droppingIntoAChildlessTaskMakesItAParent() {
        let f = Fixture()
        #expect(f.apply(.into(f.milk), to: f.bread))
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3] Milk[Bread]")
    }

    @Test func reordersSubTasksWithinTheirParent() {
        let f = Fixture()
        #expect(f.apply(.before(f.step1), to: f.step3))
        #expect(f.shape == "Ticket[Step 3,Step 1,Step 2] Milk Bread")
        #expect(f.apply(.after(f.step2), to: f.step3))
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3] Milk Bread")
    }

    @Test func aTopLevelTaskCanLandBetweenSubTasks() {
        let f = Fixture()
        #expect(f.apply(.after(f.step1), to: f.milk))
        #expect(f.shape == "Ticket[Step 1,Milk,Step 2,Step 3] Bread")
    }

    @Test func aSubTaskMovesToAnotherParent() {
        let f = Fixture()
        f.apply(.into(f.milk), to: f.bread)
        #expect(f.apply(.into(f.milk), to: f.step2))
        #expect(f.shape == "Ticket[Step 1,Step 3] Milk[Bread,Step 2]")
        #expect(f.apply(.before(f.bread), to: f.step3))
        #expect(f.shape == "Ticket[Step 1] Milk[Step 3,Bread,Step 2]")
    }

    @Test func aSubTaskCanBePromotedToTopLevel() {
        let f = Fixture()
        #expect(f.apply(.before(f.milk), to: f.step2))
        #expect(f.shape == "Ticket[Step 1,Step 3] Step 2 Milk Bread")
        #expect(f.doc.parentID(of: f.step2) == nil)
        #expect(f.apply(.end, to: f.step3))
        #expect(f.shape == "Ticket[Step 1] Step 2 Milk Bread Step 3")
        #expect(f.apply(.before(f.ticket), to: f.step1))
        #expect(f.shape == "Step 1 Ticket Step 2 Milk Bread Step 3")
    }

    @Test func movingKeepsDoneStateAndDueDate() throws {
        let f = Fixture()
        f.setDue(f.step1, try day("2026-10-15"))
        #expect(f.apply(.end, to: f.step1))
        #expect(f.doc.item(f.step1)?.isDone == true)
        #expect(try f.doc.item(f.step1)?.due == day("2026-10-15"))
    }

    @Test func aTaskWithSubTasksCannotBecomeASubTask() {
        let f = Fixture()
        f.apply(.into(f.milk), to: f.bread)
        let before = f.doc
        #expect(!f.doc.canApply(.into(f.milk), to: f.ticket))
        #expect(!f.apply(.into(f.milk), to: f.ticket))
        #expect(!f.apply(.before(f.bread), to: f.ticket))
        #expect(!f.apply(.after(f.bread), to: f.ticket))
        #expect(f.doc == before)
    }

    @Test func aTaskCannotBeDroppedOnItselfOrItsOwnSubTasks() {
        let f = Fixture()
        let before = f.doc
        #expect(!f.apply(.into(f.ticket), to: f.ticket))
        #expect(!f.apply(.before(f.milk), to: f.milk))
        #expect(!f.apply(.after(f.milk), to: f.milk))
        #expect(!f.apply(.before(f.step1), to: f.ticket))
        #expect(!f.apply(.into(f.milk), to: f.milk))
        #expect(f.doc == before)
    }

    @Test func aSubTaskCannotBeDroppedIntoASubTask() {
        let f = Fixture()
        let before = f.doc
        #expect(!f.apply(.into(f.step1), to: f.milk))
        #expect(!f.apply(.into(f.step1), to: f.step2))
        #expect(f.doc == before)
    }

    @Test func movesInvolvingSomethingThatIsNotThereFail() {
        let f = Fixture()
        let before = f.doc
        #expect(!f.apply(.end, to: UUID()))
        #expect(!f.apply(.before(UUID()), to: f.milk))
        #expect(!f.apply(.after(UUID()), to: f.milk))
        #expect(!f.apply(.into(UUID()), to: f.milk))
        #expect(f.doc == before)
    }

    @Test func canApplyAgreesWithApplyOnAllowedMoves() {
        let f = Fixture()
        #expect(f.doc.canApply(.into(f.ticket), to: f.milk))
        #expect(f.doc.canApply(.before(f.step1), to: f.milk))
        #expect(f.doc.canApply(.end, to: f.step2))
        #expect(f.doc.canApply(.after(f.milk), to: f.ticket))
    }
}

@Suite struct DropResolverTests {
    func resolve(_ f: Fixture, _ dragged: UUID, onto target: UUID, at fraction: Double, open: Bool = false)
        -> DropAction?
    {
        DropResolver.resolve(
            dragged: dragged, target: target, fraction: fraction, targetShowsChildren: open, in: f.doc)
    }

    @Test func aTopLevelRowSplitsIntoThirds() {
        let f = Fixture()
        #expect(resolve(f, f.bread, onto: f.milk, at: 0.1) == .before(f.milk))
        #expect(resolve(f, f.bread, onto: f.milk, at: 0.5) == .into(f.milk))
        #expect(resolve(f, f.bread, onto: f.milk, at: 0.9) == .after(f.milk))
    }

    @Test func theBottomOfAnOpenParentMeansInsideIt() {
        let f = Fixture()
        #expect(resolve(f, f.milk, onto: f.ticket, at: 0.9, open: true) == .into(f.ticket))
        #expect(resolve(f, f.milk, onto: f.ticket, at: 0.9, open: false) == .after(f.ticket))
        #expect(resolve(f, f.milk, onto: f.ticket, at: 0.1, open: true) == .before(f.ticket))
    }

    @Test func aSubTaskRowSplitsInHalf() {
        let f = Fixture()
        #expect(resolve(f, f.milk, onto: f.step2, at: 0.2) == .before(f.step2))
        #expect(resolve(f, f.milk, onto: f.step2, at: 0.8) == .after(f.step2))
        #expect(resolve(f, f.step3, onto: f.step1, at: 0.2) == .before(f.step1))
    }

    @Test func aTaskWithSubTasksOnlyEverReorders() {
        let f = Fixture()
        #expect(resolve(f, f.ticket, onto: f.milk, at: 0.2) == .before(f.milk))
        #expect(resolve(f, f.ticket, onto: f.milk, at: 0.5) == .after(f.milk))
        #expect(resolve(f, f.ticket, onto: f.milk, at: 0.9) == .after(f.milk))
        #expect(resolve(f, f.ticket, onto: f.step2, at: 0.5) == nil)
    }

    @Test func droppingOnItselfDoesNothing() {
        let f = Fixture()
        #expect(resolve(f, f.milk, onto: f.milk, at: 0.5) == nil)
        #expect(resolve(f, f.step1, onto: f.step1, at: 0.2) == nil)
    }

    @Test func unknownRowsDoNothing() {
        let f = Fixture()
        #expect(resolve(f, UUID(), onto: f.milk, at: 0.5) == nil)
        #expect(resolve(f, f.milk, onto: UUID(), at: 0.5) == nil)
    }
}
