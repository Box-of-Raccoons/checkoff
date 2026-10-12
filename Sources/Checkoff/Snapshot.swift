import AppKit
import CheckoffCore
import SwiftUI

/// Dev-only: draws the window's content with sample tasks to a PNG.
/// The sample lives in a temporary folder; the real tasks file is never read or written.
@MainActor
enum Snapshot {
    static func run(to path: String, dark: Bool) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkoff-snapshot-\(UUID().uuidString)")
        let file = folder.appendingPathComponent("tasks.md")
        let today = DateOnly(Date())
        func offset(_ days: Int) -> DateOnly {
            DateOnly(Calendar.current.date(byAdding: .day, value: days, to: today.date()) ?? Date())
        }
        let sample = """
            - [ ] GG-212 Fix the login redirect @due(\(offset(3)))
              - [x] Reproduce it on staging
              - [ ] Write the failing test @due(\(today))
              - [ ] Fix and open the PR
            - [ ] Renew the car registration @due(\(offset(-1)))
            - [ ] Book the dentist
            - [x] Order printer paper
            - [ ] Plan the birthday party @due(\(offset(40)))
              - [ ] Pick a date

            """
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try sample.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        let size = NSSize(width: 440, height: 420)
        let model = AppModel(fileURL: file, watch: false)
        let host = NSHostingView(rootView: ContentView()
            .environmentObject(model)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))  // the window itself is not captured
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))  // off every screen
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = bitmap.representation(using: .png, properties: [:])
        try? png?.write(to: URL(fileURLWithPath: path))
        try? FileManager.default.removeItem(at: folder)
        exit(png == nil ? 1 : 0)
    }
}
