import SwiftUI

/// Entry point.
///
/// Besides the window, the same executable answers `--run-demo`, which walks the
/// exact code path the Run button walks and prints the result. It exists so the
/// pipeline can be checked without a human clicking, in CI or from a shell, rather
/// than by a second implementation that could drift from the button.
@main
struct FripackMain {
    static func main() {
        if CommandLine.arguments.contains("--run-demo") {
            HeadlessDemo.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--version") {
            print("Fripack \(BundleLayout.versionDescription)")
            exit(0)
        }
        FripackApp.main()
    }
}

struct FripackApp: App {
    var body: some Scene {
        WindowGroup("Fripack") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Nothing here creates documents, so the New Item entry is only noise.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
