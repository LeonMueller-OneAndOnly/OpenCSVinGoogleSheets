import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("CSVtoSheets-launcher.log")

    func applicationWillFinishLaunching(_ notification: Notification) {
        log("application will finish launching")
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        log("openFiles: \(filenames.joined(separator: ", "))")
        guard !filenames.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        sender.reply(toOpenOrPrint: startCore(with: filenames) ? .success : .failure)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        log("openFile: \(filename)")
        return startCore(with: [filename])
    }

    private func startCore(with filenames: [String]) -> Bool {
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/CSVtoSheets-core")
        let process = Process()
        process.executableURL = executable
        process.arguments = filenames

        do {
            try process.run()
            log("started Go core")
            DispatchQueue.global().async {
                process.waitUntilExit()
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
			return true
        } catch {
            log("failed to start Go core: \(error.localizedDescription)")
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
			return false
        }
    }

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: logURL)
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
