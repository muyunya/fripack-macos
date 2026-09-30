import Foundation

/// Where the pieces live inside the bundle.
///
/// Everything the app needs is inside `Contents/Resources`, so the bundle can be
/// moved anywhere and still work; nothing is read from the checkout it was built in.
enum BundleLayout {
    static var resources: URL {
        Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
    }

    static var fripack: URL { resources.appendingPathComponent("bin/fripack") }
    static var payload: URL {
        resources.appendingPathComponent("payload/libchromatic-injectee-macos-arm64.dylib")
    }
    static var demoTarget: URL { resources.appendingPathComponent("demo/demo-target") }
    static var sampleScript: URL { resources.appendingPathComponent("samples/hook-demo.js") }

    static var versionDescription: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    /// Scratch space for the generated config, script and patched payload.
    static var workDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fripack/work", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

/// Runs a child process and hands its output to a callback as it arrives.
enum Shell {
    @discardableResult
    static func run(_ executable: URL,
                    arguments: [String],
                    workingDirectory: URL?,
                    environment: [String: String]? = nil,
                    onOutput: @escaping (String) -> Void,
                    completion: @escaping (Int32) -> Void) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        if let environment { process.environment = environment }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onOutput(text)
        }
        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            // Drain whatever the handler had not delivered yet.
            if let rest = try? pipe.fileHandleForReading.readToEnd(),
               let text = String(data: rest, encoding: .utf8), !text.isEmpty {
                onOutput(text)
            }
            completion(finished.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            onOutput("[app] cannot run \(executable.path): \(error.localizedDescription)\n")
            completion(-1)
        }
        return process
    }
}

/// The build-and-inject pipeline, shared by the Run button and the headless check.
final class Runner: ObservableObject {
    @Published private(set) var log = ""
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready"

    private var current: Process?
    private let queue = DispatchQueue(label: "com.muyunya.fripack.runner")

    private func emit(_ text: String) {
        DispatchQueue.main.async { self.log += text }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.status = text }
    }

    func clear() { DispatchQueue.main.async { self.log = "" } }

    func stop() {
        current?.terminate()
        setStatus("Stopped")
    }

    func start(script: String, target: URL, onFinish: (() -> Void)? = nil) {
        guard !isRunning else { return }
        isRunning = true
        DispatchQueue.main.async { self.log = "" }
        queue.async { [weak self] in
            self?.pipeline(script: script, target: target, onFinish: onFinish)
        }
    }

    // MARK: - Pipeline

    private func pipeline(script: String, target: URL, onFinish: (() -> Void)?) {
        let fm = FileManager.default
        let work = BundleLayout.workDirectory
        defer {
            DispatchQueue.main.async { self.isRunning = false }
            onFinish?()
        }

        for url in [BundleLayout.fripack, BundleLayout.payload, target] {
            guard fm.isExecutableFile(atPath: url.path) || url == target else {
                emit("[app] missing from the bundle: \(url.path)\n")
                setStatus("Bundle incomplete")
                return
            }
        }

        // 1. Write the script and a config that points fripack at our bundled payload.
        let scriptURL = work.appendingPathComponent("script.js")
        let configURL = work.appendingPathComponent("fripack.json")
        let outputDir = work.appendingPathComponent("out", isDirectory: true)
        try? fm.removeItem(at: outputDir)

        let config = """
        {
          "demo": {
            "type": "shared",
            "platform": "macos-arm64",
            "entry": "./script.js",
            "xz": false,
            "outputDir": "./out",
            "targetBaseName": "injected",
            "overridePrebuildFile": \(jsonString(BundleLayout.payload.path))
          }
        }

        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try config.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            emit("[app] cannot write the work files: \(error.localizedDescription)\n")
            setStatus("Write failed")
            return
        }

        // 2. Build the patched payload.
        setStatus("Building payload")
        emit("[app] fripack build demo\n")
        let built = DispatchSemaphore(value: 0)
        var buildStatus: Int32 = -1
        current = Shell.run(BundleLayout.fripack,
                            arguments: ["build", "demo"],
                            workingDirectory: work,
                            onOutput: { [weak self] text in self?.emit(text) },
                            completion: { code in
                                buildStatus = code
                                built.signal()
                            })
        built.wait()
        guard buildStatus == 0 else {
            emit("[app] fripack build failed (exit \(buildStatus))\n")
            setStatus("Build failed")
            return
        }

        let payload = outputDir.appendingPathComponent("injected-macos-arm64.dylib")
        guard fm.fileExists(atPath: payload.path) else {
            emit("[app] the build reported success but \(payload.path) is not there\n")
            setStatus("No payload produced")
            return
        }

        // 3. Launch the target with the payload preloaded.
        emit("\n[app] launching \(target.path)\n\n")
        setStatus("Running")

        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_INSERT_LIBRARIES"] = payload.path
        // The payload logs through the engine's console binding, which writes to
        // stdout; unbuffered keeps it interleaved with the target's own output.
        environment["NSUnbufferedIO"] = "YES"

        let finished = DispatchSemaphore(value: 0)
        var runStatus: Int32 = -1
        current = Shell.run(executable(url: target),
                            arguments: [],
                            workingDirectory: target.deletingLastPathComponent(),
                            environment: environment,
                            onOutput: { [weak self] text in self?.emit(text) },
                            completion: { code in
                                runStatus = code
                                finished.signal()
                            })
        finished.wait()

        emit("\n[app] the target exited with status \(runStatus)\n")
        setStatus(runStatus == 0 ? "Finished" : "Target exited with \(runStatus)")
    }

    /// A `.app` selection is a directory; the thing to launch is its executable.
    private func executable(url: URL) -> URL {
        guard url.pathExtension == "app" else { return url }
        let macos = url.appendingPathComponent("Contents/MacOS")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: macos.path)) ?? []
        if let name = entries.first(where: { $0 == url.deletingPathExtension().lastPathComponent }) {
            return macos.appendingPathComponent(name)
        }
        if let name = entries.first { return macos.appendingPathComponent(name) }
        return url
    }
}

private func jsonString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

/// `--run-demo`: the same pipeline the Run button uses, with no window.
enum HeadlessDemo {
    static func run() {
        let target = CommandLine.arguments
            .firstIndex(of: "--target")
            .flatMap { index -> URL? in
                let next = index + 1
                guard next < CommandLine.arguments.count else { return nil }
                return URL(fileURLWithPath: CommandLine.arguments[next])
            } ?? BundleLayout.demoTarget

        let script = (try? String(contentsOf: BundleLayout.sampleScript, encoding: .utf8))
            ?? "console.log(\"no sample script in the bundle\");"

        print("[app] fripack: \(BundleLayout.fripack.path)")
        print("[app] payload: \(BundleLayout.payload.path)")
        print("[app] target:  \(target.path)")

        let runner = Runner()
        var finished = false
        runner.start(script: script, target: target) { finished = true }

        // The Runner publishes on the main queue, and dispatch queues are only drained
        // while the main run loop runs. Blocking on a semaphore here would block the
        // very queue the output arrives on, and this mode would print nothing - a
        // verification that cannot fail is worse than none.
        var printed = 0
        let deadline = Date().addingTimeInterval(180)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            printed = flush(runner.log, from: printed)
        }
        printed = flush(runner.log, from: printed)
        print("[app] status: \(runner.status)")
    }

    /// Writes whatever the log has grown by since `printed`, and returns the new mark.
    private static func flush(_ log: String, from printed: Int) -> Int {
        guard log.count > printed else { return printed }
        let start = log.index(log.startIndex, offsetBy: printed)
        print(String(log[start...]), terminator: "")
        return log.count
    }
}
