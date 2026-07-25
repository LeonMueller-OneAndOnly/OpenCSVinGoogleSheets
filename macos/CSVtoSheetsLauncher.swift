import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard !filenames.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        sender.reply(toOpenOrPrint: startCore(with: filenames) ? .success : .failure)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        startCore(with: [filename])
    }

    private func startCore(with filenames: [String]) -> Bool {
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/CSVtoSheets-core")
        let process = Process()
        process.executableURL = executable
        process.arguments = filenames

        do {
            try process.run()
            DispatchQueue.global().async {
                process.waitUntilExit()
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
			return true
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
			return false
        }
    }
}
