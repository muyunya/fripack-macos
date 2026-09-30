import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var runner = Runner()
    @State private var script = ""
    @State private var target = BundleLayout.demoTarget
    @State private var hardeningNote: String?

    var body: some View {
        VSplitView {
            controls
                .frame(minHeight: 260)

            logPane
                .frame(minHeight: 200)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear(perform: loadDefaults)
    }

    // MARK: - Top half

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Script").font(.headline)
                Spacer()
                Button("Open…", action: openScript)
                Button("Reset to sample", action: loadSampleScript)
            }

            TextEditor(text: $script)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 130)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))

            HStack(spacing: 8) {
                Text("Target").font(.headline)
                Text(target.path)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…", action: chooseTarget)
                Button("Demo program", action: useDemoTarget)
            }

            if let hardeningNote {
                Label(hardeningNote, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button(action: run) {
                    Label("Build and run", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(runner.isRunning)

                Button(action: runner.stop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!runner.isRunning)

                Spacer()

                Text(runner.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    // MARK: - Bottom half

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output").font(.headline)
                Spacer()
                Button("Clear", action: runner.clear)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(runner.log.isEmpty ? "Nothing yet — press Build and run." : runner.log)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .id("tail")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
                .onChange(of: runner.log) { _ in
                    proxy.scrollTo("tail", anchor: .bottom)
                }
            }
        }
        .padding(14)
    }

    // MARK: - Actions

    private func loadDefaults() {
        loadSampleScript()
        inspectTarget()
    }

    private func loadSampleScript() {
        script = (try? String(contentsOf: BundleLayout.sampleScript, encoding: .utf8))
            ?? "console.log(\"the sample script is missing from the bundle\");"
    }

    private func openScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.javaScript, .plainText]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            script = (try? String(contentsOf: url, encoding: .utf8)) ?? script
        }
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose an executable, or a .app bundle, to inject into."
        if panel.runModal() == .OK, let url = panel.url {
            target = url
            inspectTarget()
        }
    }

    private func useDemoTarget() {
        target = BundleLayout.demoTarget
        inspectTarget()
    }

    private func run() {
        runner.start(script: script, target: target)
    }

    /// Injection here goes through DYLD_INSERT_LIBRARIES, which the dynamic linker
    /// ignores for hardened processes. Saying so up front beats a silent no-op.
    private func inspectTarget() {
        hardeningNote = nil
        guard FileManager.default.isExecutableFile(atPath: target.path) else { return }
        let result = try? shell("/usr/bin/codesign", ["-dv", target.path])
        if let result, result.contains("runtime") {
            hardeningNote = "This target has the hardened runtime enabled, so it will not load the payload. System apps cannot be injected into."
        }
    }

    private func shell(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
