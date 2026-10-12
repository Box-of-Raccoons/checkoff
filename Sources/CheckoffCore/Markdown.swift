import Foundation

/// The task file format: a Markdown checklist.
///
///     - [ ] GG-12 Fix login @due(2026-10-15)
///       - [x] Reproduce it
///       - [ ] Write the test
///     - [ ] Buy milk
///
/// A task indented under another is its sub-task. Deeper indents flatten to one
/// level. Lines that are not tasks are kept and written back where they were.
public enum TodoMarkdown {
    public static func parse(_ text: String) -> TodoDocument {
        var lines = text.components(separatedBy: "\n").map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }
        if lines.last == "" { lines.removeLast() }

        var document = TodoDocument()
        var parentIndent = 0
        var lastWasChild = false

        for line in lines {
            if let task = parseTaskLine(line) {
                if !document.items.isEmpty, task.indent > parentIndent {
                    document.items[document.items.count - 1].children.append(task.item)
                    lastWasChild = true
                } else {
                    document.items.append(task.item)
                    parentIndent = task.indent
                    lastWasChild = false
                }
            } else if document.items.isEmpty {
                document.preamble.append(line)
            } else {
                let last = document.items.count - 1
                if lastWasChild {
                    let child = document.items[last].children.count - 1
                    document.items[last].children[child].extraLines.append(line)
                } else {
                    document.items[last].extraLines.append(line)
                }
            }
        }
        return document
    }

    public static func serialize(_ document: TodoDocument) -> String {
        var lines = document.preamble
        for item in document.items {
            lines.append(taskLine(item, indent: ""))
            lines.append(contentsOf: item.extraLines)
            for child in item.children {
                lines.append(taskLine(child, indent: "  "))
                lines.append(contentsOf: child.extraLines)
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// Tidies a typed title and pulls out a `@due(YYYY-MM-DD)` tag if it holds a real date.
    /// Returns nil when nothing is left to call a title.
    public static func splitTitle(_ raw: String) -> (title: String, due: DateOnly?)? {
        let collapsed = collapseWhitespace(raw)
        guard !collapsed.isEmpty else { return nil }

        if let open = collapsed.range(of: "@due(", options: .backwards) {
            let rest = collapsed[open.upperBound...]
            if rest.count >= 11, rest[rest.index(rest.startIndex, offsetBy: 10)] == ")",
               let due = DateOnly(String(rest.prefix(10)))
            {
                let close = rest.index(rest.startIndex, offsetBy: 11)
                let title = collapseWhitespace(collapsed[..<open.lowerBound] + " " + collapsed[close...])
                if !title.isEmpty { return (title, due) }
            }
        }
        return (collapsed, nil)
    }

    private static func parseTaskLine(_ line: String) -> (indent: Int, item: TodoItem)? {
        let body = line.drop { $0 == " " || $0 == "\t" }
        let indent = line.count - body.count

        let isDone: Bool
        let rest: Substring
        if let open = stripMarker(body, box: "[ ] ") {
            (isDone, rest) = (false, open)
        } else if let checked = stripMarker(body, box: "[x] ") ?? stripMarker(body, box: "[X] ") {
            (isDone, rest) = (true, checked)
        } else {
            return nil
        }
        guard let parts = splitTitle(String(rest)) else { return nil }
        return (indent, TodoItem(title: parts.title, isDone: isDone, due: parts.due))
    }

    private static func stripMarker(_ body: Substring, box: String) -> Substring? {
        for bullet in ["- ", "* ", "+ "] where body.hasPrefix(bullet + box) {
            return body.dropFirst(bullet.count + box.count)
        }
        return nil
    }

    private static func taskLine(_ item: TodoItem, indent: String) -> String {
        var line = "\(indent)- [\(item.isDone ? "x" : " ")] \(item.title)"
        if let due = item.due { line += " @due(\(due))" }
        return line
    }

    private static func collapseWhitespace<S: StringProtocol>(_ text: S) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
