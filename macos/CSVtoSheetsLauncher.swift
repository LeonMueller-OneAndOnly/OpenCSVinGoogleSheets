import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("CSVtoSheets-launcher.log")
    private var progressWindow: NSWindow?

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
            showProgress(for: filenames)
            DispatchQueue.global().async {
                process.waitUntilExit()
                DispatchQueue.main.async {
                    self.progressWindow?.close()
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

    private func showProgress(for filenames: [String]) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 174),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "CSVtoSheets"
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let title = NSTextField(labelWithString: "Google Sheet wird erstellt")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let fileList = filenames.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        let detail = NSTextField(wrappingLabelWithString: "Lade \(fileList) in den Google-Drive-Ordner Sheets hoch ...")
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let stack = NSStackView(views: [title, detail, spinner])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressWindow = window
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
