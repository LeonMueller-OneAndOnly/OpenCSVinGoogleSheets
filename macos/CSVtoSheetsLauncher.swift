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
            contentRect: NSRect(x: 0, y: 0, width: 408, height: 194),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "CSVtoSheets"
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
        icon.contentTintColor = .systemBlue
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let title = NSTextField(labelWithString: "Google Sheet wird erstellt")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let fileList = filenames.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        let detail = NSTextField(wrappingLabelWithString: fileList)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.maximumNumberOfLines = 1

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let status = NSTextField(labelWithString: "Upload in Google Drive \u{00b7} Ordner Sheets")
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.textColor = .secondaryLabelColor

        let copy = NSStackView(views: [title, detail])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4

        let heading = NSStackView(views: [icon, copy])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 14

        let activity = NSStackView(views: [spinner, status])
        activity.orientation = .horizontal
        activity.alignment = .centerY
        activity.spacing = 8

        let stack = NSStackView(views: [heading, activity])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
        ])
        window.contentView = visualEffect
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
