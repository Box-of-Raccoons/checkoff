import SwiftUI

@main
enum Main {
    @MainActor
    static func main() {
        // Dev-only: `--snapshot <path> [--dark]` draws the window with sample
        // tasks to a PNG and exits (a way to check the UI without Screen Recording).
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            Snapshot.run(to: arguments[index + 1], dark: arguments.contains("--dark"))
        }
        CheckoffApp.main()
    }
}

struct CheckoffApp: App {
    @StateObject private var model = AppModel(fileURL: TasksFile.resolveURL())
    @AppStorage("hideDone") private var hideDone = false

    var body: some Scene {
        Window("Checkoff", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 340, minHeight: 260)
        }
        .defaultSize(width: 440, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { model.focusAddField += 1 }
                    .keyboardShortcut("n")
                Divider()
                Button("Show Tasks File in Finder") { TasksFile.reveal(model.fileURL) }
                Button("Copy Tasks File Path") { TasksFile.copyPath(model.fileURL) }
            }
            CommandGroup(after: .toolbar) {
                Toggle("Hide Done Tasks", isOn: $hideDone)
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }
}
