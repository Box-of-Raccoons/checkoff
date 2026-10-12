import Foundation

extension TodoDocument {
    private enum Location {
        case top(Int)
        case child(parent: Int, index: Int)
    }

    private func location(of id: UUID) -> Location? {
        for (index, item) in items.enumerated() {
            if item.id == id { return .top(index) }
            if let child = item.children.firstIndex(where: { $0.id == id }) {
                return .child(parent: index, index: child)
            }
        }
        return nil
    }

    public func item(_ id: UUID) -> TodoItem? {
        switch location(of: id) {
        case .top(let index): return items[index]
        case .child(let parent, let index): return items[parent].children[index]
        case nil: return nil
        }
    }

    /// The parent's id when `id` is a sub-task; nil for a top-level task or an unknown id.
    public func parentID(of id: UUID) -> UUID? {
        if case .child(let parent, _) = location(of: id) { return items[parent].id }
        return nil
    }

    private mutating func update(_ id: UUID, _ change: (inout TodoItem) -> Void) -> Bool {
        switch location(of: id) {
        case .top(let index): change(&items[index])
        case .child(let parent, let index): change(&items[parent].children[index])
        case nil: return false
        }
        return true
    }

    /// Adds a task at the end of the list, or at the end of `parentID`'s sub-tasks.
    /// Returns nil for a blank title, or a parent that is missing or is itself a sub-task.
    @discardableResult
    public mutating func add(title: String, toParent parentID: UUID? = nil) -> UUID? {
        guard let parts = TodoMarkdown.splitTitle(title) else { return nil }
        let item = TodoItem(title: parts.title, due: parts.due)
        if let parentID {
            guard case .top(let index) = location(of: parentID) else { return nil }
            items[index].children.append(item)
        } else {
            items.append(item)
        }
        return item.id
    }

    /// Checks or unchecks one task. A parent's sub-tasks are left as they are.
    @discardableResult
    public mutating func setDone(_ id: UUID, _ done: Bool) -> Bool {
        update(id) { $0.isDone = done }
    }

    /// Renames a task. A `@due(...)` tag typed in the title sets the due date;
    /// a title without one keeps the date it had.
    @discardableResult
    public mutating func setTitle(_ id: UUID, _ title: String) -> Bool {
        guard let parts = TodoMarkdown.splitTitle(title) else { return false }
        return update(id) { item in
            item.title = parts.title
            if let due = parts.due { item.due = due }
        }
    }

    @discardableResult
    public mutating func setDue(_ id: UUID, _ due: DateOnly?) -> Bool {
        update(id) { $0.due = due }
    }

    /// Deletes a task. Deleting a parent deletes its sub-tasks too.
    @discardableResult
    public mutating func delete(_ id: UUID) -> Bool {
        switch location(of: id) {
        case .top(let index): items.remove(at: index)
        case .child(let parent, let index): items[parent].children.remove(at: index)
        case nil: return false
        }
        return true
    }

    public func openChildCount(of id: UUID) -> Int {
        item(id)?.children.filter { !$0.isDone }.count ?? 0
    }

    /// Done and total sub-task counts; nil when the task has no sub-tasks.
    public func progress(of id: UUID) -> (done: Int, total: Int)? {
        guard let children = item(id)?.children, !children.isEmpty else { return nil }
        return (children.filter(\.isDone).count, children.count)
    }

    /// Whether `action` is a legal place to drop task `id`.
    /// Nesting is one level deep, so a task that has sub-tasks can only sit at the top level.
    public func canApply(_ action: DropAction, to id: UUID) -> Bool {
        guard let moving = item(id) else { return false }
        switch action {
        case .end:
            return true
        case .into(let target):
            guard target != id, case .top = location(of: target) else { return false }
            return moving.children.isEmpty
        case .before(let target), .after(let target):
            guard target != id else { return false }
            switch location(of: target) {
            case .top: return true
            case .child: return moving.children.isEmpty
            case nil: return false
            }
        }
    }

    /// Moves task `id` to where `action` says. Returns false, changing nothing, if that is not allowed.
    @discardableResult
    public mutating func apply(_ action: DropAction, to id: UUID) -> Bool {
        guard canApply(action, to: id), let moving = item(id) else { return false }
        delete(id)

        switch action {
        case .end:
            items.append(moving)
        case .into(let target):
            guard case .top(let index) = location(of: target) else { return false }
            items[index].children.append(moving)
        case .before(let target), .after(let target):
            let offset = action == .after(target) ? 1 : 0
            switch location(of: target) {
            case .top(let index): items.insert(moving, at: index + offset)
            case .child(let parent, let index): items[parent].children.insert(moving, at: index + offset)
            case nil: return false
            }
        }
        return true
    }

    /// Gives tasks the ids they had in `old`, matched by title and parent in file order,
    /// so a task is still the same task after the file is read again.
    public mutating func adoptIDs(from old: TodoDocument) {
        var known: [String: [UUID]] = [:]
        for item in old.items {
            known[item.title, default: []].append(item.id)
            for child in item.children {
                known[Self.childKey(item.title, child.title), default: []].append(child.id)
            }
        }
        func take(_ key: String) -> UUID? {
            guard let first = known[key]?.first else { return nil }
            known[key]?.removeFirst()
            return first
        }
        for index in items.indices {
            let parentTitle = items[index].title
            if let id = take(parentTitle) { items[index].id = id }
            for child in items[index].children.indices {
                if let id = take(Self.childKey(parentTitle, items[index].children[child].title)) {
                    items[index].children[child].id = id
                }
            }
        }
    }

    private static func childKey(_ parent: String, _ child: String) -> String {
        "\(parent)\u{0}\(child)"
    }
}

/// Turns "dragged this row onto that row, this far down it" into a drop action.
public enum DropResolver {
    /// - Parameters:
    ///   - fraction: how far down the target row the pointer is, 0 at the top and 1 at the bottom.
    ///   - targetShowsChildren: the target is a parent with its sub-tasks showing under it.
    /// - Returns: nil when the drop should do nothing.
    public static func resolve(
        dragged: UUID, target: UUID, fraction: Double, targetShowsChildren: Bool, in document: TodoDocument
    ) -> DropAction? {
        guard dragged != target, document.item(target) != nil else { return nil }
        let targetIsChild = document.parentID(of: target) != nil

        let action: DropAction
        if !targetIsChild, document.canApply(.into(target), to: dragged) {
            // Top third reorders above, bottom third below, the middle nests.
            // Under an open parent the sub-tasks start right below, so the bottom nests too.
            if fraction < 1.0 / 3 {
                action = .before(target)
            } else if fraction > 2.0 / 3, !targetShowsChildren {
                action = .after(target)
            } else {
                action = .into(target)
            }
        } else {
            action = fraction < 0.5 ? .before(target) : .after(target)
        }
        return document.canApply(action, to: dragged) ? action : nil
    }
}
